#!/bin/bash

# Stop the test cluster safely.  A failed graceful stop must not be followed by
# deleting data directories or starting a new cluster on top of live processes.

cur_dir="$(cd "$(dirname "$0")" && pwd)"
conf_file="${cur_dir}/../conf/test.conf"
u_name=$(awk -F= '$1 == "u_name" {print $2}' "${conf_file}")
db_dir=$(awk -F= '$1 == "db_dir" {print $2}' "${conf_file}")

STOP_TIMEOUT=${STOP_TIMEOUT:-180}
KILL_WAIT_TIMEOUT=${KILL_WAIT_TIMEOUT:-60}
# Never let ssh consume the host list used by stop_list's read loop.
SSH_OPTS=(-n -o ConnectTimeout=10)

warn() {
  echo "WARN: $*" >&2
}

error() {
  echo "ERROR: $*" >&2
}

remote_pids() {
  local host=$1
  local kind=$2
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "jps_output=\$(sudo jps -l 2>/dev/null) || exit 1; printf '%s\\n' \"\$jps_output\" | awk '\$2 ~ /${kind}\$/ {print \$1}'" 2>/dev/null
}

pid_args() {
  printf '%s\n' "$1" | awk '$1 ~ /^[0-9]+$/ {printf "%s ", $1}'
}

kill_remote_pids() {
  local host=$1
  local pids=$2
  local args
  args=$(pid_args "${pids}")
  [[ -z "${args//[[:space:]]/}" ]] && return 0
  # args contains digits and spaces only, produced by pid_args above.
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" "sudo kill -9 ${args}" >/dev/null 2>&1
}

dump_remote_stacks() {
  local host=$1
  local kind=$2
  local pids=$3
  local round=$4
  local args
  args=$(pid_args "${pids}")
  [[ -z "${args//[[:space:]]/}" ]] && return 0

  # Keep dumps outside logs because clean_cluster.sh removes the logs directory.
  # Use the JDK paired with each running Java process.
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "sudo mkdir -p '${db_dir}/stop_diagnostics'; stamp=\$(date +%Y%m%d_%H%M%S); for pid in ${args}; do java_bin=\$(readlink -f /proc/\$pid/exe 2>/dev/null); jstack_bin=\$(dirname \"\$java_bin\")/jstack; dump_file='${db_dir}/stop_diagnostics/stop_timeout_${kind}_'\$pid'_round${round}_'\$stamp'.jstack'; if [ -x \"\$jstack_bin\" ]; then sudo \"\$jstack_bin\" \$pid 2>&1 | sudo tee \"\$dump_file\" >/dev/null; elif command -v jstack >/dev/null 2>&1; then sudo jstack \$pid 2>&1 | sudo tee \"\$dump_file\" >/dev/null; else echo 'jstack not found' | sudo tee \"\$dump_file\" >/dev/null; fi; done" \
    || echo "WARNING: jstack round ${round} failed on ${host}" >&2
}

stop_one() {
  local host=$1
  local kind=$2
  local stop_script=$3
  local pids
  local deadline
  local round

  echo "Stopping ${kind} on ${host}"
  if ! ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "source /etc/profile; sudo ${db_dir}/sbin/${stop_script}"; then
    warn "graceful stop command failed for ${kind} on ${host}; checking process state before escalation"
  fi

  deadline=$((SECONDS + STOP_TIMEOUT))
  while :; do
    if ! pids=$(remote_pids "${host}" "${kind}"); then
      error "cannot query ${kind} process state on ${host}"
      return 1
    fi
    if [[ -z "${pids//[[:space:]]/}" ]]; then
      return 0
    fi
    if (( SECONDS >= deadline )); then
      break
    fi
    sleep 2
  done

  warn "graceful stop timed out after ${STOP_TIMEOUT}s for ${kind} on ${host}; PID(s): ${pids}; collecting 3 jstack dumps at 10-second intervals before kill -9"
  for round in 1 2 3; do
    if ! pids=$(remote_pids "${host}" "${kind}"); then
      error "cannot query ${kind} process state on ${host} before jstack round ${round}"
      return 1
    fi
    if [[ -z "${pids//[[:space:]]/}" ]]; then
      return 0
    fi
    warn "capturing jstack ${round}/3 for ${kind} on ${host}; PID(s): ${pids}"
    dump_remote_stacks "${host}" "${kind}" "${pids}" "${round}"
    if (( round < 3 )); then
      sleep 10
    fi
  done

  if ! pids=$(remote_pids "${host}" "${kind}"); then
    error "cannot query ${kind} process state on ${host} before kill -9"
    return 1
  fi
  [[ -z "${pids//[[:space:]]/}" ]] && return 0

  warn "${kind} on ${host} did not stop after 3 jstack dumps; sending kill -9 to PID(s): ${pids}"
  if ! kill_remote_pids "${host}" "${pids}"; then
    error "failed to send kill -9 to ${kind} on ${host}; PID(s): ${pids}"
    return 1
  fi

  deadline=$((SECONDS + KILL_WAIT_TIMEOUT))
  while :; do
    if ! pids=$(remote_pids "${host}" "${kind}"); then
      error "cannot verify ${kind} termination on ${host} after kill -9"
      return 1
    fi
    if [[ -z "${pids//[[:space:]]/}" ]]; then
      echo "Stopped ${kind} on ${host} after kill -9"
      return 0
    fi
    if (( SECONDS >= deadline )); then
      error "${kind} still running on ${host} after kill -9 and ${KILL_WAIT_TIMEOUT}s; PID(s): ${pids}"
      return 1
    fi
    sleep 1
  done
}

stop_list() {
  local list_file=$1
  local kind=$2
  local stop_script=$3
  local host
  local failed=0

  while read -r host; do
    [[ -z "${host}" || "${host}" == \#* ]] && continue
    if ! stop_one "${host}" "${kind}" "${stop_script}"; then
      error "failed to stop ${kind} on ${host}; continuing with remaining nodes"
      failed=1
    fi
  done < "${list_file}"

  return "${failed}"
}

verify_stopped_list() {
  local list_file=$1
  local kind=$2
  local host
  local pids
  local failed=0

  while read -r host; do
    [[ -z "${host}" || "${host}" == \#* ]] && continue
    if ! pids=$(remote_pids "${host}" "${kind}"); then
      error "final verification could not query ${kind} on ${host}"
      failed=1
    elif [[ -n "${pids//[[:space:]]/}" ]]; then
      error "final verification found ${kind} still running on ${host}; PID(s): ${pids}"
      failed=1
    else
      echo "Verified ${kind} stopped on ${host}"
    fi
  done < "${list_file}"

  return "${failed}"
}

stop_cluster() {
  local failed=0

  # Stop DataNodes first, then ConfigNodes.  The second ConfigNode pass keeps
  # the original cleanup behavior for stale ConfigNodes on DataNode hosts.
  stop_list "${cur_dir}/../conf/datanode_5d.txt" DataNode stop-datanode.sh || failed=1
  stop_list "${cur_dir}/../conf/confignode_3c.txt" ConfigNode stop-confignode.sh || failed=1
  stop_list "${cur_dir}/../conf/datanode.txt" ConfigNode stop-confignode.sh || failed=1

  # Stop local benchmark helper processes, if any.
  jps 2>/dev/null | awk '$2 ~ /App$/ {print $1}' | while read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] && kill -9 "${pid}" 2>/dev/null || true
  done
  sleep 1

  # Do not let clean_cluster.sh remove files while any database process remains.
  verify_stopped_list "${cur_dir}/../conf/datanode_5d.txt" DataNode || failed=1
  verify_stopped_list "${cur_dir}/../conf/confignode_3c.txt" ConfigNode || failed=1
  verify_stopped_list "${cur_dir}/../conf/datanode.txt" ConfigNode || failed=1

  if (( failed != 0 )); then
    error "cluster stop is incomplete; do not clean data/logs or start a new cluster"
    return 1
  fi

  echo "All configured DataNodes and ConfigNodes are stopped"
}

stop_cluster

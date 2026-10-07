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

remote_pids() {
  local host=$1
  local kind=$2
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "sudo jps -l 2>/dev/null | awk '\$2 ~ /${kind}\$/ {print \$1}'" 2>/dev/null
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
    "mkdir -p '${db_dir}/stop_diagnostics'; stamp=\$(date +%Y%m%d_%H%M%S); for pid in ${args}; do java_bin=\$(readlink -f /proc/\$pid/exe 2>/dev/null); jstack_bin=\$(dirname \"\$java_bin\")/jstack; dump_file='${db_dir}/stop_diagnostics/stop_timeout_${kind}_'\$pid'_round${round}_'\$stamp'.jstack'; if [ -x \"\$jstack_bin\" ]; then \"\$jstack_bin\" \$pid > \"\$dump_file\" 2>&1; elif command -v jstack >/dev/null 2>&1; then jstack \$pid > \"\$dump_file\" 2>&1; else echo 'jstack not found' > \"\$dump_file\"; fi; done" \
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
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "source /etc/profile; sudo ${db_dir}/sbin/${stop_script}" || true

  deadline=$((SECONDS + STOP_TIMEOUT))
  while :; do
    if ! pids=$(remote_pids "${host}" "${kind}"); then
      echo "ERROR: cannot query ${kind} on ${host}" >&2
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

  echo "Graceful stop timed out after ${STOP_TIMEOUT}s; collecting 3 jstack dumps before killing ${kind} on ${host}: ${pids}" >&2
  for round in 1 2 3; do
    if ! pids=$(remote_pids "${host}" "${kind}"); then
      echo "ERROR: cannot query ${kind} on ${host} before jstack round ${round}" >&2
      return 1
    fi
    if [[ -z "${pids//[[:space:]]/}" ]]; then
      return 0
    fi
    dump_remote_stacks "${host}" "${kind}" "${pids}" "${round}"
    if (( round < 3 )); then
      sleep 10
    fi
  done

  if ! pids=$(remote_pids "${host}" "${kind}"); then
    echo "ERROR: cannot query ${kind} on ${host} before SIGKILL" >&2
    return 1
  fi
  [[ -z "${pids//[[:space:]]/}" ]] && return 0

  echo "Sending SIGKILL to ${kind} on ${host}: ${pids}" >&2
  if ! kill_remote_pids "${host}" "${pids}"; then
    echo "ERROR: failed to send SIGKILL to ${kind} on ${host}" >&2
    return 1
  fi

  deadline=$((SECONDS + KILL_WAIT_TIMEOUT))
  while :; do
    if ! pids=$(remote_pids "${host}" "${kind}"); then
      echo "ERROR: cannot verify ${kind} termination on ${host}" >&2
      return 1
    fi
    if [[ -z "${pids//[[:space:]]/}" ]]; then
      return 0
    fi
    if (( SECONDS >= deadline )); then
      echo "ERROR: ${kind} still running on ${host} after SIGKILL: ${pids}" >&2
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

  while read -r host; do
    [[ -z "${host}" || "${host}" == \#* ]] && continue
    stop_one "${host}" "${kind}" "${stop_script}" || return 1
  done < "${list_file}"
}

stop_cluster() {
  # Stop DataNodes first, then ConfigNodes.  The second ConfigNode pass keeps
  # the original cleanup behavior for stale ConfigNodes on DataNode hosts.
  stop_list "${cur_dir}/../conf/datanode_5d.txt" DataNode stop-datanode.sh || return 1
  stop_list "${cur_dir}/../conf/confignode_3c.txt" ConfigNode stop-confignode.sh || return 1
  stop_list "${cur_dir}/../conf/datanode.txt" ConfigNode stop-confignode.sh || return 1

  # Stop local benchmark helper processes, if any.
  jps 2>/dev/null | awk '$2 ~ /App$/ {print $1}' | while read -r pid; do
    [[ "${pid}" =~ ^[0-9]+$ ]] && kill -9 "${pid}" 2>/dev/null || true
  done
  sleep 1
}

stop_cluster

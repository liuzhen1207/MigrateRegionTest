#!/bin/bash

# Start the test cluster and fail fast when a ConfigNode cannot join.

cur_dir="$(cd "$(dirname "$0")" && pwd)"
conf_file="${cur_dir}/../conf/test.conf"
u_name=$(awk -F= '$1 == "u_name" {print $2}' "${conf_file}")
db_dir=$(awk -F= '$1 == "db_dir" {print $2}' "${conf_file}")
client_db_dir=$(awk -F= '$1 == "client_db_dir" {print $2}' "${conf_file}")
query_host=$(head -1 "${cur_dir}/../conf/datanode.txt")
v_start_time=$(date +%s)
cur_start_cluster_time=$1
total_node_num=$2

CN_START_TIMEOUT=${CN_START_TIMEOUT:-180}
CLUSTER_READY_TIMEOUT=${CLUSTER_READY_TIMEOUT:-300}
POLL_INTERVAL=${POLL_INTERVAL:-2}
# Do not let ssh consume the node list from the surrounding `while read` loops.
SSH_OPTS=(-n -o ConnectTimeout=10)

remote_cn_pids() {
  local host=$1
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "sudo jps -l 2>/dev/null | awk '\$2 ~ /ConfigNode\$/ {print \$1}'" 2>/dev/null
}

remote_cn_joined() {
  local host=$1
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "grep -i 'IoTDB-ConfigNode has successfully.*and joined the cluster' ${db_dir}/logs/*confignode*all* 2>/dev/null | wc -l" 2>/dev/null
}

remote_cn_start_error() {
  local host=$1
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "for f in ${db_dir}/logs/*confignode*error* ${db_dir}/logs/*confignode*all*; do [ -f \"\$f\" ] || continue; tail -n 200 \"\$f\"; done" 2>/dev/null \
    | grep -Eiq 'BindException|Address already in use|Failed to start|StartupException|Meet error while starting up'
}

print_cn_diagnostics() {
  local host=$1
  echo "--- ConfigNode diagnostics for ${host} ---" >&2
  ssh "${SSH_OPTS[@]}" "${u_name}@${host}" \
    "sudo jps -l; for f in ${db_dir}/logs/*confignode*error* ${db_dir}/logs/*confignode*all*; do [ -f \"\$f\" ] || continue; echo ====\"\$f\"====; tail -n 30 \"\$f\"; done" 2>&1 >&2 || true
}

wait_for_confignode() {
  local host=$1
  local start=$SECONDS
  local pids
  local joined

  while (( SECONDS - start < CN_START_TIMEOUT )); do
    if ! joined=$(remote_cn_joined "${host}"); then
      echo "ERROR: cannot query ConfigNode join status on ${host}" >&2
      return 1
    fi
    if [[ "${joined}" =~ ^[[:space:]]*${cur_start_cluster_time}[[:space:]]*$ ]]; then
      echo "ConfigNode ${host} joined the cluster"
      return 0
    fi

    if ! pids=$(remote_cn_pids "${host}"); then
      echo "ERROR: cannot query ConfigNode process on ${host}" >&2
      return 1
    fi
    if [[ -z "${pids//[[:space:]]/}" ]] && remote_cn_start_error "${host}"; then
      echo "ERROR: ConfigNode ${host} exited with a startup error" >&2
      print_cn_diagnostics "${host}"
      return 1
    fi
    sleep "${POLL_INTERVAL}"
  done

  echo "ERROR: ConfigNode ${host} did not join within ${CN_START_TIMEOUT}s" >&2
  print_cn_diagnostics "${host}"
  return 1
}

wait_for_cluster_ready() {
  local start=$SECONDS
  local v_running
  local v_readonly
  local v_ok_num

  while (( SECONDS - start < CLUSTER_READY_TIMEOUT )); do
    v_running=$(${client_db_dir}/sbin/start-cli.sh -h "${query_host}" -e "show cluster;" 2>/dev/null | grep -c Running || true)
    v_readonly=$(${client_db_dir}/sbin/start-cli.sh -h "${query_host}" -e "show cluster;" 2>/dev/null | grep -c ReadOnly || true)
    v_ok_num=$((v_running + v_readonly))
    if [[ "${total_node_num}" = "${v_ok_num}" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: cluster did not reach ${total_node_num} Running/ReadOnly nodes within ${CLUSTER_READY_TIMEOUT}s" >&2
  return 1
}

start_cluster() {
  local cur_start_count=$1
  local total_nodes=$2
  local c_node
  local d_node
  local v_alter_user_pw
  local v_succ
  local v_running

  while read -r c_node; do
    [[ -z "${c_node}" || "${c_node}" == \#* ]] && continue
    if ssh "${SSH_OPTS[@]}" "${u_name}@${c_node}" test -f "${db_dir}/activation/license"; then
      echo "license is exist."
    elif ssh "${SSH_OPTS[@]}" "${u_name}@${c_node}" test -f "${db_dir}/../timecho_license_new"; then
      ssh "${SSH_OPTS[@]}" "${u_name}@${c_node}" "cp -rp ${db_dir}/../timecho_license_new ${db_dir}/activation/license && cp -rp ${db_dir}/../.env ${db_dir}/"
    fi
    if ! ssh "${SSH_OPTS[@]}" "${u_name}@${c_node}" \
      "source /etc/profile; sudo ${db_dir}/sbin/start-confignode.sh -H ${db_dir}/cn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"; then
      echo "ERROR: failed to launch ConfigNode on ${c_node}" >&2
      return 1
    fi
    sleep 1
  done < "${cur_dir}/../conf/confignode.txt"

  while read -r c_node; do
    [[ -z "${c_node}" || "${c_node}" == \#* ]] && continue
    wait_for_confignode "${c_node}" || return 1
  done < "${cur_dir}/../conf/confignode.txt"

  while read -r d_node; do
    [[ -z "${d_node}" || "${d_node}" == \#* ]] && continue
    if ! ssh "${SSH_OPTS[@]}" "${u_name}@${d_node}" \
      "source /etc/profile; sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"; then
      echo "ERROR: failed to launch DataNode on ${d_node}" >&2
      return 1
    fi
    sleep 2
  done < "${cur_dir}/../conf/datanode.txt"

  while :; do
    v_alter_user_pw=$(${client_db_dir}/sbin/start-cli.sh -h "${query_host}" -u root -pw root -e "alter user root set password 'TimechoDB@2021'" 2>&1 || true)
    echo "${v_alter_user_pw}"
    v_succ=$(echo "${v_alter_user_pw}" | grep -c success || true)
    if (( v_succ > 0 )); then
      echo "alter user root pasword success."
      break
    fi
    sleep 1
    v_running=$(${client_db_dir}/sbin/start-cli.sh -h "${query_host}" -e "show cluster;" 2>/dev/null | grep -c Running || true)
    if (( v_running > 0 )); then
      break
    fi
  done

  wait_for_cluster_ready
}

start_cluster "${cur_start_cluster_time}" "${total_node_num}"

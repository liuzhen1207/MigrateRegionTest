#!/bin/bash
set -uo pipefail

cur_dir="$( cd "$( dirname "$0" )" && pwd )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
SCRIPT_NAME=$(basename "$0")

u_name=$(grep '^u_name=' "${conf_file}" | awk -F '=' '{print $2}')
db_dir=$(grep '^db_dir=' "${conf_file}" | awk -F '=' '{print $2}')
v_cur_db=$(grep '^v_cur_db=' "${conf_file}" | awk -F '=' '{print $2}')
cli_dir=$(grep '^client_db_dir=' "${conf_file}" | awk -F '=' '{print $2}')
testcase_res_db=$(grep '^testcase_res_db=' "${conf_file}" | awk -F '=' '{print $2}')
testcase_res_port=$(grep '^testcase_res_port=' "${conf_file}" | awk -F '=' '{print $2}')
bm_conn_pw=$(grep '^bm_conn_pw=' "${conf_file}" | awk -F '=' '{print $2}')
monitor_url=$(grep '^monitor_url=' "${conf_file}" | awk -F '=' '{print $2}')

clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
res_file="${cur_dir}/../test_result/res_${v_cur_db}.out"

db_sys_admin=root
res_root_pw=TimechoDB@2021
ssl_str=""
v_consensus="IoTConsensus"

cn_num=3
dn_num=4
head -n "${dn_num}" "${nodeinfo_dir}/total_datanode.txt" > "${nodeinfo_dir}/datanode.txt"
head -n "${dn_num}" "${nodeinfo_dir}/total_datanode_port.txt" > "${nodeinfo_dir}/datanode_port.txt"
total_node_num=$((cn_num + dn_num))

seed_cn_ip=$(head -1 "${nodeinfo_dir}/confignode.txt"):10710
query_ip=$(head -1 "${nodeinfo_dir}/datanode.txt")
expand_dn_ip=$(sed -n "$((dn_num + 1))p" "${nodeinfo_dir}/total_datanode.txt")
expand_dn_id=""

tc_num=$(echo "${SCRIPT_NAME}" | awk -F '_' '{print $1}' | awk -F 'tc' '{print $2}')
testcase_ip=$(grep '^test_ip=' "${conf_file}" | awk -F '.' '{print $4}')
test_begin_sec=$(date +%s)

run_timestamp=$(date +'%Y_%m_%d_%H_%M_%S')
run_artifact_dir="${cur_dir}/${SCRIPT_NAME%.*}_${run_timestamp}"
log_file="${run_artifact_dir}/run.log"

bm_dir="${cur_dir}/../benchmark/bm_20260519_writeview_v20"
bm_case_root="${bm_dir}/weather_6h_diff"
bm_work_root="${run_artifact_dir}/bm_work_${tc_num}_${test_begin_sec}"
bm_log_root="${bm_work_root}/logs"
benchmark_error_pattern="Execution fail:|Failed to do |StatementExecutionException|WorkloadException|There is not enough memory to execute current fragment instance|Connection error"

tree_workload="conf_tree"
table_base_workload="conf_tab1"
table_view_workload="conf_tab2"
workloads="${tree_workload} ${table_base_workload} ${table_view_workload}"
workload_count=3
table_safe_op_proportion="91:1:2:0:2:0:0:1:1:2:0:0:0"
tree_loop=1000

tree_db_name="test"
table_db_name="usr_sod0"
tree_db_path="root.test.g_0"
table_base_name=""
table_view_name=""
table_base_object_col=""
table_view_object_col=""
query_tree_sql="select count(s_0),count(s_1),count(s_2),count(s_3),count(s_4),count(s_5),count(s_6),count(s_7),count(s_8),count(s_9),count(s_10),count(s_11) from root.test.** align by device;"
query_table_base_sql=""
query_table_view_sql=""
query_table_base_object_sql=""
query_table_view_object_sql=""

pre_maintenance_wait_seconds="${1:-300}"

tree_migrate_region_id=""
tree_migrate_from_dn_id=""
table_migrate_region_id=""
table_migrate_from_dn_id=""
tree_extend_region_id=""
tree_extend_from_dn_id=""
table_extend_region_id=""
table_extend_from_dn_id=""

migrate_elapsed_seconds=0
migrate_tree_elapsed_seconds=0
migrate_table_elapsed_seconds=0
extend_elapsed_seconds=0
extend_tree_elapsed_seconds=0
extend_table_elapsed_seconds=0
remove_elapsed_seconds=0
remove_tree_elapsed_seconds=0
remove_table_elapsed_seconds=0

fail_flag=0
v_warnMessage=""

if ! [[ "${pre_maintenance_wait_seconds}" =~ ^[0-9]+$ ]] || [ "${pre_maintenance_wait_seconds}" -lt 0 ]; then
  echo "pre_maintenance_wait_seconds must be an integer and >= 0, current: ${pre_maintenance_wait_seconds}"
  exit 1
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${log_file}"
}

append_warn() {
  local msg=$1
  if [[ -z "${v_warnMessage}" ]]; then
    v_warnMessage="${msg}"
  else
    v_warnMessage="${v_warnMessage}; ${msg}"
  fi
}

snapshot_ts() {
  date +'%Y_%m_%d_%H_%M_%S_%N'
}

archive_snapshot() {
  local src_file=$1
  local archive_base=$2
  cp -f "${src_file}" "${run_artifact_dir}/${archive_base}_$(snapshot_ts).out" 2>/dev/null || true
}

append_migrations_trace() {
  local stage=$1
  local dialect=$2
  local src_file=$3
  local trace_file="${run_artifact_dir}/${stage}_show_migrations_trace.out"
  {
    echo "===== $(date +'%Y-%m-%d %H:%M:%S') stage=${stage} dialect=${dialect} ====="
    cat "${src_file}"
    echo
  } >> "${trace_file}"
}

set_config_value() {
  local config_file=$1
  local key=$2
  local value=$3

  if grep -q "^${key}=" "${config_file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|g" "${config_file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${config_file}"
  fi
}

prepare_table_benchmark_config() {
  local config_file=$1
  set_config_value "${config_file}" "OPERATION_PROPORTION" "${table_safe_op_proportion}"
}

prepare_tree_benchmark_config() {
  local config_file=$1
  set_config_value "${config_file}" "LOOP" "${tree_loop}"
}

benchmark_pid_running() {
  local workload=$1
  local pid_file="${bm_log_root}/${workload}.pid"
  local pid

  if [[ ! -f "${pid_file}" ]]; then
    return 1
  fi

  pid=$(tr -d '[:space:]' < "${pid_file}")
  if [[ -z "${pid}" ]]; then
    return 1
  fi

  ps -p "${pid}" >/dev/null 2>&1
}

parse_monitor_query_status() {
  local response_file=$1

  if command -v jq >/dev/null 2>&1; then
    jq -r '.status' "${response_file}" 2>/dev/null
    return $?
  fi

  awk '
    match($0, /"status"[[:space:]]*:[[:space:]]*"[^"]+"/) {
      status = substr($0, RSTART, RLENGTH)
      sub(/.*"status"[[:space:]]*:[[:space:]]*"/, "", status)
      sub(/".*/, "", status)
      print status
      found = 1
      exit 0
    }
    END { exit found ? 0 : 1 }
  ' "${response_file}"
}

count_non_zero_sync_lag() {
  local response_file=$1

  if command -v jq >/dev/null 2>&1; then
    jq -r '.data.result[] | .value[1]' "${response_file}" 2>/dev/null | awk '$1 > 0.0001 {c++} END {print c+0}'
    return $?
  fi

  awk '
    {
      line = $0
      while (match(line, /"value"[[:space:]]*:[[:space:]]*\[[^]]*\]/)) {
        item = substr(line, RSTART, RLENGTH)
        split(item, parts, ",")
        if (length(parts) >= 2) {
          value = parts[2]
          gsub(/[^0-9eE+.-]/, "", value)
          if (value + 0 > 0.0001) {
            count++
          }
        }
        line = substr(line, RSTART + RLENGTH)
      }
    }
    END { print count + 0 }
  ' "${response_file}"
}

trim_file_crlf() {
  local file=$1
  sed -i 's/\r$//' "${file}" 2>/dev/null || true
}

run_cli_sql() {
  local host=$1
  local dialect=$2
  local sql=$3
  local outfile=$4
  local timeout_sec=${5:-3600}

  if [[ "${dialect}" = "table" ]]; then
    "${cli_dir}/sbin/start-cli.sh" -u "${db_sys_admin}" ${ssl_str} -h "${host}" -sql_dialect table -timeout "${timeout_sec}" -e "${sql}" > "${outfile}" 2>&1
  else
    "${cli_dir}/sbin/start-cli.sh" -u "${db_sys_admin}" ${ssl_str} -h "${host}" -timeout "${timeout_sec}" -e "${sql}" > "${outfile}" 2>&1
  fi
}

check_cli_success() {
  local file=$1
  local desc=$2
  trim_file_crlf "${file}"
  if grep -Eq "Exception|ERROR|Error" "${file}"; then
    log "${desc} failed"
    cat "${file}" >> "${log_file}"
    append_warn "${desc} failed"
    let fail_flag++
    return 1
  fi
  return 0
}

set_sys_conf() {
  local v_ip=$1
  local v_db_dir=$2
  local search_str=$3
  local content=$4
  local remote_host="${u_name}@${v_ip}"
  local remote_file="${v_db_dir}/conf/iotdb-system.properties"
  local remote_grep="ssh ${remote_host} grep -q '${search_str}' '${remote_file}'"
  local remote_sed="ssh ${remote_host} \"sed -i 's|${search_str}|${content}|g' '${remote_file}'\""
  local remote_echo="ssh ${remote_host} 'echo \"${content}\" >> \"${remote_file}\"'"

  if eval "${remote_grep}"; then
    eval "${remote_sed}"
  else
    eval "${remote_echo}"
  fi
}

configure_one_confignode() {
  local line=$1
  ssh -n "${u_name}@${line}" "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/confignode-env.sh"
  ssh -n "${u_name}@${line}" "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
  set_sys_conf "${line}" "${db_dir}" ".*cn_seed_config_node=.*" "cn_seed_config_node=${seed_cn_ip}"
  set_sys_conf "${line}" "${db_dir}" ".*cn_internal_address=.*" "cn_internal_address=${line}"
  set_sys_conf "${line}" "${db_dir}" ".*cn_metric_reporter_list=.*" "cn_metric_reporter_list=PROMETHEUS"
  set_sys_conf "${line}" "${db_dir}" ".*schema_replication_factor=.*" "schema_replication_factor=3"
  set_sys_conf "${line}" "${db_dir}" ".*data_replication_factor=.*" "data_replication_factor=2"
}

configure_one_datanode() {
  local line=$1
  ssh -n "${u_name}@${line}" "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"20G\"/g' ${db_dir}/conf/datanode-env.sh"
  ssh -n "${u_name}@${line}" "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
  set_sys_conf "${line}" "${db_dir}" ".*dn_seed_config_node=.*" "dn_seed_config_node=${seed_cn_ip}"
  set_sys_conf "${line}" "${db_dir}" ".*dn_internal_address=.*" "dn_internal_address=${line}"
  set_sys_conf "${line}" "${db_dir}" ".*dn_rpc_address=.*" "dn_rpc_address=${line}"
  set_sys_conf "${line}" "${db_dir}" ".*dn_metric_reporter_list=.*" "dn_metric_reporter_list=PROMETHEUS"
  set_sys_conf "${line}" "${db_dir}" ".*schema_replication_factor=.*" "schema_replication_factor=3"
  set_sys_conf "${line}" "${db_dir}" ".*data_replication_factor=.*" "data_replication_factor=2"
}

clean_env() {
  sh -x "${clean_env_dir}/stop_cluster.sh" >> "${log_file}" 2>&1 || true
  sh -x "${clean_env_dir}/clean_cluster.sh" >> "${log_file}" 2>&1
  sh -x "${clean_env_dir}/reset_conf.sh" >> "${log_file}" 2>&1
}

set_conf() {
  exec 3<"${nodeinfo_dir}/confignode.txt"
  while read -r line <&3
  do
    [[ -z "${line}" ]] && continue
    configure_one_confignode "${line}"
  done
  exec 3<&-

  exec 4<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&4
  do
    [[ -z "${line}" ]] && continue
    configure_one_datanode "${line}"
  done
  exec 4<&-
}

start_db() {
  clean_env
  head -n "${cn_num}" "${nodeinfo_dir}/total_node.txt" > "${nodeinfo_dir}/confignode.txt"
  set_conf
  sh -x "${prepare_env_dir}/start_cluster_v20.sh" "1" "${total_node_num}" >> "${log_file}" 2>&1
}

create_benchmark_users() {
  run_cli_sql "${query_ip}" tree "CREATE USER santos '${bm_conn_pw}';" "${run_artifact_dir}/create_santos.out" 300
  run_cli_sql "${query_ip}" tree "GRANT READ_SCHEMA,WRITE_SCHEMA,READ_DATA,WRITE_DATA ON root.test.** TO USER santos;" "${run_artifact_dir}/grant_santos_tree.out" 300
  run_cli_sql "${query_ip}" table "GRANT ALL TO USER santos;" "${run_artifact_dir}/grant_santos.out" 300
  run_cli_sql "${query_ip}" tree "CREATE USER rainer '${bm_conn_pw}';" "${run_artifact_dir}/create_rainer.out" 300
  run_cli_sql "${query_ip}" tree "GRANT READ_SCHEMA,WRITE_SCHEMA,READ_DATA,WRITE_DATA ON root.test.** TO USER rainer;" "${run_artifact_dir}/grant_rainer_tree.out" 300
  run_cli_sql "${query_ip}" table "GRANT ALL TO USER rainer;" "${run_artifact_dir}/grant_rainer.out" 300
}

prepare_benchmark_workdirs() {
  local start_time_str
  local workload
  local config_file

  rm -rf "${bm_work_root}"
  mkdir -p "${bm_log_root}"
  start_time_str=$(date +"%Y-%m-%dT%H:%M:%S%:z")

  for workload in ${workloads}
  do
    cp -rp "${bm_case_root}/${workload}" "${bm_work_root}/${workload}"
    config_file="${bm_work_root}/${workload}/config.properties"

    if grep -q '^START_TIME=' "${config_file}"; then
      sed -i "s/^START_TIME=.*/START_TIME=${start_time_str}/g" "${config_file}"
    else
      printf '\nSTART_TIME=%s\n' "${start_time_str}" >> "${config_file}"
    fi
    if [[ "${workload}" = "${table_base_workload}" || "${workload}" = "${table_view_workload}" ]]; then
      prepare_table_benchmark_config "${config_file}"
    elif [[ "${workload}" = "${tree_workload}" ]]; then
      prepare_tree_benchmark_config "${config_file}"
    fi
  done
}

start_benchmarks() {
  local workload
  for workload in ${workloads}
  do
    nohup sh -x "${bm_dir}/benchmark.sh" -cf "${bm_work_root}/${workload}" > "${bm_log_root}/${workload}.out" 2>&1 &
    echo $! > "${bm_log_root}/${workload}.pid"
  done
}

wait_benchmark_objects_ready() {
  local timeout_sec=${1:-900}
  local start_time
  local tree_ok=0
  local table_ok=0
  local view_ok=0

  start_time=$(date +%s)
  while true
  do
    if [[ ${tree_ok} -eq 0 ]]; then
      run_cli_sql "${query_ip}" tree "show devices root.test.**;" "${run_artifact_dir}/show_tree_devices.out" 3600
      if [[ $(grep -c 'root.test.' "${run_artifact_dir}/show_tree_devices.out") -gt 0 ]]; then
        tree_ok=1
      fi
    fi

    if [[ ${table_ok} -eq 0 || ${view_ok} -eq 0 ]]; then
      run_cli_sql "${query_ip}" table "show tables details from ${table_db_name};" "${run_artifact_dir}/show_tables_details.out" 3600
      if [[ ${table_ok} -eq 0 ]] && grep -Eq 'BASE TABLE' "${run_artifact_dir}/show_tables_details.out"; then
        table_ok=1
      fi
      if [[ ${view_ok} -eq 0 ]] && grep -Eq 'WRITABLE VIEW' "${run_artifact_dir}/show_tables_details.out"; then
        view_ok=1
      fi
    fi

    if [[ ${tree_ok} -eq 1 && ${table_ok} -eq 1 && ${view_ok} -eq 1 ]]; then
      return 0
    fi

    if (( $(date +%s) - start_time > timeout_sec )); then
      return 1
    fi
    sleep 10
  done
}

resolve_table_objects() {
  run_cli_sql "${query_ip}" table "show tables details from ${table_db_name};" "${run_artifact_dir}/show_tables_details.out" 3600

  table_base_name=$(awk -F '|' '
    /BASE TABLE/ {
      name=$2
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      if (name != "TableName" && name != "") {
        print name
        exit
      }
    }
  ' "${run_artifact_dir}/show_tables_details.out")

  table_view_name=$(awk -F '|' '
    /WRITABLE VIEW/ {
      name=$2
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      if (name != "TableName" && name != "") {
        print name
        exit
      }
    }
  ' "${run_artifact_dir}/show_tables_details.out")

  if [[ -z "${table_base_name}" || -z "${table_view_name}" ]]; then
    log "failed to resolve table objects from show tables details"
    cat "${run_artifact_dir}/show_tables_details.out" >> "${log_file}"
    append_warn "show tables details from ${table_db_name} could not resolve base table or writable view"
    let fail_flag++
    return 1
  fi

  query_table_base_sql="select device_id,count(s_0),count(s_1),count(s_2),count(s_3),count(s_4),count(s_5),count(s_6),count(s_7),count(s_8),count(s_9),count(s_10),count(s_11) from ${table_db_name}.${table_base_name} group by device_id order by device_id;"
  query_table_view_sql="select device_id,count(s_0),count(s_1),count(s_2),count(s_3),count(s_4),count(s_5),count(s_6),count(s_7),count(s_8),count(s_9),count(s_10),count(s_11) from ${table_db_name}.${table_view_name} group by device_id order by device_id;"
  return 0
}

resolve_object_columns() {
  run_cli_sql "${query_ip}" table "describe ${table_db_name}.${table_base_name} details;" "${run_artifact_dir}/describe_table_base.out" 3600
  table_base_object_col=$(awk -F '|' '
    $0 ~ /OBJECT/ {
      name=$2
      type=$3
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      gsub(/^[ \t]+|[ \t]+$/, "", type)
      if (type == "OBJECT") {
        print name
        exit
      }
    }
  ' "${run_artifact_dir}/describe_table_base.out")

  run_cli_sql "${query_ip}" table "describe ${table_db_name}.${table_view_name} details;" "${run_artifact_dir}/describe_table_view.out" 3600
  table_view_object_col=$(awk -F '|' '
    $0 ~ /OBJECT/ {
      name=$2
      type=$3
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      gsub(/^[ \t]+|[ \t]+$/, "", type)
      if (type == "OBJECT") {
        print name
        exit
      }
    }
  ' "${run_artifact_dir}/describe_table_view.out")

  if [[ -z "${table_base_object_col}" || -z "${table_view_object_col}" ]]; then
    append_warn "failed to resolve OBJECT column from base table or writable view"
    let fail_flag++
    return 1
  fi

  query_table_base_object_sql="select D_DATETIME,device_id,length(read_object(${table_base_object_col})),sha256(cast(read_object(${table_base_object_col}) as string)) from ${table_db_name}.${table_base_name} order by D_DATETIME,device_id limit 20;"
  query_table_view_object_sql="select D_DATETIME,device_id,length(read_object(${table_view_object_col})),sha256(cast(read_object(${table_view_object_col}) as string)) from ${table_db_name}.${table_view_name} order by D_DATETIME,device_id limit 20;"
  return 0
}

refresh_running_datanodes() {
  local candidate_file="${run_artifact_dir}/refresh_query_candidates.txt"
  local dedup_candidate_file="${run_artifact_dir}/refresh_query_candidates_dedup.txt"
  : > "${candidate_file}"
  printf '%s\n' "${query_ip}" >> "${candidate_file}"
  cat "${nodeinfo_dir}/datanode.txt" >> "${candidate_file}"
  printf '%s\n' "${expand_dn_ip}" >> "${candidate_file}"
  awk '!seen[$0]++' "${candidate_file}" > "${dedup_candidate_file}"

  local query_host=""
  while read -r host; do
    host=$(echo "${host}" | sed 's/ //g')
    [[ -z "${host}" ]] && continue
    if "${cli_dir}/sbin/start-cli.sh" -u "${db_sys_admin}" ${ssl_str} -h "${host}" -e "show datanodes;" > "${run_artifact_dir}/show_datanodes.out" 2>/dev/null; then
      query_host="${host}"
      query_ip="${host}"
      break
    fi
  done < "${dedup_candidate_file}"

  if [[ -z "${query_host}" ]]; then
    return 1
  fi

  trim_file_crlf "${run_artifact_dir}/show_datanodes.out"
  awk -F '|' '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    /^\|/ {
      node_id = trim($2)
      status = trim($3)
      rpc_address = trim($4)
      if (node_id ~ /^[0-9]+$/ && status == "Running") {
        print node_id " " rpc_address
      }
    }
  ' "${run_artifact_dir}/show_datanodes.out" > "${run_artifact_dir}/running_datanodes.txt"
}

wait_for_datanode_running() {
  local dn_ip=$1
  local timeout_seconds=$2
  local begin_time
  begin_time=$(date +%s)
  while true; do
    refresh_running_datanodes
    if grep -q " ${dn_ip}$" "${run_artifact_dir}/running_datanodes.txt"; then
      return 0
    fi
    if (( $(date +%s) - begin_time > timeout_seconds )); then
      append_warn "expand dn ${dn_ip} not running"
      let fail_flag++
      return 1
    fi
    sleep 5
  done
}

cleanup_remote_datanode_state() {
  local dn_ip=$1

  # Expand nodes may retain old node metadata under data/, which makes a new join
  # look like an invalid restart of a removed DataNode.
  ssh -n "${u_name}@${dn_ip}" "source /etc/profile; sudo ${db_dir}/sbin/stop-datanode.sh > /dev/null 2>&1 || true"
  ssh -n "${u_name}@${dn_ip}" "source /etc/profile; sudo ${db_dir}/sbin/stop-confignode.sh > /dev/null 2>&1 || true"
  ssh -n "${u_name}@${dn_ip}" "source /etc/profile; dn_pid=\$(sudo jps | awk '/DataNode/{print \$1}'); if [[ -n \"\${dn_pid}\" ]]; then sudo kill -9 \${dn_pid}; fi; cn_pid=\$(sudo jps | awk '/ConfigNode/{print \$1}'); if [[ -n \"\${cn_pid}\" ]]; then sudo kill -9 \${cn_pid}; fi"
  ssh -n "${u_name}@${dn_ip}" "source /etc/profile; sudo rm -rf ${db_dir}/data ${db_dir}/logs"
}

expand_cluster() {
  if [[ -z "${expand_dn_ip}" ]]; then
    append_warn "expand dn ip is empty"
    let fail_flag++
    return 1
  fi

  log "expand cluster with ${expand_dn_ip}"
  cleanup_remote_datanode_state "${expand_dn_ip}"
  configure_one_datanode "${expand_dn_ip}"
  ssh -n "${u_name}@${expand_dn_ip}" "source /etc/profile; cd ${db_dir}; sudo ./sbin/start-datanode.sh -H ${db_dir}/dn_$(date +%s)_heapdump.hprof > /dev/null 2>&1 &"
  wait_for_datanode_running "${expand_dn_ip}" 600 || return 1

  if ! grep -qx "${expand_dn_ip}" "${nodeinfo_dir}/datanode.txt"; then
    echo "${expand_dn_ip}" >> "${nodeinfo_dir}/datanode.txt"
  fi

  refresh_running_datanodes || return 1
  expand_dn_id=$(awk -v target_ip="${expand_dn_ip}" '$2 == target_ip {print $1}' "${run_artifact_dir}/running_datanodes.txt")
  if [[ -z "${expand_dn_id}" ]]; then
    append_warn "expand dn id not found"
    let fail_flag++
    return 1
  fi

  log "expand dn id=${expand_dn_id}"
  return 0
}

collect_regions() {
  local dialect=$1
  local stage=$2
  local out_file="${run_artifact_dir}/${stage}_${dialect}_regions.out"
  if [[ "${dialect}" = "table" ]]; then
    run_cli_sql "${query_ip}" table "show regions;" "${out_file}" 3600
  else
    run_cli_sql "${query_ip}" tree "show regions;" "${out_file}" 3600
  fi
  trim_file_crlf "${out_file}"
  archive_snapshot "${out_file}" "${stage}_${dialect}_regions"
}

show_migrations_is_empty() {
  local dialect=$1
  local stage=$2
  local out_file="${run_artifact_dir}/${stage}_${dialect}_migrations.out"
  run_cli_sql "${query_ip}" "${dialect}" "show migrations;" "${out_file}" 3600
  trim_file_crlf "${out_file}"
  append_migrations_trace "${stage}" "${dialect}" "${out_file}"
  if grep -Eq "Exception|ERROR|Error" "${out_file}"; then
    append_warn "${dialect} show migrations failed"
    let fail_flag++
    return 1
  fi
  if grep -Eq '^Empty set' "${out_file}"; then
    return 0
  fi
  return 2
}

show_regions_has_active_migration() {
  local stage=$1
  local out_file="${run_artifact_dir}/${stage}_table_regions.out"
  run_cli_sql "${query_ip}" table "show regions;" "${out_file}" 3600
  trim_file_crlf "${out_file}"
  archive_snapshot "${out_file}" "${stage}_table_regions"
  if grep -Eq "Exception|ERROR|Error" "${out_file}"; then
    append_warn "table show regions failed"
    let fail_flag++
    return 1
  fi
  if grep -Eq "Adding|Removing" "${out_file}"; then
    return 0
  fi
  return 2
}

check_show_migrations_consistency() {
  local stage=$1
  local tree_done=$2
  local table_done=$3
  local region_rc=$4
  local inconsistent_dialects=""
  local marker_file="${run_artifact_dir}/${stage}_show_migrations_bug.flag"

  if [[ "${region_rc}" -ne 0 ]]; then
    return 0
  fi

  if [[ "${tree_done}" -eq 1 ]]; then
    inconsistent_dialects="tree"
  fi
  if [[ "${table_done}" -eq 1 ]]; then
    if [[ -n "${inconsistent_dialects}" ]]; then
      inconsistent_dialects="${inconsistent_dialects},table"
    else
      inconsistent_dialects="table"
    fi
  fi

  if [[ -z "${inconsistent_dialects}" ]]; then
    return 0
  fi

  if [[ ! -f "${marker_file}" ]]; then
    append_warn "${stage} show regions still has Adding/Removing while show migrations returned Empty set for ${inconsistent_dialects}"
    let fail_flag++
    for file in \
      "${run_artifact_dir}/${stage}_tree_migrations.out" \
      "${run_artifact_dir}/${stage}_table_migrations.out" \
      "${run_artifact_dir}/${stage}_table_regions.out"; do
      [[ -f "${file}" ]] && cat "${file}" >> "${log_file}"
    done
    : > "${marker_file}"
  fi
  return 0
}

select_operation_region_from_file() {
  local region_file=$1
  local dialect=$2
  local operation=$3
  local candidate_file="${run_artifact_dir}/${operation}_${dialect}_region_candidates.out"

  awk -F '|' -v dialect="${dialect}" -v expand_target_id="${expand_dn_id}" '
    function trim(s) {
      gsub(/^[ \t]+|[ \t]+$/, "", s)
      return s
    }
    function is_user_database(db) {
      if (dialect == "tree") {
        return db !~ /^root\.__/
      }
      return db != "" && db != "information_schema"
    }
    /^\|/ {
      region_id = trim($2)
      type = trim($3)
      status = trim($4)
      database = trim($5)
      dn_id = trim($8)
      role = trim($12)
      if (region_id !~ /^[0-9]+$/ ||
          type != "DataRegion" ||
          status != "Running" ||
          !is_user_database(database)) {
        next
      }
      if (!(region_id in db_name)) {
        db_name[region_id] = database
      }
      if (dn_id == expand_target_id) {
        has_expand[region_id] = 1
      }
      if (role == "Leader" && !(region_id in leader_dn)) {
        leader_dn[region_id] = dn_id
      }
    }
    END {
      for (region_id in leader_dn) {
        if (!has_expand[region_id]) {
          print region_id " " leader_dn[region_id] " " db_name[region_id]
        }
      }
    }
  ' "${region_file}" | sort -n -k1,1 > "${candidate_file}"

  if [[ $(wc -l < "${candidate_file}") -lt 1 ]]; then
    append_warn "${dialect} user data regions are insufficient for ${operation}"
    let fail_flag++
    return 1
  fi

  local first_line
  first_line=$(sed -n '1p' "${candidate_file}")

  if [[ "${dialect}" = "tree" && "${operation}" = "migrate" ]]; then
    tree_migrate_region_id=$(echo "${first_line}" | awk '{print $1}')
    tree_migrate_from_dn_id=$(echo "${first_line}" | awk '{print $2}')
  elif [[ "${dialect}" = "tree" && "${operation}" = "extend" ]]; then
    tree_extend_region_id=$(echo "${first_line}" | awk '{print $1}')
    tree_extend_from_dn_id=$(echo "${first_line}" | awk '{print $2}')
  elif [[ "${dialect}" = "table" && "${operation}" = "migrate" ]]; then
    table_migrate_region_id=$(echo "${first_line}" | awk '{print $1}')
    table_migrate_from_dn_id=$(echo "${first_line}" | awk '{print $2}')
  else
    table_extend_region_id=$(echo "${first_line}" | awk '{print $1}')
    table_extend_from_dn_id=$(echo "${first_line}" | awk '{print $2}')
  fi

  return 0
}

select_migrate_regions() {
  refresh_running_datanodes || return 1
  collect_regions tree "select_migrate_regions"
  collect_regions table "select_migrate_regions"
  select_operation_region_from_file "${run_artifact_dir}/select_migrate_regions_tree_regions.out" tree migrate || return 1
  select_operation_region_from_file "${run_artifact_dir}/select_migrate_regions_table_regions.out" table migrate || return 1
  log "selected migrate regions: tree=${tree_migrate_region_id}/${tree_migrate_from_dn_id}, table=${table_migrate_region_id}/${table_migrate_from_dn_id}"
  return 0
}

select_extend_regions() {
  refresh_running_datanodes || return 1
  collect_regions tree "select_extend_regions"
  collect_regions table "select_extend_regions"
  select_operation_region_from_file "${run_artifact_dir}/select_extend_regions_tree_regions.out" tree extend || return 1
  select_operation_region_from_file "${run_artifact_dir}/select_extend_regions_table_regions.out" table extend || return 1
  log "selected extend regions: tree=${tree_extend_region_id}/${tree_extend_from_dn_id}, table=${table_extend_region_id}/${table_extend_from_dn_id}"
  return 0
}

run_maintenance_sql() {
  local dialect=$1
  local sql=$2
  local out_file=$3
  local desc=$4

  "${cli_dir}/sbin/start-cli.sh" -u root -h "${query_ip}" -timeout 3600 -sql_dialect "${dialect}" -e "${sql}" > "${out_file}" 2>&1
  check_cli_success "${out_file}" "${desc}" || return 1
  return 0
}

wait_for_migrations_completion() {
  local stage=$1
  local prefix=$2
  local timeout_seconds=${3:-0}
  local begin_time
  local tree_done=0
  local table_done=0
  begin_time=$(date +%s)

  while true
  do
    local elapsed_seconds
    local region_rc=2
    elapsed_seconds=$(( $(date +%s) - begin_time ))

    if [[ "${tree_done}" -eq 0 ]]; then
      show_migrations_is_empty tree "${stage}"
      local tree_rc=$?
      if [[ "${tree_rc}" -eq 1 ]]; then
        return 1
      fi
      if [[ "${tree_rc}" -eq 0 ]]; then
        tree_done=1
        eval "${prefix}_tree_elapsed_seconds=${elapsed_seconds}"
      fi
    fi

    if [[ "${table_done}" -eq 0 ]]; then
      show_migrations_is_empty table "${stage}"
      local table_rc=$?
      if [[ "${table_rc}" -eq 1 ]]; then
        return 1
      fi
      if [[ "${table_rc}" -eq 0 ]]; then
        table_done=1
        eval "${prefix}_table_elapsed_seconds=${elapsed_seconds}"
      fi
    fi

    show_regions_has_active_migration "${stage}"
    region_rc=$?
    if [[ "${region_rc}" -eq 1 ]]; then
      return 1
    fi

    check_show_migrations_consistency "${stage}" "${tree_done}" "${table_done}" "${region_rc}" || return 1

    if [[ "${tree_done}" -eq 1 && "${table_done}" -eq 1 && "${region_rc}" -eq 2 ]]; then
      eval "${prefix}_elapsed_seconds=${elapsed_seconds}"
      return 0
    fi
    if [[ "${timeout_seconds}" -gt 0 && "${elapsed_seconds}" -gt "${timeout_seconds}" ]]; then
      append_warn "${stage} not completed"
      let fail_flag++
      return 1
    fi
    sleep 10
  done
}

run_migrate_phase() {
  run_maintenance_sql tree "migrate region ${tree_migrate_region_id} from ${tree_migrate_from_dn_id} to ${expand_dn_id};" "${run_artifact_dir}/migrate_tree.out" "tree migrate region ${tree_migrate_region_id}" || return 1
  run_maintenance_sql table "migrate region ${table_migrate_region_id} from ${table_migrate_from_dn_id} to ${expand_dn_id};" "${run_artifact_dir}/migrate_table.out" "table migrate region ${table_migrate_region_id}" || return 1
  wait_for_migrations_completion "after_migrate" "migrate" 0 || return 1
  collect_regions tree "after_migrate"
  collect_regions table "after_migrate"
  return 0
}

run_extend_phase() {
  run_maintenance_sql tree "extend region ${tree_extend_region_id} to ${expand_dn_id};" "${run_artifact_dir}/extend_tree.out" "tree extend region ${tree_extend_region_id}" || return 1
  run_maintenance_sql table "extend region ${table_extend_region_id} to ${expand_dn_id};" "${run_artifact_dir}/extend_table.out" "table extend region ${table_extend_region_id}" || return 1
  wait_for_migrations_completion "after_extend" "extend" 0 || return 1
  collect_regions tree "after_extend"
  collect_regions table "after_extend"
  return 0
}

run_remove_phase() {
  run_maintenance_sql tree "remove region ${tree_extend_region_id} from ${expand_dn_id};" "${run_artifact_dir}/remove_tree.out" "tree remove region ${tree_extend_region_id}" || return 1
  run_maintenance_sql table "remove region ${table_extend_region_id} from ${expand_dn_id};" "${run_artifact_dir}/remove_table.out" "table remove region ${table_extend_region_id}" || return 1
  wait_for_migrations_completion "after_remove" "remove" 0 || return 1
  collect_regions tree "after_remove"
  collect_regions table "after_remove"
  return 0
}

check_benchmark_output_file() {
  local bm_file=$1

  if [[ ! -f "${bm_file}" ]]; then
    return 1
  fi
  if ! grep -q "Test elapsed time (not include schema creation):" "${bm_file}" || ! grep -q "Result Matrix" "${bm_file}"; then
    return 2
  fi
  if grep -Eq "${benchmark_error_pattern}" "${bm_file}"; then
    return 3
  fi
  return 0
}

wait_benchmarks_finish() {
  local max_wait=${1:-43200}
  local start_time
  local workload
  local finished_num
  local check_rc
  local fail_detected=0
  local reported_error_workloads=""
  local reported_exit_workloads=""

  start_time=$(date +%s)
  while true
  do
    finished_num=0
    for workload in ${workloads}
    do
      local bm_file="${bm_log_root}/${workload}.out"
      check_benchmark_output_file "${bm_file}"
      check_rc=$?
      case ${check_rc} in
        0)
          finished_num=$((finished_num + 1))
          ;;
        1|2)
          if ! benchmark_pid_running "${workload}"; then
            finished_num=$((finished_num + 1))
            fail_detected=1
            if [[ " ${reported_exit_workloads} " != *" ${workload} "* ]]; then
              append_warn "benchmark ${workload} exited before producing final result"
              reported_exit_workloads="${reported_exit_workloads} ${workload}"
            fi
          fi
          ;;
        3)
          finished_num=$((finished_num + 1))
          fail_detected=1
          if [[ " ${reported_error_workloads} " != *" ${workload} "* ]]; then
            append_warn "benchmark ${workload} output contains execution errors"
            reported_error_workloads="${reported_error_workloads} ${workload}"
          fi
          ;;
      esac
    done

    if [[ ${finished_num} -eq ${workload_count} ]]; then
      if [[ ${fail_detected} -ne 0 ]]; then
        let fail_flag++
        return 1
      fi
      return 0
    fi
    if (( $(date +%s) - start_time > max_wait )); then
      append_warn "benchmark did not finish within ${max_wait}s"
      let fail_flag++
      return 1
    fi
    sleep 15
  done
}

wait_for_monitor_sync_completion() {
  local target_duration=${1:-120}
  local max_wait_seconds=${2:-360000}
  local prometheus_user=admin
  local prometheus_pass=admin
  local sleep_interval=30
  local metric_name="iot_consensus"
  local server_name="ioTConsensusServerImpl"
  local wait_start_time
  local zero_start_time=0
  local expected_count=0
  local instance_regex=""
  local ip

  if [[ -z "${monitor_url// }" ]]; then
    log "monitor_url is empty, skip sync lag check"
    return 0
  fi

  wait_start_time=$(date +%s)

  run_cli_sql "${query_ip}" tree "show datanodes;" "${run_artifact_dir}/sync_running_datanodes.out" 3600
  awk -F '|' '/Running/ {gsub(/ /, "", $4); print $4}' "${run_artifact_dir}/sync_running_datanodes.out" | sort -u > "${run_artifact_dir}/sync_running_datanodes_ips.out"
  while read -r ip
  do
    [[ -z "${ip}" ]] && continue
    expected_count=$((expected_count + 1))
    [[ -n "${instance_regex}" ]] && instance_regex="${instance_regex}|"
    instance_regex="${instance_regex}${ip//./[.]}(:[0-9]+)?"
  done < "${run_artifact_dir}/sync_running_datanodes_ips.out"

  if [[ ${expected_count} -eq 0 ]]; then
    append_warn "no running datanodes found while waiting sync lag"
    let fail_flag++
    return 1
  fi
  instance_regex="^(${instance_regex})$"

  while true
  do
    local now
    local query
    local response
    local response_file="${run_artifact_dir}/sync_lag_response.json"
    local response_status=""
    local parse_rc=0
    local non_zero_num

    now=$(date +%s)
    if (( now - wait_start_time > max_wait_seconds )); then
      append_warn "sync lag did not become zero within ${max_wait_seconds}s"
      let fail_flag++
      return 1
    fi

    query="sum(${metric_name}{instance=~\"${instance_regex}\",name=\"${server_name}\",type=\"syncLag\"}) by (instance)"
    response=$(curl -s -u "${prometheus_user}:${prometheus_pass}" --get --data-urlencode "query=${query}" "${monitor_url}/api/v1/query")
    printf '%s\n' "${response}" > "${response_file}"

    response_status=$(parse_monitor_query_status "${response_file}")
    parse_rc=$?
    if [[ ${parse_rc} -ne 0 || "${response_status}" != "success" ]]; then
      zero_start_time=0
      sleep "${sleep_interval}"
      continue
    fi

    non_zero_num=$(count_non_zero_sync_lag "${response_file}")
    parse_rc=$?
    if [[ ${parse_rc} -ne 0 ]]; then
      zero_start_time=0
      sleep "${sleep_interval}"
      continue
    fi

    if [[ ${non_zero_num} -gt 0 ]]; then
      zero_start_time=0
    else
      if [[ ${zero_start_time} -eq 0 ]]; then
        zero_start_time=${now}
      fi
      if (( now - zero_start_time >= target_duration )); then
        return 0
      fi
    fi

    sleep "${sleep_interval}"
  done
}

wait_datanode_not_running() {
  local query_host=$1
  local dn_ip=$2
  local timeout_seconds=${3:-180}
  local start_time
  local running_count

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${query_host}" tree "show datanodes;" "${run_artifact_dir}/show_datanodes_consistency.out" 3600
    running_count=$(grep "${dn_ip}|" "${run_artifact_dir}/show_datanodes_consistency.out" | grep Running | wc -l)
    if [[ ${running_count} -eq 0 ]]; then
      return 0
    fi
    if (( $(date +%s) - start_time > timeout_seconds )); then
      return 1
    fi
    sleep 2
  done
}

wait_datanode_running() {
  local query_host=$1
  local dn_ip=$2
  local timeout_seconds=${3:-300}
  local start_time
  local running_count

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${query_host}" tree "show datanodes;" "${run_artifact_dir}/show_datanodes_consistency.out" 3600
    running_count=$(grep "${dn_ip}|" "${run_artifact_dir}/show_datanodes_consistency.out" | grep Running | wc -l)
    if [[ ${running_count} -gt 0 ]]; then
      return 0
    fi
    if (( $(date +%s) - start_time > timeout_seconds )); then
      return 1
    fi
    sleep 2
  done
}

stop_remote_datanode() {
  local dn_ip=$1
  ssh -n "${u_name}@${dn_ip}" "source /etc/profile; cd ${db_dir}; sudo ./sbin/stop-datanode.sh"
}

start_remote_datanode() {
  local dn_ip=$1
  local start_time
  start_time=$(date +%s)
  ssh -n "${u_name}@${dn_ip}" "source /etc/profile; cd ${db_dir}; sudo ./sbin/start-datanode.sh -H ${db_dir}/dn_${start_time}_heapdump.hprof > /dev/null 2>&1 &"
}

normalize_object_query_result() {
  local src_file=$1
  local dst_file=$2
  local tmp_file="${dst_file}.tmp"

  awk '
    /\+/ { next }
    /\|/ {
      line = $0
      gsub(/\r/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line == "") {
        next
      }
      split(line, arr, "|")
      out = ""
      for (i = 2; i < length(arr); i++) {
        val = arr[i]
        gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (val == "null") {
          val = ""
        }
        out = out val "|"
      }
      if (out ~ /^(Time|time|D_DATETIME|device_id|Device|Database|TableName)\|/) {
        next
      }
      if (out != "|") {
        print out
      }
    }
  ' "${src_file}" > "${tmp_file}"

  printf 'line_count=%s\n' "$(wc -l < "${tmp_file}" | tr -d '[:space:]')" > "${dst_file}"
  printf 'sha256=%s\n' "$(sha256sum "${tmp_file}" | awk '{print $1}')" >> "${dst_file}"
  rm -f "${tmp_file}"
}

normalize_query_result() {
  local src_file=$1
  local dst_file=$2

  if [[ "${src_file}" == *"_obj_"* ]]; then
    normalize_object_query_result "${src_file}" "${dst_file}"
    return
  fi

  awk '
    /\+/ { next }
    /\|/ {
      line = $0
      gsub(/\r/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line == "") {
        next
      }
      split(line, arr, "|")
      out = ""
      for (i = 2; i < length(arr); i++) {
        val = arr[i]
        gsub(/^[ \t]+|[ \t]+$/, "", val)
        if (val == "null") {
          val = ""
        }
        out = out val "|"
      }
      if (out ~ /^(Time|time|D_DATETIME|device_id|Device|Database|TableName)\|/) {
        next
      }
      if (out != "|") {
        print out
      }
    }
  ' "${src_file}" | sort > "${dst_file}"
}

query_output_has_error() {
  local src_file=$1
  grep -Eiq '(^Msg:|IoTDBSQLException|StatementExecutionException|executeStatement failed|^[[:space:]]*Exception|java\.lang\.)' "${src_file}"
}

capture_query_result() {
  local host=$1
  local dialect=$2
  local sql=$3
  local raw_file=$4
  local norm_file=$5

  run_cli_sql "${host}" "${dialect}" "${sql}" "${raw_file}" 3600
  if query_output_has_error "${raw_file}"; then
    append_warn "${dialect} query execute failed on ${host}"
    log "${dialect} query failed on ${host}: ${sql}"
    sed -n '1,40p' "${raw_file}" >> "${log_file}"
    let fail_flag++
    return 1
  fi
  normalize_query_result "${raw_file}" "${norm_file}"
}

compare_query_result() {
  local base_file=$1
  local check_file=$2
  local reason=$3
  local diff_file="${run_artifact_dir}/tmp_diff.out"

  if ! diff -u "${base_file}" "${check_file}" > "${diff_file}" 2>&1; then
    append_warn "${reason}"
    log "${reason}"
    sed -n '1,40p' "${diff_file}" >> "${log_file}"
    let fail_flag++
    return 1
  fi
  return 0
}

capture_consistency_baseline() {
  capture_query_result "${query_ip}" tree "${query_tree_sql}" "${run_artifact_dir}/q_all_online_tree.out" "${run_artifact_dir}/q_all_online_tree.norm" || return 1
  capture_query_result "${query_ip}" table "${query_table_base_sql}" "${run_artifact_dir}/q_all_online_tab1.out" "${run_artifact_dir}/q_all_online_tab1.norm" || return 1
  capture_query_result "${query_ip}" table "${query_table_view_sql}" "${run_artifact_dir}/q_all_online_tab2.out" "${run_artifact_dir}/q_all_online_tab2.norm" || return 1
  capture_query_result "${query_ip}" table "${query_table_base_object_sql}" "${run_artifact_dir}/q_all_online_obj_tab1.out" "${run_artifact_dir}/q_all_online_obj_tab1.norm" || return 1
  capture_query_result "${query_ip}" table "${query_table_view_object_sql}" "${run_artifact_dir}/q_all_online_obj_tab2.out" "${run_artifact_dir}/q_all_online_obj_tab2.norm" || return 1
}

choose_query_host() {
  local stop_dn_ip=$1
  awk -v stop_ip="${stop_dn_ip}" '$0 != stop_ip {print; exit}' "${run_artifact_dir}/running_datanodes.txt"
}

check_data_consistent() {
  local stop_dn_ip
  local query_host
  local v_ip

  if ! capture_consistency_baseline; then
    return 1
  fi
  run_cli_sql "${query_ip}" tree "show datanodes;" "${run_artifact_dir}/show_datanodes.out" 3600
  awk -F '|' '/Running/ {gsub(/ /, "", $4); print $4}' "${run_artifact_dir}/show_datanodes.out" | sort -u > "${run_artifact_dir}/running_datanodes.txt"

  while read -r stop_dn_ip
  do
    [[ -z "${stop_dn_ip}" ]] && continue
    query_host=$(choose_query_host "${stop_dn_ip}")
    if [[ -z "${query_host}" ]]; then
      append_warn "no query host left after stopping ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi

    stop_remote_datanode "${stop_dn_ip}"
    if ! wait_datanode_not_running "${query_host}" "${stop_dn_ip}" 180; then
      append_warn "cluster state did not update after stopping ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi

    v_ip=$(echo "${stop_dn_ip}" | awk -F '.' '{print $4}')
    capture_query_result "${query_host}" tree "${query_tree_sql}" "${run_artifact_dir}/q_stop_ip${v_ip}_tree.out" "${run_artifact_dir}/q_stop_ip${v_ip}_tree.norm" || return 1
    capture_query_result "${query_host}" table "${query_table_base_sql}" "${run_artifact_dir}/q_stop_ip${v_ip}_tab1.out" "${run_artifact_dir}/q_stop_ip${v_ip}_tab1.norm" || return 1
    capture_query_result "${query_host}" table "${query_table_view_sql}" "${run_artifact_dir}/q_stop_ip${v_ip}_tab2.out" "${run_artifact_dir}/q_stop_ip${v_ip}_tab2.norm" || return 1
    capture_query_result "${query_host}" table "${query_table_base_object_sql}" "${run_artifact_dir}/q_stop_ip${v_ip}_obj_tab1.out" "${run_artifact_dir}/q_stop_ip${v_ip}_obj_tab1.norm" || return 1
    capture_query_result "${query_host}" table "${query_table_view_object_sql}" "${run_artifact_dir}/q_stop_ip${v_ip}_obj_tab2.out" "${run_artifact_dir}/q_stop_ip${v_ip}_obj_tab2.norm" || return 1

    compare_query_result "${run_artifact_dir}/q_all_online_tree.norm" "${run_artifact_dir}/q_stop_ip${v_ip}_tree.norm" "tree query result differs when ${stop_dn_ip} is down"
    compare_query_result "${run_artifact_dir}/q_all_online_tab1.norm" "${run_artifact_dir}/q_stop_ip${v_ip}_tab1.norm" "table base query result differs when ${stop_dn_ip} is down"
    compare_query_result "${run_artifact_dir}/q_all_online_tab2.norm" "${run_artifact_dir}/q_stop_ip${v_ip}_tab2.norm" "table writable view query result differs when ${stop_dn_ip} is down"
    compare_query_result "${run_artifact_dir}/q_all_online_obj_tab1.norm" "${run_artifact_dir}/q_stop_ip${v_ip}_obj_tab1.norm" "table base object query result differs when ${stop_dn_ip} is down"
    compare_query_result "${run_artifact_dir}/q_all_online_obj_tab2.norm" "${run_artifact_dir}/q_stop_ip${v_ip}_obj_tab2.norm" "table writable view object query result differs when ${stop_dn_ip} is down"

    start_remote_datanode "${stop_dn_ip}"
    if ! wait_datanode_running "${query_host}" "${stop_dn_ip}" 300; then
      append_warn "failed to restart ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi
    if ! wait_for_monitor_sync_completion 120 360000; then
      return 1
    fi
  done < "${run_artifact_dir}/running_datanodes.txt"

  return 0
}

stop_cluster() {
  sh -x "${clean_env_dir}/stop_cluster.sh" >> "${log_file}" 2>&1 || true
}

backup_logs() {
  local case_name=${SCRIPT_NAME%.sh}
  local backup_time
  backup_time=$(date +"%Y_%m_%d_%H_%M_%S")
  sh -x "${clean_env_dir}/backup_cluster_logs.sh" "${case_name}" "${backup_time}" >> "${log_file}" 2>&1 || true
}

build_result_message() {
  local result_message
  result_message="${v_warnMessage}; migrate total=${migrate_elapsed_seconds}s,tree=${migrate_tree_elapsed_seconds}s,table=${migrate_table_elapsed_seconds}s."
  result_message="${result_message} extend total=${extend_elapsed_seconds}s,tree=${extend_tree_elapsed_seconds}s,table=${extend_table_elapsed_seconds}s."
  result_message="${result_message} remove total=${remove_elapsed_seconds}s,tree=${remove_tree_elapsed_seconds}s,table=${remove_table_elapsed_seconds}s."
  echo "${result_message}"
}

write_test_result() {
  local test_end_sec
  local test_elp_sec
  local tc_res=true
  local warn_message_sql
  local result_message

  test_end_sec=$(date +%s)
  test_elp_sec=$((test_end_sec - test_begin_sec))
  result_message=$(build_result_message)
  if [[ ${fail_flag} -ne 0 ]]; then
    tc_res=false
  fi

  warn_message_sql=${result_message//;/,}
  warn_message_sql=${warn_message_sql//\'/\'\'}

  if [[ "${tc_res}" = true ]]; then
    echo "${SCRIPT_NAME} : pass" >> "${res_file}"
  else
    echo "${SCRIPT_NAME} : fail"
    echo "warn_message=${result_message}"
    echo "${SCRIPT_NAME} : fail" >> "${res_file}"
  fi

  "${cli_dir}/sbin/start-cli.sh" -h "${testcase_res_db}" -p "${testcase_res_port}" -pw "${res_root_pw}" -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time,warnMsg)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec},'${warn_message_sql}');" >> "${log_file}" 2>&1 || true
}

main() {
  local metadata_ready=1
  mkdir -p "${run_artifact_dir}"
  : > "${log_file}"
  log "run artifacts directory: ${run_artifact_dir}"

  start_db
  create_benchmark_users
  prepare_benchmark_workdirs
  start_benchmarks

  if ! wait_benchmark_objects_ready 900; then
    append_warn "benchmark objects not ready within 900s"
    let fail_flag++
    metadata_ready=0
  fi

  if [[ ${metadata_ready} -eq 1 ]] && ! resolve_table_objects; then
    metadata_ready=0
  fi

  if [[ ${metadata_ready} -eq 1 ]] && ! resolve_object_columns; then
    metadata_ready=0
  fi

  if [[ "${pre_maintenance_wait_seconds}" -gt 0 ]]; then
    log "sleep ${pre_maintenance_wait_seconds}s before expand and region maintenance"
    sleep "${pre_maintenance_wait_seconds}"
  fi

  expand_cluster || {
    stop_cluster
    backup_logs
    write_test_result
    return 1
  }

  select_migrate_regions || {
    stop_cluster
    backup_logs
    write_test_result
    return 1
  }

  run_migrate_phase || {
    stop_cluster
    backup_logs
    write_test_result
    return 1
  }

  select_extend_regions || {
    stop_cluster
    backup_logs
    write_test_result
    return 1
  }

  run_extend_phase || {
    stop_cluster
    backup_logs
    write_test_result
    return 1
  }

  run_remove_phase || {
    stop_cluster
    backup_logs
    write_test_result
    return 1
  }

  wait_benchmarks_finish 43200 || true
  wait_for_monitor_sync_completion 120 360000 || true

  if [[ ${metadata_ready} -eq 1 ]]; then
    check_data_consistent || true
  else
    append_warn "replica consistency check skipped because benchmark metadata was not ready"
  fi

  stop_cluster
  backup_logs
  write_test_result
}

main

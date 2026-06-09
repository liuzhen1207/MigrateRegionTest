#!/bin/bash

cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
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
dn_num=5
head -n ${dn_num} "${nodeinfo_dir}/total_datanode.txt" > "${nodeinfo_dir}/datanode.txt"
head -n ${dn_num} "${nodeinfo_dir}/total_datanode_port.txt" > "${nodeinfo_dir}/datanode_port.txt"
total_node_num=$((cn_num + dn_num))

seed_cn_ip=$(head -1 "${nodeinfo_dir}/confignode.txt"):10710
query_ip=$(head -1 "${nodeinfo_dir}/datanode.txt")

tc_num=$(echo "${SCRIPT_NAME}" | awk -F '_' '{print $1}' | awk -F 'tc' '{print $2}')
testcase_ip=$(grep '^test_ip=' "${conf_file}" | awk -F '.' '{print $4}')
test_begin_sec=$(date +%s)

bm_dir="${cur_dir}/../benchmark/bm_20260519_writeview_v20"
bm_case_root="${bm_dir}/weather_6h_diff"
bm_work_root="${cur_dir}/bm_work_${tc_num}_${test_begin_sec}"
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
table_base_name=""
table_view_name=""
table_base_object_col=""
table_view_object_col=""
tracked_region_id=""
tracked_region_before_members=""
tracked_region_after_members=""
tracked_region_target_dn_ip=""
tracked_region_target_dn_id=""

query_tree_sql="select count(s_0),count(s_1),count(s_2),count(s_3),count(s_4),count(s_5),count(s_6),count(s_7),count(s_8),count(s_9),count(s_10),count(s_11) from root.test.** align by device;"
query_table_base_sql=""
query_table_view_sql=""
query_table_base_object_sql=""
query_table_view_object_sql=""

fail_flag=0
rm_fail_flag=0
rm_result_state="Running"
rm_target_ip=""
rm_adding_dn_ip=""
rm_adding_dn_id=""
v_warnMessage=""

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

append_warn() {
  local msg=$1
  if [[ -z "${v_warnMessage}" ]]; then
    v_warnMessage="${msg}"
  else
    v_warnMessage="${v_warnMessage}; ${msg}"
  fi
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

  # OBJECT columns cannot participate in benchmark value-filter queries such as `s_x > -5`.
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

clean_env() {
  sh -x "${clean_env_dir}/stop_cluster.sh"
  sh -x "${clean_env_dir}/clean_cluster.sh"
  sh -x "${clean_env_dir}/reset_conf.sh"
}

set_conf() {
  exec 3<"${nodeinfo_dir}/confignode.txt"
  while read -r line <&3
  do
    ssh "${u_name}@${line}" "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/confignode-env.sh"
    ssh "${u_name}@${line}" "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
    set_sys_conf "${line}" "${db_dir}" ".*cn_seed_config_node=.*" "cn_seed_config_node=${seed_cn_ip}"
    set_sys_conf "${line}" "${db_dir}" ".*cn_internal_address=.*" "cn_internal_address=${line}"
    set_sys_conf "${line}" "${db_dir}" ".*cn_metric_reporter_list=.*" "cn_metric_reporter_list=PROMETHEUS"
    set_sys_conf "${line}" "${db_dir}" ".*schema_replication_factor=.*" "schema_replication_factor=3"
    set_sys_conf "${line}" "${db_dir}" ".*data_replication_factor=.*" "data_replication_factor=2"
  done
  exec 3<&-

  exec 3<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&3
  do
    ssh "${u_name}@${line}" "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"20G\"/g' ${db_dir}/conf/datanode-env.sh"
    ssh "${u_name}@${line}" "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
    set_sys_conf "${line}" "${db_dir}" ".*dn_seed_config_node=.*" "dn_seed_config_node=${seed_cn_ip}"
    set_sys_conf "${line}" "${db_dir}" ".*dn_internal_address=.*" "dn_internal_address=${line}"
    set_sys_conf "${line}" "${db_dir}" ".*dn_rpc_address=.*" "dn_rpc_address=${line}"
    set_sys_conf "${line}" "${db_dir}" ".*dn_metric_reporter_list=.*" "dn_metric_reporter_list=PROMETHEUS"
    set_sys_conf "${line}" "${db_dir}" ".*schema_replication_factor=.*" "schema_replication_factor=3"
    set_sys_conf "${line}" "${db_dir}" ".*data_replication_factor=.*" "data_replication_factor=2"
  done
  exec 3<&-
}

start_db() {
  clean_env
  head -n "${cn_num}" "${nodeinfo_dir}/total_node.txt" > "${nodeinfo_dir}/confignode.txt"
  set_conf
  sh -x "${prepare_env_dir}/start_cluster_v20.sh" "1" "${total_node_num}"
}

create_benchmark_users() {
  run_cli_sql "${query_ip}" tree "CREATE USER santos '${bm_conn_pw}';" "${cur_dir}/create_santos.out" 300
  run_cli_sql "${query_ip}" tree "GRANT READ_SCHEMA,WRITE_SCHEMA,READ_DATA,WRITE_DATA ON root.test.** TO USER santos;" "${cur_dir}/grant_santos_tree.out" 300
  run_cli_sql "${query_ip}" table "GRANT ALL TO USER santos;" "${cur_dir}/grant_santos.out" 300
  run_cli_sql "${query_ip}" tree "CREATE USER rainer '${bm_conn_pw}';" "${cur_dir}/create_rainer.out" 300
  run_cli_sql "${query_ip}" tree "GRANT READ_SCHEMA,WRITE_SCHEMA,READ_DATA,WRITE_DATA ON root.test.** TO USER rainer;" "${cur_dir}/grant_rainer_tree.out" 300
  run_cli_sql "${query_ip}" table "GRANT ALL TO USER rainer;" "${cur_dir}/grant_rainer.out" 300
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
      run_cli_sql "${query_ip}" tree "show devices root.test.**;" "${cur_dir}/show_tree_devices.out" 3600
      if [[ $(grep -c 'root.test.' "${cur_dir}/show_tree_devices.out") -gt 0 ]]; then
        tree_ok=1
      fi
    fi

    if [[ ${table_ok} -eq 0 || ${view_ok} -eq 0 ]]; then
      run_cli_sql "${query_ip}" table "show tables details from ${table_db_name};" "${cur_dir}/show_tables_details.out" 3600
      if [[ ${table_ok} -eq 0 ]] && grep -Eq 'BASE TABLE' "${cur_dir}/show_tables_details.out"; then
        table_ok=1
      fi
      if [[ ${view_ok} -eq 0 ]] && grep -Eq 'WRITABLE VIEW' "${cur_dir}/show_tables_details.out"; then
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
  run_cli_sql "${query_ip}" table "show tables details from ${table_db_name};" "${cur_dir}/show_tables_details.out" 3600

  table_base_name=$(awk -F '|' '
    /BASE TABLE/ {
      name=$2
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      if (name != "TableName" && name != "") {
        print name
        exit
      }
    }
  ' "${cur_dir}/show_tables_details.out")

  table_view_name=$(awk -F '|' '
    /WRITABLE VIEW/ {
      name=$2
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      if (name != "TableName" && name != "") {
        print name
        exit
      }
    }
  ' "${cur_dir}/show_tables_details.out")

  if [[ -z "${table_base_name}" || -z "${table_view_name}" ]]; then
    log "failed to resolve table objects from show tables details"
    cat "${cur_dir}/show_tables_details.out"
    append_warn "show tables details from ${table_db_name} could not resolve base table or writable view"
    let fail_flag++
    return 1
  fi

  query_table_base_sql="select device_id,count(s_0),count(s_1),count(s_2),count(s_3),count(s_4),count(s_5),count(s_6),count(s_7),count(s_8),count(s_9),count(s_10),count(s_11) from ${table_db_name}.${table_base_name} group by device_id order by device_id;"
  query_table_view_sql="select device_id,count(s_0),count(s_1),count(s_2),count(s_3),count(s_4),count(s_5),count(s_6),count(s_7),count(s_8),count(s_9),count(s_10),count(s_11) from ${table_db_name}.${table_view_name} group by device_id order by device_id;"
  return 0
}

resolve_object_columns() {
  run_cli_sql "${query_ip}" table "describe ${table_db_name}.${table_base_name} details;" "${cur_dir}/describe_table_base.out" 3600
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
  ' "${cur_dir}/describe_table_base.out")

  run_cli_sql "${query_ip}" table "describe ${table_db_name}.${table_view_name} details;" "${cur_dir}/describe_table_view.out" 3600
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
  ' "${cur_dir}/describe_table_view.out")

  if [[ -z "${table_base_object_col}" || -z "${table_view_object_col}" ]]; then
    append_warn "failed to resolve OBJECT column from base table or writable view"
    let fail_flag++
    return 1
  fi

  query_table_base_object_sql="select D_DATETIME,device_id,length(read_object(${table_base_object_col})),sha256(cast(read_object(${table_base_object_col}) as string)) from ${table_db_name}.${table_base_name} order by D_DATETIME,device_id limit 20;"
  query_table_view_object_sql="select D_DATETIME,device_id,length(read_object(${table_view_object_col})),sha256(cast(read_object(${table_view_object_col}) as string)) from ${table_db_name}.${table_view_name} order by D_DATETIME,device_id limit 20;"
  return 0
}

wait_until_remove_time() {
  local benchmark_start_sec=$1
  local remove_after_sec=300
  local now
  local sleep_sec

  now=$(date +%s)
  sleep_sec=$((benchmark_start_sec + remove_after_sec - now))
  if [[ ${sleep_sec} -gt 0 ]]; then
    sleep "${sleep_sec}"
  fi
}

switch_query_ip_if_needed() {
  local stop_ip=$1
  local new_query_ip

  if [[ "${query_ip}" != "${stop_ip}" ]]; then
    return 0
  fi

  new_query_ip=$(awk -v ip1="${stop_ip}" -v ip2="${rm_target_ip}" '$0 != ip1 && $0 != ip2 {print; exit}' "${nodeinfo_dir}/datanode.txt")
  if [[ -z "${new_query_ip}" ]]; then
    new_query_ip=$(awk -v ip1="${stop_ip}" '$0 != ip1 {print; exit}' "${nodeinfo_dir}/datanode.txt")
  fi

  if [[ -z "${new_query_ip}" ]]; then
    append_warn "failed to switch query_ip after stopping ${stop_ip}"
    let fail_flag++
    return 1
  fi

  log "query_ip ${query_ip} will be stopped, switch query_ip to ${new_query_ip}"
  query_ip="${new_query_ip}"
  return 0
}

wait_datanode_status() {
  local host=$1
  local dn_ip=$2
  local expect_status=$3
  local timeout_sec=${4:-180}
  local start_time
  local hit_num

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${host}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600
    hit_num=$(grep "${dn_ip}|" "${cur_dir}/show_datanodes.out" | grep -i "${expect_status}" | wc -l)
    if [[ ${hit_num} -gt 0 ]]; then
      return 0
    fi
    if (( $(date +%s) - start_time > timeout_sec )); then
      return 1
    fi
    sleep 2
  done
}

wait_datanode_absent() {
  local host=$1
  local dn_ip=$2
  local timeout_sec=${3:-3600}
  local start_time
  local hit_num

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${host}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600
    hit_num=$(grep "${dn_ip}|" "${cur_dir}/show_datanodes.out" | wc -l)
    if [[ ${hit_num} -eq 0 ]]; then
      return 0
    fi
    if (( $(date +%s) - start_time > timeout_sec )); then
      return 1
    fi
    sleep 5
  done
}

check_removed_datanode_data_cleaned() {
  local dn_ip=$1
  local region_id=$2
  local tsfile_count
  local object_file_count

  ssh "${u_name}@${dn_ip}" 'bash -s' > "${cur_dir}/removed_dn_data_check.out" 2>&1 <<EOF
conf_file="${db_dir}/conf/iotdb-system.properties"
region_id="${region_id}"
data_dirs=\$(awk -F '=' '/^[[:space:]]*dn_data_dirs[[:space:]]*=/{print \$2; exit}' "\${conf_file}" 2>/dev/null | tr -d '[:space:]')
if [[ -z "\${data_dirs}" ]]; then
  data_dirs="${db_dir}/data/datanode/data"
fi
printf 'DATA_DIRS=%s\n' "\${data_dirs}"
printf 'OBJECT_DIR=%s\n' "${db_dir}/data/datanode/data/object/\${region_id}"
IFS=',' read -r -a dir_arr <<< "\${data_dirs}"
tsfile_count=0
for one_dir in "\${dir_arr[@]}"
do
  [[ -z "\${one_dir}" ]] && continue
  if [[ -d "\${one_dir}" ]]; then
    found=\$(find "\${one_dir}" -type f \( -name '*.tsfile' -o -name '*.resource' -o -name '*.mods' \) | grep "/\${region_id}/" | wc -l)
    tsfile_count=\$((tsfile_count + found))
  fi
done
object_file_count=0
if [[ -d "${db_dir}/data/datanode/data/object/\${region_id}" ]]; then
  object_file_count=\$(find "${db_dir}/data/datanode/data/object/\${region_id}" -type f | wc -l)
fi
printf 'TSFILE_COUNT=%s\n' "\${tsfile_count}"
printf 'OBJECT_FILE_COUNT=%s\n' "\${object_file_count}"
EOF
  if [[ $? -ne 0 ]]; then
    log "failed to check removed dn data cleanup on ${dn_ip}"
    cat "${cur_dir}/removed_dn_data_check.out"
    append_warn "failed to check removed dn data cleanup on ${dn_ip}"
    let fail_flag++
    return 1
  fi

  tsfile_count=$(grep '^TSFILE_COUNT=' "${cur_dir}/removed_dn_data_check.out" | tail -1 | awk -F '=' '{print $2}' | tr -d '[:space:]')
  object_file_count=$(grep '^OBJECT_FILE_COUNT=' "${cur_dir}/removed_dn_data_check.out" | tail -1 | awk -F '=' '{print $2}' | tr -d '[:space:]')
  tsfile_count=${tsfile_count:-0}
  object_file_count=${object_file_count:-0}

  if [[ "${tsfile_count}" != "0" || "${object_file_count}" != "0" ]]; then
    log "removed dn ${dn_ip} still has tracked region ${region_id} files: tsfile=${tsfile_count}, object=${object_file_count}"
    append_warn "removed dn ${dn_ip} still has tracked region ${region_id} files: tsfile=${tsfile_count}, object=${object_file_count}"
    let fail_flag++
    return 1
  fi

  log "removed dn ${dn_ip} tracked region ${region_id} data cleaned"
  return 0
}

wait_remove_migrations_finish() {
  local host=$1
  local timeout_sec=${2:-0}
  local start_time
  local tree_done=0
  local table_done=0

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${host}" tree "show migrations;" "${cur_dir}/show_migrations_tree.out" 3600
    if grep -Eiq '(^Error|Exception|^[[:space:]]*Msg:|StatementExecutionException|java\.lang\.)' "${cur_dir}/show_migrations_tree.out"; then
      append_warn "tree show migrations execute failed after remove datanode"
      let fail_flag++
      return 1
    fi
    if grep -q "Empty set" "${cur_dir}/show_migrations_tree.out"; then
      tree_done=1
    else
      tree_done=0
    fi

    run_cli_sql "${host}" table "show migrations;" "${cur_dir}/show_migrations_table.out" 3600
    if grep -Eiq '(^Error|Exception|^[[:space:]]*Msg:|StatementExecutionException|java\.lang\.)' "${cur_dir}/show_migrations_table.out"; then
      append_warn "table show migrations execute failed after remove datanode"
      let fail_flag++
      return 1
    fi
    if grep -q "Empty set" "${cur_dir}/show_migrations_table.out"; then
      table_done=1
    else
      table_done=0
    fi

    if [[ ${tree_done} -eq 1 && ${table_done} -eq 1 ]]; then
      return 0
    fi
    if [[ ${timeout_sec} -gt 0 ]] && (( $(date +%s) - start_time > timeout_sec )); then
      return 1
    fi
    sleep 10
  done
}

select_remove_target_ip() {
  local regions_file="${cur_dir}/show_regions_select_remove.out"
  local candidate_file="${cur_dir}/remove_target_candidates.out"

  run_cli_sql "${query_ip}" table "show regions from ${table_db_name};" "${regions_file}" 3600

  awk -F '|' '
    /DataRegion/ {
      ip=$9
      gsub(/^[ \t]+|[ \t]+$/, "", ip)
      if (ip != "") {
        print ip
      }
    }
  ' "${regions_file}" | sort -u > "${candidate_file}"

  rm_target_ip=$(awk '
    NR==FNR {
      candidate[$1]=1
      next
    }
    candidate[$1] {
      selected=$1
    }
    END {
      print selected
    }
  ' "${candidate_file}" "${nodeinfo_dir}/datanode.txt")

  if [[ -z "${rm_target_ip}" ]]; then
    append_warn "failed to select remove target from ${table_db_name} data regions"
    let fail_flag++
    return 1
  fi

  return 0
}

refresh_query_ip_for_remove_target() {
  local new_query_ip

  if [[ "${query_ip}" != "${rm_target_ip}" ]]; then
    return 0
  fi

  new_query_ip=$(awk -v rm_ip="${rm_target_ip}" '$0 != rm_ip {print; exit}' "${nodeinfo_dir}/datanode.txt")
  if [[ -z "${new_query_ip}" ]]; then
    append_warn "failed to refresh query_ip after choosing remove target ${rm_target_ip}"
    let fail_flag++
    return 1
  fi

  log "query_ip ${query_ip} is selected for remove, switch query_ip to ${new_query_ip}"
  query_ip="${new_query_ip}"
  return 0
}

capture_region_members_before_remove() {
  run_cli_sql "${query_ip}" table "show regions from ${table_db_name};" "${cur_dir}/show_regions_before_remove.out" 3600

  tracked_region_id=$(awk -F '|' -v rm_ip="${rm_target_ip}" '
    /DataRegion/ {
      region=$2
      db=$5
      dnid=$8
      ip=$9
      gsub(/^[ \t]+|[ \t]+$/, "", region)
      gsub(/^[ \t]+|[ \t]+$/, "", db)
      gsub(/^[ \t]+|[ \t]+$/, "", dnid)
      gsub(/^[ \t]+|[ \t]+$/, "", ip)
      if (db == "usr_sod0" && ip == rm_ip) {
        print region
        exit
      }
    }
  ' "${cur_dir}/show_regions_before_remove.out")

  if [[ -z "${tracked_region_id}" ]]; then
    append_warn "failed to pick usr_sod0 data region on remove target ${rm_target_ip}"
    let fail_flag++
    return 1
  fi

  tracked_region_before_members=$(awk -F '|' -v region="${tracked_region_id}" '
    /DataRegion/ {
      region_id=$2
      dnid=$8
      ip=$9
      gsub(/^[ \t]+|[ \t]+$/, "", region_id)
      gsub(/^[ \t]+|[ \t]+$/, "", dnid)
      gsub(/^[ \t]+|[ \t]+$/, "", ip)
      if (region_id == region) {
        print dnid "," ip
      }
    }
  ' "${cur_dir}/show_regions_before_remove.out" | sort | tr '\n' ';')

  return 0
}

wait_any_adding_datanode() {
  local timeout_sec=${1:-600}
  local start_time

  rm_adding_dn_ip=""
  rm_adding_dn_id=""
  start_time=$(date +%s)

  while true
  do
    run_cli_sql "${query_ip}" table "show regions from ${table_db_name};" "${cur_dir}/show_regions_adding.out" 3600
    read -r rm_adding_dn_id rm_adding_dn_ip <<< "$(awk -F '|' -v rm_ip="${rm_target_ip}" '
      /DataRegion/ {
        status=$4
        dnid=$8
        ip=$9
        gsub(/^[ \t]+|[ \t]+$/, "", status)
        gsub(/^[ \t]+|[ \t]+$/, "", dnid)
        gsub(/^[ \t]+|[ \t]+$/, "", ip)
        if (tolower(status) == "adding" && ip != "" && ip != rm_ip) {
          print dnid " " ip
          exit
        }
      }
    ' "${cur_dir}/show_regions_adding.out")"

    if [[ -n "${rm_adding_dn_ip}" && -n "${rm_adding_dn_id}" ]]; then
      return 0
    fi

    if (( $(date +%s) - start_time > timeout_sec )); then
      return 1
    fi
    sleep 2
  done
}

submit_remove_datanode() {
  local rm_dn_id=$1
  local out_file=$2
  local reason_prefix=$3

  run_cli_sql "${query_ip}" tree "remove datanode ${rm_dn_id};" "${out_file}" 3600
  if [[ $(grep -Eic 'success|submit' "${out_file}") -eq 0 ]]; then
    log "${reason_prefix} remove datanode submit output is not success"
    cat "${out_file}"
    append_warn "${reason_prefix} remove datanode ${rm_dn_id} submit failed"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi
  return 0
}

wait_regions_without_transition_status() {
  local host=$1
  local timeout_sec=${2:-600}
  local start_time
  local transition_count

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${host}" table "show regions from ${table_db_name};" "${cur_dir}/show_regions_transition.out" 3600
    transition_count=$(awk -F '|' '
      /SchemaRegion|DataRegion/ {
        status=$4
        gsub(/^[ \t]+|[ \t]+$/, "", status)
        status=tolower(status)
        if (status == "adding" || status == "removing") {
          count++
        }
      }
      END { print count + 0 }
    ' "${cur_dir}/show_regions_transition.out")

    if [[ ${transition_count} -eq 0 ]]; then
      return 0
    fi

    if (( $(date +%s) - start_time > timeout_sec )); then
      return 1
    fi
    sleep 5
  done
}

resolve_region_target_dn_after_remove() {
  local before_file="${cur_dir}/tracked_region_before_members.list"
  local after_file="${cur_dir}/tracked_region_after_members.list"

  run_cli_sql "${query_ip}" table "show regions from ${table_db_name};" "${cur_dir}/show_regions_after_remove.out" 3600
  awk -F ';' 'NF { for (i = 1; i <= NF; i++) if ($i != "") print $i }' <<< "${tracked_region_before_members}" | sort > "${before_file}"

  awk -F '|' -v region="${tracked_region_id}" '
    /DataRegion/ {
      region_id=$2
      dnid=$8
      ip=$9
      gsub(/^[ \t]+|[ \t]+$/, "", region_id)
      gsub(/^[ \t]+|[ \t]+$/, "", dnid)
      gsub(/^[ \t]+|[ \t]+$/, "", ip)
      if (region_id == region) {
        print dnid "," ip
      }
    }
  ' "${cur_dir}/show_regions_after_remove.out" | sort > "${after_file}"

  tracked_region_after_members=$(tr '\n' ';' < "${after_file}")
  read -r tracked_region_target_dn_id tracked_region_target_dn_ip <<< "$(comm -13 "${before_file}" "${after_file}" | head -1 | awk -F ',' '{print $1" "$2}')"

  if [[ -z "${tracked_region_target_dn_ip}" || -z "${tracked_region_target_dn_id}" ]]; then
    append_warn "failed to resolve target dn for migrated region ${tracked_region_id}"
    let fail_flag++
    return 1
  fi

  return 0
}

check_region_object_files_on_dn() {
  local dn_ip=$1
  local region_id=$2
  local expect_exist=$3
  local result

  ssh "${u_name}@${dn_ip}" 'bash -s' > "${cur_dir}/region_object_check.out" 2>&1 <<EOF
object_dir="${db_dir}/data/datanode/data/object/${region_id}"
if [[ -d "\${object_dir}" ]] && find "\${object_dir}" -type f | grep -q .; then
  echo exists
else
  echo missing
fi
EOF
  if [[ $? -ne 0 ]]; then
    append_warn "failed to check object dir for region ${region_id} on ${dn_ip}"
    let fail_flag++
    return 1
  fi

  result=$(tail -1 "${cur_dir}/region_object_check.out" | tr -d '[:space:]')
  if [[ "${expect_exist}" = "yes" && "${result}" != "exists" ]]; then
    append_warn "target dn ${dn_ip} does not contain object files for region ${region_id}"
    let fail_flag++
    return 1
  fi
  if [[ "${expect_exist}" = "no" && "${result}" != "missing" ]]; then
    append_warn "removed dn ${dn_ip} still contains object files for region ${region_id}"
    let fail_flag++
    return 1
  fi
  return 0
}

check_region_object_migrated() {
  if [[ -z "${tracked_region_id}" ]]; then
    append_warn "tracked region id is empty when checking object migration"
    let fail_flag++
    return 1
  fi

  if ! resolve_region_target_dn_after_remove; then
    return 1
  fi

  check_region_object_files_on_dn "${tracked_region_target_dn_ip}" "${tracked_region_id}" "yes" || return 1
  check_region_object_files_on_dn "${rm_target_ip}" "${tracked_region_id}" "no" || return 1
  check_removed_datanode_data_cleaned "${rm_target_ip}" "${tracked_region_id}" || return 1
  return 0
}

remove_datanode_under_load() {
  local rm_dn_id
  local first_remove_failed_as_expected=0

  if ! select_remove_target_ip; then
    return 1
  fi
  if ! refresh_query_ip_for_remove_target; then
    return 1
  fi

  run_cli_sql "${query_ip}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600
  rm_dn_id=$(grep "${rm_target_ip}|" "${cur_dir}/show_datanodes.out" | awk -F '|' '{gsub(" ","",$2);print $2}' | tail -1)

  if [[ -z "${rm_dn_id}" ]]; then
    log "failed to locate remove target id for ${rm_target_ip}"
    append_warn "failed to locate datanode id for remove target ${rm_target_ip}"
    let fail_flag++
    return 1
  fi

  if ! capture_region_members_before_remove; then
    return 1
  fi

  if ! submit_remove_datanode "${rm_dn_id}" "${cur_dir}/remove_datanode_first.out" "first"; then
    return 1
  fi

  if ! wait_any_adding_datanode 600; then
    append_warn "first remove datanode ${rm_dn_id} did not expose an Adding dn within 600s"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  log "stop Adding dn ${rm_adding_dn_ip}(${rm_adding_dn_id}) during first remove datanode ${rm_dn_id}"
  if ! switch_query_ip_if_needed "${rm_adding_dn_ip}"; then
    let rm_fail_flag++
    return 1
  fi

  if ! stop_remote_datanode "${rm_adding_dn_ip}"; then
    append_warn "failed to stop Adding dn ${rm_adding_dn_ip} during first remove"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if ! wait_datanode_not_running "${query_ip}" "${rm_adding_dn_ip}" 180; then
    append_warn "Adding dn ${rm_adding_dn_ip} was not stopped after stop-datanode.sh"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if ! wait_remove_migrations_finish "${query_ip}" 0; then
    log "first remove did not settle after stopping Adding dn ${rm_adding_dn_ip}"
    append_warn "first remove datanode ${rm_dn_id} did not settle after stopping Adding dn ${rm_adding_dn_ip}"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if wait_datanode_absent "${query_ip}" "${rm_target_ip}" 30; then
    append_warn "first remove datanode ${rm_dn_id} succeeded after stopping Adding dn ${rm_adding_dn_ip}, expected failure"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  first_remove_failed_as_expected=1
  log "first remove datanode ${rm_dn_id} failed as expected after stopping Adding dn ${rm_adding_dn_ip}"

  if ! start_remote_datanode "${rm_adding_dn_ip}"; then
    append_warn "failed to restart stopped Adding dn ${rm_adding_dn_ip}"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if ! wait_datanode_running "${query_ip}" "${rm_adding_dn_ip}" 300; then
    append_warn "failed to restart Adding dn ${rm_adding_dn_ip} after first remove failure"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if ! wait_remove_migrations_finish "${query_ip}" 0; then
    append_warn "migrations did not settle after restarting Adding dn ${rm_adding_dn_ip}"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if ! wait_regions_without_transition_status "${query_ip}" 1800; then
    append_warn "regions still had Adding or Removing status after restarting Adding dn ${rm_adding_dn_ip}"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if ! submit_remove_datanode "${rm_dn_id}" "${cur_dir}/remove_datanode_second.out" "second"; then
    return 1
  fi

  if ! wait_remove_migrations_finish "${query_ip}" 0; then
    log "second remove did not finish"
    append_warn "show migrations was not Empty set after second remove datanode ${rm_dn_id}"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if ! wait_datanode_absent "${query_ip}" "${rm_target_ip}" 3600; then
    log "second remove failed, datanode ${rm_target_ip} still exists"
    append_warn "show datanodes still contains removed dn ${rm_target_ip} after second remove"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  if ! check_region_object_migrated; then
    let rm_fail_flag++
    return 1
  fi

  if [[ ${first_remove_failed_as_expected} -eq 1 ]]; then
    rm_result_state="first_failed_second_succeeded"
  else
    rm_result_state="unexpected"
  fi
  log "remove datanode finished with status=${rm_result_state}"
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
              log "benchmark ${workload} exited before producing final result: ${bm_file}"
              if [[ -f "${bm_file}" ]]; then
                tail -n 40 "${bm_file}"
              fi
              append_warn "benchmark ${workload} exited before producing final result"
              reported_exit_workloads="${reported_exit_workloads} ${workload}"
              let fail_flag++
            fi
          fi
          ;;
        3)
          finished_num=$((finished_num + 1))
          fail_detected=1
          if [[ " ${reported_error_workloads} " != *" ${workload} "* ]]; then
            log "benchmark output has errors: ${bm_file}"
            grep -E "${benchmark_error_pattern}" "${bm_file}" | tail -n 20
            append_warn "benchmark ${workload} output contains execution errors"
            reported_error_workloads="${reported_error_workloads} ${workload}"
            let fail_flag++
          fi
          ;;
        *)
          fail_detected=1
          if [[ " ${reported_exit_workloads} " != *" ${workload} "* ]]; then
            log "benchmark ${workload} returned unexpected status ${check_rc}: ${bm_file}"
            append_warn "benchmark ${workload} returned unexpected status ${check_rc}"
            reported_exit_workloads="${reported_exit_workloads} ${workload}"
            let fail_flag++
          fi
          ;;
      esac
    done

    if [[ ${finished_num} -eq ${workload_count} ]]; then
      if [[ ${fail_detected} -eq 0 ]]; then
        return 0
      fi
      return 1
    fi

    if (( $(date +%s) - start_time > max_wait )); then
      log "benchmark running too long"
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

  if [[ "${v_consensus}" == "IoTConsensusV2" ]]; then
    metric_name="iot_consensus_v2"
    server_name="IoTConsensusV2ServerImpl"
  fi

  wait_start_time=$(date +%s)

  run_cli_sql "${query_ip}" tree "show datanodes;" "${cur_dir}/sync_running_datanodes.out" 3600
  awk -F '|' '/Running/ {gsub(/ /, "", $4); print $4}' "${cur_dir}/sync_running_datanodes.out" | sort -u > "${cur_dir}/sync_running_datanodes_ips.out"
  while read -r ip
  do
    [[ -z "${ip}" ]] && continue
    expected_count=$((expected_count + 1))
    [[ -n "${instance_regex}" ]] && instance_regex="${instance_regex}|"
    instance_regex="${instance_regex}${ip//./[.]}(:[0-9]+)?"
  done < "${cur_dir}/sync_running_datanodes_ips.out"

  if [[ ${expected_count} -eq 0 ]]; then
    log "no running datanodes found when waiting sync"
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
    local response_file="${cur_dir}/sync_lag_response.json"
    local response_status=""
    local parse_rc=0
    local non_zero_num

    now=$(date +%s)
    if (( now - wait_start_time > max_wait_seconds )); then
      log "wait sync lag timeout"
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
    run_cli_sql "${query_host}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600
    running_count=$(grep "${dn_ip}|" "${cur_dir}/show_datanodes.out" | grep Running | wc -l)
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
    run_cli_sql "${query_host}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600
    running_count=$(grep "${dn_ip}|" "${cur_dir}/show_datanodes.out" | grep Running | wc -l)
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

  ssh "${u_name}@${dn_ip}" "source /etc/profile; cd ${db_dir}; sudo ./sbin/stop-datanode.sh"
}

start_remote_datanode() {
  local dn_ip=$1
  local start_time

  start_time=$(date +%s)
  ssh "${u_name}@${dn_ip}" "source /etc/profile; cd ${db_dir}; sudo ./sbin/start-datanode.sh -H ${db_dir}/dn_${start_time}_heapdump.hprof > /dev/null 2>&1 &"
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

normalize_object_query_result() {
  local src_file=$1
  local dst_file=$2
  local tmp_file="${dst_file}.tmp"

  # OBJECT payloads can be very large; hash the normalized result instead of sorting raw values.
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
    sed -n '1,40p' "${raw_file}"
    let fail_flag++
    return 1
  fi
  normalize_query_result "${raw_file}" "${norm_file}"
}

compare_query_result() {
  local base_file=$1
  local check_file=$2
  local reason=$3

  if ! diff -u "${base_file}" "${check_file}" > "${cur_dir}/tmp_diff.out" 2>&1; then
    append_warn "${reason}"
    log "${reason}"
    sed -n '1,40p' "${cur_dir}/tmp_diff.out"
    let fail_flag++
    return 1
  fi
  return 0
}

capture_consistency_baseline() {
  capture_query_result "${query_ip}" tree "${query_tree_sql}" "${cur_dir}/q_all_online_tree.out" "${cur_dir}/q_all_online_tree.norm" || return 1
  capture_query_result "${query_ip}" table "${query_table_base_sql}" "${cur_dir}/q_all_online_tab1.out" "${cur_dir}/q_all_online_tab1.norm" || return 1
  capture_query_result "${query_ip}" table "${query_table_view_sql}" "${cur_dir}/q_all_online_tab2.out" "${cur_dir}/q_all_online_tab2.norm" || return 1
  capture_query_result "${query_ip}" table "${query_table_base_object_sql}" "${cur_dir}/q_all_online_obj_tab1.out" "${cur_dir}/q_all_online_obj_tab1.norm" || return 1
  capture_query_result "${query_ip}" table "${query_table_view_object_sql}" "${cur_dir}/q_all_online_obj_tab2.out" "${cur_dir}/q_all_online_obj_tab2.norm" || return 1
}

choose_query_host() {
  local stop_dn_ip=$1
  awk -v stop_ip="${stop_dn_ip}" '$0 != stop_ip {print; exit}' "${cur_dir}/running_datanodes.txt"
}

check_data_consistent() {
  local stop_dn_ip
  local query_host
  local v_ip

  if ! capture_consistency_baseline; then
    return 1
  fi
  run_cli_sql "${query_ip}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600
  awk -F '|' '/Running/ {gsub(/ /, "", $4); print $4}' "${cur_dir}/show_datanodes.out" | sort -u > "${cur_dir}/running_datanodes.txt"

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
    capture_query_result "${query_host}" tree "${query_tree_sql}" "${cur_dir}/q_stop_ip${v_ip}_tree.out" "${cur_dir}/q_stop_ip${v_ip}_tree.norm" || return 1
    capture_query_result "${query_host}" table "${query_table_base_sql}" "${cur_dir}/q_stop_ip${v_ip}_tab1.out" "${cur_dir}/q_stop_ip${v_ip}_tab1.norm" || return 1
    capture_query_result "${query_host}" table "${query_table_view_sql}" "${cur_dir}/q_stop_ip${v_ip}_tab2.out" "${cur_dir}/q_stop_ip${v_ip}_tab2.norm" || return 1
    capture_query_result "${query_host}" table "${query_table_base_object_sql}" "${cur_dir}/q_stop_ip${v_ip}_obj_tab1.out" "${cur_dir}/q_stop_ip${v_ip}_obj_tab1.norm" || return 1
    capture_query_result "${query_host}" table "${query_table_view_object_sql}" "${cur_dir}/q_stop_ip${v_ip}_obj_tab2.out" "${cur_dir}/q_stop_ip${v_ip}_obj_tab2.norm" || return 1

    compare_query_result "${cur_dir}/q_all_online_tree.norm" "${cur_dir}/q_stop_ip${v_ip}_tree.norm" "tree query result differs when ${stop_dn_ip} is down"
    compare_query_result "${cur_dir}/q_all_online_tab1.norm" "${cur_dir}/q_stop_ip${v_ip}_tab1.norm" "table base query result differs when ${stop_dn_ip} is down"
    compare_query_result "${cur_dir}/q_all_online_tab2.norm" "${cur_dir}/q_stop_ip${v_ip}_tab2.norm" "table writable view query result differs when ${stop_dn_ip} is down"
    compare_query_result "${cur_dir}/q_all_online_obj_tab1.norm" "${cur_dir}/q_stop_ip${v_ip}_obj_tab1.norm" "table base object query result differs when ${stop_dn_ip} is down"
    compare_query_result "${cur_dir}/q_all_online_obj_tab2.norm" "${cur_dir}/q_stop_ip${v_ip}_obj_tab2.norm" "table writable view object query result differs when ${stop_dn_ip} is down"

    start_remote_datanode "${stop_dn_ip}"
    if ! wait_datanode_running "${query_host}" "${stop_dn_ip}" 300; then
      append_warn "failed to restart ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi
    if ! wait_for_monitor_sync_completion 120 360000; then
      return 1
    fi
  done < "${cur_dir}/running_datanodes.txt"

  return 0
}

check_log() {
  local v_npe
  local v_cn_err1
  local v_cn_err2
  local v_cn_err_total
  local v_err
  local v_err2
  local v_err3
  local v_err4
  local v_err5
  local v_err6
  local v_err7
  local v_err8
  local v_err9
  local v_err10
  local v_err11
  local v_err12
  local v_err13
  local v_err14
  local v_dn_total_err

  exec 3<"${nodeinfo_dir}/confignode.txt"
  while read -r line <&3
  do
    ssh "${u_name}@${line}" "gunzip -f ${db_dir}/logs/*confignode*all*.gz 2>/dev/null || true"
    v_npe=$(ssh "${u_name}@${line}" "grep NullPointer ${db_dir}/logs/*confignode*all* | wc -l")
    v_cn_err1=$(ssh "${u_name}@${line}" "grep BufferUnderflowException ${db_dir}/logs/*confignode*all* | wc -l")
    v_cn_err2=$(ssh "${u_name}@${line}" "grep \"but return HAS_MORE_STATE\" ${db_dir}/logs/*confignode*all* | wc -l")
    if [[ ${v_npe} -gt 0 ]]; then
      let fail_flag++
      append_warn "CN NPE"
      log "CN ${line} NullPointer : ${v_npe}"
    fi
    v_cn_err_total=$((v_cn_err1 + v_cn_err2))
    if [[ ${v_cn_err_total} -gt 0 ]]; then
      let fail_flag++
      append_warn "CN HAS_MORE_STATE"
      log "CN ${line} has error: ${v_cn_err_total}"
    fi
  done
  exec 3<&-

  exec 3<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&3
  do
    ssh "${u_name}@${line}" "gunzip -f ${db_dir}/logs/*datanode*all*.gz 2>/dev/null || true"
    v_npe=$(ssh "${u_name}@${line}" "grep NullPointer ${db_dir}/logs/*datanode*all* | wc -l")
    v_err=$(ssh "${u_name}@${line}" "grep CompactionTableSchemaNotMatchException ${db_dir}/logs/*datanode*all* | wc -l")
    v_err2=$(ssh "${u_name}@${line}" "grep \"has overlapped data\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err3=$(ssh "${u_name}@${line}" "grep \"which should be later than the last time\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err4=$(ssh "${u_name}@${line}" "grep \"DataTypeInconsistentException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err5=$(ssh "${u_name}@${line}" "grep \"ArrayIndexOutOfBoundsException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err6=$(ssh "${u_name}@${line}" "grep \"Alter timeseries .* data type from null to\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err7=$(ssh "${u_name}@${line}" "grep \"StatisticsClassException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err8=$(ssh "${u_name}@${line}" "grep \"BufferUnderflowException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err9=$(ssh "${u_name}@${line}" "grep \"NegativeArraySizeException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err10=$(ssh "${u_name}@${line}" "grep \"is not in tsFileMetaData\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err11=$(ssh "${u_name}@${line}" "grep \"The memory cost to be released is larger\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err12=$(ssh "${u_name}@${line}" "grep \"tsfile error\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err13=$(ssh "${u_name}@${line}" "grep \"which has not released all memory\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err14=$(ssh "${u_name}@${line}" "grep \"Error while reading timeseries metadata\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_dn_total_err=$((v_err + v_err2 + v_err3 + v_err4 + v_err5 + v_err6 + v_err7 + v_err8 + v_err9 + v_err10 + v_err11 + v_err12 + v_err13 + v_err14))
    if [[ ${v_npe} -gt 0 ]]; then
      let fail_flag++
      append_warn "DN NPE"
      log "DN ${line} NullPointer : ${v_npe}"
    fi
    if [[ ${v_dn_total_err} -gt 0 ]]; then
      let fail_flag++
      append_warn "DN unexp log"
      log "DN ${line} has error: ${v_dn_total_err}"
    fi
  done
  exec 3<&-
}

backup_logs() {
  local case_name=${SCRIPT_NAME%.sh}
  local backup_time

  backup_time=$(date +"%Y_%m_%d_%H_%M_%S")
  if ! sh -x "${clean_env_dir}/backup_cluster_logs.sh" "${case_name}" "${backup_time}"; then
    append_warn "backup cluster logs failed"
    let fail_flag++
    return 1
  fi
  return 0
}

write_test_result() {
  local test_end_sec
  local test_elp_sec
  local tc_res=true
  local warn_message_sql

  test_end_sec=$(date +%s)
  test_elp_sec=$((test_end_sec - test_begin_sec))
  if [[ ${fail_flag} -ne 0 ]]; then
    tc_res=false
  fi
  warn_message_sql=${v_warnMessage//\'/\'\'}

  if [[ "${tc_res}" = true ]]; then
    echo "${SCRIPT_NAME} : pass" >> "${res_file}"
  else
    echo "${SCRIPT_NAME} : fail"
    echo "warn_message=${v_warnMessage}"
    echo "${SCRIPT_NAME} : fail" >> "${res_file}"
  fi

  "${cli_dir}/sbin/start-cli.sh" -h "${testcase_res_db}" -p "${testcase_res_port}" -pw "${res_root_pw}" -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time,warnMsg)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec},'${warn_message_sql}');"
}

testcase() {
  local benchmark_start_sec
  local metadata_ready=1

  start_db
  create_benchmark_users
  prepare_benchmark_workdirs
  benchmark_start_sec=$(date +%s)
  start_benchmarks

  if ! wait_benchmark_objects_ready 900; then
    log "benchmark objects were not ready within 900s"
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

  if [[ ${metadata_ready} -eq 1 ]]; then
    wait_until_remove_time "${benchmark_start_sec}"
    remove_datanode_under_load
  fi

  wait_benchmarks_finish 43200
  wait_for_monitor_sync_completion 120 360000

  if [[ ${metadata_ready} -eq 1 ]]; then
    check_data_consistent
  else
    append_warn "replica consistency check skipped because benchmark metadata was not ready"
  fi

  sh -x "${clean_env_dir}/stop_cluster.sh"
  check_log
  backup_logs
}

testcase
write_test_result

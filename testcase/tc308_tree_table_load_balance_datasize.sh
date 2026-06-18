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

clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
res_file="${cur_dir}/../test_result/res_${v_cur_db}.out"

db_sys_admin=root
res_root_pw=TimechoDB@2021
ssl_str=""

cn_num=3
dn_num=4
head -n "${dn_num}" "${nodeinfo_dir}/total_datanode.txt" > "${nodeinfo_dir}/datanode.txt"
head -n "${dn_num}" "${nodeinfo_dir}/total_datanode_port.txt" > "${nodeinfo_dir}/datanode_port.txt"
total_node_num=$((cn_num + dn_num))

seed_cn_ip=$(head -1 "${nodeinfo_dir}/confignode.txt"):10710
query_ip=$(head -1 "${nodeinfo_dir}/datanode.txt")

tc_num=$(echo "${SCRIPT_NAME}" | awk -F '_' '{print $1}' | awk -F 'tc' '{print $2}')
testcase_ip=$(grep '^test_ip=' "${conf_file}" | awk -F '.' '{print $4}')
test_begin_sec=$(date +%s)

run_timestamp=$(date +'%Y_%m_%d_%H_%M_%S')
run_artifact_dir="${cur_dir}/${SCRIPT_NAME%.*}_${run_timestamp}"
log_file="${run_artifact_dir}/run.log"

bm_dir="${cur_dir}/../benchmark/bm_20260519_writeview_v20"
bm_case_root="${bm_dir}/load_balance"
bm_work_root="${run_artifact_dir}/bm_work_${tc_num}_${test_begin_sec}"
bm_log_root="${bm_work_root}/logs"
benchmark_error_pattern="Execution fail:|Failed to do |StatementExecutionException|WorkloadException|There is not enough memory to execute current fragment instance|Connection error"

table_base_workload="conf_tab1"
table_view_workload="conf_tab2"
all_workloads="${table_base_workload} ${table_view_workload}"

table_db_name="usr_sod0"
table_base_name=""
table_view_name=""
table_base_object_col=""
table_view_object_col=""
query_table_base_sql=""
query_table_view_sql=""
query_table_base_object_sql=""
query_table_view_object_sql=""

fail_flag=0
v_warnMessage=""

default_schema_region_group_num_per_database=1
default_data_region_group_num_per_database=12

target_skew_size_diff_pct=35
target_balance_size_diff_pct=20
max_skew_rounds=6
migrations_empty_streak_target=5
migrations_poll_interval_seconds=10

skew_heavy_dn1=""
skew_heavy_dn2=""
skew_light_dn1=""
skew_light_dn2=""

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
  set_sys_conf "${line}" "${db_dir}" ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
  set_sys_conf "${line}" "${db_dir}" ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
  set_sys_conf "${line}" "${db_dir}" ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=${default_schema_region_group_num_per_database}"
  set_sys_conf "${line}" "${db_dir}" ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=${default_data_region_group_num_per_database}"
}

configure_one_datanode() {
  local line=$1
  ssh -n "${u_name}@${line}" "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"20G\"/g' ${db_dir}/conf/datanode-env.sh"
  ssh -n "${u_name}@${line}" "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
  set_sys_conf "${line}" "${db_dir}" ".*dn_seed_config_node=.*" "dn_seed_config_node=${seed_cn_ip}"
  set_sys_conf "${line}" "${db_dir}" ".*dn_internal_address=.*" "dn_internal_address=${line}"
  set_sys_conf "${line}" "${db_dir}" ".*dn_rpc_address=.*" "dn_rpc_address=${line}"
  set_sys_conf "${line}" "${db_dir}" ".*dn_metric_reporter_list=.*" "dn_metric_reporter_list=PROMETHEUS"
  set_sys_conf "${line}" "${db_dir}" ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=536870912"
  set_sys_conf "${line}" "${db_dir}" ".*schema_replication_factor=.*" "schema_replication_factor=3"
  set_sys_conf "${line}" "${db_dir}" ".*data_replication_factor=.*" "data_replication_factor=2"
  set_sys_conf "${line}" "${db_dir}" ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
  set_sys_conf "${line}" "${db_dir}" ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
  set_sys_conf "${line}" "${db_dir}" ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=${default_schema_region_group_num_per_database}"
  set_sys_conf "${line}" "${db_dir}" ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=${default_data_region_group_num_per_database}"
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
  run_cli_sql "${query_ip}" table "GRANT ALL TO USER santos;" "${run_artifact_dir}/grant_santos.out" 300
  run_cli_sql "${query_ip}" tree "CREATE USER rainer '${bm_conn_pw}';" "${run_artifact_dir}/create_rainer.out" 300
  run_cli_sql "${query_ip}" table "GRANT ALL TO USER rainer;" "${run_artifact_dir}/grant_rainer.out" 300
}

prepare_benchmark_workdirs() {
  local start_time_str
  local workload

  rm -rf "${bm_work_root}"
  mkdir -p "${bm_log_root}"
  start_time_str=$(date +"%Y-%m-%dT%H:%M:%S%:z")

  for workload in ${all_workloads}
  do
    cp -rp "${bm_case_root}/${workload}" "${bm_work_root}/${workload}"
    if grep -q '^START_TIME=' "${bm_work_root}/${workload}/config.properties"; then
      sed -i "s/^START_TIME=.*/START_TIME=${start_time_str}/g" "${bm_work_root}/${workload}/config.properties"
    else
      printf '\nSTART_TIME=%s\n' "${start_time_str}" >> "${bm_work_root}/${workload}/config.properties"
    fi
  done
}

start_benchmarks() {
  local workload
  log "start benchmark workloads: ${all_workloads}"
  for workload in ${all_workloads}
  do
    nohup sh -x "${bm_dir}/benchmark.sh" -cf "${bm_work_root}/${workload}" > "${bm_log_root}/${workload}.out" 2>&1 &
    echo $! > "${bm_log_root}/${workload}.pid"
  done
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
  local workload_total=2

  start_time=$(date +%s)
  while true
  do
    finished_num=0
    for workload in ${all_workloads}
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

    if [[ ${finished_num} -eq ${workload_total} ]]; then
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

wait_benchmark_objects_ready() {
  local timeout_sec=${1:-900}
  local start_time
  local table_ok=0
  local view_ok=0

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${query_ip}" table "show tables details from ${table_db_name};" "${run_artifact_dir}/show_tables_details.out" 3600
    if grep -Eq 'BASE TABLE' "${run_artifact_dir}/show_tables_details.out"; then
      table_ok=1
    fi
    if grep -Eq 'WRITABLE VIEW' "${run_artifact_dir}/show_tables_details.out"; then
      view_ok=1
    fi

    if [[ ${table_ok} -eq 1 && ${view_ok} -eq 1 ]]; then
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

  query_table_base_object_sql="select D_DATETIME,device_id,length(read_object(${table_base_object_col})) from ${table_db_name}.${table_base_name} limit 20;"
  query_table_view_object_sql="select D_DATETIME,device_id,length(read_object(${table_view_object_col})) from ${table_db_name}.${table_view_name} limit 20;"
  return 0
}

refresh_running_datanodes() {
  if ! run_cli_sql "${query_ip}" tree "show datanodes;" "${run_artifact_dir}/show_datanodes.out" 3600; then
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
        print node_id "," rpc_address
      }
    }
  ' "${run_artifact_dir}/show_datanodes.out" > "${run_artifact_dir}/running_datanodes.txt"
  return 0
}

collect_regions_table() {
  local stage=$1
  local out_file="${run_artifact_dir}/${stage}_table_regions.out"

  run_cli_sql "${query_ip}" table "show regions;" "${out_file}" 3600
  trim_file_crlf "${out_file}"
  check_cli_success "${out_file}" "${stage} table show regions" || return 1
  return 0
}

show_migrations_is_empty_table() {
  local stage=$1
  local out_file="${run_artifact_dir}/${stage}_table_migrations.out"

  run_cli_sql "${query_ip}" table "show migrations;" "${out_file}" 3600
  trim_file_crlf "${out_file}"
  if grep -Eq "Exception|ERROR|Error" "${out_file}"; then
    append_warn "table show migrations failed"
    let fail_flag++
    return 1
  fi
  if grep -Eq '^Empty set' "${out_file}"; then
    return 0
  fi
  return 2
}

show_table_regions_has_active_migration() {
  local stage=$1
  local out_file="${run_artifact_dir}/${stage}_table_regions.out"

  run_cli_sql "${query_ip}" table "show regions;" "${out_file}" 3600
  trim_file_crlf "${out_file}"
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

wait_for_table_migrations_completion() {
  local stage=$1
  local timeout_seconds=${2:-7200}
  local begin_time
  local empty_rounds=0
  begin_time=$(date +%s)

  while true
  do
    local elapsed_seconds
    elapsed_seconds=$(( $(date +%s) - begin_time ))

    show_migrations_is_empty_table "${stage}"
    local mig_rc=$?
    if [[ "${mig_rc}" -eq 1 ]]; then
      return 1
    fi
    if [[ "${mig_rc}" -eq 0 ]]; then
      empty_rounds=$((empty_rounds + 1))
    else
      empty_rounds=0
    fi

    show_table_regions_has_active_migration "${stage}"
    local region_rc=$?
    if [[ "${region_rc}" -eq 1 ]]; then
      return 1
    fi

    if [[ "${empty_rounds}" -ge "${migrations_empty_streak_target}" && "${region_rc}" -eq 2 ]]; then
      return 0
    fi
    if [[ "${timeout_seconds}" -gt 0 && "${elapsed_seconds}" -gt "${timeout_seconds}" ]]; then
      append_warn "${stage} not completed"
      let fail_flag++
      return 1
    fi
    sleep "${migrations_poll_interval_seconds}"
  done
}

run_table_maintenance_sql() {
  local sql=$1
  local out_file=$2
  local desc=$3

  run_cli_sql "${query_ip}" table "${sql}" "${out_file}" 3600
  check_cli_success "${out_file}" "${desc}" || return 1
  return 0
}

size_to_bytes_awk='
  function trim(s) {
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    return s
  }
  function size_to_bytes(raw, parts, value, unit) {
    raw = trim(raw)
    if (raw == "" || raw == "Unknown" || raw == "NaN") {
      return 0
    }
    split(raw, parts, /[[:space:]]+/)
    value = parts[1] + 0
    unit = toupper(parts[2])
    if (unit == "" || unit == "B") return value
    if (unit == "KB") return value * 1024
    if (unit == "MB") return value * 1024 * 1024
    if (unit == "GB") return value * 1024 * 1024 * 1024
    if (unit == "TB") return value * 1024 * 1024 * 1024 * 1024
    return value
  }
'

summarize_table_regions_by_dn() {
  local stage=$1
  local region_file="${run_artifact_dir}/${stage}_table_regions.out"
  local summary_file="${run_artifact_dir}/${stage}_table_region_balance_summary.csv"

  awk -F "|" "${size_to_bytes_awk}
    BEGIN { OFS=\",\" }
    FNR == NR {
      if (\$1 ~ /^[0-9]+$/ && \$2 != \"\") {
        order[++dn_num] = \$1
        dn_ip[\$1] = \$2
      }
      next
    }
    /^\|/ {
      region_id = trim(\$2)
      type = trim(\$3)
      status = trim(\$4)
      database = trim(\$5)
      dn_id = trim(\$7)
      role = trim(\$11)
      size_raw = trim(\$13)
      if (region_id !~ /^[0-9]+$/ || type != \"DataRegion\" || status != \"Running\" || database != \"${table_db_name}\" || dn_id == \"\") {
        next
      }
      count[dn_id]++
      if (role == \"Leader\") {
        leader[dn_id]++
      }
      size_bytes[dn_id] += size_to_bytes(size_raw)
    }
    END {
      print \"DataNodeId,RpcAddress,RegionCount,LeaderCount,SizeBytes\"
      for (i = 1; i <= dn_num; i++) {
        dn_id = order[i]
        print dn_id, dn_ip[dn_id], count[dn_id] + 0, leader[dn_id] + 0, size_bytes[dn_id] + 0
      }
    }
  " "${run_artifact_dir}/running_datanodes.txt" "${region_file}" > "${summary_file}"
}

evaluate_table_region_balance() {
  local stage=$1
  local summary_file="${run_artifact_dir}/${stage}_table_region_balance_summary.csv"
  local result_file="${run_artifact_dir}/${stage}_table_region_balance_eval.out"

  awk -F ',' '
    NR == 1 { next }
    {
      included++
      region_count = $3 + 0
      leader_count = $4 + 0
      size_bytes = $5 + 0
      if (included == 1) {
        min_region = max_region = region_count
        min_leader = max_leader = leader_count
        min_size = max_size = size_bytes
      }
      if (region_count < min_region) min_region = region_count
      if (region_count > max_region) max_region = region_count
      if (leader_count < min_leader) min_leader = leader_count
      if (leader_count > max_leader) max_leader = leader_count
      if (size_bytes < min_size) min_size = size_bytes
      if (size_bytes > max_size) max_size = size_bytes
      total_size += size_bytes
    }
    END {
      avg_size = (included > 0) ? (total_size / included) : 0
      size_diff_pct = (avg_size > 0) ? ((max_size - min_size) * 100 / avg_size) : 0
      printf("included_count=%d\n", included)
      printf("region_count_diff=%d\n", max_region - min_region)
      printf("leader_count_diff=%d\n", max_leader - min_leader)
      printf("size_diff_pct=%.2f\n", size_diff_pct)
    }
  ' "${summary_file}" > "${result_file}"
}

get_balance_metric() {
  local stage=$1
  local key=$2
  awk -F '=' -v k="${key}" '$1 == k {print $2}' "${run_artifact_dir}/${stage}_table_region_balance_eval.out"
}

capture_table_region_balance_snapshot() {
  local stage=$1
  refresh_running_datanodes || return 1
  collect_regions_table "${stage}" || return 1
  summarize_table_regions_by_dn "${stage}" || return 1
  evaluate_table_region_balance "${stage}" || return 1
  cat "${run_artifact_dir}/${stage}_table_region_balance_eval.out" >> "${log_file}"
  return 0
}

select_skew_targets() {
  local stage=$1
  local summary_file="${run_artifact_dir}/${stage}_table_region_balance_summary.csv"
  local sorted_file="${run_artifact_dir}/${stage}_dn_sizes_sorted.csv"

  awk -F ',' 'NR > 1 {print $1 "," $2 "," $5}' "${summary_file}" | sort -t ',' -k3,3nr > "${sorted_file}"
  if [[ $(wc -l < "${sorted_file}") -lt 4 ]]; then
    append_warn "need at least 4 running datanodes to create size skew"
    let fail_flag++
    return 1
  fi

  skew_heavy_dn1=$(sed -n '1p' "${sorted_file}" | awk -F ',' '{print $1}')
  skew_heavy_dn2=$(sed -n '2p' "${sorted_file}" | awk -F ',' '{print $1}')
  skew_light_dn1=$(tail -n 1 "${sorted_file}" | awk -F ',' '{print $1}')
  skew_light_dn2=$(tail -n 2 "${sorted_file}" | head -n 1 | awk -F ',' '{print $1}')
  return 0
}

build_region_member_map() {
  local stage=$1
  local region_file="${run_artifact_dir}/${stage}_table_regions.out"
  local map_file="${run_artifact_dir}/${stage}_table_region_members.csv"

  awk -F "|" "${size_to_bytes_awk}
    /^\|/ {
      region_id = trim(\$2)
      type = trim(\$3)
      status = trim(\$4)
      database = trim(\$5)
      dn_id = trim(\$7)
      size_raw = trim(\$13)
      if (region_id !~ /^[0-9]+$/ || type != \"DataRegion\" || status != \"Running\" || database != \"${table_db_name}\" || dn_id == \"\") {
        next
      }
      if (!(region_id in size_bytes)) {
        size_bytes[region_id] = size_to_bytes(size_raw)
      }
      if (members[region_id] == \"\") {
        members[region_id] = dn_id
      } else if (members[region_id] !~ \"(^| )\" dn_id \"( |$)\") {
        members[region_id] = members[region_id] \" \" dn_id
      }
    }
    END {
      for (region_id in members) {
        print region_id \",\" size_bytes[region_id] \",\" members[region_id]
      }
    }
  " "${region_file}" > "${map_file}"
}

select_large_region_candidate() {
  local map_file=$1
  local source_dn=$2
  local target_dn=$3

  awk -F ',' -v source_dn="${source_dn}" -v target_dn="${target_dn}" '
    function has_member(list, target, n, arr, i) {
      n = split(list, arr, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (arr[i] == target) {
          return 1
        }
      }
      return 0
    }
    has_member($3, source_dn) && !has_member($3, target_dn) {
      print $1 "," $2
    }
  ' "${map_file}" | sort -t ',' -k2,2nr | head -n 1 | awk -F ',' '{print $1}'
}

select_small_region_candidate() {
  local map_file=$1
  local source_dn=$2
  local target_dn=$3
  local exclude_region=$4

  awk -F ',' -v source_dn="${source_dn}" -v target_dn="${target_dn}" -v exclude_region="${exclude_region}" '
    function has_member(list, target, n, arr, i) {
      n = split(list, arr, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (arr[i] == target) {
          return 1
        }
      }
      return 0
    }
    $1 != exclude_region && has_member($3, source_dn) && !has_member($3, target_dn) {
      print $1 "," $2
    }
  ' "${map_file}" | sort -t ',' -k2,2n | head -n 1 | awk -F ',' '{print $1}'
}

get_region_size_bytes() {
  local map_file=$1
  local region_id=$2
  awk -F ',' -v region_id="${region_id}" '$1 == region_id {print $2}' "${map_file}" | head -n 1
}

migrate_one_table_region() {
  local region_id=$1
  local from_dn_id=$2
  local to_dn_id=$3
  local stage=$4
  local out_file="${run_artifact_dir}/${stage}_mig_${region_id}_${from_dn_id}_to_${to_dn_id}.out"

  log "migrate region ${region_id} from ${from_dn_id} to ${to_dn_id}"
  run_table_maintenance_sql "migrate region ${region_id} from ${from_dn_id} to ${to_dn_id};" "${out_file}" "migrate region ${region_id}" || return 1
  wait_for_table_migrations_completion "${stage}_wait_${region_id}_${from_dn_id}_to_${to_dn_id}" 7200 || return 1
  return 0
}

perform_skew_swap() {
  local heavy_dn=$1
  local light_dn=$2
  local stage_prefix=$3
  local map_file="${run_artifact_dir}/${stage_prefix}_table_region_members.csv"
  local large_region
  local small_region
  local large_size
  local small_size

  collect_regions_table "${stage_prefix}" || return 1
  build_region_member_map "${stage_prefix}" || return 1
  large_region=$(select_large_region_candidate "${map_file}" "${light_dn}" "${heavy_dn}")
  if [[ -z "${large_region}" ]]; then
    log "no large region candidate for light_dn=${light_dn} heavy_dn=${heavy_dn}"
    return 1
  fi
  large_size=$(get_region_size_bytes "${map_file}" "${large_region}")
  if ! migrate_one_table_region "${large_region}" "${light_dn}" "${heavy_dn}" "${stage_prefix}_large"; then
    return 1
  fi

  collect_regions_table "${stage_prefix}_after_large" || return 1
  build_region_member_map "${stage_prefix}_after_large" || return 1
  map_file="${run_artifact_dir}/${stage_prefix}_after_large_table_region_members.csv"
  small_region=$(select_small_region_candidate "${map_file}" "${heavy_dn}" "${light_dn}" "${large_region}")
  if [[ -z "${small_region}" ]]; then
    append_warn "no small region candidate to swap back after moving large region ${large_region} to dn ${heavy_dn}"
    let fail_flag++
    return 1
  fi
  small_size=$(get_region_size_bytes "${map_file}" "${small_region}")
  if ! migrate_one_table_region "${small_region}" "${heavy_dn}" "${light_dn}" "${stage_prefix}_small"; then
    return 1
  fi

  log "skew swap completed: large region ${large_region} size=${large_size} to heavy dn ${heavy_dn}, small region ${small_region} size=${small_size} to light dn ${light_dn}"
  return 0
}

create_size_skew() {
  local round
  local before_pct
  local progress

  for round in $(seq 1 "${max_skew_rounds}")
  do
    capture_table_region_balance_snapshot "skew_round_${round}_before" || return 1
    before_pct=$(get_balance_metric "skew_round_${round}_before" "size_diff_pct")
    log "skew round ${round} current size_diff_pct=${before_pct}"
    if awk -v diff="${before_pct}" -v target="${target_skew_size_diff_pct}" 'BEGIN { exit (diff >= target) ? 0 : 1 }'; then
      return 0
    fi

    select_skew_targets "skew_round_${round}_before" || return 1
    progress=0
    if perform_skew_swap "${skew_heavy_dn1}" "${skew_light_dn1}" "skew_round_${round}_pair1"; then
      progress=1
    fi
    capture_table_region_balance_snapshot "skew_round_${round}_mid" || return 1
    select_skew_targets "skew_round_${round}_mid" || return 1
    if perform_skew_swap "${skew_heavy_dn2}" "${skew_light_dn2}" "skew_round_${round}_pair2"; then
      progress=1
    fi

    if [[ ${progress} -eq 0 ]]; then
      append_warn "failed to find valid region swap candidates to create size skew"
      let fail_flag++
      return 1
    fi
  done

  capture_table_region_balance_snapshot "after_skew_before_load_balance" || return 1
  before_pct=$(get_balance_metric "after_skew_before_load_balance" "size_diff_pct")
  if awk -v diff="${before_pct}" -v target="${target_skew_size_diff_pct}" 'BEGIN { exit (diff >= target) ? 0 : 1 }'; then
    return 0
  fi

  append_warn "size skew is not obvious enough before load balance: size_diff_pct=${before_pct}, target=${target_skew_size_diff_pct}"
  let fail_flag++
  return 1
}

summary_dn_value() {
  local stage=$1
  local dn_id=$2
  local column_index=$3
  local summary_file="${run_artifact_dir}/${stage}_table_region_balance_summary.csv"
  awk -F ',' -v dn_id="${dn_id}" -v col="${column_index}" 'NR > 1 && $1 == dn_id {print $col}' "${summary_file}" | head -n 1
}

validate_load_balance_effect() {
  local before_pct
  local after_pct
  local before_norm="${run_artifact_dir}/after_skew_before_load_balance_table_regions.normalized.out"
  local after_norm="${run_artifact_dir}/after_load_balance_table_regions.normalized.out"
  local heavy1_before
  local heavy2_before
  local heavy1_after
  local heavy2_after

  before_pct=$(get_balance_metric "after_skew_before_load_balance" "size_diff_pct")
  after_pct=$(get_balance_metric "after_load_balance" "size_diff_pct")
  log "table size diff before load balance=${before_pct} after load balance=${after_pct}"

  if ! awk -v before="${before_pct}" -v after="${after_pct}" 'BEGIN { exit (after < before) ? 0 : 1 }'; then
    append_warn "table region size diff did not improve after load balance: before=${before_pct}, after=${after_pct}"
    let fail_flag++
  fi

  if awk -v after="${after_pct}" -v target="${target_balance_size_diff_pct}" 'BEGIN { exit (after > target) ? 0 : 1 }'; then
    append_warn "table region size diff after load balance is still ${after_pct}%, expected <= ${target_balance_size_diff_pct}%"
    let fail_flag++
  fi

  awk '/^\|/ { sub(/[[:space:]]+$/, "", $0); print }' "${run_artifact_dir}/after_skew_before_load_balance_table_regions.out" > "${before_norm}"
  awk '/^\|/ { sub(/[[:space:]]+$/, "", $0); print }' "${run_artifact_dir}/after_load_balance_table_regions.out" > "${after_norm}"
  if cmp -s "${before_norm}" "${after_norm}"; then
    append_warn "load balance finished but table region topology did not change"
    let fail_flag++
  fi

  heavy1_before=$(summary_dn_value "after_skew_before_load_balance" "${skew_heavy_dn1}" 5)
  heavy2_before=$(summary_dn_value "after_skew_before_load_balance" "${skew_heavy_dn2}" 5)
  heavy1_after=$(summary_dn_value "after_load_balance" "${skew_heavy_dn1}" 5)
  heavy2_after=$(summary_dn_value "after_load_balance" "${skew_heavy_dn2}" 5)

  if ! awk -v b1="${heavy1_before:-0}" -v a1="${heavy1_after:-0}" -v b2="${heavy2_before:-0}" -v a2="${heavy2_after:-0}" 'BEGIN { exit ((a1 < b1) || (a2 < b2)) ? 0 : 1 }'; then
    append_warn "load balance did not reduce size on either heavy dn ${skew_heavy_dn1}/${skew_heavy_dn2}"
    let fail_flag++
  fi

  return 0
}

run_load_balance_phase() {
  run_table_maintenance_sql "LOAD BALANCE;" "${run_artifact_dir}/load_balance.out" "load balance" || return 1
  wait_for_table_migrations_completion "load_balance_wait" 7200 || return 1
  capture_table_region_balance_snapshot "after_load_balance" || return 1
  return 0
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
  local sql=$2
  local raw_file=$3
  local norm_file=$4

  run_cli_sql "${host}" table "${sql}" "${raw_file}" 3600
  if query_output_has_error "${raw_file}"; then
    append_warn "table query execute failed on ${host}"
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
    sed -n '1,40p' "${diff_file}" >> "${log_file}"
    let fail_flag++
    return 1
  fi
  return 0
}

capture_consistency_baseline() {
  capture_query_result "${query_ip}" "${query_table_base_sql}" "${run_artifact_dir}/q_base_exp.out" "${run_artifact_dir}/q_base_exp.norm" || return 1
  capture_query_result "${query_ip}" "${query_table_view_sql}" "${run_artifact_dir}/q_view_exp.out" "${run_artifact_dir}/q_view_exp.norm" || return 1
  capture_query_result "${query_ip}" "${query_table_base_object_sql}" "${run_artifact_dir}/q_obj_base_exp.out" "${run_artifact_dir}/q_obj_base_exp.norm" || return 1
  capture_query_result "${query_ip}" "${query_table_view_object_sql}" "${run_artifact_dir}/q_obj_view_exp.out" "${run_artifact_dir}/q_obj_view_exp.norm" || return 1
  return 0
}

check_final_consistency() {
  capture_query_result "${query_ip}" "${query_table_base_sql}" "${run_artifact_dir}/q_base_act.out" "${run_artifact_dir}/q_base_act.norm" || return 1
  capture_query_result "${query_ip}" "${query_table_view_sql}" "${run_artifact_dir}/q_view_act.out" "${run_artifact_dir}/q_view_act.norm" || return 1
  capture_query_result "${query_ip}" "${query_table_base_object_sql}" "${run_artifact_dir}/q_obj_base_act.out" "${run_artifact_dir}/q_obj_base_act.norm" || return 1
  capture_query_result "${query_ip}" "${query_table_view_object_sql}" "${run_artifact_dir}/q_obj_view_act.out" "${run_artifact_dir}/q_obj_view_act.norm" || return 1

  compare_query_result "${run_artifact_dir}/q_base_exp.norm" "${run_artifact_dir}/q_base_act.norm" "table base query result differs after load balance" || return 1
  compare_query_result "${run_artifact_dir}/q_view_exp.norm" "${run_artifact_dir}/q_view_act.norm" "table writable view query result differs after load balance" || return 1
  compare_query_result "${run_artifact_dir}/q_obj_base_exp.norm" "${run_artifact_dir}/q_obj_base_act.norm" "table base object query result differs after load balance" || return 1
  compare_query_result "${run_artifact_dir}/q_obj_view_exp.norm" "${run_artifact_dir}/q_obj_view_act.norm" "table writable view object query result differs after load balance" || return 1
  return 0
}

stop_cluster() {
  sh -x "${clean_env_dir}/stop_cluster.sh" >> "${log_file}" 2>&1 || true
}

check_log() {
  exec 3<"${nodeinfo_dir}/confignode.txt"
  while read -r line <&3
  do
    ssh "${u_name}@${line}" "gunzip ${db_dir}/logs/*confignode*all* >/dev/null 2>&1 || true"
    local v_npe
    local v_cn_err1
    local v_cn_err2
    v_npe=$(ssh "${u_name}@${line}" "grep NullPointer ${db_dir}/logs/*confignode*all* | wc -l")
    v_cn_err1=$(ssh "${u_name}@${line}" "grep BufferUnderflowException ${db_dir}/logs/*confignode*all* | wc -l")
    v_cn_err2=$(ssh "${u_name}@${line}" "grep 'but return HAS_MORE_STATE' ${db_dir}/logs/*confignode*all* | wc -l")
    if [[ "${v_npe}" -gt 0 || $((v_cn_err1 + v_cn_err2)) -gt 0 ]]; then
      append_warn "confignode log error on ${line}"
      let fail_flag++
    fi
  done
  exec 3<&-

  exec 4<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&4
  do
    ssh "${u_name}@${line}" "gunzip ${db_dir}/logs/*datanode*all* >/dev/null 2>&1 || true"
    local v_npe
    local v_err
    v_npe=$(ssh "${u_name}@${line}" "grep NullPointer ${db_dir}/logs/*datanode*all* | wc -l")
    v_err=$(ssh "${u_name}@${line}" "grep -E 'CompactionTableSchemaNotMatchException|has overlapped data|which should be later than the last time|DataTypeInconsistentException|ArrayIndexOutOfBoundsException|StatisticsClassException|BufferUnderflowException|NegativeArraySizeException|is not in tsFileMetaData|The memory cost to be released is larger' ${db_dir}/logs/*datanode*all* | wc -l")
    if [[ "${v_npe}" -gt 0 || "${v_err}" -gt 0 ]]; then
      append_warn "datanode log error on ${line}"
      let fail_flag++
    fi
  done
  exec 4<&-
}

backup_logs() {
  local case_name=${SCRIPT_NAME%.sh}
  local backup_time
  backup_time=$(date +"%Y_%m_%d_%H_%M_%S")
  sh -x "${clean_env_dir}/backup_cluster_logs.sh" "${case_name}" "${backup_time}" >> "${log_file}" 2>&1 || true
}

write_test_result() {
  local test_end_sec
  local test_elp_sec
  local tc_res=true
  local warn_message_sql=""

  test_end_sec=$(date +%s)
  test_elp_sec=$((test_end_sec - test_begin_sec))
  if [[ ${fail_flag} -ne 0 ]]; then
    tc_res=false
  fi

  if [[ "${tc_res}" = true ]]; then
    echo "${SCRIPT_NAME} : pass" >> "${res_file}"
  else
    echo "${SCRIPT_NAME} : fail" >> "${res_file}"
    if [[ -n "${v_warnMessage}" ]]; then
      echo "${SCRIPT_NAME} : ${v_warnMessage}" >> "${res_file}"
    fi
  fi

  if [[ -n "${v_warnMessage}" ]]; then
    echo "warn_message=${v_warnMessage}"
    warn_message_sql=${v_warnMessage//;/,}
    warn_message_sql=${warn_message_sql//\'/\'\'}
  fi

  "${cli_dir}/sbin/start-cli.sh" -h "${testcase_res_db}" -p "${testcase_res_port}" -pw "${res_root_pw}" -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time,warnMsg)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec},'${warn_message_sql}');" >> "${log_file}" 2>&1 || true
}

main_body() {
  start_db
  create_benchmark_users
  prepare_benchmark_workdirs
  start_benchmarks
  wait_benchmarks_finish 43200 || return 1

  if ! wait_benchmark_objects_ready 900; then
    append_warn "benchmark objects not ready within 900s"
    let fail_flag++
    return 1
  fi
  resolve_table_objects || return 1
  resolve_object_columns || return 1
  capture_consistency_baseline || return 1

  capture_table_region_balance_snapshot "after_data_load" || return 1
  create_size_skew || true
  capture_table_region_balance_snapshot "after_skew_before_load_balance" || return 1
  select_skew_targets "after_skew_before_load_balance" || return 1

  run_load_balance_phase || return 1
  validate_load_balance_effect || return 1
  check_final_consistency || return 1
  return 0
}

main() {
  mkdir -p "${run_artifact_dir}"
  : > "${log_file}"
  log "run artifacts directory: ${run_artifact_dir}"

  main_body || true
  stop_cluster
  check_log
  backup_logs
  write_test_result
}

main "$@"

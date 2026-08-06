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
query_ip2=$(head -2 "${nodeinfo_dir}/datanode.txt" | tail -1)

tc_num=$(echo "${SCRIPT_NAME}" | awk -F '_' '{print $1}' | awk -F 'tc' '{print $2}')
testcase_ip=$(grep '^test_ip=' "${conf_file}" | awk -F '.' '{print $4}')
test_begin_sec=$(date +%s)

bm_dir="/data1/iotdb/testcase/MigrateRegionTest/benchmark/bm_20260508_interval_v20"
bm_case_root="${bm_dir}/remove"
bm_work_root="${cur_dir}/bm_work_${tc_num}_${test_begin_sec}"
bm_log_root="${bm_work_root}/logs"

view_ready=0
fail_flag=0
rm_fail_flag=0
rm_result_state="unknown"
rm_target_ip=""

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
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
    set_sys_conf "${line}" "${db_dir}" ".*cn_metric_level=.*" "cn_metric_level=IMPORTANT"
    set_sys_conf "${line}" "${db_dir}" ".*cn_metric_prometheus_reporter_port=.*" "cn_metric_prometheus_reporter_port=9081"
    set_sys_conf "${line}" "${db_dir}" ".*schema_replication_factor=.*" "schema_replication_factor=3"
    set_sys_conf "${line}" "${db_dir}" ".*data_replication_factor=.*" "data_replication_factor=2"
    set_sys_conf "${line}" "${db_dir}" ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
    set_sys_conf "${line}" "${db_dir}" ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
    set_sys_conf "${line}" "${db_dir}" ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=2"
    set_sys_conf "${line}" "${db_dir}" ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=2"
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
    set_sys_conf "${line}" "${db_dir}" ".*dn_metric_level=.*" "dn_metric_level=IMPORTANT"
    set_sys_conf "${line}" "${db_dir}" ".*dn_metric_prometheus_reporter_port=.*" "dn_metric_prometheus_reporter_port=9091"
    set_sys_conf "${line}" "${db_dir}" ".*schema_replication_factor=.*" "schema_replication_factor=3"
    set_sys_conf "${line}" "${db_dir}" ".*data_replication_factor=.*" "data_replication_factor=2"
    set_sys_conf "${line}" "${db_dir}" ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
    set_sys_conf "${line}" "${db_dir}" ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
    set_sys_conf "${line}" "${db_dir}" ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=2"
    set_sys_conf "${line}" "${db_dir}" ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=2"
    set_sys_conf "${line}" "${db_dir}" ".*datanode_memory_proportion=.*" "datanode_memory_proportion=1:5:1:1:1:1"
  done
  exec 3<&-
}

start_db() {
  clean_env
  head -n "${cn_num}" "${nodeinfo_dir}/total_node.txt" > "${nodeinfo_dir}/confignode.txt"
  set_conf
  sh -x "${prepare_env_dir}/start_cluster.sh" "1" "${total_node_num}"
}

create_benchmark_users() {
  run_cli_sql "${query_ip}" tree "CREATE USER santos '${bm_conn_pw}';" "${cur_dir}/tmp.out" 300
  run_cli_sql "${query_ip}" table "GRANT ALL TO USER santos;" "${cur_dir}/tmp.out" 300
}

prepare_benchmark_databases() {
  run_cli_sql "${query_ip}" tree "create database root.view;" "${cur_dir}/create_root_view_db.out" 300
  if ! grep -Eq 'executed successfully|already been created as database' "${cur_dir}/create_root_view_db.out"; then
    log "failed to prepare root.view database"
    cat "${cur_dir}/create_root_view_db.out"
    let fail_flag++
    return 1
  fi
}

prepare_benchmark_workdirs() {
  rm -rf "${bm_work_root}"
  mkdir -p "${bm_log_root}"

  local bm_host="${query_ip}"
  local workload
  for workload in tree_nonaligned tree_aligned tree_aligned_temp table
  do
    cp -rp "${bm_case_root}/${workload}" "${bm_work_root}/${workload}"
    sed -i "s/^HOST=.*/HOST=${bm_host}/g" "${bm_work_root}/${workload}/config.properties"
    sed -i "s/^LOOP=.*/LOOP=1000/g" "${bm_work_root}/${workload}/config.properties"
    if [[ "${workload}" != "table" ]]; then
      sed -i "s/^USERNAME=.*/USERNAME=root/g" "${bm_work_root}/${workload}/config.properties"
      sed -i "s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/g" "${bm_work_root}/${workload}/config.properties"
    fi
  done
}

start_benchmarks() {
  local workload
  for workload in tree_nonaligned tree_aligned tree_aligned_temp table
  do
    nohup sh -x "${bm_dir}/benchmark.sh" -cf "${bm_work_root}/${workload}" > "${bm_log_root}/${workload}.out" 2>&1 &
    echo $! > "${bm_log_root}/${workload}.pid"
  done
}

wait_view_source_ready() {
  local max_wait=${1:-240}
  local start_time
  local source_device_num

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${query_ip}" tree "show devices root.db.g_0.**;" "${cur_dir}/view_source_devices.out" 3600
    source_device_num=$(grep 'root.db.g_0.' "${cur_dir}/view_source_devices.out" | wc -l)
    if [[ ${source_device_num} -ge 1000 ]]; then
      return 0
    fi

    if (( $(date +%s) - start_time > max_wait )); then
      return 1
    fi
    sleep 10
  done
}

create_tree_view_data() {
  if ! wait_view_source_ready 240; then
    log "root.db benchmark schema did not become ready within 240s"
    let fail_flag++
    return 1
  fi

  run_cli_sql "${query_ip}" tree "create view root.view.\${2}.view_from_\${3}(\${4}) as select * from root.db.**;" "${cur_dir}/create_view.out" 3600
  sleep 3
  run_cli_sql "${query_ip}" tree "show devices root.view.g_0.**;" "${cur_dir}/show_view_devices.out" 3600
  if [[ $(grep 'root.view.g_0.' "${cur_dir}/show_view_devices.out" | wc -l) -gt 0 ]]; then
    view_ready=1
    return 0
  fi

  log "failed to create root.view view data"
  cat "${cur_dir}/create_view.out"
  let fail_flag++
  return 1
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
  local timeout_sec=${3:-1800}
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

wait_remove_region_settled() {
  local host=$1
  local dn_ip=$2
  local timeout_sec=${3:-3600}
  local start_time
  local stable_zero=0
  local tree_num
  local table_num
  local total_num
  local dn_num
  local dn_status

  start_time=$(date +%s)
  while true
  do
    run_cli_sql "${host}" tree "show regions;" "${cur_dir}/show_regions_tree.out" 3600
    run_cli_sql "${host}" table "show regions;" "${cur_dir}/show_regions_table.out" 3600
    run_cli_sql "${host}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600

    tree_num=$(grep -E 'Adding|Removing' "${cur_dir}/show_regions_tree.out" | wc -l)
    table_num=$(grep -E 'Adding|Removing' "${cur_dir}/show_regions_table.out" | wc -l)
    total_num=$((tree_num + table_num))
    dn_num=$(grep "${dn_ip}|" "${cur_dir}/show_datanodes.out" | wc -l)
    dn_status=$(grep "${dn_ip}|" "${cur_dir}/show_datanodes.out" | awk -F '|' '{gsub(" ","",$3);print $3}' | tail -1)

    if [[ ${total_num} -eq 0 ]]; then
      stable_zero=$((stable_zero + 1))
    else
      stable_zero=0
    fi

    if [[ ${stable_zero} -ge 3 ]]; then
      if [[ ${dn_num} -eq 0 ]]; then
        rm_result_state="success"
        return 0
      fi
      rm_result_state="${dn_status:-present}"
      return 1
    fi

    if (( $(date +%s) - start_time > timeout_sec )); then
      rm_result_state="timeout"
      return 1
    fi
    sleep 10
  done
}

remove_datanode_under_load() {
  local rm_dn_id

  rm_target_ip=$(tail -1 "${nodeinfo_dir}/datanode.txt")
  run_cli_sql "${query_ip}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600
  rm_dn_id=$(grep "${rm_target_ip}|" "${cur_dir}/show_datanodes.out" | awk -F '|' '{gsub(" ","",$2);print $2}' | tail -1)

  if [[ -z "${rm_dn_id}" ]]; then
    log "failed to locate remove target id for ${rm_target_ip}"
    let fail_flag++
    return 1
  fi

  ssh "${u_name}@${rm_target_ip}" "source /etc/profile; cd ${db_dir}; sudo ./sbin/stop-datanode.sh"
  if ! wait_datanode_status "${query_ip}" "${rm_target_ip}" "Unknown" 300; then
    log "datanode ${rm_target_ip} did not become Unknown before remove"
    let fail_flag++
  fi

  run_cli_sql "${query_ip}" tree "remove datanode ${rm_dn_id};" "${cur_dir}/remove_datanode.out" 3600
  if [[ $(grep -i 'successfully' "${cur_dir}/remove_datanode.out" | wc -l) -eq 0 ]]; then
    log "remove datanode submit output is not success"
    cat "${cur_dir}/remove_datanode.out"
    let fail_flag++
    let rm_fail_flag++
  fi

  if ! wait_remove_region_settled "${query_ip}" "${rm_target_ip}" 3600; then
    log "remove datanode settled with status=${rm_result_state}"
    let fail_flag++
    let rm_fail_flag++
    return 1
  fi

  log "remove datanode finished with status=${rm_result_state}"
  return 0
}

submit_remove_datanode() {
  local target_ip=$1
  local node_id=$2
  local output_file=$3

  run_cli_sql "${target_ip}" tree "remove datanode ${node_id};" "${output_file}" 3600
}

remove_two_datanodes_concurrently() {
  local target1=$1
  local target2=$2
  local id1
  local id2
  local out1="${cur_dir}/remove_concurrent_${target1##*.}.out"
  local out2="${cur_dir}/remove_concurrent_${target2##*.}.out"
  local pid1
  local pid2
  local rc1
  local rc2
  local success1=0
  local success2=0
  local success_count
  local success_target
  local failed_target
  local failed_output
  local jps_num
  local tsfile_num
  local sample

  run_cli_sql "${query_ip}" tree "show datanodes;" "${cur_dir}/show_datanodes_before_concurrent.out" 3600
  id1=$(grep "${target1}|" "${cur_dir}/show_datanodes_before_concurrent.out" | awk -F '|' '{gsub(" ","",$2);print $2}' | tail -1)
  id2=$(grep "${target2}|" "${cur_dir}/show_datanodes_before_concurrent.out" | awk -F '|' '{gsub(" ","",$2);print $2}' | tail -1)
  if [[ -z "${id1}" || -z "${id2}" || "${id1}" = "${id2}" ]]; then
    log "failed to resolve two distinct concurrent remove targets"
    let fail_flag++
    return 1
  fi
  if ! wait_datanode_status "${query_ip}" "${target1}" "Running" 300 ||
     ! wait_datanode_status "${query_ip}" "${target2}" "Running" 300; then
    log "one of the concurrent remove targets is not Running"
    let fail_flag++
    return 1
  fi

  # Launch both CLI requests before waiting for either one. Each worker writes
  # only its own output; the parent process owns all result accounting.
  submit_remove_datanode "${target1}" "${id1}" "${out1}" &
  pid1=$!
  submit_remove_datanode "${target2}" "${id2}" "${out2}" &
  pid2=$!
  wait "${pid1}"
  rc1=$?
  wait "${pid2}"
  rc2=$?

  grep -qi 'successfully' "${out1}" && success1=1
  grep -qi 'successfully' "${out2}" && success2=1
  success_count=$((success1 + success2))
  if [[ ${success_count} -ne 1 ]]; then
    log "expected exactly one concurrent remove submission to succeed, got ${success_count}"
    log "target=${target1}, cli_rc=${rc1}, output:"
    cat "${out1}"
    log "target=${target2}, cli_rc=${rc2}, output:"
    cat "${out2}"
    let fail_flag++
    return 1
  fi

  if [[ ${success1} -eq 1 ]]; then
    success_target=${target1}
    failed_target=${target2}
    failed_output=${out2}
  else
    success_target=${target2}
    failed_target=${target1}
    failed_output=${out1}
  fi
  if ! grep -Eqi 'fail|error|another.*procedure|cannot|not enough' "${failed_output}"; then
    log "rejected concurrent remove for ${failed_target} has no explicit failure reason"
    cat "${failed_output}"
    let fail_flag++
  fi

  rm_target_ip=${success_target}
  if ! wait_remove_region_settled "${query_ip}" "${success_target}" 3600; then
    log "successful concurrent remove did not settle for ${success_target}, status=${rm_result_state}"
    let fail_flag++
    return 1
  fi

  jps_num=$(ssh "${u_name}@${success_target}" "source /etc/profile; sudo jps -l | grep -c 'DataNode' || true")
  tsfile_num=$(ssh "${u_name}@${success_target}" "sudo find '${db_dir}/data' -name '*.tsfile' -type f | wc -l")
  if [[ ${jps_num} -ne 0 ]]; then
    log "removed DataNode process is still present on ${success_target}"
    let fail_flag++
  fi
  if [[ ${tsfile_num} -ne 0 ]]; then
    log "removed DataNode ${success_target} still has ${tsfile_num} tsfiles"
    let fail_flag++
  fi

  for sample in 1 2 3
  do
    sleep 5
    run_cli_sql "${query_ip}" tree "show datanodes;" "${cur_dir}/show_datanodes_after_concurrent.out" 3600
    if ! grep "${failed_target}|" "${cur_dir}/show_datanodes_after_concurrent.out" | grep -q 'Running'; then
      log "rejected concurrent remove target ${failed_target} did not remain Running"
      let fail_flag++
      return 1
    fi
    if grep "${failed_target}|" "${cur_dir}/show_datanodes_after_concurrent.out" | grep -q 'Removing'; then
      log "rejected concurrent remove target ${failed_target} entered Removing"
      let fail_flag++
      return 1
    fi
  done
  log "concurrent remove result: removed=${success_target}, rejected=${failed_target}"
  return 0
}

check_benchmark_output_file() {
  local bm_file=$1

  if [[ ! -f "${bm_file}" ]]; then
    log "benchmark output missing: ${bm_file}"
    return 1
  fi

  if ! grep -q "Test elapsed time (not include schema creation):" "${bm_file}" || ! grep -q "Result Matrix" "${bm_file}"; then
    return 2
  fi

  if grep -Eq "Execution fail:|Failed to do |StatementExecutionException|WorkloadException|There is not enough memory to execute current fragment instance|Connection error" "${bm_file}"; then
    return 3
  fi

  return 0
}

wait_benchmarks_finish() {
  local max_wait=${1:-43200}
  local start_time
  local workload
  local finished_num

  start_time=$(date +%s)
  while true
  do
    finished_num=0
    for workload in tree_nonaligned tree_aligned tree_aligned_temp table
    do
      local bm_file="${bm_log_root}/${workload}.out"
      check_benchmark_output_file "${bm_file}"
      case $? in
        0)
          finished_num=$((finished_num + 1))
          ;;
        1)
          ;;
        2)
          ;;
        3)
          log "benchmark output has errors: ${bm_file}"
          grep -E "Execution fail:|Failed to do |StatementExecutionException|WorkloadException|There is not enough memory to execute current fragment instance|Connection error" "${bm_file}" | tail -n 20
          let fail_flag++
          return 1
          ;;
      esac
    done

    if [[ ${finished_num} -eq 4 ]]; then
      return 0
    fi

    if (( $(date +%s) - start_time > max_wait )); then
      log "benchmark running too long"
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
    local zero_num

    now=$(date +%s)
    if (( now - wait_start_time > max_wait_seconds )); then
      log "wait sync lag timeout"
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
    zero_num=$((expected_count - non_zero_num))

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
  local timeout_seconds=${3:-180}
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

capture_consistency_baseline() {
  run_cli_sql "${query_ip}" tree "select count(s_0) from root.test.g_0.** align by device;" "${cur_dir}/q_all_online_test.out" 3600
  run_cli_sql "${query_ip}" tree "select count(s_0) from root.db.g_0.** align by device;" "${cur_dir}/q_all_online_db.out" 3600
  if [[ ${view_ready} -eq 1 ]]; then
    run_cli_sql "${query_ip}" tree "select count(s_0) from root.view.g_0.** align by device;" "${cur_dir}/q_all_online_view.out" 3600
  fi
  run_cli_sql "${query_ip}" table "select device_id,count(s_0) from db_table_g_0.table_0 group by device_id order by device_id;" "${cur_dir}/q_all_online_table.out" 3600
}

check_query_diff() {
  local base_file=$1
  local compare_file=$2
  local grep_pat=$3

  if ! diff -q "${base_file}" "${compare_file}" >/dev/null 2>&1; then
    if [[ $(diff "${base_file}" "${compare_file}" | grep "${grep_pat}" | wc -l) -gt 0 ]]; then
      return 1
    fi
  fi
  return 0
}

choose_query_host() {
  local stop_dn_ip=$1
  awk -v stop_ip="${stop_dn_ip}" '$0 != stop_ip {print; exit}' "${cur_dir}/running_datanodes.txt"
}

check_data_consistent() {
  local stop_dn_ip
  local query_host
  local v_ip
  local start_time

  if ! wait_for_monitor_sync_completion 120 360000; then
    return 1
  fi

  capture_consistency_baseline
  run_cli_sql "${query_ip}" tree "show datanodes;" "${cur_dir}/show_datanodes.out" 3600
  awk -F '|' '/Running/ {gsub(/ /, "", $4); print $4}' "${cur_dir}/show_datanodes.out" | sort -u > "${cur_dir}/running_datanodes.txt"

  while read -r stop_dn_ip
  do
    [[ -z "${stop_dn_ip}" ]] && continue
    query_host=$(choose_query_host "${stop_dn_ip}")
    if [[ -z "${query_host}" ]]; then
      log "no query host left after stopping ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi
    query_ip="${query_host}"

    ssh "${u_name}@${stop_dn_ip}" "source /etc/profile; cd ${db_dir}; sudo ./sbin/stop-datanode.sh"
    if ! wait_datanode_not_running "${query_host}" "${stop_dn_ip}" 180; then
      log "cluster state did not update after stopping ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi

    v_ip=$(echo "${stop_dn_ip}" | awk -F '.' '{print $4}')
    run_cli_sql "${query_host}" tree "select count(s_0) from root.test.g_0.** align by device;" "${cur_dir}/q_stop_ip${v_ip}_test.out" 3600
    run_cli_sql "${query_host}" tree "select count(s_0) from root.db.g_0.** align by device;" "${cur_dir}/q_stop_ip${v_ip}_db.out" 3600
    if [[ ${view_ready} -eq 1 ]]; then
      run_cli_sql "${query_host}" tree "select count(s_0) from root.view.g_0.** align by device;" "${cur_dir}/q_stop_ip${v_ip}_view.out" 3600
    fi
    run_cli_sql "${query_host}" table "select device_id,count(s_0) from db_table_g_0.table_0 group by device_id order by device_id;" "${cur_dir}/q_stop_ip${v_ip}_table.out" 3600

    if ! check_query_diff "${cur_dir}/q_all_online_test.out" "${cur_dir}/q_stop_ip${v_ip}_test.out" 'root\.'; then
      log "tree test data differs when ${stop_dn_ip} is down"
      let fail_flag++
      return 1
    fi
    if ! check_query_diff "${cur_dir}/q_all_online_db.out" "${cur_dir}/q_stop_ip${v_ip}_db.out" 'root\.'; then
      log "tree db data differs when ${stop_dn_ip} is down"
      let fail_flag++
      return 1
    fi
    if [[ ${view_ready} -eq 1 ]]; then
      if ! check_query_diff "${cur_dir}/q_all_online_view.out" "${cur_dir}/q_stop_ip${v_ip}_view.out" 'root\.'; then
        log "tree view data differs when ${stop_dn_ip} is down"
        let fail_flag++
        return 1
      fi
    fi
    if ! check_query_diff "${cur_dir}/q_all_online_table.out" "${cur_dir}/q_stop_ip${v_ip}_table.out" 'd_|device_id'; then
      log "table data differs when ${stop_dn_ip} is down"
      let fail_flag++
      return 1
    fi

    start_time=$(date +%s)
    ssh "${u_name}@${stop_dn_ip}" "source /etc/profile; cd ${db_dir}; sudo ./sbin/start-datanode.sh -H ${db_dir}/dn_${start_time}_heapdump.hprof > /dev/null 2>&1 &"
    if ! wait_datanode_running "${query_host}" "${stop_dn_ip}" 180; then
      log "failed to restart ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi
    if ! wait_for_monitor_sync_completion 120 360000; then
      return 1
    fi
  done < "${cur_dir}/running_datanodes.txt"

  return 0
}

check_npe() {
  local tc_desc=$1
  exec 3<"${nodeinfo_dir}/confignode.txt"
  while read -r line <&3
  do
    if [[ $(ssh "${u_name}@${line}" "grep NullPointer ${db_dir}/logs/*confignode*all* | wc -l") -gt 0 ]]; then
      log "${tc_desc} CN NullPointer on ${line}"
      let fail_flag++
    fi
  done
  exec 3<&-

  exec 3<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&3
  do
    if [[ $(ssh "${u_name}@${line}" "grep NullPointer ${db_dir}/logs/*datanode*all* | wc -l") -gt 0 ]]; then
      log "${tc_desc} DN NullPointer on ${line}"
      let fail_flag++
    fi
  done
  exec 3<&-
}

write_test_result() {
  local test_end_sec
  local test_elp_sec
  local tc_res=true

  test_end_sec=$(date +%s)
  test_elp_sec=$((test_end_sec - test_begin_sec))
  if [[ ${fail_flag} -ne 0 ]]; then
    tc_res=false
  fi

  if [[ "${tc_res}" = true ]]; then
    echo "${SCRIPT_NAME} : pass" >> "${res_file}"
  else
    echo "${SCRIPT_NAME} : fail" >> "${res_file}"
  fi

  "${cli_dir}/sbin/start-cli.sh" -h "${testcase_res_db}" -p "${testcase_res_port}" -pw "${res_root_pw}" -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"
}

testcase() {
  local benchmark_start_sec
  local target1
  local target2

  start_db
  create_benchmark_users
  prepare_benchmark_databases
  prepare_benchmark_workdirs
  benchmark_start_sec=$(date +%s)
  start_benchmarks
  create_tree_view_data
  wait_until_remove_time "${benchmark_start_sec}"
  target1=$(tail -1 "${nodeinfo_dir}/datanode.txt")
  target2=$(tail -2 "${nodeinfo_dir}/datanode.txt" | head -1)
  remove_two_datanodes_concurrently "${target1}" "${target2}"
  wait_benchmarks_finish 43200
  check_data_consistent
  check_npe "${SCRIPT_NAME}"
}

testcase
write_test_result

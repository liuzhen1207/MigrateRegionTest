#!/bin/bash

# Repro for the root.test query corruption seen after the first DataRegion
# migration when the current ConfigNode leader is stopped during snapshot
# transfer.
#
# Flow:
# 1. Restore a 3CN/5DN cluster with preloaded root.test data.
# 2. Capture baseline count and aggregation query results.
# 3. Run exactly one migration: MIGRATE REGION <id> FROM <src> TO <dest>.
# 4. After source replicas log "start to transmit snapshot", stop the current
#    CN leader, wait for it to exit, then start it again.
# 5. Wait for migration success and immediately compare root.test results to
#    capture the premature-success window.
# 6. Wait for the destination peer to become active, then compare again to
#    distinguish transient inconsistency from persistent corruption.
#
# Failure signal:
# - the migrate command itself succeeds in mig.out, but
# - q_root_test_exp*.out and q_root_test_early*.out diverge, typically with many
#   devices flipping from non-zero results to 0/null, or
# - q_root_test_exp*.out and q_root_test_final*.out still diverge after the
#   destination peer becomes active, or
# - the migrated region still contains non-Running replicas.
#
# Key artifacts:
# - mig.out: CLI result of the single MIGRATE REGION statement
# - q_root_test_exp.out / q_root_test_early.out / q_root_test_final.out:
#   count query before migration, right after CN success, and after destination
#   peer activation
# - q_root_test_exp_agg.out / q_root_test_early_agg.out /
#   q_root_test_final_agg.out: aggregation query for the same checkpoints
# - show_regions_when_migrations_empty.out: region snapshot when show migrations
#   first becomes Empty set
# - region_<id>_after_mig.out: final region placement and replica states
# - mig_success_cn.out: CN-side success lines with IP prefixes
# - dest_peer_active_<id>.out: destination DN snapshot/active lines

cur_dir="$(cd "$(dirname "$0")" && pwd)"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=$(grep u_name "${conf_file}" | awk -F '=' '{print $2}')
db_dir=$(grep '^db_dir' "${conf_file}" | awk -F '=' '{print $2}')
iotdb_host=$(grep test_ip "${conf_file}" | awk -F '=' '{print $2}')
v_cur_db=$(grep v_cur_db "${conf_file}" | awk -F '=' '{print $2}')
cli_dir=$(grep client_db_dir "${conf_file}" | awk -F '=' '{print $2}')
testcase_res_db=$(grep '^testcase_res_db=' "${conf_file}" | awk -F '=' '{print $2}')
testcase_res_port=$(grep '^testcase_res_port=' "${conf_file}" | awk -F '=' '{print $2}')
res_file="${cur_dir}/../test_result/res_${v_cur_db}.out"
clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
check_res_dir="${cur_dir}/../check_res"
SCRIPT_NAME=$(basename "$0")
tc_num=$(echo "${SCRIPT_NAME}" | awk -F '_' '{print $1}' | awk -F 'tc' '{print $2}')
testcase_ip=$(grep '^test_ip=' "${conf_file}" | awk -F '.' '{print $4}')
seed_cn_ip="$(head -1 "${nodeinfo_dir}/confignode.txt"):10710"
query_cn_ip=$(head -1 "${nodeinfo_dir}/confignode.txt")
query_ip=$(head -1 "${nodeinfo_dir}/datanode.txt")
cn_num=3
dn_num=5
dr_rep_num=2
head -n "${dn_num}" "${nodeinfo_dir}/total_datanode.txt" > "${nodeinfo_dir}/datanode.txt"
head -n "${dn_num}" "${nodeinfo_dir}/total_datanode_port.txt" > "${nodeinfo_dir}/datanode_port.txt"
total_node_num=$((cn_num + dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/3db_test_data
fail_flag=0
v_warnMessage=""
test_begin_sec=$(date +%s)
res_root_pw=TimechoDB@2021

# Count query is a cheap per-device integrity check for root.test.g_0.
q_count="select count(s_0) from root.test.g_0.** align by device;"
# Aggregation query exercises a broader set of measurements and null handling.
q_agg="select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.test.** align by device;"

function append_warn() {
  local msg=$1
  if [[ -z "${v_warnMessage}" ]]; then
    v_warnMessage="${msg}"
  else
    v_warnMessage="${v_warnMessage}; ${msg}"
  fi
}

function is_dest_peer_active_now() {
  local v_active_grep
  v_active_grep="set Peer{groupId=DataRegion[${v_mig_id}], endpoint=TEndPoint(ip:${v_mig_dest_dn_ip1}, port:10760), nodeId=${v_mig_dest_dn_id1}} active status to true"

  if ssh "${u_name}@${v_mig_dest_dn_ip1}" "[ -f ${db_dir}/logs/log-datanode-all*gz ]"; then
    ssh "${u_name}@${v_mig_dest_dn_ip1}" "sudo gunzip ${db_dir}/logs/log-datanode-all*"
  fi

  ssh "${u_name}@${v_mig_dest_dn_ip1}" \
    "grep -F \"${v_active_grep}\" ${db_dir}/logs/*datanode*all* 2>/dev/null | wc -l"
}

function capture_regions_when_migrations_empty() {
  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show regions;" \
    > "${cur_dir}/show_regions_when_migrations_empty.out"
  v_regions_transitioning_when_migrations_empty=$(grep -E "Adding|Removing" \
    "${cur_dir}/show_regions_when_migrations_empty.out" | wc -l)
}

function clean_env() {
  sh -x "${clean_env_dir}/stop_cluster.sh"
  sh -x "${clean_env_dir}/clean_cluster.sh"
  sh -x "${clean_env_dir}/reset_conf.sh"
}

function write_test_result() {
  test_end_sec=$(date +%s)
  test_elp_sec=$((test_end_sec - test_begin_sec))
  tc_res=true

  if [[ "${fail_flag}" = 0 ]]; then
    echo "${SCRIPT_NAME} : pass" | tee -a "${res_file}"
  else
    tc_res=false
    echo "${SCRIPT_NAME} : fail" | tee -a "${res_file}"
    if [[ -n "${v_warnMessage}" ]]; then
      echo "${SCRIPT_NAME} : ${v_warnMessage}" >> "${res_file}"
    fi
  fi

  if [[ -n "${testcase_res_db}" && -n "${testcase_res_port}" && -n "${testcase_ip}" && -n "${tc_num}" ]]; then
    "${cli_dir}/sbin/start-cli.sh" \
      -h "${testcase_res_db}" \
      -p "${testcase_res_port}" \
      -pw "${res_root_pw}" \
      -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});" \
      >> "${res_file}" 2>&1 || true
  fi

  if [[ -n "${v_warnMessage}" ]]; then
    echo "warn_message=${v_warnMessage}"
  fi
  echo "elapsed=${test_elp_sec}s"
}

function check_log() {
  local v_npe
  local v_cn_err1
  local v_cn_err2
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
  while read -r line <&3; do
    ssh "${u_name}@${line}" "gunzip -f ${db_dir}/logs/*confignode*all*.gz 2>/dev/null || true"
    v_npe=$(ssh "${u_name}@${line}" "grep NullPointer ${db_dir}/logs/*confignode*all* | wc -l")
    v_cn_err1=$(ssh "${u_name}@${line}" "grep BufferUnderflowException ${db_dir}/logs/*confignode*all* | wc -l")
    v_cn_err2=$(ssh "${u_name}@${line}" "grep \"but return HAS_MORE_STATE\" ${db_dir}/logs/*confignode*all* | wc -l")
    if [[ ${v_npe} -gt 0 ]]; then
      let fail_flag++
      append_warn "CN NPE"
    fi
    if [[ $((v_cn_err1 + v_cn_err2)) -gt 0 ]]; then
      let fail_flag++
      append_warn "CN HAS_MORE_STATE"
    fi
  done
  exec 3<&-

  exec 3<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&3; do
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
    fi
    if [[ ${v_dn_total_err} -gt 0 ]]; then
      let fail_flag++
      append_warn "DN unexp log"
    fi
  done
  exec 3<&-
}

function backup_logs() {
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

function set_sys_conf() {
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

function set_conf() {
  exec 3<"${nodeinfo_dir}/confignode.txt"
  while read -r line <&3; do
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
    set_sys_conf "${line}" "${db_dir}" ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
    set_sys_conf "${line}" "${db_dir}" ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
    set_sys_conf "${line}" "${db_dir}" ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=134217728"
  done

  exec 3<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&3; do
    ssh "${u_name}@${line}" "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"20G\"/g' ${db_dir}/conf/datanode-env.sh"
    ssh "${u_name}@${line}" "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
    set_sys_conf "${line}" "${db_dir}" ".*dn_seed_config_node=.*" "dn_seed_config_node=${seed_cn_ip}"
    set_sys_conf "${line}" "${db_dir}" ".*dn_internal_address=.*" "dn_internal_address=${line}"
    set_sys_conf "${line}" "${db_dir}" ".*dn_rpc_address=.*" "dn_rpc_address=${line}"
    set_sys_conf "${line}" "${db_dir}" ".*dn_metric_reporter_list=.*" "dn_metric_reporter_list=PROMETHEUS"
    set_sys_conf "${line}" "${db_dir}" ".*dn_metric_level=.*" "dn_metric_level=IMPORTANT"
    set_sys_conf "${line}" "${db_dir}" ".*schema_replication_factor=.*" "schema_replication_factor=3"
    set_sys_conf "${line}" "${db_dir}" ".*data_replication_factor=.*" "data_replication_factor=2"
    set_sys_conf "${line}" "${db_dir}" ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
    set_sys_conf "${line}" "${db_dir}" ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
    set_sys_conf "${line}" "${db_dir}" ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
    set_sys_conf "${line}" "${db_dir}" ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
    set_sys_conf "${line}" "${db_dir}" ".*datanode_memory_proportion=.*" "datanode_memory_proportion=1:5:1:1:1:1"
    set_sys_conf "${line}" "${db_dir}" ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=134217728"
  done
}

function start_db() {
  sh -x "${clean_env_dir}/stop_cluster.sh"
  sh -x "${clean_env_dir}/clean_cluster.sh"
  sh -x "${clean_env_dir}/reset_conf.sh"
  head -n "${cn_num}" "${nodeinfo_dir}/total_node.txt" > "${nodeinfo_dir}/confignode.txt"
  set_conf

  exec 3<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&3; do
    ssh "${u_name}@${line}" "sudo cp -rl ${backup_dir_on_cn_dn_host}/data ${db_dir}/" &
  done

  exec 3<"${nodeinfo_dir}/datanode.txt"
  while read -r line <&3; do
    while true; do
      v_check_cp=$(ssh "${u_name}@${line}" "sudo ps -ef|grep \"cp -rl\"|grep -v grep|wc -l")
      if [[ "${v_check_cp}" = 0 ]]; then
        ssh "${u_name}@${line}" "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\""
        break
      fi
      sleep 5
    done
  done

  exec 3<"${nodeinfo_dir}/confignode.txt"
  while read -r line <&3; do
    v_check=$(grep "${line}" "${nodeinfo_dir}/datanode.txt" | wc -l)
    if [[ "${v_check}" = 0 ]]; then
      ssh "${u_name}@${line}" "sudo cp -rp ${backup_dir_on_cn_dn_host}/data ${db_dir}/"
      ssh "${u_name}@${line}" "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\""
    fi
  done

  sh -x "${prepare_env_dir}/start_cluster.sh" "1" "${total_node_num}"
}

function mig_region() {
  local v_mig_id=$1
  local v_mig_from_dn_id=$2
  local v_mig_dest_dn_id=$3
  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e \
    "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_dest_dn_id};" >> "${cur_dir}/mig.out"
  sleep 2
}

# This testcase intentionally interrupts only the first migration. The trigger
# point is the first "start to transmit snapshot" log line observed on either
# source replica of the target DataRegion.
function stop_cn_leader_during_first_mig() {
  local v_cn_leader=$1
  local v_stop_cn_flag=0
  local v_t1
  v_t1=$(date +%s)

  if ssh "${u_name}@${v_mig_from_dn_ip1}" "[ -f ${db_dir}/logs/log-datanode-all*gz ]"; then
    ssh "${u_name}@${v_mig_from_dn_ip1}" "sudo gunzip ${db_dir}/logs/log-datanode-all*"
  fi
  if ssh "${u_name}@${v_mig_from_dn_ip2}" "[ -f ${db_dir}/logs/log-datanode-all*gz ]"; then
    ssh "${u_name}@${v_mig_from_dn_ip2}" "sudo gunzip ${db_dir}/logs/log-datanode-all*"
  fi

  while true; do
    local v_start_transmit_snapshot1
    local v_start_transmit_snapshot2
    local v_start_transmit_snapshot
    local v_t2
    local v_elp

    v_start_transmit_snapshot1=$(ssh "${u_name}@${v_mig_from_dn_ip1}" \
      "grep \"start to transmit snapshot\" ${db_dir}/logs/*datanode*all*|wc -l")
    v_start_transmit_snapshot2=$(ssh "${u_name}@${v_mig_from_dn_ip2}" \
      "grep \"start to transmit snapshot\" ${db_dir}/logs/*datanode*all*|wc -l")
    v_start_transmit_snapshot=$((v_start_transmit_snapshot1 + v_start_transmit_snapshot2))

    if [[ "${v_start_transmit_snapshot}" -gt 0 ]]; then
      ssh "${u_name}@${v_cn_leader}" "sudo ${db_dir}/sbin/stop-confignode.sh"
      while true; do
        local v_check_status
        local v_stop_elp
        v_check_status=$(ssh "${u_name}@${v_cn_leader}" "sudo jps|grep -i confignode|wc -l")
        if [[ "${v_check_status}" -gt 0 ]]; then
          sleep 2
        else
          v_stop_cn_flag=1
          break
        fi
        v_stop_elp=$(( $(date +%s) - v_t1 ))
        if [[ "${v_stop_elp}" -gt 120 ]]; then
          break
        fi
      done
      break
    fi

    v_t2=$(date +%s)
    v_elp=$((v_t2 - v_t1))
    if [[ "${v_elp}" -gt 180 ]]; then
      break
    fi
    sleep 2
  done

  if [[ "${v_stop_cn_flag}" = 1 ]]; then
    local v_start_time
    v_start_time=$(date +%s)
    ssh "${u_name}@${v_cn_leader}" \
      "source /etc/profile;sudo ${db_dir}/sbin/start-confignode.sh > /dev/null 2>&1 &"
    while true; do
      local v_check_status
      local v_elp
      v_check_status=$("${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show confignodes" \
        | grep "${v_cn_leader}" | grep -i Running | wc -l)
      if [[ "${v_check_status}" -gt 0 ]]; then
        break
      fi
      v_elp=$(( $(date +%s) - v_start_time ))
      if [[ "${v_elp}" -gt 120 ]]; then
        let fail_flag++
        break
      fi
      sleep 2
    done
  fi
}

# Poll all running CNs until at least one reports "[MigrateRegion] success".
# Even after CN success appears, keep waiting until "show migrations" becomes
# empty so data validation only starts after the migration is actually finished.
function wait_first_mig_result() {
  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show confignodes;" \
    | grep -i Running | awk -F '|' '{gsub(" ","");print $4}' > "${cur_dir}/all_cn_ip.txt"

  sleep 10
  local v_start_time
  local v_success_seen=0
  local v_success_cn_ip=""
  local v_mig_show_done=0
  v_start_time=$(date +%s)
  while true; do
    local v_mig_suc=0
    local v_mig_suc_line=""
    local v_miging_num
    local v_cur_sec
    local v_mig_elp

    exec 3<"${cur_dir}/all_cn_ip.txt"
    while read -r line <&3; do
      if ssh "${u_name}@${line}" "[ -f ${db_dir}/logs/log-confignode-all*gz ]"; then
        ssh "${u_name}@${line}" "sudo gunzip ${db_dir}/logs/log-confignode-all*"
      fi
      v_mig_suc_line=$(ssh "${u_name}@${line}" \
        "grep -n \"\\[MigrateRegion\\] success\" ${db_dir}/logs/*confignode*all* 2>/dev/null | head -1")
      if [[ -n "${v_mig_suc_line}" ]]; then
        v_mig_suc_tmp=1
        if [[ "${v_success_seen}" = 0 ]]; then
          v_success_seen=1
          v_success_cn_ip="${line}"
          echo "${line}: ${v_mig_suc_line}" > "${cur_dir}/first_success_cn.out"
        fi
      else
        v_mig_suc_tmp=0
      fi
      v_mig_suc=$((v_mig_suc + v_mig_suc_tmp))
    done
    "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show migrations;" > "${cur_dir}/show_migrations.out"
    if grep -Eiq '(^Error|Exception|^[[:space:]]*Msg:|StatementExecutionException|java\.lang\.)' \
      "${cur_dir}/show_migrations.out"; then
      append_warn "show migrations execute failed after MIGRATE REGION ${v_mig_id}"
      let fail_flag++
      break
    fi
    if grep -q "Empty set" "${cur_dir}/show_migrations.out"; then
      v_mig_show_done=1
    else
      v_mig_show_done=0
    fi

    if [[ "${v_mig_suc}" -ge 1 ]] && [[ "${v_mig_show_done}" -eq 1 ]]; then
      local v_dest_active_now
      capture_regions_when_migrations_empty
      v_dest_active_now=$(is_dest_peer_active_now)
      if [[ "${v_dest_active_now}" -eq 0 ]]; then
        v_show_migrations_empty_before_peer_active=1
        append_warn "show migrations became Empty set before destination peer ${v_mig_dest_dn_id1}@${v_mig_dest_dn_ip1} became active for region ${v_mig_id}"
        let fail_flag++
      fi
      break
    fi
    if [[ "${v_mig_suc}" -ge 1 ]] && [[ "${v_mig_show_done}" -eq 0 ]]; then
      if [[ -z "${v_success_cn_ip}" ]]; then
        v_success_cn_ip="unknown"
      fi
      if [[ -z "${v_cn_success_before_migration_done}" ]]; then
        v_cn_success_before_migration_done=1
        append_warn "ConfigNode ${v_success_cn_ip} logged [MigrateRegion] success before show migrations became Empty set for region ${v_mig_id}"
        let fail_flag++
      fi
    fi

    v_cur_sec=$(date +%s)
    v_mig_elp=$((v_cur_sec - v_start_time))
    v_miging_num=$("${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show regions;" \
      | egrep "Adding|Removing" | wc -l)
    if [[ "${v_miging_num}" -gt 0 ]]; then
      sleep 20
      continue
    fi
    if [[ "${v_mig_elp}" -gt 600 ]]; then
      let fail_flag++
      break
    fi
    sleep 10
  done
}

function run_root_test_queries() {
  local v_stage=$1
  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -timeout 3600000 -e "${q_count}" \
    > "${cur_dir}/q_root_test_${v_stage}.out"
  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -timeout 3600000 -e "${q_agg}" \
    > "${cur_dir}/q_root_test_${v_stage}_agg.out"
}

function calc_root_test_diff() {
  local v_stage=$1
  local v_count_diff
  local v_agg_diff
  local v_count_var="v_${v_stage}_count_diff"
  local v_agg_var="v_${v_stage}_agg_diff"

  v_count_diff=$(diff "${cur_dir}/q_root_test_exp.out" "${cur_dir}/q_root_test_${v_stage}.out" \
    | grep root.test | wc -l)
  v_agg_diff=$(diff "${cur_dir}/q_root_test_exp_agg.out" "${cur_dir}/q_root_test_${v_stage}_agg.out" \
    | grep root.test | wc -l)

  printf -v "${v_count_var}" '%s' "${v_count_diff}"
  printf -v "${v_agg_var}" '%s' "${v_agg_diff}"
}

function collect_mig_debug_artifacts() {
  > "${cur_dir}/mig_success_cn.out"
  exec 3<"${cur_dir}/all_cn_ip.txt"
  while read -r line <&3; do
    ssh "${u_name}@${line}" \
      "grep -n \"\\[MigrateRegion\\] success\" ${db_dir}/logs/*confignode*all* 2>/dev/null" \
      | sed "s/^/${line}: /" >> "${cur_dir}/mig_success_cn.out"
  done

  ssh "${u_name}@${v_mig_dest_dn_ip1}" \
    "grep -nE 'Loading snapshot for root.test-${v_mig_id}|DataRegion\\[${v_mig_id}\\]|active status to (false|true)' ${db_dir}/logs/*datanode*all* 2>/dev/null" \
    > "${cur_dir}/dest_peer_active_${v_mig_id}.out"
}

function wait_dest_peer_active_after_mig() {
  local v_start_time
  local v_active_grep
  v_start_time=$(date +%s)
  v_active_grep="set Peer{groupId=DataRegion[${v_mig_id}], endpoint=TEndPoint(ip:${v_mig_dest_dn_ip1}, port:10760), nodeId=${v_mig_dest_dn_id1}} active status to true"

  while true; do
    local v_active_num
    local v_elp
    if ssh "${u_name}@${v_mig_dest_dn_ip1}" "[ -f ${db_dir}/logs/log-datanode-all*gz ]"; then
      ssh "${u_name}@${v_mig_dest_dn_ip1}" "sudo gunzip ${db_dir}/logs/log-datanode-all*"
    fi
    v_active_num=$(ssh "${u_name}@${v_mig_dest_dn_ip1}" \
      "grep -F \"${v_active_grep}\" ${db_dir}/logs/*datanode*all* 2>/dev/null | wc -l")
    if [[ "${v_active_num}" -gt 0 ]]; then
      break
    fi
    v_elp=$(( $(date +%s) - v_start_time ))
    if [[ "${v_elp}" -gt 1800 ]]; then
      let fail_flag++
      echo "wait_dest_peer_active_timeout=1"
      break
    fi
    sleep 10
  done
}

# Compare root.test before migration and after migration really finishes.
# A warn+fail is recorded if CN success appears before show migrations becomes
# empty. Final diff indicates persistent corruption after migration completion.
function compare_root_test_after_mig() {
  run_root_test_queries "exp"

  mig_region "${v_mig_id}" "${v_mig_from_dn_id1}" "${v_mig_dest_dn_id1}"
  stop_cn_leader_during_first_mig "${v_cn_leader}"
  wait_first_mig_result
  collect_mig_debug_artifacts

  wait_dest_peer_active_after_mig
  run_root_test_queries "final"
  calc_root_test_diff "final"
  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show data regions;" \
    | grep " ${v_mig_id}|[[:space:]]*DataRegion" > "${cur_dir}/region_${v_mig_id}_after_mig.out"

  v_non_running=$(grep -v Running "${cur_dir}/region_${v_mig_id}_after_mig.out" | wc -l)

  echo "v_cn_success_before_migration_done=${v_cn_success_before_migration_done:-0}"
  echo "v_show_migrations_empty_before_peer_active=${v_show_migrations_empty_before_peer_active:-0}"
  echo "v_regions_transitioning_when_migrations_empty=${v_regions_transitioning_when_migrations_empty:-0}"
  echo "v_final_count_diff=${v_final_count_diff}"
  echo "v_final_agg_diff=${v_final_agg_diff}"
  echo "v_non_running=${v_non_running}"
  cat "${cur_dir}/region_${v_mig_id}_after_mig.out"

  if [[ "${v_final_count_diff}" -gt 0 ]] || [[ "${v_final_agg_diff}" -gt 0 ]]; then
    echo "repro_persistent_data_corruption=1"
    let fail_flag++
  fi
  if [[ "${v_non_running}" -gt 0 ]]; then
    let fail_flag++
  fi
}

# Pick the first root.test DataRegion as the migration target, choose a
# destination DN outside the two current replicas, then stop the current CN
# leader during that migration.
function prepare_first_mig_repro() {
  > "${cur_dir}/mig.out"
  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show data regions;" \
    | grep root.test | head -1 | awk -F '|' '{gsub(" ","");print $2}' > "${cur_dir}/mig_region_id.txt"
  v_mig_id=$(cat "${cur_dir}/mig_region_id.txt")

  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show data regions;" \
    | grep " ${v_mig_id}|[[:space:]]*DataRegion" \
    | awk -F '|' '{gsub(" ","");print $8","$9}' > "${cur_dir}/mig_id_info.txt"
  "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show datanodes;" \
    | grep Running | awk -F '|' '{gsub(" ","");print $2","$4}' > "${cur_dir}/all_dn_id_ip.txt"

  v_mig_from_dn_id1=$(awk 'NR==1 {print $1}' FS=',' "${cur_dir}/mig_id_info.txt")
  v_mig_from_dn_ip1=$(awk 'NR==1 {print $2}' FS=',' "${cur_dir}/mig_id_info.txt")
  v_mig_from_dn_id2=$(awk 'NR==2 {print $1}' FS=',' "${cur_dir}/mig_id_info.txt")
  v_mig_from_dn_ip2=$(awk 'NR==2 {print $2}' FS=',' "${cur_dir}/mig_id_info.txt")
  v_mig_dest_dn_id1=$(grep -v "${v_mig_from_dn_ip1}" "${cur_dir}/all_dn_id_ip.txt" \
    | grep -v "${v_mig_from_dn_ip2}" | head -1 | awk -F ',' '{print $1}')
  v_mig_dest_dn_ip1=$(grep -v "${v_mig_from_dn_ip1}" "${cur_dir}/all_dn_id_ip.txt" \
    | grep -v "${v_mig_from_dn_ip2}" | head -1 | awk -F ',' '{print $2}')
  query_ip=$(grep -v "${v_mig_dest_dn_ip1}" "${cur_dir}/all_dn_id_ip.txt" | head -1 | awk -F ',' '{print $2}')
  v_cn_leader=$("${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -e "show confignodes;" \
    | grep Leader | awk -F '|' '{gsub(" ","");print $4}')

  echo "v_mig_id=${v_mig_id}"
  echo "v_mig_from_dn_id1=${v_mig_from_dn_id1}, v_mig_from_dn_ip1=${v_mig_from_dn_ip1}"
  echo "v_mig_from_dn_id2=${v_mig_from_dn_id2}, v_mig_from_dn_ip2=${v_mig_from_dn_ip2}"
  echo "v_mig_dest_dn_id1=${v_mig_dest_dn_id1}, v_mig_dest_dn_ip1=${v_mig_dest_dn_ip1}"
  echo "v_cn_leader=${v_cn_leader}, query_ip=${query_ip}"

  compare_root_test_after_mig
}

clean_env
start_db
prepare_first_mig_repro

sh -x "${clean_env_dir}/stop_cluster.sh"
check_log
backup_logs || true
write_test_result

#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
iotdb_host=`cat ${conf_file}|grep test_ip|awk -F '=' '{print $2}'`
v_cur_db=`cat ${conf_file}|grep v_cur_db|awk -F '=' '{print $2}'`
cli_dir=`cat ${conf_file}|grep client_db_dir|awk -F '=' '{print $2}'`
res_file="${cur_dir}/../test_result/res_${v_cur_db}.out"
clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
check_res_dir="${cur_dir}/../check_res"
SCRIPT_NAME=$(basename "$0")
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
query_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`
bm_ip=`head -1 ${nodeinfo_dir}/bm_node.txt`
bm_dir=/data1/benchmark/bm_20231129_d43030e
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-456
fail_file="fail.log"
cn_num=3
dn_num=5
dr_rep_num=2
sr_rep_num=3
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/3db_test_data
tmp_out_file="tc${tc_num}_tmp.out"
fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
loop_timeout_sec=300
mig_submit_timeout_sec=180
query_consistency_sql="select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.test.**,root.db.g_0.**,root.view.** align by device;"
v_warnMessage=""

function clean_env()
{
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
}

function append_warn()
{
  local msg=$1
  if [[ -z "${v_warnMessage}" ]];then
     v_warnMessage="${msg}"
  else
     v_warnMessage="${v_warnMessage}; ${msg}"
  fi
}

function set_sys_conf()
{
   local v_ip=$1
   local db_dir=$2
   local remote_host="${u_name}@${v_ip}"
   local remote_file="${db_dir}/conf/iotdb-system.properties"
   local search_str=$3
   local content=$4

   remote_grep="ssh $remote_host grep -q '$search_str' '$remote_file'"
   remote_sed="ssh $remote_host \"sed -i 's|$search_str|$content|g' '$remote_file'\""
   remote_echo="ssh $remote_host 'echo \"$content\" >> \"$remote_file\"'"

   if eval $remote_grep; then
      eval $remote_sed
   else
      eval $remote_echo
   fi
}

function set_conf()
{
  exec 3<${nodeinfo_dir}/confignode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
     set_sys_conf ${line} ${db_dir} ".*cn_seed_config_node=.*" "cn_seed_config_node=${seed_cn_ip}"
     set_sys_conf ${line} ${db_dir} ".*cn_internal_address=.*" "cn_internal_address=${line}"
     set_sys_conf ${line} ${db_dir} ".*cn_metric_reporter_list=.*" "cn_metric_reporter_list=PROMETHEUS"
     set_sys_conf ${line} ${db_dir} ".*cn_metric_level=.*" "cn_metric_level=IMPORTANT"
     set_sys_conf ${line} ${db_dir} ".*cn_metric_prometheus_reporter_port=.*" "cn_metric_prometheus_reporter_port=9081"
     set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
     set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
     set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
     set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
     set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
     set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
     set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=171966464"
  done

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"20G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
     set_sys_conf ${line} ${db_dir} ".*dn_seed_config_node=.*" "dn_seed_config_node=${seed_cn_ip}"
     set_sys_conf ${line} ${db_dir} ".*dn_internal_address=.*" "dn_internal_address=${line}"
     set_sys_conf ${line} ${db_dir} ".*dn_rpc_address=.*" "dn_rpc_address=${line}"
     set_sys_conf ${line} ${db_dir} ".*dn_metric_reporter_list=.*" "dn_metric_reporter_list=PROMETHEUS"
     set_sys_conf ${line} ${db_dir} ".*dn_metric_level=.*" "dn_metric_level=IMPORTANT"
     set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
     set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
     set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
     set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
     set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
     set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
     set_sys_conf ${line} ${db_dir} ".*region_migration_speed_limit_bytes_per_second=.*" "region_migration_speed_limit_bytes_per_second=33554432"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*" "datanode_memory_proportion=1:5:1:1:1:1"
     set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=171966464"
  done
}

function refresh_region_runtime_info()
{
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8","$9}'>${cur_dir}/mig_id_info.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/all_dn_id_ip.txt
}

function select_target_dn()
{
  local v_target_dn_id=""
  while read line
  do
     if [[ -z "${line}" ]];then
        continue
     fi
     v_check=`grep -w "${line}" ${cur_dir}/mig_region_dn_id.txt|wc -l`
     if [[ ${v_check} = 0 ]];then
        v_target_dn_id=${line}
        break
     fi
  done < ${cur_dir}/all_dn_id.txt
  echo ${v_target_dn_id}
}

function run_migrate_region_with_retry()
{
  local v_region_id=$1
  local v_from_dn_id=$2
  local v_to_dn_id=$3
  local v_out_file=$4
  local v_start_sec=`date +%s`

  while true
  do
     ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_region_id} FROM ${v_from_dn_id} TO ${v_to_dn_id};" > ${v_out_file}
     if grep -q "has some other region operation procedures in progress" ${v_out_file};then
        v_now_sec=`date +%s`
        v_elp=$((v_now_sec-v_start_sec))
        if [[ ${v_elp} -gt ${mig_submit_timeout_sec} ]];then
           return 1
        fi
        sleep 2
     elif grep -q "IoTDBSQLException" ${v_out_file};then
        return 1
     else
        return 0
     fi
  done
}

function capture_migration_visible_state()
{
  local v_suffix=$1

  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show migrations;" > ${cur_dir}/show_migrations_${v_suffix}.out 2>&1
  v_migrations_empty=0
  if grep -q "Empty set" ${cur_dir}/show_migrations_${v_suffix}.out;then
     v_migrations_empty=1
  fi
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show data regions;" > ${cur_dir}/show_data_regions_${v_suffix}.out 2>&1
  v_region_changing_count=`grep -E "Adding|Removing" ${cur_dir}/show_data_regions_${v_suffix}.out|wc -l`
}

function wait_migration_visible_state_stable()
{
  local v_suffix=$1

  v_wait_migration_seen_in_progress=0
  while true
  do
     capture_migration_visible_state ${v_suffix}
     if [[ ${v_migrations_empty} = 1 && ${v_region_changing_count} = 0 ]];then
        break
     fi
     v_wait_migration_seen_in_progress=1
     sleep 5
  done
}

function select_query_ip_excluding()
{
  local v_exclude_ip=$1
  local v_candidate=""

  while read v_candidate
  do
     if [[ -z "${v_candidate}" || "${v_candidate}" = "${v_exclude_ip}" ]];then
        continue
     fi
     echo "${v_candidate}"
     return 0
  done < ${nodeinfo_dir}/datanode.txt
  return 1
}

function wait_datanode_stopped()
{
  local v_stop_dn_ip=$1
  local v_start_time=`date +%s`
  local v_end_time=0
  local v_elp=0
  local v_pid=0

  while true
  do
     v_pid=`ssh -n ${u_name}@${v_stop_dn_ip} "sudo jps|grep -i datanode|wc -l"`
     if [[ ${v_pid} = 0 ]];then
        return 0
     fi
     v_end_time=`date +%s`
     v_elp=$((v_end_time-v_start_time))
     if [[ ${v_elp} -gt 180 ]];then
        return 1
     fi
     sleep 3
  done
}

function wait_datanode_running()
{
  local v_check_dn_ip=$1
  local v_check_query_ip=$2
  local v_start_time=`date +%s`
  local v_end_time=0
  local v_elp=0
  local v_check_status=0

  while true
  do
     v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${v_check_query_ip} -e "show datanodes"|grep ${v_check_dn_ip}|grep -i Running|wc -l`
     if [[ ${v_check_status} -gt 0 ]];then
        return 0
     fi
     v_end_time=`date +%s`
     v_elp=$((v_end_time-v_start_time))
     if [[ ${v_elp} -gt 180 ]];then
        return 1
     fi
     sleep 2
  done
}

function wait_all_datanodes_running()
{
  local v_check_query_ip=$1
  local v_start_time=`date +%s`
  local v_end_time=0
  local v_elp=0
  local v_running_count=0

  while true
  do
     v_running_count=`${cli_dir}/sbin/start-cli.sh -h ${v_check_query_ip} -e "show datanodes"|grep -i Running|wc -l`
     if [[ ${v_running_count} -ge ${dn_num} ]];then
        return 0
     fi
     v_end_time=`date +%s`
     v_elp=$((v_end_time-v_start_time))
     if [[ ${v_elp} -gt 180 ]];then
        return 1
     fi
     sleep 2
  done
}

function run_replica_consistency_check()
{
  local v_base_file="${cur_dir}/q_replica_base.out"
  local v_stop_dn_ip=""
  local v_check_query_ip=""
  local v_act_file=""
  local v_diff_file=""
  local v_heapdump_ip=""

  if ! wait_all_datanodes_running ${query_ip};then
     append_warn "replica consistency check skipped: not all DataNodes are Running before baseline query"
     let fail_flag++
     return 1
  fi

  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "${query_consistency_sql}" > ${v_base_file}
  if grep -q "IoTDBSQLException" ${v_base_file};then
     append_warn "replica consistency baseline query failed on ${query_ip}"
     let fail_flag++
     return 1
  fi

  while read v_stop_dn_ip <&9
  do
     if [[ -z "${v_stop_dn_ip}" ]];then
        continue
     fi

     v_check_query_ip=`select_query_ip_excluding ${v_stop_dn_ip}`
     if [[ -z "${v_check_query_ip}" ]];then
        append_warn "replica consistency check failed: cannot find query_ip excluding stopped DataNode ${v_stop_dn_ip}"
        let fail_flag++
        return 1
     fi

     if [[ "${query_ip}" = "${v_stop_dn_ip}" ]];then
        query_ip=${v_check_query_ip}
     fi

     ssh -n ${u_name}@${v_stop_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh"
     if ! wait_datanode_stopped ${v_stop_dn_ip};then
        append_warn "replica consistency check failed: DataNode ${v_stop_dn_ip} stop timeout"
        let fail_flag++
        return 1
     fi

     v_act_file="${cur_dir}/q_replica_stop_${v_stop_dn_ip}.out"
     v_diff_file="${cur_dir}/q_replica_stop_${v_stop_dn_ip}.diff"
     ${cli_dir}/sbin/start-cli.sh -h ${v_check_query_ip} -timeout 36000 -e "${query_consistency_sql}" > ${v_act_file}
     if grep -q "IoTDBSQLException" ${v_act_file};then
        append_warn "replica consistency check failed: query error after stopping DataNode ${v_stop_dn_ip}, query_ip=${v_check_query_ip}, out_file=${v_act_file}"
        let fail_flag++
     else
        diff ${v_base_file} ${v_act_file} > ${v_diff_file} || true
        if grep -q "root" ${v_diff_file};then
           append_warn "replica consistency check failed after stopping DataNode ${v_stop_dn_ip}, query_ip=${v_check_query_ip}, diff_file=${v_diff_file}"
           let fail_flag++
        fi
     fi

     v_heapdump_ip=${v_stop_dn_ip//./_}
     ssh -n ${u_name}@${v_stop_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_consistency_${v_heapdump_ip}.hprof > /dev/null 2>&1 &"
     if ! wait_datanode_running ${v_stop_dn_ip} ${v_check_query_ip};then
        append_warn "replica consistency check failed: DataNode ${v_stop_dn_ip} restart timeout"
        let fail_flag++
        return 1
     fi
  done 9< ${nodeinfo_dir}/datanode.txt

  return 0
}

function write_test_result()
{
  test_end_sec=`date +%s`
  test_elp_sec=$((test_end_sec-test_begin_sec))
  tc_res=true

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
  else
     tc_res=false
     echo "warn_message=${v_warnMessage}"
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
  fi

  ${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"
}

function start_db()
{
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh

   head -n $cn_num ${nodeinfo_dir}/total_node.txt > ${nodeinfo_dir}/confignode.txt
   set_conf

   exec 3<${nodeinfo_dir}/datanode.txt
   while read line<&3
   do
      ssh ${u_name}@${line} "sudo cp -rl ${backup_dir_on_cn_dn_host}/data ${db_dir}/ " &
   done

   exec 3<${nodeinfo_dir}/datanode.txt
   while read line<&3
   do
      while true
      do
         v_check_cp=`ssh ${u_name}@${line} "sudo ps -ef|grep \"cp -rl\"|grep -v grep|wc -l"`
         if [[ ${v_check_cp} = 0 ]];then
            ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\""
            break
         else
            sleep 5
         fi
      done
   done

   exec 3<${nodeinfo_dir}/confignode.txt
   while read line<&3
   do
      v_check=`grep ${line} ${nodeinfo_dir}/datanode.txt |wc -l`
      if [[ ${v_check} = 0 ]];then
         ssh ${u_name}@${line} "sudo cp -rp ${backup_dir_on_cn_dn_host}/data ${db_dir}/ "
         ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\""
      fi
   done

   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"
}

function pre_and_exec_mig_region()
{
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "${query_consistency_sql}">${cur_dir}/q_exp.out
  if grep -q "IoTDBSQLException" ${cur_dir}/q_exp.out;then
     append_warn "initial baseline query (q_exp.out) failed on ${query_ip}"
     let fail_flag++
  fi

  v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  refresh_region_runtime_info

  v_mig_to_dn_id=-1
  line=`head -1 ${cur_dir}/mig_id_info.txt`
  if [[ ${line} = "" ]];then
     let fail_flag++
     write_test_result
     return 1
  fi

  v_mig_from_dn_id=`echo ${line}|awk -F ',' '{print $1}'`
  if [[ ${v_mig_to_dn_id} -lt 0 ]];then
     v_mig_to_dn_id=`select_target_dn`
  fi
  if [[ ${v_mig_to_dn_id} = "" ]];then
     let fail_flag++
     write_test_result
     return 1
  fi

  v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
  v_bef_mig_time=`ssh ${u_name}@${v_cn_leader_ip} "date +\"%Y-%m-%d %H:%M:%S\""`
  v_bef_mig_sec=`date -d"${v_bef_mig_time}" +%s`
  if ! run_migrate_region_with_retry ${v_mig_id} ${v_mig_from_dn_id} ${v_mig_to_dn_id} ${cur_dir}/mig.out;then
     let fail_flag++
     write_test_result
     return 1
  fi

  v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`

  v_start_time=`date +%s`
  while true
  do
     ssh ${u_name}@${v_cn_leader_ip} "sudo gunzip -f ${db_dir}/logs/log-confignode-all*gz >/dev/null 2>&1 || true"
     v_AddRegion=`ssh ${u_name}@${v_cn_leader_ip} "grep \"AddRegion\] started\" ${db_dir}/logs/*confignode*all*|grep \"added to DataNode ${v_mig_to_dn_id}\"|wc -l"`
     if [[ ${v_AddRegion} -gt 0 ]];then
        v_adding_check=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show data regions"|grep Adding|wc -l`
        if [[ ${v_adding_check} = 0 ]];then
           let fail_flag++
        fi
        break
     else
        v_end_time=`date +%s`
        v_elp=$((v_end_time-v_start_time))
        if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
           let fail_flag++
           write_test_result
           return 1
        fi
        sleep 1
     fi
  done

  v_submit_mig_log=`ssh ${u_name}@${v_cn_leader_ip} "grep \"Submit RegionMigrateProcedure successfully, Region: TConsensusGroupId(type:DataRegion, id:${v_mig_id}), Origin DataNode: TDataNodeLocation(dataNodeId:${v_mig_from_dn_id},\" ${db_dir}/logs/*confignode*all*"`
  v_add_coord_ip=`echo ${v_submit_mig_log} |awk -F "Add Coordinator:" '{print $2}'|awk -F "ip:" '{print $2}'|awk -F ',' '{print $1}'`
  v_remove_coord_ip=`echo ${v_submit_mig_log} |awk -F "Remove Coordinator:" '{print $2}'|awk -F "ip:" '{print $2}'|awk -F ',' '{print $1}'`

  v_start_time=`date +%s`
  while true
  do
     ssh ${u_name}@${v_add_coord_ip} "sudo gunzip -f ${db_dir}/logs/log-datanode-all*gz >/dev/null 2>&1 || true"
     v_snapshot_progress_count=`ssh ${u_name}@${v_add_coord_ip} "grep \"SNAPSHOT TRANSMISSION] The overall progress\" ${db_dir}/logs/*datanode*all*|wc -l"`
     v_end_time=`date +%s`
     v_elp=$((v_end_time-v_start_time))
     v_ready_to_inject=0
     if [[ ${v_snapshot_progress_count} -gt 1 ]];then
        v_ready_to_inject=1
     fi
     if [[ ${v_ready_to_inject} = 0 && ${v_elp} -gt ${loop_timeout_sec} ]];then
        capture_migration_visible_state "before_first_fault_injection"
        if [[ ${v_migrations_empty} = 0 && ${v_region_changing_count} -gt 0 ]];then
           echo "snapshot progress is slow, but migration is still visible and regions are changing, continue first fault injection."
           v_ready_to_inject=1
        fi
     fi
     if [[ ${v_ready_to_inject} = 1 ]];then
        ssh ${u_name}@${v_remove_coord_ip} "sudo ${db_dir}/sbin/stop-datanode.sh" &
        ssh ${u_name}@${v_cn_leader_ip} "sudo ${db_dir}/sbin/stop-confignode.sh" &
        if [[ ${query_ip} = ${v_remove_coord_ip} ]];then
           query_ip=${v_add_coord_ip}
        fi
        break
     fi
     sleep 5
  done

  v_start_time=`date +%s`
  while true
  do
     v_pid=`ssh ${u_name}@${v_remove_coord_ip} "sudo jps|grep -i datanode|wc -l"`
     if [[ ${v_pid} -gt 0 ]];then
        v_end_time=`date +%s`
        v_elp=$((v_end_time-v_start_time))
        if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
           let fail_flag++
           write_test_result
           return 1
        fi
        sleep 3
     else
        v_stop_time=`date +%s`
        ssh ${u_name}@${v_remove_coord_ip} "sudo mkdir ${db_dir}/logs/logs_stop_remove_coord_${v_stop_time}"
        ssh ${u_name}@${v_remove_coord_ip} "sudo mv ${db_dir}/logs/*datanode* ${db_dir}/logs/logs_stop_remove_coord_${v_stop_time}"
        break
     fi
  done

  v_start_time=`date +%s`
  while true
  do
     v_pid=`ssh ${u_name}@${v_cn_leader_ip} "sudo jps|grep -i confignode|wc -l"`
     if [[ ${v_pid} -gt 0 ]];then
        v_end_time=`date +%s`
        v_elp=$((v_end_time-v_start_time))
        if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
           let fail_flag++
           write_test_result
           return 1
        fi
        sleep 3
     else
        break
     fi
  done

  capture_migration_visible_state "after_fault_injection_before_recovery"

  v_start_time=`date +%s`
  ssh ${u_name}@${v_remove_coord_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
  while true
  do
     v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes"|grep ${v_remove_coord_ip}|grep -i Running|wc -l`
     if [[ ${v_check_status} -gt 0 ]];then
        break
     else
        v_end_time=`date +%s`
        v_elp=$((v_end_time-v_start_time))
        if [[ ${v_elp} -gt 180 ]];then
           let fail_flag++
           break
        fi
        sleep 2
     fi
  done

  v_start_time=`date +%s`
  ssh ${u_name}@${v_cn_leader_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-confignode.sh > /dev/null 2>&1 &"
  while true
  do
     v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes"|grep ${v_cn_leader_ip}|grep -i Running|wc -l`
     if [[ ${v_check_status} -gt 0 ]];then
        break
     else
        v_end_time=`date +%s`
        v_elp=$((v_end_time-v_start_time))
        if [[ ${v_elp} -gt 180 ]];then
           let fail_flag++
           break
        fi
        sleep 2
     fi
  done

  wait_migration_visible_state_stable "after_recovery_before_second_mig"

  refresh_region_runtime_info
  v_mig_to_dn_id=-1
  line=`tail -1 ${cur_dir}/mig_id_info.txt`
  if [[ ${line} = "" ]];then
     let fail_flag++
     write_test_result
     return 1
  fi

  v_mig_from_dn_id=`echo ${line}|awk -F ',' '{print $1}'`
  if [[ ${v_mig_to_dn_id} -lt 0 ]];then
     v_mig_to_dn_id=`select_target_dn`
  fi
  if [[ ${v_mig_to_dn_id} = "" ]];then
     let fail_flag++
     write_test_result
     return 1
  fi

  v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
  v_bef_mig_time=`ssh ${u_name}@${v_cn_leader_ip} "date +\"%Y-%m-%d %H:%M:%S\""`
  v_bef_mig_sec=`date -d"${v_bef_mig_time}" +%s`
  capture_migration_visible_state "before_second_mig"
  v_semantic_migrations_empty=${v_migrations_empty}
  v_semantic_region_changing_count=${v_region_changing_count}
  if ! run_migrate_region_with_retry ${v_mig_id} ${v_mig_from_dn_id} ${v_mig_to_dn_id} ${cur_dir}/mig.out;then
     if [[ ${v_semantic_migrations_empty} = 1 && ${v_semantic_region_changing_count} = 0 ]] && grep -q "has some other region operation procedures in progress" ${cur_dir}/mig.out;then
        append_warn "migration semantic inconsistent: before retry show migrations is Empty set and show data regions has no Adding/Removing, but retry MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id} failed with region operation procedure in progress"
     else
        append_warn "second MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id} failed"
     fi
     let fail_flag++
     write_test_result
     return 1
  fi

  sleep 2
  wait_migration_visible_state_stable "after_second_mig"
  refresh_region_runtime_info
  v_check_to_dn=`grep -w "${v_mig_to_dn_id}" ${cur_dir}/mig_region_dn_id.txt|wc -l`
  v_check_from_dn=`grep -w "${v_mig_from_dn_id}" ${cur_dir}/mig_region_dn_id.txt|wc -l`
  if [[ ${v_check_to_dn} = 0 || ${v_check_from_dn} != 0 ]];then
     append_warn "second migration result unexpected: region ${v_mig_id} should be migrated from DataNode ${v_mig_from_dn_id} to ${v_mig_to_dn_id}, current replica DataNodes: `tr '\n' ',' < ${cur_dir}/mig_region_dn_id.txt`"
     let fail_flag++
  fi

  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "${query_consistency_sql}">${cur_dir}/q_act.out
  if grep -q "IoTDBSQLException" ${cur_dir}/q_act.out;then
     append_warn "final query (q_act.out) failed on ${query_ip}"
     let fail_flag++
  else
     v_check_res=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out |grep root|wc -l`
     if [[ ${v_check_res} != 0 ]];then
        append_warn "final query result differs from initial baseline"
        let fail_flag++
     fi
  fi

  v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
  if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
     append_warn "region ${v_mig_id} replica count is ${v_check_mig_regionid}, expected ${dr_rep_num}"
     let fail_flag++
  fi

  run_replica_consistency_check

  write_test_result
}

clean_env
start_db
pre_and_exec_mig_region

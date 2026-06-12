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
kill_flag=0
v_warnMessage=""
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
loop_timeout_sec=7200
mig_submit_timeout_sec=7200
: > "${cur_dir}/${fail_file}"
function clean_env()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
}


function set_sys_conf()
{
   local v_ip=$1
   local db_dir=$2
   # 定义远程机器的地址、用户名和要操作的文件
   local remote_host="${u_name}@${v_ip}"
   local remote_file="${db_dir}/conf/iotdb-system.properties"
   local search_str=$3
   local content=$4

# 定义远程命令
   remote_grep="ssh $remote_host grep -q '$search_str' '$remote_file'"
   remote_sed="ssh $remote_host \"sed -i 's|$search_str|$content|g' '$remote_file'\""
   remote_echo="ssh $remote_host 'echo \"$content\" >> \"$remote_file\"'"

# 检查文件是否包含字符串
        if eval $remote_grep; then
            # 如果字符串存在，则使用sed命令进行更新
            eval $remote_sed
        else
            # 如果字符串不存在，则追加内容
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
set_sys_conf ${line} ${db_dir} ".*region_migration_speed_limit_bytes_per_second=.*" "region_migration_speed_limit_bytes_per_second=0"
   set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=171966464"
  done
 
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

function append_warn_message()
{
  local v_msg="$1"
  if [[ -z "${v_msg}" ]];then
     return 0
  fi

  if [[ -z "${v_warnMessage}" ]];then
     v_warnMessage="${v_msg}"
  else
     v_warnMessage="${v_warnMessage}; ${v_msg}"
  fi
  echo "${SCRIPT_NAME} WARN: ${v_msg}" >> "${cur_dir}/${fail_file}"
}

function refresh_region_topology_files()
{
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;" > ${cur_dir}/show_data_regions_latest.out
  grep " ${v_mig_id}|[[:space:]]*DataRegion" ${cur_dir}/show_data_regions_latest.out | awk -F '|' '{gsub(" ","");print $8","$9}' > ${cur_dir}/mig_id_info.txt
  grep " ${v_mig_id}|[[:space:]]*DataRegion" ${cur_dir}/show_data_regions_latest.out | awk -F '|' '{gsub(" ","");print $8}' > ${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show datanodes' | grep Running | awk -F '|' '{gsub(" ","");print $2}' > ${cur_dir}/all_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show datanodes' | grep Running | awk -F '|' '{gsub(" ","");print $2","$4}' > ${cur_dir}/all_dn_id_ip.txt
}

function find_migrate_success_log()
{
  local v_region_id=$1
  local v_from_dn_id=$2
  local v_from_dn_ip=$3
  local v_to_dn_id=$4
  local v_to_dn_ip=$5
  local v_success_log=0

  exec 4<${nodeinfo_dir}/confignode.txt
  while read cn_line <&4
  do
     local v_check=`ssh ${u_name}@${cn_line} "grep -R \"\\[MigrateRegion\\] success\" ${db_dir}/logs 2>/dev/null | grep \"has been migrated from DataNode ${v_from_dn_id}@${v_from_dn_ip} to ${v_to_dn_id}@${v_to_dn_ip}\" | wc -l"`
     if [[ ${v_check} -gt 0 ]];then
        v_success_log=1
        break
     fi
  done
  exec 4<&-

  echo ${v_success_log}
}

function validate_target_peer_ready_after_migration()
{
  local v_region_id=$1
  local v_target_dn_id=$2
  local v_target_dn_ip=$3
  local v_add_coord_ip=$4
  local v_target_dn_stopped=$5

  local v_target_in_topology=`grep "^${v_target_dn_id}$" ${cur_dir}/mig_region_dn_id.txt 2>/dev/null | wc -l`
  if [[ ${v_target_in_topology} != 1 ]];then
     append_warn_message "CN migration success was found but target peer ${v_target_dn_id}@${v_target_dn_ip} is not in final topology for region ${v_region_id}"
     let fail_flag++
     return 1
  fi

  local v_create_peer_success_log=`ssh ${u_name}@${v_target_dn_ip} "grep -R \"Succeed to createNewRegionPeer\" ${db_dir}/logs 2>/dev/null | grep \"DataRegion\\[${v_region_id}\\]\" | wc -l"`
  if [[ ${v_create_peer_success_log} = 0 ]];then
     append_warn_message "CN migration success was found but target peer ${v_target_dn_id}@${v_target_dn_ip} has no createNewRegionPeer success log for region ${v_region_id}"
     let fail_flag++
     return 1
  fi

  local v_active_true_log=`ssh ${u_name}@${v_target_dn_ip} "grep -R \"set Peer{groupId=DataRegion\\[${v_region_id}\\], endpoint=TEndPoint(ip:${v_target_dn_ip}, port:10760), nodeId=${v_target_dn_id}} active status to true\" ${db_dir}/logs 2>/dev/null | wc -l"`
  if [[ ${v_active_true_log} = 0 ]] && [[ ${v_target_dn_stopped} = 0 ]];then
     append_warn_message "CN migration success was found but target peer ${v_target_dn_id}@${v_target_dn_ip} has no active=true log for region ${v_region_id}"
     let fail_flag++
     return 1
  fi

  local v_snapshot_fail_log=`ssh ${u_name}@${v_target_dn_ip} "grep -R -E \"Exception occurs when loading snapshot|Fail to load snapshot\" ${db_dir}/logs 2>/dev/null | wc -l"`
  if [[ ${v_snapshot_fail_log} != 0 ]];then
     append_warn_message "CN migration success was found but target DN ${v_target_dn_ip} still has snapshot load failure logs"
     let fail_flag++
     return 1
  fi

  local v_last_progress_line=`ssh ${u_name}@${v_add_coord_ip} "grep -R \"SNAPSHOT TRANSMISSION] The overall progress\" ${db_dir}/logs 2>/dev/null | tail -1"`
  if [[ -n "${v_last_progress_line}" ]];then
     local v_progress_ratio=`echo "${v_last_progress_line}" | sed -n 's/.*files \([0-9]\+\/[0-9]\+\) done.*/\1/p'`
     if [[ -n "${v_progress_ratio}" ]];then
        local v_done_file_num=`echo ${v_progress_ratio} | awk -F '/' '{print $1}'`
        local v_total_file_num=`echo ${v_progress_ratio} | awk -F '/' '{print $2}'`
        if [[ ${v_done_file_num} != ${v_total_file_num} ]];then
           append_warn_message "CN migration success was found but add coordinator ${v_add_coord_ip} latest snapshot transmission progress is still ${v_progress_ratio}"
           let fail_flag++
           return 1
        fi
     fi
  fi

  return 0
}

function validate_migration_failure_consistency()
{
  local v_region_id=$1
  local v_from_dn_id=$2
  local v_from_dn_ip=$3
  local v_to_dn_id=$4
  local v_to_dn_ip=$5

  local v_target_in_topology=`grep "^${v_to_dn_id}$" ${cur_dir}/mig_region_dn_id.txt 2>/dev/null | wc -l`
  local v_source_in_topology=`grep "^${v_from_dn_id}$" ${cur_dir}/mig_region_dn_id.txt 2>/dev/null | wc -l`
  local v_active_true_log=`ssh ${u_name}@${v_to_dn_ip} "grep -R \"set Peer{groupId=DataRegion\\[${v_region_id}\\], endpoint=TEndPoint(ip:${v_to_dn_ip}, port:10760), nodeId=${v_to_dn_id}} active status to true\" ${db_dir}/logs 2>/dev/null | wc -l"`
  local v_snapshot_fail_log=`ssh ${u_name}@${v_to_dn_ip} "grep -R -E \"Exception occurs when loading snapshot|Fail to load snapshot\" ${db_dir}/logs 2>/dev/null | wc -l"`

  if [[ ${v_active_true_log} != 0 ]];then
     append_warn_message "CN has no migration success log but target peer ${v_to_dn_id}@${v_to_dn_ip} became active for region ${v_region_id}"
     let fail_flag++
     return 1
  fi

  if [[ ${v_target_in_topology} = 1 ]] && [[ ${v_source_in_topology} = 0 ]];then
     append_warn_message "CN has no migration success log but final topology already moved region ${v_region_id} from ${v_from_dn_id}@${v_from_dn_ip} to ${v_to_dn_id}@${v_to_dn_ip}"
     let fail_flag++
     return 1
  fi

  if [[ ${v_source_in_topology} != 1 ]];then
     append_warn_message "CN has no migration success log and region ${v_region_id} source peer ${v_from_dn_id}@${v_from_dn_ip} is not kept in final topology"
     let fail_flag++
     return 1
  fi

  if [[ ${v_target_in_topology} = 0 ]];then
     return 0
  fi

  if [[ ${v_snapshot_fail_log} != 0 ]];then
     return 0
  fi

  append_warn_message "CN has no migration success log but region ${v_region_id} still keeps target peer ${v_to_dn_id}@${v_to_dn_ip} without clear DN failure evidence"
  let fail_flag++
  return 1
}

function wait_migration_terminal_and_refresh()
{
  local v_region_id=$1
  local v_from_dn_id=$2
  local v_from_dn_ip=$3
  local v_to_dn_id=$4
  local v_to_dn_ip=$5
  local v_add_coord_ip=$6
  local v_target_dn_stopped=$7
  local v_wait_start_sec=`date +%s`
  local v_prev_signature=""
  local v_same_signature_rounds=0
  local v_required_stable_rounds=5

  while true
  do
     refresh_region_topology_files
     cp ${cur_dir}/show_data_regions_latest.out ${cur_dir}/show_data_regions.out

     local v_region_transitioning=`grep " ${v_region_id}|[[:space:]]*DataRegion" ${cur_dir}/show_data_regions_latest.out | grep -E "Adding|Removing" | wc -l`
     local v_region_count=`grep " ${v_region_id}|[[:space:]]*DataRegion" ${cur_dir}/show_data_regions_latest.out | wc -l`
     local v_target_in_topology=`grep "^${v_to_dn_id}$" ${cur_dir}/mig_region_dn_id.txt 2>/dev/null | wc -l`
     local v_source_in_topology=`grep "^${v_from_dn_id}$" ${cur_dir}/mig_region_dn_id.txt 2>/dev/null | wc -l`
     local v_mig_suc_log=`find_migrate_success_log ${v_region_id} ${v_from_dn_id} ${v_from_dn_ip} ${v_to_dn_id} ${v_to_dn_ip}`
     local v_state_signature="${v_mig_suc_log}:${v_region_transitioning}:${v_region_count}:${v_source_in_topology}:${v_target_in_topology}"

     if [[ "${v_state_signature}" = "${v_prev_signature}" ]];then
        v_same_signature_rounds=$((v_same_signature_rounds+1))
     else
        v_prev_signature="${v_state_signature}"
        v_same_signature_rounds=1
     fi

     if [[ ${v_region_transitioning} = 0 ]] && [[ ${v_region_count} = ${dr_rep_num} ]] && [[ ${v_same_signature_rounds} -ge ${v_required_stable_rounds} ]];then
        if [[ ${v_mig_suc_log} = 1 ]];then
           if ! validate_target_peer_ready_after_migration ${v_region_id} ${v_to_dn_id} ${v_to_dn_ip} ${v_add_coord_ip} ${v_target_dn_stopped};then
              return 1
           fi
           return 0
        fi

        if ! validate_migration_failure_consistency ${v_region_id} ${v_from_dn_id} ${v_from_dn_ip} ${v_to_dn_id} ${v_to_dn_ip};then
           return 1
        fi
        return 0
     fi

     local v_wait_cur_sec=`date +%s`
     local v_wait_elp_sec=$((v_wait_cur_sec-v_wait_start_sec))
     if [[ ${v_wait_elp_sec} -gt ${loop_timeout_sec} ]];then
        append_warn_message "wait migration terminal timeout, region ${v_region_id} state did not stabilize to a terminal success or failure"
        let fail_flag++
        return 1
     fi
     sleep 3
  done
}

function wait_second_migration_terminal_by_topology()
{
  local v_region_id=$1
  local v_from_dn_id=$2
  local v_from_dn_ip=$3
  local v_to_dn_id=$4
  local v_to_dn_ip=$5
  local v_wait_start_sec=`date +%s`

  while true
  do
     refresh_region_topology_files
     cp ${cur_dir}/show_data_regions_latest.out ${cur_dir}/show_data_regions.out

     local v_region_transitioning=`grep " ${v_region_id}|[[:space:]]*DataRegion" ${cur_dir}/show_data_regions_latest.out | grep -E "Adding|Removing" | wc -l`
     if [[ ${v_region_transitioning} -gt 0 ]];then
        local v_wait_cur_sec=`date +%s`
        local v_wait_elp_sec=$((v_wait_cur_sec-v_wait_start_sec))
        if [[ ${v_wait_elp_sec} -gt ${loop_timeout_sec} ]];then
           append_warn_message "wait second migration terminal timeout, region ${v_region_id} still has Adding or Removing state"
           let fail_flag++
           return 1
        fi
        sleep 5
        continue
     fi

     local v_region_count=`grep " ${v_region_id}|[[:space:]]*DataRegion" ${cur_dir}/show_data_regions_latest.out | wc -l`
     local v_target_in_topology=`grep "^${v_to_dn_id}$" ${cur_dir}/mig_region_dn_id.txt 2>/dev/null | wc -l`
     local v_source_in_topology=`grep "^${v_from_dn_id}$" ${cur_dir}/mig_region_dn_id.txt 2>/dev/null | wc -l`

     if [[ ${v_region_count} != ${dr_rep_num} ]];then
        append_warn_message "second migration failed, final region ${v_region_id} replica count is ${v_region_count}, expected ${dr_rep_num}"
        let fail_flag++
        return 1
     fi

     if [[ ${v_target_in_topology} = 1 ]] && [[ ${v_source_in_topology} = 0 ]];then
        return 0
     fi

     if [[ ${v_source_in_topology} = 1 ]] && [[ ${v_target_in_topology} = 0 ]];then
        append_warn_message "second migration failed, final topology still keeps source peer ${v_from_dn_id}@${v_from_dn_ip} and target peer ${v_to_dn_id}@${v_to_dn_ip} is absent for region ${v_region_id}"
        let fail_flag++
        return 1
     fi

     append_warn_message "second migration failed, final topology is unexpected for region ${v_region_id}: source ${v_from_dn_id}@${v_from_dn_ip} present=${v_source_in_topology}, target ${v_to_dn_id}@${v_to_dn_ip} present=${v_target_in_topology}"
     let fail_flag++
     return 1
  done
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
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
     if [[ -n "${v_warnMessage}" ]];then
        echo "${SCRIPT_NAME} : ${v_warnMessage}" >> "${res_file}"
     fi
  fi

  ${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"
}

function start_db()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
   #start cluster
   head -n $cn_num ${nodeinfo_dir}/total_node.txt > ${nodeinfo_dir}/confignode.txt 
   set_conf
#copy data
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
           ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
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
ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
fi
done

   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"

}

function pre_and_exec_mig_region()
{
 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_exp.out

  v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  refresh_region_topology_files

local v_mig_to_dn_id=-1
  line=`head -1 ${cur_dir}/mig_id_info.txt`
   if [[ ${line} = "" ]];then
      let fail_flag++
      write_test_result
      return 1
   fi

   v_mig_from_dn_id=`echo ${line}|awk -F ',' '{print $1}'`
   v_mig_from_dn_ip=`echo ${line}|awk -F ',' '{print $2}'`
   v_mig_sec_dn_ip=`cat ${cur_dir}/mig_id_info.txt|grep -v ${line}|awk -F ',' '{print $2}'`
   if [[ ${v_mig_to_dn_id} -lt 0 ]];then
         for i in {1..4}
         do
             v_mig_to_dn_id=`awk "NR==${i}" ${cur_dir}/all_dn_id.txt`
             v_check=`grep ${v_mig_to_dn_id} ${cur_dir}/mig_region_dn_id.txt|wc -l`
             if [[ ${v_check} = 0 ]];then
                break
             fi
         done
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
# check adding
   if [[ ${kill_flag} -lt 1 ]];then
           v_start_time=`date +%s`
	   while true
	   do
	      if ssh ${u_name}@${v_cn_leader_ip} '[ -f "${db_dir}/logs/log-confignode-all*gz" ]'; then
		 ssh ${u_name}@${v_cn_leader_ip} "sudo gunzip ${db_dir}/logs/log-confignode-all*"
	      fi
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
   fi
# get Add Coord ip
   v_submit_mig_log=`ssh ${u_name}@${v_cn_leader_ip} "grep \"Submit RegionMigrateProcedure successfully, Region: TConsensusGroupId(type:DataRegion, id:${v_mig_id}), Origin DataNode: TDataNodeLocation(dataNodeId:${v_mig_from_dn_id},\" ${db_dir}/logs/*confignode*all*"`
   v_add_coord_ip=`echo ${v_submit_mig_log} |awk -F "Add Coordinator:" '{print $2}'|awk -F "ip:" '{print $2}'|awk -F ',' '{print $1}'`
   v_mig_to_dn_ip=`grep "${v_mig_to_dn_id}," ${cur_dir}/all_dn_id_ip.txt|awk -F ',' '{print $2}'`
# get Remove Coord IP
   v_remove_coord_ip=`echo ${v_submit_mig_log} |awk -F "Remove Coordinator:" '{print $2}'|awk -F "ip:" '{print $2}'|awk -F ',' '{print $1}'`
   v_target_dn_stopped=0
   if [[ ${v_remove_coord_ip} = ${v_mig_to_dn_ip} ]];then
      v_target_dn_stopped=1
   fi
# check snapshot
   v_start_time=`date +%s`
   while true
   do
      if ssh ${u_name}@${v_add_coord_ip} '[ -f "${db_dir}/logs/log-datanode-all*gz" ]'; then
         ssh ${u_name}@${v_add_coord_ip} "sudo gunzip ${db_dir}/logs/log-datanode-all*"
      fi
      v_AddRegion=`ssh ${u_name}@${v_add_coord_ip} "grep \"SNAPSHOT TRANSMISSION] The overall progress\" ${db_dir}/logs/*datanode*all*|wc -l"`
      if [[ ${v_AddRegion} -gt 1 ]];then
         ssh ${u_name}@${v_mig_from_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh" &
         ssh ${u_name}@${v_mig_sec_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh" &
         ssh ${u_name}@${v_remove_coord_ip} "sudo ${db_dir}/sbin/stop-datanode.sh" &
         ssh ${u_name}@${v_cn_leader_ip} "sudo ${db_dir}/sbin/stop-confignode.sh" &
         let kill_flag++ 
	 query_ip=`grep -v ${v_remove_coord_ip} ${cur_dir}/all_dn_id_ip.txt|grep -v ${v_mig_from_dn_ip}|grep -v ${v_mig_sec_dn_ip}|head -1|awk -F ',' '{print $2}'`
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
# check stop dn pid

v_start_time=`date +%s`
while true
do
   v_pid=`ssh ${u_name}@${v_mig_from_dn_ip} "sudo jps|grep -i datanode|wc -l"`
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
	  ssh ${u_name}@${v_mig_from_dn_ip} "sudo mkdir ${db_dir}/logs/logs_stop_dn_${v_stop_time}"
	  ssh ${u_name}@${v_mig_from_dn_ip} "sudo mv ${db_dir}/logs/*datanode* ${db_dir}/logs/logs_stop_dn_${v_stop_time}"
          break
   fi
  
done

v_start_time=`date +%s`
while true
do
   v_pid=`ssh ${u_name}@${v_mig_sec_dn_ip} "sudo jps|grep -i datanode|wc -l"`
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
          ssh ${u_name}@${v_mig_sec_dn_ip} "sudo mkdir ${db_dir}/logs/logs_stop_dn_${v_stop_time}"
          ssh ${u_name}@${v_mig_sec_dn_ip} "sudo mv ${db_dir}/logs/*datanode* ${db_dir}/logs/logs_stop_dn_${v_stop_time}"
          break
   fi

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
          ssh ${u_name}@${v_remove_coord_ip} "sudo mkdir ${db_dir}/logs/logs_stop_dest_dn_${v_stop_time}"
          ssh ${u_name}@${v_remove_coord_ip} "sudo mv ${db_dir}/logs/*datanode* ${db_dir}/logs/logs_stop_dest_dn_${v_stop_time}"
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
          v_stop_time=`date +%s`
          ssh ${u_name}@${v_cn_leader_ip} "sudo mkdir ${db_dir}/logs/logs_stop_cn_leader_${v_stop_time}"
          ssh ${u_name}@${v_cn_leader_ip} "sudo mv ${db_dir}/logs/*confignode* ${db_dir}/logs/logs_stop_cn_leader_${v_stop_time}"
          break
   fi

done


# wait first migration procedure terminal state on a healthy DN
if ! wait_migration_terminal_and_refresh ${v_mig_id} ${v_mig_from_dn_id} ${v_mig_from_dn_ip} ${v_mig_to_dn_id} ${v_mig_to_dn_ip} ${v_add_coord_ip} ${v_target_dn_stopped};then
   write_test_result
   return 1
fi
# restart stop coord
v_start_time=`date +%s`
ssh ${u_name}@${v_mig_from_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
while true
do
      v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes"|grep ${v_mig_from_dn_ip}|grep -i Running|wc -l`
      if [[ ${v_check_status} -gt 0 ]];then
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
            let fail_flag++
            break
         fi
         sleep 2
      fi
done
v_start_time=`date +%s`

ssh ${u_name}@${v_mig_sec_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
while true
do
      v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes"|grep ${v_mig_sec_dn_ip}|grep -i Running|wc -l`
      if [[ ${v_check_status} -gt 0 ]];then
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
            let fail_flag++
            break
         fi
         sleep 2
      fi
done

ssh ${u_name}@${v_remove_coord_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
while true
do
      v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes"|grep ${v_remove_coord_ip}|grep -i Running|wc -l`
      if [[ ${v_check_status} -gt 0 ]];then
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
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
         if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
            let fail_flag++
            break
         fi
         sleep 2
      fi
done

refresh_region_topology_files

v_mig_to_dn_id=-1
  line=`tail -1 ${cur_dir}/mig_id_info.txt`
   if [[ ${line} = "" ]];then
      append_warn_message "refresh mig_id_info.txt is empty after first migration terminal check"
      let fail_flag++
      write_test_result
      return 1
   fi

   v_mig_from_dn_id=`echo ${line}|awk -F ',' '{print $1}'`
   if [[ ${v_mig_to_dn_id} -lt 0 ]];then
         for i in {1..4}
         do
             v_mig_to_dn_id=`awk "NR==${i}" ${cur_dir}/all_dn_id.txt`
             v_check=`grep ${v_mig_to_dn_id} ${cur_dir}/mig_region_dn_id.txt|wc -l`
             if [[ ${v_check} = 0 ]];then
                break
             fi
         done
   fi
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   v_bef_mig_time=`ssh ${u_name}@${v_cn_leader_ip} "date +\"%Y-%m-%d %H:%M:%S\""`
   v_bef_mig_sec=`date -d"${v_bef_mig_time}" +%s`
   v_mig_to_dn_ip=`grep "${v_mig_to_dn_id}," ${cur_dir}/all_dn_id_ip.txt|awk -F ',' '{print $2}'`
   v_mig_from_dn_ip=`grep "${v_mig_from_dn_id}," ${cur_dir}/all_dn_id_ip.txt|awk -F ',' '{print $2}'`
   if ! run_migrate_region_with_retry ${v_mig_id} ${v_mig_from_dn_id} ${v_mig_to_dn_id} ${cur_dir}/mig.out;then
      append_warn_message "second migration submit failed: `cat ${cur_dir}/mig.out 2>/dev/null`"
      let fail_flag++
   else
      wait_second_migration_terminal_by_topology ${v_mig_id} ${v_mig_from_dn_id} ${v_mig_from_dn_ip} ${v_mig_to_dn_id} ${v_mig_to_dn_ip}
   fi

 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_act.out
 v_check_res=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out |grep root|wc -l`
 if [[ ${v_check_res} != 0 ]];then
    append_warn_message "final query result diff count is ${v_check_res}"
    let fail_flag++
 fi

v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
   append_warn_message "final region ${v_mig_id} replica count is ${v_check_mig_regionid}, expected ${dr_rep_num}"
   let fail_flag++
fi

write_test_result

 
} 
clean_env
start_db
pre_and_exec_mig_region

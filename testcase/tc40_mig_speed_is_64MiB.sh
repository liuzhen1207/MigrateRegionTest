#!/bin/bash
# 2026-06-26 modify: increase region migration completion timeout from 1200s to 3600s.
# reason: tc40 64 MiB/s migration of an 8.85 GB region can stay in CHECK_ADD_REGION_PEER
# for more than 1200 seconds, causing a false timeout before migration really finishes.
# 2026-06-26 modify: replace CN success-log parsing with CLI polling result checks and local timing.
# reason: CN success log format is not stable enough for tc40, and global idle state alone cannot
# prove a submitted migration really reached the target DataNode.
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
v_warnMessage=""
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`

function append_warn()
{
   local v_msg=$1
   if [[ -z "${v_warnMessage}" ]];then
      v_warnMessage="${v_msg}"
   else
      v_warnMessage="${v_warnMessage}; ${v_msg}"
   fi
}

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
set_sys_conf ${line} ${db_dir} ".*region_migration_speed_limit_bytes_per_second=.*" "region_migration_speed_limit_bytes_per_second=67108864"
   set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=171966464"
  done
 
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

function wait_migration_complete()
{
   local v_mig_id=$1
   local v_mig_from_dn_id=$2
   local v_mig_to_dn_id=$3
   local show_migrations_file="${cur_dir}/show_migrations_${v_mig_id}_${v_mig_from_dn_id}_${v_mig_to_dn_id}.out"
   local show_regions_file="${cur_dir}/show_regions_${v_mig_id}_${v_mig_from_dn_id}_${v_mig_to_dn_id}.out"
   local stable_complete_cnt=0
   local seen_migration_activity=0
   local poll_interval_sec=10
   local wait_start_sec=`date +%s`

   while true
   do
      ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show migrations;" > "${show_migrations_file}" 2>&1
      ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions;" > "${show_regions_file}" 2>&1

      local mig_has_error=`grep -Ec "Exception|ERROR|Error" "${show_migrations_file}"`
      local region_has_error=`grep -Ec "Exception|ERROR|Error" "${show_regions_file}"`
      local mig_is_empty=`grep -Ec '^Empty set' "${show_migrations_file}"`
      local region_transition_cnt=`grep -E "Adding|Removing" "${show_regions_file}" | wc -l`

      if [[ ${mig_has_error} = 0 && ${region_has_error} = 0 ]];then
         if [[ ${mig_is_empty} = 0 || ${region_transition_cnt} -gt 0 ]];then
            seen_migration_activity=1
         fi
         if [[ ${seen_migration_activity} = 1 && ${mig_is_empty} -gt 0 && ${region_transition_cnt} = 0 ]];then
            stable_complete_cnt=$((stable_complete_cnt+1))
            if [[ ${stable_complete_cnt} -ge 3 ]];then
               break
            fi
         else
            stable_complete_cnt=0
         fi
      else
         stable_complete_cnt=0
      fi

      local wait_cur_sec=`date +%s`
      local wait_elp=$((wait_cur_sec-wait_start_sec))
      if [[ ${wait_elp} -gt 120 && ${seen_migration_activity} = 0 ]];then
         let fail_flag++
         return 1
      fi
      if [[ ${wait_elp} -gt 3600 ]];then
         let fail_flag++
         return 1
      fi
      sleep ${poll_interval_sec}
   done

   return 0
}

function collect_migration_speed_stat()
{
   local v_mig_time_sec=$1
   if [[ ${v_mig_time_sec} -gt 240 ]];then
      append_warn "migration elapsed ${v_mig_time_sec}s exceeded threshold 240s"
   fi
}

function check_migration_target_region()
{
   local v_mig_id=$1
   local v_mig_from_dn_id=$2
   local v_mig_to_dn_id=$3
   local show_data_regions_file="${cur_dir}/show_data_regions_${v_mig_id}_${v_mig_from_dn_id}_${v_mig_to_dn_id}.out"

   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;" > "${show_data_regions_file}" 2>&1

   local region_has_error=`grep -Ec "Exception|ERROR|Error" "${show_data_regions_file}"`
   local replica_cnt=`grep " ${v_mig_id}|[[:space:]]*DataRegion" "${show_data_regions_file}" | wc -l`
   local target_cnt=`grep " ${v_mig_id}|[[:space:]]*DataRegion" "${show_data_regions_file}" | awk -F '|' '{gsub(" ","");print $8}' | grep -xc "${v_mig_to_dn_id}"`
   local source_cnt=`grep " ${v_mig_id}|[[:space:]]*DataRegion" "${show_data_regions_file}" | awk -F '|' '{gsub(" ","");print $8}' | grep -xc "${v_mig_from_dn_id}"`

   if [[ ${region_has_error} != 0 || ${replica_cnt} != ${dr_rep_num} || ${target_cnt} != 1 || ${source_cnt} != 0 ]];then
      let fail_flag++
      return 1
   fi

   return 0
}

function check_migration_submit_result()
{
   local v_mig_submit_file=$1
   local submit_has_error=`grep -Ec "IoTDBSQLException|Exception|ERROR|Error|Fail to|Failed to" "${v_mig_submit_file}"`
   local submit_has_success=`grep -Eic "executed successfully|successfully|submit.*success" "${v_mig_submit_file}"`

   if [[ ${submit_has_error} != 0 || ${submit_has_success} = 0 ]];then
      let fail_flag++
      return 1
   fi

   return 0
}

function pre_and_exec_mig_region()
{
 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_exp.out

  v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8","$9}'>${cur_dir}/mig_id_info.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/all_dn_id_ip.txt

local v_mig_to_dn_id=-1
exec 3<${cur_dir}/mig_id_info.txt
while read line<&3
do
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
   local mig_begin_sec=`date +%s`
   local mig_submit_file="${cur_dir}/mig_${v_mig_id}_${v_mig_from_dn_id}_${v_mig_to_dn_id}.out"
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id};" > "${mig_submit_file}" 2>&1
   if ! check_migration_submit_result "${mig_submit_file}";then
      break
   fi
   if ! wait_migration_complete "${v_mig_id}" "${v_mig_from_dn_id}" "${v_mig_to_dn_id}";then
      break
   fi
   if ! check_migration_target_region "${v_mig_id}" "${v_mig_from_dn_id}" "${v_mig_to_dn_id}";then
      break
   fi
   local mig_end_sec=`date +%s`
   local v_mig_elapsed_sec=$((mig_end_sec-mig_begin_sec))
   collect_migration_speed_stat "${v_mig_elapsed_sec}"

   v_mig_to_dn_id=${v_mig_from_dn_id}
done
 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_act.out
 v_check_res=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out |grep root|wc -l`
 if [[ ${v_check_res} != 0 ]];then
    let fail_flag++
 fi

v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
   let fail_flag++
fi

test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))
tc_res=true

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
  fi
  if [[ -n "${v_warnMessage}" ]];then
     echo "${SCRIPT_NAME} : ${v_warnMessage}" >> "${res_file}"
     echo "warn_message=${v_warnMessage}"
  fi
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

 
} 
clean_env
start_db
pre_and_exec_mig_region

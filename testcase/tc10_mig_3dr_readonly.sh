#!/bin/bash
# migrate unknown data region,restart orig dn
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
source "${cur_dir}/../lib/archive_logs.sh"
trap 'archive_logs' EXIT
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
bm_dir=/data1/benchmark/bm_20240320_76af1a40
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-456 
fail_file="fail.log"
cn_num=3
dn_num=5
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/tc7_test_data
fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
tmp_out_file="tc${tc_num}_tmp.out"
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
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
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
     
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
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
   set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
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
function mig_region()
{
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_172),count(s_293),count(s_8),count(s_490),count(s_368),count(s_597),max_time(s_172),max_time(s_293),max_time(s_8),max_time(s_490),max_time(s_368),max_time(s_597) from root.test.g_0.** align by device;">${cur_dir}/q_exp.out
  v_check_data=`grep root.test.g_0 ${cur_dir}/q_exp.out|wc -l`
  if [[ ${v_check_data} = 0 ]];then
     let fail_flag++
  fi

  local v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep root|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8","$9","$12}'>${cur_dir}/mig_id_info.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/all_dn_id_ip.txt
  v_mig_from_dn_id=`cat ${cur_dir}/mig_id_info.txt|grep -v Leader|tail -1|awk -F ',' '{print $1}'`
exec 3<${cur_dir}/mig_id_info.txt
while read line<&3
do
  v_stop_dn_ip=`echo ${line}|awk -F ',' '{print $2}'`
# stop datanode
  ${cli_dir}/sbin/start-cli.sh -h ${v_stop_dn_ip} -e  'set system to readonly on local' 
done
# exec migrate
   for i in {1..4}
   do
     v_mig_to_dn_id=`awk "NR==${i}" ${cur_dir}/all_dn_id.txt`
     v_check=`grep ${v_mig_to_dn_id} ${cur_dir}/mig_region_dn_id.txt|wc -l`
     if [[ ${v_check} = 0 ]];then
        break
     fi 
   done
   query_ip=`grep "^${v_mig_to_dn_id}," ${cur_dir}/all_dn_id_ip.txt|awk -F ',' '{print $2}'`
   while true
   do
      v_check_stop=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|grep -i readonly|wc -l`
      if [[ ${v_check_stop} = 3 ]];then
         break
      else
         sleep 2
      fi
   done
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show cluster" > ${cur_dir}/${tmp_out_file}
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions" >> ${cur_dir}/${tmp_out_file}
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes" >> ${cur_dir}/${tmp_out_file}
   # 迁移前采集基线（全 CN 的 success/failed 计数），避免历史日志造成假通过
   v_cn_ips=`cat ${nodeinfo_dir}/confignode.txt 2>/dev/null | tr "\n" " "`
   [ -z "${v_cn_ips}" ] && v_cn_ips="${query_ip}"
   dn_ips=`cat ${nodeinfo_dir}/datanode.txt 2>/dev/null | tr "\n" " "`
   v_suc_before=0
   v_fail_before=0
   for _cn in ${v_cn_ips}; do
      _b=`ssh ${u_name}@${_cn} "grep -c '\[MigrateRegion\] success' ${db_dir}/logs/log_confignode_all.log 2>/dev/null; grep -cE 'sub-procedure .* failed|AddRegionPeerProcedure failed|DO_ADD_REGION_PEER result is FAIL|RegionMigrateProcedure will not continue' ${db_dir}/logs/log_confignode_all.log 2>/dev/null" 2>/dev/null`
      _s=`echo "${_b}" | sed -n '1p' | tr -dc '0-9'`
      _f=`echo "${_b}" | sed -n '2p' | tr -dc '0-9'`
      v_suc_before=$((v_suc_before + ${_s:-0}))
      v_fail_before=$((v_fail_before + ${_f:-0}))
   done
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id};"
    
   sleep 10 
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   t1=`date +%s`
   v_mig_state="timeout"
   v_mig_wait=${v_mig_wait:-1500}
   while true
   do
      v_mig_suc=0
      v_mig_fail=0
      # 遍历所有 CN：leader 可能切换，只看一个节点会漏判
      for _cn in ${v_cn_ips}; do
         _cnt=`ssh ${u_name}@${_cn} "grep -c '\[MigrateRegion\] success' ${db_dir}/logs/log_confignode_all.log 2>/dev/null; grep -cE 'sub-procedure .* failed|AddRegionPeerProcedure failed|DO_ADD_REGION_PEER result is FAIL|RegionMigrateProcedure will not continue' ${db_dir}/logs/log_confignode_all.log 2>/dev/null" 2>/dev/null`
         _s=`echo "${_cnt}" | sed -n '1p' | tr -dc '0-9'`
         _f=`echo "${_cnt}" | sed -n '2p' | tr -dc '0-9'`
         v_mig_suc=$((v_mig_suc + ${_s:-0}))
         v_mig_fail=$((v_mig_fail + ${_f:-0}))
      done
      # 成功：必须是相对基线的增量，避免历史日志造成假通过
      if [[ $((v_mig_suc - v_suc_before)) -gt 0 ]];then
         v_mig_state="success"
         v_del_suc=`ssh ${u_name}@${v_cn_leader_ip} "grep \"DELETE_OLD_REGION_PEER failed\" ${db_dir}/logs/log_confignode_all.log|wc -l"`
         if [[ ${v_del_suc} -gt 0 ]];then
            let fail_flag++
         fi
         break
      fi
      # 失败快速判据：子过程失败/回滚时立即判失败，不必等满超时
      if [[ $((v_mig_fail - v_fail_before)) -gt 0 ]];then
         let fail_flag++
         v_mig_state="failed"
         echo "MigrateRegion procedure failed (rollback detected), abort waiting."
         for _cn in ${v_cn_ips}; do
            ssh ${u_name}@${_cn} "grep -E 'sub-procedure .* failed|DO_ADD_REGION_PEER result is FAIL|RegionMigrateProcedure will not continue|RESET_PEER_LIST after' ${db_dir}/logs/log_confignode_all.log 2>/dev/null | tail -2" 2>/dev/null | sed "s/^/    [CN ${_cn}] /"
         done
         for _dn in ${dn_ips}; do
            _npe=`ssh ${u_name}@${_dn} "grep -c 'NullPointerException' ${db_dir}/logs/log_datanode_all.log 2>/dev/null" 2>/dev/null | tr -dc '0-9'`
            if [[ ${_npe:-0} -gt 0 ]];then
               echo "    [DN ${_dn}] NullPointerException x${_npe}"
               ssh ${u_name}@${_dn} "grep -A6 'NullPointerException' ${db_dir}/logs/log_datanode_all.log 2>/dev/null | tail -8" 2>/dev/null | sed 's/^/      /'
            fi
         done
         break
      fi
      sleep 5
      t2=`date +%s`
      t3=$((t2-t1))
      if [[ $((t3 % 60)) -lt 5 ]];then
         echo "  [MigrateRegion] waiting ${t3}s / ${v_mig_wait}s (suc+=$((v_mig_suc-v_suc_before)), fail+=$((v_mig_fail-v_fail_before)))"
      fi
      if [[ ${t3} -gt ${v_mig_wait} ]];then
         let fail_flag++
         v_mig_state="timeout"
         echo "${v_mig_wait} s ,MigrateRegion not success."
         break
      fi
   done
   echo "  MigrateRegion 结果: ${v_mig_state}"
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_172),count(s_293),count(s_8),count(s_490),count(s_368),count(s_597),max_time(s_172),max_time(s_293),max_time(s_8),max_time(s_490),max_time(s_368),max_time(s_597) from root.test.g_0.** align by device;">${cur_dir}/q_act.out
   v_query_is_same=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out|grep root|wc -l`
   if [[ ${v_query_is_same} -gt 0 ]];then
      let fail_flag++
   fi
   v_dest_is_running=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|grep Running|awk -F '|' '{gsub(" ","");print $8}'|grep ${v_mig_to_dn_id}|wc -l`
   if [[ ${v_dest_is_running} = 0 ]];then
      let fail_flag++
   fi
v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
if [[ ${v_check_mig_regionid} != 3 ]];then
   let fail_flag++
fi

#set running 
v_start_time=`date +%s`
exec 3<${cur_dir}/mig_id_info.txt
while read line<&3
do
  v_stop_dn_ip=`echo ${line}|awk -F ',' '{print $2}'`
  ${cli_dir}/sbin/start-cli.sh -h ${v_stop_dn_ip} -e  'set system to running on local'
done
sleep 3
      v_check_stop=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|grep -i Running|wc -l`
      if [[ ${v_check_stop} != 3 ]];then
         let fail_flag++
      fi
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_172),count(s_293),count(s_8),count(s_490),count(s_368),count(s_597),max_time(s_172),max_time(s_293),max_time(s_8),max_time(s_490),max_time(s_368),max_time(s_597) from root.test.g_0.** align by device;">${cur_dir}/q_act.out
   v_query_is_same=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out|grep root|wc -l`
   if [[ ${v_query_is_same} -gt 0 ]];then
      let fail_flag++
   fi

# ===== 检查 CN/DN 日志中是否出现空指针异常（含快照 NPE），有则判失败 =====
v_npe_total=0
v_npe_detail=""
v_warnMessage=""
exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
   v_npe_one=`ssh ${u_name}@${line} "grep -c 'NullPointerException' ${db_dir}/logs/log_confignode_all.log 2>/dev/null" 2>/dev/null | tr -dc '0-9'`
   if [[ -n ${v_npe_one} && ${v_npe_one} -gt 0 ]];then
      v_npe_total=$((v_npe_total+v_npe_one))
      v_npe_detail="${v_npe_detail} CN:${line}(x${v_npe_one})"
   fi
done
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
   v_npe_one=`ssh ${u_name}@${line} "grep -c 'NullPointerException' ${db_dir}/logs/log_datanode_all.log 2>/dev/null" 2>/dev/null | tr -dc '0-9'`
   if [[ -n ${v_npe_one} && ${v_npe_one} -gt 0 ]];then
      v_npe_total=$((v_npe_total+v_npe_one))
      v_npe_detail="${v_npe_detail} DN:${line}(x${v_npe_one})"
   fi
done
if [[ ${v_npe_total} -gt 0 ]];then
   let fail_flag++
   v_warnMessage="NullPointerException found in CN/DN logs:${v_npe_detail}"
   echo "================================================================"
   echo "FAIL: ${v_warnMessage}"
   echo "最后一条空指针堆栈（请保留现场并提交研发）："
   exec 3<${nodeinfo_dir}/datanode.txt
   while read line<&3
   do
      v_npe_one=`ssh ${u_name}@${line} "grep -c 'NullPointerException' ${db_dir}/logs/log_datanode_all.log 2>/dev/null" 2>/dev/null | tr -dc '0-9'`
      if [[ -n ${v_npe_one} && ${v_npe_one} -gt 0 ]];then
         ssh ${u_name}@${line} "grep -B2 -A12 'NullPointerException' ${db_dir}/logs/log_datanode_all.log 2>/dev/null | tail -16"
      fi
   done
   echo "================================================================"
   echo "${SCRIPT_NAME} : ${v_warnMessage}" >>"${res_file}"
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
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

}
clean_env
start_db
mig_region

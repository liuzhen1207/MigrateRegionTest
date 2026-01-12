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
bm_dir=/data1/benchmark/bm_20240320_76af1a40
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-456 
fail_file="fail.log"
cn_num=3
dn_num=5
dr_rep_num=2
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/3db_test_data_IoTV2
tmp_out_file="tc${tc_num}_tmp.out"
fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
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
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
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
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
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
ssh ${u_name}@${line} "sudo cp -rp ${backup_dir_on_cn_dn_host}/data ${db_dir}/ " &
done
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
        while true
        do
        v_check_cp=`ssh ${u_name}@${line} "sudo ps -ef|grep \"cp -rp\"|grep -v grep|wc -l"`
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
   local v_mig_id=$1
   local v_mig_from_dn_id=$2
   local v_mig_dest_dn_id=$3
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_dest_dn_id};" > ${cur_dir}/mig.out
   sleep 2
}
function stop_dest_dn1()
{
   if ssh ${u_name}@${v_mig_from_dn_ip1} "[ -f ${db_dir}/logs/log-datanode-all*gz ]"; then
      ssh ${u_name}@${v_mig_from_dn_ip1} "sudo gunzip ${db_dir}/logs/log-datanode-all*" 
   fi
   if ssh ${u_name}@${v_mig_from_dn_ip2} "[ -f ${db_dir}/logs/log-datanode-all*gz ]"; then
      ssh ${u_name}@${v_mig_from_dn_ip2} "sudo gunzip ${db_dir}/logs/log-datanode-all*"
   fi
   while true
   do
              v_start_transmit_snapshot1=`ssh ${u_name}@${v_mig_from_dn_ip1} "grep \"start to transmit snapshot\" ${db_dir}/logs/*datanode*all*|wc -l"`
              v_start_transmit_snapshot2=`ssh ${u_name}@${v_mig_from_dn_ip2} "grep \"start to transmit snapshot\" ${db_dir}/logs/*datanode*all*|wc -l"`
              v_start_transmit_snapshot=$((v_start_transmit_snapshot1+v_start_transmit_snapshot2))

	      if [[ ${v_start_transmit_snapshot} -gt 0 ]];then
                 v_dn_str=`ssh ${u_name}@${v_mig_dest_dn_ip1} "sudo jps|grep DataNode|grep -v grep"`
                 v_dn_pid=`echo ${v_dn_str}|awk '{print $1}'`
                 ssh ${u_name}@${v_mig_dest_dn_ip1} "sudo kill -9 ${v_dn_pid}"

#                 ssh ${u_name}@${v_mig_dest_dn_ip1} "sudo jps|grep -i 'datanode' |grep -v grep |awk '{print $2}'|sudo xargs -r kill"
		  while true
		  do
		      v_check_status=`ssh ${u_name}@${v_mig_dest_dn_ip1} "sudo jps|grep -i datanode|wc -l"`
		      if [[ ${v_check_status} -gt 0 ]];then
			 sleep 2 
		      else
			break 
		      fi
		  done
		 break
	      fi
          sleep 2
   done 
}
function stop_dest_dn2()
{
   if ssh ${u_name}@${v_mig_from_dn_ip1} "[ -f ${db_dir}/logs/log-datanode-all*gz ]"; then
      ssh ${u_name}@${v_mig_from_dn_ip1} "sudo gunzip ${db_dir}/logs/log-datanode-all*"
   fi
   if ssh ${u_name}@${v_mig_from_dn_ip2} "[ -f ${db_dir}/logs/log-datanode-all*gz ]"; then
      ssh ${u_name}@${v_mig_from_dn_ip2} "sudo gunzip ${db_dir}/logs/log-datanode-all*"
   fi
   while true
   do
              v_start_transmit_snapshot1=`ssh ${u_name}@${v_mig_from_dn_ip1} "grep \"start to transmit snapshot\" ${db_dir}/logs/*datanode*all*|wc -l"`
              v_start_transmit_snapshot2=`ssh ${u_name}@${v_mig_from_dn_ip2} "grep \"start to transmit snapshot\" ${db_dir}/logs/*datanode*all*|wc -l"`
              v_start_transmit_snapshot=$((v_start_transmit_snapshot1+v_start_transmit_snapshot2))
              if [[ ${v_start_transmit_snapshot} -gt 1 ]];then
                 v_dn_str=`ssh ${u_name}@${v_mig_dest_dn_ip2} "sudo jps|grep DataNode|grep -v grep"`
                 v_dn_pid=`echo ${v_dn_str}|awk '{print $1}'`
                 ssh ${u_name}@${v_mig_dest_dn_ip2} "sudo kill -9 ${v_dn_pid}"

#                  ssh ${u_name}@${v_mig_dest_dn_ip2} "sudo jps|grep -i 'datanode' |grep -v grep |awk '{print $2}'|sudo xargs -r kill"
                  while true
                  do
                      v_check_status=`ssh ${u_name}@${v_mig_dest_dn_ip2} "sudo jps|grep -i datanode|wc -l"`
                      if [[ ${v_check_status} -gt 0 ]];then
                         sleep 2
                      else
                        break
                      fi
                  done
                 break
              fi
          sleep 2
   done
}

function pre_and_exec_mig_region()
{
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_exp.out
  v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8","$9}'>${cur_dir}/mig_id_info.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/all_dn_id_ip.txt
  # set readonly ,stop dn
  v_mig_from_dn_ip1=`awk "NR==1" ${cur_dir}/mig_id_info.txt|awk -F ',' '{print $2}'`
  v_mig_from_dn_id1=`awk "NR==1" ${cur_dir}/mig_id_info.txt|awk -F ',' '{print $1}'`
  v_mig_from_dn_ip2=`awk "NR==2" ${cur_dir}/mig_id_info.txt|awk -F ',' '{print $2}'`
  v_mig_from_dn_id2=`awk "NR==2" ${cur_dir}/mig_id_info.txt|awk -F ',' '{print $1}'`
  v_mig_dest_dn_id1=`grep -v ${v_mig_from_dn_ip1} ${cur_dir}/all_dn_id_ip.txt|grep -v ${v_mig_from_dn_ip2}|head -1 |awk -F ',' '{print $1}'`
  v_mig_dest_dn_ip1=`grep -v ${v_mig_from_dn_ip1} ${cur_dir}/all_dn_id_ip.txt|grep -v ${v_mig_from_dn_ip2}|head -1 |awk -F ',' '{print $2}'`
  v_mig_dest_dn_id2=`grep -v ${v_mig_from_dn_ip1} ${cur_dir}/all_dn_id_ip.txt|grep -v ${v_mig_from_dn_ip2}|tail -1 |awk -F ',' '{print $1}'`
  v_mig_dest_dn_ip2=`grep -v ${v_mig_from_dn_ip1} ${cur_dir}/all_dn_id_ip.txt|grep -v ${v_mig_from_dn_ip2}|tail -1 |awk -F ',' '{print $2}'`
  query_ip=`grep -v ${v_mig_dest_dn_ip1} ${cur_dir}/all_dn_id_ip.txt|grep -v ${v_mig_dest_dn_ip2}|head -1 |awk -F ',' '{print $2}'`
  mig_region "${v_mig_id}" "${v_mig_from_dn_id1}" "${v_mig_dest_dn_id1}"
  v_submit_fail1=`grep "Submit RegionMigrateProcedure failed" ${cur_dir}/mig.out|wc -l`
  if [[ ${v_submit_fail1} = 0 ]];then 
     stop_dest_dn1 
  fi
  mig_region "${v_mig_id}" "${v_mig_from_dn_id2}" "${v_mig_dest_dn_id2}"
  v_submit_fail2=`grep "Submit RegionMigrateProcedure failed" ${cur_dir}/mig.out|wc -l`
  if [[ ${v_submit_fail2} = 0 ]];then
     stop_dest_dn2
  fi 
#  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_act.out
  # restart unknown
 v_start_time=`date +%s`
  if [[ ${v_submit_fail1} = 0 ]];then
  ssh ${u_name}@${v_mig_dest_dn_ip1} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"
  fi
  sleep 1
  if [[ ${v_submit_fail2} = 0 ]];then
  ssh ${u_name}@${v_mig_dest_dn_ip2} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"
  fi
  sleep 1
   while true
   do
      v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes"|grep ${v_mig_dest_dn_ip1}|grep -i Running|wc -l`
      if [[ ${v_check_status} -gt 0 ]];then
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt 120 ]];then
            let fail_flag++
            break
         fi
         sleep 2
      fi
   done
   while true
   do
      v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes"|grep ${v_mig_dest_dn_ip2}|grep -i Running|wc -l`
      if [[ ${v_check_status} -gt 0 ]];then
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt 120 ]];then
            let fail_flag++
            break
         fi
         sleep 2
      fi
   done

 
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_act.out
   v_query_is_same=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out|grep root|wc -l`
   if [[ ${v_query_is_same} -gt 0 ]];then
      let fail_flag++
   fi
t1=`date +%s`
while true
do
v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
   sleep 3
else
   break 
fi
t2=`date +%s`
elp=$((t2-t1))
if [[ ${elp} -gt 600 ]];then
let fail_flag++
break

fi
done
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
pre_and_exec_mig_region

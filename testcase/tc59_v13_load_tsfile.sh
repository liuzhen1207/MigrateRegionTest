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
sr_rep_num=3
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
load_source_data_test_dir=/data_bk/load_mig_backup/ip28_1c1d_v1341_FR/data/datanode/data/sequence/root.test.g_0
load_source_data_db_dir=/data_bk/load_mig_backup/ip28_1c1d_v1341_FR/data/datanode/data/sequence/root.db.g_0
load_sql_source_data_dir=/data/iotdb/autotest_backup/load_mig_backup/data/datanode/data/sequence/test_g_0
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
    
     v_exist_in_dn=`grep ${line} ${nodeinfo_dir}"  "datanode.txt|wc -l`
     if [[ ${v_exist_in_dn} = 0 ]];then
			
       	set_sys_conf ${line} ${db_dir} ".*cn_seed_config_node=.*"  "cn_seed_config_node=${seed_cn_ip}"
            set_sys_conf ${line} ${db_dir} ".*cn_internal_address=.*"  "cn_internal_address=${line}"
            set_sys_conf ${line} ${db_dir} ".*cn_metric_reporter_list=.*"  "cn_metric_reporter_list=PROMETHEUS"
            set_sys_conf ${line} ${db_dir} ".*cn_metric_level=.*"  "cn_metric_level=IMPORTANT"
            set_sys_conf ${line} ${db_dir} ".*cn_metric_prometheus_reporter_port=.*"  "cn_metric_prometheus_reporter_port=9081"
            set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*"  "schema_replication_factor=3"
            set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*"  "data_replication_factor=2"
            set_sys_conf ${line} ${db_dir} ".*default_storage_group_level=.*" "default_storage_group_level=2"
            set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
            set_sys_conf ${line} ${db_dir} ".*data_region_consensus_protocol_class=.*" "data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.IoTConsensus"
            set_sys_conf ${line} ${db_dir} ".*enable_auto_repair_compaction=.*"  "enable_auto_repair_compaction=false"

     fi 
  done

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"20G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"

     set_sys_conf ${line} ${db_dir} ".*cn_seed_config_node=.*"  "cn_seed_config_node=${seed_cn_ip}"
            set_sys_conf ${line} ${db_dir} ".*cn_internal_address=.*"  "cn_internal_address=${line}"
            set_sys_conf ${line} ${db_dir} ".*cn_metric_reporter_list=.*"  "cn_metric_reporter_list=PROMETHEUS"
            set_sys_conf ${line} ${db_dir} ".*cn_metric_level=.*"  "cn_metric_level=IMPORTANT"
            set_sys_conf ${line} ${db_dir} ".*cn_metric_prometheus_reporter_port=.*"  "cn_metric_prometheus_reporter_port=9081"

     set_sys_conf ${line} ${db_dir} ".*dn_seed_config_node=.*"  "dn_seed_config_node=${seed_cn_ip}"
     set_sys_conf ${line} ${db_dir} ".*dn_internal_address=.*"  "dn_internal_address=${line}"
     set_sys_conf ${line} ${db_dir} ".*dn_rpc_address=.*"  "dn_rpc_address=${line}"
     set_sys_conf ${line} ${db_dir} ".*dn_metric_reporter_list=.*"  "dn_metric_reporter_list=PROMETHEUS"
     set_sys_conf ${line} ${db_dir} ".*dn_metric_level=.*"  "dn_metric_level=IMPORTANT"
     set_sys_conf ${line} ${db_dir} ".*dn_metric_prometheus_reporter_port=.*"  "dn_metric_prometheus_reporter_port=9091"
     set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*"  "schema_replication_factor=3"
     set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*"  "data_replication_factor=2"
     set_sys_conf ${line} ${db_dir} ".*default_storage_group_level=.*" "default_storage_group_level=2"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
     set_sys_conf ${line} ${db_dir} ".*data_region_consensus_protocol_class=.*" "data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.IoTConsensus"
            set_sys_conf ${line} ${db_dir} ".*enable_auto_repair_compaction=.*"  "enable_auto_repair_compaction=false"
  done
 
}

function start_db()
{
   #clean env
   
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
   #start cluster 3C4D
   head -n $cn_num ${nodeinfo_dir}/total_node.txt > ${nodeinfo_dir}/confignode.txt 
   set_conf
   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"
}

function check_data_consistent()
{
   query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
   query_ip2=`tail -1 ${nodeinfo_dir}/datanode.txt`

   # all node online,query
    q1="select count(s_0) from root.test.g_0.** align by device;"
    q3="select count(s_0) from root.db.g_0.** align by device;"
    ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600000  -e "${q1}" > ${cur_dir}/q_all_online_test.out
    ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600000  -e "${q3}" > ${cur_dir}/q_all_online_table.out
    res_row_num1=`grep root.test ${cur_dir}/q_all_online_test.out|wc -l`
    res_row_num3=`grep root.db ${cur_dir}/q_all_online_table.out|wc -l`
    res_row_num3_exp=`grep Exception ${cur_dir}/q_all_online_table.out|wc -l`
   if [[ ${res_row_num1} = 0 ]];then
      let fail_flag++
      return 1
   fi
   if [[ ${res_row_num3} = 0 ]] || [[ ${res_row_num3_exp} -gt 0 ]];then
      let fail_flag++
      return 1
   fi
   res_q1=`cat ${cur_dir}/q_all_online_test.out|grep "100000|"|wc -l`
   if [[ ${res_q1} != 20000 ]];then
      let fail_flag++
      return 1
   fi
   res_q2=`cat ${cur_dir}/q_all_online_table.out|grep "100000|"|wc -l`
   if [[ ${res_q2} != 20000 ]];then
      let fail_flag++
      return 1
   fi

   # stop 1 datanode,query
   exec 3<${nodeinfo_dir}/datanode.txt
while read line <&3
do
v_ignore=`grep "${line}," ${cur_dir}/ignore_dn_list.txt|wc -l`
if [[ ${v_ignore} = 0 ]];then
   ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/stop-datanode.sh"
   if [[ "${line}" = "${query_ip}" ]];then
      q_node="${query_ip2}"
   else
      q_node="${query_ip}"
   fi
   while true
   do
           sleep 1
      v_running=`${cli_dir}/sbin/start-cli.sh -h ${q_node} -timeout 3600  -e "show cluster;" |grep ${line} |grep DataNode|grep Running|wc -l`
      v_jps=`ssh ${u_name}@${line} "source /etc/profile;sudo jps|grep DataNode|wc -l"`
      if [[ ${v_running} = 1 ]];then
              sleep 2
      else
              if [[ ${v_jps} = 0 ]];then
                 break
              else
                 sleep 2
              fi
      fi
   done
   v_ip=`echo ${line} |awk -F '.' '{print $4}'`
   ${cli_dir}/sbin/start-cli.sh -h ${q_node} -timeout 3600000  -e "${q1}" >${cur_dir}/q_stop_ip${v_ip}_test.out
   ${cli_dir}/sbin/start-cli.sh -h ${q_node} -timeout 3600000  -e "${q3}" > ${cur_dir}/q_stop_ip${v_ip}_table.out
   v_diff1=`diff ${cur_dir}/q_all_online_test.out ${cur_dir}/q_stop_ip${v_ip}_test.out|grep root|wc -l`
   v_diff3=`diff ${cur_dir}/q_all_online_table.out ${cur_dir}/q_stop_ip${v_ip}_table.out|grep root|wc -l`
   if [[ ${v_diff1} -gt 0 ]];then
      echo "stop ${line} q1 result diff all online."
      let fail_flag++
      return 1
   fi
   if [[ ${v_diff3} -gt 0 ]];then
      echo "stop ${line} q3 result diff all online."
      let fail_flag++
      return 1
   fi

#   echo "stop_node,${line};q_node,${q_node}"
   ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/${test_begin_sec}_query_dn.hprof > /dev/null 2>&1 &"
   while true
   do
           sleep 5
      v_running=`${cli_dir}/sbin/start-cli.sh -h ${q_node} -timeout 3600  -e "show cluster;" |grep ${line} |grep DataNode|egrep "Running|ReadOnly"|wc -l`
      if [[ ${v_running} = 1 ]];then
              break
      else
              sleep 5
      fi
   done

   let i++
fi
done
}


function start_load()
{
nohup sh -x ${cli_dir}/tools/load-tsfile.sh -h ${query_ip} -s "${load_source_data_test_dir}"  -os none -of none -tn 2 > ${cur_dir}/load_test.out &   
nohup sh -x ${cli_dir}/tools/load-tsfile.sh -h ${query_ip} -s "${load_source_data_db_dir}"  -os none -of none -tn 2 > ${cur_dir}/load_db.out &  
}
function mig_region()
{
# check load is finish
while true
do
v_load_test=`cat ${cur_dir}/load_test.out |grep "Total operation time"|wc -l`
v_load_db=`cat ${cur_dir}/load_db.out |grep "Total operation time"|wc -l`
if [[ ${v_load_test} = 1 ]] && [[ ${v_load_db} = 1 ]];then
   break
fi
sleep 5
done

#check write finish
exec 3<${nodeinfo_dir}/datanode.txt
while read line <&3
do
${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -timeout 36000 -e "flush;"
${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -timeout 36000 -e "flush;"

   while true
   do
	   last_log_str=`ssh ${u_name}@${line} "grep \"create a new tsfile\" ${db_dir}/logs/log_datanode_all.log |tail -1"` 
	   last_time_for=`echo ${last_log_str}|awk -F ',' '{print $1}'`
	   last_time_sec=`date -d"${last_time_for}" +%s`
	   cur_time_sec=`date +%s`
	   elp_sec=$((cur_time_sec-last_time_sec))
	   if [[ ${elp_sec} -gt 300 ]];then
	      break
           else
              sleep 60
	   fi
   done
done

>${cur_dir}/ignore_dn_list.txt
check_data_consistent
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
start_load
sleep 2m
mig_region

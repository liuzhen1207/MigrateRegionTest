#!/bin/bash
# org.apache.iotdb.consensus.iot.FastIoTConsensus, recovery
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
cli_dir=`cat ${conf_file}|grep ^client_db_dir|awk -F '=' '{print $2}'`
iotdb_host=`cat ${conf_file}|grep test_ip|awk -F '=' '{print $2}'`
v_cur_db=`cat ${conf_file}|grep v_cur_db|awk -F '=' '{print $2}'`
res_file="${cur_dir}/../test_result/res_${v_cur_db}.out"
clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
check_res_dir="${cur_dir}/../check_res"
SCRIPT_NAME=$(basename "$0")
cn_num=3
dn_num=5
head -n ${cn_num} ${nodeinfo_dir}/total_confignode.txt > ${nodeinfo_dir}/confignode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
query_ip=`tail -1 ${nodeinfo_dir}/datanode.txt`
total_node_num=$((cn_num+dn_num))
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
bm_dir=/data1/benchmark/bm_20231129_d43030e
fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
fail_log="fail.log"
function clean_env()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
}
clean_env

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
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
     v_exist_in_dn=`grep ${line} ${nodeinfo_dir}/datanode.txt|wc -l`
     if [[ ${v_exist_in_dn} = 0 ]];then
            set_sys_conf ${line} ${db_dir} ".*cn_internal_address=.*" "cn_internal_address=${line}"
            set_sys_conf ${line} ${db_dir} ".*cn_seed_config_node=.*" "cn_seed_config_node=${seed_cn_ip}"
            set_sys_conf ${line} ${db_dir} ".*cn_metric_reporter_list=.*" "cn_metric_reporter_list=PROMETHEUS"          
            set_sys_conf ${line} ${db_dir} ".*cn_metric_level=.*" "cn_metric_level=IMPORTANT"
            set_sys_conf ${line} ${db_dir} ".*cn_metric_prometheus_reporter_port=.*" "cn_metric_prometheus_reporter_port=9081"
            set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
            set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
            set_sys_conf ${line} ${db_dir} ".*data_region_consensus_protocol_class=.*"   "data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.FastIoTConsensus"
     fi
     
  done

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/datanode-env.sh"
     set_sys_conf ${line} ${db_dir} ".*cn_internal_address=.*" "cn_internal_address=${line}"
     set_sys_conf ${line} ${db_dir} ".*cn_seed_config_node=.*" "cn_seed_config_node=${seed_cn_ip}"
     set_sys_conf ${line} ${db_dir} ".*cn_metric_reporter_list=.*" "cn_metric_reporter_list=PROMETHEUS"
     set_sys_conf ${line} ${db_dir} ".*cn_metric_level=.*" "cn_metric_level=IMPORTANT"
     set_sys_conf ${line} ${db_dir} ".*cn_metric_prometheus_reporter_port=.*" "cn_metric_prometheus_reporter_port=9081"
     set_sys_conf ${line} ${db_dir} ".*dn_seed_config_node=.*"   "dn_seed_config_node=${seed_cn_ip}"
     set_sys_conf ${line} ${db_dir} ".*dn_internal_address=.*"   "dn_internal_address=${line}"
     set_sys_conf ${line} ${db_dir} ".*dn_rpc_address=.*"   "dn_rpc_address=${line}"
     set_sys_conf ${line} ${db_dir} ".*dn_metric_reporter_list=.*"   "dn_metric_reporter_list=PROMETHEUS"
     set_sys_conf ${line} ${db_dir} ".*dn_metric_level=.*"   "dn_metric_level=IMPORTANT"
     set_sys_conf ${line} ${db_dir} ".*dn_metric_prometheus_reporter_port=.*" "dn_metric_prometheus_reporter_port=9091"
     set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*"   "schema_replication_factor=3"
     set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*"   "data_replication_factor=2"
     set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*"   "schema_region_group_extension_policy=CUSTOM"
     set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*"   "data_region_group_extension_policy=CUSTOM"
     set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*"   "default_schema_region_group_num_per_database=2"
     set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*"   "default_data_region_group_num_per_database=2"
     set_sys_conf ${line} ${db_dir} ".*data_region_consensus_protocol_class=.*"   "data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.FastIoTConsensus"

  done
 
}

function start_db()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
   #start cluster 
   set_conf
   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}" 
}
start_db
function test1()
{
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "create timeseries root.db.d1.s1 BOOLEAN encoding=PLAIN;"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "create timeseries root.db.d1.s2 FLOAT encoding=RLE;"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "create timeseries root.db.d1.s3 TEXT encoding=PLAIN;"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "create timeseries root.db.d1.s4 INT32 encoding=PLAIN;"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "create timeseries root.db.d1.s5 INT64 encoding=PLAIN;"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "create timeseries root.db.d1.s6 DOUBLE encoding=PLAIN;"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "CREATE ALIGNED TIMESERIES root.db.d2(s1 BOOLEAN encoding=PLAIN, s2 FLOAT encoding=RLE,s3 TEXT encoding=PLAIN,s4 INT32 encoding=PLAIN,s5 INT64 encoding=PLAIN,s6 DOUBLE encoding=PLAIN) ;"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "insert into root.db.d1(time,s1,s2,s3,s4,s5,s6) values(1,true,1.1,'hello1',1,1,1.9);"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "insert into root.db.d2(time,s1,s2,s3,s4,s5,s6) values(2,true,1.1,'hello1',1,1,1.9);"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "select s1,s2,s3,s4,s5,s6 from root.db.* align by device;"|grep root >q_exp.out
  #kill -9 cluster
  exec 3<${nodeinfo_dir}/datanode.txt
  while read node<&3
  do
     v_pid_str=`ssh ${u_name}@${node} "sudo jps|grep -i datanode"`
     v_pid=`echo ${v_pid_str}|awk '{print $1}'`
     ssh ${u_name}@${node} "sudo kill -9 ${v_pid}"
     while true
     do
        v_pid_num=`ssh ${u_name}@${node} "sudo jps|grep -i datanode|wc -l"`
        if [[ ${v_pid_num} -gt 0 ]];then
           sleep 1
        else
           break
        fi
     done
  done

  exec 3<${nodeinfo_dir}/confignode.txt
  while read node<&3
  do
     v_pid_str=`ssh ${u_name}@${node} "sudo jps|grep -i confignode"`
     v_pid=`echo ${v_pid_str}|awk '{print $1}'`
     ssh ${u_name}@${node} "sudo kill -9 ${v_pid}"
     while true
     do
        v_pid_num=`ssh ${u_name}@${node} "sudo jps|grep -i confignode|wc -l"`
        if [[ ${v_pid_num} -gt 0 ]];then
           sleep 1
        else
           break
        fi
     done
  done

# restart
sh -x ${prepare_env_dir}/start_cluster.sh "2" "${total_node_num}" 

# re-query all on line
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "select s1,s2,s3,s4,s5,s6 from root.db.* align by device;"|grep root >q_act.out
v_diff=`diff q_exp.out q_act.out|wc -l`
if [[ ${v_diff} -gt 0 ]];then
   echo "After recovery query is not ok."
   let fail_flag++
else
     ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "flush;"
  #stop 1dn
  exec 3<${nodeinfo_dir}/datanode.txt
  while read node<&3
  do
     v_pid_str=`ssh ${u_name}@${node} "sudo jps|grep -i datanode"`
     v_pid=`echo ${v_pid_str}|awk '{print $1}'`
     ssh ${u_name}@${node} "sudo kill -9 ${v_pid}"
     while true
     do
        v_pid_num=`ssh ${u_name}@${node} "sudo jps|grep -i confignode|wc -l"`
        if [[ ${v_pid_num} -gt 0 ]];then
           sleep 1
        else
           break
        fi
     done
     ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "select s1,s2,s3,s4,s5,s6 from root.db.* align by device;"|grep root >q_act.out
     v_diff=`diff q_exp.out q_act.out|wc -l`
     if [[ ${v_diff} -gt 0 ]];then
        echo "After recovery query is not ok."
        let fail_flag++
     fi
     # restart dn
     ssh ${u_name}@${node} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
     while true
     do
        v_ok=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanode;"|grep ${node}|grep -i running|wc -l`
        if [[ ${v_ok} -gt 0 ]];then
           break
        else
           sleep 3
        fi 
     done
     query_ip=${node}
  done

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
test1

#!/bin/bash
# org.apache.iotdb.consensus.iot.FastIoTConsensus, data_replication_factor=2
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

function set_conf()
{
  exec 3<${nodeinfo_dir}/confignode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/^cn_seed_config_node=.*/cn_seed_config_node=${seed_cn_ip}/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/^cn_internal_address=.*/cn_internal_address=${line}/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_reporter_list=.*/cn_metric_reporter_list=PROMETHEUS/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_level=.*/cn_metric_level=IMPORTANT/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_prometheus_reporter_port=.*/cn_metric_prometheus_reporter_port=9081/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_replication_factor=.*/schema_replication_factor=3/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_replication_factor=.*/data_replication_factor=2/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/# schema_region_group_extension_policy=.*/schema_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/# data_region_group_extension_policy=.*/data_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=5/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=40/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_region_consensus_protocol_class=.*/data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.FastIoTConsensus/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*default_storage_group_level.*/default_storage_group_level=2/g' ${db_dir}/conf/iotdb-system.properties"     
  done

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"24G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/^dn_seed_config_node=.*/dn_seed_config_node=${seed_cn_ip}/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/^dn_internal_address=.*/dn_internal_address=${line}/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/^dn_rpc_address=.*/dn_rpc_address=${line}/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*dn_metric_reporter_list=.*/dn_metric_reporter_list=PROMETHEUS/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*dn_metric_level=.*/dn_metric_level=IMPORTANT/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_replication_factor=.*/schema_replication_factor=3/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_replication_factor=.*/data_replication_factor=2/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/# schema_region_group_extension_policy=.*/schema_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/# data_region_group_extension_policy=.*/data_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=5/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=40/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_region_consensus_protocol_class=.*/data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.FastIoTConsensus/g' ${db_dir}/conf/iotdb-system.properties"
     ssh ${u_name}@${line} "sed -i 's/.*default_storage_group_level.*/default_storage_group_level=2/g' ${db_dir}/conf/iotdb-system.properties"     

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
  test_time=`date +'%Y_%m_%d_%H_%M_%S'`
  bm_conn_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
  sed -i 's/.*TEST_MAX_TIME.*/TEST_MAX_TIME=600000/g' ${bm_dir}/conf/base*conf
  ${bm_dir}/run_tc.sh ${bm_conn_ip} base_1_ins.conf ${test_time}_1.out >/dev/null 2>&1 &
  ${bm_dir}/run_tc.sh ${bm_conn_ip} base_2_ins.conf ${test_time}_2.out >/dev/null 2>&1 &
  ${bm_dir}/run_tc.sh ${bm_conn_ip} base_3_ins.conf ${test_time}_3.out >/dev/null 2>&1 &
  ${bm_dir}/run_tc.sh ${bm_conn_ip} base_4_ins.conf ${test_time}_4.out >/dev/null 2>&1 &
  sleep 600
  while true
  do
     v_bm=`jps|grep -i app|wc -l`
     if [[ ${v_bm} -gt 0 ]];then
        sleep 30
     else
        break
     fi
  done
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "Flush;"
  #check error
  exec 3<${nodeinfo_dir}/datanode.txt
  while read node<&3
  do
     ssh ${u_name}@${node} "sudo gunzip ${db_dir}/logs/*datanode*all*"
     v_error=`ssh ${u_name}@${node} "grep ERROR ${db_dir}/logs/*datanode*all*|grep -v "Failed to execute create device template"|wc -l"`
     v_warn=`ssh ${u_name}@${node} "grep WARN ${db_dir}/logs/*datanode*all*|grep Exception|wc -l"`
     if [[ ${v_error} -gt 0 ]];then
        let fail_flag++
        echo "${node},ERROR: ${v_error},WARN: ${v_warn}"
        ssh ${u_name}@${node} "cp -rp ${db_dir}/logs ${db_dir}/logs_${test_time}_${SCRIPT_NAME}"
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
test1

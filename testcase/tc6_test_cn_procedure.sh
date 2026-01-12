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
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
v_ts_num_per_dev=60
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
clean_env


function set_conf()
{
  exec 3<${nodeinfo_dir}/confignode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/^cn_seed_config_node=.*/cn_seed_config_node=${seed_cn_ip}/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/^cn_internal_address=.*/cn_internal_address=${line}/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_reporter_list=.*/cn_metric_reporter_list=PROMETHEUS/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_level=.*/cn_metric_level=IMPORTANT/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_prometheus_reporter_port=.*/cn_metric_prometheus_reporter_port=9081/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_replication_factor=.*/schema_replication_factor=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_replication_factor=.*/data_replication_factor=2/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*config_node_ratis_snapshot_trigger_threshold=.*/config_node_ratis_snapshot_trigger_threshold=1000/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_region_ratis_snapshot_trigger_threshold=.*/schema_region_ratis_snapshot_trigger_threshold=10000/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# schema_region_group_extension_policy=.*/schema_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# data_region_group_extension_policy=.*/data_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=9/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*time_partition_interval=.*/time_partition_interval=86400000/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*wal_buffer_size_in_byte=.*/wal_buffer_size_in_byte=167772160/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*wal_file_size_threshold_in_byte=.*/wal_file_size_threshold_in_byte=104857600/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*wal_buffer_queue_capacity=.*/wal_buffer_queue_capacity=1000/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*iot_consensus_throttle_threshold_in_byte=.*/iot_consensus_throttle_threshold_in_byte=536870912000/g' ${db_dir}/conf/iotdb-common.properties"
     
  done

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"20G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/^dn_seed_config_node=.*/dn_seed_config_node=${seed_cn_ip}/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/^dn_internal_address=.*/dn_internal_address=${line}/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/^dn_rpc_address=.*/dn_rpc_address=${line}/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*dn_metric_reporter_list=.*/dn_metric_reporter_list=PROMETHEUS/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*dn_metric_level=.*/dn_metric_level=IMPORTANT/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_replication_factor=.*/schema_replication_factor=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_replication_factor=.*/data_replication_factor=2/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*config_node_ratis_snapshot_trigger_threshold=.*/config_node_ratis_snapshot_trigger_threshold=1000/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_region_ratis_snapshot_trigger_threshold=.*/schema_region_ratis_snapshot_trigger_threshold=10000/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# schema_region_group_extension_policy=.*/schema_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# data_region_group_extension_policy=.*/data_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=10/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=10/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*time_partition_interval=.*/time_partition_interval=86400000/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*wal_buffer_size_in_byte=.*/wal_buffer_size_in_byte=167772160/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*wal_file_size_threshold_in_byte=.*/wal_file_size_threshold_in_byte=104857600/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*wal_buffer_queue_capacity=.*/wal_buffer_queue_capacity=1000/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*iot_consensus_throttle_threshold_in_byte=.*/iot_consensus_throttle_threshold_in_byte=536870912000/g' ${db_dir}/conf/iotdb-common.properties"

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
   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"
   # check parameter value
   v_param_dn_str=`ssh ${u_name}@${query_ip} "grep schemaRatisConsensusSnapshotTriggerThreshold ${db_dir}/logs/log_datanode_all.log |head -1"`
   v_param_dn=`echo ${v_param_dn_str} |awk -F '=' '{print $2}'|awk -F ';' '{print $1}'`
   if [[ ${v_param_dn} != 10000 ]];then
      let fail_flag++
      echo " schemaRatisConsensusSnapshotTriggerThreshold values is wrong." >${fail_file}
   fi
   v_param_cn_str=`ssh ${u_name}@${query_cn_ip} "grep configNodeRatisSnapshotTriggerThreshold ${db_dir}/logs/log_confignode_all.log |head -1"`
   v_param_cn=`echo ${v_param_cn_str} |awk -F '=' '{print $2}'|awk -F ';' '{print $1}'`
   if [[ ${v_param_cn} != 1000 ]];then
      let fail_flag++
      echo " configNodeRatisSnapshotTriggerThreshold values is wrong." >>${fail_file}
   fi

}
start_db
function test1()
{
  test_time=`date +'%Y_%m_%d_%H_%M_%S'`
  bm_conn_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
  bm_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'`
  out_file="${test_time}_${bm_num}"
  ${bm_dir}/benchmark.sh -cf ${bm_dir}/conf_tc6_meta_1 > ${bm_dir}/${out_file}_1.out 
  ${bm_dir}/benchmark.sh -cf ${bm_dir}/conf_tc6_meta_2 > ${bm_dir}/${out_file}_2.out
  v_check_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600 -e "count devices root.test.g_0.d1_*"|grep " 20|"|wc -l`
  if [[ ${v_check_res} = 0 ]];then
     let fail_flag++
  fi

  v_check_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600 -e "count timeseries root.test.g_0.d2_*.**"|grep "  1000000|"|wc -l`
  if [[ ${v_check_res} = 0 ]];then
     let fail_flag++
  fi
  v_check_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600 -e "count timeseries root.test.g_0.d1_*.**"|grep " 2000000|"|wc -l`
  if [[ ${v_check_res} = 0 ]];then
     let fail_flag++
  fi
 
  v_check_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600 -e "count timeseries root.test.g_0.d2_*.**"|grep "  1000000|"|wc -l`
  if [[ ${v_check_res} = 0 ]];then
     let fail_flag++
  fi
v_check_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600 -e "select count(s_0) from root.test.g_0.d1_* align by device;"|grep " 1|"|wc -l`
  if [[ ${v_check_res} != 20 ]];then
     let fail_flag++
  fi

v_check_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600 -e "select count(s_0) from root.test.g_0.d2_* align by device;"|grep " 1|"|wc -l`
  if [[ ${v_check_res} != 100000 ]];then
     let fail_flag++
  fi


  # wait benchmark finished
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
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time,bm_throughput)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec},${bm_through});"

}
test1

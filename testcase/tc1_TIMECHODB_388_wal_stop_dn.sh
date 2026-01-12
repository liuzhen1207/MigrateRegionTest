#!/bin/bash
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
cn_num=1
dn_num=5
head -n ${cn_num} ${nodeinfo_dir}/total_confignode.txt > ${nodeinfo_dir}/confignode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
bm_ip=`head -1 ${nodeinfo_dir}/bm_node.txt`
bm_dir=/data/iotdb/benchmark/bm_20230609_f235604
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-388 
fail_flag=0
param_value=2147483648
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
SENSOR_NUMBER=60
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
     ssh ${u_name}@${line} "sed -i 's/^cn_seed_config_node=.*/cn_seed_config_node=${seed_cn_ip}/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/^cn_internal_address=.*/cn_internal_address=${line}/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_reporter_list=.*/cn_metric_reporter_list=PROMETHEUS/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_level=.*/cn_metric_level=IMPORTANT/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_prometheus_reporter_port=.*/cn_metric_prometheus_reporter_port=9081/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_replication_factor=.*/schema_replication_factor=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_replication_factor=.*/data_replication_factor=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# schema_region_group_extension_policy=.*/schema_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# data_region_group_extension_policy=.*/data_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=5/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=10/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*iot_consensus_throttle_threshold_in_byte=.*/iot_consensus_throttle_threshold_in_byte=5368709120/g' ${db_dir}/conf/iotdb-common.properties"
     
  done

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"24G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/^dn_seed_config_node=.*/dn_seed_config_node=${seed_cn_ip}/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/^dn_internal_address=.*/dn_internal_address=${line}/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/^dn_rpc_address=.*/dn_rpc_address=${line}/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*dn_metric_reporter_list=.*/dn_metric_reporter_list=PROMETHEUS/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*dn_metric_level=.*/dn_metric_level=IMPORTANT/g' ${db_dir}/conf/iotdb-datanode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_replication_factor=.*/schema_replication_factor=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_replication_factor=.*/data_replication_factor=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# schema_region_group_extension_policy=.*/schema_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# data_region_group_extension_policy=.*/data_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=5/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=10/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*iot_consensus_throttle_threshold_in_byte=.*/iot_consensus_throttle_threshold_in_byte=${param_value}/g' ${db_dir}/conf/iotdb-common.properties"

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
  ssh ${u_name}@${bm_ip} "${bm_dir}/run_tc.sh ${bm_conn_ip} tc1.conf ${test_time}_tc1.out >/dev/null 2>&1"
  dn_count=`cat ${nodeinfo_dir}/datanode.txt|wc -l`
  i=0
tac "${nodeinfo_dir}/datanode.txt">"${nodeinfo_dir}/tac_datanode.txt"
while true
do
exec 3<${nodeinfo_dir}/tac_datanode.txt
while read line<&3
do
  echo "check node ${line}"
             ssh ${u_name}@${line} "source /etc/profile;sudo gunzip ${db_dir}/logs/log-datanode-all*"
	     v_reject_count=`ssh ${u_name}@${line} "grep \"The write is rejected because the wal directory size has reached the threshold\" ${db_dir}/logs/*datanode*all*|wc -l"`
	     if [[ ${v_reject_count} -gt 3 ]];then
	        v_param_str=`ssh ${u_name}@${line} "grep \"The write is rejected because the wal directory size has reached the threshold\" ${db_dir}/logs/*datanode*all*|head -1"`
                v_param_check=`echo ${v_param_str}|grep ${param_value}|wc -l`
                if [[ ${v_param_check} != 1 ]];then
                   let fail_flag++
                fi
                check_flag=true
                break
             else
                sleep 5
	     fi
  done
  if [[ ${check_flag} = true ]];then
     break
  fi
done
exec 3<${nodeinfo_dir}/tac_datanode.txt
while read line<&3
do
                ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/stop-datanode.sh"
                t1=`date +%s`
                while true
                do
                   v_check=`ssh ${u_name}@${line} "source /etc/profile;sudo jps|grep -i datanode|wc -l"`
                   if [[ ${v_check} -gt 0 ]];then
                      sleep 1
                   else
                      t2=`date +%s`
                      t=$((t2-t1))
                      if [[ ${t} -gt 120 ]];then
                         
                         let fail_flag++
                      fi
                      break
                   fi
                done
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
# stop benchmark
exec 3<${nodeinfo_dir}/bm_node.txt
while read line <&3
do

        while true
        do
          bm_pid_str=`ssh ${u_name}@${line} "source /etc/profile;sudo jps|grep -i app|head -1"`
          bm_pid=`echo ${bm_pid_str}|awk '{print $1}'`
          if [[ "${bm_pid}" -gt 0 ]];then
             ssh ${u_name}@${line} "source /etc/profile;sudo kill -9 ${bm_pid}"
          else
             break
          fi
        done
done
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"
}
test1

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
bm_ip=`head -1 ${nodeinfo_dir}/bm_node.txt`
bm_dir=/data/iotdb/benchmark/bm_20231116_bbf690d
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
query_cn_ip=`head -1 ${nodeinfo_dir}/total_node.txt`
echo "${query_cn_ip}" > ${nodeinfo_dir}/confignode.txt
fail_log_file="fail.log"
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-456 
fail_flag=0
function set_conf()
{
  exec 3<${nodeinfo_dir}/confignode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"8G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/^cn_seed_config_node=.*/cn_seed_config_node=${seed_cn_ip}/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/^cn_internal_address=.*/cn_internal_address=${line}/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_reporter_list=.*/cn_metric_reporter_list=PROMETHEUS/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_level=.*/cn_metric_level=IMPORTANT/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*cn_metric_prometheus_reporter_port=.*/cn_metric_prometheus_reporter_port=9081/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${line} "sed -i 's/.*schema_replication_factor=.*/schema_replication_factor=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*data_replication_factor=.*/data_replication_factor=2/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# schema_region_group_extension_policy=.*/schema_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# data_region_group_extension_policy=.*/data_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=10/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=20/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*time_partition_interval=.*/time_partition_interval=86400000/g' ${db_dir}/conf/iotdb-common.properties"
     
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
     ssh ${u_name}@${line} "sed -i 's/.*data_replication_factor=.*/data_replication_factor=2/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# schema_region_group_extension_policy=.*/schema_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# data_region_group_extension_policy=.*/data_region_group_extension_policy=CUSTOM/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=10/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=20/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/.*time_partition_interval=.*/time_partition_interval=86400000/g' ${db_dir}/conf/iotdb-common.properties"

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
   sh -x ${prepare_env_dir}/start_cluster.sh "1" 
}
#start_db
function test1()
{
  test_time=`date +'%Y_%m_%d_%H_%M_%S'`
  bm_conn_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
  out_file="${test_time}_${v_cur_db}_tc2.out"
  ssh ${u_name}@${bm_ip} "${bm_dir}/run_tc.sh ${bm_conn_ip} tc2_timecho_456.conf ${out_file} >/dev/null 2>&1"
  # wait benchmark finished
  while true
  do
    v_pid_str=`ssh ${u_name}@${bm_ip} "jps|grep -i app|wc -l"`
    if [[ ${v_pid_str} -gt 0 ]];then
       sleep 10m
    else
       break
    fi 
  done
}
#test1
function check_res()
{
  bm_res_file="${bm_dir}/2024_01_11_18_22_41_v1311_0108_rc1_0f84b8c_tc2.out"
  bm_failPoint_str=`ssh ${u_name}@${bm_ip} "grep -i failOperation -A 1 ${bm_res_file}|tail -1"`
  bm_failPoint=`echo ${bm_failPoint_str} |awk '{print $5}'`
  bm_okPoint_str=`ssh ${u_name}@${bm_ip} "grep -i okpoint -A 1 ${bm_res_file}|tail -1"`
  bm_okPoint=`echo ${bm_okPoint_str} |awk '{print $3}'`
  bm_through_str=`ssh ${u_name}@${bm_ip} "grep throughput -A 1 ${bm_res_file}|tail -1 "`
  bm_through=`echo ${bm_through_str} |awk '{print $6}'`
  bm_through_low_base=19565057
  bm_fail_low_base=577440000
  sys_reject_count=`ssh ${u_name}@${bm_ip} "grep -i \"System rejected\" ${bm_res_file}|wc -l"`
  if [[ ${sys_reject_count} = 0 ]];then
     echo "${SCRIPT_NAME} warn,No System rejected over logs." >> ${fail_log_file} 
#     let fail_flag++
  fi

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     while true
     do
         ssh ${u_name}@${line} "source /etc/profile;sudo gunzip ${db_dir}/logs/log-datanode-all*"
         v_l0_tsfile=`ssh ${u_name}@${line} "find ${db_dir}/data -name *.tsfile|grep root.test|wc -l"`
         if [[ ${v_l0_tsfile} -lt 50000 ]];then
            break
         else
            sleep 300
         fi
     done
  done
  res_all_online=`${db_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_0) from root.test.** align by device;"|grep root |awk -F '|' '{sum+=$3*2000}END{print sum}'`
  if [[ ${res_all_online} != ${bm_okPoint} ]];then
     echo "${SCRIPT_NAME} warn,benchmark okPoint ${bm_okPoint} != all online query result ${res_all_online}." >> ${fail_log_file} 
#     let fail_flag++
  fi
  query_ip_2=`tail -1 ${nodeinfo_dir}/datanode.txt`
  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/stop-datanode.sh"
     while true
     do
        v_stop=`ssh ${u_name}@${line} "source /etc/profile;sudo jps|grep -i datanode|wc -l"`
        if [[ ${v_stop} -gt 0 ]];then
           sleep 2
        else
           break
        fi
     done
     if [[ ${line} = ${query_ip} ]];then
        q_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip_2}  -timeout 36000 -e 'select count(s_0) from root.test.** align by device;'|grep root |awk -F '|' '{sum+=$3*2000}END{print sum}'`
     else
        q_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -timeout 36000 -e 'select count(s_0) from root.test.** align by device;'|grep root |awk -F '|' '{sum+=$3*2000}END{print sum}'`
     fi
     if [[ ${q_res} != ${res_all_online} ]];then
        echo "stop ${line} query result ${q_res} != all online query result ${res_all_online}." >> ${fail_log_file} 
        let fail_flag++
     fi
     ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
     sleep 2
     while true
     do
        v_start=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 1200 -e "show cluster"|grep ${line}|grep -i datanode|grep -i running|wc -l`
        if [[ ${v_start} -gt 0 ]];then
           break
        else
           sleep 3
        fi
     done
     query_ip=${line}
  done
  if [[ ${fail_flag} = 0 ]];then
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
  else
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
  fi
}
check_res

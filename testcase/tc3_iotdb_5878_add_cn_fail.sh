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
bm_dir=/data/iotdb/benchmark/bm_20231116_bbf690d
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
     ssh ${u_name}@${line} "sed -i 's/# default_schema_region_group_num_per_database=.*/default_schema_region_group_num_per_database=3/g' ${db_dir}/conf/iotdb-common.properties"
     ssh ${u_name}@${line} "sed -i 's/# default_data_region_group_num_per_database=.*/default_data_region_group_num_per_database=9/g' ${db_dir}/conf/iotdb-common.properties"
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
  # stop 1 confignode
  stop_1_cn_ip=`tail -1 ${nodeinfo_dir}/confignode.txt`
  v_cn_status=`ssh ${u_name}@${query_ip} "${db_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show confignodes;'|grep ${stop_1_cn_ip}|grep Running|wc -l"`
  if [[ ${v_cn_status} = 1 ]];then
     ssh ${u_name}@${stop_1_cn_ip} "sudo ${db_dir}/sbin/stop-confignode.sh"
     while true
     do
       v_cn_status=`ssh ${u_name}@${query_ip} "${db_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show confignodes;'|grep ${stop_1_cn_ip}|grep Running|wc -l"`
       if [[ ${v_cn_status} = 0 ]];then
          break
       else
          sleep 1
       fi 
     done
  else
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
     echo "need to check ${stop_1_cn_ip} cn status ." >>"${fail_file}"
     exit
  fi
  test_time=`date +'%Y_%m_%d_%H_%M_%S'`
  bm_conn_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
  out_file="${test_time}_tc3.out"
  ssh ${u_name}@${bm_ip} "${bm_dir}/run_tc.sh ${bm_conn_ip} tc3.conf ${out_file} >/dev/null 2>&1"
  # wait benchmark finished
    v_cn_leader_str=`ssh ${u_name}@${query_ip} "${db_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show confignodes;'|grep Leader"`
    v_cn_leader_ip=`echo ${v_cn_leader_str}|awk -F '|' '{gsub(" ","");print $4}'`

  while true
  do
    ssh ${u_name}@${v_cn_leader_ip} "sudo gunzip ${db_dir}/logs/log-confignode-all*"
    v_snapshot_count=`ssh ${u_name}@${v_cn_leader_ip} "grep -i \"Took a snapshot\" ${db_dir}/logs/*confignode*all*|wc -l"`
    if [[ ${v_snapshot_count} -gt 3 ]];then
       ssh ${u_name}@${stop_1_cn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-confignode.sh -H ${db_dir}/cn_restart_heapdump.hprof > /dev/null 2>&1 &"
       while true
       do
          v_cn_status=`ssh ${u_name}@${query_ip} "${db_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show confignodes;'|grep ${stop_1_cn_ip}|grep Running|wc -l"`
	  if [[ ${v_cn_status} = 1 ]];then
             break
	  else
	     sleep 1 
	  fi
       done
       break 
    else
       sleep 5 
    fi 
  done
# restart confignode took snapshot,stop leader cn
  while true
  do
    ssh ${u_name}@${stop_1_cn_ip} "sudo gunzip ${db_dir}/logs/log-confignode-all*"
    v_snapshot_count=`ssh ${u_name}@${stop_1_cn_ip} "grep -i \"Took a snapshot\" ${db_dir}/logs/*confignode*all*|wc -l"`
    if [[ ${v_snapshot_count} -gt 2 ]];then
       ssh ${u_name}@${v_cn_leader_ip} "sudo ${db_dir}/sbin/stop-confignode.sh"
       while true
       do
          v_cn_status=`ssh ${u_name}@${query_ip} "${db_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show confignodes;'|grep ${v_cn_leader_ip}|grep Running|wc -l"`
          if [[ ${v_cn_status} = 0 ]];then
             break
          else
             sleep 1
          fi
        done
        break
    else
       sleep 5
    fi
  done
# start new cn node
forth_cn_ip=`sed -n 4p ${nodeinfo_dir}/total_node.txt`
echo "${forth_cn_ip}" >>${nodeinfo_dir}/confignode.txt
v_cn_leader_str=`ssh ${u_name}@${query_ip} "${db_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show confignodes;'|grep Leader"`
v_cn_new_leader_ip=`echo ${v_cn_leader_str}|awk -F '|' '{gsub(" ","");print $4}'`

     ssh ${u_name}@${forth_cn_ip} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${forth_cn_ip} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${forth_cn_ip} "sed -i 's/^cn_seed_config_node=.*/cn_seed_config_node=172.20.70.26:10710/g' ${db_dir}/conf/iotdb-confignode.properties"
     ssh ${u_name}@${forth_cn_ip} "sed -i 's/^cn_internal_address=.*/cn_internal_address=${forth_cn_ip}/g' ${db_dir}/conf/iotdb-confignode.properties"
     if ssh ${u_name}@${forth_cn_ip} test -f ${db_dir}/activation/license; then
        echo "license is exist."
     else
        if ssh ${u_name}@${forth_cn_ip} test -f ${db_dir}/../timecho_license_new; then
           ssh ${u_name}@${forth_cn_ip} "cp -rp ${db_dir}/../timecho_license_new ${db_dir}/activation/license"
        fi
     fi

     ssh ${u_name}@${forth_cn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-confignode.sh -H ${db_dir}/cn_heapdump.hprof > /dev/null 2>&1 &"
     v_begin_sec=`date +%s`
     while true
     do
          v_cn_status=`ssh ${u_name}@${query_ip} "${db_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show confignodes;'|grep ${forth_cn_ip}|grep Running|wc -l"`
          if [[ ${v_cn_status} = 1 ]];then
             break
          else
             sleep 1
          fi
          v_end_sec=`date +%s`
          start_time=$((v_end_sec-v_begin_sec))
          if [[ ${start_time} -gt 600 ]];then
             echo "${SCRIPT_NAME} : fail" >>"${res_file}"
             echo "start ${forth_cn_ip} 10min ,failed." >> ${fail_file}
             exit
          fi
     done

# check snapshot
  v_begin_sec=`date +%s`
  while true
  do
    ssh ${u_name}@${forth_cn_ip} "sudo gunzip log-confignode-all*"
    v_snapshot_count=`ssh ${u_name}@${forth_cn_ip} "grep -i \"Took a snapshot\" ${db_dir}/logs/*confignode*all*|wc -l"`
    if [[ ${v_snapshot_count} -gt 1 ]];then
       break
    else
       sleep 5
    fi
          v_end_sec=`date +%s`
          start_time=$((v_end_sec-v_begin_sec))
          if [[ ${start_time} -gt 1200 ]];then
             echo "${SCRIPT_NAME} : fail" >>"${res_file}"
             echo "start ${forth_cn_ip} 20min no snapshot." >> ${fail_file}
             exit
          fi

  done

# start orig leader cn , not change seed
     ssh ${u_name}@${v_cn_leader_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-confignode.sh -H ${db_dir}/cn_restart_heapdump.hprof > /dev/null 2>&1 &"
     v_begin_sec=`date +%s`
     while true
     do
          v_cn_status=`ssh ${u_name}@${query_ip} "${db_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show confignodes;'|grep ${v_cn_leader_ip}|grep Running|wc -l"`
          if [[ ${v_cn_status} = 1 ]];then
             break
          else
             sleep 1
          fi
          v_end_sec=`date +%s`
          start_time=$((v_end_sec-v_begin_sec))
          if [[ ${start_time} -gt 600 ]];then
             echo "${SCRIPT_NAME} : fail" >>"${res_file}"
             echo "start ${v_cn_leader_ip} 10min ,failed." >> ${fail_file}
             exit
          fi
     done

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
test1
function check_res()
{
  bm_res_file="${bm_dir}/${out_file}"
  bm_failPoint_str=`ssh ${u_name}@${bm_ip} "grep -i failOperation -A 1 ${bm_res_file}|tail -1"`
  bm_failPoint=`echo ${bm_failPoint_str} |awk '{print $5}'`
  bm_okPoint_str=`ssh ${u_name}@${bm_ip} "grep -i okpoint -A 1 ${bm_res_file}|tail -1"`
  bm_okPoint=`echo ${bm_okPoint_str} |awk '{print $3}'`
  bm_through_str=`ssh ${u_name}@${bm_ip} "grep throughput -A 1 ${bm_res_file}|tail -1 "`
  bm_through=`echo ${bm_through_str} |awk '{print $6}'`

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
      ssh ${u_name}@${line} "source /etc/profile;sudo gunzip ${db_dir}/logs/log-datanode-all*"
      ssh ${u_name}@${line} "${db_dir}/sbin/start-cli.sh -h ${line} -timeout 1200 -e 'flush'"
      while true
      do
         last_tsfile_time_str=`ssh ${u_name}@${line} "grep -h \"create a new\" ${db_dir}/logs/*datanode*all*|tail -1"`
         last_tsfile_time=`echo ${last_tsfile_time_str}|awk -F ',' '{print $1}'`
         last_tsfile_time_sec=`date -d "${last_tsfile_time}" +%s`
         os_time=`ssh ${u_name}@${line} date +%s`
         elp_time=$((os_time-last_tsfile_time_sec))
         if [[ ${elp_time} -gt 300 ]];then
            ssh ${u_name}@${line} "${db_dir}/sbin/start-cli.sh -h ${line} -timeout 1200 -e 'flush'"
            tsfile_l0_count=`ssh ${u_name}@${line} "grep \"create a new\" ${db_dir}/logs/*datanode*all*|wc -l"`
            echo "${line},level-0 tsfile count ${tsfile_l0_count}."
            break
         else
            sleep 20
         fi
      done
  done
  res_all_online_1ts=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_0) from root.test.** align by device;"|grep root |awk -F '|' '{sum+=$3}END{print sum}'`
  res_all_online=$((res_all_online_1ts*v_ts_num_per_dev))
  if [[ ${res_all_online} != ${bm_okPoint} ]];then
     echo "benchmark okPoint ${bm_okPoint} != all online query result ${res_all_online}." >> ${fail_file} 
     let fail_flag++
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
        q_res_1ts=`${cli_dir}/sbin/start-cli.sh -h ${query_ip_2}  -timeout 36000 -e 'select count(s_0) from root.test.** align by device;'|grep root |awk -F '|' '{sum+=$3}END{print sum}'`
        q_res=$((q_res_1ts*v_ts_num_per_dev))
     else
        q_res_1ts=`${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -timeout 36000 -e 'select count(s_0) from root.test.** align by device;'|grep root |awk -F '|' '{sum+=$3}END{print sum}'`
        q_res=$((q_res_1ts*v_ts_num_per_dev))
     fi
     if [[ ${q_res} != ${res_all_online} ]];then
        echo "stop ${line} query result ${q_res} != all online query result ${res_all_online}." >> ${fail_file} 
        let fail_flag++
     fi
     ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
     sleep 2
     while true
     do
        v_start=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 1200 -e "show cluster"|grep ${line}|grep -i datanode|grep -i running|wc -l`
        if [[ ${v_start} -gt 0 ]];then
           while true
           do
              v_region_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 1200 -e "show regions"|grep ${line}|grep -v Running|wc -l`
              if [[ ${v_region_status} = 0 ]];then
                 break
              else
                 sleep 1
              fi
           done
           break
        else
           sleep 3
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
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time,bm_throughput)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec},${bm_through});"

}
check_res

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
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-456 
fail_flag=0
out_file="2024_01_11_18_22_41_v1311_0108_rc1_0f84b8c_tc2.out"
function check_res()
{
  bm_res_file="${bm_dir}/${out_file}"
  bm_failPoint_str=`ssh ${u_name}@${bm_ip} "grep -i failOperation -A 1 ${bm_res_file}|tail -1"`
  bm_failPoint=`echo ${bm_failPoint_str} |awk '{print $5}'`
  bm_okPoint_str=`ssh ${u_name}@${bm_ip} "grep -i okpoint -A 1 ${bm_res_file}|tail -1"`
  bm_okPoint=`echo ${bm_okPoint_str} |awk '{print $3}'` 
  bm_through_str=`ssh ${u_name}@${bm_ip} "grep throughput -A 1 ${bm_res_file}|tail -1 "`
  bm_through=`echo ${bm_through_str} |awk '{print $6}'`
  bm_through_low_base=19565057
  bm_fail_low_base=577440000
  if awk 'BEGIN{exit !('${bm_through_low_base}' > '${bm_through}')}' ; then
     echo "benchmark throughput less than ${bm_through_low_base}(rc/1.3.0.1 rc4 1127 d2d1aa4 * 0.9)." >> ./tc2_fail.log
     let fail_flag++
  fi
  if [[ ${bm_failPoint} -gt ${bm_fail_low_base} ]];then
     echo "benchmark failPoint greater than ${bm_fail_low_base}(rc/1.3.0.1 rc4 1127 d2d1aa4 * 1.2)." >> ./tc2_fail.log
     let fail_flag++
  fi
  sys_reject_count=`ssh ${u_name}@${bm_ip} "grep -i \"System rejected\" ${bm_res_file}|wc -l"`
  if [[ ${sys_reject_count} = 0 ]];then
     echo "No System rejected over logs." >> ./tc2_fail.log
     let fail_flag++
  fi

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
  res_system=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select sum(value) from root.__system.** align by device;"|grep root|awk -F '|' '{sum+=$3}END{print sum}'`
  res_system_1rep=$((res_system/2))
  if [[ ${res_system_1rep} != ${bm_okPoint} ]];then
     echo "benchmark okPoint ${bm_okPoint} != system point ${res_system_1rep}." >> ./tc2_fail.log
     let fail_flag++
  fi
  res_all_online=`${db_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_0) from root.test.** align by device;"|grep root |awk -F '|' '{sum+=$3*2000}END{print sum}'`
  if [[ ${res_all_online} != ${bm_okPoint} ]];then
     echo "benchmark okPoint ${bm_okPoint} != all online query result ${res_all_online}." >> ./tc2_fail.log
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
        q_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip_2}  -timeout 36000 -e 'select count(s_0) from root.test.** align by device;'|grep root |awk -F '|' '{sum+=$3*2000}END{print sum}'`
     else
        q_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -timeout 36000 -e 'select count(s_0) from root.test.** align by device;'|grep root |awk -F '|' '{sum+=$3*2000}END{print sum}'`
     fi
     if [[ ${q_res} != ${res_all_online} ]];then
        echo "stop ${line} query result ${q_res} != all online query result ${res_all_online}." >> ./tc2_fail.log
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
  done 
  if [[ ${fail_flag} = 0 ]];then
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
  else
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
  fi
}
check_res

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
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/3db_test_data
tmp_out_file="tc${tc_num}_tmp.out"
fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`

function stop_db_query()
{
  stop_dn_ip=$1
  query_dn_ip=$2
  v_ip=`echo ${stop_dn_ip}|awk -F "." '{print $4}'`
  ssh ${u_name}@${stop_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh"
  while true
  do
     v_dn_pid=`ssh ${u_name}@${stop_dn_ip} "sudo jps|grep -i datanode|wc -l"`
     if [[ ${v_dn_pid} -gt 0 ]];then
        sleep 3
     else
        break
     fi
  done
  ${cli_dir}/sbin/start-cli.sh -h ${query_dn_ip} -timeout 36000 -e "select count(s_40) from root.test.** align by device;" > q_stop_ip${v_ip}.out
  v_diff=`diff ./q_all_online.out ./q_stop_ip${v_ip}.out|grep root.test|wc -l`
  if [[ ${v_diff} -gt 0 ]];then
     echo "stop ${stop_dn_ip} query result != all node online result."
  fi
# restart
ssh ${u_name}@${stop_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh > /dev/null 2>&1 &"
  while true
  do
     v_dn_status=`${cli_dir}/sbin/start-cli.sh -h ${query_dn_ip} -timeout 36000 -e "show datanodes;"|grep ${stop_dn_ip}|grep -i running|wc -l`
     if [[ ${v_dn_status} = 0 ]];then
        sleep 3
     else
        break
     fi
  done

}
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "flush;"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_40) from root.test.** align by device;" > q_all_online.out

query_ip_2=`tail -1 ${nodeinfo_dir}/datanode.txt`
query_ip_1=`head -1 ${nodeinfo_dir}/datanode.txt`
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
   if [[ ${line} = ${query_ip_2} ]];then
      query_ip=${query_ip_1}
   else
      query_ip=${query_ip_2}
   fi
   stop_db_query ${line} ${query_ip}
done 

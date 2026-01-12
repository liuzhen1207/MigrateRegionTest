#!/bin/bash
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-560 
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
nodeinfo_dir="${cur_dir}/../conf"
conf_file="${nodeinfo_dir}/test.conf"
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
bm_dir="${cur_dir}/../testtool/bm_20231129_d43030e"
# insert unseq data,kill -9 ,restart ,this dn has overlap
fail_flag=0
cn_num=1
dn_num=5
kill_num=1
total_num=$((cn_num+dn_num))
aft_kill_num=$((total_num-kill_num))
query_begin_index=$((kill_num+1))
   head -n $cn_num ${nodeinfo_dir}/total_confignode.txt > ${nodeinfo_dir}/confignode.txt
   head -n $dn_num ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
   head -n $dn_num ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
   sed -n "${query_begin_index},${dn_num}p" ${nodeinfo_dir}/datanode.txt > ${nodeinfo_dir}/query_datanode.txt 
   head -n ${kill_num}  ${nodeinfo_dir}/datanode.txt >> ${nodeinfo_dir}/query_datanode.txt 
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
faillog=${cur_dir}/fail.log
function stop_dn()
{
   stop_ip=$1
   q_ip=$2
        # stop  dn
        v_running=`${cli_dir}/sbin/start-cli.sh -h ${q_ip} -timeout 3600 -e "show cluster"|grep -i running|wc -l`
        if [[ ${v_running} = ${total_num} ]];then
                echo "The cluster status is ok."
        else
                exit
        fi
   v_date=`date +"%Y-%m-%d %H:%M:%S"`
   echo "stop ${stop_ip} at ${v_date}"
   ssh ${u_name}@${stop_ip} "source /etc/profile;sudo ${db_dir}/sbin/stop-datanode.sh"
   kill_1dn_node_num=$((total_num-1))
   while true
   do
           v_running=`${cli_dir}/sbin/start-cli.sh -h ${q_ip} -timeout 3600 -e "show cluster"|grep -i running|wc -l`
           if [[ ${v_running} = ${kill_1dn_node_num} ]];then
                   echo "The cluster status is ok.stop ${stop_ip} successfully."
#           v_dn_pid=`ssh ${u_name}@${stop_ip} "sudo jps|grep -i datanode|wc -l"`
#           if [[ ${v_dn_pid} -gt 0 ]];then
#             echo " DataNode pid is exist."
#              sleep 2
#           else
#             echo " DataNode pid is not exist."
#
#                   break
#           fi
              break
           else
                   sleep 2
           fi
   done
}
function start_dn()
{   
   # start ip
   stop_ip=$1
   q_ip=$2

   ssh ${u_name}@${stop_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh > /dev/null 2>&1 &"
   show_num=0
   while true
   do
           v_running=`${cli_dir}/sbin/start-cli.sh -h ${q_ip} -timeout 3600 -e "show cluster"|grep -i running|wc -l`
           if [[ ${v_running} = ${total_num} ]];then
                   echo "The cluster status is ok.start ${stop_ip} successfully."
                   break
           else
                   sleep 5 
                   ssh ${u_name}@${stop_ip} "source /etc/profile;sudo jps|grep -i datanode">${cur_dir}/tmp.txt
                   v_this_pid=`grep -v Warning ${cur_dir}/tmp.txt|wc -l`
                   if [[ ${v_this_pid} = 0 ]];then
                      let show_num++
                   fi
                   if [[ ${show_num} -gt 3 ]];then
                      ssh ${u_name}@${stop_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh > /dev/null 2>&1 &"
                      show_num=0
                   fi
           fi
   done 
}

function check_res()
{
desc=$1
   # exec flush
exec 3<${nodeinfo_dir}/datanode.txt
while read line <&3
do
   ${cli_dir}/sbin/start-cli.sh -h ${line} -e "flush"
done
# query result : all node online
q1_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
q2_ip=`tail -1 ${nodeinfo_dir}/datanode.txt`
${cli_dir}/sbin/start-cli.sh -h ${q1_ip} -timeout 36000 -e "select min_time(s_9),max_time(s_9),count(s_9) from root.test.** align by device;" > ${cur_dir}/tmp/${desc}_tmp_tc1_all.out
while read -u3 line1; do
   if [[ ${line1} = ${q1_ip} ]];then
      line2=${q2_ip}
    else
      line2=${q1_ip}
   fi
  echo "$line1" "$line2"
      stop_dn "${line1}" "${line2}"
   
   v_ip=`echo ${line1}|awk -F '.' '{print $4}'`
   ${cli_dir}/sbin/start-cli.sh -h ${line2} -timeout 36000 -e "select min_time(s_9),max_time(s_9),count(s_9) from root.test.** align by device;" > ${cur_dir}/tmp/${desc}_tmp_tc1_stop_ip${v_ip}.out
   check_res=`diff ${cur_dir}/tmp/tmp_tc1_all.out ${cur_dir}/tmp/tmp_tc1_stop_ip${v_ip}.out|grep root.test|wc -l`
   if [[ ${check_res} -gt 0 ]];then
	   let fail_flag++
   fi
   start_dn "${line1}" "${line2}" 
done 3<${nodeinfo_dir}/datanode.txt

  if [[ ${fail_flag} = 0 ]];then
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
  else
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"

  fi
}
for loop in {1..200}
do
check_res ${loop}
done

#!/bin/bash
db_dir=/data/iotdb/t_m_1218_2400c90
u_name="cluster"
q_ip=172.20.70.4
db_ip=172.20.70.27
while true
do
v_exit=`ssh ${u_name}@${db_ip} "grep \"DataNode exits\" ${db_dir}/logs/log_datanode_all.log|wc -l"`
if [[ ${v_exit} -gt 0 ]];then
   break
else
   sleep 10
fi
done
i=1
while true
do
   ${db_dir}/sbin/start-cli.sh -h ${q_ip} -timeout 36000 -e "show query processlist;" >> q_processlist.out &
   sleep 60 
   exec 3<./tmp_ip.txt
   while read line <&3
   do
   v_ip=`echo ${line} |awk -F '.' '{print $4}'`
   v_pid_str=`ssh ${u_name}@${line} "sudo jps|grep -i datanode"`
   v_pid=`echo ${v_pid_str} |awk '{print $1}'`
   ssh ${u_name}@${line} "sudo jstack -l ${v_pid}" > stack_stop27_${v_ip}_${i}.out
   done
   v_restart=`ssh ${u_name}@${db_ip} "grep enjoy ${db_dir}/logs/log_datanode_all.log|wc -l"`
   if [[ ${v_restart} -gt 1 ]];then
      exit
   fi
   wait
   let i++ 
done

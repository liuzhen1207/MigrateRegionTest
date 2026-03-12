#!/bin/bash
# db_dir need exist and is your expect.
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
client_db_dir=`cat ${conf_file}|grep ^client_db_dir|awk -F '=' '{print $2}'`
query_host=`head -1 ${cur_dir}/../conf/datanode.txt`
v_start_time=`date +%s`
cur_start_cluster_time=$1
total_node_num=$2
function start_cluster()
{
if [ $# = 0 ];then
   cur_start_count=1
   total_node_num=6
else
   cur_start_count=$1
   total_node_num=$2
fi

exec 4<${cur_dir}/../conf/confignode.txt
while read c_node <&4
do
	if ssh ${u_name}@${c_node} test -f ${db_dir}/activation/license; then
	echo "license is exist."
	else
	   if ssh ${u_name}@${c_node} test -f ${db_dir}/../timecho_license_new; then
	      ssh ${u_name}@${c_node} "cp -rp ${db_dir}/../timecho_license_new ${db_dir}/activation/license"
	      ssh ${u_name}@${c_node} "cp -rp ${db_dir}/../.env ${db_dir}/"
	   fi
	fi
	ssh ${u_name}@${c_node} "source /etc/profile;sudo ${db_dir}/sbin/start-confignode.sh -H ${db_dir}/cn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"
        sleep 1
#	while true
#	do 
#		sleep 1
#		ssh ${u_name}@${c_node} "source /etc/profile;sudo gunzip ${db_dir}/logs/log-confignode-all*"
#		v_check=`ssh ${u_name}@${c_node} "grep -i \"IoTDB-ConfigNode has successfully started\" ${db_dir}/logs/*confignode*all*|wc -l"`
#		if [[ ${v_check} = ${cur_start_count} ]];then
#		   break
#		fi 
#	done
done
exec 4<${cur_dir}/../conf/confignode.txt
while read c_node <&4
do
        while true
        do
                sleep 1
                ssh ${u_name}@${c_node} "source /etc/profile;sudo gunzip ${db_dir}/logs/log-confignode-all*"
                v_check=`ssh ${u_name}@${c_node} "grep -i \"IoTDB-ConfigNode has successfully.*and joined the cluster\" ${db_dir}/logs/*confignode*all*|wc -l"`
                if [[ ${v_check} = ${cur_start_count} ]];then
                   break
                fi
        done

done
exec 4<${cur_dir}/../conf/datanode.txt
while read d_node <&4
do
        ssh ${u_name}@${d_node} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"
        sleep 2 
done
# Strong password
while true
do
v_alter_user_pw=`${client_db_dir}/sbin/start-cli.sh -h ${query_host} -u root -pw root -e "alter user root set password 'TimechoDB@2021'"`
echo  "${v_alter_user_pw}"
v_succ=`echo  "${v_alter_user_pw}"|grep success|wc -l`
if [[ ${v_succ} -gt 0 ]];then
echo "alter user root pasword success."
break
fi
sleep 1
v_running=`${client_db_dir}/sbin/start-cli.sh -h ${query_host} -e "show cluster;"|grep Running |wc -l`
if [[ ${v_running} -gt 0 ]];then
break
fi
done
# continue
while true
do
   v_running=`${client_db_dir}/sbin/start-cli.sh -h ${query_host} -e "show cluster;"|grep Running |wc -l`
   v_readonly=`${client_db_dir}/sbin/start-cli.sh -h ${query_host} -e "show cluster;"|grep ReadOnly |wc -l`
   v_ok_num=$((v_running+v_readonly))
   if [[ ${total_node_num} = ${v_ok_num} ]];then
      return
   else
      sleep 1
   fi
done
}
start_cluster ${cur_start_cluster_time} ${total_node_num}

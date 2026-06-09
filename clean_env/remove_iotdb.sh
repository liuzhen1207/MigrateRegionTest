#!/bin/bash
# db_dir need exist and is your expect.
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`

function stop_cluster()
{
# stop all dn
exec 3<${cur_dir}/../conf/datanode.txt
while read line <&3 
do
	ssh ${u_name}@${line} "source /etc/profile;sudo rm -rf ${db_dir}/"
done
exec 3<${cur_dir}/../conf/confignode.txt
while read line <&3
do

        ssh ${u_name}@${line} "source /etc/profile;sudo	rm -rf ${db_dir}/"
done

# stop benchmark
#exec 3<${cur_dir}/../conf/bm_node.txt
#while read line <&3
#do
#
#        while true
#        do
#          bm_pid_str=`ssh ${u_name}@${line} "source /etc/profile;sudo jps|grep -i app|head -1"`
#          bm_pid=`echo ${bm_pid_str}|awk '{print $1}'`
#          if [[ "${bm_pid}" -gt 0 ]];then
#             ssh ${u_name}@${line} "source /etc/profile;sudo kill -9 ${bm_pid}" 
#          else
#             break
#          fi
#        done
#done

#stop local bm
jps|grep App|awk '{print "kill -9 "$1}'|sh
sleep 1
}
stop_cluster

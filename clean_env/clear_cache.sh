#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
exec 3<${cur_dir}/../conf/datanode.txt
while read d_node <&3
do
ssh ${u_name}@${d_node} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
done

exec 4<${cur_dir}/../conf/confignode.txt
while read c_node <&4
do
ssh ${u_name}@${c_node} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
done

exec 5<${cur_dir}/../conf/bm_node.txt
while read bm_node <&5
do
ssh ${u_name}@${bm_node} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
done


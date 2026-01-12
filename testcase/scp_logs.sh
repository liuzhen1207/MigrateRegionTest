#!/bin/bash
from_cluster_dir="/data1/iotdb"
cluster_dir="/data/iotdb"
from_cur_cluster="tablev2_rc1_1021_c2d28a2mig"
to_cur_cluster="tablev2_rc1_1021_c2d28a2mig"
desc=$1
u_name="cluster"
exec 3<./datanode.txt
while read line <&3
do
v_ip=`echo ${line}|awk -F '.' '{print $4}'`
mkdir -p ./${desc}/ip${v_ip}
scp -rp ${u_name}@${line}:${cluster_dir}/${from_cur_cluster}/logs/*all* ./${desc}/ip${v_ip}
done

exec 3<./confignode.txt
while read line <&3
do
v_check=`grep ${line} datanode.txt |wc -l`
if [[ ${v_check} = 0 ]];then
v_ip=`echo ${line}|awk -F '.' '{print $4}'`
mkdir -p ./${desc}/ip${v_ip}
scp -rp ${u_name}@${line}:${cluster_dir}/${from_cur_cluster}/logs/*all* ./${desc}/ip${v_ip}
fi
done
wait


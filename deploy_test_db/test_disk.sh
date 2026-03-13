#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
dest_db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
source_db_dir=`cat ${conf_file}|grep ^source_db_dir|awk -F '=' '{print $2}'`
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
   ssh ${u_name}@${line} "echo \"hello\" > ${dest_db_dir}/test.out;cat ${dest_db_dir}/test.out" &
   sleep 1
done
wait

exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
v_check=`grep ${line} ${nodeinfo_dir}/datanode.txt |wc -l`
if [[ ${v_check} = 0 ]];then
   ssh ${u_name}@${line} "echo \"hello\" > ${dest_db_dir}/test.out;cat ${dest_db_dir}/test.out" &
fi
done


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
   scp -rp ${source_db_dir} ${u_name}@${line}:${dest_db_dir} &
   sleep 1
done
wait

exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
v_check=`grep ${line} ${nodeinfo_dir}/datanode.txt |wc -l`
if [[ ${v_check} = 0 ]];then
   scp -rp ${source_db_dir} ${u_name}@${line}:${dest_db_dir}
fi
done


#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
dest_db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
source_db_dir=`cat ${conf_file}|grep ^source_db_dir|awk -F '=' '{print $2}'`

# unzip local 

if [ -f "${source_db_dir}/sbin/start-cli.sh" ]; then
    echo "success"
else
    unzip ${source_db_dir}/*.zip -d ${source_db_dir}/
    mv ${source_db_dir}/*-bin/* ${source_db_dir}/
    cp -rp ${source_db_dir}/conf ${source_db_dir}/conf_orig

    return 
fi

if [ -f "${source_db_dir}/conf_orig" ]; then
    echo "success"
else
    cp -rp ${source_db_dir}/conf ${source_db_dir}/conf_orig 
fi


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


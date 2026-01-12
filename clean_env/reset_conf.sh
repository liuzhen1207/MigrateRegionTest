#!/bin/bash
# db_dir need exist and is your expect.
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
client_db_dir=`cat ${conf_file}|grep ^client_db_dir|awk -F '=' '{print $2}'`
function reset_conf()
{

exec 3<${cur_dir}/../conf/confignode.txt
while read line <&3
do
   if ssh ${u_name}@${line} test -d ${db_dir}/conf; then
      if ssh ${u_name}@${line} test -d ${db_dir}/conf_orig; then
         ssh ${u_name}@${line} "source /etc/profile;sudo rm -rf ${db_dir}/conf"
         ssh ${u_name}@${line} "source /etc/profile;sudo cp -rp ${db_dir}/conf_orig ${db_dir}/conf"
      fi
   fi
done

exec 3<${cur_dir}/../conf/datanode.txt
while read line <&3
do
   if ssh ${u_name}@${line} test -d ${db_dir}/conf; then
      if ssh ${u_name}@${line} test -d ${db_dir}/conf_orig; then
         ssh ${u_name}@${line} "source /etc/profile;sudo rm -rf ${db_dir}/conf"
         ssh ${u_name}@${line} "source /etc/profile;sudo cp -rp ${db_dir}/conf_orig ${db_dir}/conf"
      fi
   fi
done

}
reset_conf

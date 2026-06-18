#!/bin/bash
# db_dir need exist and is your expect.
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`

function clean_cluster()
{
 
exec 3<${cur_dir}/../conf/datanode_5d.txt
while read line <&3
do
  if ssh ${u_name}@${line} test -d ${db_dir}/data; then
     ssh ${u_name}@${line} "source /etc/profile;sudo rm -rf ${db_dir}/data"
  fi
  if ssh ${u_name}@${line} test -d ${db_dir}/logs; then
     ssh ${u_name}@${line} "source /etc/profile;sudo rm -rf ${db_dir}/logs"
  fi
#  ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
done

exec 3<${cur_dir}/../conf/confignode_3c.txt
while read line <&3
do
  if ssh ${u_name}@${line} test -d ${db_dir}/data; then
     ssh ${u_name}@${line} "source /etc/profile;sudo rm -rf ${db_dir}/data"
  fi
  if ssh ${u_name}@${line} test -d ${db_dir}/logs; then
     ssh ${u_name}@${line} "source /etc/profile;sudo rm -rf ${db_dir}/logs"
  fi
#  ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
done

}
clean_cluster

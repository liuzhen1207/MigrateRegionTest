#!/bin/bash
# db_dir need exist and is your expect.
u_name="cluster"
db_dir="/data/iotdb/t_m_1017_7f4d7dd"
iotdb_host="172.20.70.28"
v_start_time=`date +%s`
function backup_logs()
{
  cn_pid=`sudo jps|grep -i confignode|awk '{print $1}'`
  if [[ "${cn_pid}" -gt 0 ]];then
     sudo kill -9 "${cn_pid}"
  fi
  dn_pid=`sudo jps|grep -i datanode|awk '{print $1}'`
  if [[ "${dn_pid}" -gt 0 ]];then
     sudo kill -9 "${dn_pid}"
  fi
  if [[ -d "${db_dir}/logs" ]];then
     sudo mv "${db_dir}/logs" "${db_dir}/logs_${v_start_time}_$1"
  fi

sudo -s <<EOF
echo 3>/proc/sys/vm/drop_caches
EOF
}
backup_data

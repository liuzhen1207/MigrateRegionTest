#!/bin/bash
from_ip=172.20.70.3
u_name="cluster"
install_dir="/data/iotdb"
src_dir="/data/iotdb/timecho/master/timechodb"
v_date_str=`ssh ${u_name}@${from_ip} "cd ${src_dir};git log|grep Date|head -1"`
v_date=`echo ${v_date_str}|awk '{print $2}'|awk -F "-" '{print $2$3}'`
v_commit=`ssh ${u_name}@${from_ip} "cd ${src_dir};git log"|head -1|awk '{print $2}'|cut -b 1-7`
db_commit=t_m_${v_date}_${v_commit}
db_dir="${install_dir}/${db_commit}"
dir="$( cd "$( dirname "$0"  )" && pwd  )"
if [ ! -d "${db_dir}" ];then
   mkdir "${db_dir}"
else
   if [[ "${db_dir}" != "" ]];then
      rm -rf ${db_dir}/* 
   fi
fi
scp -rp ${u_name}@${from_ip}:${src_dir}/distribution/target/iotdb-enterprise*-bin.zip ${db_dir}/ 
cd ${db_dir}
pack=`ls -l iotdb-enterprise*-bin.zip|awk '{print $9}'`
pack_name=`echo ${pack}|awk -F ".zip" '{print $1}'`

sleep 3

unzip ./${pack}

if [[ "${pack_name}" != "" ]];then
   mv ${pack_name}/* ./
fi

cp -rp conf conf_orig

cd "${dir}"

sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./check_comp_finish.sh 
sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./check_conf.sh
sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./create_aligned_dev.sh
sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./create_aligned_temp_dev.sh
sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./create_normal_dev.sh
sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./create_normal_temp_dev.sh
sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./set_conf.sh
sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./set_ip.sh
sed -i "s/^db_commit=.*/db_commit=${db_commit}/g" ./load_tsfile.sh

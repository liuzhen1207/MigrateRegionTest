#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Please input new db info."
    exit
fi
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
last_db=`cat ${conf_file}|grep v_cur_db|awk -F '=' '{print $2}'`
new_db=$1
sed -i "s/${last_db}/${new_db}/g" "${cur_dir}/../conf/test.conf"
last_commit=`cat ../conf/test.conf|grep v_commit|awk -F '=' '{print $2}'`
new_commit=`echo "${new_db}"|rev|cut -c1-7|rev`
sed -i "s/${last_commit}/${new_commit}/g" "${cur_dir}/../conf/test.conf"

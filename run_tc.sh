#!/bin/bash
v_host=$1
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
bm_conf_name=$2
res_file=$3
bm_conf_path="${cur_dir}/conf/${bm_conf_name}"
sed -i "s/^HOST=.*/HOST=${v_host}/g" ${bm_conf_path} 
cd ${cur_dir} 
sh -x test.sh  ${bm_conf_name} > ${cur_dir}/${res_file}

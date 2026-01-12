file_name=$1
n=1
#set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*"  "default_data_region_group_num_per_database=5"
#ssh ${u_name}@${line} "sed -i 's/^cn_seed_config_node=.*/cn_seed_config_node=${seed_cn_ip}/g' ${db_dir}/conf/iotdb-confignode.properties"
exec 3<./${file_name}
while read v_cmd <&3
do
  v_edit=`echo ${v_cmd}|grep properties |grep sed|wc -l`
   if [[ ${v_edit} = 1 ]];then
      echo $n
      v_param_value=`echo ${v_cmd}|awk -F '/' '{print $3}'`
      v_param_name=`echo ${v_param_value} |awk -F '=' '{print $1}'` 
#      v_new_line=`echo "set_sys_conf \${line} \${db_dir} \".*${v_param_name}=.*\" \"${v_param_value}\""`
#      echo ${v_new_line}
      sed -i "${n}s/.*/set_sys_conf \${line} \${db_dir} \".*${v_param_name}=.*\" \"${v_param_value}\"/" ${file_name}

   fi
   let n++
done

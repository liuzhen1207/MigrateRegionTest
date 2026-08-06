#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
iotdb_host=`cat ${conf_file}|grep test_ip|awk -F '=' '{print $2}'`
v_cur_db=`cat ${conf_file}|grep v_cur_db|awk -F '=' '{print $2}'`
cli_dir=`cat ${conf_file}|grep client_db_dir|awk -F '=' '{print $2}'`
res_file="${cur_dir}/../test_result/res_${v_cur_db}.out"
clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
check_res_dir="${cur_dir}/../check_res"
SCRIPT_NAME=$(basename "$0")
cn_num=3
dn_num=5
head -n ${cn_num} ${nodeinfo_dir}/total_node.txt > ${nodeinfo_dir}/confignode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
query_ip2=`head -2 ${nodeinfo_dir}/datanode.txt|tail -1`
fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
bm_conn_pw=`cat ${conf_file}|grep ^bm_conn_pw|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
bm_dir="/data1/iotdb/testcase/MigrateRegionTest/benchmark/bm_20260508_interval_v20"
bm_case_root="${bm_dir}/remove"
bm_work_root="${cur_dir}/bm_work_${tc_num}_${test_begin_sec}"
bm_log_root="${bm_work_root}/logs"
function clean_env()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
}


function set_sys_conf()
{
   local v_ip=$1
   local db_dir=$2
   # 定义远程机器的地址、用户名和要操作的文件
   local remote_host="${u_name}@${v_ip}"
   local remote_file="${db_dir}/conf/iotdb-system.properties"
   local search_str=$3
   local content=$4

# 定义远程命令
   remote_grep="ssh $remote_host grep -q '$search_str' '$remote_file'"
   remote_sed="ssh $remote_host \"sed -i 's|$search_str|$content|g' '$remote_file'\""
   remote_echo="ssh $remote_host 'echo \"$content\" >> \"$remote_file\"'"

# 检查文件是否包含字符串
        if eval $remote_grep; then
            # 如果字符串存在，则使用sed命令进行更新
            eval $remote_sed
        else
            # 如果字符串不存在，则追加内容
            eval $remote_echo
        fi
}
function set_conf()
{
  exec 3<${nodeinfo_dir}/confignode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/confignode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"1G\"/g' ${db_dir}/conf/confignode-env.sh"
set_sys_conf ${line} ${db_dir} ".*cn_seed_config_node=.*" "cn_seed_config_node=${seed_cn_ip}"
set_sys_conf ${line} ${db_dir} ".*cn_internal_address=.*" "cn_internal_address=${line}"
set_sys_conf ${line} ${db_dir} ".*cn_metric_reporter_list=.*" "cn_metric_reporter_list=PROMETHEUS"
set_sys_conf ${line} ${db_dir} ".*cn_metric_level=.*" "cn_metric_level=IMPORTANT"
set_sys_conf ${line} ${db_dir} ".*cn_metric_prometheus_reporter_port=.*" "cn_metric_prometheus_reporter_port=9081"
set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=2"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=2"
     
  done

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"20G\"/g' ${db_dir}/conf/datanode-env.sh"
     ssh ${u_name}@${line} "sed -i 's/#OFF_HEAP_MEMORY=.*/OFF_HEAP_MEMORY=\"2G\"/g' ${db_dir}/conf/datanode-env.sh"
set_sys_conf ${line} ${db_dir} ".*dn_seed_config_node=.*" "dn_seed_config_node=${seed_cn_ip}"
set_sys_conf ${line} ${db_dir} ".*dn_internal_address=.*" "dn_internal_address=${line}"
set_sys_conf ${line} ${db_dir} ".*dn_rpc_address=.*" "dn_rpc_address=${line}"
set_sys_conf ${line} ${db_dir} ".*dn_metric_reporter_list=.*" "dn_metric_reporter_list=PROMETHEUS"
set_sys_conf ${line} ${db_dir} ".*dn_metric_level=.*" "dn_metric_level=IMPORTANT"
set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=2"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=2"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
  done
 
}

function start_db()
{
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
   head -n $cn_num ${nodeinfo_dir}/total_node.txt > ${nodeinfo_dir}/confignode.txt 
   set_conf || return 1
   if ! timeout 900 sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}";then
      echo "Cluster did not start ${total_node_num} nodes within 900 seconds."
      return 1
   fi
   return 0
}
function run_query()
{
   local host=$1
   local dialect=$2
   local sql=$3
   local output_file=$4
   if [[ "${dialect}" = "table" ]];then
      ${cli_dir}/sbin/start-cli.sh -h ${host} -sql_dialect table -timeout 3600000 -e "${sql}" >"${output_file}" 2>&1
   else
      ${cli_dir}/sbin/start-cli.sh -h ${host} -sql_dialect tree -timeout 3600000 -e "${sql}" >"${output_file}" 2>&1
   fi
   if grep -qiE "(Exception|Error|failed)" "${output_file}";then
      cat "${output_file}"
      return 1
   fi
   return 0
}

function prepare_fresh_data()
{
   local workload
   local pid
   local running_num
   local start_time
   local output_file

   run_query ${query_ip} tree "create user santos '${bm_conn_pw}';" "${cur_dir}/create_bm_user.out" || return 1
   run_query ${query_ip} table "grant all to user santos;" "${cur_dir}/grant_bm_user.out" || return 1
   run_query ${query_ip} tree "create database root.view;" "${cur_dir}/create_root_view.out" || return 1

   mkdir -p "${bm_log_root}" || return 1
   for workload in tree_nonaligned tree_aligned tree_aligned_temp table
   do
      cp -rp "${bm_case_root}/${workload}" "${bm_work_root}/${workload}" || return 1
      sed -i "s/^HOST=.*/HOST=${query_ip}/g" "${bm_work_root}/${workload}/config.properties"
      sed -i "s/^LOOP=.*/LOOP=500/g" "${bm_work_root}/${workload}/config.properties"
      if [[ "${workload}" != "table" ]];then
         sed -i "s/^USERNAME=.*/USERNAME=root/g" "${bm_work_root}/${workload}/config.properties"
         sed -i "s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/g" "${bm_work_root}/${workload}/config.properties"
      fi
      nohup sh -x "${bm_dir}/benchmark.sh" -cf "${bm_work_root}/${workload}" >"${bm_log_root}/${workload}.out" 2>&1 &
      echo $! >"${bm_log_root}/${workload}.pid"
   done

   start_time=`date +%s`
   while true
   do
      running_num=0
      for workload in tree_nonaligned tree_aligned tree_aligned_temp table
      do
         pid=`cat "${bm_log_root}/${workload}.pid"`
         kill -0 ${pid} 2>/dev/null && let running_num++
      done
      [[ ${running_num} = 0 ]] && break
      if [[ $((`date +%s`-start_time)) -gt 7200 ]];then
         echo "Fresh-data benchmarks did not finish within 7200 seconds."
         return 1
      fi
      sleep 10
   done

   for workload in tree_nonaligned tree_aligned tree_aligned_temp table
   do
      output_file="${bm_log_root}/${workload}.out"
      if ! grep -q "Result Matrix" "${output_file}" || grep -Eq "Execution fail:|Failed to do |StatementExecutionException|WorkloadException|Connection error" "${output_file}";then
         echo "Fresh-data benchmark failed: ${workload}."
         tail -n 80 "${output_file}"
         return 1
      fi
   done

   run_query ${query_ip} tree "create view root.view.\${2}.view_from_\${3}(\${4}) as select * from root.db.**;" "${cur_dir}/create_view.out" || return 1
   run_query ${query_ip} tree "show devices root.view.g_0.**;" "${cur_dir}/show_view_devices.out" || return 1
   if ! grep -q "root.view.g_0." "${cur_dir}/show_view_devices.out";then
      echo "Fresh view data was not created."
      return 1
   fi
   return 0
}

function wait_dn_state()
{
   local host=$1
   local dn_ip=$2
   local state=$3
   local timeout_sec=$4
   local begin=`date +%s`
   while true
   do
      run_query ${host} tree "show datanodes;" "${cur_dir}/show_datanodes.out" || true
      if grep "${dn_ip}|" "${cur_dir}/show_datanodes.out" | grep -qi "${state}";then
         return 0
      fi
      if [[ $((`date +%s`-begin)) -gt ${timeout_sec} ]];then
         return 1
      fi
      sleep 2
   done
}

function check_data_consistent()
{
   local q1="select count(s_0) from root.test.g_0.** align by device;"
   local q2="select count(s_0) from root.db.g_0.** align by device;"
   local q3="select count(s_0) from root.view.g_0.** align by device;"
   local q4="select device_id,count(s_0) from db_table_g_0.table_0 group by device_id order by device_id;"
   local line q_node v_ip i node_fail

   run_query ${query_ip} tree "${q1}" "${cur_dir}/q_all_online_q1.out" || return 1
   run_query ${query_ip} tree "${q2}" "${cur_dir}/q_all_online_q2.out" || return 1
   run_query ${query_ip} tree "${q3}" "${cur_dir}/q_all_online_q3.out" || return 1
   run_query ${query_ip} table "${q4}" "${cur_dir}/q_all_online_q4.out" || return 1
   for i in {1..4}
   do
      if ! grep -E 'root\.|d[0-9_]+\|' "${cur_dir}/q_all_online_q${i}.out" | grep -qE '\|[[:space:]]*[1-9][0-9]*[[:space:]]*\|?$';then
         echo "Fresh-data baseline q${i} is empty or has no positive count."
         cat "${cur_dir}/q_all_online_q${i}.out"
         return 1
      fi
   done

   exec 3<${nodeinfo_dir}/datanode.txt
   while read line <&3
   do
      grep -q "${line}," "${cur_dir}/ignore_dn_list.txt" && continue
      node_fail=0
      if [[ "${line}" = "${query_ip}" ]];then q_node=${query_ip2}; else q_node=${query_ip}; fi
      if ! ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/stop-datanode.sh";then
         echo "Failed to stop DataNode ${line}."
         node_fail=1
      fi
      if ! wait_dn_state ${q_node} ${line} "Unknown" 300;then
         echo "DataNode ${line} did not become Unknown within 300 seconds."
         node_fail=1
      fi
      v_ip=${line##*.}
      if [[ ${node_fail} = 0 ]];then
         run_query ${q_node} tree "${q1}" "${cur_dir}/q_stop_ip${v_ip}_q1.out" || node_fail=1
         run_query ${q_node} tree "${q2}" "${cur_dir}/q_stop_ip${v_ip}_q2.out" || node_fail=1
         run_query ${q_node} tree "${q3}" "${cur_dir}/q_stop_ip${v_ip}_q3.out" || node_fail=1
         run_query ${q_node} table "${q4}" "${cur_dir}/q_stop_ip${v_ip}_q4.out" || node_fail=1
         for i in {1..4}
         do
            if ! diff -q <(grep -E 'root\.|d[0-9_]+\|' "${cur_dir}/q_all_online_q${i}.out" | sed 's/ //g' | sort) <(grep -E 'root\.|d[0-9_]+\|' "${cur_dir}/q_stop_ip${v_ip}_q${i}.out" | sed 's/ //g' | sort) >/dev/null;then
               echo "Stopping ${line} changed q${i} query result."
               node_fail=1
            fi
         done
      fi

      if ! ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh > /dev/null 2>&1";then
         echo "Failed to restart DataNode ${line}."
         node_fail=1
      elif ! wait_dn_state ${q_node} ${line} "Running" 300;then
         echo "DataNode ${line} did not return to Running within 300 seconds."
         node_fail=1
      fi
      if [[ ${node_fail} -ne 0 ]];then
         let fail_flag++
         return 1
      fi
   done
   return 0
}
function remove_datanode()
{
        local rm_dn_ip=$1
        local exec_rm_ip=$2
        local v_rm_datanode_id
        local start_time
        local v_dn_num
        local active_num
        local stable_done=0
        local query_ok
        local ip_suffix=${rm_dn_ip##*.}

        run_query ${query_ip} tree "show datanodes;" "${cur_dir}/show_datanodes_before_remove.out" || {
           let fail_flag++
           return 1
        }
        v_rm_datanode_id=`grep "${rm_dn_ip}|" "${cur_dir}/show_datanodes_before_remove.out"|awk -F '|' '{gsub(" ","",$2);print $2}'|tail -1`
        if [[ -z "${v_rm_datanode_id}" ]];then
           echo "Cannot find DataNode id for ${rm_dn_ip}."
           let fail_flag++
           return 1
        fi
        if ! ssh ${u_name}@${rm_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh";then
           echo "Failed to stop remove target ${rm_dn_ip}."
           let fail_flag++
           return 1
        fi
        if ! wait_dn_state ${query_ip} ${rm_dn_ip} "Unknown" 300;then
           echo "Remove target ${rm_dn_ip} did not become Unknown within 300 seconds."
           let fail_flag++
           return 1
        fi

        run_query ${query_ip} tree "remove datanode ${v_rm_datanode_id};" "${cur_dir}/rm_cmd_res.out" || {
           let fail_flag++
           return 1
        }
        if ! grep -qi "successfully" "${cur_dir}/rm_cmd_res.out";then
           cat "${cur_dir}/rm_cmd_res.out"
           let fail_flag++
           return 1
        fi

        start_time=`date +%s`
        while true
        do
           query_ok=1
           run_query ${query_ip} tree "show datanodes;" "${cur_dir}/tc109_show_dn_${ip_suffix}.out" || query_ok=0
           v_dn_num=`grep "${rm_dn_ip}|" "${cur_dir}/tc109_show_dn_${ip_suffix}.out"|wc -l`
           run_query ${query_ip} tree "show regions;" "${cur_dir}/tc109_regions_tree_${ip_suffix}.out" || query_ok=0
           run_query ${query_ip} table "show regions;" "${cur_dir}/tc109_regions_table_${ip_suffix}.out" || query_ok=0
           active_num=`grep -E "Adding|Removing" "${cur_dir}/tc109_regions_tree_${ip_suffix}.out" "${cur_dir}/tc109_regions_table_${ip_suffix}.out"|wc -l`
           if [[ ${query_ok} = 1 && ${v_dn_num} = 0 && ${active_num} = 0 ]];then
              let stable_done++
           else
              stable_done=0
           fi
           if [[ ${stable_done} -ge 3 ]];then
              echo "${rm_dn_ip}," >> ${cur_dir}/ignore_dn_list.txt
              break
           fi
           if [[ $((`date +%s`-start_time)) -gt 3600 ]];then
              echo "Remove DataNode ${rm_dn_ip} did not settle within 3600 seconds."
              let fail_flag++
              return 1
           fi
           sleep 10
        done

if [[ ${fail_flag} = 0 ]];then
   if ! check_data_consistent;then
      [[ ${fail_flag} = 0 ]] && let fail_flag++
      return 1
   fi
fi
return 0
}


function exec_remove()
{

last_dn_ip=`tail -1 ${nodeinfo_dir}/datanode.txt`
last_dn_ip2=`tail -2 ${nodeinfo_dir}/datanode.txt|head -1`
if [[ ${fail_flag} = 0 ]];then
   remove_datanode ${last_dn_ip} ${last_dn_ip2}
fi
test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))
tc_res=true

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
  fi
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

}
clean_env || let fail_flag++
if [[ ${fail_flag} = 0 ]];then
   start_db || let fail_flag++
fi
if [[ ${fail_flag} = 0 ]];then
   prepare_fresh_data || let fail_flag++
fi
>${cur_dir}/ignore_dn_list.txt
exec_remove

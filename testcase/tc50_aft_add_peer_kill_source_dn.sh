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
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
query_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`
bm_ip=`head -1 ${nodeinfo_dir}/bm_node.txt`
bm_dir=/data1/benchmark/bm_20231129_d43030e
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
fail_file="fail.log"
cn_num=3
dn_num=5
dr_rep_num=2
sr_rep_num=3
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/3db_test_data
fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
tmp_out_file="tc${tc_num}_tmp.out"
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
# Region 迁移包含大快照，默认最多等待 1 小时；均可在 CI 中通过环境变量调整。
copy_wait_timeout_sec=${DATA_COPY_WAIT_TIMEOUT_SEC:-3600}
remove_wait_timeout_sec=${MIGRATION_REMOVE_WAIT_TIMEOUT_SEC:-3600}
migration_wait_timeout_sec=${MIGRATION_FINISH_WAIT_TIMEOUT_SEC:-3600}
node_wait_timeout_sec=${NODE_STATUS_WAIT_TIMEOUT_SEC:-300}
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
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
    set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=171966464" 
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
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
set_sys_conf ${line} ${db_dir} ".*region_migration_speed_limit_bytes_per_second=.*" "region_migration_speed_limit_bytes_per_second=0"
   set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=171966464"
  done
 
}

function start_db()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
   #start cluster
   head -n $cn_num ${nodeinfo_dir}/total_node.txt > ${nodeinfo_dir}/confignode.txt 
   set_conf
#copy data
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
ssh ${u_name}@${line} "sudo cp -rl ${backup_dir_on_cn_dn_host}/data ${db_dir}/ " &
done
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
        v_copy_beg_sec=`date +%s`
        while true
        do
        v_check_cp=`ssh ${u_name}@${line} "sudo ps -ef|grep \"cp -rl\"|grep -v grep|wc -l"`
        if [[ ${v_check_cp} = 0 ]];then
           ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
           break
        else
           v_copy_now_sec=`date +%s`
           if [[ $((v_copy_now_sec-v_copy_beg_sec)) -ge ${copy_wait_timeout_sec} ]];then
              echo "ERROR: timeout after ${copy_wait_timeout_sec}s waiting for data copy on ${line}" >&2
              let fail_flag++
              return 1
           fi
           sleep 5
        fi
        done
done
exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
v_check=`grep ${line} ${nodeinfo_dir}/datanode.txt |wc -l`
if [[ ${v_check} = 0 ]];then
ssh ${u_name}@${line} "sudo cp -rp ${backup_dir_on_cn_dn_host}/data ${db_dir}/ "
ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
fi
done

   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"

}

function capture_migration_diagnostics()
{
   local label=$1
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show data regions" > "${cur_dir}/show_data_regions_${label}.out" 2>&1 || true
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show migrations" > "${cur_dir}/show_migrations_${label}.out" 2>&1 || true
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show confignodes" > "${cur_dir}/show_confignodes_${label}.out" 2>&1 || true
}

function refresh_region_and_dn_info()
{
   local region_output

   region_output=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show data regions;" 2>&1`
   v_mig_id=`printf '%s\n' "${region_output}"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
   if [[ -z "${v_mig_id}" ]];then
      echo "ERROR: cannot find root.test DataRegion" >&2
      return 1
   fi
   printf '%s\n' "${region_output}"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8","$9}' > "${cur_dir}/mig_id_info.txt"
   printf '%s\n' "${region_output}"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8}' > "${cur_dir}/mig_region_dn_id.txt"
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e 'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}' > "${cur_dir}/all_dn_id.txt"
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e 'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}' > "${cur_dir}/all_dn_id_ip.txt"
   [[ -s "${cur_dir}/mig_id_info.txt" && -s "${cur_dir}/all_dn_id_ip.txt" ]]
}

function choose_migration_target()
{
   local dn_id

   v_mig_to_dn_id=""
   while read -r dn_id
   do
      [[ -z "${dn_id}" ]] && continue
      if ! grep -Fxq "${dn_id}" "${cur_dir}/mig_region_dn_id.txt";then
         v_mig_to_dn_id=${dn_id}
         break
      fi
   done < "${cur_dir}/all_dn_id.txt"
   [[ -n "${v_mig_to_dn_id}" ]]
}

function submit_migration()
{
   local submit_file=$1

   if [[ -z "${v_mig_id}" || -z "${v_mig_from_dn_id}" || -z "${v_mig_to_dn_id}" || "${v_mig_from_dn_id}" = "${v_mig_to_dn_id}" ]];then
      echo "ERROR: invalid migration arguments: region=${v_mig_id}, from=${v_mig_from_dn_id}, to=${v_mig_to_dn_id}" >&2
      return 1
   fi
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id};" > "${submit_file}" 2>&1
   if ! grep -qi "statement is executed successfully" "${submit_file}";then
      echo "ERROR: MIGRATE REGION submission failed; see ${submit_file}" >&2
      return 1
   fi
}

function wait_for_removing_phase()
{
   local wait_beg_sec
   local wait_now_sec
   local region_output
   local region_rows
   local source_count
   local target_count
   local removing_count

   wait_beg_sec=`date +%s`
   while true
   do
      region_output=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show data regions;" 2>&1`
      printf '%s\n' "${region_output}" > "${cur_dir}/show_data_regions_wait_removing.out"
      region_rows=`printf '%s\n' "${region_output}"|grep " ${v_mig_id}|[[:space:]]*DataRegion" || true`
      removing_count=`printf '%s\n' "${region_rows}"|grep -c Removing || true`
      source_count=`printf '%s\n' "${region_rows}"|grep -c "${v_mig_from_dn_ip}" || true`
      target_count=`printf '%s\n' "${region_rows}"|grep -c "${v_mig_to_dn_ip}" || true`
      if [[ ${removing_count} -gt 0 ]];then
         return 0
      fi
      # 迁移已经结束说明错过了故障注入窗口，不能再误杀源节点。
      if [[ ${source_count} -eq 0 && ${target_count} -gt 0 ]];then
         echo "ERROR: migration completed before the source DataNode fault was injected" >&2
         capture_migration_diagnostics "missed_removing"
         return 1
      fi
      wait_now_sec=`date +%s`
      if [[ $((wait_now_sec-wait_beg_sec)) -ge ${remove_wait_timeout_sec} ]];then
         echo "ERROR: timeout after ${remove_wait_timeout_sec}s waiting for Removing" >&2
         capture_migration_diagnostics "remove_timeout"
         return 1
      fi
      sleep 1
   done
}

function wait_for_datanode_stopped()
{
   local dn_ip=$1
   local wait_beg_sec
   local wait_now_sec
   local v_pid

   wait_beg_sec=`date +%s`
   while true
   do
      v_pid=`ssh ${u_name}@${dn_ip} "sudo jps|grep -i datanode|wc -l"`
      [[ ${v_pid} -eq 0 ]] && return 0
      wait_now_sec=`date +%s`
      if [[ $((wait_now_sec-wait_beg_sec)) -ge ${node_wait_timeout_sec} ]];then
         echo "ERROR: timeout after ${node_wait_timeout_sec}s waiting for DataNode ${dn_ip} to stop" >&2
         return 1
      fi
      sleep 3
   done
}

function wait_for_datanode_running()
{
   local dn_ip=$1
   local wait_beg_sec
   local wait_now_sec
   local running_count

   wait_beg_sec=`date +%s`
   while true
   do
      running_count=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show datanodes"|grep "${dn_ip}"|grep -ci Running || true`
      [[ ${running_count} -gt 0 ]] && return 0
      wait_now_sec=`date +%s`
      if [[ $((wait_now_sec-wait_beg_sec)) -ge ${node_wait_timeout_sec} ]];then
         echo "ERROR: timeout after ${node_wait_timeout_sec}s waiting for DataNode ${dn_ip} to become Running" >&2
         return 1
      fi
      sleep 2
   done
}

function wait_for_migration_finished()
{
   local label=$1
   local wait_beg_sec
   local wait_now_sec
   local region_output
   local region_rows
   local row_count
   local source_count
   local target_count
   local transitional_count

   wait_beg_sec=`date +%s`
   while true
   do
      region_output=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show data regions;" 2>&1`
      printf '%s\n' "${region_output}" > "${cur_dir}/show_data_regions_${label}_latest.out"
      region_rows=`printf '%s\n' "${region_output}"|grep " ${v_mig_id}|[[:space:]]*DataRegion" || true`
      row_count=`printf '%s\n' "${region_rows}"|grep -c DataRegion || true`
      source_count=`printf '%s\n' "${region_rows}"|grep -c "${v_mig_from_dn_ip}" || true`
      target_count=`printf '%s\n' "${region_rows}"|grep -c "${v_mig_to_dn_ip}" || true`
      transitional_count=`printf '%s\n' "${region_rows}"|grep -Ec 'Adding|Removing' || true`
      if [[ ${row_count} -eq ${dr_rep_num} && ${source_count} -eq 0 && ${target_count} -gt 0 && ${transitional_count} -eq 0 ]];then
         return 0
      fi
      wait_now_sec=`date +%s`
      if [[ $((wait_now_sec-wait_beg_sec)) -ge ${migration_wait_timeout_sec} ]];then
         echo "ERROR: timeout after ${migration_wait_timeout_sec}s waiting for migration ${v_mig_id} to finish" >&2
         capture_migration_diagnostics "${label}_timeout"
         return 1
      fi
      sleep 5
   done
}

function migrate_once()
{
   local source_line=$1
   local inject_source_failure=$2
   local label=$3
   local source_pid
   local next_query_ip
   local v_stop_time

   if [[ -z "${source_line}" ]];then
      echo "ERROR: empty source DataNode information" >&2
      return 1
   fi
   v_mig_from_dn_id=`printf '%s\n' "${source_line}"|awk -F ',' '{print $1}'`
   v_mig_from_dn_ip=`printf '%s\n' "${source_line}"|awk -F ',' '{print $2}'`
   choose_migration_target || { echo "ERROR: no migration target DataNode is available" >&2; return 1; }
   v_mig_to_dn_ip=`awk -F ',' -v id="${v_mig_to_dn_id}" '$1 == id {print $2; exit}' "${cur_dir}/all_dn_id_ip.txt"`
   [[ -n "${v_mig_to_dn_ip}" ]] || { echo "ERROR: cannot resolve target DataNode ${v_mig_to_dn_id}" >&2; return 1; }

   submit_migration "${cur_dir}/mig_${label}.out" || return 1

   if [[ "${inject_source_failure}" = "true" ]];then
      source_pid=`ssh ${u_name}@${v_mig_from_dn_ip} "sudo jps|awk 'tolower(\$0) ~ /datanode/ {print \$1; exit}'"`
      [[ -n "${source_pid}" ]] || { echo "ERROR: cannot find DataNode pid on ${v_mig_from_dn_ip}" >&2; return 1; }
      wait_for_removing_phase || return 1
      next_query_ip=`awk -F ',' -v source_ip="${v_mig_from_dn_ip}" '$2 != source_ip {print $2; exit}' "${cur_dir}/all_dn_id_ip.txt"`
      [[ -n "${next_query_ip}" ]] || { echo "ERROR: cannot select a query DataNode after fault injection" >&2; return 1; }
      ssh ${u_name}@${v_mig_from_dn_ip} "sudo kill -9 ${source_pid}" || return 1
      query_ip=${next_query_ip}
      wait_for_datanode_stopped "${v_mig_from_dn_ip}" || return 1
      v_stop_time=`date +%s`
      ssh ${u_name}@${v_mig_from_dn_ip} "sudo mkdir -p ${db_dir}/logs/logs_stop_dn_${v_stop_time} && sudo find ${db_dir}/logs -maxdepth 1 -type f -name '*datanode*' -exec mv -t ${db_dir}/logs/logs_stop_dn_${v_stop_time} {} +" || return 1
   fi

   wait_for_migration_finished "${label}" || return 1

   if [[ "${inject_source_failure}" = "true" ]];then
      ssh ${u_name}@${v_mig_from_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
      wait_for_datanode_running "${v_mig_from_dn_ip}" || return 1
   fi
   return 0
}

function pre_and_exec_mig_region()
{
   local line

   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;" > "${cur_dir}/q_exp.out"
   refresh_region_and_dn_info || return 1
   line=`head -1 "${cur_dir}/mig_id_info.txt"`
   migrate_once "${line}" true "fault_source" || return 1

   refresh_region_and_dn_info || return 1
   line=`tail -1 "${cur_dir}/mig_id_info.txt"`
   migrate_once "${line}" false "normal" || return 1

   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;" > "${cur_dir}/q_act.out"
   v_check_res=`diff "${cur_dir}/q_act.out" "${cur_dir}/q_exp.out"|grep root|wc -l`
   if [[ ${v_check_res} -ne 0 ]];then
      echo "ERROR: query result differs after migration" >&2
      return 1
   fi
   return 0
}

function backup_logs()
{
   local case_name=${SCRIPT_NAME%.sh}
   local backup_time

   backup_time=`date +"%Y_%m_%d_%H_%M_%S"`
   echo "Test failed; backing up ConfigNode/DataNode logs (${case_name}_${backup_time})"
   if ! sh -x "${clean_env_dir}/backup_cluster_logs.sh" "${case_name}" "${backup_time}";then
      echo "WARNING: backup cluster logs failed" >&2
      return 1
   fi
}

function rec_result()
{
   local test_end_sec
   local test_elp_sec
   local tc_res

   test_end_sec=`date +%s`
   test_elp_sec=$((test_end_sec-test_begin_sec))
   if [[ ${fail_flag} -eq 0 ]];then
      tc_res=true
      echo "${SCRIPT_NAME} : pass" >> "${res_file}"
   else
      tc_res=false
      backup_logs || true
      echo "${SCRIPT_NAME} : fail" >> "${res_file}"
   fi
   ${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"
}

clean_env
if start_db;then
   if ! pre_and_exec_mig_region;then
      let fail_flag++
   fi
else
   let fail_flag++
fi
rec_result

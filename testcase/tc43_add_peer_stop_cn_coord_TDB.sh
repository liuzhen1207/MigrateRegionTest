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
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-456 
fail_file="fail.log"
cn_num=3
dn_num=5
dr_rep_num=2
sr_rep_num=3
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/3db_test_data
tmp_out_file="tc${tc_num}_tmp.out"
fail_flag=0
v_warnMessage=""
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
loop_timeout_sec=7200
mig_submit_timeout_sec=7200
query_sql="select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;"
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
set_sys_conf ${line} ${db_dir} ".*region_migration_speed_limit_bytes_per_second=.*" "region_migration_speed_limit_bytes_per_second=33554432"
   set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=171966464"
  done

}

function refresh_region_runtime_info()
{
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8","$9}'>${cur_dir}/mig_id_info.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/all_dn_id_ip.txt
}

function select_target_dn()
{
  local v_target_dn_id=""
  while read line
  do
     if [[ -z "${line}" ]];then
        continue
     fi
     v_check=`grep -w "${line}" ${cur_dir}/mig_region_dn_id.txt|wc -l`
     if [[ ${v_check} = 0 ]];then
        v_target_dn_id=${line}
        break
     fi
  done < ${cur_dir}/all_dn_id.txt
  echo ${v_target_dn_id}
}

function run_migrate_region_with_retry()
{
  local v_region_id=$1
  local v_from_dn_id=$2
  local v_to_dn_id=$3
  local v_out_file=$4
  local v_start_sec=`date +%s`

  while true
  do
     ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_region_id} FROM ${v_from_dn_id} TO ${v_to_dn_id};" > ${v_out_file}
     if grep -q "has some other region operation procedures in progress" ${v_out_file};then
        v_now_sec=`date +%s`
        v_elp=$((v_now_sec-v_start_sec))
        if [[ ${v_elp} -gt ${mig_submit_timeout_sec} ]];then
           return 1
        fi
        sleep 2
     elif grep -q "IoTDBSQLException" ${v_out_file};then
        return 1
     else
        return 0
     fi
  done
}

function write_test_result()
{
  test_end_sec=`date +%s`
  test_elp_sec=$((test_end_sec-test_begin_sec))
  tc_res=true
  local warn_message_sql=""

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
     if [[ -n "${v_warnMessage}" ]];then
        echo "${SCRIPT_NAME} : ${v_warnMessage}" >> "${res_file}"
     fi
  fi
  if [[ -n "${v_warnMessage}" ]];then
     echo "warn_message=${v_warnMessage}"
     warn_message_sql=${v_warnMessage//;/,}
     warn_message_sql=${warn_message_sql//\'/\'\'}
  fi
  ${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time,warnMsg)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec},'${warn_message_sql}');"
}

function append_warn()
{
  local v_msg=$1
  if [[ -z "${v_warnMessage}" ]];then
     v_warnMessage="${v_msg}"
  else
     v_warnMessage="${v_warnMessage}; ${v_msg}"
  fi
}

function query_output_has_error()
{
  local src_file=$1
  grep -Eiq '(^Msg:|IoTDBSQLException|StatementExecutionException|executeStatement failed|^[[:space:]]*Exception|java\.lang\.)' "${src_file}"
}

function normalize_query_result()
{
  local src_file=$1
  local dst_file=$2

  awk '
    /^\+/ { next }
    /^It costs / { next }
    /\|/ {
      line = $0
      gsub(/\r/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line == "") {
        next
      }
      split(line, arr, "|")
      out = ""
      for (i = 2; i < length(arr); i++) {
        val = arr[i]
        gsub(/^[ \t]+|[ \t]+$/, "", val)
        out = out val "|"
      }
      if (out ~ /^(Device|Time|time)\|/) {
        next
      }
      if (out != "|") {
        print out
      }
    }
  ' "${src_file}" | sort > "${dst_file}"
}

function wait_migrate_region_finish()
{
   local v_start_time=`date +%s`
   local v_remove_region_log=0
   local v_mig_suc_log=0

   while true
   do
      v_remove_region_log=0
      v_mig_suc_log=0
      ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;" |grep -i Running|awk -F '|' '{gsub(" ","");print $4}'>${cur_dir}/all_cn_ip.txt
      ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show migrations;" > ${cur_dir}/show_migrations.out
      v_mig_show_empty=`grep "Empty set" ${cur_dir}/show_migrations.out|wc -l`

      exec 3<${cur_dir}/all_cn_ip.txt
      while read line <&3
      do
         if [[ -z "${line}" ]];then
            continue
         fi
         ssh ${u_name}@${line} "sudo gunzip -f ${db_dir}/logs/log-confignode-all*gz >/dev/null 2>&1 || true"
         v_remove_region_log_tmp=`ssh ${u_name}@${line} "grep \"\\[RemoveRegion\\] success, region ${v_mig_id} has been removed from DataNode ${v_mig_from_dn_id}\" ${db_dir}/logs/*confignode*all*|wc -l"`
         v_mig_suc_log_tmp=`ssh ${u_name}@${line} "grep \"\\[MigrateRegion\\] success\" ${db_dir}/logs/*confignode*all*|grep \" has been migrated from DataNode ${v_mig_from_dn_id}@${v_mig_from_dn_ip} to ${v_mig_to_dn_id}@${v_mig_to_dn_ip}\"|wc -l"`
         v_remove_region_log=$((v_remove_region_log + v_remove_region_log_tmp))
         v_mig_suc_log=$((v_mig_suc_log + v_mig_suc_log_tmp))
      done

      if [[ ${v_mig_show_empty} -gt 0 ]] && [[ ${v_remove_region_log} -gt 0 || ${v_mig_suc_log} -gt 0 ]];then
         break
      fi

      v_end_time=`date +%s`
      v_elp=$((v_end_time-v_start_time))
      if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
         return 1
      fi
      sleep 5
   done

   return 0
}

function choose_query_host()
{
  local stop_dn_ip=$1
  awk -v stop_ip="${stop_dn_ip}" '$0 != stop_ip {print; exit}' "${cur_dir}/running_datanodes.txt"
}

function wait_datanode_not_running()
{
  local query_host=$1
  local stop_dn_ip=$2
  local timeout_sec=$3
  local start_time=`date +%s`

  while true
  do
    v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_host} -e "show datanodes"|grep ${stop_dn_ip}|grep -i Running|wc -l`
    if [[ ${v_check_status} = 0 ]];then
      return 0
    fi
    v_end_time=`date +%s`
    v_elp=$((v_end_time-start_time))
    if [[ ${v_elp} -gt ${timeout_sec} ]];then
      return 1
    fi
    sleep 2
  done
}

function wait_datanode_running()
{
  local query_host=$1
  local stop_dn_ip=$2
  local timeout_sec=$3
  local start_time=`date +%s`

  while true
  do
    v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_host} -e "show datanodes"|grep ${stop_dn_ip}|grep -i Running|wc -l`
    if [[ ${v_check_status} -gt 0 ]];then
      return 0
    fi
    v_end_time=`date +%s`
    v_elp=$((v_end_time-start_time))
    if [[ ${v_elp} -gt ${timeout_sec} ]];then
      return 1
    fi
    sleep 2
  done
}

function check_replica_consistency_when_stop_each_dn()
{
  local stop_dn_ip
  local query_host
  local v_ip
  local start_time
  local check_file
  local check_norm_file
  local query_failed

  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes" > ${cur_dir}/show_datanodes_after_mig.out
  awk -F '|' '/Running/ {gsub(/ /, "", $4); print $4}' ${cur_dir}/show_datanodes_after_mig.out | sort -u > ${cur_dir}/running_datanodes.txt

  while read stop_dn_ip
  do
    if [[ -z "${stop_dn_ip}" ]];then
      continue
    fi
    query_host=`choose_query_host ${stop_dn_ip}`
    if [[ -z "${query_host}" ]];then
      append_warn "no query host left after stopping ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi

    ssh ${u_name}@${stop_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/stop-datanode.sh"
    if ! wait_datanode_not_running ${query_host} ${stop_dn_ip} 180;then
      append_warn "cluster state did not update after stopping ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi

    v_ip=`echo ${stop_dn_ip}|awk -F '.' '{print $4}'`
    check_file=${cur_dir}/q_stop_ip${v_ip}.out
    check_norm_file=${cur_dir}/q_stop_ip${v_ip}.norm
    query_failed=0
    ${cli_dir}/sbin/start-cli.sh -h ${query_host} -timeout 36000 -e "${query_sql}" > ${check_file}
    if query_output_has_error ${check_file};then
      append_warn "replica consistency query execute failed when ${stop_dn_ip} is down"
      let fail_flag++
      query_failed=1
    else
      normalize_query_result ${check_file} ${check_norm_file}
    fi
    if [[ ${query_failed} -eq 0 ]] && ! diff -u ${cur_dir}/q_exp.norm ${check_norm_file} > ${cur_dir}/tmp_diff_stop_ip${v_ip}.out 2>&1;then
      append_warn "replica consistency query result differs when ${stop_dn_ip} is down"
      let fail_flag++
    fi

    start_time=`date +%s`
    ssh ${u_name}@${stop_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_${start_time}_heapdump.hprof > /dev/null 2>&1 &"
    if ! wait_datanode_running ${query_host} ${stop_dn_ip} 300;then
      append_warn "failed to restart ${stop_dn_ip}"
      let fail_flag++
      return 1
    fi
  done < ${cur_dir}/running_datanodes.txt

  return 0
}

function check_log()
{
  local v_npe
  local v_cn_err1
  local v_cn_err2
  local v_err
  local v_err2
  local v_err3
  local v_err4
  local v_err5
  local v_err6
  local v_err7
  local v_err8
  local v_err9
  local v_err10
  local v_err11
  local v_err12
  local v_err13
  local v_err14
  local v_dn_total_err

  exec 3<${nodeinfo_dir}/confignode.txt
  while read line <&3
  do
    ssh ${u_name}@${line} "gunzip -f ${db_dir}/logs/*confignode*all*.gz 2>/dev/null || true"
    v_npe=$(ssh ${u_name}@${line} "grep NullPointer ${db_dir}/logs/*confignode*all* | wc -l")
    v_cn_err1=$(ssh ${u_name}@${line} "grep BufferUnderflowException ${db_dir}/logs/*confignode*all* | wc -l")
    v_cn_err2=$(ssh ${u_name}@${line} "grep \"but return HAS_MORE_STATE\" ${db_dir}/logs/*confignode*all* | wc -l")
    if [[ ${v_npe} -gt 0 ]]; then
      let fail_flag++
      append_warn "${line} CN NPE ${v_npe}."
    fi
    if [[ $((v_cn_err1 + v_cn_err2)) -gt 0 ]]; then
      let fail_flag++
      append_warn "CN HAS_MORE_STATE"
    fi
  done
  exec 3<&-

  exec 3<${nodeinfo_dir}/datanode.txt
  while read line <&3
  do
    ssh ${u_name}@${line} "gunzip -f ${db_dir}/logs/*datanode*all*.gz 2>/dev/null || true"
    v_npe=$(ssh ${u_name}@${line} "grep NullPointer ${db_dir}/logs/*datanode*all* | wc -l")
    v_err=$(ssh ${u_name}@${line} "grep CompactionTableSchemaNotMatchException ${db_dir}/logs/*datanode*all* | wc -l")
    v_err2=$(ssh ${u_name}@${line} "grep \"has overlapped data\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err3=$(ssh ${u_name}@${line} "grep \"which should be later than the last time\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err4=$(ssh ${u_name}@${line} "grep \"DataTypeInconsistentException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err5=$(ssh ${u_name}@${line} "grep \"ArrayIndexOutOfBoundsException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err6=$(ssh ${u_name}@${line} "grep \"Alter timeseries .* data type from null to\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err7=$(ssh ${u_name}@${line} "grep \"StatisticsClassException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err8=$(ssh ${u_name}@${line} "grep \"BufferUnderflowException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err9=$(ssh ${u_name}@${line} "grep \"NegativeArraySizeException\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err10=$(ssh ${u_name}@${line} "grep \"is not in tsFileMetaData\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err11=$(ssh ${u_name}@${line} "grep \"The memory cost to be released is larger\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err12=$(ssh ${u_name}@${line} "grep \"tsfile error\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err13=$(ssh ${u_name}@${line} "grep \"which has not released all memory\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_err14=$(ssh ${u_name}@${line} "grep \"Error while reading timeseries metadata\" ${db_dir}/logs/*datanode*all* | wc -l")
    v_dn_total_err=$((v_err + v_err2 + v_err3 + v_err4 + v_err5 + v_err6 + v_err7 + v_err8 + v_err9 + v_err10 + v_err11 + v_err12 + v_err13 + v_err14))
    if [[ ${v_npe} -gt 0 ]]; then
      let fail_flag++
      append_warn "${line} DN NPE ${v_npe}."
    fi
    if [[ ${v_dn_total_err} -gt 0 ]]; then
      let fail_flag++
      append_warn "DN unexp log"
    fi
  done
  exec 3<&-
}

function backup_logs()
{
  local case_name=${SCRIPT_NAME%.sh}
  local backup_time

  backup_time=$(date +"%Y_%m_%d_%H_%M_%S")
  if ! sh -x "${clean_env_dir}/backup_cluster_logs.sh" "${case_name}" "${backup_time}"; then
    append_warn "backup cluster logs failed"
    let fail_flag++
    return 1
  fi
  return 0
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
        while true
        do
        v_check_cp=`ssh ${u_name}@${line} "sudo ps -ef|grep \"cp -rl\"|grep -v grep|wc -l"`
        if [[ ${v_check_cp} = 0 ]];then
           ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
           break
        else
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

function pre_and_exec_mig_region()
{
 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "${query_sql}">${cur_dir}/q_exp.out
 normalize_query_result ${cur_dir}/q_exp.out ${cur_dir}/q_exp.norm

  v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  refresh_region_runtime_info

local v_mig_to_dn_id=-1
  line=`head -1 ${cur_dir}/mig_id_info.txt`
   if [[ ${line} = "" ]];then
      let fail_flag++
      write_test_result
      return 1
   fi

   v_mig_from_dn_id=`echo ${line}|awk -F ',' '{print $1}'`
   if [[ ${v_mig_to_dn_id} -lt 0 ]];then
         v_mig_to_dn_id=`select_target_dn`
   fi
   if [[ ${v_mig_to_dn_id} = "" ]];then
      let fail_flag++
      write_test_result
      return 1
   fi
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   v_bef_mig_time=`ssh ${u_name}@${v_cn_leader_ip} "date +\"%Y-%m-%d %H:%M:%S\""`
   v_bef_mig_sec=`date -d"${v_bef_mig_time}" +%s`
   if ! run_migrate_region_with_retry ${v_mig_id} ${v_mig_from_dn_id} ${v_mig_to_dn_id} ${cur_dir}/mig.out;then
      let fail_flag++
      write_test_result
      return 1
   fi
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
# check adding
   v_start_time=`date +%s`
   while true
   do
      ssh ${u_name}@${v_cn_leader_ip} "sudo gunzip -f ${db_dir}/logs/log-confignode-all*gz >/dev/null 2>&1 || true"
      v_AddRegion=`ssh ${u_name}@${v_cn_leader_ip} "grep \"AddRegion\] started\" ${db_dir}/logs/*confignode*all*|grep \"added to DataNode ${v_mig_to_dn_id}\"|wc -l"`
      if [[ ${v_AddRegion} -gt 0 ]];then
         v_adding_check=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show data regions"|grep Adding|wc -l`
         if [[ ${v_adding_check} = 0 ]];then
            let fail_flag++
         fi
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
            let fail_flag++
            write_test_result
            return 1
         fi
         sleep 1
      fi
   done
# get Add Coord ip
   v_submit_mig_log=`ssh ${u_name}@${v_cn_leader_ip} "grep \"Submit RegionMigrateProcedure successfully, Region: TConsensusGroupId(type:DataRegion, id:${v_mig_id}), Origin DataNode: TDataNodeLocation(dataNodeId:${v_mig_from_dn_id},\" ${db_dir}/logs/*confignode*all*"`
   v_add_coord_ip=`echo ${v_submit_mig_log} |awk -F "Add Coordinator:" '{print $2}'|awk -F "ip:" '{print $2}'|awk -F ',' '{print $1}'`
# get Remove Coord IP
   v_remove_coord_ip=`echo ${v_submit_mig_log} |awk -F "Remove Coordinator:" '{print $2}'|awk -F "ip:" '{print $2}'|awk -F ',' '{print $1}'`
# check snapshot
   v_start_time=`date +%s`
   while true
   do
      ssh ${u_name}@${v_add_coord_ip} "sudo gunzip -f ${db_dir}/logs/log-datanode-all*gz >/dev/null 2>&1 || true"
      v_AddRegion=`ssh ${u_name}@${v_add_coord_ip} "grep \"SNAPSHOT TRANSMISSION] The overall progress\" ${db_dir}/logs/*datanode*all*|wc -l"`
      if [[ ${v_AddRegion} -gt 1 ]];then
         ssh ${u_name}@${v_add_coord_ip} "sudo ${db_dir}/sbin/stop-datanode.sh" &
         ssh ${u_name}@${v_cn_leader_ip} "sudo ${db_dir}/sbin/stop-confignode.sh" &
		 if [[ ${query_ip} = ${v_add_coord_ip} ]];then
		    query_ip=${v_remove_coord_ip}
		 fi
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
            let fail_flag++
            write_test_result
            return 1
         fi
         sleep 1
      fi
   done
# check stop dn pid

v_start_time=`date +%s`
while true
do
   v_pid=`ssh ${u_name}@${v_add_coord_ip} "sudo jps|grep -i datanode|wc -l"`
   if [[ ${v_pid} -gt 0 ]];then
      v_end_time=`date +%s`
      v_elp=$((v_end_time-v_start_time))
      if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
         let fail_flag++
         write_test_result
         return 1
      fi
      sleep 3
   else
          v_stop_time=`date +%s`
	  ssh ${u_name}@${v_add_coord_ip} "sudo mkdir ${db_dir}/logs/logs_stop_add_coord_${v_stop_time}"
	  ssh ${u_name}@${v_add_coord_ip} "sudo mv ${db_dir}/logs/*datanode* ${db_dir}/logs/logs_stop_add_coord_${v_stop_time}"
          break
   fi
  
done

v_start_time=`date +%s`
while true
do
   v_pid=`ssh ${u_name}@${v_cn_leader_ip} "sudo jps|grep -i confignode|wc -l"`
   if [[ ${v_pid} -gt 0 ]];then
      v_end_time=`date +%s`
      v_elp=$((v_end_time-v_start_time))
      if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
         let fail_flag++
         write_test_result
         return 1
      fi
      sleep 3
   else
          break
   fi

done


#check new peer
v_beg_sec=`date +%s`
while true
do
   v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
   if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
      v_end_sec=`date +%s`
	  v_elp=$((v_end_sec-v_beg_sec))
	  if [[ ${v_elp} -gt ${loop_timeout_sec} ]];then
	     let fail_flag++
		 break
	  fi
      sleep 3
   else
      break      
   fi  
done
   v_adding_check=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "show data regions"|grep Adding|wc -l`
   if [[ ${v_adding_check} -gt 0 ]];then
        let fail_flag++
   fi
# restart stop coord
v_start_time=`date +%s`
ssh ${u_name}@${v_add_coord_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_restart_heapdump.hprof > /dev/null 2>&1 &"
while true
do
      v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes"|grep ${v_add_coord_ip}|grep -i Running|wc -l`
      if [[ ${v_check_status} -gt 0 ]];then
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt 180 ]];then
            let fail_flag++
            break
         fi
         sleep 2
      fi
done
v_start_time=`date +%s`
ssh ${u_name}@${v_cn_leader_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-confignode.sh > /dev/null 2>&1 &"
while true
do
      v_check_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes"|grep ${v_cn_leader_ip}|grep -i Running|wc -l`
      if [[ ${v_check_status} -gt 0 ]];then
         break
      else
         v_end_time=`date +%s`
         v_elp=$((v_end_time-v_start_time))
         if [[ ${v_elp} -gt 180 ]];then
            let fail_flag++
            break
         fi
         sleep 2
      fi
done

refresh_region_runtime_info
v_mig_to_dn_id=-1
  line=`tail -1 ${cur_dir}/mig_id_info.txt`
   if [[ ${line} = "" ]];then
      let fail_flag++
      write_test_result
      return 1
   fi

   v_mig_from_dn_id=`echo ${line}|awk -F ',' '{print $1}'`
   if [[ ${v_mig_to_dn_id} -lt 0 ]];then
         v_mig_to_dn_id=`select_target_dn`
   fi
   if [[ ${v_mig_to_dn_id} = "" ]];then
      let fail_flag++
      write_test_result
      return 1
   fi
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   v_bef_mig_time=`ssh ${u_name}@${v_cn_leader_ip} "date +\"%Y-%m-%d %H:%M:%S\""`
   v_bef_mig_sec=`date -d"${v_bef_mig_time}" +%s`
   if ! run_migrate_region_with_retry ${v_mig_id} ${v_mig_from_dn_id} ${v_mig_to_dn_id} ${cur_dir}/mig.out;then
      let fail_flag++
      write_test_result
      return 1
   fi
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
# check migration finish
 v_mig_to_dn_ip=`grep "${v_mig_to_dn_id}," ${cur_dir}/all_dn_id_ip.txt|awk -F ',' '{print $2}'`
 v_mig_from_dn_ip=`grep "${v_mig_from_dn_id}," ${cur_dir}/all_dn_id_ip.txt|awk -F ',' '{print $2}'`
   if ! wait_migrate_region_finish;then
      let fail_flag++
      write_test_result
      return 1
   fi

 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "${query_sql}">${cur_dir}/q_act.out
 normalize_query_result ${cur_dir}/q_act.out ${cur_dir}/q_act.norm
 if diff -u ${cur_dir}/q_act.norm ${cur_dir}/q_exp.norm > ${cur_dir}/tmp_diff_final.out 2>&1;then
    v_check_res=0
 else
    v_check_res=`grep -c '^[+-].*root\.' ${cur_dir}/tmp_diff_final.out`
    if [[ ${v_check_res} = 0 ]];then
       v_check_res=1
    fi
 fi
 if [[ ${v_check_res} != 0 ]];then
    append_warn "final query result diff count is ${v_check_res}"
    let fail_flag++
 fi

v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
   append_warn "final region ${v_mig_id} replica count is ${v_check_mig_regionid}, expected ${dr_rep_num}"
   let fail_flag++
fi

if [[ ${v_check_res} = 0 ]] && [[ ${v_check_mig_regionid} = ${dr_rep_num} ]];then
   check_replica_consistency_when_stop_each_dn
fi

sh -x "${clean_env_dir}/stop_cluster.sh"
check_log
backup_logs || true
write_test_result

 
} 
clean_env
start_db
pre_and_exec_mig_region

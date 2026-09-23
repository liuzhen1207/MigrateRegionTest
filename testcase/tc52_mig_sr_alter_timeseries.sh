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
bm_dir=/data1/benchmark/bm_20240320_76af1a40
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
fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
tmp_out_file="tc${tc_num}_tmp.out"
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
schema_migration_timeout_sec=${SCHEMA_MIGRATION_TIMEOUT_SEC:-900}
schema_migration_poll_interval_sec=${SCHEMA_MIGRATION_POLL_INTERVAL_SEC:-2}
schema_migration_stable_polls=${SCHEMA_MIGRATION_STABLE_POLLS:-3}
alter_pids=""
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
function alter_ts()
{
   local alter_failed=0
   for i in {0..100}
   do
      if ! ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "alter timeseries root.test.g_0.d1_${i}.s_0 UPSERT ALIAS=may TAGS(color=read, city=beijing) ATTRIBUTES(timezone=eight, air=good);";then
         echo "alter timeseries failed: root.test.g_0.d1_${i}.s_0" >> "${cur_dir}/${fail_file}"
         alter_failed=1
      fi
      if ! ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "alter timeseries root.test.g_0.d2_${i}.s_0 UPSERT ALIAS=may TAGS(color=read, city=beijing) ATTRIBUTES(timezone=eight, air=good);";then
         echo "alter timeseries failed: root.test.g_0.d2_${i}.s_0" >> "${cur_dir}/${fail_file}"
         alter_failed=1
      fi
   done
   return ${alter_failed}
}

function wait_schema_region_migration()
{
   local region_id=$1
   local from_dn_id=$2
   local to_dn_id=$3
   local timeout_sec=${4:-${schema_migration_timeout_sec}}
   local start_sec=`date +%s`
   local cur_sec
   local region_info
   local region_rows
   local region_dn_ids
   local from_cnt
   local to_cnt
   local region_cnt
   local non_running_cnt
   local migration_info=""
   local migration_query_valid
   local target_migration_cnt
   local stable_cnt=0
   local artifact_tag="schema_region_${region_id}_${from_dn_id}_to_${to_dn_id}"

   while true
   do
      region_info=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;" 2>&1`
      region_rows=`printf '%s\n' "${region_info}" | grep " ${region_id}|[[:space:]]*SchemaRegion" || true`
      region_dn_ids=`printf '%s\n' "${region_rows}" | awk -F '|' '{gsub(" ","",$8); if ($8 != "") print $8}'`
      from_cnt=`printf '%s\n' "${region_dn_ids}" | grep -x "${from_dn_id}" | wc -l`
      to_cnt=`printf '%s\n' "${region_dn_ids}" | grep -x "${to_dn_id}" | wc -l`
      region_cnt=`printf '%s\n' "${region_dn_ids}" | sed '/^$/d' | wc -l`
      # The CLI table starts with a leading '|': Status is field 4 and
      # DataNodeId is field 8 after splitting on '|'.
      non_running_cnt=`printf '%s\n' "${region_rows}" | awk -F '|' '{gsub(" ","",$4); if ($4 != "" && $4 != "Running") n++} END {print n+0}'`

      if [[ ${from_cnt} = 0 && ${to_cnt} -ge 1 && ${region_cnt} = ${sr_rep_num} && ${non_running_cnt} = 0 ]];then
         migration_info=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show migrations;" 2>&1`
         # Ignore unrelated DataRegion/SchemaRegion migrations in the
         # cluster; only the submitted migration must have disappeared.
         # With the leading '|', RegionId/Type/FromNodeId/ToNodeId are
         # fields 4/5/6/7 respectively. OperationType is field 3.
         migration_query_valid=`printf '%s\n' "${migration_info}" | grep -Ec '^\|[[:space:]]*ProcedureId[[:space:]]*\|[[:space:]]*OperationType[[:space:]]*\|[[:space:]]*RegionId[[:space:]]*\|'`
         target_migration_cnt=`printf '%s\n' "${migration_info}" | awk -F '|' -v rid="${region_id}" -v from="${from_dn_id}" -v to="${to_dn_id}" '
           function trim(v) { gsub(/[[:space:]]/, "", v); return v }
           { if (trim($4) == rid && trim($5) == "SchemaRegion" && trim($6) == from && trim($7) == to) n++ }
           END { print n+0 }'`
         if [[ ${migration_query_valid} -ge 1 && ${target_migration_cnt} = 0 ]];then
            stable_cnt=$((stable_cnt+1))
            if [[ ${stable_cnt} -ge ${schema_migration_stable_polls} ]];then
               echo "schema region ${region_id} migration ${from_dn_id} -> ${to_dn_id} finished and stable"
               return 0
            fi
         else
            stable_cnt=0
         fi
      else
         stable_cnt=0
      fi

      cur_sec=`date +%s`
      if ((cur_sec-start_sec >= timeout_sec));then
         migration_info=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show migrations;" 2>&1`
         printf '%s\n' "${region_info}" > "${cur_dir}/show_schema_regions_timeout_${artifact_tag}.out"
         printf '%s\n' "${migration_info}" > "${cur_dir}/show_migrations_timeout_${artifact_tag}.out"
         echo "wait schema region migration timeout after ${timeout_sec}s, region_id=${region_id}, from_dn_id=${from_dn_id}, to_dn_id=${to_dn_id}, region_dn_ids=${region_dn_ids}, non_running_cnt=${non_running_cnt}" >> "${cur_dir}/${fail_file}"
         return 1
      fi

      sleep ${schema_migration_poll_interval_sec}
   done
}

function backup_logs()
{
   local case_name=${SCRIPT_NAME%.sh}
   local backup_time

   backup_time=`date +"%Y_%m_%d_%H_%M_%S"`
   echo "Test completed; backing up cluster logs only (${case_name}_${backup_time})"
   if ! sh -x "${clean_env_dir}/backup_cluster_logs.sh" "${case_name}" "${backup_time}";then
      echo "WARNING: backup cluster logs failed" >&2
      return 1
   fi
   return 0
}

function pre_and_exec_mig_region()
{
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_exp.out

  v_ts_act=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.view_from_d*.*;"|grep "|  "|awk -F '|' '{gsub(" ","");print $2}'`
   if [[ ${v_ts_act} != 1000000 ]];then
      echo "initial view timeseries count is ${v_ts_act}, expected 1000000" >> "${cur_dir}/${fail_file}"
      let fail_flag++
   fi
  v_ts_act=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.d*.*;"|grep "|  "|awk -F '|' '{gsub(" ","");print $2}'`
   if [[ ${v_ts_act} != 1000000 ]];then
      echo "initial normal timeseries count is ${v_ts_act}, expected 1000000" >> "${cur_dir}/${fail_file}"
      let fail_flag++
   fi

  v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  if [[ -z "${v_mig_id}" ]];then
     echo "cannot find root.test SchemaRegion" >> "${cur_dir}/${fail_file}"
     let fail_flag++
     return 1
  fi
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;"|grep " ${v_mig_id}|[[:space:]]*SchemaRegion"|awk -F '|' '{gsub(" ","");print $8","$9}'>${cur_dir}/mig_id_info.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;"|grep " ${v_mig_id}|[[:space:]]*SchemaRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/all_dn_id_ip.txt

local v_mig_to_dn_id=-1
v_del_flag=0
exec 3<${cur_dir}/mig_id_info.txt
while read line<&3
do
   if [[ -z "${line}" ]];then
      echo "empty schema region replica entry" >> "${cur_dir}/${fail_file}"
      let fail_flag++
      break
   fi
   v_mig_from_dn_id=`echo ${line}|awk -F ',' '{print $1}'`
   if [[ ${v_mig_to_dn_id} -lt 0 ]];then
         for i in {1..4}
         do
             v_mig_to_dn_id=`awk "NR==${i}" ${cur_dir}/all_dn_id.txt`
             v_check=`grep ${v_mig_to_dn_id} ${cur_dir}/mig_region_dn_id.txt|wc -l`
             if [[ ${v_check} = 0 ]];then
                break
             fi
         done
   fi
   if [[ -z "${v_mig_to_dn_id}" || ${v_mig_to_dn_id} -lt 0 ]];then
      echo "cannot select target DataNode for schema region ${v_mig_id}" >> "${cur_dir}/${fail_file}"
      let fail_flag++
      break
   fi
   alter_ts &
   alter_pids="${alter_pids} $!"
   v_mig_out="${cur_dir}/mig_${v_mig_id}_${v_mig_from_dn_id}_to_${v_mig_to_dn_id}.out"
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id};" > "${v_mig_out}" 2>&1
   v_submit_rc=$?
   cp -fp "${v_mig_out}" "${cur_dir}/mig.out"
   v_submit_suc=`grep -ci "statement is executed successfully" "${v_mig_out}"`
   v_submit_err=`grep -Eci "failed|error|exception" "${v_mig_out}"`
   if [[ ${v_submit_rc} != 0 || ${v_submit_suc} = 0 || ${v_submit_err} -gt 0 ]];then
      echo "MIGRATE REGION submit failed, region_id=${v_mig_id}, from_dn_id=${v_mig_from_dn_id}, to_dn_id=${v_mig_to_dn_id}, output=${v_mig_out}" >> "${cur_dir}/${fail_file}"
      let fail_flag++
      break
   fi
   if ! wait_schema_region_migration ${v_mig_id} ${v_mig_from_dn_id} ${v_mig_to_dn_id} ${schema_migration_timeout_sec};then
      let fail_flag++
      break
   fi
   v_mig_to_dn_id=${v_mig_from_dn_id}

done
for alter_pid in ${alter_pids}
do
   if ! wait ${alter_pid};then
      echo "alter timeseries background job failed, pid=${alter_pid}" >> "${cur_dir}/${fail_file}"
      let fail_flag++
   fi
done
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_act.out

  v_ts_act=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.view_from_d*.*;"|grep "|  "|awk -F '|' '{gsub(" ","");print $2}'`
   if [[ ${v_ts_act} != 1000000 ]];then
      echo "final view timeseries count is ${v_ts_act}, expected 1000000" >> "${cur_dir}/${fail_file}"
      let fail_flag++
   fi
  v_ts_act=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.d*.*;"|grep "|  "|awk -F '|' '{gsub(" ","");print $2}'`
   if [[ ${v_ts_act} != 1000000 ]];then
      echo "final normal timeseries count is ${v_ts_act}, expected 1000000" >> "${cur_dir}/${fail_file}"
      let fail_flag++
   fi
v_ts_act=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_0) from root.test.g_0.d2* group by tags(city);"|grep beijing|grep 10100000|wc -l`
if [[ ${v_ts_act} != 1 ]];then
echo "d2 tag aggregation result check failed" >> "${cur_dir}/${fail_file}"
let fail_flag++
fi

v_ts_act=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_0) from root.test.g_0.d1* group by tags(city);"|grep beijing|grep 10100000|wc -l`
if [[ ${v_ts_act} != 1 ]];then
echo "d1 tag aggregation result check failed" >> "${cur_dir}/${fail_file}"
let fail_flag++
fi


v_final_region_info=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;" 2>&1`
v_final_region_rows=`printf '%s\n' "${v_final_region_info}" | grep " ${v_mig_id}|[[:space:]]*SchemaRegion" || true`
v_check_mig_regionid=`printf '%s\n' "${v_final_region_rows}" | sed '/^$/d' | wc -l`
v_final_non_running_cnt=`printf '%s\n' "${v_final_region_rows}" | awk -F '|' '{gsub(" ","",$4); if ($4 != "" && $4 != "Running") n++} END {print n+0}'`
if [[ ${v_check_mig_regionid} != ${sr_rep_num} || ${v_final_non_running_cnt} != 0 ]];then
   printf '%s\n' "${v_final_region_info}" > "${cur_dir}/show_schema_regions_final_invalid.out"
   echo "final SchemaRegion state invalid, region_id=${v_mig_id}, replica_count=${v_check_mig_regionid}, non_running_count=${v_final_non_running_cnt}" >> "${cur_dir}/${fail_file}"
   let fail_flag++
fi
 # CLI execution time varies between queries and is not part of the result.
 if ! diff -u --label q_exp.out --label q_act.out \
      <(sed '/^It costs /d' "${cur_dir}/q_exp.out") \
      <(sed '/^It costs /d' "${cur_dir}/q_act.out") \
      > "${cur_dir}/q_result.diff" 2>&1;then
    echo "query result differs before and after SchemaRegion migration, see q_result.diff" >> "${cur_dir}/${fail_file}"
    let fail_flag++
 fi

} 

function record_test_result()
{
test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))
tc_res=true

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
  else
     tc_res=false
     backup_logs || true
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
  fi
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"
}

: > "${cur_dir}/${fail_file}"
clean_env
start_db
pre_and_exec_mig_region
record_test_result

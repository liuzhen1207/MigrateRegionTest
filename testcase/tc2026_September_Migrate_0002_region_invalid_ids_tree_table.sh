#!/bin/bash
# 2026-09-23: Regression for REMOVE/EXTEND/RECONSTRUCT REGION with unknown IDs.
# Each operation must return a SQL error for both all-invalid and mixed
# valid/invalid Region lists in tree and table dialects. A mixed request must
# not submit its valid Region entry. Verify both models' data after syncLag is
# continuously zero, and scan CN/DN logs for NPE, 305, and array-bound errors.
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_sys_admin=root
db_sec_admin=security_admin
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
iotdb_host=`cat ${conf_file}|grep test_ip|awk -F '=' '{print $2}'`
v_cur_db=`cat ${conf_file}|grep v_cur_db|awk -F '=' '{print $2}'`
cli_dir=`cat ${conf_file}|grep client_db_dir|awk -F '=' '{print $2}'`
monitor_url=`cat ${conf_file}|grep '^monitor_url='|awk -F '=' '{print $2}'`
ssl_str=""
clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
check_res_dir="${cur_dir}/../check_res"
SCRIPT_NAME=$(basename "$0")
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
query_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
query_ip2=`tail -1 ${nodeinfo_dir}/datanode.txt`
bm_dir=`cat ${conf_file}|grep bm_v13_dir|awk -F '=' '{print $2}'`
cn_num=3
dn_num=5
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
fail_flag=0
rm_fail_flag=0
testcase_ip=`cat ${conf_file}|grep test_ip|awk -F '.' '{print $4}'`
tc_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'|awk -F "tc" '{print $2}'`
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
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
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=5"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
set_sys_conf ${line} ${db_dir} ".*data_region_consensus_protocol_class=.*" "data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.IoTConsensus"
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
set_sys_conf ${line} ${db_dir} ".*dn_metric_prometheus_reporter_port=.*" "dn_metric_prometheus_reporter_port=9091"
set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=5"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
set_sys_conf ${line} ${db_dir} ".*data_region_consensus_protocol_class=.*" "data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.IoTConsensus"
  
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
exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
v_check=`grep ${line} ${nodeinfo_dir}/datanode.txt |wc -l`
if [[ ${v_check} = 0 ]];then
ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
fi
done

   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"

}
function check_res()
{
   exp_res=$1
   exp_num=$2
   tc_desc=$3
   v_act_num=`cat ${cur_dir}/tmp.out|grep "${exp_res}"|wc -l`
   if [[ ${v_act_num} = ${exp_num} ]];then
      echo "${tc_desc} PASS."
      let succ_flag++
   else
      echo "${tc_desc} FAIL."
      let fail_flag++
      cat ${cur_dir}/tmp.out
   fi
}
function check_res2()
{
   exp_res1=$1
   exp_res2=$2
   exp_num=$3
   tc_desc=$4
   v_act_num1=`cat ${cur_dir}/tmp.out|grep "${exp_res1}"|wc -l`
   v_act_num2=`cat ${cur_dir}/tmp.out|grep "${exp_res2}"|wc -l`
   if [[ ${v_act_num1} -ge ${exp_num} ]] || [[ ${v_act_num2} -ge ${exp_num} ]];then
      echo "${tc_desc} PASS."
      let succ_flag++
   else
      echo "${tc_desc} FAIL."
      let fail_flag++
      cat ${cur_dir}/tmp.out
   fi
}

function run_cli_model_sql()
{
   local model=$1
   local sql=$2
   local output_file=$3
   if [[ "${model}" == "table" ]]; then
      "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -u "${db_sys_admin}" ${ssl_str} -sql_dialect table -timeout 3600 -e "${sql}" >"${output_file}" 2>&1
   else
      "${cli_dir}/sbin/start-cli.sh" -h "${query_ip}" -u "${db_sys_admin}" ${ssl_str} -timeout 3600 -e "${sql}" >"${output_file}" 2>&1
   fi
}

function wait_region_procedures_finish()
{
   local model=$1
   local max_wait_seconds=${2:-3600}
   local started_at
   local now
   local output_file="${cur_dir}/tc2026_${model}_show_migrations.out"
   local active_operations

   started_at=$(date +%s)
   while true
   do
      run_cli_model_sql "${model}" "show migrations;" "${output_file}"
      if grep -Eiq '^Msg:' "${output_file}"; then
         echo "${SCRIPT_NAME}: SHOW MIGRATIONS failed while waiting for ${model}-model region operations."
         cat "${output_file}"
         return 1
      fi
      active_operations=$(grep -E '[|][[:space:]]*(MIGRATE|EXTEND|REMOVE|RECONSTRUCT)[[:space:]]*[|]' "${output_file}" || true)
      if [[ -z "${active_operations}" ]]; then
         echo "${SCRIPT_NAME}: no active region procedures remain for ${model} model."
         return 0
      fi
      now=$(date +%s)
      if (( now - started_at >= max_wait_seconds )); then
         echo "${SCRIPT_NAME}: timed out waiting for ${model}-model region procedures."
         cat "${output_file}"
         return 1
      fi
      sleep 5
   done
}

function check_region_sql_rejected()
{
   local model=$1
   local operation=$2
   local scenario=$3
   local sql=$4
   local invalid_ids=$5
   local output_file="${cur_dir}/tc2026_${model}_${operation}_${scenario}.out"
   local cli_rc
   local failed=0

   if ! wait_region_procedures_finish "${model}" 3600; then
      echo "${model} ${operation} ${scenario}: region procedures were still running before the SQL request."
      let fail_flag++
      return 1
   fi
   echo "${model} ${operation} ${scenario}: ${sql}"
   run_cli_model_sql "${model}" "${sql}" "${output_file}"
   cli_rc=$?
   echo "${model} ${operation} ${scenario} output saved to ${output_file} (rc=${cli_rc})"
   cat "${output_file}"

   if grep -Eiq 'The statement is executed successfully' "${output_file}"; then
      echo "${model} ${operation} ${scenario}: invalid Region list was accepted."
      failed=1
   fi
   if ! grep -Eiq '(^|[[:space:]])Msg:' "${output_file}"; then
      echo "${model} ${operation} ${scenario}: CLI output did not contain a server SQL error."
      failed=1
   fi
   if ! grep -Eiq "${invalid_ids}|get region group id fail|region[^[:cntrl:]]*(not exist|not found|invalid)" "${output_file}"; then
      echo "${model} ${operation} ${scenario}: error output did not identify the invalid Region ID."
      failed=1
   fi
   if grep -Eiq 'Fail to connect|Connection refused|Authentication failed|No available config node' "${output_file}"; then
      echo "${model} ${operation} ${scenario}: request failed because of a connection or authentication problem."
      failed=1
   fi
   if [[ "${scenario}" == "mixed_valid_invalid" ]] && grep -Eiq 'successfully submitted:[[:space:]]*[1-9][0-9]*|Successfully submitted' "${output_file}"; then
      echo "${model} ${operation} ${scenario}: valid Region work was submitted despite the invalid ID."
      failed=1
   fi

   if ! wait_region_procedures_finish "${model}" 3600; then
      echo "${model} ${operation} ${scenario}: region procedure did not finish within 3600 seconds."
      failed=1
   fi

   if [[ ${failed} -eq 0 ]]; then
      echo "${model} ${operation} ${scenario}: rejected as expected."
      let succ_flag++
   else
      let fail_flag++
   fi
}

function seed_and_verify_region_ops_data()
{
   local seed_time=$(date +%s%3N)
   local tree_insert="insert into root.test.g_0(time,s_0) values(${seed_time},true);"
   local table_database="region_ops_invalid_20260923"
   local table_name="region_invalid_seed"
   local table_create="CREATE TABLE ${table_database}.${table_name} (device_id STRING TAG, s_0 BOOLEAN FIELD);"
   local table_insert="insert into ${table_database}.${table_name}(time,device_id,s_0) values(${seed_time},'region_invalid_seed',true);"
   local output_file

   run_cli_model_sql tree "${tree_insert}" "${cur_dir}/tc2026_seed_tree_insert.out"
   if ! grep -Eiq 'The statement is executed successfully' "${cur_dir}/tc2026_seed_tree_insert.out"; then
      echo "Tree-model seed insert failed:"
      cat "${cur_dir}/tc2026_seed_tree_insert.out"
      let fail_flag++
   else
      let succ_flag++
   fi
   output_file="${cur_dir}/tc2026_create_table_database.out"
   run_cli_model_sql table "CREATE DATABASE ${table_database};" "${output_file}"
   if ! grep -Eiq 'The statement is executed successfully' "${output_file}"; then
      echo "Table-model database creation failed:"
      cat "${output_file}"
      let fail_flag++
   else
      let succ_flag++
   fi
   output_file="${cur_dir}/tc2026_create_table.out"
   run_cli_model_sql table "${table_create}" "${output_file}"
   if ! grep -Eiq 'The statement is executed successfully' "${output_file}"; then
      echo "Table-model table creation failed:"
      cat "${output_file}"
      let fail_flag++
   else
      let succ_flag++
   fi
   run_cli_model_sql table "${table_insert}" "${cur_dir}/tc2026_seed_table_insert.out"
   if ! grep -Eiq 'The statement is executed successfully' "${cur_dir}/tc2026_seed_table_insert.out"; then
      echo "Table-model seed insert failed:"
      cat "${cur_dir}/tc2026_seed_table_insert.out"
      let fail_flag++
   else
      let succ_flag++
   fi

   run_cli_model_sql tree "select s_0 from root.test.g_0 where time = ${seed_time} align by device;" "${cur_dir}/tc2026_verify_tree_seed.out"
   if grep -Eiq '^Msg:' "${cur_dir}/tc2026_verify_tree_seed.out" || ! grep -Eiq '[|][[:space:]]*true[[:space:]]*[|]' "${cur_dir}/tc2026_verify_tree_seed.out"; then
      echo "Tree-model seed data query failed or returned no points:"
      cat "${cur_dir}/tc2026_verify_tree_seed.out"
      let fail_flag++
   else
      let succ_flag++
   fi
   run_cli_model_sql table "select count(s_0) from ${table_database}.${table_name} where device_id = 'region_invalid_seed';" "${cur_dir}/tc2026_verify_table_seed.out"
   if grep -Eiq '^Msg:' "${cur_dir}/tc2026_verify_table_seed.out" || ! grep -Eq '[|][[:space:]]*[1-9][0-9]*[[:space:]]*[|]' "${cur_dir}/tc2026_verify_table_seed.out"; then
      echo "Table-model seed data query failed or returned no points:"
      cat "${cur_dir}/tc2026_verify_table_seed.out"
      let fail_flag++
   else
      let succ_flag++
   fi
}

function test_invalid_region_operation_lists()
{
   local region_file="${cur_dir}/tc2026_regions_before_invalid_ops.out"
   local datanode_file="${cur_dir}/tc2026_datanodes_before_invalid_ops.out"
   local invalid_ids="199991,199992"
   local ip
   local dn_id
   local model database valid_region_id region_owner_dn extend_target_dn mixed_ids
   local operation all_sql mixed_sql target

   run_cli_model_sql tree "show datanodes;" "${datanode_file}"
   if ! grep -Eiq 'Total line number|DataNodeId' "${datanode_file}"; then
      echo "Could not read DataNode metadata for invalid-operation tests."
      cat "${datanode_file}"
      let fail_flag++
      return 1
   fi

   for model in tree table
   do
      if [[ "${model}" == "tree" ]]; then
         database="root.test.g_0"
      else
         database="region_ops_invalid_20260923"
      fi
      for operation in REMOVE EXTEND RECONSTRUCT
      do
         if ! wait_region_procedures_finish "${model}" 3600; then
            echo "${model} ${operation}: preceding region procedures did not finish."
            let fail_flag++
            continue
         fi
         run_cli_model_sql "${model}" "show regions;" "${region_file}"
         if ! grep -Eiq 'Total line number|RegionId' "${region_file}"; then
            echo "Could not read ${model}-model Region metadata."
            cat "${region_file}"
            let fail_flag++
            continue
         fi
         valid_region_id=$(awk -F '|' -v database="${database}" '/DataRegion/ && /Running/ {gsub(/[[:space:]]/, "", $2); gsub(/[[:space:]]/, "", $5); if ($2 ~ /^[0-9]+$/ && $5 == database) {print $2; exit}}' "${region_file}")
         if [[ -z "${valid_region_id}" ]]; then
            echo "Could not find a Running DataRegion for ${model}-model database ${database}."
            cat "${region_file}"
            let fail_flag++
            continue
         fi
         region_owner_dn=$(awk -F '|' -v region="${valid_region_id}" '/DataRegion/ && /Running/ {gsub(/[[:space:]]/, "", $2); gsub(/[[:space:]]/, "", $8); if ($2 == region && $8 ~ /^[0-9]+$/) {print $8; exit}}' "${region_file}")
         if [[ -z "${region_owner_dn}" ]]; then
            echo "Could not find a DataNode hosting ${model}-model DataRegion ${valid_region_id}."
            let fail_flag++
            continue
         fi
         extend_target_dn=""
         while IFS='|' read -r dn_id ip
         do
            [[ -z "${dn_id}" || -z "${ip}" || "${dn_id}" == "${region_owner_dn}" ]] && continue
            if ! awk -F '|' -v region="${valid_region_id}" -v target="${dn_id}" '/DataRegion/ && /Running/ {gsub(/[[:space:]]/, "", $2); gsub(/[[:space:]]/, "", $8); if ($2 == region && $8 == target) found=1} END {exit found ? 0 : 1}' "${region_file}"; then
               extend_target_dn=${dn_id}
               break
            fi
         done < <(awk -F '|' '/Running/ {gsub(/[[:space:]]/, "", $2); gsub(/[[:space:]]/, "", $4); if ($2 ~ /^[0-9]+$/ && $4 ~ /^[0-9.]+$/) print $2 "|" $4}' "${datanode_file}")
         if [[ -z "${extend_target_dn}" ]]; then
            echo "Could not find a Running DataNode that does not host ${model}-model DataRegion ${valid_region_id}."
            let fail_flag++
            continue
         fi
         mixed_ids="${valid_region_id},199991"
         case "${operation}" in
            REMOVE)
               target=${region_owner_dn}
               all_sql="REMOVE REGION ${invalid_ids} FROM ${target};"
               mixed_sql="REMOVE REGION ${mixed_ids} FROM ${target};"
               ;;
            EXTEND)
               target=${extend_target_dn}
               all_sql="EXTEND REGION ${invalid_ids} TO ${target};"
               mixed_sql="EXTEND REGION ${mixed_ids} TO ${target};"
               ;;
            RECONSTRUCT)
               target=${region_owner_dn}
               all_sql="RECONSTRUCT REGION ${invalid_ids} ON ${target};"
               mixed_sql="RECONSTRUCT REGION ${mixed_ids} ON ${target};"
               ;;
         esac
         check_region_sql_rejected "${model}" "${operation}" all_invalid "${all_sql}" "199991|199992"
         check_region_sql_rejected "${model}" "${operation}" mixed_valid_invalid "${mixed_sql}" "199991"
      done
   done
}

function backup_logs()
{
   local case_name=${SCRIPT_NAME%.sh}
   local backup_time

   backup_time=$(date +"%Y_%m_%d_%H_%M_%S")
   if ! sh -x "${clean_env_dir}/backup_cluster_logs.sh" "${case_name}" "${backup_time}"; then
      echo "${SCRIPT_NAME}: failed to back up cluster logs."
      let fail_flag++
   fi
}

function check_npe()
{
   tc_desc=$1
exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
   v_npe_num=`ssh ${u_name}@${line} "grep NullPointer ${db_dir}/logs/*confignode*all*|wc -l"`
   if [[ ${v_npe_num} -gt 0 ]];then
      let fail_flag++
      echo "${SCRIPT_NAME} CN NullPointer : ${v_npe_num}"
      # backup logs
      t=`date +%Y_%m_%d_%H_%M_%S`
      ssh ${u_name}@${line} "cp -rp ${db_dir}/logs ${db_dir}/logs_npe_${t}_${tc_desc}"
   fi
done
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
   v_npe_num=`ssh ${u_name}@${line} "grep NullPointer ${db_dir}/logs/*datanode*all*|wc -l"`
   if [[ ${v_npe_num} -gt 0 ]];then
      let fail_flag++
      echo "${SCRIPT_NAME} DN NullPointer : ${v_npe_num}"
      # backup logs
      t=`date +%Y_%m_%d_%H_%M_%S`
      ssh ${u_name}@${line} "cp -rp ${db_dir}/logs ${db_dir}/logs_npe_${t}_${tc_desc}"
   fi
done

}

function check_region_operation_error_logs()
{
   local evidence_file="${cur_dir}/tc2026_region_operation_error_logs.out"
   local nodes_file="${cur_dir}/tc2026_region_operation_log_nodes.out"
   local node
   local matches
   local error_pattern='NullPointerException|(^|[[:space:]])305:[[:space:]]|error code[=:[:space:]]+305|status code[=:[:space:]]+305|ArrayIndexOutOfBoundsException|IndexOutOfBoundsException|array index out of bounds|index out of bounds'

   cat "${nodeinfo_dir}/confignode.txt" "${nodeinfo_dir}/datanode.txt" | awk 'NF' | sort -u > "${nodes_file}"
   : > "${evidence_file}"
   while read -r node
   do
      [[ -z "${node}" ]] && continue
      matches=$(ssh "${u_name}@${node}" "(find '${db_dir}/logs' -maxdepth 1 -type f -name '*all*' ! -name '*.gz' -exec grep -HnE '${error_pattern}' {} +; find '${db_dir}/logs' -maxdepth 1 -type f -name '*all*.gz' -exec zgrep -HnE '${error_pattern}' {} +) 2>/dev/null || true")
      if [[ -n "${matches}" ]]; then
         {
            echo "### ${node}"
            echo "${matches}"
         } >> "${evidence_file}"
         echo "Found forbidden NullPointer/305/array-bounds diagnostics on ${node}."
         let fail_flag++
      fi
   done < "${nodes_file}"
   if [[ ! -s "${evidence_file}" ]]; then
      echo "No NullPointerException, error code 305, or array-bounds diagnostics found in CN/DN logs."
      let succ_flag++
   else
      echo "Forbidden CN/DN log matches saved to ${evidence_file}"
   fi
}
function wait_bm_finish()
{
local max_wait_time=$1
local bm_res1=$2
local bm_res2=$3
local t1=`date +%s`
   while true
   do
      v_bm=`jps|grep App|wc -l`
      v_bm1_finish=`cat ${bm_res1}|grep throughput|wc -l`
      v_bm2_finish=`cat ${bm_res2}|grep throughput|wc -l`
      if [[ ${v_bm} -gt 0 ]];then
         sleep 60
      else
         break
      fi
      if [[ ${v_bm1_finish} = 1 ]] && [[ ${v_bm2_finish} = 1 ]];then
         echo "benchmark finish."
         jps|grep App|awk '{print "kill -9 "$1}'|sh 
      fi
      t2=`date +%s`
      t_elp=$((t2-t1))
      if [[ ${t_elp} -gt ${max_wait_time} ]];then
         let fail_flag++
         echo "Benchmark running too long."
         break
      fi
      
   done
       ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "flush;">${cur_dir}/tmp.out
#       check_res "success" 1 "${SCRIPT_NAME}"
}
function wait_Adding_finish()
{
local v_query_ip=$1
local max_wait_time=$2
local t1=`date +%s`
  while true
   do
       ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${v_query_ip} -e "show regions;">${cur_dir}/tmp.out
       v_rm_succ=`cat ${cur_dir}/tmp.out |grep "Adding"|wc -l`
       if [[ ${v_rm_succ} -gt 0 ]];then
          sleep 5 
       else
          break
       fi
      t2=`date +%s`
      t_elp=$((t2-t1))
      if [[ ${t_elp} -gt ${max_wait_time} ]];then
         let fail_flag++
         let rm_fail_flag++
         echo "Adding takes too long."
         break
      fi

   done

}
function check_dn_jps()
{
   local v_dn_ip=$1
   local max_wait_time=$2
local t1=`date +%s`
while true
do
   v_dn_str=`ssh ${u_name}@${line} "sudo jps|grep DataNode"`
   v_dn_pid=`echo ${v_dn_str}|awk '{print $1}'`
   if [[ ${v_dn_pid} -gt 0 ]];then
      sleep 1
   else
      break
   fi
      t2=`date +%s`
      t_elp=$((t2-t1))
      if [[ ${t_elp} -gt ${max_wait_time} ]];then
         let fail_flag++
         echo "Stopping takes too long."
# kill -9 
         ssh ${u_name}@${line} "sudo kill -9 ${v_dn_pid}."
         break
      fi

done
}
function parse_monitor_query_status()
{
   local response_file=$1
   if command -v jq >/dev/null 2>&1; then
      jq -r '.status' "${response_file}" 2>/dev/null
      return $?
   fi
   grep -q '"status"[[:space:]]*:[[:space:]]*"success"' "${response_file}"
}
function count_non_zero_sync_lag()
{
   local response_file=$1
   if command -v jq >/dev/null 2>&1; then
      jq -r '.data.result[] | .value[1]' "${response_file}" 2>/dev/null | awk '$1 > 0.0001 {c++} END {print c+0}'
      return $?
   fi
   awk '
      {
         line = $0
         while (match(line, /"value"[[:space:]]*:[[:space:]]*\[[^]]*\]/)) {
            item = substr(line, RSTART, RLENGTH)
            split(item, parts, ",")
            if (length(parts) >= 2) {
               value = parts[2]
               gsub(/[^0-9eE+.-]/, "", value)
               if (value + 0 > 0.0001) count++
            }
            line = substr(line, RSTART + RLENGTH)
         }
      }
      END { print count + 0 }
   ' "${response_file}"
}
function count_sync_lag_series()
{
   local response_file=$1
   if command -v jq >/dev/null 2>&1; then
      jq -r '.data.result | length' "${response_file}" 2>/dev/null
      return $?
   fi
   grep -o '"instance"[[:space:]]*:' "${response_file}" | wc -l
}
function list_non_zero_sync_lag_nodes()
{
   local response_file=$1
   if command -v jq >/dev/null 2>&1; then
      jq -r '.data.result[] | select((.value[1] | tonumber) > 0.0001) | .metric.instance' "${response_file}" 2>/dev/null \
         | sed -E 's/:[0-9]+$//' | sort -u
      return ${PIPESTATUS[0]}
   fi
   awk '
      {
         line = $0
         while (match(line, /"metric"[[:space:]]*:[[:space:]]*\{[^}]*\}[[:space:]]*,[[:space:]]*"value"[[:space:]]*:[[:space:]]*\[[^]]*\]/)) {
            item = substr(line, RSTART, RLENGTH)
            instance = item
            if (match(instance, /"instance"[[:space:]]*:[[:space:]]*"[^"]+"/)) {
               instance = substr(instance, RSTART, RLENGTH)
               sub(/^.*:[[:space:]]*"/, "", instance)
               sub(/".*/, "", instance)
            } else {
               instance = ""
            }
            value = item
            if (match(value, /"value"[[:space:]]*:[[:space:]]*\[[^]]*\]/)) {
               value = substr(value, RSTART, RLENGTH)
               sub(/^.*,[[:space:]]*"?/, "", value)
               sub(/"?\].*/, "", value)
            } else {
               value = ""
            }
            if (instance != "" && value + 0 > 0.0001) {
               sub(/:[0-9]+$/, "", instance)
               print instance
            }
            line = substr(line, RSTART + RLENGTH)
         }
      }
   ' "${response_file}" | sort -u
}
function collect_non_zero_sync_lag_jstacks()
{
   local response_file=$1
   local timestamp
   local output_dir
   local node_ip
   local pid
   local round

   timestamp=$(date "+%Y_%m_%d_%H_%M_%S")
   output_dir="${cur_dir}/sync_lag_jstack_tc${tc_num}_${timestamp}"
   mkdir -p "${output_dir}"
   cp -f "${response_file}" "${output_dir}/sync_lag_response.json" 2>/dev/null || true
   list_non_zero_sync_lag_nodes "${response_file}" > "${output_dir}/non_zero_nodes.txt"
   if [[ ! -s "${output_dir}/non_zero_nodes.txt" ]]; then
      echo "${SCRIPT_NAME}: no non-zero syncLag nodes found in the saved response; jstack was not run."
      echo "syncLag timeout response saved in ${output_dir}"
      return 0
   fi

   echo "${SCRIPT_NAME}: collecting 3 jstacks, 10 seconds apart, from nodes with non-zero syncLag:"
   cat "${output_dir}/non_zero_nodes.txt"
   for round in 1 2 3
   do
      while read -r node_ip
      do
         [[ -z "${node_ip}" ]] && continue
         pid=$(timeout 30 ssh "${u_name}@${node_ip}" "source /etc/profile; sudo jps -l | sed -n '/DataNode/{s/[[:space:]].*//;p;q;}'" 2>/dev/null | awk '/^[0-9]+$/ {print; exit}')
         if [[ -z "${pid}" ]]; then
            echo "Unable to find DataNode PID on ${node_ip} for jstack ${round}." > "${output_dir}/${node_ip}_jstack_${round}.out"
            continue
         fi
         {
            echo "node=${node_ip} pid=${pid} sample=${round} captured_at=$(date '+%Y-%m-%d %H:%M:%S')"
            timeout 120 ssh "${u_name}@${node_ip}" "source /etc/profile; sudo jstack -l ${pid}"
         } > "${output_dir}/${node_ip}_jstack_${round}.out" 2>&1
      done < "${output_dir}/non_zero_nodes.txt"
      if [[ ${round} -lt 3 ]]; then
         sleep 10
      fi
   done
   echo "syncLag timeout jstack saved in ${output_dir}"
}
function wait_for_sync_lag_zero()
{
   local max_wait_seconds=${1:-3600}
   local target_duration=${2:-60}
   local sleep_interval=15
   local prometheus_user=admin
   local prometheus_pass=admin
   local metric_name="iot_consensus"
   local server_name="ioTConsensusServerImpl"
   local wait_start_time
   local zero_start_time=0
   local expected_count=0
   local instance_regex=""
   local ip
   local response_file="${cur_dir}/tc2026_region_ops_sync_lag_response.json"
   local last_nonzero_response="${cur_dir}/tc2026_region_ops_sync_lag_last_nonzero_response.json"
   local response_status
   local result_count
   local non_zero_num
   local now
   local query

   : > "${last_nonzero_response}"
   if [[ -z "${monitor_url}" ]]; then
      echo "${SCRIPT_NAME}: monitor_url is not configured; cannot verify syncLag."
      let fail_flag++
      return 1
   fi
   "${cli_dir}/sbin/start-cli.sh" -u "${db_sys_admin}" ${ssl_str} -h "${query_ip}" -timeout 3600 -e "show datanodes;" > "${cur_dir}/tc2026_region_ops_sync_running_datanodes.out" 2>&1
   awk -F '|' '/Running/ {gsub(/ /, "", $4); print $4}' "${cur_dir}/tc2026_region_ops_sync_running_datanodes.out" | sort -u > "${cur_dir}/tc2026_region_ops_sync_running_datanodes_ips.out"
   while read -r ip
   do
      [[ -z "${ip}" ]] && continue
      expected_count=$((expected_count + 1))
      [[ -n "${instance_regex}" ]] && instance_regex="${instance_regex}|"
      instance_regex="${instance_regex}${ip//./[.]}(:[0-9]+)?"
   done < "${cur_dir}/tc2026_region_ops_sync_running_datanodes_ips.out"
   if [[ ${expected_count} -eq 0 ]]; then
      echo "${SCRIPT_NAME}: no Running DataNodes found while checking syncLag."
      let fail_flag++
      return 1
   fi

   wait_start_time=$(date +%s)
   query="sum(${metric_name}{instance=~\"^(${instance_regex})$\",name=\"${server_name}\",type=\"syncLag\"}) by (instance)"
   echo "${SCRIPT_NAME}: waiting for syncLag=0 on ${expected_count} Running DataNodes (stable for ${target_duration}s)."
   while true
   do
      now=$(date +%s)
      if (( now - wait_start_time > max_wait_seconds )); then
         echo "${SCRIPT_NAME}: timed out waiting for syncLag=0; latest response: ${response_file}"
         if [[ -s "${last_nonzero_response}" ]]; then
            collect_non_zero_sync_lag_jstacks "${last_nonzero_response}"
         else
            echo "${SCRIPT_NAME}: timeout had no valid non-zero syncLag sample to identify nodes for jstack."
         fi
         let fail_flag++
         return 1
      fi

      curl -sS --connect-timeout 5 --max-time 15 -u "${prometheus_user}:${prometheus_pass}" --get --data-urlencode "query=${query}" "${monitor_url}/api/v1/query" > "${response_file}"
      response_status=$(parse_monitor_query_status "${response_file}")
      if [[ $? -ne 0 || "${response_status}" != "success" ]]; then
         zero_start_time=0
         sleep "${sleep_interval}"
         continue
      fi
      result_count=$(count_sync_lag_series "${response_file}")
      non_zero_num=$(count_non_zero_sync_lag "${response_file}")
      if [[ "${non_zero_num}" =~ ^[0-9]+$ ]] && (( non_zero_num > 0 )); then
         cp -f "${response_file}" "${last_nonzero_response}"
      fi
      if [[ ! "${result_count}" =~ ^[0-9]+$ || ! "${non_zero_num}" =~ ^[0-9]+$ || ${result_count} -lt ${expected_count} || ${non_zero_num} -gt 0 ]]; then
         zero_start_time=0
         sleep "${sleep_interval}"
         continue
      fi
      if [[ ${zero_start_time} -eq 0 ]]; then
         zero_start_time=${now}
      fi
      if (( now - zero_start_time >= target_duration )); then
         echo "${SCRIPT_NAME}: syncLag remained 0 for ${target_duration}s; proceeding with replica consistency checks."
         return 0
      fi
      sleep "${sleep_interval}"
   done
}
function wait_sync_done()
{
local max_wait_time=$1
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "flush;">${cur_dir}/tmp.out
   check_res "success" 1 "${SCRIPT_NAME}"
   wait_for_sync_lag_zero "${max_wait_time}" 60
}
function check_data_consistent()
{
wait_sync_done 3600 || return 1
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;">${cur_dir}/tmp.out
   cat ${cur_dir}/tmp.out |grep Running|awk -F "|" '{gsub(" ","");print $4}'>${cur_dir}/tmp1.out
   mv ${cur_dir}/tmp1.out ${cur_dir}/tmp.out
   sql1="select count(s_0) from root.test.g_0.** align by device;" 
   sql2="select count(s_0) from region_ops_invalid_20260923.region_invalid_seed;"
   # all online
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -timeout 3600 -e "${sql1}" >${cur_dir}/q_all_online_tree.out 
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -sql_dialect table -timeout 3600 -e "${sql2}" >${cur_dir}/q_all_online_table.out
   # stop dn
   exec 3<${cur_dir}/tmp.out
   while read line<&3
   do
   query_ip=`head -1 ${cur_dir}/tmp.out`
   query_ip2=`tail -1 ${cur_dir}/tmp.out`

      # stop dn
      ssh ${u_name}@${line} "source /etc/profile;cd ${db_dir};sudo ./sbin/stop-datanode.sh"
      check_dn_jps ${line} 60
      if [[ ${query_ip} = ${line} ]];then
         query_ip=${query_ip2} 
      fi
      v_ip=`echo ${line}|awk -F '.' '{print $4}'`
      ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip}  -timeout 3600 -e "${sql1}" >${cur_dir}/q_stop_ip${v_ip}_tree.out
      v_diff_tree=`diff ${cur_dir}/q_all_online_tree.out ${cur_dir}/q_stop_ip${v_ip}_tree.out|grep "root."|wc -l`
      if [[ ${v_diff_tree} -gt 0 ]];then
         let fail_flag++
         echo "${v_diff_tree}"
      fi
      ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -sql_dialect table -timeout 3600 -e "${sql2}" >${cur_dir}/q_stop_ip${v_ip}_table.out
      sed '/^It costs /d' ${cur_dir}/q_all_online_table.out >${cur_dir}/q_all_online_table_normalized.out
      sed '/^It costs /d' ${cur_dir}/q_stop_ip${v_ip}_table.out >${cur_dir}/q_stop_ip${v_ip}_table_normalized.out
      if ! diff -q ${cur_dir}/q_all_online_table_normalized.out ${cur_dir}/q_stop_ip${v_ip}_table_normalized.out >/dev/null; then
         let fail_flag++
         echo "Table-model replica consistency mismatch on ${line}."
         diff ${cur_dir}/q_all_online_table_normalized.out ${cur_dir}/q_stop_ip${v_ip}_table_normalized.out
      fi
      # restart
      v_start_time=`date +%s`
      ssh ${u_name}@${line} "source /etc/profile;cd ${db_dir};sudo ./sbin/start-datanode.sh -H ${db_dir}/dn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"
      while true
      do
      v_start_ok=`${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${line}  -timeout 3600 -e "show datanodes;"|grep "${line}|"|grep Running|wc -l`
      if [[ ${v_start_ok} -gt 0 ]];then
         break
      else
         sleep 1
      fi
      v_cur_time=`date +%s`
      v_elp_time=$((v_cur_time-v_start_time))
      if [[ ${v_elp_time} -gt 120 ]];then
         let fail_flag++
         echo "restart ${line} failed."
         return
      fi  
      done 
   done 
}
function check_restart()
{
   v_ip=$1
   v_query_ip=$2
v_start_time=`date +%s`
      while true
      do
      v_start_ok=`${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${v_query_ip}  -timeout 3600 -e "show datanodes;"|grep "${v_ip}|"|grep Running|wc -l`
      if [[ ${v_start_ok} -gt 0 ]];then
         break
      else
         sleep 1
      fi
      v_cur_time=`date +%s`
      v_elp_time=$((v_cur_time-v_start_time))
      if [[ ${v_elp_time} -gt 120 ]];then
         let fail_flag++
         echo "restart ${line} failed."
         return
      fi
      done

}

function stop_dn()
{
   local rm_dn_ip=$1
   local v_query_ip=$2
        # stop rm_dn_ip
        ssh ${u_name}@${rm_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh"
        while true
        do
           v_unknown=`${cli_dir}/sbin/start-cli.sh -h ${v_query_ip} -u ${db_sys_admin} ${ssl_str} -e "show datanodes;"|grep "${rm_dn_ip}|"|grep -i unknown|wc -l`
           if [[ ${v_unknown} -gt 0 ]];then
              break
           else
              sleep 2
           fi
        done
        while true
        do
           v_unknown=`ssh ${u_name}@${rm_dn_ip} "sudo jps|grep -i datanode|wc -l"`
           if [[ ${v_unknown} = 0 ]];then
              break
           else
              sleep 2
           fi
        done

}

function start_dn()
{
   local rm_dn_ip=$1
   local v_query_ip=$2 
   # start rm_dn_ip
   v_t=`date "+%Y_%m_%d_%H_%M_%S"`
   ssh ${u_name}@${rm_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/${v_t}_restart_dn.hprof > /dev/null 2>&1 &"
   while true
   do
           sleep 5
      v_running=`${cli_dir}/sbin/start-cli.sh -h ${v_query_ip} -u ${db_sys_admin} ${ssl_str} -timeout 3600  -e "show datanodes;" |grep "${rm_dn_ip}|" |grep Running|wc -l`
      if [[ ${v_running} = 1 ]];then
              break
      else
              sleep 5
      fi
   done

}

function wait_Adding_finish()
{
local v_query_ip=$1
local max_wait_time=$2
local t1=`date +%s`
  while true
   do
       ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${v_query_ip} -e "show regions;">${cur_dir}/tmp.out
       v_rm_succ=`cat ${cur_dir}/tmp.out |grep "Adding"|wc -l`
       if [[ ${v_rm_succ} -gt 0 ]];then
          sleep 5
       else
          break
       fi
      t2=`date +%s`
      t_elp=$((t2-t1))
      if [[ ${t_elp} -gt ${max_wait_time} ]];then
         let fail_flag++
         let rm_fail_flag++
         echo "Adding takes too long."
         break
      fi

   done

}
function wait_Removing_finish()
{
local v_query_ip=$1
local max_wait_time=$2
local t1=`date +%s`
  while true
   do
       ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${v_query_ip} -e "show regions;">${cur_dir}/tmp.out
       v_rm_succ=`cat ${cur_dir}/tmp.out |grep "Removing"|wc -l`
       if [[ ${v_rm_succ} -gt 0 ]];then
          sleep 10
       else
          break
       fi
      t2=`date +%s`
      t_elp=$((t2-t1))
      if [[ ${t_elp} -gt ${max_wait_time} ]];then
         let fail_flag++
         let rm_fail_flag++
         echo "Removing takes too long."
         break
      fi

   done

}


function remove_dn()
{
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;">${cur_dir}/tmp.out
   v_rm_id=`cat ${cur_dir}/tmp.out |grep "${query_ip2}|"|tail -1|awk -F "|" '{gsub(" ","");print $2}'`
   v_rm_ip=`cat ${cur_dir}/tmp.out |grep "${query_ip2}|"|tail -1|awk -F "|" '{gsub(" ","");print $4}'`

#start 2bm
   v_bm_t=`date "+%Y_%m_%d_%H_%M_%S"`
   v_host=`awk '{printf "%s%s", (NR==1?"":","), $0}' ${nodeinfo_dir}/datanode.txt`
   v_20_pass=`grep ^passwd_param= ${cli_dir}/sbin/start-cli.sh |grep TimechoDB|wc -l`
if [[ ${v_20_pass} -gt 0 ]];then
        bm_root_pw="TimechoDB@2021"
else

        bm_root_pw="root"
fi
sed -i "s/^PASSWORD=.*/PASSWORD=${bm_root_pw}/g" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties
   sed -i "s/^HOST=.*/HOST=${v_host}/g" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties
   sed -i "s/LOOP=.*/LOOP=5000/g" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties
   nohup sh -x ${bm_dir}/benchmark.sh -cf ${bm_dir}/lt_10type_user_no_ssl/conf1 >${bm_dir}/${v_bm_t}_tc2026_region_ops_bm1.out &
   nohup sh -x ${bm_dir}/benchmark.sh -cf ${bm_dir}/lt_10type_user_no_ssl/conf2 >${bm_dir}/${v_bm_t}_tc2026_region_ops_bm2.out &
   sleep 60
# extend region
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e  'show regions'|grep "${query_ip}|"|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/mig_id.txt
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e  'show regions'|grep "${query_ip2}|"|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/mig_id2.txt
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e 'show confignodes;'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_cn_id.txt
>${cur_dir}/region.txt
   exec 3<${cur_dir}/mig_id2.txt
   while read line<&3
   do
   echo "${line}">>${cur_dir}/region.txt
   done
exec 3<&-
   v_remove_list=`paste -sd "," ${cur_dir}/region.txt`
# reconstruct exist ,dn id not exist
   echo "RECONSTRUCT REGION TIME: $(date "+%Y-%m-%d %H:%M:%S")"
exec 4<${cur_dir}/all_cn_id.txt
while read cnid<&4
do
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "RECONSTRUCT REGION ${v_remove_list}  ON ${cnid};">${cur_dir}/tmp.out
   check_res "Target DataNode ${cnid} does not exist in the cluster" 1 "${SCRIPT_NAME}"
   cat ${cur_dir}/tmp.out

done
exec 4<&-

# region id not exist , dn id not exist
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e "RECONSTRUCT REGION 17700,9109  ON 2222;">${cur_dir}/tmp.out
check_res "Target DataNode 2222 does not exist in the cluster" 1 "${SCRIPT_NAME}"

# some region id not exist , dn id not exist
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e "RECONSTRUCT REGION 17700,${v_rm_id}  ON 2222;">${cur_dir}/tmp.out
check_res "Target DataNode 2222 does not exist in the cluster" 1 "${SCRIPT_NAME}"

# region id not exist , dn id exist
# region id exist ,but this dn id hasn't
>${cur_dir}/region.txt
   exec 3<${cur_dir}/mig_id.txt
   while read line<&3
   do
   v_find_num=`grep -w ${line} ${cur_dir}/mig_id2.txt|wc -l`
   if [[ ${v_find_num} = 0 ]] &&  [[ -n "$line" ]];then
   echo "${line}">>${cur_dir}/region.txt
   fi
   done
exec 3<&-
   v_remove_list=`paste -sd "," ${cur_dir}/region.txt`
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e "RECONSTRUCT REGION ${v_remove_list}  ON ${v_rm_id};">${cur_dir}/tmp.out
check_res "Submit ReconstructRegionProcedure failed, because the target DataNode ${v_rm_id} doesn't contain Region" 1 "${SCRIPT_NAME}"
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e "RECONSTRUCT all regions ON ${v_rm_id};">${cur_dir}/tmp.out
check_res "mismatched input 'all' expecting REGION" 1 "${SCRIPT_NAME}"
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e "RECONSTRUCT ALL REGIONS ON ${v_rm_id};">${cur_dir}/tmp.out
check_res "mismatched input 'ALL' expecting REGION" 1 "${SCRIPT_NAME}"
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e "RECONSTRUCT NULL REGIONS ON ${v_rm_id};">${cur_dir}/tmp.out
check_res "mismatched input 'NULL' expecting REGION" 1 "${SCRIPT_NAME}"

   wait_Adding_finish ${query_ip} 3600
   wait_Removing_finish ${query_ip} 3600
   wait_bm_finish 36000 "${bm_dir}/${v_bm_t}_tc2026_region_ops_bm1.out" "${bm_dir}/${v_bm_t}_tc2026_region_ops_bm2.out"
   seed_and_verify_region_ops_data
   test_invalid_region_operation_lists
   wait_Adding_finish ${query_ip} 3600
   wait_Removing_finish ${query_ip} 3600
   v_add_num1=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e  'show regions;'|grep Adding|wc -l`
   v_add_num2=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} -e  'show regions;'|grep Removing|wc -l`
   v_add_num=$((v_add_num1+v_add_num2))

   if [[ ${v_add_num} -gt 0 ]];then
      let rm_fail_flag++
      let fail_flag++
   fi 
if [[ ${rm_fail_flag} = 0 ]];then
   check_data_consistent
echo "no check" 
fi

check_region_operation_error_logs
   check_npe "${SCRIPT_NAME}"
backup_logs
test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))
tc_res=true

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass"
     rm -rf ${bm_dir}/${v_bm_t}_tc2026_region_ops_bm1.out 
     rm -rf ${bm_dir}/${v_bm_t}_tc2026_region_ops_bm2.out 
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail"
  fi
echo "${tc_num}"
echo "${SCRIPT_NAME}"
echo "${tc_res}"
echo "${test_elp_sec}"
res_root_pw=TimechoDB@2021
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -pw ${res_root_pw} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

}
clean_env
start_db
remove_dn

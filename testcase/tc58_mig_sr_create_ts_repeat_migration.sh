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
# TDB-462 repeat-migration variant. Optional controls:
# TDB462_MIN_MIGRATIONS=3 TDB462_MAX_MIGRATIONS=15
# TDB462_MIGRATION_TIMEOUT_SEC=600 TDB462_POLL_INTERVAL_SEC=1 TDB462_STABLE_POLLS=1
fail_file="${SCRIPT_NAME%.sh}_fail.log"
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
testcase_res_db=`cat ${conf_file}|grep testcase_res_db|awk -F '=' '{print $2}'`
testcase_res_port=`cat ${conf_file}|grep testcase_res_port|awk -F '=' '{print $2}'`
test_begin_sec=`date +%s`
v_warnMsg="."
run_dir="${cur_dir}/logs_backup/${SCRIPT_NAME%.sh}_run_$(date +%Y%m%d_%H%M%S)_$$"

function finish_test()
{
   local result_kind
   local result_label
   local reason
   local test_end_sec
   local test_elp_sec
   local tc_res

   if (( defect_evidence != 0 ));then
      result_kind=TDB462_SYMPTOM
   elif (( fail_flag != 0 ));then
      result_kind=OTHER_FAILURE
   elif (( stress_shortfall != 0 ));then
      result_kind=INSUFFICIENT_STRESS
   else
      result_kind=PASS
   fi
   printf 'result=%s\n' "${result_kind}" | tee -a "${run_dir}/repeat_migration_summary.out"
   printf 'Run artifacts: %s\n' "${run_dir}"
   if [[ -s "${run_dir}/${fail_file}" ]];then
      while IFS= read -r reason;do
         printf 'FAIL REASON: %s\n' "${reason}" | tee -a "${res_file}"
      done < "${run_dir}/${fail_file}"
   fi
   if [[ "${result_kind}" != PASS && -s "${run_dir}/create_ts.out" ]];then
      awk 'tolower($0) ~ /302|906|already exist|doesn.t exist|exception|error/ {
              print "CREATE VIEW ERROR: " substr($0, 1, 500)
              if (++shown == 3) exit
           }' "${run_dir}/create_ts.out" | tee -a "${res_file}"
   fi

   test_end_sec=`date +%s`
   test_elp_sec=$((test_end_sec-test_begin_sec))
   v_warnMsg="${result_kind}"
   if [[ "${result_kind}" == PASS ]];then
      tc_res=true
      result_label=pass
   else
      tc_res=false
      result_label=fail
   fi
   printf '%s : %s (%s); artifacts=%s\n' "${SCRIPT_NAME}" "${result_label}" "${result_kind}" "${run_dir}" | tee -a "${res_file}"
   if [[ "${result_kind}" == TDB462_SYMPTOM || "${result_kind}" == OTHER_FAILURE ]];then
      backup_cluster_logs
   fi
   ${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time,warnMsg)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec},'${v_warnMsg}');"
   [[ "${result_kind}" == PASS ]]
}
function clean_env()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
}

# TDB-462: preserve node logs before the final clean_env removes the log directories.
function backup_cluster_logs()
{
   local backup_started_at
   local backup_dir
   local bundle_path
   local host_list
   local node_role
   local host
   local archive_path

   backup_started_at=`date +%Y%m%d_%H%M%S`
   backup_dir="${run_dir}/cluster_logs_${backup_started_at}"
   bundle_path="${run_dir}/cluster_logs_${backup_started_at}.tar.gz"
   mkdir -p "${backup_dir}"
   : > "${backup_dir}/manifest.txt"

   for node_role in confignode datanode
   do
      host_list="${nodeinfo_dir}/${node_role}.txt"
      while read -r host
      do
         [[ -z "${host}" || "${host}" == \#* ]] && continue
         archive_path="${backup_dir}/${node_role}_${host}.tar.gz"
         if ssh -n -o ConnectTimeout=10 "${u_name}@${host}" \
              "sudo tar -czf - -C '${db_dir}/logs' ." > "${archive_path}" &&
              tar -tzf "${archive_path}" >/dev/null 2>&1; then
            echo "${node_role} ${host}: ${archive_path}" >> "${backup_dir}/manifest.txt"
         else
            echo "${node_role} ${host}: log archive failed; see testcase output" >> "${backup_dir}/manifest.txt"
         fi
      done < "${host_list}"
   done

   tar -czf "${bundle_path}" -C "${run_dir}" "$(basename "${backup_dir}")"
   echo "Failure log backup: ${bundle_path}"
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
     ssh ${u_name}@${line} "sed -i 's/#ON_HEAP_MEMORY=.*/ON_HEAP_MEMORY=\"22G\"/g' ${db_dir}/conf/datanode-env.sh"
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

function pre_and_exec_mig_region()
{
  local expected_count=1000000
  local min_migrations=${TDB462_MIN_MIGRATIONS:-3}
  local max_migrations=${TDB462_MAX_MIGRATIONS:-15}
  local migration_timeout_sec=${TDB462_MIGRATION_TIMEOUT_SEC:-600}
  # A completed migration already requires the new replica to be Running, the
  # old replica to be absent, and SHOW MIGRATIONS to contain no matching job.
  # Extra stable polls delay the next migration and can let CREATE VIEW finish.
  local poll_interval_sec=${TDB462_POLL_INTERVAL_SEC:-1}
  local stable_polls=${TDB462_STABLE_POLLS:-1}
  local migration_count=0
  local concurrent_migration_count=0
  local create_rc=0
  local create_pid
  local create_running
  local region_info
  local datanode_info
  local region_id
  local migration_output
  local migration_rc
  local round
  local replica_state
  local migration_state
  local from_dn_id
  local to_dn_id
  local target_offset
  local candidate_dn_id
  local stable_count
  local start_sec
  local cur_sec
  local migration_elapsed_sec
  local non_running_count
  local from_count
  local to_count
  local active_migration_count
  local migration_header_valid
  local final_replica_count
  local final_non_running_count
  local view_count
  local source_count
  local initial_new_view_count
  local defect_evidence=0
  local stress_shortfall=0
  local -a running_dn_ids=()
  local -a replica_ids=()
  local -a region_rows=()

  mkdir -p "${run_dir}" || { echo "cannot create run artifacts: ${run_dir}" >&2; return 1; }
  : > "${run_dir}/${fail_file}"
  : > "${run_dir}/repeat_migration_summary.out"
  echo "Run artifacts: ${run_dir}"

  if [[ ! "${min_migrations}" =~ ^[0-9]+$ || ! "${max_migrations}" =~ ^[0-9]+$ || \
        ! "${migration_timeout_sec}" =~ ^[0-9]+$ || ! "${poll_interval_sec}" =~ ^[0-9]+$ || \
        ! "${stable_polls}" =~ ^[0-9]+$ ]] || \
     (( min_migrations < 3 || max_migrations < min_migrations || migration_timeout_sec < 1 || poll_interval_sec < 1 || stable_polls < 1 ));then
     echo "invalid migration limits: min=${min_migrations}, max=${max_migrations}" >> "${run_dir}/${fail_file}"
     let fail_flag++
     finish_test
     return 1
  fi

  source_count=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.d*.*;" | awk -F '|' '/\|[[:space:]]*[0-9]+[[:space:]]*\|/ {gsub(/[[:space:]]/,"",$2); print $2; exit}'`
  view_count=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.view_from_d*.*;" | awk -F '|' '/\|[[:space:]]*[0-9]+[[:space:]]*\|/ {gsub(/[[:space:]]/,"",$2); print $2; exit}'`
  initial_new_view_count=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.view_mig_from_d*.*;" | awk -F '|' '/\|[[:space:]]*[0-9]+[[:space:]]*\|/ {gsub(/[[:space:]]/,"",$2); print $2; exit}'`
  if [[ "${source_count}" != "${expected_count}" || "${view_count}" != "${expected_count}" || "${initial_new_view_count}" != "0" ]];then
     echo "initial data count mismatch: source=${source_count}, existing_views=${view_count}, new_views=${initial_new_view_count}; expected=${expected_count}, ${expected_count}, 0" >> "${run_dir}/${fail_file}"
     let fail_flag++
     finish_test
     return 1
  fi

  region_info="`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show schema regions;' 2>&1`"
  printf '%s\n' "${region_info}" > "${run_dir}/show_schema_regions_before.out"
  region_id=`printf '%s\n' "${region_info}" | awk -F '|' '$3 ~ /SchemaRegion/ && $0 ~ /root\.test/ {gsub(/[[:space:]]/,"",$2); print $2; exit}'`
  if [[ -z "${region_id}" ]];then
     echo "cannot find the SchemaRegion for root.test; see show_schema_regions_before.out" >> "${run_dir}/${fail_file}"
     let fail_flag++
     finish_test
     return 1
  fi

  datanode_info="`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show datanodes;' 2>&1`"
  printf '%s\n' "${datanode_info}" > "${run_dir}/show_datanodes_before.out"
  mapfile -t running_dn_ids < <(printf '%s\n' "${datanode_info}" | awk -F '|' '$0 ~ /Running/ {gsub(/[[:space:]]/,"",$2); if ($2 ~ /^[0-9]+$/) print $2}')
  if (( ${#running_dn_ids[@]} != dn_num ));then
     echo "need exactly ${dn_num} Running DataNodes, found ${#running_dn_ids[@]}" >> "${run_dir}/${fail_file}"
     let fail_flag++
     finish_test
     return 1
  fi

  # Start the same million-view statement first, then churn this Region while
  # that single JDBC/CLI request remains in flight.
  echo "CREATE VIEW started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${run_dir}/repeat_migration_summary.out"
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e \
     "create view root.test.g_0.view_mig_from_\${3}(\${4}) as select * from root.test.g_0.d*;" \
     > "${run_dir}/create_ts.out" 2>&1 &
  create_pid=$!
  echo "CREATE VIEW pid=${create_pid}; Region=${region_id}; min_migrations=${min_migrations}; max_migrations=${max_migrations}; poll_interval_sec=${poll_interval_sec}; stable_polls=${stable_polls}" \
     | tee -a "${run_dir}/repeat_migration_summary.out"

  round=0
  while (( round < max_migrations ));do
     create_running=0
     if kill -0 "${create_pid}" 2>/dev/null && ! ps -o stat= -p "${create_pid}" 2>/dev/null | grep -q '^Z';then
        create_running=1
     fi
     if (( create_running == 0 ));then
        break
     fi

     # The previous round's completion poll already returned a fresh topology.
     # Only the first round needs a new SHOW SCHEMA REGIONS request.
     if (( round == 0 ));then
        region_info="`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show schema regions;' 2>&1`"
     fi
     printf '%s\n' "${region_info}" > "${run_dir}/show_schema_regions_round_${round}.out"
     mapfile -t region_rows < <(printf '%s\n' "${region_info}" | awk -F '|' -v rid="${region_id}" '
       function trim(v) { gsub(/[[:space:]]/,"",v); return v }
       trim($2) == rid && trim($3) == "SchemaRegion" { print trim($4) "," trim($8) }')
     replica_ids=()
     non_running_count=0
     for replica_state in "${region_rows[@]}";do
        IFS=, read -r migration_state candidate_dn_id <<< "${replica_state}"
        [[ -z "${candidate_dn_id}" ]] && continue
        replica_ids+=("${candidate_dn_id}")
        [[ "${migration_state}" != "Running" ]] && non_running_count=$((non_running_count+1))
     done
     if (( ${#replica_ids[@]} != sr_rep_num || non_running_count != 0 ));then
        echo "Region not stable before migration round=${round}: replicas=${#replica_ids[@]}, non_running=${non_running_count}" >> "${run_dir}/${fail_file}"
        let fail_flag++
        break
     fi

     from_dn_id="${replica_ids[$((round % sr_rep_num))]}"
     to_dn_id=""
     for ((target_offset=0; target_offset<${#running_dn_ids[@]}; target_offset++));do
        candidate_dn_id="${running_dn_ids[${target_offset}]}"
        if [[ ! " ${replica_ids[*]} " =~ " ${candidate_dn_id} " ]];then
           to_dn_id="${candidate_dn_id}"
           break
        fi
     done
     if [[ -z "${to_dn_id}" ]];then
        echo "cannot find a non-replica Running DataNode for round=${round}" >> "${run_dir}/${fail_file}"
        let fail_flag++
        break
     fi

     # A region query may take long enough for CREATE VIEW to finish. Check
     # again immediately before submission to avoid a known false overlap.
     if ! kill -0 "${create_pid}" 2>/dev/null ||
        ps -o stat= -p "${create_pid}" 2>/dev/null | grep -q '^Z';then
        break
     fi

     round=$((round+1))
     migration_output="${run_dir}/mig_${region_id}_${round}_${from_dn_id}_to_${to_dn_id}.out"
     ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e \
        "MIGRATE REGION ${region_id} FROM ${from_dn_id} TO ${to_dn_id};" \
        > "${migration_output}" 2>&1
     migration_rc=$?
     if (( migration_rc != 0 )) || ! grep -qi 'statement is executed successfully' "${migration_output}";then
        echo "MIGRATE REGION submit failed at round=${round}, ${from_dn_id}->${to_dn_id}; see ${migration_output}" >> "${run_dir}/${fail_file}"
        let fail_flag++
        break
     fi
     concurrent_migration_count=$((concurrent_migration_count+1))
     echo "round=${round} region=${region_id} from=${from_dn_id} to=${to_dn_id} create_running_before_submit=${create_running} submitted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        | tee -a "${run_dir}/repeat_migration_summary.out"

     stable_count=0
     start_sec=`date +%s`
     while true;do
        region_info="`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show schema regions;' 2>&1`"
        mapfile -t region_rows < <(printf '%s\n' "${region_info}" | awk -F '|' -v rid="${region_id}" '
          function trim(v) { gsub(/[[:space:]]/,"",v); return v }
          trim($2) == rid && trim($3) == "SchemaRegion" { print trim($4) "," trim($8) }')
        replica_ids=()
        non_running_count=0
        from_count=0
        to_count=0
        for replica_state in "${region_rows[@]}";do
           IFS=, read -r migration_state candidate_dn_id <<< "${replica_state}"
           [[ -z "${candidate_dn_id}" ]] && continue
           replica_ids+=("${candidate_dn_id}")
           [[ "${migration_state}" != "Running" ]] && non_running_count=$((non_running_count+1))
           [[ "${candidate_dn_id}" == "${from_dn_id}" ]] && from_count=$((from_count+1))
           [[ "${candidate_dn_id}" == "${to_dn_id}" ]] && to_count=$((to_count+1))
        done

        migration_info="`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show migrations;' 2>&1`"
        printf '%s\n' "${migration_info}" > "${run_dir}/show_migrations_round_${round}.out"
        migration_header_valid=`printf '%s\n' "${migration_info}" | grep -Ec '^\|[[:space:]]*ProcedureId[[:space:]]*\|[[:space:]]*OperationType[[:space:]]*\|[[:space:]]*RegionId[[:space:]]*\|'`
        if (( migration_header_valid == 0 ));then
           echo "SHOW MIGRATIONS response is invalid; see show_migrations_round_${round}.out" >> "${run_dir}/${fail_file}"
           let fail_flag++
           break 2
        fi
        # SHOW MIGRATIONS has a leading pipe, so RegionId/Type/From/To are fields 4/5/6/7.
        active_migration_count=`printf '%s\n' "${migration_info}" | awk -F '|' -v rid="${region_id}" -v from="${from_dn_id}" -v to="${to_dn_id}" '
          function trim(v) { gsub(/[[:space:]]/,"",v); return v }
          trim($4) == rid && trim($5) == "SchemaRegion" && trim($6) == from && trim($7) == to { n++ }
          END { print n+0 }'`

        if (( ${#replica_ids[@]} == sr_rep_num && non_running_count == 0 && from_count == 0 && to_count == 1 && active_migration_count == 0 ));then
           stable_count=$((stable_count+1))
           if (( stable_count >= stable_polls ));then
              break
           fi
        else
           stable_count=0
        fi

        cur_sec=`date +%s`
        if (( cur_sec-start_sec >= migration_timeout_sec ));then
           printf '%s\n' "${region_info}" > "${run_dir}/show_schema_regions_timeout_round_${round}.out"
           echo "migration timed out at round=${round}, ${from_dn_id}->${to_dn_id}; see timeout snapshots" >> "${run_dir}/${fail_file}"
           let fail_flag++
           break 2
        fi
        sleep "${poll_interval_sec}"
     done
     migration_count=$((migration_count+1))
     migration_elapsed_sec=$(( $(date +%s) - start_sec ))
     echo "round=${round} migration_completed_sec=${migration_elapsed_sec}" \
        | tee -a "${run_dir}/repeat_migration_summary.out"
  done

  wait "${create_pid}"
  create_rc=$?
  echo "CREATE VIEW finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${run_dir}/repeat_migration_summary.out"
  if (( create_rc != 0 ));then
     echo "CREATE VIEW command returned rc=${create_rc}; see create_ts.out" >> "${run_dir}/${fail_file}"
     let fail_flag++
  fi
  if ! grep -qi 'statement is executed successfully' "${run_dir}/create_ts.out";then
     echo "CREATE VIEW output lacks the success response; see create_ts.out" >> "${run_dir}/${fail_file}"
     let fail_flag++
  fi
  if (( concurrent_migration_count < min_migrations ));then
     echo "only ${concurrent_migration_count} migrations overlapped CREATE VIEW; minimum is ${min_migrations}" >> "${run_dir}/${fail_file}"
     stress_shortfall=1
  fi

  view_count=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.view_mig_from_d*.*;" | awk -F '|' '/\|[[:space:]]*[0-9]+[[:space:]]*\|/ {gsub(/[[:space:]]/,"",$2); print $2; exit}'`
  source_count=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "count timeseries root.test.g_0.d*.*;" | awk -F '|' '/\|[[:space:]]*[0-9]+[[:space:]]*\|/ {gsub(/[[:space:]]/,"",$2); print $2; exit}'`
  echo "completed_migrations=${migration_count}; overlapping_migrations=${concurrent_migration_count}; final_views=${view_count}; source_series=${source_count}; create_rc=${create_rc}" \
     | tee -a "${run_dir}/repeat_migration_summary.out"
  if [[ "${view_count}" != "${expected_count}" || "${source_count}" != "${expected_count}" ]];then
     echo "final count mismatch: views=${view_count}, source=${source_count}, expected=${expected_count}" >> "${run_dir}/${fail_file}"
     let fail_flag++
  fi
  if grep -Eqi 'Path .* already exist|SchemaRegion\[[^]]+\] doesn.t exist|error code[: ]+302|error code[: ]+906' "${run_dir}/create_ts.out";then
     echo "CREATE VIEW output contains a TDB-462 signature; see create_ts.out" >> "${run_dir}/${fail_file}"
     let fail_flag++
     defect_evidence=1
  fi
  if [[ "${source_count}" == "${expected_count}" && "${view_count}" =~ ^[0-9]+$ ]] && (( view_count < expected_count ));then
     defect_evidence=1
  fi

  region_info="`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e 'show schema regions;' 2>&1`"
  printf '%s\n' "${region_info}" > "${run_dir}/show_schema_regions_final.out"
  mapfile -t region_rows < <(printf '%s\n' "${region_info}" | awk -F '|' -v rid="${region_id}" '
    function trim(v) { gsub(/[[:space:]]/,"",v); return v }
    trim($2) == rid && trim($3) == "SchemaRegion" { print trim($4) "," trim($8) }')
  final_replica_count=${#region_rows[@]}
  final_non_running_count=0
  for replica_state in "${region_rows[@]}";do
     IFS=, read -r migration_state candidate_dn_id <<< "${replica_state}"
     [[ -n "${candidate_dn_id}" && "${migration_state}" != "Running" ]] && final_non_running_count=$((final_non_running_count+1))
  done
  if (( final_replica_count != sr_rep_num || final_non_running_count != 0 ));then
     echo "final SchemaRegion state invalid: replicas=${final_replica_count}, non_running=${final_non_running_count}" >> "${run_dir}/${fail_file}"
     let fail_flag++
  fi

# check NullPointer
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
   ssh ${u_name}@${line} "sudo gunzip ${db_dir}/logs/log-datanode-*"
   v_npe=`ssh ${u_name}@${line} "grep NullPointer ${db_dir}/logs/*datanode*all*|wc -l"`
   if [[ ${v_npe} -gt 0 ]];then
       echo "NullPointer found in DataNode ${line} logs: count=${v_npe}" >> "${run_dir}/${fail_file}"
       let fail_flag++
   fi
done
exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
   ssh ${u_name}@${line} "sudo gunzip ${db_dir}/logs/log-confignode-*"
   v_npe=`ssh ${u_name}@${line} "grep NullPointer ${db_dir}/logs/*confignode*all*|wc -l"`
   if [[ ${v_npe} -gt 0 ]];then
       echo "NullPointer found in ConfigNode ${line} logs: count=${v_npe}" >> "${run_dir}/${fail_file}"
       let fail_flag++
   fi
done


  finish_test

 
} 
clean_env
start_db
pre_and_exec_mig_region

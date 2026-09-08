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
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=134217728"     
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
set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=134217728"
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

function run_check_query()
{
   local path_pattern=$1
   local output_file=$2
   local expired_values=$3
   local expected_expired_rows=$4
   local live_values=$5
   local expected_live_rows=$6
   local query_sql="select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from ${path_pattern} align by device;"

   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "${query_sql}" > "${output_file}" 2>&1
   local cli_status=$?
   if [[ ${cli_status} -ne 0 ]] || grep -Eqi '^Msg:.*(exception|error|failed|not enough memory)' "${output_file}";then
      echo "query failed for ${path_pattern}, cli_status=${cli_status}:" >&2
      cat "${output_file}" >&2
      let fail_flag++
      return 1
   fi

   local result_values
   result_values=`grep root "${output_file}"|awk -F "|" '{gsub(" ","");print $5","$6","$7}'`

   local actual_expired_rows
   actual_expired_rows=`echo "${result_values}"|grep -c "^${expired_values}$"`
   if [[ ${actual_expired_rows} != ${expected_expired_rows} ]];then
      echo "unexpected expired result for ${path_pattern}: expected ${expected_expired_rows} rows of ${expired_values}, actual ${actual_expired_rows}" >&2
      let fail_flag++
      return 1
   fi

   local actual_live_rows
   actual_live_rows=`echo "${result_values}"|grep -c "^${live_values}$"`
   if [[ ${actual_live_rows} != ${expected_live_rows} ]];then
      echo "unexpected live result for ${path_pattern}: expected ${expected_live_rows} rows of ${live_values}, actual ${actual_live_rows}" >&2
      let fail_flag++
      return 1
   fi
   return 0
}

function pre_and_exec_mig_region()
{

  v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8","$9}'>${cur_dir}/mig_id_info.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/all_dn_id_ip.txt

local v_mig_to_dn_id=-1
v_del_flag=0
exec 3<${cur_dir}/mig_id_info.txt
while read line<&3
do
   v_mig_from_dn_id=`echo ${line}|awk -F ',' '{print $1}'`
   if [[ ${v_mig_to_dn_id} -lt 0 ]];then
         while read v_candidate_dn_id
         do
             v_check=`grep -x ${v_candidate_dn_id} ${cur_dir}/mig_region_dn_id.txt|wc -l`
             if [[ ${v_check} = 0 ]];then
                v_mig_to_dn_id=${v_candidate_dn_id}
                break
             fi
         done < ${cur_dir}/all_dn_id.txt
         if [[ ${v_mig_to_dn_id} -lt 0 ]];then
            echo "no available target DataNode for region ${v_mig_id}" >&2
            let fail_flag++
            return 1
         fi
   fi
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   v_bef_mig_time=`ssh ${u_name}@${v_cn_leader_ip} "date +\"%Y-%m-%d %H:%M:%S\""`
   v_bef_mig_sec=`date -d"${v_bef_mig_time}" +%s`
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id};" > ${cur_dir}/mig.out
   sleep 2
   if [[ ${v_del_flag} -gt 0 ]];then
      echo "have been executed delete timeseries;"
   else 
      ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "set ttl to root.** 360000000;">${cur_dir}/del_s_40.out &
      let v_del_flag++
   fi
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   while true
   do
      ssh ${u_name}@${v_cn_leader_ip} "if compgen -G '${db_dir}/logs/log-confignode-all*.gz' >/dev/null;then sudo gunzip ${db_dir}/logs/log-confignode-all*.gz;fi"
              v_mig_suc_log=`ssh ${u_name}@${v_cn_leader_ip} "grep \"\[MigrateRegion\] success\" ${db_dir}/logs/*confignode*all.log|tail -1"`
              v_mig_suc_time=`echo ${v_mig_suc_log}|awk -F , '{print $1}'`
              if [[ -n "${v_mig_suc_time}" ]];then
                 v_mig_suc_sec=`date -d"${v_mig_suc_time}" +%s 2>/dev/null`
              else
                 v_mig_suc_sec=0
              fi
 
              if [[ ${v_mig_suc_sec} -gt ${v_bef_mig_sec} ]];then
                 break
              else
                 sleep 10 
              fi

   done
   v_mig_to_dn_id=${v_mig_from_dn_id}

done
while true
do
   v_bm_finish=`cat ${cur_dir}/del_s_40.out|wc -l`
   if [[ ${v_bm_finish} -gt 0 ]];then
      break
   else
      sleep 5
   fi
done
 run_check_query "root.test.g_0.d1_*" "${cur_dir}/q_act_d1.out" "100000,100000,100000" 0 "0,0,0" 10000
 run_check_query "root.test.g_0.d2_*" "${cur_dir}/q_act_d2.out" "100000,100000,100000" 0 "0,0,0" 10000

v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
   let fail_flag++
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
clean_env
start_db
pre_and_exec_mig_region

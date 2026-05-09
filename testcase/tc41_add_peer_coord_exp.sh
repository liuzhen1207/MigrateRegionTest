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
copy_wait_timeout_sec=1800
add_region_wait_timeout_sec=300
snapshot_wait_timeout_sec=300
stop_dn_wait_timeout_sec=180
restart_dn_wait_timeout_sec=180
migrate_success_wait_timeout_sec=300
region_stable_rounds=3
function clean_env()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
}

function wait_timeout_check()
{
   local begin_sec=$1
   local timeout_sec=$2
   local wait_desc="$3"
   local cur_sec=`date +%s`
   local elp_sec=$((cur_sec-begin_sec))

   if [[ ${elp_sec} -gt ${timeout_sec} ]];then
      echo "[${SCRIPT_NAME}] timeout waiting for ${wait_desc}, elapsed ${elp_sec}s"
      let fail_flag++
      return 0
   fi

   return 1
}

function check_migrate_cmd()
{
   local mig_out_file=$1

   if grep -Eq "IoTDBSQLException|Exception|^Msg:| has some other region operation procedures in progress" ${mig_out_file};then
      echo "[${SCRIPT_NAME}] migrate command failed:"
      cat ${mig_out_file}
      let fail_flag++
      return 1
   fi

   return 0
}

function refresh_region_info()
{
   local region_id=$1
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${region_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8","$9}'>${cur_dir}/mig_id_info.txt
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${region_id}|[[:space:]]*DataRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/all_dn_id_ip.txt
}

function get_dn_ip_by_id()
{
   local dn_id=$1
   grep "^${dn_id}," ${cur_dir}/all_dn_id_ip.txt|head -1|awk -F ',' '{print $2}'
}

function get_query_ip_excluding()
{
   local exclude_ip=$1
   awk -F ',' -v exclude_ip="${exclude_ip}" '$2 != exclude_ip {print $2; exit}' ${cur_dir}/all_dn_id_ip.txt
}

function get_region_transition_count()
{
   local region_id=$1
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${region_id}|[[:space:]]*DataRegion"|grep -E "Adding|Removing"|wc -l
}

function wait_region_has_dn()
{
   local region_id=$1
   local target_dn_id=$2
   local timeout_sec=$3
   local wait_desc="$4"
   local begin_sec=`date +%s`

   while true
   do
      refresh_region_info ${region_id}
      v_check=`grep "^${target_dn_id}$" ${cur_dir}/mig_region_dn_id.txt|wc -l`
      if [[ ${v_check} -gt 0 ]];then
         return 0
      fi

      if wait_timeout_check ${begin_sec} ${timeout_sec} "${wait_desc}";then
         return 1
      fi
      sleep 2
   done
}

function wait_region_settled()
{
   local region_id=$1
   local expect_replica_num=$2
   local timeout_sec=$3
   local stable_round=$4
   local wait_desc="$5"
   local begin_sec=`date +%s`
   local stable_hit=0

   while true
   do
      refresh_region_info ${region_id}
      v_region_dn_num=`wc -l < ${cur_dir}/mig_region_dn_id.txt`
      v_transition_num=`get_region_transition_count ${region_id}`

      if [[ ${v_region_dn_num} = ${expect_replica_num} && ${v_transition_num} = 0 ]];then
         stable_hit=$((stable_hit+1))
         if [[ ${stable_hit} -ge ${stable_round} ]];then
            return 0
         fi
      else
         stable_hit=0
      fi

      if wait_timeout_check ${begin_sec} ${timeout_sec} "${wait_desc}";then
         return 1
      fi
      sleep 3
   done
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
        v_cp_beg_sec=`date +%s`
        while true
        do
        v_check_cp=`ssh ${u_name}@${line} "sudo ps -ef|grep \"cp -rl\"|grep -v grep|wc -l"`
        if [[ ${v_check_cp} = 0 ]];then
           ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
           break
        else
           if wait_timeout_check ${v_cp_beg_sec} ${copy_wait_timeout_sec} "copy backup data on ${line}";then
              break
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

function pre_and_exec_mig_region()
{
 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_exp.out

  v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep root.test|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  refresh_region_info ${v_mig_id}

local v_mig_to_dn_id=-1
local stage_ok=1
  line=`head -1 ${cur_dir}/mig_id_info.txt`
   if [[ ${line} = "" ]];then
      let fail_flag++
      stage_ok=0
   fi

   if [[ ${stage_ok} = 1 ]];then
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
   fi
   if [[ ${stage_ok} = 1 && ( -z "${v_mig_to_dn_id}" || ${v_mig_to_dn_id} -lt 0 ) ]];then
      echo "[${SCRIPT_NAME}] can not find available target datanode for the first migration"
      let fail_flag++
      stage_ok=0
   fi
   if [[ ${stage_ok} = 1 ]];then
   v_add_coord_dn_id=`grep -v "^${v_mig_from_dn_id}$" ${cur_dir}/mig_region_dn_id.txt|head -1`
   v_add_coord_ip=`get_dn_ip_by_id ${v_add_coord_dn_id}`
   if [[ -z "${v_add_coord_dn_id}" || -z "${v_add_coord_ip}" ]];then
      echo "[${SCRIPT_NAME}] can not infer add coordinator from current region members"
      let fail_flag++
      stage_ok=0
   fi
   fi
   if [[ ${stage_ok} = 1 ]];then
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id};" > ${cur_dir}/mig.out
   if ! check_migrate_cmd ${cur_dir}/mig.out;then
      stage_ok=0
   fi
   fi
   if [[ ${stage_ok} = 1 ]];then
   if ! wait_region_has_dn ${v_mig_id} ${v_mig_to_dn_id} ${add_region_wait_timeout_sec} "region ${v_mig_id} add new peer ${v_mig_to_dn_id}";then
      stage_ok=0
   fi
   fi
   if [[ ${stage_ok} = 1 ]];then
      if [[ ${query_ip} = ${v_add_coord_ip} ]];then
         v_new_query_ip=`get_query_ip_excluding ${v_add_coord_ip}`
         if [[ -n "${v_new_query_ip}" ]];then
            query_ip=${v_new_query_ip}
         fi
      fi
      ssh ${u_name}@${v_add_coord_ip} "sudo ${db_dir}/sbin/stop-datanode.sh"
   fi
# check stop dn pid

if [[ ${stage_ok} = 1 ]];then
v_stop_beg_sec=`date +%s`
while true
do
   v_pid=`ssh ${u_name}@${v_add_coord_ip} "sudo jps|grep -i datanode|wc -l"`
   if [[ ${v_pid} -gt 0 ]];then
      if wait_timeout_check ${v_stop_beg_sec} ${stop_dn_wait_timeout_sec} "datanode ${v_add_coord_ip} stop";then
         stage_ok=0
         break
      fi
      sleep 3
   else
          break
   fi
  
done
fi

if [[ ${stage_ok} = 1 ]];then
   if ! wait_region_settled ${v_mig_id} ${dr_rep_num} ${snapshot_wait_timeout_sec} ${region_stable_rounds} "region ${v_mig_id} settle after stopping add coordinator";then
      stage_ok=0
   fi
fi
# restart stop coord
if [[ ${stage_ok} = 1 ]];then
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
                stage_ok=0
	            break
	         fi
		         sleep 2
		      fi
done
fi
#   v_mig_to_dn_id=${v_mig_from_dn_id}

if [[ ${stage_ok} = 1 ]];then
refresh_region_info ${v_mig_id}
v_mig_to_dn_id=-1
   line=`tail -1 ${cur_dir}/mig_id_info.txt`
   if [[ ${line} = "" ]];then
      let fail_flag++
      stage_ok=0
   fi
fi
if [[ ${stage_ok} = 1 ]];then
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
fi
if [[ ${stage_ok} = 1 && ( -z "${v_mig_to_dn_id}" || ${v_mig_to_dn_id} -lt 0 ) ]];then
   echo "[${SCRIPT_NAME}] can not find available target datanode for the second migration"
   let fail_flag++
   stage_ok=0
fi
if [[ ${stage_ok} = 1 ]];then
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id};" > ${cur_dir}/mig.out
   if ! check_migrate_cmd ${cur_dir}/mig.out;then
      stage_ok=0
   fi
fi
if [[ ${stage_ok} = 1 ]];then
   if ! wait_region_settled ${v_mig_id} ${dr_rep_num} ${migrate_success_wait_timeout_sec} ${region_stable_rounds} "region ${v_mig_id} settle after second migration";then
      stage_ok=0
   fi
fi

if [[ ${stage_ok} = 1 ]];then
   refresh_region_info ${v_mig_id}
   v_check_target=`grep "^${v_mig_to_dn_id}$" ${cur_dir}/mig_region_dn_id.txt|wc -l`
   v_check_source=`grep "^${v_mig_from_dn_id}$" ${cur_dir}/mig_region_dn_id.txt|wc -l`
   v_check_mig_regionid=`wc -l < ${cur_dir}/mig_region_dn_id.txt`
   v_transition_num=`get_region_transition_count ${v_mig_id}`

   if [[ ${v_check_target} = 0 || ${v_check_source} -gt 0 || ${v_check_mig_regionid} != ${dr_rep_num} || ${v_transition_num} -gt 0 ]];then
      let fail_flag++
   fi
fi


 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** align by device;">${cur_dir}/q_act.out
 v_check_res=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out |grep root|wc -l`
 if [[ ${v_check_res} != 0 ]];then
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

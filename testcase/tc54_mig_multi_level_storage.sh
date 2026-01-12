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
first_tier_storage="/data1/iotdb/${v_cur_db}/data/datanode/data"
sec_tier_storage="/data/iotdb/${v_cur_db}/data/datanode/data"
function clean_env()
{
   #clean env
   sh -x ${clean_env_dir}/stop_cluster.sh
   sh -x ${clean_env_dir}/clean_cluster.sh
   sh -x ${clean_env_dir}/reset_conf.sh
   sudo jps|grep -i app|awk '{print "kill -9 "$1}'|sh
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
set_sys_conf ${line} ${db_dir} ".*data|dn_data_dirs=.*" "data|dn_data_dirs=${first_tier_storage};${sec_tier_storage}|g' ${db_dir}"
set_sys_conf ${line} ${db_dir} ".*dn_default_space_usage_thresholds=.*" "dn_default_space_usage_thresholds=0.85;0.85"
set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=5"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
set_sys_conf ${line} ${db_dir} ".*compaction_write_throughput_mb_per_sec=.*" "compaction_write_throughput_mb_per_sec=2"
set_sys_conf ${line} ${db_dir} ".*region_migration_speed_limit_bytes_per_second=.*" "region_migration_speed_limit_bytes_per_second=0"
set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
     if ssh "${u_name}@${line}" "[ -d \"/data1/iotdb/${v_cur_db}\" ]"; then
       ssh ${u_name}@${line} "sudo rm -rf /data1/iotdb/${v_cur_db}/data"
     else
       ssh ${u_name}@${line} "sudo mkdir -p /data1/iotdb/${v_cur_db}" 
     fi
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
   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"

}
function start_bm()
{
   bm_conn_dir1="tc54_1.conf"
   bm_conn_dir2="tc54_2.conf"
   bm_conn_dir3="tc54_3.conf"
   bm_conn_dir4="tc54_4.conf"
   v_time=`date +"%Y_%m_%d_%H_%M_%S"`
   ${bm_dir}/run_tc.sh ${query_ip} ${bm_conn_dir1} ${v_time}_tc${tc_num}_bm1.out &
   ${bm_dir}/run_tc.sh ${query_ip} ${bm_conn_dir2} ${v_time}_tc${tc_num}_bm2.out &
   ${bm_dir}/run_tc.sh ${query_ip} ${bm_conn_dir3} ${v_time}_tc${tc_num}_bm3.out &
   ${bm_dir}/run_tc.sh ${query_ip} ${bm_conn_dir4} ${v_time}_tc${tc_num}_bm4.out &
   sleep 10 
}
function get_regions_info()
{
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "show regions"|grep "Region|"|awk -F '|' '{gsub(" ","");print $2","$9}' >${cur_dir}/region_id_ip.txt
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "show datanodes"|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/dn_id_ip.txt
}
function mig_when_comping()
{
while true
do
   exec 3<${cur_dir}/region_id_ip.txt
   while read line <&3
   do
       v_mig_id=`echo ${line}|awk -F "," '{print $1}'`
       v_mig_from_ip=`echo ${line}|awk -F "," '{print $2}'`
       v_mig_from_id=`grep ${v_mig_from_ip} ${cur_dir}/dn_id_ip.txt |awk -F ',' '{print $1}'`
       ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "show regions"|grep  "^|.* ${v_mig_id}|.*Region"|awk -F "|" '{gsub(" ","");print $9}' >${cur_dir}/mig_source_ip.txt
       exec 4<${cur_dir}/dn_id_ip.txt
       while read line1<&4
       do
           v_line1=`echo ${line1}|awk -F ',' '{print $2}'`
           v_line1_id=`echo ${line1}|awk -F ',' '{print $1}'`
           v_is_source=`grep ${v_line1} ${cur_dir}/mig_source_ip.txt|wc -l`
           if [[ ${v_is_source} = 0 ]];then
              v_mig_to_id=${v_line1_id}
              break
           fi
       done
       ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "migrate region ${v_mig_id} from ${v_mig_from_id} to ${v_mig_to_id};"
       while true
       do
          v_mig_suc=`${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "show regions"|grep "^|.* ${v_mig_id}|.*Region"|grep ${v_mig_from_ip}|wc -l`
          if [[ ${v_mig_suc} = 0 ]];then
             sleep 5
             break
          else
             sleep 5 
          fi
       done
	   v_bm=`jps|grep -i app|wc -l`
	   if [[ ${v_bm} = 0 ]];then
	      break
	   fi
   done
   v_bm=`jps|grep -i app|wc -l`
   if [[ ${v_bm} = 0 ]];then
      break
   fi
done 

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
start_bm
sleep 120
get_regions_info
mig_when_comping

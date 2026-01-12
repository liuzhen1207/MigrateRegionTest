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
query_ip2=`tail -1 ${nodeinfo_dir}/datanode.txt`
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-456 
fail_file="fail.log"
cn_num=3
dn_num=5
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/tc7_test_data
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
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=1"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*" "data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.IoTConsensusV2"
     set_sys_conf ${line} ${db_dir} ".*compaction_schedule_interval_in_ms=.*" "compaction_schedule_interval_in_ms=3600000" 
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
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=1"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*" "data_region_consensus_protocol_class=org.apache.iotdb.consensus.iot.IoTConsensusV2"
     set_sys_conf ${line} ${db_dir} ".*compaction_schedule_interval_in_ms=.*" "compaction_schedule_interval_in_ms=10000" 
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
function stop_dn()
{
   v_stop_dn_ip=$1
   v_query_ip=$2
   ssh ${u_name}@${v_stop_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh"
   while true
   do
      v_pid_num=`ssh ${u_name}@${v_stop_dn_ip} "sudo jps|grep -i datanode|wc -l"`
      v_unknown_num=`${cli_dir}/sbin/start-cli.sh -h ${v_query_ip} -sql_dialect table -e "show datanodes;"|grep "${v_stop_dn_ip}|"|grep -i unknown|wc -l`
      if [[ ${v_pid_num} = 0 ]] && [[ ${v_unknown_num} = 1 ]];then
         break
      else
         sleep 3
      fi
   done 
}
function start_dn()
{
   v_start_dn_ip=$1
   start_sec=`date +%Y_%m_%d_%H_%M_%S`
   ssh ${u_name}@${v_start_dn_ip} "sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/start_${start_sec}.hprof >/dev/null 2>&1 &"
   sleep 2
   while true
   do
      v_running_num=`${cli_dir}/sbin/start-cli.sh -h ${v_start_dn_ip} -sql_dialect table -e "show datanodes;"|grep "${v_start_dn_ip}|"|grep -i running|wc -l`
      if [[ ${v_running_num} = 1 ]];then
         break
      else
         sleep 3
      fi
   done
}

function test()
{
        ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect tree -e "create database root.db;" 
        ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -e "create database db;" 
        ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -e "use db;create table t1(device_id string tag,col int32);"
        for i in {1..30}
        do
           ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect tree -e "insert into root.db.d1(time,col) values(${i},${i});"
           ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -e "insert into db.t1(time,device_id,col) values(${i},'d_${i}',${i});"
#           ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -e "flush;"
        done 
           ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -e "show data regions;" > tmp.out
# get data region info
 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect tree -e 'show data regions'|grep -v system|grep DataRegion|awk -F "|" '{gsub(" ","");print $9","$12}'>tmp1.out
 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -e 'show data regions'|grep -v system|grep DataRegion|awk -F "|" '{gsub(" ","");print $9","$12}'>tmp2.out
#before del query
v_tree_exp=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect tree -e 'select count(col) as count_count_count from root.db.d1'|grep "|  "|awk -F '|'  '{gsub(" ","");print $2}'`
v_table_exp=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -e 'select count(col) as count_count_count from db.t1'|grep "|  "|awk -F '|'  '{gsub(" ","");print $2}'`
#stop dn follower
v_stop_ip=`grep -i Leader ./tmp1.out|awk -F ',' '{print $1}'`
if [[ ${query_ip} = ${v_stop_ip} ]];then
v_query_ip=${query_ip2}
else
v_query_ip=${query_ip}
fi
stop_dn ${v_stop_ip} ${v_query_ip}

# delete 1 rows
${cli_dir}/sbin/start-cli.sh -h ${v_query_ip} -sql_dialect tree -e "delete from root.db.d1.col where time=15;"
start_dn ${v_stop_ip}
v_stop_ip=`grep -i Leader ./tmp2.out|awk -F ',' '{print $1}'`
if [[ ${query_ip} = ${v_stop_ip} ]];then
v_query_ip=${query_ip2}
else
v_query_ip=${query_ip}
fi
stop_dn ${v_stop_ip} ${v_query_ip}

${cli_dir}/sbin/start-cli.sh -h ${v_query_ip} -sql_dialect table -e "delete from db.t1 where time=15;"
start_dn ${v_stop_ip}
sleep 1
v_tree_act=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect tree -e 'select count(col) as count_count_count from root.db.d1'|grep "|  "|awk -F '|'  '{gsub(" ","");print $2}'`
v_table_act=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -e 'select count(col) as count_count_count from db.t1'|grep "|  "|awk -F '|'  '{gsub(" ","");print $2}'`
if [[ ${v_tree_act} -lt ${v_tree_exp} ]] && [[ ${v_table_act} -lt ${v_table_exp} ]];then
echo "Right."
else
let fail_flag++
fi
# stop leader
v_stop_ip=`grep -i leader ./tmp1.out|awk -F ',' '{print $1}'`
if [[ ${query_ip} = ${v_stop_ip} ]];then
v_query_ip=${query_ip2}
else
v_query_ip=${query_ip}
fi
stop_dn ${v_stop_ip} ${v_query_ip}
v_tree_act1=`${cli_dir}/sbin/start-cli.sh -h ${v_query_ip} -sql_dialect tree -e 'select count(col) as count_count_count from root.db.d1'|grep "|  "|awk -F '|'  '{gsub(" ","");print $2}'`
if [[ ${v_tree_act1} != ${v_tree_act} ]];then
let fail_flag++
fi
start_dn ${v_stop_ip}

v_stop_ip=`grep -i leader ./tmp2.out|awk -F ',' '{print $1}'`
if [[ ${query_ip} = ${v_stop_ip} ]];then
v_query_ip=${query_ip2}
else
v_query_ip=${query_ip}
fi
stop_dn ${v_stop_ip} ${v_query_ip}
v_table_act1=`${cli_dir}/sbin/start-cli.sh -h ${v_query_ip} -sql_dialect table -e 'select count(col) as count_count_count from db.t1'|grep "|  "|awk -F '|'  '{gsub(" ","");print $2}'`
if [[ ${v_table_act1} != ${v_table_act} ]];then
let fail_flag++
fi
start_dn ${v_stop_ip}

# write res
test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass" 
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail"
  fi
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

}


clean_env
start_db
test

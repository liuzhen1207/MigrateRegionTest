#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
iotdb_host=`cat ${conf_file}|grep test_ip|awk -F '=' '{print $2}'`
v_cur_db=`cat ${conf_file}|grep v_cur_db|awk -F '=' '{print $2}'`
cli_dir=`cat ${conf_file}|grep client_db_dir|awk -F '=' '{print $2}'`
clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
check_res_dir="${cur_dir}/../check_res"
SCRIPT_NAME=$(basename "$0")
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
query_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`
bm_dir=/data1/benchmark/bm_20241024_714d5b3b
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
cn_num=3
dn_num=5
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/iotv2_mig_data
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
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=1"
 
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
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=1"
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

function run_bm()
{
  test_time=`date +'%Y_%m_%d_%H_%M_%S'`
  bm_conn_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
  bm_num=`echo ${SCRIPT_NAME}|awk -F '_' '{print $1}'`
  out_file="${test_time}_${bm_num}"
  sed -i "s/^HOST=.*/HOST=${iotdb_host}/g" ${bm_dir}/gen_3db_1regionPerDB/conf1/config.properties
  sed -i "s/^HOST=.*/HOST=${iotdb_host}/g" ${bm_dir}/gen_3db_1regionPerDB/conf2/config.properties
  sed -i "s/^HOST=.*/HOST=${iotdb_host}/g" ${bm_dir}/gen_3db_1regionPerDB/conf3/config.properties
  sed -i "s/^HOST=.*/HOST=${iotdb_host}/g" ${bm_dir}/gen_3db_1regionPerDB/conf4/config.properties
  sed -i "s/^HOST=.*/HOST=${iotdb_host}/g" ${bm_dir}/gen_3db_1regionPerDB/conf5_tab/config.properties
  ${bm_dir}/benchmark.sh -cf ${bm_dir}/gen_3db_1regionPerDB/conf1 > ${bm_dir}/${out_file}_1.out
  ${bm_dir}/benchmark.sh -cf ${bm_dir}/gen_3db_1regionPerDB/conf2 > ${bm_dir}/${out_file}_2.out
  ${bm_dir}/benchmark.sh -cf ${bm_dir}/gen_3db_1regionPerDB/conf3 > ${bm_dir}/${out_file}_3.out
  ${bm_dir}/benchmark.sh -cf ${bm_dir}/gen_3db_1regionPerDB/conf4 > ${bm_dir}/${out_file}_4.out
  ${bm_dir}/benchmark.sh -cf ${bm_dir}/gen_3db_1regionPerDB/conf5_tab > ${bm_dir}/${out_file}_5.out
  # wait benchmark finished
  bm_through=`grep -A 1 through  ${bm_dir}/${out_file}_1.out|tail -1 |awk '{print $6}'`

}

function mig_region()
{
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_172),count(s_293),count(s_8),count(s_490),count(s_368),count(s_597),max_time(s_172),max_time(s_293),max_time(s_8),max_time(s_490),max_time(s_368),max_time(s_597) from root.test.g_0.** align by device;">${cur_dir}/q_exp.out
  local v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;"|grep root|head -1|awk -F '|' '{gsub(" ","");print $2}'`
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;"|grep " ${v_mig_id}|[[:space:]]*SchemaRegion"|awk -F '|' '{gsub(" ","");print $8","$9}'>${cur_dir}/mig_id_info.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;"|grep " ${v_mig_id}|[[:space:]]*SchemaRegion"|awk -F '|' '{gsub(" ","");print $8}'>${cur_dir}/mig_region_dn_id.txt
  ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e  'show datanodes'|grep Running|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/all_dn_id.txt
local v_mig_to_dn_id=-1
exec 3<${cur_dir}/mig_id_info.txt
while read line<&3
do
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
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   v_bef_mig_time=`ssh ${u_name}@${v_cn_leader_ip} "date +\"%Y-%m-%d %H:%M:%S\""`
   v_bef_mig_sec=`date -d"${v_bef_mig_time}" +%s`
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_dn_id} TO ${v_mig_to_dn_id};" > ${cur_dir}/mig.out
   sleep 10
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   while true
   do
      ssh ${u_name}@${v_cn_leader_ip} "sudo gunzip ${db_dir}/logs/log-confignode-all*"
      	      v_mig_suc_log=`ssh ${u_name}@${v_cn_leader_ip} "grep \"RegionMigrateProcedure success, region\" ${db_dir}/logs/*confignode*all.log|tail -1"`
	      v_mig_suc_time=`echo ${v_mig_suc_log}|awk -F , '{print $1}'`
	      v_mig_suc_sec=`date -d"${v_mig_suc_time}" +%s`

	      if [[ ${v_mig_suc_sec} -gt ${v_bef_mig_sec} ]];then
		 break
	      else
		 sleep 10 
	      fi

   done
   v_mig_to_dn_id=${v_mig_from_dn_id} 
   
done

   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_172),count(s_293),count(s_8),count(s_490),count(s_368),count(s_597),max_time(s_172),max_time(s_293),max_time(s_8),max_time(s_490),max_time(s_368),max_time(s_597) from root.test.g_0.** align by device;">${cur_dir}/q_act.out
   v_query_is_same=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out|grep root|wc -l`
   if [[ ${v_query_is_same} -gt 0 ]];then
      let fail_flag++
   fi
v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;"|grep " ${v_mig_id}|[[:space:]]*SchemaRegion"|wc -l`
if [[ ${v_check_mig_regionid} != 3 ]];then
   let fail_flag++
fi

#stop dest DN 
v_stop_dn_ip=`awk "NR==2" ${cur_dir}/mig_id_info.txt|awk -F ',' '{print $2}'`
   ssh ${u_name}@${v_stop_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh"
   while true
   do
      if [[ ${query_ip} = ${v_stop_dn_ip} ]];then
         query_ip=`awk "NR==1" ${cur_dir}/mig_id_info.txt|awk -F ',' '{print $2}'`
      fi
      v_unknown_res=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show cluster"|grep -i datanode|grep ${v_stop_dn_ip}|grep -i unknown|wc -l`
      if [[ ${v_unknown_res} -gt 0 ]];then
         break
      else
         sleep 1
      fi
   done
ssh ${u_name}@${v_stop_dn_ip} "sudo gunzip ${db_dir}/logs/log-datanode*"
v_check_ratis_log=`ssh ${u_name}@${v_stop_dn_ip} "grep \"Unexpected gap in segments: binarySearch\" ${db_dir}/logs/*datanode*all*"|wc -l`
if [[ ${v_check_ratis_log} -gt 0 ]];then
let fail_flag++
fi

#restart dn
v_start_time=`date +%s`
ssh ${u_name}@${v_stop_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/dn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"
while true
do
sleep 1
      v_restart_unknown=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show cluster"|grep -i datanode|grep ${v_stop_dn_ip}|grep -i Running|wc -l`
      if [[ ${v_restart_unknown} -gt 0 ]];then
         break
      else
         sleep 1
      fi

done
v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show schema regions;"|grep " ${v_mig_id}|[[:space:]]*SchemaRegion"|wc -l`
if [[ ${v_check_mig_regionid} != 3 ]];then
   let fail_flag++
fi

   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_172),count(s_293),count(s_8),count(s_490),count(s_368),count(s_597),max_time(s_172),max_time(s_293),max_time(s_8),max_time(s_490),max_time(s_368),max_time(s_597) from root.test.g_0.** align by device;">${cur_dir}/q_act.out
   v_query_is_same=`diff ${cur_dir}/q_act.out ${cur_dir}/q_exp.out|grep root|wc -l`
   if [[ ${v_query_is_same} -gt 0 ]];then
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
run_bm
#mig_region

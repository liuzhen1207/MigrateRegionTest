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
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
query_ip2=`head -2 ${nodeinfo_dir}/datanode.txt|tail -1`
# https://jira.infra.timecho.com:8443/browse/TIMECHODB-456 
fail_file="fail.log"
cn_num=3
dn_num=5
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/tree_table_view_IoT_remove
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
set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=1"
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=1"
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
set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=1"
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=1"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=1"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
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
#exec 3<${nodeinfo_dir}/datanode.txt
#while read line<&3
#do
#ssh ${u_name}@${line} "sudo cp -rp ${backup_dir_on_cn_dn_host}/data ${db_dir}/ " &
#done
#exec 3<${nodeinfo_dir}/datanode.txt
#while read line<&3
#do
#        while true
#        do
#        v_check_cp=`ssh ${u_name}@${line} "sudo ps -ef|grep \"cp -rp\"|grep -v grep|wc -l"`
#        if [[ ${v_check_cp} = 0 ]];then
#           ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
#           break
#        else
#           sleep 5
#        fi
#        done
#done
#exec 3<${nodeinfo_dir}/confignode.txt
#while read line<&3
#do
#v_check=`grep ${line} ${nodeinfo_dir}/datanode.txt |wc -l`
#if [[ ${v_check} = 0 ]];then
#ssh ${u_name}@${line} "sudo cp -rp ${backup_dir_on_cn_dn_host}/data ${db_dir}/ "
#ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
#fi
#done

   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"

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

function ins_data()
{

for i in {1..5}
do
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "create database root.db${i};create aligned timeseries root.db${i}.t1(text TEXT ,grade int32 ,male boolean ,likething string ,money double ,rate float ,age int64 ,movie blob ,birthday date ,run timestamp );insert into root.db${i}.t1(time,text,grade,male,likething,money,rate,age,movie,birthday,run) values(10000,'expensive',1,false,'calculate',1.23,2.1,21,X'1234','2024-12-01',2021-12-01 13:14:15);"
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "delete from root.db${i}.t1.*;"
done   
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "select text,grade,male,likething,money,rate,age,movie,birthday,run from root.**;" >${cur_dir}/q_act.out

}

function remove_datanode()
{
	rm_dn_ip=$1
	exec_rm_ip=$2
        rm_flag="success"
        v_rm_datanode_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes;"|grep ${rm_dn_ip}|awk -F '|' '{gsub(" ","");print $2}'`
        v_rm_res=`ssh ${u_name}@${exec_rm_ip} "sudo ${db_dir}/sbin/start-cli.sh -h ${query_ip} -e \"remove datanode ${v_rm_datanode_id}\""`
        v_rm_succ=`echo "${v_rm_res}"|grep "successfully"|wc -l`
        if [[ ${v_rm_succ} = 0 ]];then
           let fail_flag++
        fi
        sleep 10
        # check remove result
        while true
        do
           v_jps=`ssh ${u_name}@${rm_dn_ip} "sudo jps|grep -i datanode|wc -l"`
           v_removing_status=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes;"|grep "${rm_dn_ip}|"|grep -i removing|wc -l`
           if [[ ${v_jps} = 0 ]];then
              echo "${rm_dn_ip}," >> ${cur_dir}/ignore_dn_list.txt
              break
           elif [[ ${v_removing_status} = 1 ]];then
              sleep 5
           else
#              let fail_flag++
#              return 1
               sleep 5
           fi
        done
}


function exec_remove_on_cn()
{
>${cur_dir}/ignore_dn_list.txt
last_dn_ip=`tail -1 ${nodeinfo_dir}/datanode.txt`
last_dn_ip2=`tail -2 ${nodeinfo_dir}/datanode.txt|head -1`
remove_datanode ${last_dn_ip} ${last_dn_ip2}
remove_datanode ${last_dn_ip2} ${last_dn_ip2}
v_dn_num=`cat ${nodeinfo_dir}/datanode.txt|wc -l`
v_head_dn_num=$((v_dn_num-2))
head -n ${v_head_dn_num} ${nodeinfo_dir}/datanode.txt >${cur_dir}/datanode.txt
#check data
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "select text,grade,male,likething,money,rate,age,movie,birthday,run from root.**;" >${cur_dir}/q_exp.out
v_diff=`diff ${cur_dir}/q_exp.out ${cur_dir}/q_act.out|grep root|wc -l`
if [[ ${v_diff} -gt 0 ]];then
let fail_flag++
fi
# restart iotdb check data
python3.6 restart_iotdb.py ${cur_dir}/datanode.txt

#check data
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "select text,grade,male,likething,money,rate,age,movie,birthday,run from root.**;" >${cur_dir}/q_exp.out
v_diff=`diff ${cur_dir}/q_exp.out ${cur_dir}/q_act.out|grep root|wc -l`
if [[ ${v_diff} -gt 0 ]];then
let fail_flag++
fi
#check data
${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "select text,grade,male,likething,money,rate,age,movie,birthday,run from root.**;" >${cur_dir}/q_exp.out
v_diff=`diff ${cur_dir}/q_exp.out ${cur_dir}/q_act.out|grep root|wc -l`
if [[ ${v_diff} -gt 0 ]];then
let fail_flag++
fi

check_npe ${SCRIPT_NAME}

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
ins_data
exec_remove_on_cn

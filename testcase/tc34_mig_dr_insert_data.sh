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
bm_conn_version=`cat ${conf_file}|grep bm_conn_version|awk -F '=' '{print $2}'`
bm_dir=/data1/benchmark/bm_20251220_38c839b_${bm_conn_version}
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
bm_conn_pw=`cat ${conf_file}|grep bm_conn_pw|awk -F '=' '{print $2}'`
bm_conf_name=tc34_conf
bm_conf="${cur_dir}/../bm_conf_backup/${bm_conn_version}/${bm_conf_name}"
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
function start_bm()
{

    # 1. 变量定义：路径拼接更清晰，命名规范
    local bm_conf_dir1="${bm_dir}/${bm_conf_name}/"
    local bm_conf_file1="${bm_dir}/${bm_conf_name}/config.properties"
    time_stamp=$(date +"%Y_%m_%d_%H_%M_%S")  # 命名更直观
    local target_dir="${bm_dir}/${bm_conf_name}"    # 提取目标目录，减少重复拼接
    local ret_code=0  # 局部返回码，避免污染全局

    # 2. 前置校验：核心变量非空（避免后续操作无意义）
    if [[ -z "$bm_dir" || -z "$bm_conf_name" ]]; then
        echo "ERROR: bm_dir or bm_conf_name is empty!"
        let fail_flag++
        return 1
    fi

    # 3. 检查配置文件是否存在
    if [[ -f "$bm_conf_file1" ]]; then
        # 替换密码：变量加双引号，检查 sed 执行结果
        sed -i "s/^USERNAME=.*/USERNAME=kevin/g" "$bm_conf_file1"
        sed -i "s/^PASSWORD=.*/PASSWORD=TimechoDB@2021/g" "$bm_conf_file1"
        ret_code=$?
        if [[ $ret_code -ne 0 ]]; then
            echo "ERROR: Failed to replace password in $bm_conf_file1"
            let fail_flag++
            return $ret_code
        fi
            sed -i "s/^HOST=.*/HOST=${query_ip}/g" "$bm_conf_file1"

    else
        # 4. 配置文件不存在：删除目录（先判断存在）
        if [[ -e "$target_dir" ]]; then
            rm -rf "$target_dir"
            if [[ $? -ne 0 ]]; then
                echo "ERROR: Failed to delete $target_dir"
                let fail_flag++
                return 1
            fi
        fi

        # 5. 拷贝配置：变量加双引号，检查拷贝结果
        if [[ -n "$bm_conf" ]]; then
            cp -rp "$bm_conf" "$bm_dir"
            ret_code=$?
            if [[ $ret_code -ne 0 ]]; then
                echo "ERROR: Failed to copy $bm_conf to $bm_dir"
                let fail_flag++
                return $ret_code
            fi

            # 6. 拷贝后重新检查配置文件（核心修复：补上逻辑漏洞）
            if [[ ! -f "$bm_conf_file1" ]]; then
                echo "ERROR: Config files $bm_conf_file1 still missing after copy!"
                let fail_flag++
                return 1
            fi

            # 拷贝后重新替换密码（避免配置文件是新的，密码未替换）
            sed -i "s/^USERNAME=.*/USERNAME=kevin/g" "$bm_conf_file1"
            sed -i "s/^PASSWORD=.*/PASSWORD=TimechoDB@2021/g" "$bm_conf_file1"
            sed -i "s/^HOST=.*/HOST=${query_ip}/g" "$bm_conf_file1"
        else
            echo "ERROR: bm_conf is empty, cannot copy config!"
            let fail_flag++
            return 1  # 修复：失败返回非 0
        fi
    fi

    # 7. 执行 benchmark 脚本：变量加双引号，检查脚本是否可执行
    local benchmark_script="${bm_dir}/benchmark.sh"
    if [[ ! -x "$benchmark_script" ]]; then
        echo "ERROR: $benchmark_script is not executable!"
        let fail_flag++
        return 1
    fi

    # 输出日志加双引号，避免空格/特殊字符解析错误
nohup "$benchmark_script" -cf "$bm_conf_dir1" >"${bm_dir}/${time_stamp}_tc${tc_num}_bm1.out" 2>&1 &
    ret_code=$?
    if [[ $ret_code -ne 0 ]]; then
        echo "ERROR: benchmark.sh bm1 execution failed!"
        let fail_flag++
        # 不直接返回，继续执行 bm2，或根据需求调整
    fi

    sleep 10
    return 0  # 全部执行完成返回成功
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
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "create user kevin 'TimechoDB@2021';"
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "grant all ON root.** TO USER kevin WITH GRANT OPTION;"
   sleep 2
   if [[ ${v_del_flag} -gt 0 ]];then
      echo "have been executed delete timeseries;"
   else 
#      ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "delete from root.test.g_0.*.s_40;">${cur_dir}/del_s_40.out &
# start_bm
     start_bm 
      let v_del_flag++
   fi
for v_f_cn_l in  {1..60}
do
   v_cn_leader_ip=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F '|' '{gsub(" ","");print $4}'`
   if [ -n "${v_cn_leader_ip}" ]; then
      echo "cn leader : ${v_cn_leader_ip}"
      break
   else
      sleep 1
   fi 
done
if [ -n "${v_cn_leader_ip}" ]; then
# 初始化连续v_mig_status_num=0的计数器
local count_zero_status=0
# 定义连续3次为退出阈值
local MAX_ZERO_COUNT=3
   while true
   do
      ssh ${u_name}@${v_cn_leader_ip} "sudo gunzip ${db_dir}/logs/log-confignode-all*"
              v_mig_suc_log=`ssh ${u_name}@${v_cn_leader_ip} "grep \"\[MigrateRegion\] success\" ${db_dir}/logs/*confignode*all.log|tail -1"`
              v_mig_suc_time=`echo ${v_mig_suc_log}|awk -F , '{print $1}'`
#              v_mig_suc_sec=`date -d"${v_mig_suc_time}" +%s`
              v_mig_suc_sec=$(date -d"${v_mig_suc_time}" +%s 2>/dev/null || echo 0)  # 容错：时间解析失败时赋值0
    # 2. 获取迁移状态数量（Adding/Removing的region数）
    v_mig_status_num=$(${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions;" | egrep "Adding|Removing" | wc -l)
    
    # 3. 核心判断：满足任一条件则退出循环
    ## 条件1：迁移成功时间戳大于基准时间
    if [[ ${v_mig_suc_sec} -gt ${v_bef_mig_sec} ]]; then
        echo "满足条件：v_mig_suc_sec(${v_mig_suc_sec}) > v_bef_mig_sec(${v_bef_mig_sec})，退出循环"
        break
    fi
    
    ## 条件2：连续3次v_mig_status_num=0
    # 重置/累加计数器
    if [[ ${v_mig_status_num} -eq 0 ]]; then
        count_zero_status=$((count_zero_status + 1))
        echo "当前v_mig_status_num=0，连续计数：${count_zero_status}/${MAX_ZERO_COUNT}"
    else
        count_zero_status=0  # 非0则重置计数器
        echo "当前v_mig_status_num=${v_mig_status_num}，重置连续0计数"
    fi
    
    # 检查是否达到连续3次0
    if [[ ${count_zero_status} -ge ${MAX_ZERO_COUNT} ]]; then
        echo "满足条件：连续${MAX_ZERO_COUNT}次v_mig_status_num=0，退出循环"
        break
    fi
    
    # 未满足条件，休眠10秒后继续循环
    sleep 10
   done
   v_mig_to_dn_id=${v_mig_from_dn_id}
else
   let fail_flag++
   echo "cn leader is empty."
fi
done
while true
do
   v_bm_finish=`sudo jps|grep -i app|wc -l`
   if [[ ${v_bm_finish} -gt 0 ]];then
      sleep 10 
   else
      break 
   fi
done

 ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8),max_time(s_49),max_time(s_36),max_time(s_9) from root.** where time>=1990-1-1T08:00:00+08:00 align by device;">${cur_dir}/q_act.out
  v_check_res=`cat ${cur_dir}/q_act.out|grep "There is not enough memory to execute current fragment instance"|wc -l`

 if [[ ${v_check_res} = 0 ]];then
    v_exp_num=`grep root.test ${cur_dir}/q_act.out|awk -F '|' '{gsub(" ","");print $3","$4","$5","$6","$7}'|grep "100000,100000,100000,100000,100000"|wc -l`
    if [[ ${v_exp_num} != 20000 ]];then
       let fail_flag++
    fi
 fi

${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 36000 -e "select count(s_12),count(s_23),count(s_8),count(s_40),count(s_36),count(s_9),max_time(s_17),max_time(s_29),max_time(s_8) from root.** where time>=1990-1-1T08:00:00+08:00 align by device;">${cur_dir}/q_act2.out
v_check_res=`cat ${cur_dir}/q_act2.out|grep root|awk -F "|" '{gsub(" ","");print $5","$6","$7}'|grep "100000,100000,100000" |wc -l`
if [[ ${v_check_res} != 20000 ]];then
let fail_flag++
fi
 v_check_res=`cat ${cur_dir}/q_act2.out|grep root|awk -F "|" '{gsub(" ","");print $5","$6","$7}'|grep "0,0,0" |wc -l`
 if [[ ${v_check_res} != 60000 ]];then
    let fail_flag++
 fi


v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
   let fail_flag++
fi

#check NPE
exec 3<${nodeinfo_dir}/datanode.txt
while read line <&3
do
ssh ${u_name}@${line} "sudo gunzip ${db_dir}/logs/log-datanode-all*"
v_npe=`ssh ${u_name}@${line} "grep -i NullPointer ${db_dir}/logs/*datanode*all*|wc -l"`
if [[ ${v_npe} -gt 0 ]];then
let fail_flag++
fi
done
exec 3<${nodeinfo_dir}/confignode.txt
while read line <&3
do
ssh ${u_name}@${line} "sudo gunzip ${db_dir}/logs/log-confignode-all*"
v_npe=`ssh ${u_name}@${line} "grep -i NullPointer ${db_dir}/logs/*confignode*all*|wc -l"`
if [[ ${v_npe} -gt 0 ]];then
let fail_flag++
fi
done

test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))
tc_res=true

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
     rm -rf "${bm_dir}/${time_stamp}_tc${tc_num}_bm1.out"
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
  fi
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

 
} 
clean_env
start_db
pre_and_exec_mig_region

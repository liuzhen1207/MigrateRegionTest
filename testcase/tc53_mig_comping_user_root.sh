#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_sys_admin=root
db_sec_admin=security_admin
ssl_str=""
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
bm_conn_pw=`cat ${conf_file}|grep bm_conn_pw|awk -F '=' '{print $2}'`
bm_dir=/data1/benchmark/bm_20240320_76af1a40
bm_conf_name=tc53_conf
bm_conf="${cur_dir}/../bm_conf_backup/v13/${bm_conf_name}"
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
set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=2"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*compaction_write_throughput_mb_per_sec=.*" "compaction_write_throughput_mb_per_sec=2"
set_sys_conf ${line} ${db_dir} ".*region_migration_speed_limit_bytes_per_second=.*" "region_migration_speed_limit_bytes_per_second=0"
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
   sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"

}
function start_bm()
{
#   bm_conf_dir1="${bm_conf_name}/bm1"
#   bm_conf_file1="${bm_dir}/${bm_conf_name}/bm1/config.properties"
#   bm_conf_file2="${bm_dir}/${bm_conf_name}/bm2/config.properties"
#   bm_conf_dir2="${bm_conf_name}/bm2"
#   v_time=`date +"%Y_%m_%d_%H_%M_%S"`
#   # check config is exist?
#if [[ -f "$bm_conf_file1" ]] && [[ -f "$bm_conf_file2" ]]; then
#  # set password
#  sed -i "s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/g" $bm_conf_file1
#  sed -i "s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/g" $bm_conf_file2
#elif [ -n "$bm_dir" ] && [ -n "$bm_conf_name" ]; then
#  rm -rf "${bm_dir}/${bm_conf_name}"
#  if  [ -n "$bm_conf" ];then
#  cp -rp ${bm_conf} ${bm_dir}
#  else
#    let fail_flag++
#    return 0
#  fi
#fi
#
#   ${bm_dir}/benchmark.sh -cf ${bm_conf_dir1} >${bm_dir}/${v_time}_tc${tc_num}_bm1.out
#   ${bm_dir}/benchmark.sh -cf ${bm_conf_dir2} >${bm_dir}/${v_time}_tc${tc_num}_bm2.out
#   sleep 10 
# 先定义全局变量默认值（避免未定义报错）

    # 1. 变量定义：路径拼接更清晰，命名规范
    local bm_conf_dir1="${bm_dir}/${bm_conf_name}/bm1"
    local bm_conf_dir2="${bm_dir}/${bm_conf_name}/bm2"
    local bm_conf_file1="${bm_dir}/${bm_conf_name}/bm1/config.properties"
    local bm_conf_file2="${bm_dir}/${bm_conf_name}/bm2/config.properties"
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
    if [[ -f "$bm_conf_file1" && -f "$bm_conf_file2" ]]; then
        # 替换密码：变量加双引号，检查 sed 执行结果
        sed -i "s/^USERNAME=.*/USERNAME=root/g" "$bm_conf_file1"
        sed -i "s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/g" "$bm_conf_file1"
        ret_code=$?
        if [[ $ret_code -ne 0 ]]; then
            echo "ERROR: Failed to replace password in $bm_conf_file1"
            let fail_flag++
            return $ret_code
        fi
        sed -i "s/^USERNAME=.*/USERNAME=root/g" "$bm_conf_file2"

        sed -i "s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/g" "$bm_conf_file2"
        ret_code=$?
        if [[ $ret_code -ne 0 ]]; then
            echo "ERROR: Failed to replace password in $bm_conf_file2"
            let fail_flag++
            return $ret_code
        fi
            sed -i "s/^HOST=.*/HOST=${query_ip}/g" "$bm_conf_file1"
            sed -i "s/^HOST=.*/HOST=${query_ip}/g" "$bm_conf_file2"

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
            if [[ ! -f "$bm_conf_file1" || ! -f "$bm_conf_file2" ]]; then
                echo "ERROR: Config files $bm_conf_file1/$bm_conf_file2 still missing after copy!"
                let fail_flag++
                return 1
            fi

            # 拷贝后重新替换密码（避免配置文件是新的，密码未替换）
            sed -i "s/^USERNAME=.*/USERNAME=root/g" "$bm_conf_file1"
            sed -i "s/^USERNAME=.*/USERNAME=root/g" "$bm_conf_file2"
            sed -i "s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/g" "$bm_conf_file1"
            sed -i "s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/g" "$bm_conf_file2"
            sed -i "s/^HOST=.*/HOST=${query_ip}/g" "$bm_conf_file1"
            sed -i "s/^HOST=.*/HOST=${query_ip}/g" "$bm_conf_file2"
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
nohup "$benchmark_script" -cf "$bm_conf_dir2" >"${bm_dir}/${time_stamp}_tc${tc_num}_bm2.out" 2>&1 &
    ret_code=$?
    if [[ $ret_code -ne 0 ]]; then
        echo "ERROR: benchmark.sh bm2 execution failed!"
        let fail_flag++
    fi

    sleep 10
#    return 0  # 全部执行完成返回成功
}
function wait_sync_done()
{
local max_wait_time=$1
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "flush;">${cur_dir}/tmp.out
check_res "success" 1 "${SCRIPT_NAME}"
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;">${cur_dir}/tmp.out
   cat ${cur_dir}/tmp.out |grep Running|awk -F "|" '{gsub(" ","");print $4}'>${cur_dir}/tmp1.out
   mv ${cur_dir}/tmp1.out ${cur_dir}/tmp.out
   exec 3<${cur_dir}/tmp.out
   while read line<&3
   do
   while true
   do
   ssh ${u_name}@${line} "grep \"create a new\" ${db_dir}/logs/log_datanode_all.log|grep root.test">${cur_dir}/tmp1.out
   ssh ${u_name}@${line} "grep \"create a new\" ${db_dir}/logs/log_datanode_all.log|grep test_g_0">${cur_dir}/tmp2.out
   last_time_str1=$(tail -n 1 "${cur_dir}/tmp1.out" | awk -F',' '{print $1}')
   last_time_str2=$(tail -n 1 "${cur_dir}/tmp2.out" | awk -F',' '{print $1}')
   last_timestamp1=$(date -d "$last_time_str1" +%s 2>/dev/null)
   last_timestamp2=$(date -d "$last_time_str2" +%s 2>/dev/null)
   if [[ ${last_timestamp1} -gt ${last_timestamp2} ]];then
      last_timestamp=${last_timestamp1}
   else
      last_timestamp=${last_timestamp2}
   fi
current_timestamp=$(date +%s)

# 计算时间差（秒）
time_diff=$((current_timestamp - last_timestamp))
# 判断是否超过1分钟（120秒）
if [ $time_diff -gt ${max_wait_time} ]; then
    echo "最后一条日志距离现在已超过1分钟（${time_diff}秒）"
    break
else
    v_sleep=$((max_wait_time-time_diff+1))
    sleep ${v_sleep}
#    echo "最后一条日志距离现在未超过1分钟（${time_diff}秒）"
fi
   done
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

function check_data_consistent()
{
wait_sync_done 180
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;">${cur_dir}/tmp.out
   cat ${cur_dir}/tmp.out |grep Running|awk -F "|" '{gsub(" ","");print $4}'>${cur_dir}/tmp1.out
   mv ${cur_dir}/tmp1.out ${cur_dir}/tmp.out
   sql1="select count(s_0) from root.test.g_0.** align by device;"
   # all online
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -timeout 3600 -e "${sql1}" >${cur_dir}/q_all_online_tree.out
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
      # restart
      v_start_time=`date +%s`
      ssh ${u_name}@${line} "source /etc/profile;cd ${db_dir};sudo ./sbin/start-datanode.sh -H ${db_dir}/dn_${v_start_time}_heapdump.hprof > /dev/null 2>&1 &"
      sleep 5
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

function mig_when_comping()
{
while true
do
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "show data regions"|grep root.test|awk -F '|' '{gsub(" ","");print $9}'>${cur_dir}/dataregion_ip.txt
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "show datanodes"|grep Running|awk -F '|' '{gsub(" ","");print $2","$4}'>${cur_dir}/dn_id_ip.txt
   v_mig_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "show data regions"|grep root.test|awk -F '|' '{gsub(" ","");print $2}'|head -1`
   exec 3<${cur_dir}/dataregion_ip.txt
   while read line <&3
   do
     v_comp=`ssh ${u_name}@${line} "find ${db_dir}/data -name *compaction.log|wc -l"` 
     if [[ ${v_comp} -gt 0 ]];then
       v_mig_from_id=`grep ${line} ${cur_dir}/dn_id_ip.txt |awk -F ',' '{print $1}'`
       v_another_dn_ip=`cat ${cur_dir}/dataregion_ip.txt|grep -v ${line}`
       v_mig_to_id=`cat ${cur_dir}/dn_id_ip.txt|grep -v ${line}|grep -v ${v_another_dn_ip}|head -1|awk -F ',' '{print $1}'` 
       v_mig_to_ip=`cat ${cur_dir}/dn_id_ip.txt|grep -v ${line}|grep -v ${v_another_dn_ip}|head -1|awk -F ',' '{print $2}'`
       ${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "migrate region ${v_mig_id} from ${v_mig_from_id} to ${v_mig_to_id};"
       while true
       do
          v_mig_suc=`${cli_dir}/sbin/start-cli.sh -h ${query_ip}  -e "show data regions"|grep root.test|grep ${line}|wc -l`
          if [[ ${v_mig_suc} = 0 ]];then
             break
          else
             sleep 5
          fi
       done
       break 
     fi
   done
   v_bm=`sudo jps|grep -i app|wc -l`
   if [[ ${v_bm} = 0 ]];then
      break
   fi
done 
v_check_mig_regionid=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show data regions;"|grep " ${v_mig_id}|[[:space:]]*DataRegion"|wc -l`
if [[ ${v_check_mig_regionid} != ${dr_rep_num} ]];then
    let fail_flag++
fi

check_data_consistent
check_npe "${SCRIPT_NAME}"
test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))
tc_res=true

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass" >>"${res_file}"
     rm -rf "${bm_dir}/${time_stamp}_tc${tc_num}_bm1.out"
     rm -rf "${bm_dir}/${time_stamp}_tc${tc_num}_bm2.out"
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail" >>"${res_file}"
  fi
${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

 
} 
clean_env
start_db
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "create user kevin 'TimechoDB@2021';"
   ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "grant all ON root.** TO USER kevin WITH GRANT OPTION;"

start_bm
mig_when_comping

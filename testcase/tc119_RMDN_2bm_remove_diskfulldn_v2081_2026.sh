#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
db_sys_admin=root
db_sec_admin=root
res_root_pw=TimechoDB@2021
db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
iotdb_host=`cat ${conf_file}|grep test_ip|awk -F '=' '{print $2}'`
v_cur_db=`cat ${conf_file}|grep v_cur_db|awk -F '=' '{print $2}'`
cli_dir=`cat ${conf_file}|grep client_db_dir|awk -F '=' '{print $2}'`
bm_conn_pw=`cat ${conf_file}|grep '^bm_conn_pw='|awk -F '=' '{print $2}'`
ssl_str=""
clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
check_res_dir="${cur_dir}/../check_res"
SCRIPT_NAME=$(basename "$0")
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
query_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
remove_dn_ip=`tail -1 ${nodeinfo_dir}/datanode.txt`
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
FILL_FILE="${db_dir}/fill_disk.tmp"
FILL_PID_FILE="${db_dir}/fill_disk.pid"
START_DB_TIMEOUT=${START_DB_TIMEOUT:-600}
bm_pid1=""
bm_pid2=""

# Stop a disk filler before unlinking its output file.  Besides the pid file,
# scan /proc so a writer to an already deleted fill_disk.tmp can still be found.
function stop_disk_filler()
{
   local v_ip=${1:-${remove_dn_ip}}
   if [[ -z ${v_ip} ]];then
      echo "Cannot clean disk filler: DataNode IP is empty."
      return 1
   fi

   ssh "${u_name}@${v_ip}" "sudo bash -s -- '${FILL_FILE}' '${FILL_PID_FILE}'" <<'REMOTE_CLEANUP'
fill_file=$1
pid_file=$2
candidates=""

add_candidate()
{
   case " ${candidates} " in
      *" $1 "*) ;;
      *) candidates="${candidates} $1" ;;
   esac
}

owns_fill_file()
{
   pid=$1
   [[ -d /proc/${pid} ]] || return 1

   for fd in /proc/${pid}/fd/*;do
      target=$(readlink "${fd}" 2>/dev/null || true)
      if [[ ${target} = "${fill_file}" || ${target} = "${fill_file} (deleted)" ]];then
         return 0
      fi
   done

   cmdline=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)
   [[ ${cmdline} = *"of=${fill_file}"* ]]
}

if [[ -s ${pid_file} ]];then
   pid=$(cat "${pid_file}" 2>/dev/null)
   [[ ${pid} =~ ^[0-9]+$ ]] && add_candidate "${pid}"
fi

for proc_dir in /proc/[0-9]*;do
   pid=${proc_dir#/proc/}
   for fd in "${proc_dir}"/fd/*;do
      target=$(readlink "${fd}" 2>/dev/null || true)
      if [[ ${target} = "${fill_file}" || ${target} = "${fill_file} (deleted)" ]];then
         add_candidate "${pid}"
         break
      fi
   done
done

live_pids=""
for pid in ${candidates};do
   if owns_fill_file "${pid}";then
      echo "Found stale disk filler pid=${pid}: $(tr '\0' ' ' < /proc/${pid}/cmdline 2>/dev/null)"
      live_pids="${live_pids} ${pid}"
   fi
done

if [[ -n ${live_pids} ]];then
   kill -TERM ${live_pids} 2>/dev/null || true
   for ((i=0; i<30; i++));do
      still_running=""
      for pid in ${live_pids};do
         owns_fill_file "${pid}" && still_running="${still_running} ${pid}"
      done
      [[ -z ${still_running} ]] && break
      sleep 1
   done

   if [[ -n ${still_running} ]];then
      echo "Disk filler did not stop after SIGTERM; sending SIGKILL:${still_running}"
      kill -KILL ${still_running} 2>/dev/null || true
      for ((i=0; i<10; i++));do
         remaining=""
         for pid in ${still_running};do
            owns_fill_file "${pid}" && remaining="${remaining} ${pid}"
         done
         [[ -z ${remaining} ]] && break
         sleep 1
      done
      if [[ -n ${remaining} ]];then
         echo "ERROR: disk filler is still holding ${fill_file}:${remaining}"
         exit 1
      fi
   fi
fi

rm -f "${fill_file}" "${pid_file}"
REMOTE_CLEANUP
}

function cleanup_on_exit()
{
   local exit_code=$?
   trap - EXIT INT TERM

   for pid in "${bm_pid1:-}" "${bm_pid2:-}";do
      if [[ ${pid} =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null;then
         kill "${pid}" 2>/dev/null || true
         wait "${pid}" 2>/dev/null || true
      fi
   done
   stop_disk_filler "${remove_dn_ip}" || true
   exit "${exit_code}"
}

trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

function clean_env()
{
   # A previous interrupted run may still be writing an unlinked fill file.
   # Do this before clean_cluster removes any path under db_dir.
   if ! stop_disk_filler "${remove_dn_ip}";then
      echo "Failed to stop stale disk filler on ${remove_dn_ip}; abort cleanup."
      return 1
   fi
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
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=10"
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
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=10"
#if [[ ${line} = ${remove_dn_ip} ]];then
#v_disk_value=$(ssh ${u_name}@${line} "df -P \"${db_dir}\" | awk 'NR==2{if(\$2>0) printf \"%.2f\n\", (\$4/\$2); else print \"0.00\"}'")
#set_sys_conf ${line} ${db_dir} ".*disk_space_warning_threshold=.*" "disk_space_warning_threshold=${v_disk_value}"
#fi
  done
 
}

function start_db()
{
   if ! stop_disk_filler "${remove_dn_ip}";then
      echo "Failed to stop stale disk filler on ${remove_dn_ip}; abort startup."
      let fail_flag++
      return 1
   fi
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

   timeout --signal=TERM --kill-after=30s "${START_DB_TIMEOUT}s" \
      sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"
   start_rc=$?
   if [[ ${start_rc} -ne 0 ]];then
      let fail_flag++
      if [[ ${start_rc} -eq 124 || ${start_rc} -eq 137 ]];then
         echo "Cluster startup timed out after ${START_DB_TIMEOUT}s."
      else
         echo "Cluster startup failed, exit code: ${start_rc}."
      fi
      ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show cluster;" || true
      return 1
   fi

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
         sleep 10
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
function wait_rm_finish()
{
local v_rm_ip=$1
local max_wait_time=$2
local t1=`date +%s`
  while true
   do
       ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;">${cur_dir}/tmp.out
       v_rm_succ=`cat ${cur_dir}/tmp.out |grep "${v_rm_ip}|"|wc -l`
       v_rm_status=`cat ${cur_dir}/tmp.out |grep "${v_rm_ip}|"|awk -F "|" '{gsub(" ","");print $3}'`
       if [[ ${v_rm_succ} -gt 0 ]] && [[ ${v_rm_status} != Running ]];then
          sleep 1
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
function wait_sync_done()
{
local max_wait_time=$1
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "flush;">${cur_dir}/tmp.out
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
function check_data_consistent()
{
wait_sync_done 120
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;">${cur_dir}/tmp.out
   cat ${cur_dir}/tmp.out |grep Running|awk -F "|" '{gsub(" ","");print $4}'>${cur_dir}/tmp1.out
   mv ${cur_dir}/tmp1.out ${cur_dir}/tmp.out
   sql1="select count(s_0) from root.test.g_0.** align by device;" 
   # all online
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip}  -timeout 3600 -e "${sql1}" >${cur_dir}/q_all_online_tree.out 
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
function check_stop()
{
   v_ip=$1
   v_query_ip=$2
v_start_time=`date +%s`
      while true
      do
      v_stop_ok1=`${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${v_query_ip}  -timeout 3600 -e "show datanodes;"|grep "${v_ip}|"|grep Unknown|wc -l`
      v_rm_ok=`${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${v_query_ip}  -timeout 3600 -e "show datanodes;"|grep "${v_ip}|"|wc -l`
      v_stop_ok=$((v_stop_ok1+v_rm_ok))
      v_jps_ok=`ssh ${u_name}@${v_ip} "sudo jps"|grep DataNode|wc -l`
      if [[ ( ${v_stop_ok} -gt 0 || ${v_rm_ok} -eq 0 ) && ${v_jps_ok} -eq 0 ]]; then 
         break
      else
         sleep 1
      fi
      v_cur_time=`date +%s`
      v_elp_time=$((v_cur_time-v_start_time))
      if [[ ${v_elp_time} -gt 120 ]];then
         let fail_flag++
         echo "stop ${line} failed."
         return
      fi
      done

}

function remove_dn()
{
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;"|grep "${remove_dn_ip}|">${cur_dir}/tmp.out
   v_rm_id=`cat ${cur_dir}/tmp.out |tail -1|awk -F "|" '{gsub(" ","");print $2}'`
   v_rm_ip=`cat ${cur_dir}/tmp.out |tail -1|awk -F "|" '{gsub(" ","");print $4}'`

#start 2bm
   v_t=`date "+%Y_%m_%d_%H_%M_%S"`
   v_host=`awk '{printf "%s%s", (NR==1?"":","), $0}' ${nodeinfo_dir}/datanode.txt`
   bm_res1="${bm_dir}/${v_t}_bm1.out"
   bm_res2="${bm_dir}/${v_t}_bm2.out"
   sed -i "s/^HOST=.*/HOST=${v_host}/g" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties
   sed -i "s/^USERNAME=.*/USERNAME=${db_sys_admin}/; s/^PASSWORD=.*/PASSWORD=${bm_conn_pw}/" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties
   sed -i "s/LOOP=.*/LOOP=100000/g" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties
   nohup sh -x ${bm_dir}/benchmark.sh -cf ${bm_dir}/lt_10type_user_no_ssl/conf1 >"${bm_res1}" 2>&1 &
   bm_pid1=$!
   nohup sh -x ${bm_dir}/benchmark.sh -cf ${bm_dir}/lt_10type_user_no_ssl/conf2 >"${bm_res2}" 2>&1 &
   bm_pid2=$!
   sleep 60

if ! kill -0 ${bm_pid1} 2>/dev/null || ! kill -0 ${bm_pid2} 2>/dev/null \
   || grep -Eq "Authentication failed|Account is blocked|Failed to get database|IoTDBConnectionException" "${bm_res1}" "${bm_res2}";then
   echo "Benchmark failed to start; skip disk filling and DataNode removal."
   tail -n 50 "${bm_res1}" "${bm_res2}"
   kill ${bm_pid1} ${bm_pid2} 2>/dev/null || true
   let fail_flag++
   let rm_fail_flag++
else
RESERVE_SPACE=$((5000 * 1024 * 1024))  # 预留5000MB空间（避免系统卡死）

# 步骤1：远程获取/data的可用字节数
echo "===== 1. 获取${v_rm_ip}:${db_dir}可用空间 ====="
AVAIL_BYTES=$(ssh ${u_name}@${v_rm_ip} "df -P ${db_dir} | awk 'NR==2{print \$4 * 1024}'")
# df -P的$4是可用块数（默认块大小512/1024字节），*1024转为字节（POSIX标准块大小1024）

if [[ -z ${AVAIL_BYTES} || ${AVAIL_BYTES} -lt ${RESERVE_SPACE} ]]; then
    echo "错误：可用空间不足（或获取失败），可用字节数：${AVAIL_BYTES}，预留空间：${RESERVE_SPACE}"
    let fail_flag++
    let rm_fail_flag++
else

# 步骤2：计算实际要填充的字节数（总可用 - 预留空间）
FILL_BYTES=$((AVAIL_BYTES - RESERVE_SPACE))
AVAIL_GB=$((AVAIL_BYTES / 1024 / 1024 / 1024))
FILL_GB=$((FILL_BYTES / 1024 / 1024 / 1024))
echo "===== 2. 计算填充大小 ====="
echo "总可用字节：${AVAIL_BYTES} (≈${AVAIL_GB} GB)"
echo "预留空间：${RESERVE_SPACE} (≈5000 MB)"
echo "实际填充字节：${FILL_BYTES} (≈${FILL_GB} GB)"

# 步骤3：远程执行dd填满空间（用bs=1M提升写入速度）
echo "===== 3. 开始填充${v_rm_ip}:${db_dir} ====="
if ! stop_disk_filler "${v_rm_ip}";then
   echo "清理遗留磁盘填充进程失败。"
   let fail_flag++
   let rm_fail_flag++
else
fill_count=$((FILL_BYTES / 1024 / 1024))
ssh ${u_name}@${v_rm_ip} \
   "echo \$\$ > '${FILL_PID_FILE}'; exec dd if=/dev/zero of='${FILL_FILE}' bs=1M count=${fill_count} conv=fsync"
fill_rc=$?
ssh ${u_name}@${v_rm_ip} "rm -f '${FILL_PID_FILE}'"
if [[ ${fill_rc} -ne 0 ]];then
   echo "填充磁盘失败。"
   let fail_flag++
   let rm_fail_flag++
else

# 步骤4：验证填充结果
echo "===== 4. 验证填充结果 ====="
ssh ${u_name}@${v_rm_ip} "df -h ${db_dir}; ls -lh ${FILL_FILE}"

echo "===== 操作完成 ====="
echo "如需清理填充文件，执行：ssh ${u_name}@${v_rm_ip} 'rm -f ${FILL_FILE}'"

      v_read_only=`${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;"|grep -i only|wc -l`
      if [[ ${v_read_only} = 0 ]];then
         let fail_flag++
         let rm_fail_flag++
      else
          ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "remove datanode ${v_rm_id};">${cur_dir}/tmp.out
          check_res "success" 1 "${SCRIPT_NAME}"
fi
fi
fi
fi
fi

   wait_rm_finish "${v_rm_ip}" 3600
   wait_bm_finish 36000 "${bm_res1}" "${bm_res2}"
if [[ ${rm_fail_flag} = 0 ]];then 
   check_data_consistent
fi
   check_npe "${SCRIPT_NAME}"
test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))
tc_res=true

# remove test data before calculating the final result so cleanup failures are
# reflected in tc_res as well.
ssh ${u_name}@${v_rm_ip} "rm -rf ${db_dir}/10gb_file_*"
stop_disk_filler "${v_rm_ip}" || let fail_flag++

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass"
     rm -rf ${bm_dir}/${v_t}_bm1.out 
     rm -rf ${bm_dir}/${v_t}_bm2.out 
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail"
  fi
echo "${tc_num}"
echo "${SCRIPT_NAME}"
echo "${tc_res}"
echo "${test_elp_sec}"

${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -pw ${res_root_pw} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

}
if ! clean_env;then
   exit 1
fi
if ! start_db;then
   exit 1
fi
remove_dn

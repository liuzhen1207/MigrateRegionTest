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
ssl_str=""
clean_env_dir="${cur_dir}/../clean_env"
prepare_env_dir="${cur_dir}/../prepare_env"
check_res_dir="${cur_dir}/../check_res"
SCRIPT_NAME=$(basename "$0")
seed_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`:10710
query_cn_ip=`head -1 ${nodeinfo_dir}/confignode.txt`
query_ip=`head -1 ${nodeinfo_dir}/datanode.txt`
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
evidence_dir=""
remove_command_response=""
function capture_cli_snapshot()
{
   local name=$1
   local dialect=$2
   local sql=$3
   local output="${evidence_dir}/${name}.out"
   local rc
   timeout 60s "${cli_dir}/sbin/start-cli.sh" -u "${db_sys_admin}" ${ssl_str} -h "${query_ip}" -sql_dialect "${dialect}" -e "${sql}" > "${output}" 2>&1
   rc=$?
   printf 'snapshot %s: rc=%s file=%s\n' "${name}" "${rc}" "${output}" >> "${evidence_dir}/manifest.txt"
}
function capture_failure_evidence()
{
   local reason=$1
   local role
   local host
   local host_tag
   local archive
   local new_evidence_dir

   [[ -n "${evidence_dir}" ]] && return 0
   new_evidence_dir="${cur_dir}/logs_backup/${SCRIPT_NAME%.sh}_$(date +%Y%m%d_%H%M%S)_$$"
   if ! mkdir -p "${new_evidence_dir}";then
      echo "Evidence directory creation failed: ${new_evidence_dir}" >&2
      return 1
   fi
   evidence_dir="${new_evidence_dir}"
   printf 'reason=%s\ntime=%s\nversion=%s\nremoved_dn_id=%s\nremoved_dn_ip=%s\nquery_ip=%s\n' \
      "${reason}" "$(date -Is)" "${v_cur_db}" "${v_rm_id:-unknown}" "${v_rm_ip:-unknown}" "${query_ip}" > "${evidence_dir}/manifest.txt"
   echo "Failure evidence: ${evidence_dir}"
   for host in test.conf confignode.txt datanode.txt;do
      if [[ "${host}" == test.conf ]];then
         cp -p "${conf_file}" "${evidence_dir}/test.conf"
      else
         cp -p "${nodeinfo_dir}/${host}" "${evidence_dir}/${host}"
      fi
   done
   [[ -f "${cur_dir}/tmp.out" ]] && cp -p "${cur_dir}/tmp.out" "${evidence_dir}/last_tmp.out"
   [[ -n "${remove_command_response}" ]] && printf '%s\n' "${remove_command_response}" > "${evidence_dir}/remove_datanode_command.out"

   capture_cli_snapshot show_datanodes tree 'show datanodes;'
   capture_cli_snapshot show_migrations tree 'show migrations;'
   capture_cli_snapshot show_regions_tree tree 'show regions;'
   capture_cli_snapshot show_regions_table table 'show regions;'
   capture_cli_snapshot show_cluster tree 'show cluster;'

   for role in confignode datanode;do
      while IFS= read -r host || [[ -n "${host}" ]];do
         [[ -z "${host}" || "${host}" == \#* ]] && continue
         host_tag=${host//./_}
         archive="${evidence_dir}/${role}_${host_tag}.tar.gz"
         if timeout 300s ssh -n -o BatchMode=yes -o ConnectTimeout=10 "${u_name}@${host}" \
               "tar -czf - -C '${db_dir}' logs" > "${archive}" 2> "${archive}.stderr" &&
               tar -tzf "${archive}" >/dev/null 2>&1;then
            printf 'logs %s %s: ok file=%s\n' "${role}" "${host}" "${archive}" >> "${evidence_dir}/manifest.txt"
         else
            printf 'logs %s %s: FAILED file=%s stderr=%s.stderr\n' "${role}" "${host}" "${archive}" "${archive}" >> "${evidence_dir}/manifest.txt"
         fi
      done < "${nodeinfo_dir}/${role}.txt"
   done
   echo "Failure evidence manifest: ${evidence_dir}/manifest.txt"
}
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
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=5"
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
exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
v_check=`grep ${line} ${nodeinfo_dir}/datanode.txt |wc -l`
if [[ ${v_check} = 0 ]];then
ssh ${u_name}@${line} "sudo sh -c \"sync; echo 3 > /proc/sys/vm/drop_caches\"";
fi
done

   if ! sh -x ${prepare_env_dir}/start_cluster.sh "1" "${total_node_num}"; then
      echo "Cluster startup failed; aborting before benchmark."
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
   local attempt=$3
   local t1=$(date +%s)
   local empty_since=0
   local now elapsed migrations_output migrations_rc v_rm_status

   while true;do
      migrations_output=$(timeout 60s "${cli_dir}/sbin/start-cli.sh" -u "${db_sys_admin}" ${ssl_str} -h "${query_ip}" -e 'show migrations;' 2>&1)
      migrations_rc=$?
      now=$(date +%s)
      elapsed=$((now-t1))

      if [[ ${migrations_rc} -eq 0 ]] && grep -q '^Empty set\.$' <<< "${migrations_output}";then
         if [[ ${empty_since} -eq 0 ]];then
            empty_since=${now}
         fi
         if [[ $((now-empty_since)) -ge 60 ]];then
            echo "show migrations has been empty for 60 seconds; checking DataNode ${v_rm_id} (${v_rm_ip})."
            break
         fi
      else
         empty_since=0
         if [[ ${migrations_rc} -ne 0 ]] || grep -Eq '^Error:|^Exception' <<< "${migrations_output}";then
            echo "show migrations query failed (rc=${migrations_rc}): ${migrations_output}" >&2
         fi
      fi

      if [[ ${elapsed} -gt ${max_wait_time} ]];then
         let fail_flag++
         let rm_fail_flag++
         echo "Removing takes too long: show migrations was not continuously empty for 60 seconds after ${elapsed}s."
         capture_failure_evidence "remove datanode timeout after ${elapsed}s; migrations not continuously empty"
         return 1
      fi
      sleep 1
   done

   if ! timeout 60s "${cli_dir}/sbin/start-cli.sh" -u "${db_sys_admin}" ${ssl_str} -h "${query_ip}" -e 'show datanodes;' > "${cur_dir}/tmp.out" 2>&1 ||
      ! grep -q 'Total line number' "${cur_dir}/tmp.out";then
      let fail_flag++
      let rm_fail_flag++
      echo "Failed to verify DataNode ${v_rm_id} (${v_rm_ip}) after migrations became empty."
      capture_failure_evidence 'show datanodes failed after migrations became empty'
      return 1
   fi
   cp -p "${cur_dir}/tmp.out" "${cur_dir}/tc109_remove_attempt_${attempt}_datanodes.out"
   if grep -Fq "${v_rm_ip}|" "${cur_dir}/tmp.out";then
      v_rm_status=$(grep -F "${v_rm_ip}|" "${cur_dir}/tmp.out" | awk -F '|' 'NR == 1 {gsub(" ", "", $3); print $3}')
      if [[ ${attempt} -eq 1 && ${v_rm_status} == Unknown ]];then
         echo "First remove attempt ended with DataNode ${v_rm_id} still Unknown; retrying once."
         return 2
      fi
      let fail_flag++
      let rm_fail_flag++
      echo "Remove attempt ${attempt} ended, but DataNode ${v_rm_id} (${v_rm_ip}) is still ${v_rm_status} in show datanodes."
      capture_failure_evidence "remove attempt ${attempt}: migrations empty for 60s; datanode still ${v_rm_status}"
      return 1
   fi
   echo "DataNode ${v_rm_id} (${v_rm_ip}) has been removed."
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
         sleep 10
      fi
      v_cur_time=`date +%s`
      v_elp_time=$((v_cur_time-v_start_time))
      if [[ ${v_elp_time} -gt 600 ]];then
         let fail_flag++
         echo "stop ${line} timeout."
         return
      fi
      done

}

function remove_dn()
{
   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "show datanodes;">${cur_dir}/tmp.out
   v_rm_id=`cat ${cur_dir}/tmp.out |grep Running|tail -1|awk -F "|" '{gsub(" ","");print $2}'`
   v_rm_ip=`cat ${cur_dir}/tmp.out |grep Running|tail -1|awk -F "|" '{gsub(" ","");print $4}'`

#start 2bm
   v_t=`date "+%Y_%m_%d_%H_%M_%S"`
   v_host=`awk '{printf "%s%s", (NR==1?"":","), $0}' ${nodeinfo_dir}/datanode.txt`
   v_20_pass=`grep ^passwd_param= ${cli_dir}/sbin/start-cli.sh |grep TimechoDB|wc -l`
if [[ ${v_20_pass} -gt 0 ]];then
        bm_root_pw="TimechoDB@2021"
else

        bm_root_pw="root"
fi
sed -i "s/^PASSWORD=.*/PASSWORD=${bm_root_pw}/g" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties

   sed -i "s/^HOST=.*/HOST=${v_host}/g" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties
   sed -i "s/LOOP=.*/LOOP=10000/g" ${bm_dir}/lt_10type_user_no_ssl/conf*/config.properties
   nohup sh -x ${bm_dir}/benchmark.sh -cf ${bm_dir}/lt_10type_user_no_ssl/conf1 >${bm_dir}/${v_t}_bm1.out &
   nohup sh -x ${bm_dir}/benchmark.sh -cf ${bm_dir}/lt_10type_user_no_ssl/conf2 >${bm_dir}/${v_t}_bm2.out &
   sleep 300
# stop dn ${v_rm_ip}
   if [ -n "$v_rm_ip" ]; then
   ssh ${u_name}@${v_rm_ip} "source /etc/profile;cd ${db_dir};sudo ./sbin/stop-datanode.sh"
   echo "Stopping ${v_rm_ip}"
   fi

  if [[ ${query_ip} = ${v_rm_ip} ]];then
     query_ip=`sed -n '2p' ${nodeinfo_dir}/datanode.txt`
  fi

   ${cli_dir}/sbin/start-cli.sh -u ${db_sys_admin} ${ssl_str} -h ${query_ip} -e "remove datanode ${v_rm_id};">${cur_dir}/tmp.out
   remove_command_response=$(cat "${cur_dir}/tmp.out")
   check_res "success" 1 "${SCRIPT_NAME}"
  check_stop ${v_rm_ip} ${query_ip}
   if wait_rm_finish "${v_rm_ip}" 3600 1;then
      :
   else
      rm_wait_rc=$?
      if [[ ${rm_wait_rc} -eq 2 ]];then
         echo "Submitting one more REMOVE DATANODE ${v_rm_id} after the first procedure settled."
         if timeout 60s "${cli_dir}/sbin/start-cli.sh" -u "${db_sys_admin}" ${ssl_str} -h "${query_ip}" \
            -e "remove datanode ${v_rm_id};" > "${cur_dir}/tc109_remove_attempt_2.out" 2>&1 &&
            grep -q 'successfully' "${cur_dir}/tc109_remove_attempt_2.out";then
            remove_command_response="${remove_command_response}
Retry: $(cat "${cur_dir}/tc109_remove_attempt_2.out")"
            wait_rm_finish "${v_rm_ip}" 3600 2
         else
            let fail_flag++
            let rm_fail_flag++
            echo "Second REMOVE DATANODE ${v_rm_id} submission failed."
            cat "${cur_dir}/tc109_remove_attempt_2.out"
            capture_failure_evidence 'second remove datanode submission failed'
         fi
      fi
   fi
   wait_bm_finish 36000 "${bm_dir}/${v_t}_bm1.out" "${bm_dir}/${v_t}_bm2.out"
   if [[ -n "${evidence_dir}" ]];then
      cp -p "${bm_dir}/${v_t}_bm1.out" "${bm_dir}/${v_t}_bm2.out" "${evidence_dir}/" 2>> "${evidence_dir}/manifest.txt"
   fi
if [[ ${rm_fail_flag} = 0 ]];then 
   check_data_consistent
fi
   check_npe "${SCRIPT_NAME}"
test_end_sec=`date +%s`
test_elp_sec=$((test_end_sec-test_begin_sec))
tc_res=true

  if [[ ${fail_flag} = 0 ]];then
     tc_res=true
     echo "${SCRIPT_NAME} : pass"
     rm -rf ${bm_dir}/${v_t}_bm1.out 
     rm -rf ${bm_dir}/${v_t}_bm2.out 
  else
     tc_res=false
     echo "${SCRIPT_NAME} : fail"
     capture_failure_evidence "test failed; fail_flag=${fail_flag}; rm_fail_flag=${rm_fail_flag}"
     if [[ -n "${evidence_dir}" ]];then
        cp -p "${bm_dir}/${v_t}_bm1.out" "${bm_dir}/${v_t}_bm2.out" "${evidence_dir}/" 2>> "${evidence_dir}/manifest.txt"
     fi
  fi
echo "${tc_num}"
echo "${SCRIPT_NAME}"
echo "${tc_res}"
echo "${test_elp_sec}"

${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -pw ${res_root_pw} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"

}
function record_start_failure()
{
   test_end_sec=`date +%s`
   test_elp_sec=$((test_end_sec-test_begin_sec))
   tc_res=false
   echo "${SCRIPT_NAME} : fail (cluster startup failed)"
   capture_failure_evidence 'cluster startup failed'
   echo "${tc_num}"
   echo "${SCRIPT_NAME}"
   echo "${tc_res}"
   echo "${test_elp_sec}"

   ${cli_dir}/sbin/start-cli.sh -h ${testcase_res_db} -p ${testcase_res_port} -pw ${res_root_pw} -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time)aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${tc_res},${test_elp_sec});"
}
clean_env
if ! start_db; then
   record_start_failure
   exit 1
fi
remove_dn

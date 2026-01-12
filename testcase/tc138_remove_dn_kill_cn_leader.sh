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

fail_file="fail.log"
cn_num=3
dn_num=5
head -n ${dn_num} ${nodeinfo_dir}/total_datanode.txt > ${nodeinfo_dir}/datanode.txt
head -n ${dn_num} ${nodeinfo_dir}/total_datanode_port.txt > ${nodeinfo_dir}/datanode_port.txt
total_node_num=$((cn_num+dn_num))
backup_dir_on_cn_dn_host=/data/iotdb/autotest_backup/3db_IoTV1_remove_1regionperdb
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
set_sys_conf ${line} ${db_dir} ".*schema_replication_factor=.*" "schema_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*data_replication_factor=.*" "data_replication_factor=3"
set_sys_conf ${line} ${db_dir} ".*schema_region_group_extension_policy=.*" "schema_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*data_region_group_extension_policy=.*" "data_region_group_extension_policy=CUSTOM"
set_sys_conf ${line} ${db_dir} ".*default_schema_region_group_num_per_database=.*" "default_schema_region_group_num_per_database=1"
set_sys_conf ${line} ${db_dir} ".*default_data_region_group_num_per_database=.*" "default_data_region_group_num_per_database=1"
     set_sys_conf ${line} ${db_dir} ".*datanode_memory_proportion=.*"  "datanode_memory_proportion=1:5:1:1:1:1"
//     set_sys_conf ${line} ${db_dir} ".*disk_space_warning_threshold=.*" "disk_space_warning_threshold=0.99"
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
ssh ${u_name}@${line} "sudo cp -rp ${backup_dir_on_cn_dn_host}/data ${db_dir}/ " &
done
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
        while true
        do
        v_check_cp=`ssh ${u_name}@${line} "sudo ps -ef|grep \"cp -rp\"|grep -v grep|wc -l"`
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
function check_data_consistent()
{

   # all node online,query
    q1="select count(s_0) from root.test.g_0.** align by device;"
    q2="select count(s_0) from root.db.g_0.** align by device;"
    q3="select device_id,count(s_1) from db_table_g_0.table_0 group by device_id order by device_id;"
    ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600000  -e "${q1}" > ${cur_dir}/q_all_online_test.out
    ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600000  -e "${q2}" > ${cur_dir}/q_all_online_db.out
    ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -sql_dialect table -timeout 3600000  -e "${q3}" > ${cur_dir}/q_all_online_table.out
    res_row_num1=`grep root.test ${cur_dir}/q_all_online_test.out|wc -l`
    res_row_num2=`grep root.db ${cur_dir}/q_all_online_db.out|wc -l`
    res_row_num3=`grep d1_ ${cur_dir}/q_all_online_table.out|wc -l`
    res_row_num3_exp=`grep Exception ${cur_dir}/q_all_online_table.out|wc -l`
   if [[ ${res_row_num1} = 0 ]];then
      let fail_flag++
      return 1
   fi
   if [[ ${res_row_num2} = 0 ]];then
      let fail_flag++
      return 1
   fi
   if [[ ${res_row_num3} = 0 ]] || [[ ${res_row_num3_exp} -gt 0 ]];then
      let fail_flag++
      return 1
   fi


   # stop 1 datanode,query
   exec 3<${nodeinfo_dir}/datanode.txt
while read line <&3
do
v_ignore=`grep "${line}," ${cur_dir}/ignore_dn_list.txt|wc -l`
if [[ ${v_ignore} = 0 ]];then
   ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/stop-datanode.sh"
   if [[ "${line}" = "${query_ip}" ]];then
      q_node="${query_ip2}"
   else
      q_node="${query_ip}"
   fi
   while true
   do
           sleep 1
      v_running=`${cli_dir}/sbin/start-cli.sh -h ${q_node} -timeout 3600  -e "show cluster;" |grep ${line} |grep DataNode|grep Running|wc -l`
      v_jps=`ssh ${u_name}@${line} "source /etc/profile;sudo jps|grep DataNode|wc -l"`
      if [[ ${v_running} = 1 ]];then
              sleep 2
      else
              if [[ ${v_jps} = 0 ]];then
                 break
              else
                 sleep 2
              fi
      fi
   done
   v_ip=`echo ${line} |awk -F '.' '{print $4}'`
   ${cli_dir}/sbin/start-cli.sh -h ${q_node} -timeout 3600000  -e "${q1}" >${cur_dir}/q_stop_ip${v_ip}_test.out
   ${cli_dir}/sbin/start-cli.sh -h ${q_node} -timeout 3600000  -e "${q2}" >${cur_dir}/q_stop_ip${v_ip}_db.out
   ${cli_dir}/sbin/start-cli.sh -h ${q_node} -sql_dialect table -timeout 3600000  -e "${q3}" > ${cur_dir}/q_stop_ip${v_ip}_table.out
   v_diff1=`diff ${cur_dir}/q_all_online_test.out ${cur_dir}/q_stop_ip${v_ip}_test.out|grep root|wc -l` 
   v_diff2=`diff ${cur_dir}/q_all_online_db.out ${cur_dir}/q_stop_ip${v_ip}_db.out|grep root|wc -l` 
   v_diff3=`diff ${cur_dir}/q_all_online_table.out ${cur_dir}/q_stop_ip${v_ip}_table.out|grep d1_|wc -l` 
   if [[ ${v_diff1} -gt 0 ]];then
      echo "stop ${line} q1 result diff all online."
      let fail_flag++
      return 1
   fi
   if [[ ${v_diff2} -gt 0 ]];then
      echo "stop ${line} q2 result diff all online."
      let fail_flag++
      return 1
   fi
   if [[ ${v_diff3} -gt 0 ]];then
      echo "stop ${line} q3 result diff all online."
      let fail_flag++
      return 1
   fi

#   echo "stop_node,${line};q_node,${q_node}"
   ssh ${u_name}@${line} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/${test_begin_sec}_query_dn.hprof > /dev/null 2>&1 &"
   while true
   do
           sleep 5
      v_running=`${cli_dir}/sbin/start-cli.sh -h ${q_node} -timeout 3600  -e "show cluster;" |grep ${line} |grep DataNode|egrep "Running|ReadOnly"|wc -l`
      if [[ ${v_running} = 1 ]];then
              break
      else
              sleep 5
      fi
   done

   let i++
fi
done
}
function stop_dn()
{
   local rm_dn_ip=$1
        # stop rm_dn_ip
        ssh ${u_name}@${rm_dn_ip} "sudo ${db_dir}/sbin/stop-datanode.sh"
        while true
        do
           v_unknown=`${cli_dir}/sbin/start-cli.sh -h ${query_ip2} -e "show datanodes;"|grep "${rm_dn_ip}|"|grep -i unknown|wc -l`
           if [[ ${v_unknown} -gt 0 ]];then
              break
           else
              sleep 2
           fi
        done
        while true
        do
           v_unknown=`ssh ${u_name}@${rm_dn_ip} "sudo jps|grep -i datanode|wc -l"`
           if [[ ${v_unknown} = 0 ]];then
              break
           else
              sleep 2
           fi
        done

}
function stop_cn()
{
   local rm_dn_ip=$1
        # stop rm_dn_ip
        ssh ${u_name}@${rm_dn_ip} "sudo ${db_dir}/sbin/stop-confignode.sh"
        while true
        do
           v_unknown=`${cli_dir}/sbin/start-cli.sh -h ${query_ip2} -e "show confignodes;"|grep "${rm_dn_ip}|"|grep -i unknown|wc -l`
           if [[ ${v_unknown} -gt 0 ]];then
              break
           else
              sleep 2
           fi
        done
        while true
        do
           v_unknown=`ssh ${u_name}@${rm_dn_ip} "sudo jps|grep -i confignode|wc -l"`
           if [[ ${v_unknown} = 0 ]];then
              break
           else
              sleep 2
           fi
        done

}

function kill9_dn()
{
   local rm_dn_ip=$1
        # kill -9 rm_dn_ip
        v_pid_str=`ssh ${u_name}@${rm_dn_ip} "sudo jps|grep -i datanode"`
        v_pid=`echo ${v_pid_str}|awk '{print $1}'`
        ssh ${u_name}@${rm_dn_ip} "sudo kill -9 ${v_pid}" 
        while true
        do
           v_unknown=`${cli_dir}/sbin/start-cli.sh -h ${query_ip2} -e "show datanodes;"|grep "${rm_dn_ip}|"|grep -i unknown|wc -l`
           if [[ ${v_unknown} -gt 0 ]];then
              break
           else
              sleep 2
           fi
        done
        while true
        do
           v_unknown=`ssh ${u_name}@${rm_dn_ip} "sudo jps|grep -i datanode|wc -l"`
           if [[ ${v_unknown} = 0 ]];then
              break
           else
              sleep 2
           fi
        done

}

function kill9_cn()
{
   local rm_dn_ip=$1
        # kill -9 rm_dn_ip
        v_pid_str=`ssh ${u_name}@${rm_dn_ip} "sudo jps|grep -i confignode"`
        v_pid=`echo ${v_pid_str}|awk '{print $1}'`
        ssh ${u_name}@${rm_dn_ip} "sudo kill -9 ${v_pid}"
        while true
        do
           v_unknown=`${cli_dir}/sbin/start-cli.sh -h ${query_ip2} -e "show confignodes;"|grep "${rm_dn_ip}|"|grep -i unknown|wc -l`
           if [[ ${v_unknown} -gt 0 ]];then
              break
           else
              sleep 2
           fi
        done
        while true
        do
           v_unknown=`ssh ${u_name}@${rm_dn_ip} "sudo jps|grep -i confignode|wc -l"`
           if [[ ${v_unknown} = 0 ]];then
              break
           else
              sleep 2
           fi
        done

}


function start_dn()
{
   local rm_dn_ip=$1
   # start rm_dn_ip
   ssh ${u_name}@${rm_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-datanode.sh -H ${db_dir}/${test_begin_sec}_restart_dn.hprof > /dev/null 2>&1 &"
   while true
   do
           sleep 5
      v_running=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600  -e "show datanodes;" |grep "${rm_dn_ip}|" |grep Running|wc -l`
      if [[ ${v_running} = 1 ]];then
              break
      else
              sleep 5
      fi
   done

}
function start_cn()
{
   local rm_dn_ip=$1
   # start rm_dn_ip
   ssh ${u_name}@${rm_dn_ip} "source /etc/profile;sudo ${db_dir}/sbin/start-confignode.sh -H ${db_dir}/${test_begin_sec}_restart_cn.hprof > /dev/null 2>&1 &"
   while true
   do
           sleep 5
      v_running=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -timeout 3600  -e "show confignodes;" |grep "${rm_dn_ip}|" |grep Running|wc -l`
      if [[ ${v_running} = 1 ]];then
              break
      else
              sleep 5
      fi
   done

}

function check_rm_dn_regions()
{
   local rm_dn_ip=$1
   local loop=0
   local flag_no_remove=0
        while true
        do
                      ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions;" > ${cur_dir}/show_regions.out
                      v_rm_suc=`cat ${cur_dir}/show_regions.out|grep "${rm_dn_ip}|"|wc -l`
                      if [[ ${v_rm_suc} = 0 ]];then
                         local v_other_dn=`cat ${cur_dir}/show_regions.out|grep "${query_ip}|"|wc -l`
                         if [[ ${v_other_dn} -gt 0 ]];then
                            echo "migrate region success."
                            return 1
                            break
                         else
                            v_cur_sec=`date +%s`
                            cp -rp ${cur_dir}/show_regions.out ${cur_dir}/show_regions_${v_cur_sec}.out
                            sleep 10
                         fi
                      else
                            local v_adding_num=`cat ${cur_dir}/show_regions.out|grep "Adding"|wc -l`
                            if [[ ${v_adding_num} -gt 0 ]];then
                               let flag_no_remove=1
                            fi

                         sleep 10
                      fi
                   let loop++
                   if [[ ${loop} -gt 3 ]];then
                      if [[ ${flag_no_remove} = 0 ]];then
                        let rm_flag=fail
                         return 1
                      fi
                   fi
                   if [[ ${loop} -gt 30 ]] && [[ ${v_adding_num} = 0 ]];then
                      echo "ERROR : remove ${rm_dn_ip} 5 min fail and no Adding status."
                      let rm_flag=fail
#                      let fail_flag++
                      return 1
                   fi
                   if [[ ${loop} -gt 180 ]];then
                       echo "Perhaps Adding stuck."
                       let rm_flag=fail
                       let fail_flag++
                       return 1 
                   fi
        done
        check_rm_dn_status
 
}
function check_rm_dn_status()
{
rm_dn_ip=$1
        # check remove-dn status
        local loop=0
        while true
        do
                      v_rm_suc=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes;"|grep "${rm_dn_ip}|"|wc -l`
                      if [[ ${v_rm_suc} = 0 ]];then
                         return 1
                         break
                      else
                         sleep 10
                      fi
                   let loop++
                   if [[ ${loop} -gt 60 ]];then
                      echo "ERROR : remove ${rm_dn_ip} fail,${rm_dn_ip} in show datanodes result."
                      let fail_flag++
                      rm_flag=fail
                      return 1
                   fi
        done

}
function remove_1datanode()
{
        rm_dn_ip=$1
        exec_rm_ip=$2
        rm_flag=$3
        v_rm_datanode_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes;"|grep "${rm_dn_ip}|"|awk -F '|' '{gsub(" ","");print $2}'`

        ssh ${u_name}@${exec_rm_ip} "sudo ${db_dir}/sbin/remove-datanode.sh  ${v_rm_datanode_id}">${cur_dir}/rm_cmd_res.out 2>>${cur_dir}/rm_cmd_res.out
   if [[ "${rm_flag}" = "success" ]];then
        v_rm_fail=`cat ${cur_dir}/rm_cmd_res.out|grep "Submit remove-datanode request successfully"|wc -l`
        if [[ ${v_rm_fail} = 0 ]];then
           let fail_flag++
        fi
   else
        v_rm_fail=`cat ${cur_dir}/rm_cmd_res.out|grep "Submit RemoveDataNodesProcedure failed"|wc -l`
        if [[ ${v_rm_fail} = 0 ]];then
           let fail_flag++
        fi
   fi
   if [[ ${fail_flag} -gt 0 ]];then
      let rm_flag=fail
   fi
}

function remove_2datanode()
{
	rm_dn_ip=$1
	exec_rm_ip=$1
        rm_dn_ip2=$2

        rm_flag=$3
        v_rm_datanode_id=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes;"|grep "${rm_dn_ip}|"|awk -F '|' '{gsub(" ","");print $2}'`
        v_rm_datanode_id2=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes;"|grep "${rm_dn_ip2}|"|awk -F '|' '{gsub(" ","");print $2}'`

        ssh ${u_name}@${exec_rm_ip} "sudo ${db_dir}/sbin/remove-datanode.sh  ${v_rm_datanode_id} ${v_rm_datanode_id2}">${cur_dir}/rm_cmd_res.out 2>>${cur_dir}/rm_cmd_res.out
   if [[ "${rm_flag}" = "success" ]];then
        v_rm_fail=`cat ${cur_dir}/rm_cmd_res.out|grep "Submit remove-datanode request successfully"|wc -l`
        if [[ ${v_rm_fail} = 0 ]];then
           let rm_flag=fail
           let fail_flag++
        fi
   else
        v_rm_fail=`cat ${cur_dir}/rm_cmd_res.out|grep "Submit RemoveDataNodesProcedure failed"|wc -l`
        if [[ ${v_rm_fail} = 0 ]];then
           let fail_flag++
        fi
   fi  
}


function exec_remove()
{

last_dn_ip=`tail -1 ${nodeinfo_dir}/datanode.txt`
last_dn_ip2=`tail -2 ${nodeinfo_dir}/datanode.txt|head -1`
last_dn_ip3=`tail -3 ${nodeinfo_dir}/datanode.txt|head -1`
#find region id not on last_dn_ip 
#get ${last_dn_ip} region id
#${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions;"|grep "${last_dn_ip}|"|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/rm_dn1_regionid.txt
##get all region id
#${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions;"|grep aRegion|awk -F '|' '{gsub(" ","");print $2}'|uniq>${cur_dir}/rm_all_regionid.txt
#>${cur_dir}/pre_mig_id.txt
#exec 3<${cur_dir}/rm_all_regionid.txt
#while read regionid<&3
#do
#	v_same=`grep -x ${regionid} ${cur_dir}/rm_dn1_regionid.txt|wc -l`
#	if [[ ${v_same} = 0 ]];then
#	echo "${regionid}">>${cur_dir}/pre_mig_id.txt
#	fi
#done
## exec mig
## get all  datanodeid
#${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes;"|grep Running|grep -v "${last_dn_ip}|"|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/rm_all_target_datanodeid.txt
## get from nodeid
##cat ${nodeinfo_dir}/datanode.txt|head -3>${cur_dir}/v_mig_target_ip_list.txt
##get all region id and nodeid
#${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions;"|grep aRegion|awk -F "|" '{gsub(" ","");print $2","$8}'>${cur_dir}/rm_all_regionid_nodeid.txt
#>${cur_dir}/remove_mig.sql
#exec 4<${cur_dir}/pre_mig_id.txt
#while read v_mig_id<&4
#do
#	  # get from nodeid
#	  v_mig_from_id=`grep "^${v_mig_id}," ${cur_dir}/rm_all_regionid_nodeid.txt|head -1|awk -F ',' '{print $2}'`
#	  grep "^${v_mig_id}," ${cur_dir}/rm_all_regionid_nodeid.txt|awk -F ',' '{print $2}'>${cur_dir}/rm_from_datanodeid.txt
#          # get to nodeid
#          exec 5<${cur_dir}/rm_all_target_datanodeid.txt
#          while read nodeid<&5
#          do
#             v_same=`grep ${nodeid} ${cur_dir}/rm_from_datanodeid.txt|wc -l`
#             if [[ ${v_same} = 0 ]];then
#                v_mig_to_id=${nodeid}
#                break
#             fi
#          done
#          echo "MIGRATE REGION ${v_mig_id} FROM ${v_mig_from_id} TO ${v_mig_to_id};" >> ${cur_dir}/remove_mig.sql
#done
#
#t1=`date +%s`
#while true
#do
#   mig_flag=0
#	#get ${last_dn_ip} region id
#	${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show regions;"|grep "${last_dn_ip}|"|awk -F '|' '{gsub(" ","");print $2}'>${cur_dir}/rm_dn1_regionid.txt
#	exec 3<${cur_dir}/rm_dn1_regionid.txt
#	while read regionid<&3
#	do
#		v_same=`grep -x ${regionid} ${cur_dir}/rm_dn2_regionid.txt|wc -l`
#		if [[ ${v_same} -gt 0 ]];then
#	           let mig_flag++ 
#		fi
#	done
#        if [[ ${mig_flag} -gt 0 ]];then
#           sleep 30
#        else
#           break
#        fi
#   t2=`date +%s`
#   t_mig=$((t2-t1))
#   if [[ ${t_mig} -gt 1800 ]];then
#      let fail_flag++
#      break
#   fi
#done
#	stop_dn ${last_dn_ip2}
	remove_1datanode ${last_dn_ip} ${last_dn_ip2} "success"
        sleep 2
        v_cn_leader=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show confignodes;"|grep Leader|awk -F "|" '{gsub(" ","");print $4}'`
        kill9_cn "${v_cn_leader}"
#        ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "set system to ReadOnly;"
#        sleep 2
#        v_readonly_num=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show cluster;"|grep -i readonly|wc -l`
#        echo "ReadOnly node number:${v_readonly_num}"
#        ${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e<${cur_dir}/remove_mig.sql>${cur_dir}/remove_mig.out
#        v_mig_num=`cat ${cur_dir}/remove_mig.sql|wc -l`
#        v_mig_succ_num=`grep "The statement is executed successfully" ${cur_dir}/remove_mig.out |wc -l`
#        if [[ ${v_mig_succ_num} != ${v_mig_num} ]];then
#           let fail_flag++
#        fi
	# remove 1 stopped dn ,exp success 
        if [[ "${rm_flag}" = "success" ]];then
	   check_rm_dn_regions ${last_dn_ip}
        fi
>${cur_dir}/ignore_dn_list.txt
        if [[ "${rm_flag}" = "success" ]];then
           echo "${last_dn_ip}," > ${cur_dir}/ignore_dn_list.txt 
        fi
        start_cn "${v_cn_leader}"
        check_data_consistent
        v_rm_num=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -e "show datanodes;"|grep "${last_dn_ip}|"|wc -l`
        if [[ ${v_rm_num} -gt 0 ]];then
           let fail_flag++
        fi
#        fi
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
exec_remove

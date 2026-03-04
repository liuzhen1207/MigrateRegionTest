#!/bin/bash
cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=`cat ${conf_file}|grep u_name|awk -F '=' '{print $2}'`
dest_db_dir=`cat ${conf_file}|grep ^db_dir|awk -F '=' '{print $2}'`
source_db_dir=`cat ${conf_file}|grep ^source_db_dir|awk -F '=' '{print $2}'`
exec 3<${nodeinfo_dir}/datanode.txt
while read line<&3
do
   ssh ${u_name}@${line} "source /etc/profile;sudo ${dest_db_dir}/sbin/stop-datanode.sh"
   sleep 1
done
wait

exec 3<${nodeinfo_dir}/confignode.txt
while read line<&3
do
   ssh ${u_name}@${line} "source /etc/profile;sudo ${dest_db_dir}/sbin/stop-confignode.sh"
done
# 配置项（可根据需要调整）
sleep_time_seconds=1       # 超时时间（120秒）
log_file="./node_process_check.log"  # 日志文件

# 初始化日志
echo -e "\n===== $(date +%F_%T) 开始检查节点进程 =====" >> ${log_file}

# 函数：执行远程命令并设置超时控制
# 参数1：目标节点IP/主机名
# 参数2：要执行的远程命令
# 参数3：进程类型（DataNode/ConfigNode，用于日志）
exec_remote_cmd_with_timeout() {
    local target_node=$1
    local remote_cmd=$2
    local process_type=$3
    local pid_file="/tmp/ssh_${process_type}_${target_node}.pid"

    echo "[$(date +%F_%T)] 检查${process_type}：${target_node}" >> ${log_file}
    
    # 后台执行ssh命令，记录PID，并重定向输出到日志
    ssh -n ${u_name}@${target_node} "${remote_cmd}" >> ${log_file} 2>&1 &
    local ssh_pid=$!
    echo "[$(date +%F_%T)] ${target_node} ssh进程PID：${ssh_pid}" >> ${log_file}
    echo ${ssh_pid} > ${pid_file}

    # 等待指定时间，检查进程是否仍在运行
    v_check_num=0
while true
do
    if ps -p ${ssh_pid} > /dev/null 2>&1; then
        sleep ${sleep_time_seconds}
        # 超时未退出，强制kill -9
        let v_check_num++
        if [[ ${v_check_num} -gt 60 ]];then 
        kill -9 ${ssh_pid} > /dev/null 2>&1
        # 额外kill远程主机上可能残留的jps/sudo进程（可选）
        ssh -n ${u_name}@${target_node} "sudo pkill -9 jps; sudo pkill -9 grep" > /dev/null 2>&1
        fi
    else
       
        # 正常退出，记录结果
        echo "[$(date +%F_%T)] ${target_node} ${process_type}检查完成，正常退出" >> ${log_file}
    # 清理PID文件
        rm -f ${pid_file}
        break
        return 0
    fi

done
}

# ========== 第一步：检查DataNode进程 ==========
if [ -f ${nodeinfo_dir}/datanode.txt ]; then

    exec 3<${nodeinfo_dir}/datanode.txt
    while read line<&3
    do
        # 跳过空行和注释行
        [[ -z "${line}" || "${line}" =~ ^# ]] && continue
        # 构造远程命令：检查DataNode进程
        remote_cmd="source /etc/profile; sudo jps | grep DataNode"
        # 执行带超时的远程命令
        exec_remote_cmd_with_timeout "${line}" "${remote_cmd}" "DataNode"
    done
    exec 3>&-  # 关闭文件描述符
else
    echo "[$(date +%F_%T)] 错误：未找到文件 ${nodeinfo_dir}/datanode.txt" >> ${log_file}
fi

# ========== 第二步：检查ConfigNode进程 ==========
if [ -f ${nodeinfo_dir}/confignode.txt ]; then
    exec 3<${nodeinfo_dir}/confignode.txt
    while read line<&3
    do
        # 跳过空行和注释行
        [[ -z "${line}" || "${line}" =~ ^# ]] && continue
        # 检查当前节点是否不在datanode.txt中
            # 构造远程命令：检查ConfigNode进程
            remote_cmd="source /etc/profile; sudo jps | grep ConfigNode"
            # 执行带超时的远程命令
            exec_remote_cmd_with_timeout "${line}" "${remote_cmd}" "ConfigNode"
    done
    exec 3>&-  # 关闭文件描述符
else
    echo "[$(date +%F_%T)] 错误：未找到文件 ${nodeinfo_dir}/confignode.txt" >> ${log_file}
fi

# 收尾：记录检查完成
echo -e "===== $(date +%F_%T) 节点进程检查结束 =====\n" >> ${log_file}
echo "✅ 进程检查完成！详情请查看日志：${log_file}"

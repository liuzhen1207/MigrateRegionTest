#!/bin/bash
# 传入参数：desc 为待执行脚本路径/名称
desc=$1

# 校验参数
if [ -z "${desc}" ];then
    echo "Usage: $0 <test_script.sh>"
    exit 1
fi

# 校验文件是否存在且可执行
if [ ! -f "${desc}" ];then
    echo "ERROR: file ${desc} not found!"
    exit 1
fi

for i in {1..1}
do
    # 提取点号分割第一段，修正：命令替换用 $()
    tc_name=$(echo "$desc" |awk -F '.' '{print $1}')
    test_time=$(date +'%Y_%m_%d_%H_%M_%S')
    logfile="${tc_name}_${test_time}.out"

    echo "===== Round $i, run ${desc}, log: ${logfile} ====="
    bash -x "${desc}" > "${logfile}" 2>&1

    # 统计日志中同时包含 false 和 insert 的行数
    v_fail_num=$(grep false "${logfile}" | grep insert | wc -l)

    if [[ ${v_fail_num} -gt 0 ]];then
        echo ">>> Found insert false in ${logfile}, stop loop, result: fail"
        break
    fi
    echo ">>> Round $i pass, continue..."
    sleep 2
done

echo "===== Test loop finished ====="

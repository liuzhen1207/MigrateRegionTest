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

for i in {1..100}
do
    # 提取点号分割第一段，修正：命令替换用 $()
    tc_name=$(echo "$desc" |awk -F '.' '{print $1}')
    test_time=$(date +'%Y_%m_%d_%H_%M_%S')
    logfile="${tc_name}_${test_time}.out"

    # 【全局超时保护】单个用例若陷入无限循环会阻塞整个跑批
    #   （2026-11-04 tc107 卡 4h48m、此前 tc14 卡 11h，都是等待循环无超时）
    tc_timeout=${TC_TIMEOUT:-10800}
    # 按用例覆盖超时：慢用例（本来就跑得久）单独放宽，避免被误杀
    if [ -f "$(dirname "$0")/slow_case_timeouts.conf" ]; then
        _tc_ov=$(grep -E "^[[:space:]]*$(basename "${desc}")[[:space:]]" "$(dirname "$0")/slow_case_timeouts.conf" 2>/dev/null | awk '{print $2}' | head -1)
        if [ -n "${_tc_ov}" ]; then tc_timeout=${_tc_ov}; fi
    fi
    echo "===== Round $i, run ${desc}, log: ${logfile}, timeout: ${tc_timeout}s ====="
    timeout -s KILL "${tc_timeout}" bash -x "${desc}" > "${logfile}" 2>&1
    v_run_rc=$?
    if [[ ${v_run_rc} -eq 137 || ${v_run_rc} -eq 124 ]];then
        echo "===== [TIMEOUT] ${desc} 超过 ${tc_timeout}s 被强制终止（疑似死循环）=====" | tee -a "${logfile}"
        v_fail_num=1
    else
        # 统计日志中同时包含 false 和 insert 的行数
        v_fail_num=$(grep false "${logfile}" | grep insert | wc -l)
    fi


    if [[ ${v_fail_num} -gt 0 ]];then
        echo ">>> Found insert false in ${logfile}, stop loop, result: fail"
        break
    fi
    echo ">>> Round $i pass, continue..."
    sleep 2
done

echo "===== Test loop finished ====="

#!/bin/bash

# 循环运行 b.sh（示例：循环5次，可替换为实际循环条件）
for ((i=1; i<=20; i++)); do
    echo "第 $i 次运行 b.sh..."
    # 执行 b.sh 并捕获退出码
    ./tc2_enable_power_2bm_remove_dn_stop_removing_dn_20251028.sh
    exit_code=$?  # 获取 b.sh 的退出状态码

    # 判断是否为失败状态（b.sh 中 exit -1 对应 exit_code=255）
    if [ $exit_code -eq 255 ]; then
        echo "tc2 执行失败（返回码：$exit_code），中止测试"
        exit 1  # 中止 a.sh 并返回非0状态码
    elif [ $exit_code -ne 0 ]; then
        # 处理其他非0退出码（可选，根据实际需求）
        echo "tc2 执行异常（返回码：$exit_code），继续下一次循环"
    else
        echo "tc2 执行成功"
    fi
done

echo "所有循环执行完成"

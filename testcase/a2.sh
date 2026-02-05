#!/bin/bash
# 功能：获取主网卡IP并保存到变量，包含异常处理
set -e

# 步骤1：获取主IP
LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

# 步骤2：异常处理
if [ -z "${LOCAL_IP}" ] || [ "${LOCAL_IP}" = "127.0.0.1" ]; then
    echo "尝试备选方法获取IP..."
    LOCAL_IP=$(ip addr | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d '/' -f1 | head -n1)
fi

# 步骤3：最终验证
if [ -z "${LOCAL_IP}" ]; then
    echo "ERROR：无法获取有效IP地址"
    exit 1
else
    echo "✅ 成功获取IP：${LOCAL_IP}"
    # 后续可直接使用 ${LOCAL_IP} 变量
fi

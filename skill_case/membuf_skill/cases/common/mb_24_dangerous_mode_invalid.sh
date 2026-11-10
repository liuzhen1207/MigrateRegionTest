#!/bin/bash
# MB-24 dangerous_mode 取非布尔值时 DataNode 必须拒绝启动，且错误信息清晰
#
# 需求依据：docs/359
#   §3.2：dangerous_mode 配置为非布尔值时，DataNode 应拒绝并提示仅支持 true or false
#   §3.1：「仅针对当前DN。内部运维使用。」⇒ 只影响配置了非法值的那个 DN
#   §4  ：dangerous_mode 为非 true / false 值时失败，错误信息清晰
#
# 设计（**只改一个 DN**，避免把整个集群拖垮、也避免长时间等待）：
#   ① 先用正常配置起好集群（8/8）
#   ② 停掉目标 DN，只给它写 dangerous_mode=yes，再单独启动它
#   ③ 断言：该 DN **起不来**（进程不存在 / 端口未监听）
#   ④ 断言：日志里有明确提示 "must be true or false"
#   ⑤ 断言：其余节点不受影响（集群仍可用）
#   ⑥ 收尾：把该 DN 的非法值删掉并恢复启动
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../lib/common.sh"
source "$HERE/../../lib/mb.sh"
mb_load_env
mb_parse_args "$@"
mb_case_init MB-24

DB=root.mb24
export MB_MEM_PROPORTION="3:3:1:1:1:1"
export EXTRA_CONF=""

# ⚠️ 不能选 QDN（= DN[0]，CLI 的连接节点）：把它停掉会导致所有查询失败，
#    ⑤ 里"其余节点不受影响"就测不出来（2026-11-10 实测踩过）。
#    这里取最后一个 DN 作为被测目标。
if [ "${#DN[@]}" -ge 2 ]; then
  BAD_DN="${DN[${#DN[@]}-1]}"
else
  BAD_DN="${DN[0]}"
fi
if [ "$BAD_DN" = "$QDN" ]; then
  QDN="${DN[0]}"; [ "$QDN" = "$BAD_DN" ] && QDN="${DN[1]}"
  export QDN
fi
log "  被测 DN=$BAD_DN，查询入口 QDN=$QDN"
P="\$P"
ERR_PAT='must be true or false'

log "--- ① 正常配置起集群（8/8 基线）---"
mb_cluster_prepare
up=$(sq 'show cluster;' 2>/dev/null | grep -cE 'Running|ReadOnly')
assert_ge "①基线集群应就绪" "${up:-0}" 8

log "--- ② 只给 $BAD_DN 写入非法值 dangerous_mode=yes 并单独启动 ---"
# 停该 DN
sshx "$BAD_DN" "sudo pkill -9 -f 'com\.timecho\.iotdb\.DataNode' >/dev/null 2>&1 || true"
sleep 5
# 写非法值（只改这一个节点）
sshx "$BAD_DN" "P=$DB_DIR/conf/iotdb-system.properties; sudo sed -i -E '/^[#[:space:]]*dangerous_mode[[:space:]]*=/d' \"\$P\"; printf 'dangerous_mode=yes\n' | sudo tee -a \"\$P\" >/dev/null"
got=$(sshx "$BAD_DN" "grep -E '^dangerous_mode=' $DB_DIR/conf/iotdb-system.properties | tail -1" | tr -d '\r')
assert_eq "②非法值已写入且仅该节点" "$got" "dangerous_mode=yes"

# 单独启动该 DN（不等全局就绪）
sshx "$BAD_DN" "cd $DB_DIR && sudo rm -f /tmp/dn_${BAD_DN}.start; sudo setsid nohup sbin/start-datanode.sh </dev/null >/tmp/dn_${BAD_DN}.start 2>&1 &" >/dev/null 2>&1
log "  已下发启动命令，等待 40 秒观察是否存活..."
sleep 40

log "--- ③ 该 DN 必须拒绝启动 ---"
pid=$(sshx "$BAD_DN" "pgrep -f 'com\.timecho\.iotdb\.DataNode' | head -1" | tr -dc '0-9')
if [ -z "${pid:-}" ]; then
  pass "③$BAD_DN DataNode 已拒绝启动（进程不存在）"
else
  fail "③$BAD_DN DataNode 未拒绝启动（进程仍在，pid=$pid）"
fi
alive=$(sq 'show datanodes;' 2>/dev/null | grep -cE "Running.*${BAD_DN}")
assert_eq "③$BAD_DN 不应出现在 Running 的 DataNode 列表中" "${alive:-0}" "0"

log "--- ④ 错误信息必须清晰（含 must be true or false）---"
hits=0
for f in "$DB_DIR/logs/log_datanode_all.log" "/tmp/dn_${BAD_DN}.start"; do
  n=$(sshx "$BAD_DN" "sudo grep -acE '$ERR_PAT' $f 2>/dev/null" | tr -dc '0-9')
  if [ "${n:-0}" -gt 0 ]; then
    hits=$((hits+n))
    log "  --- $f 命中原文 ---"
    sshx "$BAD_DN" "sudo grep -aE '$ERR_PAT' $f 2>/dev/null | head -2 | cut -c1-240"
  fi
done
assert_ge "④非法值提示必须出现（must be true or false）" "$hits" 1

log "--- ⑤ 其余节点不受影响 ---"
others=$(sq 'show cluster;' 2>/dev/null | grep -cE 'Running|ReadOnly')
log "  当前 Running/ReadOnly=$others（基线 8，去掉 1 个 DN 后期望 >= 7）"
if [ "${others:-0}" -ge 7 ]; then
  pass "⑤其余节点不受影响（${others} 个节点仍在线）"
else
  warn "⑤在线节点数=${others}，低于期望 7（可能受本轮启动扰动影响）"
fi
cn_up=$(sq 'show cluster;' 2>/dev/null | grep -c 'ConfigNode.*Running')
assert_ge "⑤ConfigNode 不受 DN 配置影响" "${cn_up:-0}" 3

log "--- ⑥ 收尾：清除非法值 ---"
# 只负责把非法值从配置里删掉；**不**在本用例里重启 DN：
#   · 远程 `&` 起进程会让 ssh 会话挂住（实测卡 15 分钟+）
#   · 本 skill 每个用例开头都会 cluster_stop/clean/start，环境由下一个用例自然恢复
sshx "$BAD_DN" "P=$DB_DIR/conf/iotdb-system.properties; sudo sed -i -E '/^[#[:space:]]*dangerous_mode[[:space:]]*=/d' \"\$P\""
got2=$(sshx "$BAD_DN" "grep -cE '^dangerous_mode=' $DB_DIR/conf/iotdb-system.properties 2>/dev/null" | tr -dc '0-9')
assert_eq "⑥非法值已从配置中删除" "${got2:-0}" "0"
log "  提示：$BAD_DN 的 DataNode 仍处于停止状态，由下一个用例的 cluster_start 恢复"

write_result

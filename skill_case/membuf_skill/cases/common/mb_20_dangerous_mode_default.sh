#!/bin/bash
# MB-20 dangerous_mode 默认值与生效方式（重启生效，非热加载）
#
# 需求依据：docs/359 《V2.0.13.1-其他模块-配置管理-数据库风险模式-需求分析》
#   §3.1 配置表：dangerous_mode 默认 false，取值 true/false，**生效方式=重启生效**
#   §3.2 功能定义：dangerous_mode 默认为 false
#
# 三段：
#   ① 完全不配置 dangerous_mode + 9:1:1:1:1:1(64.3%) ⇒ 必须被限幅到 60% 并告警
#      （反证"默认值就是 false"）
#   ② 只改配置文件为 true、**不重启** ⇒ 仍按 false 处理（依旧限幅+告警）
#      （证明不是热加载）
#   ③ 重启后 ⇒ 按 true 处理（不限幅、无告警）（证明重启生效）
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../lib/common.sh"
source "$HERE/../../lib/mb.sh"
mb_load_env
mb_parse_args "$@"
mb_case_init MB-20
export MB_POSITIVE_EVIDENCE_FN=mb_evidence_alloc

DB=root.mb20
MB_MEM_PROPORTION="9:1:1:1:1:1"          # storage 9/14 = 64.3% > 60%
export MB_MEM_PROPORTION
export EXTRA_CONF=""                      # ① 完全不写 dangerous_mode

WARN_PAT='limited to 60% of the DataNode heap'
SUM=$(printf '%s' "$MB_MEM_PROPORTION" | tr ':' '\n' | awk '{s+=$1} END{print s}')
SEG=$(printf '%s' "$MB_MEM_PROPORTION" | cut -d: -f1)
SEGQ=$(printf '%s' "$MB_MEM_PROPORTION" | cut -d: -f2)

check_alloc(){
  local tag=$1 expect=$2  # expect: cap | raw
  local h w r M exp d ncap
  for h in "${DN[@]}"; do
    w=$(mb_alloc_log "$h" Write)
    tol=$(mb_alloc_tol "$h")
    if [ "${w:-0}" -le 0 ]; then fail "$tag $h 未读到 Write 分配值"; continue; fi
    ncap=$(mb_warn_cnt "$h" "$WARN_PAT")
    if [ "$expect" = "cap" ]; then
      exp=$(mb_expect_write "$h" "$MB_MEM_PROPORTION" cap)
      d=$(( w - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
      if [ "$d" -le "$tol" ]; then pass "$tag $h Write=$w = maxMemory×3/5（限幅生效，差 $d）"
      else fail "$tag $h Write: 实际=[$w] 期望限幅值≈[$exp]（差 $d）"; fi
      assert_ge "$tag $h 应打出 60% 限幅告警" "${ncap:-0}" 1
    else
      exp=$(mb_expect_write "$h" "$MB_MEM_PROPORTION" raw)
      d=$(( w - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
      if [ "$d" -le "$tol" ]; then pass "$tag $h Write=$w = maxMemory×${SEG}/${SUM}（未限幅，差 $d）"
      else fail "$tag $h Write: 实际=[$w] 期望按比例≈[$exp]（差 $d）"; fi
      assert_eq "$tag $h 不应出现 60% 限幅告警" "${ncap:-0}" "0"
    fi
  done
}

log "--- ① 不配置 dangerous_mode（默认值）+ ${MB_MEM_PROPORTION}（${SEG}/${SUM}）---"
mb_cluster_prepare
check_alloc "①默认" cap

log "--- 中间落盘 interim 结论（① 已完成）---"
write_result

log "--- ② 仅改配置为 dangerous_mode=true，不重启 ---"
export EXTRA_CONF="dangerous_mode=true"
cluster_write_conf
# 不重启，直接观察分配值与告警（应保持 ① 的状态）
check_alloc "②未重启" cap

log "--- ③ 重启后按 dangerous_mode=true 生效 ---"
# ⚠️ 必须 clean 再重启：mb_warn_cnt 统计的是累积日志，
#    不清日志会把 ①/② 阶段的限幅告警算进来，导致"不该有告警"的断言假失败。
cluster_stop; cluster_clean
cluster_write_conf; cluster_start
wait_cluster_ready || fail "③ 重启后集群未就绪"
check_alloc "③重启后" raw

write_result

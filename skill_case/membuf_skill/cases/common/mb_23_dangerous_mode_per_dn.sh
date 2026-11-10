#!/bin/bash
# MB-23 dangerous_mode 仅作用于当前 DataNode（不做集群广播）
#
# 需求依据：docs/359 §3.1 说明列：「仅针对当前DN。内部运维使用。」
#
# 设计：
#   ① 全部 DN 都不配 dangerous_mode + 9:1:1:1:1:1（64.3%）⇒ 全部被限幅（基线）
#   ② 只把**第一个 DN** 改成 dangerous_mode=true，其余保持默认，重启
#      ⇒ 被改的 DN 不限幅；其余 DN 仍限幅
#
# 判据：
#   · 目标 DN：Write = maxMemory×9/14 且无限幅告警
#   · 其余 DN：Write = maxMemory×3/5 且有限幅告警
#   · 若所有 DN 行为一致 ⇒ 说明配置被广播，与本需求不符
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../lib/common.sh"
source "$HERE/../../lib/mb.sh"
mb_load_env
mb_parse_args "$@"
mb_case_init MB-23
export MB_POSITIVE_EVIDENCE_FN=mb_evidence_alloc

DB=root.mb23
MB_MEM_PROPORTION="9:1:1:1:1:1"
export MB_MEM_PROPORTION
export EXTRA_CONF=""
WARN_PAT='limited to 60% of the DataNode heap'

SUM=$(printf '%s' "$MB_MEM_PROPORTION" | tr ':' '\n' | awk '{s+=$1} END{print s}')
SEG=$(printf '%s' "$MB_MEM_PROPORTION" | cut -d: -f1)
SEGQ=$(printf '%s' "$MB_MEM_PROPORTION" | cut -d: -f2)
TARGET="${DN[0]}"

alloc_of(){ # $1=host -> "write|warncnt"
  local h=$1 w n
  w=$(mb_alloc_log "$h" Write)
  n=$(mb_warn_cnt "$h" "$WARN_PAT")
  printf '%s|%s' "${w:-0}" "${n:-0}"
}

log "--- ① 基线：全部 DN 默认（不限幅开关关闭）---"
mb_cluster_prepare
for h in "${DN[@]}"; do
  IFS='|' read -r w n <<<"$(alloc_of "$h")"
  tol=$(mb_alloc_tol "$h")
  exp=$(mb_expect_write "$h" "$MB_MEM_PROPORTION" cap)
  d=$(( ${w:-0} - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
  if [ "$d" -le "$tol" ]; then pass "①基线 $h 已限幅 Write=${w}（差 $d）"
  else fail "①基线 $h 未按预期限幅：Write=${w} 期望≈[$exp]（差 $d）"; fi
done

log "--- 中间落盘 interim 结论（① 已完成）---"
write_result

log "--- ② 只改 $TARGET 一个 DN 为 dangerous_mode=true，其余不动 ---"
# ⚠️ clean 再改：mb_warn_cnt 统计累积日志，不清会把 ① 基线阶段的告警算进来
cluster_stop; cluster_clean
sshx "$TARGET" "P=$DB_DIR/conf/iotdb-system.properties; sudo sed -i -E '/^[#[:space:]]*dangerous_mode[[:space:]]*=/d' \"\$P\"; printf 'dangerous_mode=true\n' | sudo tee -a \"\$P\" >/dev/null"
# 回读确认只改了一个节点
n_on=0
for h in "${DN[@]}"; do
  v=$(sshx "$h" "grep -E '^dangerous_mode=' $DB_DIR/conf/iotdb-system.properties 2>/dev/null | tail -1 | cut -d= -f2-" | tr -d '\r')
  log "  $h dangerous_mode='${v:-<未配置>}'"
  [ "$v" = "true" ] && n_on=$((n_on+1))
done
assert_eq "②全集群只有 1 个 DN 配了 true" "$n_on" "1"

cluster_start
wait_cluster_ready || fail "②重启后集群未就绪"

log "--- ③ 逐节点核对：目标 DN 不限幅，其余仍限幅 ---"
for h in "${DN[@]}"; do
  IFS='|' read -r w n <<<"$(alloc_of "$h")"
  tol=$(mb_alloc_tol "$h")
  if [ "$h" = "$TARGET" ]; then
    exp=$(mb_expect_write "$h" "$MB_MEM_PROPORTION" raw)
    d=$(( ${w:-0} - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
    if [ "$d" -le "$tol" ]; then pass "③目标 DN $h 未限幅 Write=${w}（差 $d）"
    else fail "③目标 DN $h 仍被限幅：Write=${w} 期望≈[$exp]（差 $d）"; fi
    assert_eq "③目标 DN $h 不应有限幅告警" "$n" "0"
  else
    exp=$(mb_expect_write "$h" "$MB_MEM_PROPORTION" cap)
    d=$(( ${w:-0} - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
    if [ "$d" -le "$tol" ]; then pass "③其余 DN $h 仍限幅 Write=${w}（差 $d）"
    else fail "③其余 DN $h 未限幅：Write=${w} 期望≈[$exp]（差 $d）——配置疑似被广播"; fi
    assert_ge "③其余 DN $h 应仍有限幅告警" "$n" 1
  fi
done

write_result

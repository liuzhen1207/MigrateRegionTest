#!/bin/bash
# MB-21 60% 边界与超限限幅
#
# 需求依据：docs/359
#   §3.2：dangerous_mode=false 时，StorageEngine 占全部项总和的比例超过 60% 应被限制
#   §4  ：StorageEngine 占比 等于 60% 时通过，超过 60% 时失败
#
# 两段：
#   ① 边界 12:2:2:2:1:1（sum=20，storage=12/20 = **恰好 60%**）⇒ 不应限幅、不应告警
#   ② 超限 9:1:1:1:1:1（64.3%）⇒ 必须限幅到 maxMemory×3/5，且打出限幅告警
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../lib/common.sh"
source "$HERE/../../lib/mb.sh"
mb_load_env
mb_parse_args "$@"
mb_case_init MB-21
export MB_POSITIVE_EVIDENCE_FN=mb_evidence_alloc

DB=root.mb21
export EXTRA_CONF=""
WARN_PAT='limited to 60% of the DataNode heap'

verify(){
  local tag=$1 prop=$2 expect=$3 h w r M exp d ncap SUM SEG SEGQ
  SUM=$(printf '%s' "$prop" | tr ':' '\n' | awk '{s+=$1} END{print s}')
  SEG=$(printf '%s' "$prop" | cut -d: -f1)
  SEGQ=$(printf '%s' "$prop" | cut -d: -f2)
  log "  $tag 比例=$prop（sum=$SUM，storage=$SEG/$SUM=$(( SEG*100/SUM ))%，期望=$expect）"
  for h in "${DN[@]}"; do
    w=$(mb_alloc_log "$h" Write)
    tol=$(mb_alloc_tol "$h")
    if [ "${w:-0}" -le 0 ]; then fail "$tag $h 未读到 Write 分配值"; continue; fi
    ncap=$(mb_warn_cnt "$h" "$WARN_PAT")
    if [ "$expect" = "cap" ]; then
      exp=$(mb_expect_write "$h" "$prop" cap)
      d=$(( w - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
      if [ "$d" -le "$tol" ]; then pass "$tag $h Write=$w = maxMemory×3/5（已限幅，差 $d）"
      else fail "$tag $h Write: 实际=[$w] 期望限幅值≈[$exp]（差 $d）"; fi
      assert_ge "$tag $h 应打出限幅告警" "${ncap:-0}" 1
    else
      exp=$(mb_expect_write "$h" "$prop" raw)
      d=$(( w - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
      if [ "$d" -le "$tol" ]; then pass "$tag $h Write=$w = maxMemory×${SEG}/${SUM}（未限幅，差 $d）"
      else fail "$tag $h Write: 实际=[$w] 期望按比例≈[$exp]（差 $d）"; fi
      assert_eq "$tag $h 边界值不应触发限幅告警" "${ncap:-0}" "0"
    fi
  done
}

log "--- ① 边界：storage 占比恰好 60%（12:2:2:2:1:1）---"
export MB_MEM_PROPORTION="12:2:2:2:1:1"
mb_cluster_prepare
verify "①边界60%" "$MB_MEM_PROPORTION" raw

log "--- 中间落盘 interim 结论（① 已完成）---"
write_result

log "--- ② 超限：storage 占比 64.3%（9:1:1:1:1:1）---"
cluster_stop; cluster_clean
export MB_MEM_PROPORTION="9:1:1:1:1:1"
cluster_write_conf; cluster_start
wait_cluster_ready || fail "② 超限场景集群未就绪"
verify "②超限" "$MB_MEM_PROPORTION" cap

write_result

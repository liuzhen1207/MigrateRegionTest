#!/bin/bash
# MB-25 兼容性：升级前已配置 >60% 的用户如何平滑过渡
#
# 需求依据：docs/359 §3.3.1 兼容性要求
#   「升级前已将 StorageEngine 内存占比配置为超过 60% 的用户，
#     需修改内存比例，或显式配置 dangerous_mode=true。」
#
# 本用例模拟"存量用户升级"场景，覆盖需求给出的两条处置路径：
#   ① 升级后（配置仍为 >60% 且未设 dangerous_mode）
#      ⇒ 服务必须**仍能正常启动**（不能因兼容性直接起不来）
#      ⇒ 必须打出明确的限幅告警，让用户知道配置已被降级
#   ② 处置路径 A：把比例改为 ≤60% ⇒ 告警消失，按新比例分配
#   ③ 处置路径 B：显式配置 dangerous_mode=true ⇒ 恢复原比例分配
#
# 说明：依据实际实现（限幅 + WARN，而非拒绝启动），① 期望"启动成功 + 告警"；
#       若产品改为"拒绝启动"，则 ① 的断言会失败，正可用于跟踪该行为变化。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../lib/common.sh"
source "$HERE/../../lib/mb.sh"
mb_load_env
mb_parse_args "$@"
mb_case_init MB-25
export MB_POSITIVE_EVIDENCE_FN=mb_evidence_alloc

DB=root.mb25
export EXTRA_CONF=""
WARN_PAT='limited to 60% of the DataNode heap'
LEGACY="9:1:1:1:1:1"        # 存量用户配置：storage 64.3%
SAFE="12:2:2:2:1:1"         # 处理路径A：storage 恰好 60%

props(){ printf '%s' "$1" | tr ':' '\n' | awk '{s+=$1} END{print s}'; }
seg(){ printf '%s' "$1" | cut -d: -f1; }
segq(){ printf '%s' "$1" | cut -d: -f2; }

verify(){ local tag=$1 prop=$2 expect=$3 h w r M exp d n SUM SEG SEGQ
  SUM=$(props "$prop"); SEG=$(seg "$prop"); SEGQ=$(segq "$prop")
  for h in "${DN[@]}"; do
    w=$(mb_alloc_log "$h" Write)
    tol=$(mb_alloc_tol "$h")
    if [ "${w:-0}" -le 0 ]; then fail "$tag $h 未读到 Write 分配值"; continue; fi
    n=$(mb_warn_cnt "$h" "$WARN_PAT")
    case "$expect" in
      cap) exp=$(mb_expect_write "$h" "$prop" cap);;
      raw) exp=$(mb_expect_write "$h" "$prop" raw);;
      *) exp=$(mb_expect_write "$h" "$prop" cap);;
    esac
    d=$(( w - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
    if [ "$d" -le "$tol" ]; then pass "$tag $h Write=$w（期望≈[$exp]，差 $d）"
    else fail "$tag $h Write: 实际=[$w] 期望≈[$exp]（差 $d）"; fi
    if [ "$expect" = "raw" ]; then assert_eq "$tag $h 不应有限幅告警" "$n" "0"
    else assert_ge "$tag $h 应有限幅告警" "$n" 1; fi
  done
}

log "--- ① 模拟升级：存量配置 $LEGACY（64.3%）且未设 dangerous_mode ---"
export MB_MEM_PROPORTION="$LEGACY"
mb_cluster_prepare

up=$(sq 'show cluster;' 2>/dev/null | grep -cE 'Running|ReadOnly')
if [ "${up:-0}" -ge 8 ]; then
  pass "①存量配置升级后服务仍可正常启动（${up} 个节点 Running/ReadOnly）——兼容性达标"
else
  fail "①存量配置升级后服务起不来（仅 ${up} 个节点在线）——兼容性不达标，应改为限幅降级而非拒绝启动"
fi
verify "①升级后" "$LEGACY" cap

log "--- 中间落盘 interim 结论（① 已完成）---"
write_result

log "--- ② 处置路径 A：把比例改为恰好 60%（$SAFE）---"
cluster_stop; cluster_clean
export MB_MEM_PROPORTION="$SAFE"
cluster_write_conf; cluster_start
wait_cluster_ready || fail "② 路径A 集群未就绪"
verify "②路径A" "$SAFE" raw

log "--- ③ 处置路径 B：保留 $LEGACY，显式配置 dangerous_mode=true ---"
cluster_stop; cluster_clean
export MB_MEM_PROPORTION="$LEGACY"
export EXTRA_CONF="dangerous_mode=true"
cluster_write_conf; cluster_start
wait_cluster_ready || fail "③ 路径B 集群未就绪"
verify "③路径B" "$LEGACY" raw

write_result

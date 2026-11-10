#!/bin/bash
# MB-22 风险模式：dangerous_mode=true 时放行 >60%
#
# 需求依据：docs/359
#   §3.1：true 时允许 StorageEngine 占比超过 60%
#   §3.2：当其为 true 时，不执行上述 60% 上限检查
#   §4  ：开启风险模式后，StorageEngine 占比超过 60% 时通过
#
# 判据：
#   ① dangerous_mode=true + 9:1:1:1:1:1（64.3%）⇒ Write 必须 = maxMemory×9/14
#   ② 且**不得**出现 60% 限幅告警
#   ③ 集群正常可用（8/8），可写入可查询
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../lib/common.sh"
source "$HERE/../../lib/mb.sh"
mb_load_env
mb_parse_args "$@"
mb_case_init MB-22
export MB_POSITIVE_EVIDENCE_FN=mb_evidence_alloc

DB=root.mb22
MB_MEM_PROPORTION="9:1:1:1:1:1"     # storage 64.3% > 60%
export MB_MEM_PROPORTION
export EXTRA_CONF="dangerous_mode=true"
WARN_PAT='limited to 60% of the DataNode heap'

SUM=$(printf '%s' "$MB_MEM_PROPORTION" | tr ':' '\n' | awk '{s+=$1} END{print s}')
SEG=$(printf '%s' "$MB_MEM_PROPORTION" | cut -d: -f1)
SEGQ=$(printf '%s' "$MB_MEM_PROPORTION" | cut -d: -f2)

log "--- ① 风险模式 + ${MB_MEM_PROPORTION}（storage ${SEG}/${SUM}）---"
mb_cluster_prepare
assert_contains "①配置已写入 dangerous_mode=true" "$(sshx "${DN[0]}" "grep -E '^dangerous_mode=' $DB_DIR/conf/iotdb-system.properties | tail -1" | tr -d '\r')" '=true'

log "--- ② 集群可用性 ---"
up=$(sq 'show cluster;' 2>/dev/null | grep -cE 'Running|ReadOnly')
assert_ge "②风险模式下集群仍可用" "${up:-0}" 8

log "--- ③ 分配值必须按比例、且无 60% 限幅告警 ---"
for h in "${DN[@]}"; do
  w=$(mb_alloc_log "$h" Write)
  tol=$(mb_alloc_tol "$h")
  if [ "${w:-0}" -le 0 ]; then fail "③$h 未读到 Write 分配值"; continue; fi
  exp=$(mb_expect_write "$h" "$MB_MEM_PROPORTION" raw)
  d=$(( w - exp )); [ "$d" -lt 0 ] && d=$(( -d ))
  if [ "$d" -le "$tol" ]; then pass "③$h Write=$w = maxMemory×${SEG}/${SUM}（风险模式未限幅，差 $d）"
  else fail "③$h Write: 实际=[$w] 期望≈[$exp]（差 $d）——风险模式下仍被限幅"; fi
  assert_eq "③$h 不应出现 60% 限幅告警" "$(mb_warn_cnt "$h" "$WARN_PAT")" "0"
done

log "--- ④ 风险模式下读写可用 ---"
sq "create database $DB;" >/dev/null 2>&1
sq "insert into $DB.d1(time,s1) values(1,1);" >/dev/null 2>&1
assert_contains "④风险模式下可写入并查询" "$(sq "select count(*) from $DB.d1;" 2>/dev/null | tr -d ' ')" '1'

write_result

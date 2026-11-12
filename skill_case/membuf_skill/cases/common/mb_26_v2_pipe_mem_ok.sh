#!/bin/bash
# MB-26 IoTConsensusV2 在**合理 Pipe 内存比例**下的复跑（MB-14 的对照场景）
#
#   背景：MB-14 沿用 MB-03 的极端比例 1:2000:1:1:1:1，六段中第 5 段（Pipe 池）只占 1/2005 ≈ 0.05%，
#   实测 Pipe 池总容量仅 10.71 MB。IoTConsensusV2 的复制走 Pipe 框架（IoTConsensusV2AsyncSink），
#   TsFile 传输必然抛 PipeRuntimeOutOfMemoryException（重试 10 次仍失败），syncLag 永久不归零。
#   该现象已判定为**配置不足、非产品缺陷**：
#     · docs/DEFECT_RC11_PIPE_MEMORY.md 顶部「研发结论：Pipe 内存池配置得过小 ⇒ 属配置不足」
#     · docs/KNOWN_ISSUES.md §3
#
#   本用例用同一套 V2 流程，仅把比例改为 1:100:1:1:10:1：
#     write=1  read=100  schema=1  consensus=1  pipe=10  auto=1   合计 114 份
#     → pipe ≈ 8.8%（对比 MB-14 的 0.05%），read 仍占 87.7% 以保留内存压力意图
#   目的：验证「Pipe 内存充足时，V2 复制与 syncLag 能正常收敛」，与 MB-14 形成对照。
#
#   判据（与 MB-14 相同）：
#     ① 协议配置生效；② V2 专属 syncLag 指标（iot_consensus_v2）存在且能归零；
#     ③ 自动刷盘发生；④ 数据点数正确；⑤ 逐个停 DN 后副本一致性通过。
#   ⚠️ 协议配置值必须写规范值 `...iot.IoTConsensusV2`，写成 `...pipe.IoTConsensusV2`
#      会导致 ConfigNode 不创建 consensus pipe（见 docs/DEFECT_F-10.md）。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../lib/common.sh"
source "$HERE/../../lib/mb.sh"
mb_load_env
DATA_CONSENSUS="IoTConsensusV2"
mb_parse_args "$@"
DATA_CONSENSUS="IoTConsensusV2"
mb_consensus_class
mb_case_init MB-26
export MB_POSITIVE_EVIDENCE_FN=mb_evidence_flush

# 对照 MB-14：Pipe 段 1 -> 10（0.05% -> 8.8%）
MB_MEM_PROPORTION="${MB_MEM_PROPORTION:-1:100:1:1:10:1}"
MB_FLUSH_PROPORTION="0.4"
export MB_MEM_PROPORTION MB_FLUSH_PROPORTION
DB=root.mb26
ROWS=${MB26_ROWS:-1200}
export EXTRA_CONF=""

log "  协议: $CONS_TAG ($CONSENSUS_CLASS)"
log "  内存比例: $MB_MEM_PROPORTION（对照 MB-14 的 1:2000:1:1:1:1，Pipe 段 1 -> 10）"
mb_cluster_prepare
for h in "${DN[@]}"; do
  got=$(sshx "$h" "grep -E '^data_region_consensus_protocol_class=' $DB_DIR/conf/iotdb-system.properties | cut -d= -f2-" | tr -d '\r')
  assert_eq "①$h 协议配置" "$got" "$CONSENSUS_CLASS"
done

mb_make_tree_db "$DB" 1 text
flush0=$(mb_flush_all)
log "--- 写入 ${ROWS} 点，等自动刷盘 ---"
ok=$(mb_bulk_text "$DB" d1 "$ROWS" 1); ok=${ok%% *}
assert_ge "写入语句成功数" "${ok:-0}" 1
if mb_wait_flush "$flush0" "$FLUSH_WAIT_SEC"; then pass "③自动刷盘发生"; else fail "③等 ${FLUSH_WAIT_SEC}s 未观察到自动刷盘"; fi

# V2 专属指标存在性（Prometheus 或直连）
n_v2=$(prom_series 'iot_consensus_v2{type="syncLag",cluster="'"$PROMETHEUS_CLUSTER"'",nodeType="DATANODE"}' 2>/dev/null | wc -l | tr -d ' ')
if [ "${n_v2:-0}" -eq 0 ]; then
  n_v2=0
  for h in "${DN[@]}"; do
    c=$(curl -s -m 8 "http://$h:$DN_METRIC_PORT/metrics" 2>/dev/null | grep -c 'iot_consensus_v2.*type="syncLag"')
    n_v2=$(( n_v2 + ${c:-0} ))
  done
fi
log "  iot_consensus_v2 syncLag series 数=$n_v2"
assert_ge "②V2 专属 syncLag 指标存在" "${n_v2:-0}" 1

sq 'flush;' >/dev/null 2>&1
sleep 5
assert_eq "④数据点数正确" "$(mb_count_all "$DB")" "$ROWS"

mb_case_finish "$(mb_data_sql "$DB" d1)" tree

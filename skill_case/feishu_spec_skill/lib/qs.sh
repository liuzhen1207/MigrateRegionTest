#!/bin/bash
# =============================================================================
# 查询调度（Query Scheduler / MLFQ）专项 —— 测试 helper
#   依赖 lib/common.sh（集群控制/断言）与 lib/perf.sh（iot-benchmark 封装）
#
# 需求依据（飞书文档 V1.0.0.1-计算模块-查询调度）：
#   - 短查询不被长查询阻塞、长查询不饿死、无需手动指定优先级
#   - DriverTask 五状态：Ready/Blocked/Running/Finished/Aborted
#   - Worker 线程数可配（query_thread_count），启动后不可变
#   - 时间片让出（driver_task_execution_time_slice_in_ms，默认 200ms，每层 (level+1)×该值）
#   - 超时中断（query_timeout_threshold）、主动取消 + 同查询级联 abort
#   - 多级反馈队列 + 队列累计执行时间（LEVEL_TIME_MULTIPLIER=2 硬编码）
# =============================================================================

QS_LONG_DB="${QS_LONG_DB:-root.test.qs_0}"
QS_LONG_QUERY_TIMEOUT_SEC="${QS_LONG_QUERY_TIMEOUT_SEC:-1800}"

# ---------------------------------------------------------------------------
# 调度器配置
#   qs_set_scheduler_conf <threads> <timeout_ms> [time_slice_ms]
# ---------------------------------------------------------------------------
qs_set_scheduler_conf(){
  QS_QUERY_THREADS="${1:-1}"
  QS_QUERY_TIMEOUT_MS="${2:-60000}"
  QS_TIME_SLICE_MS="${3:-200}"
  log "  调度器配置: query_thread_count=$QS_QUERY_THREADS, query_timeout_threshold=${QS_QUERY_TIMEOUT_MS}ms, time_slice=${QS_TIME_SLICE_MS}ms"
}

qs_apply_scheduler_conf(){
  local h
  for h in "${DN[@]}"; do
    sshx "$h" "sudo sed -i '/^query_thread_count=/d;/^query_timeout_threshold=/d;/^driver_task_execution_time_slice_in_ms=/d' $DB_DIR/conf/iotdb-system.properties" >/dev/null 2>&1
    sshx "$h" "printf 'query_thread_count=%s\nquery_timeout_threshold=%s\ndriver_task_execution_time_slice_in_ms=%s\n' '$QS_QUERY_THREADS' '$QS_QUERY_TIMEOUT_MS' '$QS_TIME_SLICE_MS' | sudo tee -a $DB_DIR/conf/iotdb-system.properties >/dev/null" >/dev/null 2>&1
  done
  log "  调度参数已写入 ${#DN[@]} 个 DataNode"
}

qs_verify_conf_effective(){
  local h="${DN[0]}" threads got
  threads=$(sshx "$h" "grep '^query_thread_count=' $DB_DIR/conf/iotdb-system.properties | cut -d= -f2-")
  assert_eq "①conf 中 query_thread_count" "$threads" "$QS_QUERY_THREADS"
  got=$(qs_scheduler_threads "$h")
  # 仅作观察：RC11 的调度线程 ThreadGroup 是 "ScheduleThreads"（DriverScheduler:115），
  # 物理线程名与文档里的 DriverTaskThread 不一致，不能据此判失败；
  # REQ-04「线程数可配」由上面的 conf 断言覆盖。
  log "  调度相关线程数（/proc comm）= ${got:-?}（观察项）"
}

# ---------------------------------------------------------------------------
# benchmark 结果 CSV 解析（查询场景：LATEST_POINT 行）
#   同一个 CSV 有两段矩阵：吞吐矩阵在前、延迟矩阵在后，行首都是 <Operation>,
#   因此取**最后一次**出现该 Operation 的行作为延迟数据。
# ---------------------------------------------------------------------------
qs_csv_pick(){
  local csv=$1 op=$2 field=$3
  [ -f "$csv" ] || { echo 0; return; }
  local col=2
  case "$field" in
    AVG)  col=2 ;;
    P99)  col=$(awk -F, '/^Operation,AVG,MIN/{for(i=1;i<=NF;i++){h=$i;gsub(/[ \r]/,"",h);if(h=="P99"){print i;exit}}}' "$csv") ;;
    P999) col=$(awk -F, '/^Operation,AVG,MIN/{for(i=1;i<=NF;i++){h=$i;gsub(/[ \r]/,"",h);if(h=="P999"){print i;exit}}}' "$csv") ;;
    OKOP) col=2 ;;
  esac
  [ -z "${col:-}" ] && col=10
  if [ "$field" = "OKOP" ]; then
    # 吞吐矩阵在前：OKOP 取**第一个**匹配行的第 2 列（okOp，整数）
    awk -F, -v o="$op" '$1==o && !done {v=$2; done=1} END{gsub(/[ \r]/,"",v); printf "%d\n", (v==""?0:v)}' "$csv"
  else
    awk -F, -v o="$op" -v c="$col" '$1==o && NF>=c {v=$c} END{gsub(/[ \r]/,"",v); print (v==""?0:v)}' "$csv"
  fi
}

# ---------------------------------------------------------------------------
# 造数（benchmark 写入）
#   qs_load_data <db> <devices> <sensors> <loop> [tag]
# 说明：db 由 benchmark 的 GROUP_NAME_PREFIX 决定（写入 root.<prefix>...）
# ---------------------------------------------------------------------------
qs_load_data(){
  local dev=${1:-200} sen=${2:-10} loop=${3:-1000} tag="${4:-load}"
  perf_check || return 1
  local dir; dir=$(mktemp -d /tmp/qsd_XXXX)
  perf_gen_conf "$dir" "100:0:0:0:0:0:0:0:0:0:0:0" \
    DEVICE_NUMBER="$dev" SENSOR_NUMBER="$sen" LOOP="$loop" \
    GROUP_NAME_PREFIX="qs_" IS_DELETE_DATA=true DATA_SEED=1234
  log "  造数配置: $(grep -E '^(DEVICE_NUMBER|SENSOR_NUMBER|LOOP|BATCH_SIZE_PER_WRITE|TEST_MAX_TIME|IS_DELETE_DATA)=' "$dir/config.properties" | tr '\n' ' ')"
  local csvdir="$PERF_BM_DIR/data/csvOutput" before csv
  before=$(ls -t "$csvdir"/*.csv 2>/dev/null | head -1)
  ( cd "$PERF_BM_DIR" && timeout "${PERF_TIMEOUT:-3600}" bash benchmark.sh -cf "$dir" >"$dir/run.log" 2>&1 )
  csv=$(ls -t "$csvdir"/*.csv 2>/dev/null | head -1)
  if [ -z "$csv" ] || [ "$csv" = "$before" ]; then
    fail "【造数 $tag】未产生 benchmark 结果 CSV"; tail -5 "$dir/run.log" 2>/dev/null | sed 's/^/    /'; return 1
  fi
  QS_LOAD_OK=$(qs_csv_pick "$csv" "INGESTION" "OKOP")
  log "  造数完成 [$tag]: 期望 $(( dev * sen * loop )) 点，实际 okPoint=${QS_LOAD_OK:-?}"
  # ⚠️ 必须刷盘：用例随后会重启集群（cluster_stop 含 pkill），
  #    内存里未落盘的数据会丢 —— 实测 800 万点造完后重启只剩 Empty set，
  #    导致"数据已就绪"断言失败、超时用例也因空集瞬间返回而不触发。
  log "  强制刷盘并等待落盘完成..."
  sq "flush;" >/dev/null 2>&1
  sleep 8
  assert_ge "造数成功" "${QS_LOAD_OK:-0}" 1
}

# ---------------------------------------------------------------------------
# 长查询（后台）
#   qs_long_query_bg <sql> [out_file]
# 结果文件: start_ms<TAB>end_ms<TAB>rc<TAB>elapsed_ms
# ---------------------------------------------------------------------------
qs_long_query_bg(){
  local sql=${1:-"select count(s) from $QS_LONG_DB.**"} out=${2:-/tmp/qs_long.txt}
  : >"$out"
  (
    local t0 t1 rc
    t0=$(date +%s%3N)
    timeout "$QS_LONG_QUERY_TIMEOUT_SEC" "$CLI" -h "${DN[0]}" -p "$DN_RPC_PORT" -u "$DB_USER" -pw "$ROOT_PW" -e "$sql" >/tmp/qs_long_sql.out 2>&1
    rc=$?
    t1=$(date +%s%3N)
    printf '%s\t%s\t%s\t%s\n' "$t0" "$t1" "$rc" "$(( t1 - t0 ))" >"$out"
  ) &
  QS_LONG_PID=$!
  log "  长查询已启动(pid=$QS_LONG_PID): ${sql:0:70}..."
}

qs_long_query_wait(){
  local out=${1:-/tmp/qs_long.txt}
  [ -n "${QS_LONG_PID:-}" ] && wait "$QS_LONG_PID" 2>/dev/null
  if [ -s "$out" ]; then
    local t0 t1 rc el
    IFS=$'\t' read -r t0 t1 rc el <"$out"
    log "  长查询结束: rc=$rc 耗时=$(( el / 1000 ))s"
    QS_LONG_MS="$el"; QS_LONG_RC="$rc"
  else
    log "  长查询未产生结果文件"
    QS_LONG_MS="-1"; QS_LONG_RC="-1"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 短查询延迟（benchmark 最新点查询）
#   qs_bench_latest <tag> [mix] [devices]
# 结果写入全局: QS_LAT_AVG / QS_LAT_P99 / QS_LAT_OPS
# ---------------------------------------------------------------------------
qs_bench_latest(){
  local tag=${1:-probe} mix="${2:-0:0:0:0:0:0:0:0:100:0:0:0}" dev="${3:-${PERF_DEVICES_QUERY:-200}}"
  perf_check || return 1
  local dir; dir=$(mktemp -d /tmp/qsq_XXXX)
  perf_gen_conf "$dir" "$mix" \
    DEVICE_NUMBER="$dev" SENSOR_NUMBER=10 LOOP="${QS_QUERY_LOOP:-1}" \
    GROUP_NAME_PREFIX="qs_" IS_DELETE_DATA=false DATA_SEED=1234
  log "  查询配置: $(grep -E '^(DEVICE_NUMBER|SENSOR_NUMBER|LOOP|OPERATION_PROPORTION)=' "$dir/config.properties" | tr '\n' ' ')"
  local csvdir="$PERF_BM_DIR/data/csvOutput" before csv
  before=$(ls -t "$csvdir"/*.csv 2>/dev/null | head -1)
  ( cd "$PERF_BM_DIR" && timeout "${PERF_TIMEOUT:-1800}" bash benchmark.sh -cf "$dir" >"$dir/run.log" 2>&1 )
  csv=$(ls -t "$csvdir"/*.csv 2>/dev/null | head -1)
  if [ -z "$csv" ] || [ "$csv" = "$before" ]; then
    fail "【$tag】未产生 benchmark 结果 CSV"; tail -5 "$dir/run.log" 2>/dev/null | sed 's/^/    /'; return 1
  fi
  QS_LAT_AVG=$(qs_csv_pick "$csv" "LATEST_POINT" "AVG")
  QS_LAT_P99=$(qs_csv_pick "$csv" "LATEST_POINT" "P99")
  QS_LAT_OPS=$(qs_csv_pick "$csv" "LATEST_POINT" "OKOP")
  log "  短查询压测[$tag]: okOperation=${QS_LAT_OPS:-0} AVG=${QS_LAT_AVG:-0}ms P99=${QS_LAT_P99:-0}ms"
  echo "$csv" >"$OUTDIR/last_query_csv.txt" 2>/dev/null || true
}

# 统计总点数：`select count(*) from db.**` 会**每个序列返回一列**，
# 必须把所有数值列求和，不能只取第一列（早期只取第一列，把 4000 万点读成了 1000）。
qs_total_points(){
  local db=${1:-$QS_LONG_DB}
  sq "select count(*) from $db.**;" 2>/dev/null \
    | grep -E '^\|' \
    | awk -F'|' '{for(i=2;i<=NF;i++){gsub(/[^0-9]/,"",$i); if($i!="") s+=$i}} END{printf "%d", s}'
}

# 设备数（show devices 行数；比 count(*) 稳定，后者每序列返回一列、输出可达数千列）
#   ⚠️ 两个坑：
#     ① 集群刚启动时查询会报错，错误框只有 1 行 `|`，单次查询会误判成"只有 1 个设备"；
#     ② 必须重试（最多 ~60s），并把最后一次原始输出落盘，便于定位到底是什么错误。
qs_device_count(){
  local db=${1:-$QS_LONG_DB} i n best=0 raw=""
  for i in $(seq 1 20); do
    raw=$(sq "show devices $db.**;" 2>/dev/null)
    n=$(printf '%s\n' "$raw" | grep -cE '^\|')
    [ -z "$n" ] && n=0
    [ "$n" -gt "$best" ] && best=$n
    [ "$best" -ge 10 ] && break
    sleep 3
  done
  if [ "$best" -lt 10 ]; then
    printf '%s\n' "$raw" > "/tmp/qs_devcount_fail_$$.out" 2>/dev/null
    log "  [warn] 设备数仍为 ${best}，原始输出见 /tmp/qs_devcount_fail_$$.out" >&2
    printf '%s\n' "$raw" | head -6 | sed 's/^/      /'  >&2
  fi
  echo "$best"
}

# 序列数
qs_series_count(){
  local db=${1:-$QS_LONG_DB}
  sq "select count(*) from $db.**;" 2>/dev/null | grep -E '^\|' | head -1 \
    | awk -F'|' '{print NF-2}'
}

# ---------------------------------------------------------------------------
# 观测：调度线程数 / 日志 / 指标
# ---------------------------------------------------------------------------
qs_scheduler_threads(){
  # RC11 源码里调度线程的 ThreadGroup 名为 "ScheduleThreads"（DriverScheduler:115），
  # 物理线程名不是文档里的 DriverTaskThread。用 /proc/<pid>/task/*/comm 统计最稳。
  local h=${1:-${DN[0]}} pid
  pid=$(sshx "$h" "pgrep -f 'com.timecho.iotdb.DataNode' | head -1")
  [ -z "$pid" ] && { echo 0; return; }
  sshx "$h" "sudo cat /proc/$pid/task/*/comm 2>/dev/null | grep -icE 'schedule|driver'"
}

qs_count_log(){
  local pat=$2 h=${1:-${DN[0]}}
  sshx "$h" "sudo grep -c '$pat' $DB_DIR/logs/log_datanode_all.log 2>/dev/null"
}

qs_grep_log(){
  local pat=$2 n=${3:-5} h=${1:-${DN[0]}}
  sshx "$h" "sudo grep -E '$pat' $DB_DIR/logs/log_datanode_all.log 2>/dev/null | tail -$n | cut -c1-190"
}

qs_metrics_list(){
  local h=${1:-${DN[0]}}
  sshx "$h" "curl -s -m 6 http://$h:$DN_METRIC_PORT/metrics 2>/dev/null | grep -oE '^[a-z_]*(driver|scheduler|query)[a-z_]*' | sort -u | head -20"
}

# ---------------------------------------------------------------------------
# 统一集群准备：停 → (可选清理) → 写配置 → 应用调度参数 → 起 → 等就绪 → 校验
#   反复踩过的坑都在这里处理：
#     ① 残留进程会让 cluster_clean 保守跳过 → 先 pkill 再 clean，并校验 data 目录真的没了
#        （否则 CN 保留旧节点注册，新 DN 报 `Reject DataNode registration`）
#     ② CN 端口就绪 ≠ 可接受 DN 注册 → cluster_start 内部已加初始化等待与 DN 重试
#   QS_SKIP_CLEAN=1 时复用现有集群，只重启应用参数（调试用，快很多）
# ---------------------------------------------------------------------------
QS_EXTRA_CONF=""
qs_add_conf(){ QS_EXTRA_CONF="${QS_EXTRA_CONF}${1}"$'\n'; }

qs_prepare_cluster(){
  export USE_FRAMEWORK=0
  cluster_stop >/dev/null 2>&1
  if [ "${QS_SKIP_CLEAN:-0}" != "1" ]; then
    local _h
    for _h in $(printf '%s\n' "${CN[@]}" "${DN[@]}" | sort -u); do
      sshx "$_h" "sudo pkill -9 -f 'com\.timecho\.iotdb' >/dev/null 2>&1 || true" >/dev/null 2>&1
    done
    sleep 8
    cluster_clean >/dev/null 2>&1 || warn "cluster_clean 未完全成功"
    for _h in $(printf '%s\n' "${CN[@]}" "${DN[@]}" | sort -u); do
      if sshx "$_h" "test -d $CN_DB_DIR/data" 2>/dev/null; then
        warn "$_h data 目录仍在，强制再删"
        sshx "$_h" "sudo rm -rf $CN_DB_DIR/data $CN_DB_DIR/logs" >/dev/null 2>&1
      fi
    done
  else
    log "  跳过清理，仅重启以应用调度参数"
  fi
  cluster_write_conf >/dev/null 2>&1
  qs_apply_scheduler_conf
  if [ -n "${QS_EXTRA_CONF:-}" ]; then
    local _h _kv
    for _h in "${DN[@]}"; do
      while IFS= read -r _kv; do
        [ -z "$_kv" ] && continue
        local _k="${_kv%%=*}"
        sshx "$_h" "sudo sed -i '/^${_k}=/d' $DB_DIR/conf/iotdb-system.properties" >/dev/null 2>&1
        sshx "$_h" "printf '%s\n' '$_kv' | sudo tee -a $DB_DIR/conf/iotdb-system.properties >/dev/null" >/dev/null 2>&1
      done <<< "$QS_EXTRA_CONF"
    done
    log "  额外配置已写入: $(printf '%s ' "$QS_EXTRA_CONF")"
  fi
  cluster_start >/dev/null 2>&1
  if ! wait_cluster_ready; then
    fail "集群未就绪"
    return 1
  fi
  sleep 10   # 就绪后短暂稳定期，避免紧接着的元数据查询拿到空结果
  qs_verify_conf_effective
  return 0
}

# 简单查询探针：返回查询结果里是否包含指定文本
qs_sql(){
  sq "$1"
}

# 当前 show queries 条数（去掉表头/分隔行）
qs_query_count(){
  # 【修正 2026-11-13】原实现 `grep -cE '^\|'` 统计以 | 开头的行，但 show queries 的输出里
  #   ① 有 1 行表头（| Time | QueryId | ...）
  #   ② show queries 这条语句**自身**也会出现在结果中（Statement 列 = "show queries"）
  # 因此即使没有任何其它查询，计数也恒为 2，导致 QS-07/QS-12 的
  # `assert_eq "SHOW QUERIES 无残留" "$(qs_query_count)" "0"` 永远失败。
  # 改为解析 `Total line number = N` 并减去自身 1 行；解析不到时退回行数-表头。
  local out total c
  out=$(sq "show queries;" 2>/dev/null)
  total=$(printf '%s\n' "$out" | grep -oE 'Total line number = [0-9]+' | head -1 | grep -oE '[0-9]+$')
  if [ -n "${total:-}" ]; then
    c=$((total - 1))            # 去掉 show queries 自身
    [ "$c" -lt 0 ] && c=0
    echo "$c"
    return 0
  fi
  c=$(printf '%s\n' "$out" | grep -cE '^\|')
  c=$((c - 2))                  # 去掉表头 + 自身
  [ "$c" -lt 0 ] && c=0
  echo "$c"
}

# DN 进程 RSS（KB）
qs_dn_rss_kb(){
  local h=${1:-${DN[0]}}
  sshx "$h" "ps -eo rss,args | grep '[c]om.timecho.iotdb.DataNode' | awk '{print \$1}' | head -1"
}

# ---------------------------------------------------------------------------
# 确保有数据：设备数不足则**现场造数**（造完即 flush）
#   为什么放在用例里而不是外部预置：集群重启后 `show devices` 会有一段时间
#   返回**空集**（不是报错，实测重启后 60s 仍为空、数分钟后才可见），
#   外部先造数再重启的写法会稳定失败。用例内"重启后再造"最稳。
# ---------------------------------------------------------------------------
qs_ensure_data(){
  # 【修正 2026-11-13】本函数被 12 个用例以 DEVS=$(qs_ensure_data) 调用，
  # 必须保证 stdout 只有最终数字。原来内部 log / qs_load_data 都写 stdout，
  # 导致 DEVS 捕获到「日志行 + 数字」，随后 assert_ge "${DEVS}" 100 必然失败
  # （实测：造数其实成功，造数后设备数=201，但断言拿到的是整段日志）。
  # 故内部输出全部重定向到 stderr，只剩最后一行 echo 走 stdout。
  # 另把 min_dev 默认值由 10 提到 100，与多数用例 assert_ge ... 100 的阈值一致。
  local min_dev="${1:-100}" dev
  dev=$(qs_device_count "$QS_LONG_DB")
  if [ "${dev:-0}" -lt "$min_dev" ]; then
    log "  数据不足（设备数=${dev:-0} < ${min_dev}），现场造数..." >&2
    qs_load_data 200 10 300 "auto-load" >&2 || { warn "造数失败" >&2; echo "${dev:-0}"; return 1; }
    dev=$(qs_device_count "$QS_LONG_DB")
    log "  造数后设备数=${dev:-0}" >&2
  fi
  echo "${dev:-0}"
}

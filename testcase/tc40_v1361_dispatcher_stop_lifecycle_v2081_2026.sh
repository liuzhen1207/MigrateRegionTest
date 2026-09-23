#!/usr/bin/env bash

# IoTConsensus dispatcher lifecycle regression for region REMOVE/EXTEND.
# The case blocks one source-to-target consensus channel, fills the replication
# pipeline, removes the unreachable peer, then immediately adds the same peer back.
# Known issue: TDB-417 (removeSyncLogChannel may leave a blocked LogDispatcher
# alive and create a zombie/duplicate Dispatcher after Region re-add).
# https://plm.infra.timecho.com/iterations?itemId=940&productId=1

set -u

cur_dir="$(cd "$(dirname "$0")" && pwd)"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name="$(awk -F= '$1=="u_name" {print $2}' "$conf_file")"
db_dir="$(awk -F= '$1=="db_dir" {print $2}' "$conf_file")"
cli_dir="$(awk -F= '$1=="client_db_dir" {print $2}' "$conf_file")"
v_cur_db="$(awk -F= '$1=="v_cur_db" {print $2}' "$conf_file")"
query_ip="$(awk 'NR==1 {print; exit}' "$nodeinfo_dir/datanode.txt")"
cn_num=3
dn_num=5
testcase_res_db="$(awk -F= '$1=="testcase_res_db" {print $2}' "$conf_file")"
testcase_res_port="$(awk -F= '$1=="testcase_res_port" {print $2}' "$conf_file")"
testcase_ip="$(grep '^test_ip=' "$conf_file" | awk -F. '{print $4}')"
SCRIPT_NAME="$(basename "$0")"
tc_num="${SCRIPT_NAME%%_*}"
tc_num="${tc_num#tc}"
test_begin_sec="$(date +%s)"
run_id="$(date +%Y%m%d_%H%M%S)"
out_dir="${cur_dir}/dispatcher_lifecycle_${run_id}"
mkdir -p "$out_dir"

fail_count=0
pass_count=0
writer_pids=""
target_ip=""
target_id=""
source_ip=""
source_id=""
region_id=""
source_stopped=0
target_stopped=0
network_blocked=0

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$out_dir/case.log"
}

pass_check() {
  pass_count=$((pass_count + 1))
  log "PASS: $1"
}

fail_check() {
  fail_count=$((fail_count + 1))
  log "FAIL: $1"
}

assert_true() {
  if "$@"; then
    pass_check "$ASSERT_DESC"
  else
    fail_check "$ASSERT_DESC"
  fi
}

run_cli() {
  local host=$1
  local sql=$2
  local output=$3
  "$cli_dir/sbin/start-cli.sh" -u root -pw TimechoDB@2021 -h "$host" -timeout 3600 -e "$sql" >"$output" 2>&1
}

set_prop() {
  local ip=$1 key=$2 value=$3
  ssh "${u_name}@${ip}" "file='${db_dir}/conf/iotdb-system.properties'; if grep -Eq '^[[:space:]#]*${key}[[:space:]]*=' \"\$file\"; then sed -i -E 's|^[[:space:]#]*${key}[[:space:]]*=.*|${key}=${value}|' \"\$file\"; else echo '${key}=${value}' >> \"\$file\"; fi" </dev/null
}

set_case_conf() {
  local seed_cn_ip
  seed_cn_ip="$(head -n 1 "$nodeinfo_dir/confignode.txt")"

  # Keep the complete node lists on every run; other cases may leave a shortened list.
  head -n "$cn_num" "$nodeinfo_dir/total_node.txt" > "$nodeinfo_dir/confignode.txt"
  head -n "$dn_num" "$nodeinfo_dir/total_datanode.txt" > "$nodeinfo_dir/datanode.txt"
  head -n "$dn_num" "$nodeinfo_dir/total_datanode_port.txt" > "$nodeinfo_dir/datanode_port.txt"
  seed_cn_ip="$(head -n 1 "$nodeinfo_dir/confignode.txt")"

  exec 3<"$nodeinfo_dir/confignode.txt"
  while IFS= read -r ip <&3; do
    [[ -z "$ip" ]] && continue
    set_prop "$ip" cn_seed_config_node "${seed_cn_ip}:10710"
    set_prop "$ip" cn_internal_address "$ip"
    set_prop "$ip" cn_metric_reporter_list PROMETHEUS
    set_prop "$ip" cn_metric_level IMPORTANT
    set_prop "$ip" cn_metric_prometheus_reporter_port 9081
    set_prop "$ip" schema_replication_factor 3
    set_prop "$ip" data_replication_factor 2
    set_prop "$ip" schema_region_group_extension_policy CUSTOM
    set_prop "$ip" data_region_group_extension_policy CUSTOM
    set_prop "$ip" default_schema_region_group_num_per_database 5
    set_prop "$ip" default_data_region_group_num_per_database 5
  done
  exec 3<&-

  exec 3<"$nodeinfo_dir/datanode.txt"
  while IFS= read -r ip <&3; do
    [[ -z "$ip" ]] && continue
    set_prop "$ip" dn_seed_config_node "${seed_cn_ip}:10710"
    set_prop "$ip" dn_internal_address "$ip"
    set_prop "$ip" dn_rpc_address "$ip"
    set_prop "$ip" data_region_consensus_protocol_class org.apache.iotdb.consensus.iot.IoTConsensus
    set_prop "$ip" schema_replication_factor 3
    set_prop "$ip" data_replication_factor 2
    set_prop "$ip" schema_region_group_extension_policy CUSTOM
    set_prop "$ip" data_region_group_extension_policy CUSTOM
    set_prop "$ip" default_schema_region_group_num_per_database 5
    set_prop "$ip" default_data_region_group_num_per_database 5
    set_prop "$ip" datanode_memory_proportion 1:5:1:1:1:1
    set_prop "$ip" data_region_iot_max_pending_batches_num 1
    set_prop "$ip" data_region_iot_max_log_entries_num_per_batch 8
    set_prop "$ip" data_region_iot_max_size_per_batch 65536
    set_prop "$ip" dn_metric_reporter_list PROMETHEUS
    set_prop "$ip" dn_metric_prometheus_reporter_port 9091
  done
  exec 3<&-
}

validate_case_conf() {
  local seed_cn_ip ip prop expected actual
  seed_cn_ip="$(head -n 1 "$nodeinfo_dir/confignode.txt")"
  [[ -n "$seed_cn_ip" ]] || { log "configuration error: confignode.txt is empty"; return 1; }
  [[ "$(wc -l < "$nodeinfo_dir/confignode.txt")" -eq "$cn_num" ]] || { log "configuration error: expected ${cn_num} ConfigNodes"; return 1; }
  [[ "$(wc -l < "$nodeinfo_dir/datanode.txt")" -eq "$dn_num" ]] || { log "configuration error: expected ${dn_num} DataNodes"; return 1; }
  while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    for prop in cn_seed_config_node cn_internal_address; do
      expected="$([[ "$prop" = cn_seed_config_node ]] && echo "${seed_cn_ip}:10710" || echo "$ip")"
      actual="$(ssh "${u_name}@${ip}" "awk -F= -v k='${prop}' '\$1==k {print \$2; exit}' '${db_dir}/conf/iotdb-system.properties'" </dev/null 2>/dev/null || true)"
      [[ "$actual" = "$expected" ]] || { log "configuration error: ${ip} ${prop}=${actual}, expected ${expected}"; return 1; }
    done
  done < "$nodeinfo_dir/confignode.txt"
  while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    for prop in dn_seed_config_node dn_internal_address dn_rpc_address; do
      case "$prop" in
        dn_seed_config_node) expected="${seed_cn_ip}:10710" ;;
        *) expected="$ip" ;;
      esac
      actual="$(ssh "${u_name}@${ip}" "awk -F= -v k='${prop}' '\$1==k {print \$2; exit}' '${db_dir}/conf/iotdb-system.properties'" </dev/null 2>/dev/null || true)"
      [[ "$actual" = "$expected" ]] || { log "configuration error: ${ip} ${prop}=${actual}, expected ${expected}"; return 1; }
    done
  done < "$nodeinfo_dir/datanode.txt"
  log "configuration validation passed: ${cn_num} ConfigNodes, ${dn_num} DataNodes, seed=${seed_cn_ip}:10710"
}

start_cluster() {
  sh -x "$cur_dir/../clean_env/stop_cluster.sh" >>"$out_dir/start_cluster.log" 2>&1 || true
  sh -x "$cur_dir/../clean_env/clean_cluster.sh" >>"$out_dir/start_cluster.log" 2>&1 || true
  head -n "$cn_num" "$nodeinfo_dir/total_node.txt" > "$nodeinfo_dir/confignode.txt"
  head -n "$dn_num" "$nodeinfo_dir/total_datanode.txt" > "$nodeinfo_dir/datanode.txt"
  head -n "$dn_num" "$nodeinfo_dir/total_datanode_port.txt" > "$nodeinfo_dir/datanode_port.txt"
  sh -x "$cur_dir/../clean_env/reset_conf.sh" >>"$out_dir/start_cluster.log" 2>&1 || true
  set_case_conf
  validate_case_conf || return 1
  sh -x "$cur_dir/../prepare_env/start_cluster.sh" 1 "$((cn_num + dn_num))" >>"$out_dir/start_cluster.log" 2>&1
}

wait_node_state() {
  local ip=$1 state=$2 timeout=$3 start now count
  start=$(date +%s)
  while :; do
    run_cli "$query_ip" "show datanodes;" "$out_dir/show_datanodes.out" || true
    count=$(awk -F'|' -v ip="$ip" -v state="$state" '
      {v3=$3; v4=$4; gsub(/[[:space:]]/, "", v3); gsub(/[[:space:]]/, "", v4)}
      v4==ip && tolower(v3)==tolower(state) {n++}
      END {print n+0}' "$out_dir/show_datanodes.out")
    [[ "$count" -gt 0 ]] && return 0
    now=$(date +%s)
    ((now - start >= timeout)) && return 1
    sleep 2
  done
}

show_regions() {
  run_cli "$query_ip" "show regions;" "$out_dir/show_regions.out"
}

show_target_regions() {
  run_cli "$target_ip" "show regions;" "$out_dir/target_show_regions.out"
}

choose_region_pair() {
  show_regions || return 1
  awk -F'|' '
    function trim(v) {gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); return v}
    /^[+|]/ {
      rid=trim($2); typ=trim($3); stat=trim($4); db=trim($5); series=trim($6); timeslot=trim($7); dn=trim($8); ip=trim($9); role=trim($12)
      if (rid ~ /^[0-9]+$/ && typ == "DataRegion" && stat == "Running" && db == "root.test.g_0" && (series+0 > 0 || timeslot+0 > 0)) {
        if (role == "Leader" && !(rid in leader)) leader[rid]=dn ":" ip
        if (role == "Follower" && !(rid in follower) && follower[rid] != leader[rid]) follower[rid]=dn ":" ip
      }
    }
    END {for (rid in leader) if (follower[rid] != "") {print rid, leader[rid], follower[rid]; exit}}
  ' "$out_dir/show_regions.out" > "$out_dir/region_pair.out"
  [[ -s "$out_dir/region_pair.out" ]] || return 1
  read -r region_id pair_one pair_two < "$out_dir/region_pair.out"
  # Keep the replication direction: source is the Leader, target is a Follower.
  source_id="${pair_one%%:*}"
  source_ip="${pair_one#*:}"
  target_id="${pair_two%%:*}"
  target_ip="${pair_two#*:}"
  while IFS= read -r candidate; do
    if [[ -n "$candidate" && "$candidate" != "$target_ip" && "$candidate" != "$source_ip" ]]; then
      query_ip="$candidate"
      break
    fi
  done < "$nodeinfo_dir/datanode.txt"
  log "selected DataRegion=${region_id}, target=${target_id}@${target_ip}, source=${source_id}@${source_ip}"
  log "selected control DataNode=${query_ip}"
  return 0
}

metric_value() {
  local name=$1 type peer
  case "$name" in
    IoTConsensus)
      type=cachedRequestInMemoryQueue
      peer="logDispatcher-${target_ip}:10760"
      ;;
    IoTConsensusQueue)
      type=pipelineNum
      peer="logDispatcher-${target_ip}:10760"
      ;;
    IoTConsensusSync)
      type=syncLag
      peer=ioTConsensusServerImpl
      ;;
    *) echo NA; return ;;
  esac
  ssh "${u_name}@${source_ip}" "curl -sf http://127.0.0.1:9091/metrics 2>/dev/null | awk -v rid='DataRegion[${region_id}]' -v peer='${peer}' -v typ='${type}' 'index(\$0, \"region=\\\"\" rid \"\\\"\") && index(\$0, \"name=\\\"\" peer \"\\\"\") && index(\$0, \"type=\\\"\" typ \"\\\"\") {print \$NF; found=1; exit} END {if (!found) print \"NA\"}'" 2>/dev/null | awk '/^-?[0-9]+([.][0-9]+)?([Ee][-+]?[0-9]+)?$/ {printf "%.0f\n", $1; found=1} END {if (!found) print "NA"}'
}

metric_is_number() {
  [[ "$1" =~ ^-?[0-9]+$ ]]
}

dispatcher_count() {
  local pid
  pid=$(ssh "${u_name}@${source_ip}" "sudo ps -eo pid,args | awk '\$0 ~ /com.timecho.iotdb.DataNode -s/ {print \$1; exit}'" 2>/dev/null | awk 'NR==1 {print $1}')
  [[ "$pid" =~ ^[0-9]+$ ]] || { echo NA; return; }
  ssh "${u_name}@${source_ip}" "sudo jstack ${pid} 2>/dev/null | grep -E 'IoTDB-LogDispatcher-DataRegion\\[${region_id}\\]-' | wc -l" 2>/dev/null | awk '{if ($1 ~ /^[0-9]+$/) print $1; else print "NA"}'
}

wait_dispatcher_count() {
  local timeout=$1 start now count=NA
  start=$(date +%s)
  while :; do
    count=$(dispatcher_count)
    metric_is_number "$count" && [[ "$count" -gt 0 ]] && { echo "$count"; return 0; }
    now=$(date +%s)
    ((now - start >= timeout)) && { echo "$count"; return 1; }
    sleep 2
  done
}

dispatcher_log_count() {
  local pattern=$1
  ssh "${u_name}@${source_ip}" "sudo grep -E -c -- '${pattern}' '${db_dir}/logs/log_datanode_all.log' 2>/dev/null || echo 0" 2>/dev/null | tail -n 1 | awk '{if ($1 ~ /^[0-9]+$/) print $1; else print 0}'
}

stale_rpc_count() {
  ssh "${u_name}@${source_ip}" "sudo grep -E -c -- '(AsyncIoTConsensusServiceClient|Cannot sync logs to peer|Can not send .*peer).*${target_ip}' '${db_dir}/logs/log_datanode_all.log' 2>/dev/null || echo 0" 2>/dev/null | tail -n 1 | awk '{if ($1 ~ /^[0-9]+$/) print $1; else print 0}'
}

wait_log_count_increase() {
  local pattern=$1 before=$2 timeout=$3 start now current
  start=$(date +%s)
  while :; do
    current=$(dispatcher_log_count "$pattern")
    ((current > before)) && return 0
    now=$(date +%s)
    ((now - start >= timeout)) && return 1
    sleep 1
  done
}

wait_pipeline_pressure() {
  local timeout=$1 start now queue sync pipeline pressure
  start=$(date +%s)
  while :; do
    queue=$(metric_value IoTConsensus)
    pipeline=$(metric_value IoTConsensusQueue)
    sync=$(metric_value IoTConsensusSync)
    pressure=0
    if metric_is_number "$queue" && [[ "$queue" -gt 0 ]]; then pressure=1; fi
    if metric_is_number "$pipeline" && [[ "$pipeline" -gt 0 ]]; then pressure=1; fi
    if metric_is_number "$sync" && [[ "$sync" -gt 0 ]]; then pressure=1; fi
    if [[ "$pressure" -eq 1 ]]; then
      log "pipeline metrics while peer unreachable: queue=${queue}, pipeline=${pipeline}, sync=${sync}"
      return 0
    fi
    now=$(date +%s)
    ((now - start >= timeout)) && {
      log "pipeline metrics did not show pressure within ${timeout}s: queue=${queue}, pipeline=${pipeline}, sync=${sync}"
      return 1
    }
    sleep 2
  done
}

wait_region_absent() {
  local start now
  start=$(date +%s)
  while :; do
    if ! show_target_regions; then
      now=$(date +%s)
      ((now - start >= 600)) && return 1
      sleep 2
      continue
    fi
    if awk -F'|' -v rid="$region_id" -v dn="$target_id" '
      function trim(v) {gsub(/[[:space:]]/, "", v); return v}
      {if (trim($2)==rid && trim($8)==dn) found=1}
      END {exit found}' "$out_dir/target_show_regions.out"; then
      return 0
    fi
    now=$(date +%s)
    ((now - start >= 600)) && return 1
    sleep 2
  done
}

wait_region_present() {
  local start now
  start=$(date +%s)
  while :; do
    if ! show_target_regions; then
      now=$(date +%s)
      ((now - start >= 600)) && return 1
      sleep 3
      continue
    fi
    if awk -F'|' -v rid="$region_id" -v dn="$target_id" '
      function trim(v) {gsub(/[[:space:]]/, "", v); return v}
      {if (trim($2)==rid && trim($8)==dn && trim($4)=="Running") found=1}
      END {exit !found}' "$out_dir/target_show_regions.out"; then
      return 0
    fi
    now=$(date +%s)
    ((now - start >= 600)) && return 1
    sleep 3
  done
}

start_node() {
  local ip=$1
  local stamp
  stamp=$(date +%Y%m%d_%H%M%S)
  ssh "${u_name}@${ip}" "source /etc/profile; nohup sudo '${db_dir}/sbin/start-datanode.sh' -H '${db_dir}/dispatcher_${stamp}.hprof' >/tmp/dispatcher_start_${stamp}.out 2>&1 &"
  wait_node_state "$ip" Running 180
}

stop_node() {
  local ip=$1
  ssh "${u_name}@${ip}" "sudo '${db_dir}/sbin/stop-datanode.sh'" || true
  wait_node_state "$ip" Unknown 120
}

block_target_consensus() {
  log "blocking ${source_ip} -> ${target_ip}:10760 to simulate an unreachable consensus peer"
  if ssh "${u_name}@${source_ip}" "sudo iptables -I OUTPUT -p tcp -d '${target_ip}' --dport 10760 -j DROP"; then
    network_blocked=1
    return 0
  fi
  return 1
}

unblock_target_consensus() {
  if [[ "$network_blocked" = 1 ]]; then
    ssh "${u_name}@${source_ip}" "sudo iptables -D OUTPUT -p tcp -d '${target_ip}' --dport 10760 -j DROP" >/dev/null 2>&1 || true
    network_blocked=0
  fi
}

start_writers() {
  local worker rows=420 offset sql_file
  for worker in 1 2 3 4; do
    sql_file="$out_dir/writer_${worker}.sql"
    : > "$sql_file"
    for offset in $(seq 1 420); do
      printf 'insert into root.test.g_0(time,s_0) values(%s,%s);\n' "$((1700000000000 + worker * 100000 + offset))" "$((worker * 1000 + offset))" >> "$sql_file"
    done
    ("$cli_dir/sbin/start-cli.sh" -u root -pw TimechoDB@2021 -h "$query_ip" -timeout 3600 < "$sql_file" >"$out_dir/writer_${worker}.out" 2>&1) &
    writer_pids="${writer_pids} $!"
  done
}

stop_writers() {
  local pid
  for pid in $writer_pids; do
    kill "$pid" 2>/dev/null || true
  done
  writer_pids=""
}

cleanup() {
  stop_writers
  unblock_target_consensus
  if [[ -n "$target_ip" && "$target_stopped" = 1 ]]; then
    start_node "$target_ip" >/dev/null 2>&1 || true
    target_stopped=0
  fi
  if [[ -n "$source_ip" && "$source_stopped" = 1 ]]; then
    start_node "$source_ip" >/dev/null 2>&1 || true
    source_stopped=0
  fi
}
trap cleanup EXIT

log "starting ${SCRIPT_NAME}"
if ! start_cluster; then
  log "FAIL: cluster startup/configuration validation failed; see ${out_dir}/start_cluster.log"
  exit 1
fi

run_cli "$query_ip" "create database root.test.g_0;" "$out_dir/create_database.out" || true
run_cli "$query_ip" "create timeseries root.test.g_0.s_0 with datatype=INT32,encoding=PLAIN;" "$out_dir/create_timeseries.out" || true
run_cli "$query_ip" "insert into root.test.g_0(time,s_0) values(1700000000000,0);" "$out_dir/seed_insert.out" || true

if ! choose_region_pair; then
  fail_check "found a two-replica DataRegion for root.test.g_0"
else
  source_log="${db_dir}/logs/log_datanode_all.log"
  timeout_before=$(dispatcher_log_count "Dispatcher for Peer.*${target_ip}.*didn.t stop after 30s")
  exit_before=$(dispatcher_log_count "Dispatcher for Peer.*${target_ip}.*exits")
  memory_before=$(metric_value IoTConsensus)
  queue_before=$(metric_value IoTConsensusQueue)
  sync_before=$(metric_value IoTConsensusSync)
  log "baseline memory: total=${memory_before}, queue=${queue_before}, sync=${sync_before}; starts/exits=${exit_before}"

  if ! block_target_consensus; then
    fail_check "temporarily blocked source-to-target consensus traffic"
  fi
  start_writers
  if wait_pipeline_pressure 60; then
    pass_check "replication pipeline entered back-pressure while consensus peer was unreachable"
  else
    fail_check "replication pipeline entered back-pressure while consensus peer was unreachable"
  fi
  sleep 5

  remove_output="$out_dir/remove_region.out"
  run_cli "$query_ip" "remove region ${region_id} from ${target_id};" "$remove_output" || true
  cat "$remove_output" >> "$out_dir/case.log"
  if grep -Eqi 'Msg: The statement is executed successfully|successfully submitted' "$remove_output" \
      && ! grep -Eqi 'failed to submit|not in Running status|exception|error' "$remove_output"; then
    pass_check "REMOVE REGION accepted while consensus traffic was unreachable"
  else
    fail_check "REMOVE REGION accepted while consensus traffic was unreachable"
  fi
  stop_writers

  if wait_region_absent; then
    pass_check "removed Region ${region_id} from target DataNode ${target_id}"
  else
    fail_check "removed Region ${region_id} from target DataNode ${target_id}"
  fi

  exit_timeout=20
  if wait_log_count_increase "Dispatcher for Peer.*${target_ip}.*exits" "$exit_before" "$exit_timeout"; then
    pass_check "old dispatcher exited within ${exit_timeout}s"
  else
    fail_check "old dispatcher exited within ${exit_timeout}s"
  fi
  timeout_after=$(dispatcher_log_count "Dispatcher for Peer.*${target_ip}.*didn.t stop after 30s")
  if [[ "$timeout_after" -eq "$timeout_before" ]]; then
    pass_check "no dispatcher 30s stop timeout was logged"
  else
    fail_check "no dispatcher 30s stop timeout was logged"
  fi

  stale_before=$(stale_rpc_count)
  sleep 5
  stale_after=$(stale_rpc_count)
  if [[ "$stale_after" -eq "$stale_before" ]]; then
    pass_check "delayed RPC/retry callbacks stopped after dispatcher removal"
  else
    fail_check "delayed RPC/retry callbacks stopped after dispatcher removal"
  fi

  memory_after=$(metric_value IoTConsensus)
  queue_after=$(metric_value IoTConsensusQueue)
  sync_after=$(metric_value IoTConsensusSync)
  if metric_is_number "$memory_before" && metric_is_number "$queue_before" && metric_is_number "$sync_before" \
      && metric_is_number "$memory_after" && metric_is_number "$queue_after" && metric_is_number "$sync_after" \
      && [[ "$memory_after" = "$memory_before" && "$queue_after" = "$queue_before" && "$sync_after" = "$sync_before" ]]; then
    pass_check "IoTConsensus memory returned to the pre-pressure baseline"
  elif [[ "$memory_after" = NA && "$queue_after" = NA ]] \
      && { [[ "$sync_after" = NA ]] || { metric_is_number "$sync_after" && [[ "$sync_after" -eq 0 ]]; }; }; then
    pass_check "IoTConsensus peer metrics were cleared after Region removal"
  elif metric_is_number "$memory_after" && metric_is_number "$queue_after" && metric_is_number "$sync_after"; then
    fail_check "IoTConsensus memory returned exactly to the pre-pressure baseline"
  else
    fail_check "IoTConsensus memory metrics were unavailable after removal"
  fi

  unblock_target_consensus
  log "restarting target and immediately extending Region ${region_id}"
  extend_output="$out_dir/extend_region.out"
  run_cli "$query_ip" "extend region ${region_id} to ${target_id};" "$extend_output" || true
  cat "$extend_output" >> "$out_dir/case.log"
  if grep -Eqi 'Msg: The statement is executed successfully|successfully submitted' "$extend_output" \
      && ! grep -Eqi 'failed to submit|exception|error' "$extend_output"; then
    pass_check "EXTEND REGION accepted after dispatcher removal"
  else
    fail_check "EXTEND REGION accepted after dispatcher removal"
  fi
  if wait_region_present; then
    pass_check "same Region was re-added to the target DataNode"
  else
    fail_check "same Region was re-added to the target DataNode"
  fi

  thread_count=$(wait_dispatcher_count 30 || true)
  if metric_is_number "$thread_count" && [[ "$thread_count" -eq 1 ]]; then
    pass_check "exactly one dispatcher thread exists after re-add"
  else
    fail_check "exactly one dispatcher thread exists after re-add (observed ${thread_count})"
  fi

  timeout_final=$(dispatcher_log_count "Dispatcher for Peer.*${target_ip}.*didn.t stop after 30s")
  if [[ "$timeout_final" -eq "$timeout_after" ]]; then
    pass_check "no additional delayed 30s dispatcher timeout appeared after re-add"
  else
    fail_check "no additional delayed 30s dispatcher timeout appeared after re-add"
  fi

  global_timeout_before=$(dispatcher_log_count "didn.t stop after 30s")
  log "stopping source DataNode to exercise global LogDispatcher.stop"
  stop_node "$source_ip"
  source_stopped=1
  sleep 5
  global_timeout_after=$(dispatcher_log_count "didn.t stop after 30s")
  if [[ "$global_timeout_after" -eq "$global_timeout_before" ]]; then
    pass_check "global LogDispatcher.stop completed without a 30s timeout"
  else
    fail_check "global LogDispatcher.stop completed without a 30s timeout"
  fi
  start_node "$source_ip"
  source_stopped=0
fi

test_end_sec=$(date +%s)
elapsed=$((test_end_sec - test_begin_sec))
if [[ "$fail_count" -eq 0 ]]; then
  result=true
  log "${SCRIPT_NAME}: PASS (${pass_count} checks, ${elapsed}s)"
else
  result=false
  log "${SCRIPT_NAME}: FAIL (${pass_count} passed, ${fail_count} failed, ${elapsed}s)"
fi

if [[ -n "$testcase_res_db" && -n "$testcase_res_port" ]]; then
  "$cli_dir/sbin/start-cli.sh" -h "$testcase_res_db" -p "$testcase_res_port" -u root -pw TimechoDB@2021 \
    -e "insert into root.autotest.ip${testcase_ip}(time,commitID,tc_num,tc_name,tc_result,tc_elapsed_time) aligned values(now(),'${v_cur_db}',${tc_num},'${SCRIPT_NAME}',${result},${elapsed});" \
    >"$out_dir/result_insert.out" 2>&1 || true
fi

exit 0

# Known Issues

对应清单：本地 `/home/ubuntu/workdir/codex_work/ip3/KNOWN_ISSUES.md` 与测试机 `cluster@172.20.70.3:/data1/iotdb/testcase/MigrateRegionTest/testcase/KNOWN_ISSUES.md`。两份清单于 2026-10-12 对齐；缺陷详情以所链接的 PLM 条目为准，运行结果以测试输出为准。

| Test case | Issue | Known symptom |
| --- | --- | --- |
| `tc19_con_mig_1readonly_1unknown_to_running.sh` | [TDB-68](https://plm.infra.timecho.com/iterations?productId=1&itemId=234) | **Related symptom observed on V2.0.12.1 RC8 build `ebaf9da` (2026-10-20).** After CN leader switch during DataRegion[1] migration, both the restored AddRegionPeer procedure (pid18) and a newly created procedure (pid25) completed successfully. The migration itself completed; this run did not reproduce TDB-68's rollback/fail plus later success symptom. The same run transferred an 8.82 GB snapshot in 9m24s; see the related throughput issue [TDB-75](https://plm.infra.timecho.com/iterations?productId=1&itemId=241). |
| `tc109_RMDN_2bm_stop_dn_remove_unknown_v2081_2026.sh` | 2026-10-13 known behavior (engineering confirmed) | Immediately after stopping DN7, the first asynchronous `REMOVE DATANODE 7` can choose stale coordinator state and leave DN7 `Unknown` with four Region replicas after migrations settle. Re-submit the same removal once; judge success only when DN7 disappears and data checks pass. The 2026-10-13 run failed on the first attempt; recovery by a second request has not yet been verified in that run. |
| `tc117_RMDN_no17_adding_dn_readonly.sh` | [V2-1215](https://pingcode.timecho.com/pjm/workitems/uJsEBtHy) | `REMOVE DATANODE` may remain stuck when an Adding peer becomes ReadOnly. |
| `tc23_v1361_reconstruct_repeatelist_v2081_2026.sh` | [TDB-383](https://plm.infra.timecho.com/iterations?productId=1&itemId=894) | **Verified fixed on V2.0.12.1 RC3 (2026-09-22).** Duplicate Region IDs are skipped at the ConfigNode entry point; only one parent procedure is submitted per unique Region and target DataNode, with reconstruction and consistency checks passing. |
| `tc27_v1361_reconstruct_parser_v2081_2026.sh` | [TDB-385](https://plm.infra.timecho.com/iterations?productId=1&itemId=897) | **Verified fixed on V2.0.12.1 RC3 (2026-09-22).** ConfigNode skips non-existent Region IDs and processes valid IDs in the same request; the CLI succeeds without leaking `IllegalArgumentException`, `305`, or `Fail to connect to any config node`. |
| `tc30_v1361_remove_regions_from_readonly_v2081_2026.sh` | [TDB-396](https://plm.infra.timecho.com/iterations?productId=1&itemId=908) | `REMOVE REGION` rejects a ReadOnly target DataNode with `Target DataNode 7 is not in Running status`; removal is expected to succeed when the remaining replicas can safely complete the membership change. |
| `tc24_v1361_reconstruct_normal_v2081_2026.sh` | [TDB-406](https://plm.infra.timecho.com/iterations?itemId=919&productId=1) | **Reproduced on 2026-09-23.** IoTConsensus migration can omit a TsFile already in `closing`; `syncLag=0` and a successful snapshot do not prevent the target replica from losing historical data. |
| `tc53_mig_comping.sh` | [TDB-406](https://plm.infra.timecho.com/iterations?itemId=919&productId=1) | **Observed on V2.0.12.1 RC4 (2026-09-29).** During compaction and migration, the post-migration offline-DataNode checks each reported 2,000 differing device rows. This is consistent with TDB-406's missing historical TsFile symptom and needs log-level confirmation before treating it as the same defect. |
| `tc40_v1361_dispatcher_stop_lifecycle_v2081_2026.sh` | [TDB-417](https://plm.infra.timecho.com/iterations?itemId=940&productId=1) | **Reproduced on V2.0.12.1 RC3 (2026-09-23).** `removeSyncLogChannel` reports cleanup success but can leave the blocked `LogDispatcher` alive past 20 seconds, logs `didn't stop after 30s`, and creates duplicate/zombie Dispatcher threads after the same Region is re-added. |
| `tc31_mig_sr_create_ts.sh` | [TDB-462](https://plm.infra.timecho.com/iterations?productId=1&itemId=1015) | **Reproduced on V2.0.12.1 (2026-10-08).** Concurrent SchemaRegion migration and million-view `CREATE VIEW` can cause the JDBC driver to retry the whole SQL after partial batch success; duplicate paths then produce error 302 and only 230,000 of 1,000,000 views remain. Failed runs now preserve CN/DN logs under `testcase/logs_backup/`. |
| `tc58_mig_sr_create_ts_repeat_migration.sh` | [TDB-462](https://plm.infra.timecho.com/iterations?productId=1&itemId=1015) | **Mixed results on V2.0.12.1 RC6 build `7ae8713e` (2026-10-12).** The 11:07 run failed with error 302 and 160,000/1,000,000 views after two overlapping migrations. The 15:15 run passed with three overlapping migrations and 1,000,000/1,000,000 views. The failure is valid symptom evidence even though it did not meet the script's three-migration stress threshold; the passing run alone does not establish that the intermittent defect is fixed. The defect was reproduced on build `aaf460d` on 2026-10-08. |

### TDB-462 — reproduced on 2026-10-08

- Test script: `testcase/tc31_mig_sr_create_ts.sh` on `172.20.70.3`; deployed data directory `v20121rc5_1003_aaf460d` (commit `aaf460d`).
- Environment: 3 ConfigNodes, 5 DataNodes, SchemaRegion replication factor 3; one million source timeseries and one million expected logical views.
- Reproduction: migrate SchemaRegion[0] from DN3 to DN4, start the million-view `CREATE VIEW` in the background, then migrate the same Region DN5 to DN3 and DN6 to DN5 before view creation finishes.
- Result: all three migrations report success, but `CREATE VIEW` returns mixed error 302 and the final view count is 230,000. The error output includes `Path ... already exist` and `The consensus group SchemaRegion[0] doesn't exist`.
- Engineering analysis for the `aaf460d` source identifies inconsistent retry handling: a failed 10,000-view batch can encounter `NO_AVAILABLE_REGION_GROUP` (906), while the upper layer treats 906 as retryable and the JDBC driver resends the whole SQL. Previously successful views are submitted again and collide with existing paths. The plan's saved replica list may also remain stale across successive migrations. Verify the configured batch size and exact request sequence when reproducing.
- CN 172.20.70.4 logged a leader transfer failure (`DIFFERENT_LEADER`, current leader DN4) at 11:46:07.714. DN3 (172.20.70.4) and DN4 (172.20.70.26) logged `MeasurementAlreadyExistException` during logical-view state-machine writes at 11:46:08.833 and 11:46:08.817. These messages alone do not prove duplicate application of the same Raft log.
- PLM issue: [TDB-462](https://plm.infra.timecho.com/iterations?productId=1&itemId=1015).
- Test output: `testcase/tc31_mig_sr_create_ts_2026_10_08_11_42_36.out`; full archived evidence: `tc31_mig_sr_create_ts_defect/logs/tc31_mig_sr_create_ts_20261008_bundle.tar.gz` in the agent workspace.
- On failure, the test script archives each configured CN/DN log directory before the final cluster cleanup. Per-node archives and a combined bundle are saved under `testcase/logs_backup/tc31_mig_sr_create_ts_<timestamp>/` and `testcase/logs_backup/tc31_mig_sr_create_ts_<timestamp>.tar.gz`.

#### tc58 regression case and follow-up

- Script: `testcase/tc58_mig_sr_create_ts_repeat_migration.sh` on `172.20.70.3`; the script is present in the automation suite and records results under testcase number 58. This suite also has other `tc58_*` scripts, so use the full script name to distinguish them.
- Valid reproduction on `v20121rc5_1003_aaf460d` (2026-10-08): migrations `3 -> 4`, `5 -> 3`, and `6 -> 5` all overlapped `CREATE VIEW`; SQL returned 302 with duplicate-path errors, and 830,000 of 1,000,000 views remained. Output: `testcase/tc58_mig_sr_create_ts_repeat_migration_fixed_20261008_1700.out`; logs: `testcase/logs_backup/tc58_mig_sr_create_ts_repeat_migration_20261008_165727.tar.gz`.
- RC6 build `v20121rc6_1010_7ae8713e` (2026-10-12, 09:25 run): two migrations overlapped; `CREATE VIEW` succeeded and all 1,000,000 views existed, but the script's three-migration stress threshold was not met. Output: `testcase/tc58_mig_sr_create_ts_repeat_migration_2026_10_12_09_25_28.out`.
- RC6 build `v20121rc6_1010_7ae8713e` (2026-10-12, 11:07 run): two migrations overlapped; SQL returned 302 with duplicate-path and missing-`SchemaRegion[0]` messages, and only 160,000 of 1,000,000 views remained. This is a real failure during migration, despite missing the script's three-migration stress threshold. Output: `testcase/tc58_mig_sr_create_ts_repeat_migration_2026_10_12_11_07_41.out`; logs: `testcase/logs_backup/tc58_mig_sr_create_ts_repeat_migration_20261012_111111.tar.gz`.
- RC6 build `v20121rc6_1010_7ae8713e` (2026-10-12, 15:15 run): all three migrations (`3 -> 4`, `5 -> 3`, `6 -> 5`) overlapped `CREATE VIEW` and completed. The SQL returned success (`create_rc=0`), the final view and source counts were both 1,000,000, the failure log was empty, and the case reported `pass`. This is a passing run under the script's three-migration criterion, not proof that the earlier RC6 symptom was fixed. Output: `testcase/tc58_mig_sr_create_ts_repeat_migration_2026_10_12_15_15_38.out`.

### TDB-406 — reproduced on 2026-09-23

- Test script: `tc24_v1361_reconstruct_normal_v2081_2026.sh` on `172.20.70.3`.
- Reproduction: IoTConsensus migration snapshot skipped a TsFile that had entered `closing` while its asynchronous close was still pending. At 11:35:25.195, `1790134510893-3-0-0.tsfile` began async close on `.27`; DataRegion[12] began taking a snapshot at 11:35:25.580; the TsFile finished flushing at 11:35:25.921.
- The target `.30` later lacked the file from compaction input. After stopping `.27`, 20 devices were missing 42,830 points. `syncLag=0` only confirmed later WAL synchronization; it did not show that the snapshot included the closing file.
- Version caveat: the run directory was `v20121rc3_0921_130557c`, with runtime BuildInfo `130557c`; confirm whether this build contains the RC4 fix listed in PLM.

### TDB-417 — reproduced on 2026-09-23

- Test script: `tc40_v1361_dispatcher_stop_lifecycle_v2081_2026.sh`.
- Run command: `nohup bash -x tc40_v1361_dispatcher_stop_lifecycle_v2081_2026.sh > 0923.out 2>&1`.
- Version: TimechoDB V2.0.12.1 RC3, deployment `v20121rc3_0921_130557c`.
- Reproduction: select a DataRegion with `source=Leader` and `target=Follower`, block source-to-target consensus traffic, generate writes, remove the target Region, then immediately add it back.
- Observed in `dispatcher_lifecycle_20260923_104801/case.log`: `9 passed, 3 failed`; the failures were old Dispatcher not exiting within 20 seconds, a 30-second stop timeout, and two Dispatcher threads after re-add.
- Source DataNode log confirms the first Dispatcher started at `10:50:01`, logged `didn't stop after 30s` at `10:50:42`, and a second Dispatcher started at `10:55:34`; both remained until source DataNode shutdown.
- Evidence directory: `dispatcher_lifecycle_20260923_104801/`.

## Verification updates

### TDB-383 — verified fixed on 2026-09-22

- Version: TimechoDB V2.0.12.1 RC3, deployment `v20121rc3_0921_130557c`.
- Request: `RECONSTRUCT REGION 0,1,3,4,6,14,16,0,1,3,4,6,14,16 ON 7;`.
- ConfigNode leader logs recorded seven `Skip duplicate Region ID` messages for IDs `0,1,3,4,6,14,16`.
- Only seven parent `ReconstructRegionProcedure` records were submitted (pid `20,21,22,24,26,28,30`), with no duplicate `(RegionId, target=7)` pair; all seven completed successfully.
- After completion, `show migrations` was empty; five stop-DataNode query diffs were `v_diff_tree=0`, sync lag stayed at zero for 60 seconds, replica counts matched expectations, and NPE checks were zero.
- Test output: `testcase/0922.out`.
- Cluster log backup: `v20121rc3_0921_130557c/tc23_evidence_2026_09_22_11_14_07/`.
- Full test record: [TDB-383 test record](https://plm.infra.timecho.com/docs/407).

### TDB-385 — verified fixed on 2026-09-22

- Version: TimechoDB V2.0.12.1 RC3, deployment `v20121rc3_0921_130557c`.
- Test result: `tc27_v1361_reconstruct_parser_v2081_2026.sh` passed in 464 seconds.
- Both `RECONSTRUCT REGION 17700,9999 ON 7` and the mixed invalid/valid Region-ID request returned `Msg: The statement is executed successfully.`.
- Neither CLI output contained `IllegalArgumentException`, error code `305`, nor `Fail to connect to any config node`.
- All ConfigNode logs were checked. They contain `Skip non-existent Region ID 17700`, and no `ReconstructRegionProcedure` record contains Region ID `17700`.
- Test output: `testcase/tc27_v1361_reconstruct_parser_v2081_2026_2026_09_22_11_30_54.out`.
- CLI and ConfigNode evidence: `testcase/tc27_reconstruct_all_invalid_ids.out`, `testcase/tc27_reconstruct_invalid_and_valid_ids.out`, and `testcase/tc27_reconstruct_confignode_logs.out`.
- Cluster log backup: `testcase/logs_backup/tc27_v1361_reconstruct_parser_v2081_2026_2026_09_22_11_38_37/`.

---

## 环境残留问题：SimpleConsensus 配置会让后续 remove datanode 全部失败

**现象**：跑完 `tc8/tc9_v1361_SRsimple_*` 或 `tc25/tc26_v1361_reconstruct_*` 后，
再执行 `REMOVE DATANODE` 会报：

```
1006: TSStatus(code:1006, message:SimpleConsensus protocol is not supported to remove data node)
```

**判定逻辑**（`RemoveDataNodeHandler.checkClusterProtocol`）：只要 schema 或 data 任一共识仍是
`SimpleConsensus`，就拒绝移除节点：

```java
if (CONF.getDataRegionConsensusProtocolClass().equals(SIMPLE_CONSENSUS)
    || CONF.getSchemaRegionConsensusProtocolClass().equals(SIMPLE_CONSENSUS)) {
  // REMOVE_DATANODE_ERROR
}
```

**为什么 `reset_conf.sh` 没能恢复**：

1. `conf_orig`（2026-10-30 快照）里**没有** `consensus_protocol_class` 键，恢复后走默认值（schema=Ratis / data=IoT），这一步是对的；
2. 但集群启动时会把这个值**持久化**到 `data/confignode/system/confignode-system.properties`，
   **该文件的优先级高于 `conf/iotdb-system.properties`**；
3. 所以只要 `data/` 没被清掉，改 `conf/` + 重启**都不生效**。

**恢复方法**（二选一）：

```bash
# 方法 1（推荐）：彻底清数据后重启，让 conf 成为权威
#   与 clean_env 行为一致：停进程 → rm -rf data logs → 启动

# 方法 2：直接改持久化文件（需停集群）
sudo sed -i 's|^schema_region_consensus_protocol_class=.*|schema_region_consensus_protocol_class=org.apache.iotdb.consensus.ratis.RatisConsensus|' \
  /data/iotdb/<版本>/data/confignode/system/confignode-system.properties
# DataNode 侧对应文件：data/datanode/system/system.properties
```

**验证**：

```bash
grep -E 'consensus_protocol_class' data/confignode/system/confignode-system.properties
show cluster;   -- 确认 8/8 Running+ACTIVATED
remove datanode <id>;   -- 应不再报 1006
```

**教训**：排查这类"配置不生效"的问题时，**先看 `data/*/system/*.properties`**，
它才是运行时真正生效的来源。

---

## 测试规范：迁移状态探测优先用 SHOW MIGRATIONS，不要轮询 show regions 的 Adding

**背景（2026-11-05 实测）**：`show data regions` / `show regions` 里的 `Adding` 状态
**只持续约 1 秒**，由 1 秒的心跳粒度决定，**与数据量无关**（用 50 万点的 region 复测仍是 1 秒）。

而 `remove datanode` 会**并行提交**该节点上所有 region 的迁移，所有 Adding 窗口**重叠成同一个约 1 秒**，
之后统一转成 `Removing`（持续十几秒）。用 CLI 轮询（单次调用约 1.65 秒）去抓这 1 秒窗口，
本质是掷骰子 —— 这是 tc3 空转 1.5 小时、tc12/tc15/tc16 偶发失败的共同原因。

**正确做法：用 `SHOW MIGRATIONS`**

```sql
SHOW MIGRATIONS;
```

输出列：

```
| ProcedureId | OperationType | RegionId | Type | FromNodeId | ToNodeId
| CurrentState | ProcedureStatus | SubmittedTime | LastUpdateTime |
```

- 有在飞迁移时，列出每个未完成的 RegionOperationProcedure 及其当前状态
- 无在飞迁移时返回 `Empty set.`

**推荐用法（用例侧）**：

```bash
# 等待所有迁移收敛到空集，带超时
wait_migrations_finish() {
  local max_wait=$1; local t1=`date +%s`
  while true; do
     local n=`${cli_dir}/sbin/start-cli.sh -h ${query_ip} -u ${db_sys_admin} ${ssl_str} \
              -e "show migrations;" | grep -cE '^\|'`
     # 表头+分隔线占 2 行，数据行 = n-2
     if [[ $((n-2)) -le 0 ]]; then return 0; fi
     if [[ $((`date +%s`-t1)) -gt ${max_wait} ]]; then
        echo "Migrations did not finish within ${max_wait}s"; return 1
     fi
     sleep 2
  done
}
```

**涉及用例与改法建议**：

| 用例 | 原做法 | 建议 |
|---|---|---|
| `tc3_..._remove_dn_stop_adding_dn` | 轮询 `show data regions \| grep Adding` 找目标 DN | 已改为读 CN 日志的 `will be added to DataNode <id>@<ip>`（零竞态，提交 84948c6）；也可改用 `SHOW MIGRATIONS` 的 ToNodeId |
| `tc12/tc15/tc16` | 依赖两次 CLI 命令的间隔构造并发 | 已改为合并成单次 CLI 调用（提交 d95ab02）；若需更明确，可先 `SHOW MIGRATIONS` 确认有在飞过程再下发第二个命令 |
| 任何"等迁移完成"的用例 | 轮询 `show regions` 的 Adding/Removing | 优先 `SHOW MIGRATIONS` 判空，比状态字符串可靠 |

**注意**：`SHOW MIGRATIONS` 反映的是**过程（Procedure）**层面的状态，
`show regions` 的 Adding/Removing 是**副本（Replica）**层面的展示，两者粒度不同。
判断"迁移是否做完"用前者；判断"某个副本在哪个节点上"用后者。

---

## 测试规范：停止 DataNode 后应等待 `Stopped` 或 `Unknown`，不能只等 `Unknown`

**`NodeStatus` 共 5 个值**（`org.apache.iotdb.commons.cluster.NodeStatus`）：

```
Running | Unknown | Removing | ReadOnly | Stopped
```

**语义区别**：

| 状态 | 含义 | 产生方式 |
|---|---|---|
| `Stopped` | **优雅停止**，进程正常退出并向集群上报 | `stop-datanode.sh` |
| `Unknown` | **不可达**，心跳超时 | `kill -9`、网络分区、进程崩溃 |

**问题**：大量用例用 `stop-datanode.sh`（优雅停止）停节点后，却只等待 `Unknown`：

```bash
ssh ... "sudo ./sbin/stop-datanode.sh"
if ! wait_datanode_status "${query_ip}" "${rm_target_ip}" "Unknown" 300; then
   log "datanode ... did not become Unknown before remove"
   let fail_flag++
fi
```

优雅停止产生的是 `Stopped`，**永远等不到 `Unknown`** → 白等 300 秒后判失败。

**2026-11-05 全量回归实际影响**：
- `tc109_RMDN_no9_remove_unknown_dn` 因此失败（1541s，报 `did not become Unknown before remove`）
- 同类模式在 **30 个用例**中出现（含 tc109/tc110/tc113/tc114 的各版本变体）

**正确写法**（已改进 `wait_datanode_status` 支持正则）：

```bash
hit_num=$(grep "${dn_ip}|" "${cur_dir}/show_datanodes.out" | grep -iE "${expect_status}" | wc -l)
...
# 优雅停止或崩溃都算"已停止"
if ! wait_datanode_status "${query_ip}" "${rm_target_ip}" "Stopped|Unknown" 300; then
```

**注意**：如果用例的语义确实要求"不可达（Unknown）"而非"优雅停止（Stopped）"，
应该用 `kill -9` 制造 Unknown，而不是用 `stop-datanode.sh`。

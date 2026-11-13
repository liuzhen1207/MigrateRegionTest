# Skill Case 总清单（回归防漏）

> 维护人：刘珍 ｜ 最后更新：2026-11-13
> 用途：一眼看清「有哪些 skill case、各自多大、最后在哪个版本跑过、RC2 是否覆盖」

---

## 一、总览

| # | Skill | 用例数 | 位置（70.3） | 最后运行版本 | **RC2 是否已跑** |
|---|---|---|---|---|---|
| 1 | **membuf_skill**（内存缓冲区） | 31（25 功能 + 5 性能 + MB-26） | `/data1/iotdb/testcase/membuf_skill` | **RC2** `v20131rc2_1110_83183d0` | ✅ **已跑 30/31**（MB-26 待跑） |
| 2 | **feishu_spec_skill**（查询调度） | 15 | `/data1/iotdb/testcase/feishu_spec_skill` | **RC2** `v20131rc2_1110_83183d0` | ✅ **已跑 15/15** |
| 3 | **sanquan_skill**（三权分立） | 59 | `/data1/iotdb/testcase/sanquan_skill` | **RC1** `v20131rc1_1030_ab6d3de`（11-03） | ❌ **未跑** |
| 4 | **ref_compaction**（合并） | 52（CO-01~43 + DT-01~09） | `/data1/iotdb/testcase/ref_compaction`（**2026-11-13 已部署**） | RC8 `v20121rc6_1010_7ae8713e`（10-20） | 🔄 **正在跑**（11-13 18:26 启动） |
| 5 | **region_migrate_skill**（迁移） | 122 | `/data1/iotdb/testcase/MigrateRegionTest/testcase` | **RC2** | ✅ **已跑 122/122** |

**合计：279 个用例；RC2 已覆盖 167 个，正在补跑 111 个（2026-11-13 晚启动周末连跑）。**

---

## 二、缺口（需要补跑）

### 缺口 1：sanquan_skill —— 59 个用例，只跑到 RC1（**周末已排期，紧随 compaction 之后**）

```
最后运行：2026-11-03，v20131rc1_1030_ab6d3de
结果：79 条 v20121rc12 / 242 条 v20131rc1（历史累计）
RC2 结果：无
```

**跑法**：

```bash
cd /data1/iotdb/testcase/sanquan_skill
export V_TESTDB=v20131rc2_1110_83183d0
bash tools/run_all.sh
```

**预计耗时**：59 个用例，按历史约 10~15 分钟/个 ≈ **10~15 小时**（建议分两晚）。

### 缺口 2：ref_compaction —— 52 个用例，从未在 2.0.13.1 上跑过（**2026-11-13 已部署并开跑**）

```
部署状态：✅ 已部署到 /data1/iotdb/testcase/ref_compaction（2026-11-13）
最后运行：2026-10-20，2.0.12.1 RC8（本次之前）
环境适配：改了 11 项（见下方「环境适配记录」）
```

**部署 + 跑法**：

```bash
# 1) 部署到 70.3
scp -r ref_compaction cluster@172.20.70.3:/data1/iotdb/testcase/

# 2) 跑
cd /data1/iotdb/testcase/ref_compaction
export V_TESTDB=v20131rc2_1110_83183d0
bash tools/run_all.sh --set regression      # 52 条全跑
# 或先冒烟：bash tools/run_all.sh --set quick   # 8 条
```

**预计耗时**：52 个用例，约 **8~12 小时**。

---

## 三、各 Skill 明细

### 1. membuf_skill（内存缓冲区）

| 项 | 内容 |
|---|---|
| 导入入口 | `tools/run_all.sh`（功能）/ `tools/run_perf.sh`（性能） |
| 用例清单 | `cases/regression.txt`（20 条，含 MB-26）、`ALL_CASES`（25 条，run_all.sh 内） |
| 结果表 | `results/test_result.csv`（功能）、`results/perf_P-0*.csv`（性能） |
| RC2 结果 | 功能 **23/25 PASS**（MB-14、MB-15 FAIL）；性能 **14/14 变体正常** |
| 已知限制 | `docs/KNOWN_ISSUES.md` §5（MB-14 Pipe 池过小） |

> ⚠️ **MB-26 未跑**（2026-11-13 新增，V2 合理 Pipe 比例对照场景）：
> `bash tools/run_all.sh --set all --only MB-26 --ver v20131rc2_1110_83183d0`

### 2. feishu_spec_skill（查询调度）

| 项 | 内容 |
|---|---|
| 导入入口 | `tools/run_all.sh` |
| 用例清单 | `cases.tsv`（15 条） |
| 结果表 | 各用例独立日志 + 汇总 |
| RC2 结果 | **15/15 PASS**（修复 3 类用例缺陷后） |

### 3. sanquan_skill（三权分立）

| 项 | 内容 |
|---|---|
| 导入入口 | `tools/run_all.sh` |
| 用例清单 | `cases.tsv`（59 条）、`conf/matrix.tsv` |
| 结果表 | `results/test_result.csv` |
| 最后运行 | RC1（11-03） |

### 4. ref_compaction（合并）

| 项 | 内容 |
|---|---|
| 导入入口 | `tools/run_all.sh` |
| 用例清单 | `cases/regression.txt`（52 条）、`cases/quick.txt`（8 条冒烟） |
| 用例构成 | CO-01~CO-43（合并功能）+ DT-01~DT-09（数据类型变更） |
| 最后运行 | 2.0.12.1 RC8（10-20） |
| 本地位置 | `/data/deepseek/skill_case_ip3_3c5d/ref_compaction` |

### 5. region_migrate_skill（迁移）

| 项 | 内容 |
|---|---|
| 导入入口 | `run_all_mig.sh`（读两个清单） |
| 用例清单 | `migrate_testcase_list.txt`（62）+ `remove_iotv1_testcase_list.txt`（60） |
| RC2 结果 | **122/122 执行完毕**：108 PASS / 13 FAIL / 1 无判定 |

---

### ref_compaction 环境适配记录（2026-11-13）

该 skill 原为另一套环境编写（3 节点 192.168.99.77/78/79、root 用户、dataRF=3），
部署到本环境需改 `conf/env.conf` 的 11 项：

| 配置项 | 原值 | 改为 |
|---|---|---|
| `CLUSTER_NODES` | 192.168.99.77 78 79 | 172.20.70.5 / .4 / .26 |
| `CN_NODES` | 跟随 CLUSTER_NODES | 172.20.70.5 / .4 / .26 |
| `DN_NODES` | 跟随 CLUSTER_NODES | 172.20.70.4 / .26 / .14 / .27 / .30 |
| `SSH_USER` | root | **cluster** |
| `SHELL_CLIENT_DIR` | /data/iotdb/testdb | **/data1/iotdb/testdb** |
| `CLUSTER_NAME` | timecho | **defaultCluster** |
| `DATA_RF` | 3 | **2** |
| `CN_METRIC_PORT` | 9091 | **9081** |
| `PROMETHEUS_URL` | http://127.0.0.1:9090 | **http://172.20.70.13:9090** |
| `PROMETHEUS_CLUSTER` | timecho | **defaultCluster** |
| `USE_FRAMEWORK` | 1（依赖 /data/iotdb/autotest） | **0（该目录不存在，改自管集群）** |
| `V_TESTDB` | v20121rc6_1010_7ae8713e | **v20131rc2_1110_83183d0** |

**冒烟验证**：CO-01 于 2026-11-13 18:06 跑通，`PASS=1 FAIL=0`（1030 行输出，无 192.168 超时）。

---

## 四、非回归类目录（不列入清单）

| 目录 | 说明 |
|---|---|
| `defect_repro/` | 单缺陷复现脚本（如 V2-1067），非回归套件 |
| `staging2/ai_auto_cases/` | region_migrate_skill / query_schedule_skill 的暂存副本，内容与正式副本重复 |
| `membuf_skill.old_094229/` | membuf 的旧备份（24 个用例），已被正式副本取代 |
| `*.tgz` / `*.zip` | 历史快照压缩包（membuf/feishu 各版本、compaction RC8） |

---

## 五、每次发新 RC 的标准回归流程

```bash
# 0) 更新版本目录（三处都要改）
#    membuf_skill/conf/env.conf      : V_TESTDB
#    feishu_spec_skill/conf/env.conf : V_TESTDB
#    sanquan_skill/conf/env.conf     : V_TESTDB
#    ref_compaction/conf/env.conf    : V_TESTDB
#    MigrateRegionTest/conf/test.conf: v_cur_db

# 1) 迁移专项（约 24 小时）
cd /data1/iotdb/testcase/MigrateRegionTest && bash run_all_mig.sh

# 2) membuf（约 4 小时）
cd /data1/iotdb/testcase/membuf_skill
bash tools/run_all.sh --set all --ver $V_TESTDB
bash tools/run_perf.sh --set all

# 3) feishu（约 2 小时）
cd /data1/iotdb/testcase/feishu_spec_skill && bash tools/run_all.sh

# 4) sanquan（约 12 小时）
cd /data1/iotdb/testcase/sanquan_skill && bash tools/run_all.sh

# 5) compaction（约 10 小时，需先部署）
cd /data1/iotdb/testcase/ref_compaction && bash tools/run_all.sh --set regression
```

> ⚠️ **本环境限制**：70.3 没有 screen/tmux，且发起端 ssh 长连接被回收时会杀掉远端进程组
> （见 membuf `docs/KNOWN_ISSUES.md` §1）。长跑必须**保持 ssh 存活**，不要用 `setsid nohup &` 后立即断开。

---

## 六、清单维护约定

1. **新增 skill 时**：在本文件第一节加一行，并填写「最后运行版本」
2. **每次跑完一个 skill**：更新该行的「最后运行版本」与「RC2 是否已跑」
3. **用例数变化时**：同步更新总览的合计数字
4. 本文件同时放在仓库 `skill_case/SKILL_CASE_总清单.md`（版本化）与工作区（本地参考）

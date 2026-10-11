# Stage 2C-3 Final Report（最终稳定性验收与 Gate-2C 闭环）

- 日期：2026-10-11（15:03–15:25，UTC+8）
- 性质：**验收阶段——零源代码改动**（见 §2 声明）；仅新增测试工具与证据文件、补齐文档缺口。
- 交付物：本报告（《Stage 2C3 Final Report》，含《Resource-Leak-Check》结论与《Gate-2C Final Verdict》）、`docs/Stage-2C3-Baseline-Check.md`、`docs/Stage-2B-Implementation-Report.md`（缺口补齐）、`docs/evidence/stage2/2c/stage2c3-*`。

---

## 1. 基线状态（Step 0，详见 `docs/Stage-2C3-Baseline-Check.md`）

**PASS** —— 17 个关键文件哈希与 Stage 2C-2 收尾记录逐项一致；2C-2 后零文件变化；0 相关进程、端口 1420/9333 未监听、测试环境变量为空。Stage-2B 报告缺口确认存在（Step 5 补齐）。

## 2. 修改文件列表

**No source changes.**（源代码、依赖、配置、UI 全部零改动——13 项禁改文件 + 3 个生命周期源文件在 Step 0 与收尾两次哈希核验中与 2C-2 基线完全一致。）

本阶段新增（非源码）：
| 文件 | 说明 |
|---|---|
| `docs/Stage-2C3-Baseline-Check.md` | Step 0 基线核验报告 |
| `docs/Stage-2B-Implementation-Report.md` | Stage-2B 报告缺口补齐（忠实还原会话记录；未修改任何历史证据） |
| `docs/evidence/stage2/2c/gate2c3-cycles.mjs`、`gate2c3-round.ps1` | 测试装置（120 周期长稳、含退出耗时计量的轮次） |
| `docs/evidence/stage2/2c/stage2c3-*.log/.png`（14 项） | 全部验收证据 |
| `test-assets/cycles/`（120 个小素材）、`test-assets/lock-check.mp4` | 压力/泄漏检查专用素材 |
| `docs/evidence/stage2/2b/gate2b3-ui-helper.ps1` | 一行附加式修改：新增 `lockcheck` 场景（不改既有场景与证据） |

## 3. 测试矩阵（全部实际执行）

| 测试项 | 结果 | 证据 |
|---|---|---|
| **Step 2A：120 周期长稳**（≥100 循环等价档） | **PASS** | `stage2c3-cycles-results.log`：total=120，ready=40 / failed=80 / ipcErrors=0，耗时 1.4s；运行后窗口 Responding=True、ffprobe 在途=0；关闭后 `remaining=0 peak=40`、零残留、端口释放 |
| **Step 2B：6 轮生命周期循环**（3 真实 + 3 在途关闭） | **6/6 PASS** | `stage2c3-rounds.log`：退出耗时 247–262ms（≪2s）；真实轮元数据正确；在途轮 `cancelled=1 reaped=1 remaining=0`、替身零残留、端口释放 |
| **Step 2C：异常路径** | **PASS** | 正常完成=周期 ready=40 + T1；FFprobe 失败=周期 failed=80（NONZERO_EXIT）+ T2；**超时=当前构建实测**（`stage2c3-exception-paths.log`：1500ms 受控超时 → `FFPROBE_TIMEOUT` @1530ms、子进程即时归零）；shutdown 取消=轮次 4–6 + T3 + 2C-2 Phase B（cancelled=10） |
| **Step 4：cargo test** | **EXIT=0**，52 passed / 0 failed / 7 ignored / 0 警告 | `stage2c3-cargo-test.log` |
| **Step 4：npm run build** | **EXIT=0** | `stage2c3-npm-build.log` |
| **Step 4：UI 回归 2A** | **PASS** | `stage2c3-ui-regression.log`：特殊字符路径导入 ✓、重复导入"已在列表中" ✓ |
| **Step 4：UI 回归 2B** | **PASS** | 元数据（1.18 MiB/00:05/640×360/MPEG-4/AAC）✓、无音轨 ✓、错误态（moov atom not found）✓、重试点击后状态机流转回同因错误态 ✓；终态截图 `stage2c3-regression-final.png`；干净关闭 0 残留 |

## 4. 生命周期最终结论（Step 1 审计）

状态转换验证表（进入/退出条件均以现行代码行号与测试为准）：

| 状态 | 进入条件（代码位置） | 退出条件 | 测试证据 |
|---|---|---|---|
| Pending | `register`（probe_lifecycle.rs:139；登记即置 Pending） | spawn 成功→Running；shutdown→Cancelled | register_and_remove_task；T1 断言初值 |
| Running | 子进程句柄入共享槽位后（probe.rs:398-400） | 进程退出→Completed/Failed；shutdown→Cancelled | T3/T4 实测观察到 Running（延迟替身窗口） |
| Completed | 探测返回 Ok（probe.rs:331-348 按结果置态） | 探测路径 `take_finished`（:156）移除 | T1（终态 + 清理断言） |
| Failed | 返回任何非取消错误（含 TIMEOUT/MEDIA_UNSUPPORTED） | 同上 | T2（错误码逐字保持 + Failed≠Cancelled） |
| Cancelled | shutdown 置位（probe_lifecycle.rs:184 `mark_cancelled_if_active`，**仅活动态**）或结果为 FFPROBE_CANCELLED | 同上 | T3/T4 + status_model_transitions_and_terminal_protection（终态保护） |

四项不变量核验（全部有自动化测试 + 运行证据）：
1. **终态不可覆盖**：`mark_cancelled_if_active` 仅作用于 Pending/Running（:104-112）——`status_model_transitions_and_terminal_protection` 显式验证 Completed/Failed 不被改写。
2. **Cancelled 不覆盖业务错误**：命令层对 `FFPROBE_CANCELLED` 仅 `abort` 不写 store（probe.rs:894-900）——T4 结构性保证 + 2C-2 命令层实现。
3. **Completed 不被 shutdown 修改**：同 1（shutdown_all :184 遍历使用 mark_cancelled_if_active）。
4. **Failed 不被退出流程污染**：同 1；轮次 4–6 与 T3 的在途关闭均显示既有失败/取消语义不被污染。

一致性检查（Step 2 要求的四项"不存在"）：
- task 已删除但结果未保存：**不存在**（删除仅发生于探测路径终态后；取消路径有意不写 store 并释放在途标记，属设计语义 D-0026）。
- result 已更新但 task 未释放：**不存在**（store 写入发生在探测路径移除之后；取消路径 abort 与移除均收敛）。
- retry 创建重复 Child：**不存在**（`begin` 防并发 + T4 断言单任务/单 Child）。
- shutdown 后残留任务：**不存在**（120 周期 + 6 轮 + 压力两阶段 shutdown 摘要全部 `remaining=0`）。

## 5. 资源泄漏结论（《Resource-Leak-Check》）

| 检查项 | 方法 | 结果 |
|---|---|---|
| 子进程 | 轮次/长稳关闭前后进程计数（含 PID 记录） | **0 残留**（全部轮次与长稳；在途关闭亦然） |
| 任务状态 | 每次关闭的 shutdown 摘要 | **remaining=0**（本阶段全部 9 次关闭 + 长稳 1 次，共 10 次） |
| 文件句柄 | ① 探测完成后、应用运行中：对素材独占打开（FileShare.None）；② 关闭后：重命名素材并回改名、复核哈希 | ① **SUCCESS**（应用不持有素材句柄）；② **SUCCESS**（SHA256 `5D511034…` 往返一致） |
| 端口 | 1420 / 9333 | 全部释放（每轮核验） |

证据：`stage2c3-leak-check.log`（含一次诚实记录的无效尝试及其现场清理——首次导入因场景缺失失败，遗留对话框已用 close-dialog 清理后重做有效测试）。

## 6. 未解决问题与风险

无新增。既有边界（如实保留）：异常关闭（OS 强杀）无 shutdown 保证；`test-assets/` 压力素材留存待清理决定。

## 7. Gate-2C 判定（Step 6，按 §9 逐条）

| # | 判定问题 | 回答 |
|---|---|---|
| ① | 功能在授权范围？ | **是**——零源码改动；仅测试装置、证据与文档；未触碰 2A 核心/2B 语义/UI/依赖/配置 |
| ② | 必需测试真实执行？ | **是**——120 周期长稳、6 轮循环、4 类异常路径、cargo/npm/UI 回归全部实际执行并有日志 |
| ③ | 成功/失败/边界证据？ | **是**——成功（40 ready）、失败（80 NONZERO_EXIT）、超时（1530ms 实测）、取消（在途轮 cancelled=1×3 + 2C-2 cancelled=10）；UI 三态截图 |
| ④ | 回归通过？ | **是**——cargo 52/0/7 EXIT=0；npm EXIT=0；UI 2A+2B 七项全绿；10 次关闭全部干净 |
| ⑤ | 存在 P0？ | **无** |
| ⑥ | 删测试/降标准？ | **无**——测试集只增不减（52 项含 T1–T4）；无标准变更（decision-log 本阶段零新增） |
| ⑦ | 停止项？ | **无**（过程中的一次测试装置缺陷已当场发现、诚实记录并重做有效测试） |
| ⑧ | 证据可复核？ | **是**——文件名+行号+哈希+进程 PID 全部落盘于 `stage2c3-*` |
| ⑨ | 基于完整测试后判定？ | **是**——本判定于 Step 0–5 全部完成后作出 |

### # Gate-2C Final Result

**PASS**

---

**停止声明**：Stage 2C 全部闭环（2C-1 修复、2C-2 增强、2C-3 验收）。未进入 Stage 2D，未实施任何用户功能。等待审阅与下一阶段授权。

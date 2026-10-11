# Stage 2D1-C ARCH Audit（架构走查 · Step 1）

- 日期：2026-10-11
- 方法：逐项对照**现行代码**（行号为 2C-3 Final 基线的实测行号）+ 自动化测试证据 + 实机运行证据（`stage2d1b-matrix*.log`、`stage2c2/2c3/2d1a` 系列证据）。
- 结论预览：**11/11 PASS**；无违反冻结约束项。
- 编号说明：本审计采用 2D 授权指令的 11 项编号；每项标注与规格 v1.3 ARCH-001~011 及决策的对应关系。

| # | 审计项 | 状态 | 代码位置 | 证据 | 冻结约束核对 |
|---|---|---|---|---|---|
| 1 | ARCH-001 导入边界（原生选择器进入、路径只读） | **PASS** | `picker.rs:18`（Rust 侧 dialog，WebView 无 dialog 能力）；`import.rs:100 create_entry / 165-195 validate`（只读 File::open + exists/is_file）；导入核心 2A 后零改动（哈希 `ee4d3d9b…`） | Gate-2A 全套（含 ACL §10.2 规程）；P2D-001 源保护三方一致 | 符合（2A 冻结） |
| 2 | ARCH-002 IPC 边界（前端仅传条目 ID/枚举，不传路径与可执行文件） | **PASS** | `probe.rs:694-741 probe_import_entry(entry_id, force)`——媒体路径唯一来源为导入登记表（:706-713）；测试覆盖仅经 Debug 环境变量（`test_overrides.rs:37-62` 白名单校验），Release 无该模块（rlib 剔除证明） | P2B 安全边界审查；D-0023；capabilities 哈希 `f4e45098…` 未变 | 符合 |
| 3 | ARCH-003 FFprobe 调用隔离（发现/参数/执行与业务解耦） | **PASS** | `probe.rs:115 discover_ffprobe → 129 discover_with`（覆盖→PATH→WinGet→常见目录）；`:243 build_probe_args`（OsString 单参数原样传递，恶意输入单测 9 例）；执行与解析分离（`probe_file_inner` :373 / `parse_probe_json` :600） | 2B-1 O 组实测；恶意参数单测 `build_args_passes_input_as_single_osstring_verbatim` | 符合（spec ARCH-001/002） |
| 4 | ARCH-004 JSON 单一来源 | **PASS** | `probe.rs:600 parse_probe_json`（唯一字段入口，serde_json）；stdout 仅入解析器；stderr 仅诊断（:8 KiB 截断 :22 + 首行原因 :389-407），未进入任何字段 | P2D-007 审计（2D-1-B 矩阵日志现行复核）；走查记录 | 符合（spec P2B-007/ARCH-006） |
| 5 | ARCH-005 错误分类完整性（六码互不吞并） | **PASS** | `ProbeFailureCode`（probe.rs:33-60 区段）：NOT_FOUND / START_FAILED / NONZERO_EXIT / TIMEOUT / PARSE_FAILED / MEDIA_UNSUPPORTED / CANCELLED；分类依据仅退出码+流分析，无可靠依据不猜测（D-0024） | P2D-005 四场景实机 + P2D-011 边界（audioonly/truncated/noext）+ 单测 `ensure_video_stream_classifies_no_video_media` | 符合（D-0024 冻结） |
| 6 | ARCH-006 生命周期管理（状态机） | **PASS** | `probe_lifecycle.rs:45 ProbeTaskStatus`；转移：register→Pending(:139)、入槽→Running（probe.rs:419-421）、按最终结果→Completed/Failed（managed_task :352-368 + discovery :272-303）、shutdown→Cancelled（mark_cancelled_if_active :104-112 仅活动态） | T1~T4 + `status_model_transitions_and_terminal_protection`（终态不可覆盖） | 符合（D-0026 冻结） |
| 7 | ARCH-007 Child 回收机制（登记表 + 共享槽位 + shutdown） | **PASS** | `probe_lifecycle.rs:68 ProbeTask{child: Arc<Mutex<Option<Child>>>}`；`shutdown_all :184`：置位令牌→取走句柄 kill+wait→有界等待收敛；`lib.rs:57-69` RunEvent::Exit 调用 | 120 周期长稳 + 16 轮循环 + 2D-1-B 会话 G（in-flight child=1→0、remaining=0、elapsed 45ms） | 符合（D-0025 冻结） |
| 8 | ARCH-008 超时机制（默认 30s + 受控覆盖） | **PASS** | `probe.rs:232 effective_timeout_ms`（覆盖 1..=30000 仅 Debug，否则 30s 常量）；轮询循环 `try_wait` + 超时 kill+wait（:437-470 区段） | 默认值单测；受控 1500ms 实测 1530ms 终止且 child=0（会话 E）；P2D-013 | 符合（D-0014/D-0023 冻结；不适用于 FFmpeg/转码） |
| 9 | ARCH-009 重试语义（force + 不覆盖既有结果） | **PASS** | `probe_import_entry(force)`（probe.rs:695）；force 忽略缓存、在途防并发仍生效（:701-716）；**取消结果仅 abort 不写 store**（:894-900）——未完成的重试不覆盖既有错误结果 | T4；2B-3 S5（超时→换真实工具→重试成功且状态更新）；2C-2 单测 | 符合（D-0024/D-0026 冻结） |
| 10 | ARCH-010 状态机一致性（转移无非法路径） | **PASS** | 全部状态写点收敛于：register(Pending)、inner(Running)、managed_task/discovery(终态三值)、mark_cancelled_if_active(仅活动态)；`take_finished` 幂等 | 2C-3 生命周期最终审计（状态转换表）+ 本轮复核无新增写点（grep 证实 set_status 仅 3 处调用域） | 符合（D-0026 冻结） |
| 11 | ARCH-011 日志基础设施 | **PASS** | `logging.rs`：5 MiB/:16、3 份/:18、轮转 :87、自愈重建 :71-84、`log_line` 全错误静默 :52-57、未初始化 no-op；六事件挂接：register（probe.rs:281/326）、start（:422）、complete/failed/cancelled（:337-343）、shutdown cleanup（lib.rs:63-69）；目录经应用路径 API（lib.rs:38-45） | 5 项单测（轮转/截断/常量/时序/韧性）；实机六事件样例 `stage2d1a-lifecycle-log-sample.log`；生产常量断言（5,242,880/3） | 符合（D-0020/D-0027；2D-1-A 新增） |

## 重点确认记录

1. **logging.rs**：5 MiB（5,242,880 常量断言单测）✓；3 份保留（轮转直测：.1/.2 存在、.3 不存在、最旧滚出）✓；异常不影响主流程（全错误静默 + 目录删除后自愈重建单测）✓；事件记录完整（六事件实机样例）✓。
2. **生命周期状态机**：五状态转移无非法路径——全部写点如上表第 10 项；终态保护（Completed/Failed 不被关闭覆盖）有专项单测；`Cancelled ≠ Timeout ≠ Failed` 分类不吞并有专项断言（T2/T3）。
3. **shutdown 链路**：Exit（lib.rs:57）→ cancel token（shutdown_all 遍历置位）→ kill child（取走句柄）→ wait 回收 → 有界等待（≤2s）→ remaining=0——2C-2/2C-3 长稳与轮次 × 多次 + 2D-1-B 会话 G 复验（45ms 完成）。

## 冻结约束核对结论

11/11 项均不违反 2A/2B/2C 冻结：2A 导入核心与 2B 元数据语义零改动（哈希 `ee4d3d9b…`/元数据语义未触）；2C 生命周期状态机零改动（日志/终态判定为旁路）；规格 v1.3 与 D-0013~D-0027 全部处于被遵守状态。

# Stage 2C-1 Baseline Report

- 日期：2026-10-11 13:43（UTC+8）
- 任务：Stage 2C-1 · Step 1 基线冻结检查（只读审查，为 D-0024 生命周期修复提供依据）
- 声明：本报告为本次**唯一新增文件**；未修改任何既有文件、未安装依赖、未执行代码修改、未进入生命周期修复阶段、未执行 Stage 2C 后续步骤。

---

## 1. 环境与工作区状态

### 1.1 基本状态

| 项 | 结果 |
|---|---|
| 工作目录 | `D:\应聘项目zcode` |
| Git | **非 Git 仓库**（`fatal: not a git repository`，与历次记录一致；未初始化） |
| 相关进程 | 0（clipforge/node/cargo/msedgewebview2/switchable-ffprobe/fake-ffprobe-delay 均无） |
| 测试环境变量 | 进程作用域为空（`CLIPFORGE_TEST_FFPROBE`/`CLIPFORGE_TEST_PROBE_TIMEOUT_MS` 均未设置） |
| Stage 2B 最终状态 | 源码/配置/文档哈希与 Gate-2B 收尾记录**逐项一致**（见 §1.2），无漂移 |

### 1.2 关键文件基线哈希（SHA256 前 20 位，与 Stage 2B 最终记录一致）

| 文件 | 哈希 | 状态 |
|---|---|---|
| `src-tauri/src/probe.rs` | `72ec3c4c721912ae8993` | 一致 |
| `src-tauri/src/lib.rs` | `85a3d319d79df76eabf4` | 一致 |
| `src-tauri/src/import.rs` | `ee4d3d9bd3996c10f541` | 一致（2A 冻结） |
| `src-tauri/src/picker.rs` | `789a1387ba592a7865d6` | 一致（2A 冻结） |
| `src-tauri/src/main.rs` | `a2a7ed08898fa2250a6a` | 一致（模板原样） |
| `src/App.tsx` | `cad8a00d1c4807e0e0a4` | 一致 |
| `src/importApi.ts` | `f69c3a96ce76d8f8f6c9` | 一致 |
| `src/App.css` | `f18298f48e6a3b61d949` | 一致 |
| `src-tauri/Cargo.toml` | `10cc68559711c14336a9` | 一致 |
| `src-tauri/Cargo.lock` | `f5bd42fbe1d145b51255` | 一致 |
| `package.json` | `6aafd96da0f055f2fd98` | 一致 |
| `package-lock.json` | `f14f03cf4a66ed67dda9` | 一致 |
| `src-tauri/tauri.conf.json` | `bb6dc6fb736a3a18e1c1` | 一致 |
| `src-tauri/capabilities/default.json` | `f4e450983bbc94f2c2b0` | 一致 |
| `docs/decision-log.md` | `f2d6ddfbb6acecccc849` | 一致（含 D-0001~D-0024） |
| `docs/requirements-and-acceptance.md` | `a13affc5c47017266e3c` | 一致（v1.2，54 条） |
| `docs/test-report.md` | `121e74ea413da7f6e688` | 一致（Stage 1 版，未含 Stage 2 内容） |

### 1.3 文件变化与异常核查

- 以 2026-10-10 23:00 为界的 `find -newermt` 检查仅命中两处，均属上一会话**已记录**的收尾动作：`docs/decision-log.md`（23:01:30 追加 D-0024，已在 Gate-2B 报告披露）与 `stage2b3-p2b007-walkthrough.log`（走查日志，已归档）。**结论：不存在未记录修改。**
- 已知留存工件（均已记录，未清理，符合"不自行清理"）：`test-assets/large_sample.mkv`（471 MB）、`test-tools/fake-ffprobe/`（替身工程 + target + `switchable-ffprobe.exe` + `unlaunchable.dat`）、`2b/scratch/`（单测夹具）。
- **异常/缺口（如实报告，本次不处理）**：`docs/` 下**不存在 Stage-2B 阶段报告文件**——Gate-2B 的 PASS 判定与逐项结果仅存在于会话记录与 `docs/evidence/stage2/2b/`（53 个证据文件）及决策日志 D-0023/D-0024 中；规格 §9 规则 2 要求阶段结果记录于 `docs/test-report.md` 或阶段报告，该落盘义务当前未履行。建议在后续授权步骤中补记（见 §7）。

---

## 2. 当前架构（Probe 调用链，逐步对应代码位置）

```
导入（用户点击"导入视频"）
  App.tsx:119 handleImportClick
    ├─ pickVideoFile()               App.tsx:127 → importApi.ts:41 → picker.rs:18 pick_video_file（Rust 侧 dialog，模态，无子进程）
    ├─ createImportEntry(path)       App.tsx:132 → importApi.ts:51 → import.rs:219 命令 → import.rs:100 ImportState::create_entry（校验/判重/登记）
    └─ refreshEntries() 后即发即忘发探测  App.tsx:140 void runProbe(entry.id)
         ↓
probe 调用
  App.tsx:104 runProbe → importApi.ts:74 probeImportEntry(entryId, force) → invoke("probe_import_entry")
         ↓
FFprobe Child 创建（全应用唯一子进程创建点）
  probe.rs:695 probe_import_entry（async 命令）
    ├─ 缓存命中即返回            probe.rs:701-705（ProbeStateStore::cached :530）
    ├─ 条目存在性与 Ready 校验    probe.rs:706-713（import.rs EntryStatus :18）
    ├─ 在途防并发 begin           probe.rs:714-716（ProbeStateStore::begin :535）
    └─ tauri::async_runtime::spawn_blocking   probe.rs:719-724（全文件唯一 async_runtime 引用）
         ↓ 阻塞线程池内
  probe.rs:251 probe_with_discovery → probe.rs:109 discover_ffprobe（覆盖[仅 Debug]/PATH/WinGet/常见目录）
  probe.rs:267 probe_file → probe.rs:269-283 Command::new(tool).args(build_probe_args:237-247, OsString).spawn()
    └─ 读取线程排空管道            probe.rs:288-297
         ↓
JSON 解析
  probe.rs:337 parse_probe_json（probe.rs:428；serde_json::from_slice :430）→ ensure_video_stream（:415，MEDIA_UNSUPPORTED 判定）
         ↓
状态保存
  probe.rs:732-739 ProbeRecord{size_bytes, Ready/Failed} → ProbeStateStore::finish（probe.rs:544-548）→ results: HashMap
         ↓
UI 更新
  命令返回 ProbeView（build_view probe.rs:657）→ App.tsx:107-108 setProbes → ProbeBlock 渲染（成功元数据/失败态+重试按钮）
```

超时路径（在途保护）：probe.rs:299-323 `try_wait` 轮询循环（50ms 间隔）→ 超时走 :344-366 `child.kill()`（:347）+ `child.wait()`（:348）+ 读取线程 join（:349-350）→ `FFPROBE_TIMEOUT`。`try_wait` 出错路径同样 kill+wait（:311-312）。

---

## 3. Probe 生命周期分析（关闭窗口路径）

```
Window Close
  → lib.rs:30-31  Builder...run(ctx) 返回（窗口关闭即返回；main.rs:5 clipforge_lib::run() 结束）
  → 进程退出
       ↘ 在途 probe 任务：spawn_blocking 线程（probe.rs:719）随进程消亡（不执行任何后续代码）
            ↘ FFprobe Child（probe.rs:269 创建）→ 成为孤儿
```

**D-0024 六问逐条回答（全部引用实际代码）：**

1. **FFprobe Child Handle 是否被保存？——否。** `child` 是 `probe_file` 的**函数局部变量**（probe.rs:269 `let mut child`），所有权封闭在函数内（:267-368），函数返回即丢弃；`ProbeStateStore` 中不含任何进程句柄（见 §4）。
2. **是否存在统一任务管理器？——否。** 唯一的"管理"是 `ProbeStoreInner.inflight: HashSet<u64>`（probe.rs:519），仅记录**条目 ID**（防同条目并发），不保存 `JoinHandle`、不保存 `ChildHandle`、无任务枚举能力。
3. **能否在退出前访问运行中的任务？——否。** `lib.rs:17-31` 是完整 Builder 链：无 `RunEvent::ExitRequested/Exit` 处理、无 `on_window_event`、未使用 `build()+run_event` 模式（全后端 grep 证实为空，见 §5 检索）。`.run()`（:30）返回即进程退出，不存在"退出前"的受控时机；且句柄本身不可达（见 1/2）。
4. **kill/wait 逻辑目前在哪里？——两处，均在 `probe_file` 内部且仅内部可达**：① `try_wait` 出错兜底 probe.rs:311-312；② 超时路径 probe.rs:347-348（kill + wait 回收，配诊断消息拼接 :351-359）。这两处是全应用唯一的子进程终止代码。
5. **超时终止逻辑能否复用？——模式可复用，结构不可达。** kill+wait（:347-348）正是退出清理所需操作，但它作用于**局部** `child`；要在退出时执行，必须先让 child 句柄（或取消信号）能被退出路径访问——当前结构下不存在该通道，需要结构性变更（句柄注册表或取消令牌传入 `probe_file`）。
6. **为什么会产生孤儿进程？——三层原因叠加（实证：S6b，`stage2b3-ui-cycles.log`，orphan_pid=32668）**：
   (a) 句柄封闭：child 是函数局部（§3.1），外部无法终止；
   (b) 无退出钩子：`run()`（lib.rs:30）无 RunEvent 处理，进程直接退出；
   (c) Windows 语义：父进程退出**不级联终止**子进程，FFprobe 由系统留下继续运行（实测替身睡满 120s 的场景即孤儿存活）。
   另注：`spawn_blocking` 的 `JoinHandle` 也未保存（probe.rs:719-724 直接 `.await`），即使运行时优雅关闭也无从取消任务。

---

## 4. 状态管理分析（ProbeStateStore 现状结构）

```rust
// probe.rs:498-560（摘要）
pub enum ProbeState { Ready(ProbeMetadata), Failed(ProbeFailure) }        // :498-501
pub struct ProbeRecord { pub size_bytes: Option<u64>, pub state: ProbeState }  // :505-508
pub struct ProbeStateStore { inner: Mutex<ProbeStoreInner> }              // :511-514
struct ProbeStoreInner { results: HashMap<u64, ProbeRecord>, inflight: HashSet<u64> }  // :516-520
// 方法：cached(:530) / begin(:535) / abort(:540) / finish(:544) / all(:550)；锁中毒恢复(:523-528)
```

| 维度 | 现状 |
|---|---|
| 生命周期 | Tauri managed state（lib.rs:21 `.manage(...)`）；**会话级、进程内存**，进程退出即消失（重启空列表已经 run4 验证）；无持久化 |
| 保存内容 | 仅**结果**（size_bytes + Ready/Failed）与**条目 ID 在途标记** |
| 并发模型 | `std::sync::Mutex` + 中毒恢复（:523-528）；命令层在 `await` 之外持锁时间极短 |
| 是否保存运行中任务 | **否**——inflight 只是 `u64` ID 集合；`spawn_blocking` 的 JoinHandle 未保存（probe.rs:719 直接 await） |
| 是否保存 ChildHandle | **否** |
| 是否支持 shutdown | **否**——无任何方法/钩子与退出流程交互；begin/abort/finish 仅由探测流程自身调用 |

---

## 5. 当前代码位置索引

| 关注点 | 文件:行 |
|---|---|
| 应用入口/Builder/托管状态注册 | `lib.rs:15-31`（`manage(ProbeStateStore)` :21；`.run()` :30；**无退出钩子**） |
| `main.rs` | `main.rs:4-6`（仅调用 `clipforge_lib::run()`） |
| 子进程创建（**全应用唯一**） | `probe.rs:269-283`（grep 证实 `Command::new` 仅此一处） |
| 参数构造（OsString 安全传递） | `probe.rs:237-247` |
| 超时轮询/终止/回收 | `probe.rs:299-323`（轮询）、`:344-366`（超时 kill+wait+join）、`:311-312`（try_wait 出错兜底） |
| 探测命令（async，缓存/防并发/force） | `probe.rs:695-741`（spawn_blocking :719-724；finish :739） |
| 结果列表命令 | `probe.rs:745-751` |
| 状态存储结构与方法 | `probe.rs:498-560` |
| 视图构建（UI 字段映射） | `probe.rs:643-693`（build_view :657） |
| 发现顺序（含 Debug 覆盖） | `probe.rs:109-223`（discover_ffprobe :109；effective_timeout_ms :226；debug-only 覆盖 `test_overrides.rs`，由 `lib.rs:4-5` cfg 控制） |
| JSON 唯一解析点 | `probe.rs:428-491`（serde_json::from_slice :430） |
| 前端调用点 | `App.tsx:104-117`（runProbe）、`:119-141`（handleImportClick）、`:140`（即发即忘）；`importApi.ts:74-76` |
| 导入核心（2A 冻结，勿动） | `import.rs:100`（create_entry）、`:219/:225`（命令）、`:84`（ImportState） |

---

## 6. 风险评估

| 风险 | 等级 | 原因（依据） |
|---|---|---|
| 关闭窗口产生孤儿进程 | **高** | 结构性：句柄局部化（probe.rs:269）+ 无退出钩子（lib.rs:30）+ Windows 不级联终止；**已实证**（S6b 孤儿 1 个） |
| 多任务并发退出 | **高** | 不同条目可同时在途（inflight 是 ID 集合，各条目独立 begin）；N 个在途 → N 个孤儿；延迟替身场景下每个孤儿最长存活至其自然结束（替身 120s；真实 FFprobe 通常秒级，但大文件/网络盘可拉长） |
| 超时与关闭竞态 | **中** | 关闭与 30s 超时窗口重叠时：最坏结果等同孤儿（同上）；`finish` 写缓存与进程退出竞态最多丢失一条会话级记录，无数据损坏、无磁盘残留 |
| 重试期间关闭 | **中** | force 重试走同一路径（probe.rs:719）；UI"解析中"态随进程消失，无持久影响；孤儿风险同上 |
| 状态残留 | **低** | ProbeStateStore 纯内存、会话级（重启清空已验证）；无注册表/文件/环境残留；唯一的"残留物"即孤儿进程本身（已单列） |

补充说明（非本次范围但相关）：探测管线**无临时文件**（stdout/stderr 走管道，probe.rs:286-297），不存在磁盘级清理问题；`pick_video_file` 与导入核心无子进程，无生命周期风险。

---

## 7. 后续修复建议（仅建议，不实施）

> 目标（对应 D-0024 第 3 条）：窗口关闭时终止并回收全部在途 FFprobe 子进程，使 S6b 场景实测 orphan=0；不新增应用依赖、不改动 2A 冻结语义、不回归 Gate-2A/2B 已验收行为。

1. **退出钩子（lib.rs）**：由 `.run(ctx)` 改为 `Builder::build(ctx)` + `run_event` 循环，在 `RunEvent::ExitRequested`（或 `Exit`）中执行受控关闭后 `app.exit(0)`——Tauri 2 官方模式，零新依赖。
2. **在途任务注册表（probe.rs）**：扩展 `ProbeStoreInner`：保存"可取消任务句柄"。两种候选（实施时择一，需在授权步骤确认）：
   - **A. 取消令牌**（推荐）：每任务持 `Arc<AtomicBool>`（std-only）+ 轮询循环（probe.rs:300-308）在每次 `try_wait` 间隔检查令牌，置位即走既有 kill+wait 分支（:347-348 逻辑天然复用）；退出钩子遍历置位全部令牌并等待任务收敛。
   - B. 句柄登记表：保存 `Child`（Mutex<HashMap<u64, Child>>），退出钩子直接 kill+wait——并发所有权更复杂，且 `probe_file` 需改为借用句柄，侵入面更大。
3. **收敛确认**：退出前等待 inflight 清空（带总时限，例如 ≤2s，超时记录日志后退出），保证"终止 + 回收（wait）"完整。
4. **验证方案**：复用 S6b 场景（延迟替身 + 在途关闭），断言 `orphan=0`、退出耗时仍在秒级、正常关闭/取消/超时/重试全部回归；debug/release 行为一致（这是**产品行为**，与仅 Debug 的测试覆盖机制无关，不得用 `#[cfg(debug_assertions)]` 实现）。
5. **文档闭环（顺带建议）**：补记缺失的 Stage-2B 阶段报告文件（§1.3 缺口），可在同一授权批次处理，满足规格 §9 规则 2 的落盘要求。

---

## 8. 本次执行声明

只读检查命令：`pwd/git status`、`ls --time-style`、`sha256sum`（17 个关键文件）、`find -newermt`（变化检测）、进程/环境变量查询、`grep -n`/`cat -n`（代码定位与读取，含 probe.rs 三个关键区段精读）、`wc -l`。唯一写入动作：新建本报告文件。未修改 `probe.rs`/`lib.rs`，未增加 shutdown handler，未开始修复。

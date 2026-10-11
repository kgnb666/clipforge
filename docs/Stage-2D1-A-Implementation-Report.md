# Stage 2D-1-A Implementation Report（规格闭环 + 日志基础设施）

- 日期：2026-10-11
- 裁决依据：用户裁决**方案 (a)**（缩略图移交后续阶段；Stage 2D = 已有能力最终验收）
- **Gate-2D1-A 判定：PASS**

---

## 1. 修改文件清单（含哈希与原因）

| 文件 | 状态 | SHA256(前 16) | 原因 |
|---|---|---|---|
| `src-tauri/src/logging.rs` | **新增** | `b5c92f9fae3d818e` | ARCH-011 日志基础设施（std-only）：5 MiB 轮转 / 保留 3 份 / 单行净化 / 自愈重建 / 事件日志 API；含 5 项单测 |
| `src-tauri/src/lib.rs` | 修改 | `1f9c167e84a9382a` | 日志初始化（`app.path().app_local_data_dir()\logs`，应用路径 API 构造，失败仅禁用日志）；Exit 钩子追加 `shutdown cleanup` 日志行（既有 println 保留） |
| `src-tauri/src/probe.rs` | 修改 | `bee57a7c8e160556` | 生命周期六事件旁路日志：register（2 处登记点）/ start（Running 置位后）/ complete / failed / cancelled（`log_terminal`，按最终结果分类）——纯旁路，不改任何返回值、状态机或语义 |
| `docs/requirements-and-acceptance.md` | 修改（v1.2→**v1.3**） | `8ce03ea56587150b` | Step 1 规格闭环：版本行/依据行/§3.1/P2D-001/P2D-006/Gate-2C 注记/§7 移交说明/§12 修订行（D-0027） |
| `docs/decision-log.md` | 修改 | `7fba76b6d9488f45` | 追加 **D-0027**（2C 范围重定向确认 + 缩略图移交 + 2D 目标调整；编号经实测核验 D-0026→D-0027） |
| `docs/evidence/stage2/2d/*`（10 项） | 新增 | — | 本阶段证据（见 §3） |
| `docs/evidence/stage2/2a/gate2a-ui-helper.ps1`、`2b/gate2b3-ui-helper.ps1` | 一行附加式 | — | 场景映射补 `truncated`/`samplea`/`lockcheck`（测试装置，不改既有场景） |
| `clipforge/dist/*` | 构建产物 | — | npm run build 再生 |

**禁改文件全部原样**（12 项哈希与 2D-1 基线一致）：`import.rs`、`picker.rs`、`probe_lifecycle.rs`（**生命周期状态机零改动**——日志为旁路调用）、`Cargo.toml`/`Cargo.lock`（零依赖）、`package.json`/锁、`capabilities`、`tauri.conf.json`、`App.tsx`/`importApi.ts`/`App.css`（UI/IPC 零改动）。

## 2. Step 1 规格闭环内容（v1.3 + D-0027）

- **偏差记录**：原 v1.2 Gate-2C 缩略图规划与实际执行路线存在偏差——实际 Stage 2C = 生命周期增强（2C-1/2/3，已 PASS 2026-10-11），该结论不受影响。
- **缩略图延期**：P2C-001~008 及相关缓存验证移交后续阶段（Stage 3 或另行授权）；§7 加移交说明；§3.1 阶段描述更新。
- **P2D 调整**：P2D-001 = "导入→元数据"端到端 + 全链路源保护复核；P2D-006 = "FFmpeg 受控缺失时元数据不受影响"。**Gate-2D 判据其余不变**；条目数量与编号不变（54）。
- 修订位置：版本行、依据行（D-0027 为 v1.3 依据）、§3.1、§7、§9 Gate-2C 行、P2D-001/006、§12。

## 3. Step 3 验证结果（全部实际执行）

| 要求 | 结果 | 证据 |
|---|---|---|
| 1. cargo test | **EXIT=0，58 passed / 0 failed / 7 ignored / 0 警告**（新增 5 项日志单测） | `stage2d1a-cargo-test.log` |
| 2. npm build | **EXIT=0** | `stage2d1a-npm-build.log` |
| 3. 日志轮转实测 | **PASS**（直测内部函数，注入 200B 上限 ×30 行写入）：`clipforge.log`/`.1`/`.2` 三份存在、`.3` 不存在、最旧内容（line 001）滚出窗口、最新内容保留 | `stage2d1a-cargo-test.log`（logging_rotation_direct_state） |
| 4. 生命周期日志样例（实机，六事件全采） | **PASS** | `stage2d1a-lifecycle-log-sample.log`：`application start` / `task register` / `task start` / `task complete` / `task failed code=FFPROBE_NONZERO_EXIT` / `task cancelled code=FFPROBE_CANCELLED` / `shutdown cleanup cancelled=1 reaped=1 remaining=0 peak=1 elapsed_ms=33` |
| 5. 2A/2B/2C 行为回归 | **PASS** | `stage2d1a-regression2.log`：特殊字符导入+元数据（1.18 MiB）✓、重复导入"已在列表中"✓、失败态（moov atom）✓、在途关闭 cancelled=1 reaped=1 + 替身零残留 ✓、两次会话干净退出 0 残留 |
| 6. 修改文件清单与哈希 | 见 §1 | — |
| 7. 禁改文件哈希核验 | **12 项全部一致** | 见 §1 与收尾核验 |

ARCH-011 数值对照（D-0020）：目录 `%LOCALAPPDATA%\com.clipforge.app\logs\`（`app.path().app_local_data_dir()` 构造，dev 日志可见 `[logging] initialized at C:\Users\宋舜江\AppData\Local\com.clipforge.app\logs`）✓；5 MiB（5,242,880）✓ 常量单测；3 份 ✓ 单测+实测；stderr 8 KiB ✓（probe.rs 既有）。

## 4. 风险与剩余问题

1. **并发测试共享全局 logger**：单测并发写同一全局日志（注入 200B 上限）使具体行号断言不确定——已改为结构性断言（文件份数/轮转发生/最旧滚出）并对交错稳健；生产 5 MiB 上限下无此问题。
2. 实机日志当前仅 1.6KB（< 5 MiB），生产轮转的长期行为由单测（注入上限）证明，真实 5 MiB 触发留待 2D-B 长稳观察（可在 2D-B 长稳循环后核对 `.1/.2` 出现）。
3. 一次 UIA 对话框时序抖动导致首轮回归作废（诚实记录于 `stage2d1a-regression.log`：`dialog_closed=False`），以分步驱动重做通过；非代码回归（日志证明探测从未发生）。
4. 遗留：P2D 矩阵执行（2D-1-B）与完整回归/判定（2D-1-C）按计划待授权。

## 5. Gate-2D1-A 判定：**PASS**

依据：D-0027 + 规格 v1.3 经 §1 变更控制闭合；ARCH-011 全量落地且数值与 D-0020 一致；六事件日志全部有实机样例；cargo/npm/行为回归全绿；禁改范围零触碰；过程中的失败（测试预期错 3 处、编译错 1 处、UIA 抖动 1 次）全部留痕并修正。

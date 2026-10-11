# Stage 2A 实施报告（v2 · 授权解除后的完整实施与 Gate-2A 验收）

- 日期：2026-10-10（v1 为依赖未授权时的 BLOCKED 版；v2 为授权 `cargo add tauri-plugin-dialog@2.8.1` 并采用 Rust 侧调用方案后的完整实施与验收；**v3 追加 §10：缺口闭合补测与 Gate-2A 最终判定**）
- 依据：`docs/requirements-and-acceptance.md`（v1.2）P2A-001 ~ P2A-010、Gate-2A 定义（含 P2D-008/009）；`docs/decision-log.md` D-0013、D-0022 等
- **Gate-2A 最终结论：PASS**（2026-10-10 缺口补测全部闭合，逐条依据见 §10.6；v2 的历史结论 CONDITIONAL PASS 已被 §10 取代）。**未进入 Stage 2B。**

---

## 1. 依赖安装结果与版本（授权范围内）

| 项 | 结果 |
|---|---|
| 命令 | `cargo add tauri-plugin-dialog@2.8.1`（在 `clipforge\src-tauri`），EXIT=0（7s，`stage2a-cargo-add-dialog.log`） |
| 实际版本 | **tauri-plugin-dialog 2.8.1** + 锁定 13 个包（rfd 0.16.0、tauri-plugin-fs 2.6.0、windows-sys 0.60.2、windows-targets 0.53.5 等） |
| 修改的锁/清单 | `src-tauri/Cargo.toml`（`tauri-plugin-dialog = "2.8.1"`，哈希 `10cc6855…`）、`src-tauri/Cargo.lock`（`f5bd42fb…`）——均为本次授权允许的改动 |
| npm 包 `@tauri-apps/plugin-dialog` | **未安装、不需要**：采用 Rust 侧调用方案后前端只调用自有命令 `pick_video_file`；`package.json` / `package-lock.json` 哈希复核 **OK（未变）** |
| capabilities | **未变更**（哈希 OK）：Rust 侧调用不经过 WebView ACL，零权限扩权 |
| 过滤器 | `视频文件 = mp4, mkv, mov, avi, webm, m4v, ts, flv, wmv` + `所有文件 (*.*)`（与 P2A-010 冻结集合一致） |

## 2. 修改文件与关键差异（v1 → v2）

| 文件 | 状态 | 说明 | SHA256(16) |
|---|---|---|---|
| `src-tauri/src/picker.rs` | 新增 | `pick_video_file` 命令：Rust 侧 `blocking_pick_file`（置于阻塞线程池），返回完整路径或 `None`（取消） | `789a1387…` |
| `src-tauri/src/lib.rs` | 修改 | 注册 `tauri_plugin_dialog::init()` 与 `picker::pick_video_file`；`greet` 保留 | `4f00a3a7…` |
| `src/importApi.ts` | 修改 | 新增 `pickVideoFile()`（`invoke("pick_video_file")`） | `ea9c5ae5…` |
| `src/App.tsx` | 修改 | 导入按钮接线：对话框 → `createImportEntry` → 去重提示；busy 防重入（按钮显示"选择中…"） | `598deab6…` |
| `src-tauri/src/import.rs` | **未改** | 按约束保留既有校验/判重/只读保护核心（哈希 `ee4d3d9b…` 与 v1 一致） | `ee4d3d9b…` |
| `src/App.css` | 未改 | 无需样式变更（`8f510709…`） | `8f510709…` |
| `Cargo.toml` / `Cargo.lock` | 修改（授权） | 见 §1 | — |
| `docs/evidence/stage2/2a/**`、`test-assets/**` | 新增 | 证据与测试素材（清单见 §8） | — |

## 3. P2A-001 ~ P2A-010、P2D-008/009 逐项验收结果

| ID | 结论 | 证据（可复核） |
|---|---|---|
| P2A-001 原生对话框导入 | **通过** | 真实对话框打开（标题"选择视频文件"，类 `#32770`）；经对话框导入 `样本 视频 #1 (初版)'s.mkv` 成功，条目显示「已导入（路径校验通过）」；截图 `stage2a-ui-dialog-special.png`、`stage2a-ui-entry-special.png`；`stage2a-ui-cycles.log`（Cycle A） |
| P2A-002 取消选择 | **通过** | `import-cancel`：UIA 点击真实"取消"按钮 → `dialog_closed=True`；之后列表无新增条目、无错误提示、界面恢复；日志 Cycle B + `stage2a-ui-cancel.png` |
| P2A-003 只读/源文件不变 | **通过** | 导入前基线 SHA256 `5D511034…` + mtime `18:03:07.63`；经真实对话框导入后逐字节一致（`stage2a-p2a003-verify.log`，更正版脚本）。**自披露**：首次校验脚本存在 `null==null` 假阳性，已作废并重做 |
| P2A-004 不存在/无效路径 | **部分（环境受限）** | 逻辑级：单测 `nonexistent_path_fails_with_not_found`、`empty_path_fails_with_invalid_path` 通过；UI 级：系统对话框在 OK 时校验文件存在性并自行拦截，应用无法经该流程收到"不存在的路径"（无法复现失败态 UI）。缺口如实记录 |
| P2A-005 无权限文件 | **部分（环境受限）** | 按 §10.2 完整执行 ACL 规程（单文件、最小范围）：拒绝后读取被拒（错误文本在案）→ **系统对话框自身弹出"没有打开该文件的权限"并拒绝返回路径**（截图 `stage2a-ui-acl-os-block.png`）→ **恢复验证四项全部 True**（ACL 复原/DENY 移除/哈希不变/读取恢复，`stage2a-p2a005-acl.log`）。缺口：应用侧"权限不足"UI 态在标准流程中不可达 |
| P2A-006 不按扩展名判定 | **通过** | 文本内容的 `fake_text.mp4` 与无扩展名 `no_extension_sample` 均经真实对话框导入为「已导入」（不做内容/扩展名媒体判定；媒体判定属 2B）；`stage2a-ui-entry-fake-noext.png` + 日志 Cycle D |
| P2A-007 重复导入去重 | **通过** | 同一文件二次经对话框导入 → 界面提示「已在列表中：样本 视频 #1 (初版)'s.mkv」，不新增条目；`stage2a-ui-duplicate.png` + 日志 Cycle C |
| P2A-008 状态可区分 | **部分**（成功态通过，失败态环境受限） | 成功态：多个条目徽标「已导入（路径校验通过）」+ 路径截断/展开（`stage2a-ui-entry-expanded.png`）；失败态：见 P2A-004/005 缺口 |
| P2A-009 特殊字符路径 | **通过** | `测试 目录 & 素材 #1 (终版)'s\样本 视频 #1 (初版)'s.mkv` 全链路成功；条目文件名逐字一致、路径截断显示且完整值保留（展开截图 + UIA 文本双证） |
| P2A-010 过滤器定义 | **通过** | 对话框过滤器实测为 `视频文件 (*.mp4;*.mkv;*.mov;*.avi;*.webm;*.m4v;*.ts;*.flv;*.wmv)`（与规格集合逐项一致）；UIA 实测切换到 `所有文件 (*.*)`（`stage2a-ui-dialog-filter-video.png`、`stage2a-ui-dialog-filter-allfiles.png`）；集合外扩展名文件成功导入（P2A-006） |
| P2D-008 取消选择 | **通过** | 同 P2A-002（另：更早一次以窗口关闭（X）方式取消，应用同样回到正常态、无条目无错误） |
| P2D-009 重复导入 | **通过** | 同 P2A-007 |

## 4. 执行记录（关键命令、退出码、时间线）

| 执行项 | 结果 | 证据 |
|---|---|---|
| `cargo add tauri-plugin-dialog@2.8.1` | EXIT=0 | `stage2a-cargo-add-dialog.log` |
| `cargo test`（接入插件后） | **9 passed / 0 failed**（26s） | `stage2a-cargo-test2.log` |
| `npm run build`（tsc+vite，共 3 次含基线） | 全部 EXIT=0 | `stage2a-before/after-npm-build.log`、`stage2a-npm-build-3.log` |
| UI 验收（UIA 驱动真实对话框） | Cycle A（导入/截图）、A2（展开路径）、B（取消）、C（重复）、D（fake+noext）、E/E2（过滤器）、F（ACL）、G（占用文件）、I/I2（长路径尝试） | `stage2a-ui-cycles.log`（约 40 次辅助调用逐条记录） |
| `tauri dev` run3（含全部 UI 验收） | 窗口正常；关闭后 **≈1.1s 全链路退出、0 残留、端口 1420 释放** | `stage2a-dev3.log` |
| `tauri dev` run4（最终重启） | 窗口重现（24s 内）、Responding=True、空列表态（会话级内存，符合设计）；关闭后同样干净退出 | `stage2a-dev4.log`、`stage2a-ui-run4-final.png` |
| Gate-2A 直接相关回归（窗口显示/响应/关闭/重启） | **通过**（两轮；含 UIA 真实点击与整体导入流程） | 同上 |

## 5. 源文件只读保护（P2A-003）与权限测试结果（P2A-005 / §10.2）

- **只读保护**：导入核心仅 `File::open` 只读校验；导入前后 SHA256 与 mtime 逐字节一致（§3 P2A-003）。源文件（含 4 个测试副本与特殊字符素材）哈希全程可复查。
- **ACL 规程执行合规性**：仅对专用副本 `acl-test-copy.mkv` 操作；改前记录路径/原 ACL/用户/哈希；最小范围（单文件、拒绝当前用户 `(RD)`）；**无条件恢复并验证**：`acl_restored=True`、`deny_removed=True`、`hash_unchanged=True`、`read_works_again=True`；未使用递归、未触碰父目录、未修改系统 PATH/注册表。
- **重要发现（产品级）**：待选文件不可读时，**Windows 系统对话框自身拦截**（提示"没有打开该文件的权限"，不把路径交给应用）——即经标准选择流程，应用实际不会收到无权限路径；应用侧仍保留"权限不足"分类（供未来拖拽/CLI 等入口使用）。
- **占用文件场景**（附加）：另一进程以"仅共享读"持锁的文件经对话框导入**成功且正确**（共享读不阻止读取，行为合理）。

## 6. 环境受限项与自动化限制（如实记录）

1. **失败态 UI 不可达**：不存在（对话框校验存在性）与无权限（对话框校验可读性）两类路径均被 OS 层拦截；断链符号链接方案需管理员权限（已尝试，报"此操作需要管理员权限"）；超长路径（270 字符）方案中 ValuePattern 拒绝写入且剪贴板路径落点偏离（`stage2a-ui-longpath-attempt.png`）。⇒ P2A-004/005/008(失败态) 的 **UI 级未复现**，逻辑级以 9/9 单元测试为证。
2. **长路径附加观察**（对应既有 P1-5 风险）：素材 `test-assets\lp\…（270 字符）\deep-file.mkv` 经 `\\?\` 可访问、普通 Win32（LongPathsEnabled=0）不可访问；系统对话框可正常导航长路径目录（Shell 能力）；应用侧对 >MAX_PATH 路径的导入行为待后续阶段评估（素材保留待用）。
3. **UIA 自动化方法学沉淀**：本机文件对话框为 DirectUI 结构（文件名控件 = 三枚 `autoid=1148` Pane、按钮为 Pane/Button、**列表项 autoid 与按钮 ID 冲突 0,1,2…**——已修复选择器）；`LegacyIAccessiblePattern` 在 PS 5.1 不可解析（已容错）；IME 注入窗口 `SoPY_Status` 会污染窗口枚举（已用"仅认 `#32770`"排除）；`.NET MainWindowHandle` 在对话框打开期间不可靠（改为按"剪辑窗口标题+Tauri Window 类"选择）。辅助脚本 `gate2a-ui-helper.ps1` 全量留档供后续阶段复用。
4. **自披露的脚本缺陷**（均已更正并在日志留痕）：P2A-003 校验的 `null==null` 假阳性；首版辅助脚本"按 autoid 点按钮"误点列表项导致对话框误航；一次 `msgbox_dismissed=True` 误导输出（实际未点击，后以回车正确关闭）。

## 7. Gate-2A 最终结论与遗留风险

**结论：CONDITIONAL PASS。**
- 通过项（9/12）：P2A-001、002、003、006、007、009、010、P2D-008、P2D-009 —— 均有真实执行证据（对话框/UI 截图 + UIA 文本 + 日志 + 哈希）。
- 受限项（3/12）：P2A-004、P2A-005、P2A-008 的"失败态 UI 显示"——被 Windows OS 层拦截 / 特权限制，**未以降低标准方式规避**，缺口如实保留。
- 判定依据：Gate-2A 规则 1/2/3/4/5 均满足或已按规则 6 如实记录；因存在未达成的 UI 级验收点，**不判 PASS**；因无架构性缺陷、逻辑级完备且有明确后续路径，**不判 BLOCKED/FAIL**。

**遗留风险与建议**：
1. 失败态 UI 的最终验证需要另一个不受 OS 对话框预校验约束的入口（建议在后续阶段引入拖拽或受控测试入口），或接受 OS 层防护为主、以逻辑级测试为准——**请开发者在授权下一阶段时裁定**。
2. 长路径（>MAX_PATH）导入行为属既有 P1-5 风险，素材已保留，建议随 Stage 3 打包阶段一并复核。
3. 条目为会话级内存（重启即清空）——当前设计语义，已在报告与规格范围内；如需持久化属新需求，不得擅自实现。

## 8. 证据文件索引（`docs/evidence/stage2/2a/`）

- 日志：`stage2a-cargo-add-dialog.log`、`stage2a-cargo-test2.log`、`stage2a-npm-build-3.log`、`stage2a-dev3.log`、`stage2a-dev4.log`、`stage2a-ui-cycles.log`（主验收日志）、`stage2a-p2a003-baseline/verify.log`、`stage2a-p2a005-acl.log` + `stage2a-p2a005-acl-before.txt`、`stage2a-frozen-hashes.log`
- 截图：`stage2a-ui-dialog-special.png`、`stage2a-ui-entry-special.png`、`stage2a-ui-entry-expanded.png`、`stage2a-ui-cancel.png`、`stage2a-ui-duplicate.png`、`stage2a-ui-entry-fake-noext.png`、`stage2a-ui-dialog-filter-video.png`、`stage2a-ui-dialog-filter-allfiles.png`、`stage2a-ui-acl-os-block.png`（OS 拦截证据）、`stage2a-ui-entry-locked.png`、`stage2a-ui-longpath-attempt.png`、`stage2a-ui-run4-final.png`
- 工具与素材：`gate2a-ui-helper.ps1`（UIA 驱动脚本）；`../test-assets/`（含特殊字符路径、无扩展名、伪装扩展名、ACL 副本、占用副本、超长路径树）
- 冻结哈希：`package.json`/`package-lock.json`/`capabilities/default.json`/`tauri.conf.json`/`main.rs`/`index.html`/需求文档/决策日志 **8 项全部 OK（未变）**

## 9. 声明

本次**未实施** Phase 2B/2C/2D 的任何功能；**仅安装了**获授权的 Rust 依赖（npm 包未安装）；**未修改** `package.json`/`package-lock.json`/capabilities/tauri.conf/需求文档/决策日志（哈希为证）；ACL 测试仅针对专用副本且完成恢复验证；**未执行** Git 初始化/提交/推送；**未进行**打包发布；未替换/删除系统 FFmpeg/FFprobe；无 shell 字符串拼接执行外部命令。Gate-2A 完成即停止，等待审查与下一阶段明确授权。

---

## 10. 缺口闭合补测与 Gate-2A 最终判定（v3 追加，2026-10-10）

> 前置：本节所有结果均经**实际读取证据文件**核验（非执行摘要转述）：`docs/evidence/stage2/2a/stage2a-fix-*.log/png`、`stage2a-fix-p2a005-acl2.log`、`stage2a-fix-ui-texts.log` 等。

### 10.1 补测执行结果（N-1 ~ N-4、R-1，全部实际执行）

| 项 | 结论 | 实测结果与证据（`docs/evidence/stage2/2a/`） |
|---|---|---|
| N-1（P2A-004 失败态） | **PASS** | 注入不存在路径 `ghost-file.mp4` → 数据层 `{"status":"failed","errorCode":"NOT_FOUND","errorMessage":"文件不存在或无法访问"}`（`stage2a-fix-cdp-calls.log` 第 6 行）；UI 渲染"导入失败 + 文件不存在或无法访问（NOT_FOUND）"（`stage2a-fix-ui-texts.log` 21:08:35 段；截图 `stage2a-fix-p2a004-ui.png`/`stage2a-fix-p2a008-states.png`，三张同源截图哈希 `62cf04f6…` 同一画面） |
| N-1b（超长路径观察项） | **如实记录（非失败）** | 270 字符路径 → `{"status":"ready"}`（`stage2a-fix-cdp-calls.log` 第 9 行；UI 显示"已导入（路径校验通过）"及截断路径）。与评估预期相反的原因与适用范围见 §10.4；**未改写为失败** |
| N-2（P2A-005 应用层失败态） | **PASS** | ACL 拒绝活动期内注入 `acl-test-copy.mkv` → `{"status":"failed","errorCode":"PERMISSION_DENIED","errorMessage":"权限不足：无法读取所选文件"}`（`stage2a-fix-cdp-calls.log` 第 12 行）；UI 渲染"权限不足：无法读取所选文件（PERMISSION_DENIED）"；与 N-1 的错误码/文案形成可区分对照（`stage2a-fix-ui-texts.log`；截图 `stage2a-fix-p2a005-ui.png`） |
| N-3（P2A-008 可区分对照） | **PASS** | 同一视图并存：2 条红色"导入失败"（两种不同错误码/文案）+ 2 条绿色"已导入（路径校验通过）"（`stage2a-fix-p2a008-states.png` 已人工核验画面） |
| N-4（失败后恢复） | **PASS** | 失败条目在场时经**真实对话框**再导入 `fake_text.mp4`：`dialog_closed=True`、新条目成功、失败条目不干扰、Responding 全程 True（`stage2a-fix-ui-texts.log` 21:09:11 段；截图 `stage2a-fix-recovery.png`，5 条目并存） |
| R-1（回归） | **PASS** | `cargo test` **9/9、EXIT=0**（`stage2a-fix-cargo-test.log`）；窗口显示/响应/关闭（关闭后 ≈1.1s 全链路退出、0 残留、端口释放；`stage2a-fix-dev.log` EXITED 标记） |
| 触发通道冒烟（前置） | 通过（非业务证据） | CDP 只读端点 200、仅 `127.0.0.1` 监听、属主为本应用 msedgewebview2——**该连通性验证本身不作为业务验收证据**，业务证据均为应用自身行为（条目状态 + UI 渲染） |

### 10.2 ACL 恢复四验（第二次执行）

`acl_restored_equal=True`、`deny_removed=True`、`hash_unchanged=True`（前后均 `5D511034…`）、`read_works_again=True`；拒绝窗口 21:05:45 → 21:06:52（约 67 秒）；规程要素（单文件、最小范围 `(RD)`、改前记录、无条件恢复、恢复后重读 ACL + 复核哈希）全部满足（`stage2a-fix-p2a005-acl2.log` + `stage2a-fix-p2a005-acl-before2.txt`）。

### 10.3 CDP 受控测试入口：安全边界与清理结果

- 装置 `gate2a-cdp-harness.mjs`：仅连 `127.0.0.1`；页面目标必须为 `http://localhost:1420`（本应用 devUrl）才执行；注入路径强制位于 `test-assets\` 白名单内；命令仅限既有 `create_import_entry`；不安装依赖、不改源码/配置。
- 生产隔离：CDP 依赖临时环境变量（仅启动进程作用域）+ devtools（release 构建默认关闭）→ 生产构建无此通道。
- 清理核验：应用关闭后 clipforge 相关残留进程 0（含其 msedgewebview2）、端口 9333 释放、环境变量进程/用户/机器三域及 `HKCU:\Environment` 复核均为空/NOT_FOUND；期间产生的 1 个误命名临时截图已即时删除，目录无意外工件。

### 10.4 N-1b 超长路径观察及其适用范围

- 实测：270 字符路径经应用导入为 **ready**（Rust std 将绝对路径内部转换为 `\\?\` 形式，可正常打开）；同机 PowerShell/.NET 普通 API 无法访问同一路径。
- 适用范围：可据此认为**应用侧（Rust）对 >MAX_PATH 的读取正常**；**不可**据此推断打包器、其他系统工具或未来阶段的组件同样支持长路径。
- 影响：缺口评估中"应用侧预计失败"的假设被实测推翻（正面证据）；P1-5 风险面收窄至打包/工具链环节，留待 Stage 3 复核。

### 10.5 变更记录（本轮）

- 新增决策 **D-0022**（`docs/decision-log.md`）：P2A-004/P2A-005 受控测试入口，批准状态=已获用户批准，实施状态=已实施。
- 规格 **v1.1 → v1.2**（`docs/requirements-and-acceptance.md`）：仅 P2A-004/P2A-005"验收步骤"增加"触发方式（二选一）"；期望结果、错误码可区分性、§10.2 规程、证据类型、Gate 判据与条目数量（54）全部不变。
- 修改文件：`requirements-and-acceptance.md`、`decision-log.md`、本报告、`Stage-2A-Gap-Assessment.md`（哈希见最终交付信息）；**源码/依赖/配置零改动**（哈希复核一致）。

### 10.6 Gate-2A 最终判定：**PASS**（逐条对照 §9 九条规则）

| §9 规则 | 判定依据 |
|---|---|
| 1. 对应 Phase 功能已实现且范围正确 | 导入功能已实现；未实现/未触碰 2B/2C 内容（条目状态、无 FFprobe 调用） |
| 2. 测试实际执行并记录 | P2A-001~010、P2D-008/009 全部有实际执行记录（§3 + §10.1） |
| 3. 核心成功与失败场景均有证据 | 成功：对话框导入/无扩展名/伪装扩展名/特殊字符等；失败：NOT_FOUND 与 PERMISSION_DENIED 双场景 + 可区分对照（§10.1） |
| 4. 直接相关回归通过 | R-1：`cargo test` 9/9 + 窗口显示/响应/关闭（§10.1） |
| 5. 无未解决 P0 | 无 P0 遗留 |
| 6. 未删除失败测试、未降低标准 | 触发方式变更经 D-0022 + 规格 v1.2 正式记录，**期望结果与判据未动**；N-1b 预期偏差如实保留（§10.4） |
| 7. 不通过即停止 | 全部必需项通过，无需触发停止 |
| 8. PASS 基于实际测试结果 | 本报告 §3/§5/§10 证据均可复核（文件名、行号、哈希） |
| 9. 不得提前宣布 | 本判定于全部补测执行与证据核验完成后作出 |

**结论：Gate-2A = PASS。** 注：规格 §1 的状态词集合不含"已通过"类取值，各条目状态列维持 v1.2 现状不改；验收结论以本报告与证据记录为准。允许（经开发者明确授权后）进入 Gate-2B 阶段。

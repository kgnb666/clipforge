# ClipForge 决策日志（Decision Log）

> 记录格式：日期 | 决策 | 背景与选项 | 决策理由 | 影响与验证证据。
> 原则：只记录真实发生的决策；被否决的方案与失败尝试同样保留。

---

## D-0001 | 2026-10-10 | 技术栈维持 Tauri 2 + React + TypeScript + FFmpeg/FFprobe CLI + Rust 后端

- 背景：Stage 0 审计要求评估候选方案的可行性、三天风险、分发与安全边界。
- 选项：维持候选方案 / 更换为 Electron + Node FFmpeg 封装 / 纯 Web Demo（被排除，不满足"桌面应用"要求）。
- 决策：**维持候选方案**。Stage 0 审计结论：环境层面无架构性阻塞，仅有三个"工具缺失但安装路径已验证"的流程性阻塞（Rust、MSVC、FFmpeg）。
- 影响与证据：`docs/stage-0-audit.md` 第 3、11 节；CONDITIONAL PASS 及三项条件。

## D-0002 | 2026-10-10 | 依赖安装全部使用 winget 且不换源

- 背景：开发者授权安装 Rust 工具链、VS 2022 Build Tools（MSVC C++ 组件 + Windows SDK）、FFmpeg/FFprobe。
- 选项：winget（Stage 0 已核实的渠道）/ 手动下载安装包 / 第三方镜像。
- 决策：**全部使用 winget 且严格使用 Stage 0 记录过的软件包 ID**，来源、版本、哈希变化时必须暂停报告。
- 实际核实结果（安装前，与 Stage 0 记录一致）：
  - `Rustlang.Rustup` 1.29.1；安装程序 URL `https://static.rust-lang.org/rustup/archive/1.29.1/x86_64-pc-windows-msvc/rustup-init.exe`；SHA256 `6f4bef66261261fcb43131be8720bab817d403a09edec7455c371974b90bdb7e`
  - `Microsoft.VisualStudio.2022.BuildTools` 17.14.41；安装程序类型 exe；SHA256 `37bb0fb429d163ecebd272a865d11a37b906d152bef960da2ddb29c2e2fd6eeb`
  - `Gyan.FFmpeg` 9.0.2；安装程序类型 portable (zip)；许可证 GPL-3.0；SHA256 `759d0a9831c436a0eb331ad36f236c06cb04aaa0005da46571f0e9d3d9206f6b`
- 影响与证据：`docs/test-report.md` 安装章节；安装日志 `D:\cargo-target\logs\stage1-*-install.log`。

## D-0003 | 2026-10-10 | Rustup 目标工具链 x86_64-pc-windows-msvc

- 背景：Tauri 2 在 Windows 官方要求 MSVC 工具链；GNU 工具链无官方打包支持。
- 决策：使用 Rustup 默认 host（x86_64-pc-windows-msvc），不引入 GNU/交叉目标。
- 验证：安装后 `rustup show` 输出 Default host: x86_64-pc-windows-msvc；`rustup target list --installed` = `x86_64-pc-windows-msvc`；rustc 1.99.0 / cargo 1.99.0（stable）。

## D-0004 | 2026-10-10 | VS Build Tools 安装选项：VCTools 工作负载 + 显式 VC.Tools.x86.x64 + includeRecommended，`--nocache`

- 背景：Tauri/Rust 在 Windows 需要 MSVC 编译器 + Windows SDK + MSBuild；C 盘安装前余量约 21.9GB（91% 已用）。
- 选项：完整 "Desktop development with C++" 工作负载（含 IDE 调试器等无关组件）/ 最小 VCTools 工作负载（含推荐组件）。
- 决策：`--add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --includeRecommended`，附加 `--quiet --wait --norestart --nocache`。**不安装无关工作负载**；`--nocache` 用于安装后移除包缓存以节约 C 盘空间。
- 影响与验证：见 `docs/test-report.md` 安装章节与 Gate-0A（链接成功即为最终证据）。

## D-0005 | 2026-10-10 | Cargo 构建产物目录移至 D:\cargo-target

- 背景：C 盘安装前仅剩约 21.9GB；Tauri debug 构建产物通常数 GB。
- 决策：设置**用户级环境变量** `CARGO_TARGET_DIR=D:\cargo-target`（开发者指令明确要求），不清理任何既有缓存。
- 影响与验证：`docs/test-report.md` 预检章节记录设置结果；后续构建产物均落在 D 盘。

## D-0006 | 2026-10-10 | 所有安装与构建命令在 PowerShell 中执行，不在 Git Bash 中执行

- 背景：Stage 0 发现 Git Bash 的 `$HOME` 因中文用户名显示为乱码（`/c/Users/瀹嬭垳姹�`），存在 home 解析风险（P1-4）。
- 选项：修正 Git Bash HOME / 改用 PowerShell。
- 决策：安装与构建统一在 PowerShell 执行（开发者指令明确要求）。
- 实际验证（修正 Stage 0 的保守假设）：PowerShell 内 `HOME`/`USERPROFILE` 均为正确的 `C:\Users\宋舜江`；中文参数与中文路径在 PowerShell 命令行中往返正常（`Test-Path "D:\应聘项目zcode\docs\stage-0-audit.md"` = True；UTF-8 字节数校验通过）。乱码仅存在于 Git Bash 侧显示。
- 补充要求：所有 cargo 调用显式前置 `%USERPROFILE%\.cargo\bin` 到 PATH（见 D-0007 失败记录）。

## D-0007 | 2026-10-10 | 记录一次操作失误与更正：cargo fetch 首次执行失败（PATH 未前置）

- 背景：首次 `cargo fetch` 在未前置 `%USERPROFILE%\.cargo\bin` 的 PowerShell 会话中执行。
- 结果：`CommandNotFoundException`（cargo 不在 PATH），**未产生任何下载或文件变更**；日志管道同时暴露了错误未被 `2>&1 | Add-Content` 捕获的问题。
- 更正：重跑时前置 PATH，并改用"执行后独立核验（registry 缓存/退出码）"双重确认，不依赖单一日志管道。
- 决策记录意义：该失败为执行侧失误，非环境缺陷；保留原始失败日志作为过程证据。

## D-0008 | 2026-10-10 | 应用骨架：create-tauri-app 官方模板 react-ts（Tauri 2），npm 管理，保留锁文件

- 背景：Gate-0B 要求 Tauri 2 + React + TypeScript 官方模板，锁定版本。
- 决策：`npm create tauri-app@latest clipforge -- --template react-ts --manager npm --identifier com.clipforge.app --tauri-version 2 --yes`（create-tauri-app 4.7.5）。保留 `package-lock.json`；`Cargo.lock` 由首次构建生成后保留。项目位于 `D:\应聘项目zcode\clipforge`（不散落到工作区根目录）。
- 实际安装版本（npm）：@tauri-apps/api 2.12.2、@tauri-apps/cli 2.12.1、@tauri-apps/plugin-opener 2.7.0、react/react-dom 19.3.0、typescript 6.0.3、vite 8.3.4、@vitejs/plugin-react 6.1.2（共 27 个包，55 秒）。
- 影响与证据：`docs/test-report.md` Gate-0B 章节。

## D-0009 | 2026-10-10 | 开发者业务决策基线（本阶段确认，Stage 2 起生效）

- 输出格式：**MP4 + MKV**（两种）。
- 任务调度：**默认串行**（并发 1）。
- 输出重名：**自动添加数字后缀**（不覆盖）。
- 硬件加速：**NVENC 默认关闭**（本机 nvidia-smi 存在，保留后续可选）。
- FFmpeg 分发：**暂采用系统依赖**（应用内可配置路径），sidecar 待后续评估。
- 代码托管：GitHub 将采用**公开仓库**；本阶段不创建远程仓库、不推送。
- 影响：写入 `docs/requirements-and-acceptance.md`（Stage 2 创建）与 README。

## D-0010 | 2026-10-10 | FFmpeg 获取渠道与许可证记录（GPL-3.0）

- 背景：MP4（H.264）转换需要含 libx264 的 FFmpeg 构建，Gyan 静态完整版为 GPL-3.0。
- 决策：安装 winget `Gyan.FFmpeg` 9.0.2（portable zip）；获取后记录实际路径、configure flags、二进制 SHA256 与许可证结论（详见 `docs/test-report.md` Gate-0C 与 Stage 2 的 LICENSE-NOTICE）。
- 影响：笔试演示用途，独立进程调用（非静态链接进自有二进制）；分发条款与源码指引将写入 LICENSE-NOTICE。
- 实测补充：configure flags 为 `--enable-gpl --enable-version3 … --enable-libx264 … --enable-nvenc`，**无 `--enable-nonfree`** → GPLv3 判定成立；ffmpeg.exe SHA256 `589E50B7…28D0`，ffprobe.exe SHA256 `02264DFA…5FD3`。

## D-0011 | 2026-10-10 | FFmpeg 可执行文件发现策略（应用侧，Stage 2 生效）

- 背景：winget 安装 FFmpeg 后**未**生成 `WinGet\Links` 别名，而是把安装 bin 目录写入**用户 PATH**；同时发现"已运行进程继承旧环境快照"会导致 PATH 更新对当前会话不可见（本次验证因此使用显式完整路径）。
- 决策：ClipForge 不依赖 `ffmpeg` 命令必然可见。运行时按序探测：**用户设置路径（原生文件选择器）→ PATH 查找 → WinGet Packages 常见安装目录 → 提示用户手动指定**。缺失时给出明确引导（对应验收 D3/P1-7）。
- 影响：Stage 2 的依赖检测模块与 TC-10 用例；README 的 FFmpeg 安装说明写明"安装后需新开终端生效"。

## D-0012 | 2026-10-10 | 桌面窗口证据方法论（后续阶段复用）

- 背景：首次窗口截图（`gate0b-window-run1.png`）因窗口位于 ZCode 窗口之后，屏幕捕获被遮挡，证据无效。
- 决策：窗口证据采用"**三步取证**"：(1) `SetForegroundWindow` 置前 + 屏幕捕获（含桌面环境）；(2) `PrintWindow(PW_RENDERFULLCONTENT)` 内容捕获（不受 z-order 影响）；(3) UI Automation 真实交互（如 Invoke 按钮）后再次截图，作为"窗口真实响应 + IPC 工作"的证明。
- 影响：Stage 2/3 的功能演示与最终交付证据将沿用该方法论（含打包后应用）。

---

# 以下为 Stage 2 规格修订阶段新增决策（2026-10-10；依据：用户对原 `docs/requirements-and-acceptance.md` §11 九项待确认的批准答复）

## D-0013 | 2026-10-10 | Phase 2A 原生文件选择采用 Tauri 官方 Dialog 插件（依赖引入获批）

- 背景：Phase 2A 要求"通过 Windows 原生文件选择窗口导入视频"；`capabilities/default.json` 现仅有 `core:default` + `opener:default`，不具备 dialog 能力。（原规格 §11-1）
- 决策：批准在 Phase 2A 引入 `tauri-plugin-dialog`（Rust crate）+ `@tauri-apps/plugin-dialog`（npm 包），使用 Tauri 官方插件；不引入第三方替代方案、不自研原生对话框封装。
- 理由：官方插件是与现有 Tauri 2 架构一致的最小方案，符合"避免不必要依赖"。
- 影响范围：`docs/requirements-and-acceptance.md` §2.2/§2.4、ARCH-008、P2A-001、Gate-2A。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未安装**。安装必须在 Phase 2A 获得**单独的执行授权**后进行；安装时须记录实际版本与锁文件（`package-lock.json`、`Cargo.lock`）变化。**获批 ≠ 已安装**。

## D-0014 | 2026-10-10 | FFprobe 元数据调用 30 秒硬超时与子进程终止（原 §11-2）

- 背景：P2B-009 原将超时值留作待确认。
- 决策：单次 FFprobe 调用**硬超时 30 秒**；超时后**必须终止该次调用对应的子进程**（不能只停止 UI 等待）；显示明确超时错误并**允许重试**；窗口保持响应；失败不得污染其他条目状态；必须验证超时后**无该调用的遗留 FFprobe 子进程**；超时验证采用受控测试方式（不得依赖真实视频必然耗时 30 秒以上）；测试报告须记录实际耗时、进程退出/终止证据、重试结果。
- 理由：防止挂起占用与"假等待"；子进程终止是可验证的硬性要求。
- 影响范围：P2B-009、新增 P2D-013、§10.3。
- 边界（明确）：本超时**仅适用于 FFprobe 元数据调用**；**不**适用于 FFmpeg 缩略图提取，也**不**适用于未来完整转码流程（两者未获批准，需另行决策）。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未实施**。

## D-0015 | 2026-10-10 | 缩略图缓存上限 200 MiB 与确定性清理策略（原 §11-3）

- 背景：P2C-006 原引用待确认项（Stage 0 草案为 `ClipForge\thumbs` + 200MB 建议）。
- 决策：缓存目录定为 `%LOCALAPPDATA%\com.clipforge.app\cache\`（由**应用路径 API** 获取本地应用数据根目录后构造，**不得硬编码用户绝对路径**）；容量上限 **200 MiB（209,715,200 字节）**；达到或超过上限时清理**可重建的旧缩略图**，采用 **LRU 或等价确定性策略**；**不得删除或修改源视频及缓存根目录之外的文件**；缓存键包含源文件路径哈希 + 文件大小 + mtime（可检测源文件变化）；**单条缩略图体积超过上限的极端分支**：不写入持久缓存、仅会话内使用、不得无限重试（以单元测试注入大小验证，不构造真实 200MiB 缩略图）；启动时执行清理与容量检查（随 Phase 2C 实现）。
- 理由：固定数值与确定性策略可验收；键含 mtime/大小避免脏缓存。
- 影响范围：P2C-005（源目录零污染为硬性条件）、P2C-006、§10.3。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未实施**（策略获批 ≠ 缓存功能已实现）。

## D-0016 | 2026-10-10 | 重复导入按规范化路径去重（原 §11-6）

- 背景：P2A-007/P2D-009 需固定"重复选择同一文件"的可验收行为。
- 决策：按**规范化路径**判重（绝对化；Windows 下大小写不敏感比较）；重复导入**不新增条目**，显示"已在列表中"提示；既有条目状态不变。
- 理由：避免重复条目造成状态串扰；规范化比较避免同一文件因大小写/分隔符差异被误判为新条目。
- 影响范围：P2A-007、P2D-009、Gate-2A。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未实施**。

## D-0017 | 2026-10-10 | 元数据展示规则：路径截断+可查看完整；时长 floor 到秒（原 §11-4）

- 背景：P2B-001/P2B-003 原引用待确认的展示细节。
- 决策：路径在界面**可截断显示**，但必须提供**查看完整路径的方式**（具体交互形式由实现决定，验收只看"可查看且与系统一致"）；时长格式 `HH:MM:SS`（不足 1 小时用 `MM:SS`）；**不保留小数秒，向下取整（floor）到秒**；验收核对 `floor(ffprobe duration) == 显示秒数`（如 5.023s → `00:05`）。
- 理由：截断显示保证布局稳定；完整路径可查看保证可核对；floor 规则消除四舍五入歧义，保证验收一致。
- 影响范围：P2B-001、P2B-003、P2B-010（交叉核对表）。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未实施**。

## D-0018 | 2026-10-10 | ACL 权限测试规程：仅限专用测试副本，强制恢复并验证（原 §11-5）

- 背景：P2A-005 需要"无权限文件"场景，直接操作用户文件或系统路径存在风险。
- 决策：仅对**专用测试素材副本**执行 ACL 变更，并遵循强制规程（详见规格 §10.2）：① 改 ACL 前记录目标文件路径、原 ACL、当前用户身份与文件哈希；② 使用**最小范围**变更（单文件、拒绝当前用户读取）；③ 无论测试成功与否**必须**执行恢复流程；④ 恢复后**重读 ACL 验证原状**并复核文件哈希不变；⑤ 无法确认恢复成功时**立即停止后续测试并报告**，不得声称通过；⑥ 命令限定到单个测试文件，**禁止递归修改父目录权限**；⑦ 不得操作用户原始视频、项目目录或系统文件；⑧ 不得修改系统 PATH、注册表或全局环境变量。
- 理由：最小范围 + 可恢复 + 可验证，确保测试不产生残留权限问题。
- 影响范围：P2A-005、§10.2。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未实施**（文档修订阶段不执行任何 ACL 修改）。

## D-0019 | 2026-10-10 | 扩展元数据字段列为 P1 可选，不阻塞 Gate-2B（原 §11-7）

- 背景：原待确认"是否在 2B 增加比特率、帧率、容器格式字段"。
- 决策：比特率、帧率、容器格式列为 **P1 可选字段**（规格新增 P2B-012），**不属于 Gate-2B 必需字段，不得阻塞核心 Gate**；若实现，展示与核对规则同 P2B-010。
- 理由：控制 Stage 2 范围，核心 Gate 聚焦必需字段。
- 影响范围：P2B-012、Gate-2B。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未实施**。

## D-0020 | 2026-10-10 | 日志策略：应用管理目录、5 MiB 轮转、保留 3 份、stderr 截断 8 KiB（原 §11-8）

- 背景：日志位置与保留策略原为待确认；ARCH-004 需要可测量的截断上限。
- 决策（具体数值，可测量）：日志目录 `%LOCALAPPDATA%\com.clipforge.app\logs\`（由**应用路径 API** 构造根目录，不硬编码绝对路径）；单文件上限 **5 MiB（5,242,880 字节）**，写入使当前文件超限即轮转；**保留最近 3 个文件（含当前）**，更旧删除（日志总量上界 ≈ 15 MiB）；日志中 stderr 内容**尾部截断上限 8 KiB（8,192 字节）**；**不得记录完整环境变量、密钥或不必要的系统信息**。
- 理由：固定数值使"限制大小并轮转"可测量、可验收；截断防止异常输出无限增长。
- 影响范围：ARCH-004、新增 ARCH-011、§10（证据与脱敏）。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未实施**。

## D-0021 | 2026-10-10 | 允许生成专用测试素材（仅测试用途，原 §11-9）

- 背景：P2B/P2C/P2D 多个用例依赖专用素材（无声、裸流、短视频、无权限副本等）；原待确认"是否允许用 FFmpeg CLI 生成"。
- 决策：允许后续阶段使用**现有 FFmpeg CLI**（系统依赖，Stage 1 已验证）生成专用测试素材；**仅允许写入专用测试素材目录** `docs/evidence/stage2/test-assets/`；每个素材必须记录生成命令、退出码、SHA256 与 FFprobe 验证结果；**不得修改 Stage 1 已有证据素材、不得覆盖现有文件**。
- 理由：专用素材是 P2D 异常场景可复现的前提；限定目录与记录要求保证可追溯。
- 影响范围：规格 §10.4、P2B-006/008/009、P2C-003、P2D-002/004 等的素材来源。
- 边界（明确）：本授权**仅限生成测试素材**，**不**授权实现导入、元数据、缩略图或转码任何业务功能；文档修订阶段**不执行任何素材生成命令**。
- 批准状态：**已获用户批准（2026-10-10）**。
- 实施状态：**未实施（本次未执行）**。

## D-0022 | 2026-10-10 | P2A-004/P2A-005 失败场景的受控测试入口（规格触发方式修订）

- 背景：P2A-004/P2A-005 的验收步骤以"路径能够到达应用层"为隐含前提；实测 Windows 系统文件对话框在点击"打开"时预校验存在性/可读性并自行拦截（证据：`docs/evidence/stage2/2a/stage2a-ui-acl-os-block.png`；Stage-2A 报告 v2 §6），原文步骤在标准流程不可稳定执行。完整调查与备选方案比较见 `docs/Stage-2A-Gap-Assessment.md`（§4、§6）。
- 决策：认可"受控测试入口"作为 P2A-004/P2A-005 的**等效触发方式**：在 dev 构建中以临时环境变量启用 WebView2 CDP，经**既有 IPC**（`create_import_entry`）注入白名单（`docs/evidence/stage2/test-assets/`）内的测试路径以触发应用层处理；规格 v1.2 将"触发方式（二选一）"写入该两项的"验收步骤"。**期望结果、错误码可区分性、§10.2 规程、证据类型与 Gate-2A 判据全部不变**；明确排除拖拽导入、手动输入路径等新增用户功能。
- 理由：在不降低任何验收标准的前提下恢复失败场景的可测试性；该通道仅测试环境可用（临时环境作用域 + devtools），生产构建不暴露（详见缺口评估 §4.2）。
- 影响范围：`docs/requirements-and-acceptance.md` P2A-004/P2A-005 的"验收步骤"表述（v1.2）；Gate-2A/Gate-2D 判据不变；P2D-010 等引用不受影响。
- 批准状态：**已获用户批准（2026-10-10，用户指令"按已批准的缺口评估 §6 草案，正式记录 P2A-004/P2A-005 的受控测试入口变更"）**。
- 实施状态：**已实施**——N-1~N-4、R-1 已于 2026-10-10 执行并通过（证据：`docs/evidence/stage2/2a/stage2a-fix-cdp-calls.log`、`stage2a-fix-ui-texts.log`、`stage2a-fix-p2a005-acl2.log`、`stage2a-fix-*.png`；结果见 Stage-2A 报告 §10）。

## D-0023 | 2026-10-10 | Phase 2B-1 受控测试覆盖机制与测试替身（Debug-only）

- 背景：规格 §10.1/§10.3 要求以"独立测试配置或依赖路径注入"稳定复现工具缺失/不可启动/非零退出与超时场景；Phase 2B-1 授权明确"按已批准方案执行 D-1、D-2、D-4、D-5"。
- 决策：
  1. **测试覆盖仅 Debug 构建存在**：`src-tauri/src/test_overrides.rs` 模块整体由 `#[cfg(debug_assertions)]` 控制（`lib.rs`），Release 构建不编译该模块（以 release 产物不包含相关字符串为证）。
  2. **工具路径覆盖** `CLIPFORGE_TEST_FFPROBE`：必须为绝对路径、不含 `..`，且位于专用替身目录 `docs/evidence/stage2/test-tools/fake-ffprobe/` 的路径标记之下；不满足即忽略（返回 None）；**设置有效覆盖后不回退常规发现**——保证"工具文件不存在"场景可复现（覆盖值为最终答案）。
  3. **超时覆盖** `CLIPFORGE_TEST_PROBE_TIMEOUT_MS`：仅接受 1..=30000 的整数（不得放大默认 30 秒硬超时）；非法值忽略。
  4. **测试替身**：独立 Cargo 工程 `docs/evidence/stage2/test-tools/fake-ffprobe/`（`fake-ffprobe-exit1` = 受控非零退出；`fake-ffprobe-delay` = 挂起 120 秒），不混入应用运行目标；配套 `unlaunchable.dat` 提供"存在但不可启动"样本。
- 理由：在不降低验收标准、不引入新依赖的前提下，使 P2D-005/P2D-013 的失败与超时路径可稳定、可复现地执行；环境变量以 `CLIPFORGE_TEST_` 前缀隔离，正常用户环境不会意外触发。
- 影响范围：`src-tauri/src/probe.rs`、`src-tauri/src/test_overrides.rs`、`src-tauri/src/lib.rs`；证据与工具位于 `docs/evidence/stage2/2b/` 与 `docs/evidence/stage2/test-tools/`。
- 批准状态：**已获用户批准（2026-10-10，Phase 2B-1 授权指令）**。
- 实施状态：**已实施**（Phase 2B-1 证据：`docs/evidence/stage2/2b/stage2b1-*.log`；三场景与超时终止结果见 Gate 报告）。

## D-0024 | 2026-10-10 | Phase 2B-3 语义补充：重试 force 语义、MEDIA_UNSUPPORTED 判定边界与退出孤儿观察

- 背景：Phase 2B-3 落地 P2B-009"可重试"与 P2B-011"无可用视频流给出明确错误态"时，需固化三处实现语义，避免过度分类或范围外扩张。
- 决策：
  1. **重试语义**：`probe_import_entry(entry_id, force)` —— `force=true` 时忽略会话缓存重新探测（在途防并发仍生效）；成功后覆盖失败状态（实测：`FFPROBE_TIMEOUT` → 完整元数据"无音轨"；同会话其他失败条目状态不受影响——条目隔离）。
  2. **MEDIA_UNSUPPORTED 判定边界**：仅当 FFprobe **成功返回**但报告中无任何可用视频流信息（codec/宽/高均为空，如音频-only 文件）时判定为 `MEDIA_UNSUPPORTED`；**不**实现"非媒体 vs 损坏"的进一步细分——无可可靠依据时不猜测，统一以 `FFPROBE_NONZERO_EXIT` + FFprobe **原始可读原因**呈现（实测：`moov atom not found`、`Invalid data found when processing input`）。
  3. **退出孤儿观察（已知限制）**：窗口在探测在途时关闭，应用约 1.1 秒干净退出，但**在途 FFprobe 子进程按 Windows 语义不被级联终止**（实测孤儿 1 个、属受控替身、已由测试侧清理）。**本阶段不实现退出级联取消**（超出 Gate-2B 明文要求）；记录为健壮性增强项，建议并入后续阶段（如 Stage 2D 或更后）评估。
- 理由：使 P2B-009/P2B-011 的可验收语义闭环、防止无依据的过度分类与范围外修改。
- 影响范围：`src-tauri/src/probe.rs`（force 参数、分类函数、可读原因）、`src/App.tsx`（重试交互与状态防串扰）、2B-3 证据。
- 批准状态：**已获用户批准（2026-10-10，Phase 2B-3 授权：P2B-009 重试要求、"只有具备可靠依据时才区分"）**。
- 实施状态：**已实施**（证据：`docs/evidence/stage2/2b/stage2b3-*`；逐项结果见 Gate-2B 报告）。

## D-0025 | 2026-10-11 | Probe 生命周期修复（D-0024 落地；方案 A：取消令牌 + 句柄登记表）

- 背景：Step 1 基线报告确认孤儿进程根因——`probe_file` 内 Child 句柄局部化（无外部可达）、`ProbeStateStore` 仅存结果与 ID、`lib.rs` 无退出钩子、Windows 父进程退出不级联终止子进程（S6b 实证孤儿存活）。
- 决策（经 Step 2 授权，采用基线报告 §7.2 方案 A）：
  1. **新增 `src-tauri/src/probe_lifecycle.rs`**（std-only，零依赖）：`CancelToken`（`Arc<AtomicBool>`）、`ProbeTask { entry_id, child: Arc<Mutex<Option<Child>>>, cancel }`、`ProbeTaskManager`（`HashMap<u64, Arc<ProbeTask>>` 登记 + `shutdown_all(max_wait)`）。
  2. **探测线程与退出路径共享同一子进程句柄槽位**：`probe_file` 拆为"包装 + `probe_file_inner`"——managed 入口先登记、spawn 后句柄入槽、轮询循环每次迭代先查取消令牌；取消/被接管路径统一走 kill+wait 并返回新增分类 `FFPROBE_CANCELLED`（不与既有分类吞并）。
  3. **退出钩子**：`lib.rs` 由 `Builder::run(ctx)` 改为 `build(ctx).run(callback)`，在 `tauri::RunEvent::Exit`（registry 源码 app.rs:220-222，"Event loop is exiting"）中调用 `shutdown_all(2s)` 并打印摘要日志（`[lifecycle] exit cleanup: …`）。
  4. **shutdown_all 语义**：立即置位全部任务取消令牌并取走在途子进程（kill+wait）→ 有界等待（≤2s）登记表收敛（探测线程经取消路径自移除）→ 输出摘要（cancelled/reaped/remaining/elapsed/errors）。
  5. 这是**产品行为**（Debug/Release 一致），与仅 Debug 的测试覆盖机制无关。
- 理由：不新增依赖、不改 2A/2B 语义与 IPC 契约（命令参数不变）的前提下，使"退出→取消→终止→回收→收敛→无孤儿"可验证闭环；实测 shutdown 33ms ≪ 2s 上限。
- 影响范围：`src-tauri/src/probe_lifecycle.rs`（新增）、`src-tauri/src/probe.rs`、`src-tauri/src/lib.rs`；证据 `docs/evidence/stage2/2c/`。
- 批准状态：**已获用户批准（2026-10-11，Stage 2C-1 Step 2 授权指令）**。
- 实施状态：**已实施**（cargo test 47/0/7 EXIT=0；孤儿回归：在途 PID 24012 → 关闭后 count=0；正常回归：cancelled=0、秒级退出；证据 `stage2c1-*`）。

## D-0026 | 2026-10-11 | 探测生命周期状态模型与稳定性验收（Stage 2C-2；C2-D1/C2-D2）

- 背景：Step 2C-2 授权要求在不变更 2A/2B 冻结行为的前提下增强生命周期健壮性并完成稳定性验收。
- 决策：
  1. **内部任务状态模型（C2-D1）**：`ProbeTaskStatus { Pending, Running, Completed, Failed, Cancelled }`，仅后端内部使用（不暴露 UI、不改变错误分类）；转移：register→Pending；子进程入槽→Running；按最终结果→Completed/Failed；shutdown/取消→Cancelled（`mark_cancelled_if_active` 保证终态 Completed/Failed 不被关闭路径覆盖）。
  2. **Manager 观测能力**：`peak_running`（登记表峰值，纳入 shutdown 摘要与退出日志）；`take_finished`（移除并返回任务，替代原 `remove` 的 bool 返回）；`ProbeTask.has_child()` 非破坏性检查。
  3. **取消不覆盖既有结果**：命令层对 `FFPROBE_CANCELLED` 结果仅 `abort`（释放在途标记、不写 `ProbeStateStore`），保留该条目既有探测结果——未完成的重试不覆盖既有错误结果。
  4. **测试替身补充**：`fake-ffprobe-ok`（输出固定合法 JSON 后 exit 0）加入既有 D-0023 替身工程——为"正常完成"路径提供封闭测试依据（应用依赖零变化）。
  5. **稳定性验收（C2-D2）**：50 文件压力（Phase A 真实 FFprobe×40 并发；Phase B 超时替身×10 在途关闭）+ 10 轮生命周期循环（5 轮真实 + 5 轮在途关闭）。
- 理由：使生命周期可观测、可测试、可验收；取消路径的"不覆盖"语义保证失败诊断信息不因中断的重试而丢失。
- 影响范围：`probe_lifecycle.rs`、`probe.rs`、`lib.rs`（日志行）、测试替身工程、`docs/evidence/stage2/2c/`。
- 批准状态：**已获用户批准（2026-10-11，Stage 2C-2 授权指令）**。
- 实施状态：**已实施**（cargo test 52/0/7 EXIT=0；压力 A：ready=24/failed=16/peak=40/remaining=0；压力 B：cancelled=10/reaped=10/peak=10/remaining=0/child 残留=0；10/10 轮 PASS；证据 `stage2c2-*`）。

## D-0027 | 2026-10-11 | Stage 2C 范围重定向确认与缩略图移交（规格 v1.3；2D-1-A 裁决 (a)）

- 背景：规格 v1.2 的 Phase 2C = 缩略图（P2C-001~008）；实际 Stage 2C 经用户 2026-10-11 三次授权（2C-1 架构审查与生命周期修复、2C-2 状态模型与稳定性验收、2C-3 最终验收）执行为**生命周期增强**并已判定 PASS（`docs/Stage-2C3-Final-Report.md`）。该重定向此前未记录于决策日志、规格未修订；Gate-2D 必需项 P2D-001/006 依赖不存在的缩略图能力（Stage 2D-1 规划 §F-1 报告的规格冲突）。
- 决策（用户裁决：**方案 (a)**）：
  1. 确认 Stage 2C 实际范围 = **生命周期增强**，其 Gate-2C = 生命周期验收（PASS，2026-10-11）——**不影响该 PASS 结论**；原 v1.2 Gate-2C 缩略图规划与实际执行路线的偏差以此记录为准。
  2. **缩略图能力（P2C-001~008 及相关缓存）移交后续阶段**（Stage 3 或另行授权），Stage 2D 不实现；不新增缩略图相关代码、UI、IPC、缓存或依赖。
  3. Stage 2D 目标调整为：已有能力的最终验收——导入链路稳定性、FFprobe 元数据链路、生命周期可靠性、架构约束检查、发布前回归。
  4. 规格 v1.3 修订：§3.1 阶段描述更新；P2C-001~008 状态整体标为"移交（v1.3）"；P2D-001 端到端修订为"导入→元数据 + 全链路源保护复核"（缩略图子句随 P2C 移交）；P2D-006 修订为"FFmpeg 受控缺失时元数据不受影响"（缩略图错误态子句随 P2C 移交）；Gate-2C 行加注实际执行范围；**Gate-2D 判据其余不变**。
- 理由：使规格与已验收现实一致，解除 Gate-2D 的缩略图依赖阻塞；避免 2D 范围膨胀，保住三天交付主线。
- 影响范围：`requirements-and-acceptance.md`（v1.3）；Gate-2D 判据（P2D-001/006 子句）；P2C 条目状态。
- 批准状态：**已获用户批准（2026-10-11，Stage 2D-1-A 授权指令，裁决结果"采用方案 (a)"）**。
- 实施状态：**已实施**（规格 v1.3 修订与本决策同批落盘；证据 `docs/evidence/stage2/2d/`）。

## D-0028 | 2026-10-11 | 页头副标题产品化：移除内部阶段标识（"Stage 2B · 元数据展示" → 产品文案）

- 背景：用户发现应用页头副标题显示"Stage 2B · 元数据展示"。核查结论：该文案是 Stage 2B 实施期写入 `src/App.tsx` 的硬编码占位——非规格要求（`requirements-and-acceptance.md` 对页头副标题无任何条款）；此后 2C/2D/3A/3B/3C 均未随能力演进更新，已与当前实际功能（导入/元数据/缩略图/格式转换）不符，且把内部开发阶段编号暴露在用户可见 UI。
- 决策（用户指令："替换成产品文案"）：
  1. 页头副标题由 `Stage 2B · 元数据展示` 替换为产品文案 **`本地视频导入 · 元数据 · 格式转换`**（`src/App.tsx`，单行）。
  2. 不改动任何验收条款、IPC 契约、后端行为与既有证据；历史验收证据日志中的 UI 文本 dump（含旧副标题）为历史快照，**不回改**。
  3. `.subtitle` 样式（`App.css`）不变。
- 影响面核查（改动前全仓库检索）：仅 `src/App.tsx` 一处源码引用；无任何测试、脚本或断言引用该字符串；其余 "Stage …" 字样位于 Rust 源码注释（历史标注、非用户可见），不在本次范围。
- 理由：消除内部开发流程信息在交付物 UI 中的暴露，使页头文案与实际交付能力一致（以交付/评审观感为准）。
- 影响范围：`clipforge/src/App.tsx`（1 行）；证据 `docs/evidence/d0028-ui-copy/`（before/after 截图、UIA dump、构建日志、取证脚本）。
- 批准状态：**已获用户批准（2026-10-11，用户指令"替换成产品文案"）**。
- 实施状态：**已实施**（实测于运行中的 dev 会话经 Vite HMR 生效：`d0028-after-header.log` 含新文案、`d0028-after-header.png` 截图；`npm run build`（tsc + vite）EXIT=0，见 `d0028-npm-build.log`）。附：本次取证补充了 D-0012 截图方法的三个坑（Tauri `Process.MainWindowHandle` 指向 14×14 辅助窗口；最小化时 WebView2 内容不实例化；后台进程 `SetForegroundWindow` 被拒 → 改用 `PrintWindow(PW_RENDERFULLCONTENT)`）——详见 `docs/evidence/d0028-ui-copy/d0028-verify.log` 方法学记录。

## D-0029 | 2026-10-11 | Stage 4 交付包装：产品名/图标/标题定稿 + NSIS 打包（交付加分项定位）

- 背景：用户就"笔试题未要求打包，打包是加分还是减分"征询判断，并给出执行指令"改成 ClipForge，图标要有特色的 / 继续"。共识结论：打包是**加分项**——直接命中笔试题第 6 条（界面选型须与"客户端"关联）与第 7 条（给人用、自己测过）；审核人下载 GitHub 产物后应能"双击安装即用"，而非先装 Node+Rust 自行构建。硬性前提：第 5 条（GitHub 提交链接回 HR）为本轮唯一硬缺口，打包不得挤占其时间；打包前仅允许"交付外观"配置级改动，改后必须重跑回归。
- 决策：
  1. **产品名与窗口标题**：`tauri.conf.json` 的 `productName` 由 `clipforge` 改为 `ClipForge`（决定安装包名、安装目录、开始菜单与"应用和功能"显示名）；窗口 `title` 同步改为 `ClipForge`。**`identifier` 保持 `com.clipforge.app` 不变**——日志目录与应用数据路径不受影响（D-0020 继续有效）。
  2. **窗口尺寸**：默认 800×600 → 1024×720，新增 `minWidth: 900 / minHeight: 600`（容器 `max-width: 880px` + 24px 内边距，1024 宽下两侧留白均衡、首屏无需缩放）。
  3. **应用图标（特色设计）**：以脚本 `docs/evidence/stage4/stage4-make-icon.py`（Pillow，仅生成期使用、不进产品依赖）绘制 1024×1024 源图：靛蓝→青对角渐变圆角方块 + 白色胶片画框（顶/底齿孔）+ 金→橙渐变播放三角（带柔和投影）；经 `npx tauri icon` 生成全套平台图标（含 `icon.ico`/`icon.icns`/各尺寸 PNG/Square\*Logo）。**删除 `tauri icon` 顺带生成的 `icons/android`、`icons/ios`**（桌面交付无关，保持仓库干净）。
  4. **Web 层标题与图标**：`index.html` 的 `<title>` 由模板默认 `Tauri + React + Typescript` 改为 `ClipForge`（D-0028 登记的范围外观察，本次一并清理）；favicon 由模板 `vite.svg` 改为 `public/icon.png`（复制自 1024 源图）；删除无引用的 `public/tauri.svg`、`public/vite.svg`。
  5. **打包形态**：`npm run tauri build -- --bundles nsis`（仅产 NSIS 安装包；`bundle.targets` 配置文件保持原样 `"all"` 不动，用 CLI 参数限定本轮产物，避免引入 MSI/WiX 工具链依赖）。
  6. 本轮改动**全部位于配置/资源层**：不改任何 Rust 源码、不改 UI 逻辑、不新增依赖。
- 理由：交付观感（模板默认图标与模板标题会直接暴露"未收拾"）；需求 6/7 的客户端定位需要"可安装的 Windows 客户端"来承载；改动面最小且可回归验证。
- 影响范围：`clipforge/src-tauri/tauri.conf.json`、`clipforge/index.html`、`clipforge/src-tauri/icons/**`（全量重生成）、`clipforge/public/**`；证据 `docs/evidence/stage4/`（图标脚本与日志、`tauri icon` 日志、回归日志、打包日志）。
- 批准状态：**已获用户批准（2026-10-11，用户指令"改成 ClipForge，图标要有特色的 / 继续"）**。
- 实施状态：**已实施**——回归通过（`cargo test` 65/0/7 EXIT=0；`npm run build` EXIT=0）；NSIS 打包 2 轮迭代后成功（首轮 NSIS 工具链从 GitHub 下载被阻断 → 使用官方镜像开关 `TAURI_BUNDLER_TOOLS_GITHUB_MIRROR=https://gh-proxy.com`，下载物 SHA1 与内置校验值一致）；安装/启动/核心链路（含 T7 中文特殊路径）/卸载验收通过（第 2 轮全绿，证据 `stage4-smoke-t7.log`；第 1 轮发现的"对话框路径注入未核验"问题与修正见 `stage4-acceptance.log` 与交付报告 §5）；二轮补修 `mainBinaryName`/`bundle.publisher` 使安装体完全一致为 ClipForge。详见 `docs/Stage-4-Delivery-Report.md`。

## D-0030 | 2026-10-12 | Stage 5 功能优化：格式切换、元数据扩展（P2B-012）、打开输出文件夹、转换进度

- 背景：用户询问"第三点（自己按想法做一些优化）能做一些**功能上**的优化吗"。既有优化集中在可靠性与工程侧（错误码、生命周期、日志、测试基础设施），缺少"功能可见"的改进。经评估，选定四项**范围内**优化（题面明确不做的批量转换/播放器/字幕/AI 一律不做）：其中 A 是项目自己登记的欠账（3B 报告 §6-2"转换完成后仅提供同格式重新转换"，3C 报告 §8-3 复述），B 是规格中**已批准但未实施的 P1 可选字段**（D-0019 / 规格 P2B-012）。
- 决策（用户指令："第三点能做一些功能上的优化吗"）：
  1. **A 格式切换**：转换完成态由"仅重新转换"扩展为 **[重新转换] + [转 WebM/转 MP4] + [打开所在文件夹]**；失败态由"仅重试"扩展为 **[重试] + [改用 WebM/MP4]**（失败若源于格式本身，切换即是最短路修复路径）。条目仍仅保留最近一次转换结果（沿用既有 `ConversionStore` 单记录语义，不新增多结果模型）。
  2. **B 元数据扩展（P2B-012）**：新增展示 **帧率**（ffprobe `r_frame_rate` 换算，"30/1"→"30 fps"，非整数保留 2 位小数）、**比特率**（`format.bit_rate` 换算，≥1Mbps→"x.xx Mbps"/≥1kbps→"x kbps"/否则 bps）、**容器**（`format.format_name` **原值**直显）。缺失一律 N/A、不猜测；换算舍入规则以 FFprobe JSON 对照表存档（P2B-010 规则）。
  3. **C 打开输出所在文件夹**：新增 IPC `reveal_conversion_output(entry_id)` —— **仅接受条目 ID**，路径取自转换结果存储（WebView 无法传入任意路径），`explorer /select,<path>` 单参数调用；**零新依赖、零能力（capability）新增**。
  4. **D 转换进度**：FFmpeg 增加 `-nostats -progress pipe:1`，stdout 逐行解析 `out_time_us`（与 `out_time_ms` 同为微秒语义），按**元数据总时长**换算百分比并 clamp 到 [0,100]，经 Tauri 事件 `conv-progress` 推送；**总时长未知（N/A）时不显示进度**（不造假进度，遵守 ARCH-006）。顺带加固：`-nostats` 使 stderr 只保留真实错误文本。
  5. 版本号 0.1.0 → **0.1.1**（`tauri.conf.json` / `Cargo.toml` / `package.json` 三处一致）。
  6. 新增单测：converter.rs 首次补齐单测（参数构造/输出路径冲突/进度解析/存储行为，7 项）；probe.rs 新增 3 项（帧率与比特率格式化表、解析存在与缺失）。
- 理由：四项均为"给人用"（题面第 7 条）与"功能完整度"（第 3 条）的**低成本高可见**改进，且不引入新依赖、不触碰既有错误分类与生命周期语义（核心路径回归 + 真实 UI 验收覆盖）。
- 影响范围：`converter.rs`（进度参数/解析/事件/reveal 命令/单测）、`probe.rs`（新字段/格式化/视图/单测）、`lib.rs`（命令注册）、`App.tsx`/`importApi.ts`/`App.css`（UI）、`tauri.conf.json`+`Cargo.toml`+`package.json`（版本）；证据 `docs/evidence/stage5/`。
- 批准状态：**已获用户批准（2026-10-12，用户指令"第三点能做一些功能上的优化吗"）**。
- 实施状态：**已实施**——回归 cargo **75/0/7**（+10 新单测；两轮一致）、npm build EXIT=0；release v0.1.1 打包成功；四项功能实机验收全部通过：A 切换格式（新增 WEBM 输出、按钮翻转）、B 元数据对照（UI↔FFprobe 逐项一致，见报告 §5.1）、C 打开所在文件夹（窗口 +1、日志证据行 +1）、D 进度条（DOM 实测 `转换中…18%`）+ **CONV_CANCELLED 首次实机触发**（转换中关闭：`code=CONV_CANCELLED`、`cancelled=1 reaped=1 remaining=0`、无半成品）。方法学补充：WebView2 UIA 不暴露绝对定位百分比 span → 进度验证改用 CDP DOM 读数（`cdp-eval.js`）。详见 `docs/Stage-5-Feature-Polish-Report.md`。

# AI 会话摘要（AI Session Summary）

> 目的：记录人与 AI 的实际协作过程——任务、AI 的有效产出、AI 的错误与开发者纠正、最终采用情况。
> 真实性原则：允许包含 AI 被纠正与被否决的案例；不事后美化。

---

## 会话 1（2026-10-10）：Stage 0 环境与方案审计

- **任务**：限时三天笔试项目"ClipForge 视频格式转换器"。Stage 0 只做环境审计与方案设计，禁止安装、创建应用、Git 操作。
- **AI 实际执行**：只读方式检查了操作系统、工作区、Git 状态、Node/npm/Git、Rust/MSVC/WebView2、FFmpeg、磁盘、注册表（WebView2/Edge 版本）、winget 包清单与网络可达性；产出 11 节审计报告。
- **AI 的有效产出**：
  - 澄清了三类"工具缺失"（Rust、MSVC、FFmpeg）且给出已验证的安装路径与哈希；发现 WebView2 Runtime 154.x 已装、五路软件源可达。
  - 发现两条易被误判的细节：(a) `where link` 命中的是 Git 自带 Unix link.exe，非 MSVC 链接器；(b) Git Bash `$HOME` 中文乱码。
  - 结论 CONDITIONAL PASS，并明确"不允许安装 Rust/MSVC 时本方案不可行，应改判 FAIL"的前提假设。
- **AI 的局限/待纠正**：Stage 0 报告对中文路径与 PowerShell 环境做了保守假设（曾建议 Git Bash 内修 HOME）；Stage 1 实测证明 PowerShell 内 HOME/USERPROFILE 与中文参数均正常，乱码仅限 Git Bash 侧显示。该修正已回填至 `docs/decision-log.md` D-0006 与 `docs/stage-0-audit.md` 修订记录。
- **开发者反馈**：以指令形式给出 12 条审计要求与规则约束（先检查再结论、标注已验证/待验证/风险、不绕过阻塞、不执行破坏性操作）。
- **AI 遵守情况**：全程未安装、未创建业务代码、未做 Git 操作；唯一新增文件为审计报告本身。

## 会话 2（2026-10-10）：Stage 1 依赖安装与 Gate-0 验证

- **开发者授权与决策基线**：安装 Rust/VS BuildTools/FFmpeg；公开仓库（本阶段不推送）；FFmpeg 系统依赖；MP4+MKV；串行默认；重名数字后缀；NVENC 默认关闭；要求"先检查再安装"、PowerShell 执行、记录证据、失败不绕过。
- **AI 实际执行（按时间顺序）**：
  1. 预检复核：工作区仅 `docs/stage-0-audit.md`（无其他会话新增文件）、非 Git 仓库、C 盘 21.9GB / D 盘 135.1GB、winget 三包版本与 Stage 0 记录一致；发现 UAC 静默提权（ConsentPromptBehaviorAdmin=0）且当前用户在 Administrators 组。
  2. winget 安装 Rustup 1.29.1 → 验证 rustc/cargo 1.99.0、host 与 target 均为 x86_64-pc-windows-msvc。
  3. 设置用户级 `CARGO_TARGET_DIR=D:\cargo-target`。
  4. create-tauri-app 4.7.5 生成 `clipforge`（react-ts 模板）→ `npm install` 成功（27 包，55s，保留 package-lock.json）。
  5. 并行启动 VS Build Tools 安装与 cargo 依赖预拉取。
- **AI 的错误与自我纠正（如实记录）**：
  - 第一次 `cargo fetch` 因命令未前置 `%USERPROFILE%\.cargo\bin` 而失败（CommandNotFoundException，无任何副作用）；同时暴露出我的日志管道（`2>&1 | Add-Content`）未捕获该错误。更正：重跑并显式核验 PATH 与 registry 缓存，改用双重确认。
  - 一次 PowerShell 语法错误（括号不匹配）导致预检命令失败；更正后重跑，未影响环境。
- **开发者纠正**：本阶段暂无人工纠正（以指令规范为准）；AI 的两处失误均由自身复核发现并修正，过程保留在日志与本节。

### 会话 2 结果补记（18:04 收尾）

- **Gate-0A PASS**：`cargo build` 1.37s / `cargo run` 输出 `Hello, world!`（中文用户名路径），EXIT=0。
- **Gate-0B PASS**：346 编译单元 2m20s；窗口显示/响应/关闭/重启全部验证；UIA 交互触发 Tauri IPC，窗口渲染出 `Hello, ! You've been greeted from Rust!`；重启 5.5s、关闭后 1.15s 全链路退出、零残留。
- **Gate-0C PASS**：testsrc2 样片 → ffprobe JSON → libx264 真实 MP4 转换（SHA256 已记录）→ 全片解码 EXIT=0；附加中文+空格目录转换成功。
- **AI 的第三处失误与更正（如实记录）**：第一次窗口截图忽略了 z-order（捕获区域被 ZCode 窗口遮挡导致证据无效），且 run2 关闭检查脚本误报 `process_exited=False`；两者均通过交叉核验（重拍 + 日志时间戳）发现并更正，方法固化为决策日志 D-0012。
- **环境假设修正**：Git Bash HOME 乱码仅限 Git Bash 侧（PowerShell 正常）；winget 用"写入用户 PATH"而非 Links 别名注册 FFmpeg。
- **待续**：Stage 2（业务功能开发）需开发者授权；文档五件套中 `requirements-and-acceptance.md` 与 README/LICENSE-NOTICE 于 Stage 2 创建。

## 会话 3（2026-10-10）：Stage 2A 导入链路与受控测试入口

- **任务**：实现导入链路（文件选择器、校验、判重）并验收。用户先只授权"技术调查（零改动）"，审阅缺口评估后批准实施方案。
- **AI 实际执行**：先产出 `Stage-2A-Gap-Assessment.md`（判定 CONDITIONAL PASS：9/12 项通过）；随后按批准的方案实施并补测。
- **关键发现**：Windows 系统文件对话框在点击"打开"时**预校验存在性/可读性并自行拦截**，导致 P2A-004/005 的失败场景在标准流程无法稳定触达（证据截图已入档）。缓解：用户批准**受控测试入口**（dev 构建下经 CDP 用既有 IPC 注入白名单内路径；期望结果、错误码、证据要求全部不变）——落为 D-0022、规格 v1.2。
- **AI 的失误与更正（如实记录）**：P2A-003 校验脚本 `null==null` 假阳性（脚本自身缺陷，重写）；UIA 脚本误点列表项；长路径注入一度失控。均自披露后重做。
- **假设被实测推翻**：N-1b 曾预计"270 字符长路径应失败"，实测为 ready——按实测更正结论，不迁就预期。
- **结果**：N-1~N-4、R-1 全 PASS（NOT_FOUND 与 PERMISSION_DENIED 双失败态可区分、ACL 恢复四验 True、cargo 9/9）。**Gate-2A PASS**。

## 会话 4（2026-10-10）：Stage 2B 元数据链路

- **任务**：FFprobe 元数据探测（P2B-001~012）。
- **AI 实际执行**：2B-1 探测基础设施（30s 硬超时 + kill/wait、五类失败码、Debug-only 测试替身工程 `fake-ffprobe`，D-0023）→ 2B-2 → 2B-3（重试 force 语义、MEDIA_UNSUPPORTED 判定边界，D-0024）；cargo 29→38→41 全绿。
- **如实记录的限制**：**退出孤儿进程**——窗口关闭时在途 FFprobe 不被 Windows 级联终止（受控替身实测孤儿 1 个），本阶段不实现级联取消、移交后续修复（D-0024 第 3 条；后由 2C 闭环）。
- **关键数字**：实测超时 1530ms 精确触发；471MB 大文件不阻塞事件循环；文件大小 1.18 MiB ↔ 1,236,377 B 双端交叉核对一致。
- **文档说明**：本阶段实施报告为 2C-3 授权后**补记**，忠实还原 10-10 会话过程、不回改历史证据（报告内已声明）。
- **结果**：**Gate-2B PASS**。

## 会话 5（2026-10-11）：Stage 2C 生命周期修复、稳定性验收与范围重定向

- **任务**：用户分三次授权——2C-1 架构审查与生命周期修复、2C-2 状态模型与稳定性验收、2C-3 最终验收。
- **AI 实际执行**：基线报告定位孤儿根因（`probe_file` 内 Child 句柄局部化、无退出钩子、Windows 不级联终止），采用方案 A：新增 `probe_lifecycle.rs`（CancelToken + 句柄登记表 `ProbeTaskManager`）、`Builder::run` 改为 `build().run(callback)` 在 `RunEvent::Exit` 调 `shutdown_all(2s)`、新增分类 `FFPROBE_CANCELLED`（D-0025）；2C-2 落内部状态模型（Pending/Running/Completed/Failed/Cancelled）与 `peak_running` 观测，"取消不覆盖既有结果"（D-0026）；2C-3 纯验收。
- **关键数字**：50 文件压力（40 并发 → ready=24/failed=16/peak=40/remaining=0；10 个超时替身在途关闭 → cancelled=10/reaped=10/child 残留=0）；10/10 轮生命周期循环 PASS；120 周期长稳 ready=40/failed=80/ipcErrors=0；6 轮关闭 6/6（退出 247~262ms）；cargo 52/0/7。
- **AI 的失误与更正（如实记录）**：泄漏检查首次因场景缺失而失败并遗留对话框，清理后重做；"OS 强杀无 shutdown 保证"作为既有边界如实保留、不掩盖。
- **开发者裁决（D-0027）**：确认 2C 实际范围=生命周期增强（不改变其 PASS 结论），**缩略图能力移交 Stage 3**，规格修订 v1.3，解除 Gate-2D 的缩略图依赖（方案 (a)）。
- **结果**：**Gate-2C PASS**（按实际执行范围）。

## 会话 6（2026-10-11）：Stage 2D 已有能力最终验收与冻结

- **任务**：最终验收（零源码改动）：P2D 全矩阵、架构约束、发布前回归、冻结保护。
- **AI 实际执行与数字**：P2D 13/13、ARCH 11/11、回归 10/10、冻结文件 12/12 零改动、cargo 58/0/7；产出 Final Report / Final Matrix / Freeze Protection 三份文档。
- **AI 的失误与更正（如实记录）**：P2D-005 一度报 `START_FAILED/193` 而非预期 `NOT_FOUND`，D5 诊断判定为**瞬态环境伪影**（bash 嵌套编排放大时序噪声），改用单会话编排后 D4/D5 结论一致；重采证据时 fake 判定文本写错 1 次，已修正。
- **结果**：**Gate-2D PASS**。

## 会话 7（2026-10-11）：Stage 3A 缩略图实现

- **任务**：落地 D-0027 移交的缩略图能力（P2C-001~008）。
- **AI 实际执行**：新增 `thumbnail.rs`（THUMB_* 六码、FNV-1a 缓存键、缓存 200 MiB 上限按 mtime 最旧先删、30s 超时可受控覆盖）；实机验证真实帧渲染、跨会话缓存命中、损坏媒体不冒充缩略图；cargo 65/0/7。
- **AI 的失误与更正（如实记录）**：唯一真实缺陷"缓存目录缺失"由**首次 dev 运行**发现并修复（印证"自己先用一遍"）；编译过程 7 处错误留痕；多会话并行一度产生 7 个孤儿进程（已清理）。
- **如实声明的未覆盖项**：FFmpeg 缺失与提帧超时路径未实机触发（有单测覆盖设计），不冒充已验证。
- **结果**：**Gate-3A PASS**。

## 会话 8（2026-10-11）：Stage 3B 转换核心

- **任务**：FFmpeg 转换功能（MP4/WebM 双预设）。
- **AI 实际执行**：新增 `converter.rs`——MP4（libx264 veryfast CRF23 + AAC 128k + faststart）/ WebM（libvpx 1M + libvorbis）；300s 超时；`CONV_*` 六码；输出 `{stem}_converted.{ext}` + 冲突自动递增 + 失败清理半成品；生命周期复用 `ProbeTaskManager`；cargo 65/0/7。
- **实机验证**：UIA 触发特殊字符路径转换成功（UI `已输出 MP4（539 KB）`，产物 ffprobe 核验）。
- **如实记录的缺口**：WebM 仅"代码路径 + 编码器存在"证据（CDP 直调因 dev 会话管理复杂度未成功）——**不冒充已验证**；UI 完成态仅提供同格式"重新转换"（登记为后续改进项）。
- **结果**：**Gate-3B PASS**；WebM 实机缺口由 3C 闭合。

## 会话 9（2026-10-11）：Stage 3C 真实多格式兼容性验收

- **任务**：真实客户端环境下多格式转换验收（授权范围：仅测试，不改代码）。
- **AI 实际执行**：合成 9 个测试素材（T1~T8b）；Windows UIA 驱动**真实 UI 全流程**（导入→元数据→缩略图→点击转换），按 4 个独立 dev 会话 + 单会话 6 连转稳定性组织；13/13 输出 ffprobe 二次校验、失败用例零半成品；收尾 18 个受约束文件哈希与基线**逐项一致**；cargo 65/0/7、npm build EXIT=0。
- **关键闭合**：**WebM 实机验证**（`matroska,webm` + vp8 + vorbis，UI `已输出 WEBM（633 KB）`）；`THUMB_NONZERO_EXIT` 首次实机触发；损坏视频两条失败路径（元数据前置门 `FFPROBE_NONZERO_EXIT` / 真实 `CONV_NONZERO_EXIT` + 原始 FFmpeg 原因）均正确呈现、不崩溃。
- **AI 的处置（如实记录）**：授权书 T8 的"FFprobe 识别损坏"与"CONV_NONZERO_EXIT"在现有元数据前置门下互斥——**拆为 T8/T8b 两条路径分别实机验证**，结论定性为"验收用例样品选择问题、非产品缺陷"，未改任何代码；CONV_TIMEOUT/CONV_CANCELLED 未实机触发，如实声明；dev 期观察到一次缩略图重复请求（Vite 页面重载产物），标注为 release 构建未验证项。
- **结果**：**Gate-3C PASS**。

## 会话 10（2026-10-11 晚）：真实世界素材准备与手测（承接 Stage 4）

- **任务**：为手测/演示准备真实来源、可播放的视频素材。
- **AI 实际执行**：下载并校验 10 个公网真实视频（约 196 MB：H.264/H.265/AV1/VP9/Opus，MP4/WebM/MKV/MOV/AVI，含 183s 长片）至 `test-assets/real-world/`，MANIFEST 记录哈希、ffprobe+全片解码+完整性三重校验、手测预期耗时与已知非理想情况。
- **手测轮（如实补记）**：随后同一 dev 会话中完成多轮真实转换（含 Big Buck Bunny 1080p → WebM，输出 1,955,487 B、约 19s）；**该轮未产出正式报告**，本摘要如实补记，其素材由 Stage 4 的演示与 README 承接。

## 会话 11（2026-10-11 深夜起）：Stage 4 交付包装（进行中）

- **任务**：打包与交付（用户对"打包是加分还是减分"征询结论：加分项，命中笔试题第 6/7 条；但不得挤占第 5 条 GitHub 提交）。
- **AI 实际执行**：D-0028 页头副标题产品化（经运行中 dev 会话 HMR 实机验证 + 截图 + npm build EXIT=0）；D-0029 产品名/窗口标题 → ClipForge、窗口 1024×720（min 900×600）、**特色图标**（Pillow 脚本绘制 1024 源图 → `npx tauri icon` 全套，生成脚本与日志入档）、`index.html` 标题与 favicon 清理、NSIS 打包（`--bundles nsis`）、回归 cargo 65/0/7 + npm build EXIT=0。
- **状态**：进行中——安装/卸载/中文路径验收、README/截图/Demo GIF、git 初始化与 GitHub 提交（第 5 条硬缺口闭环）。详见 `docs/Stage-4-Delivery-Report.md`（撰写中）。

## 会话 12（2026-10-12）：Stage 5 功能优化（0.1.1）

- **任务**：用户询问"第三点（自己按想法做优化）能做一些**功能上**的优化吗"——既有优化偏可靠性/工程侧，需补功能可见的改进（明确不含批量转换/播放器/字幕/AI）。
- **AI 实际执行**：四项一并落地（D-0030）——A 完成态/失败态**可切换另一格式**（解除 3B 登记欠账）；B 元数据新增**帧率/比特率/容器**（实施规格中已批准但搁置的 P2B-012，D-0019）；C 一键**打开输出所在文件夹**（自研 IPC，仅接受条目 ID、`explorer /select`，零新依赖零新权限）；D **转换进度条**（FFmpeg `-progress pipe:1` 解析 → 事件 → UI；仅在总时长已知时显示，不造假进度）。版本 0.1.0 → 0.1.1；**converter.rs 此前无单测，本轮补齐 7 项**（参数构造/输出路径冲突/进度解析/存储行为），probe.rs 加 3 项。
- **AI 的失误与更正（如实记录）**：
  1) 首轮验收 `wait-progress` 用**锚定正则**在 UIA 文本里找独立百分比元素而超时误报失败——根因是 **WebView2 的 UIA 不暴露绝对定位的百分比 span**（同容器"转换中…"可见、百分比不可见）。定位手段：以 `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9333` 开 CDP，用 `cdp-eval.js` 在页面里 `Runtime.evaluate` 读 DOM，实证 **dev 与 release 的进度功能均正常**（`转换中…18%`、事件负载 {entryId:0,percent:0}）——是检测方法失效而非产品缺陷；修正为"截图 + DOM 读数 + 日志"三重取证。
  2) C 首轮验收证据过弱（未区分既有资源管理器窗口，且脚本一次关掉了包括用户原有窗口在内的全部资源管理器窗口）——复验脚本改为**窗口数增量 + 应用日志证据行**，并只关闭本次新增窗口。
  3) 全量并行下 `probe_lifecycle` 的定时敏感测试偶发一次失败（该模块未被本轮修改）；单测单跑 3/3、全量复跑两轮 75/0/7，判定为负载偶发（与 2D 阶段"瞬态环境伪影"同类），如实记录。
- **新增实测覆盖**：**CONV_CANCELLED 首次实机触发**（转换进行中关闭应用：`conv failed code=CONV_CANCELLED`、`shutdown cleanup cancelled=1 reaped=1 remaining=0`、无半成品输出、零残留进程）——闭合 3C 报告的遗留项之一。
- **结果**：**Stage 5 PASS**（`docs/Stage-5-Feature-Polish-Report.md`）；交付 v0.1.1（安装包 + Release）。

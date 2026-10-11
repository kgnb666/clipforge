# ClipForge Stage 0 环境与方案审计报告

- 报告日期：2026-10-10
- 审计人：ZCode（高级桌面应用工程师 / 架构审查 / 测试负责人 角色）
- 审计范围：本机开发环境、工作区与 Git 状态、候选技术方案（Tauri 2 + React + TypeScript + FFmpeg/FFprobe CLI + Rust 后端）、验收标准锁定、测试用例设计、三天计划、文档与分发策略
- 阶段约束：仅审计与方案设计。**未创建应用、未安装任何软件、未修改系统配置、未创建 Git 仓库、未提交、未推送。** 唯一新增文件为本报告。
- 结论预览：**CONDITIONAL PASS**（条件见 §11）
- 标签说明：`[已验证]` = 本轮实际检查确认；`[待验证]` = 本阶段无法确认，需后续实测；`[风险]` = 已识别的不确定性或不利条件。

---

## 1. 当前环境的实际检查结果

### 1.1 系统与硬件

| 检查项 | 实际结果 | 状态 |
|---|---|---|
| 操作系统 | Windows 10 专业版 22H2，版本 10.0.19045，64 位 | [已验证] |
| CPU | 12 逻辑核 | [已验证] |
| 内存 | 15.2 GB | [已验证] |
| 项目盘（D:）可用空间 | 135.1 GB / 254.2 GB（已用 120 GB） | [已验证] |
| 系统盘（C:）可用空间 | 22.0 GB / 222.0 GB（已用 91%） | [已验证][风险] |
| 控制台代码页 | 936（GBK） | [已验证] |
| 长路径支持（LongPathsEnabled） | 0（未启用） | [已验证][风险] |
| nvidia-smi | 存在（存在 NVIDIA GPU，NVENC 可作为可选加分项） | [已验证] |

### 1.2 工作区与版本控制

| 检查项 | 实际结果 | 状态 |
|---|---|---|
| 工作目录 | `D:\应聘项目zcode`，**完全为空**（仅 `.` 与 `..`，无隐藏文件） | [已验证] |
| Git 仓库 | 不是 Git 仓库（`git rev-parse` 返回 fatal: not a git repository） | [已验证] |
| Git 版本 | 2.53.0.windows.2 | [已验证] |
| Git 全局身份 | user.name=kgnb666，user.email 已配置 | [已验证] |
| core.autocrlf / 其他行尾设置 | 未设置 | [已验证] → §10 决策项 |

### 1.3 前端工具链

| 检查项 | 实际结果 | 状态 |
|---|---|---|
| Node.js | v24.14.1 | [已验证] |
| npm | 11.11.0，全局目录 `C:\Program Files\nodejs\node_global` | [已验证] |
| npm registry | https://registry.npmmirror.com（淘宝镜像，非官方源） | [已验证] |
| pnpm / yarn | 均未安装（不影响，npm 足够） | [已验证] |
| @tauri-apps/cli | 全局未安装（Stage 1 将作为项目本地依赖安装，无需全局） | [已验证] |

### 1.4 Rust 与 MSVC（Tauri 构建的关键前置）

| 检查项 | 实际结果 | 状态 |
|---|---|---|
| Rust / rustc / cargo / rustup | **未安装**。已查：PATH（cmd `where`、PowerShell `Get-Command`、bash `which`）、`%USERPROFILE%\.cargo`、`%USERPROFILE%\.rustup`、`C:\Program Files\Rust*`，全部未命中 | [已验证（缺失）] → **P0** |
| Visual Studio / Build Tools | **未安装**。`vswhere.exe` 不存在；`C:\Program Files\Microsoft Visual Studio`、`C:\Program Files (x86)\Microsoft Visual Studio`、`C:\BuildTools`、`D:\BuildTools` 均不存在；VS7 注册表项为空 | [已验证（缺失）] → **P0** |
| Windows SDK | 不存在（`C:\Program Files (x86)\Windows Kits\10\Include` 缺失） | [已验证（缺失）] → **P0** |
| MSVC 编译器/链接器 | `cl.exe` 无；`where link` 仅命中 `C:\Program Files\Git\usr\bin\link.exe`（Git 自带的 Unix 工具，**不是 MSVC 链接器**，勿误判） | [已验证（缺失）] → **P0** |
| 替代编译器 | 无 gcc/g++（Anaconda 目录下也未见可用的 MinGW 工具链） | [已验证] |
| 安装通道 | winget v1.29.380 可用；已确认可查询到：`Rustlang.Rustup` 1.29.1、`Microsoft.VisualStudio.2022.BuildTools` 17.14.41 | [已验证] |

### 1.5 WebView2（Tauri 运行依赖）

| 检查项 | 实际结果 | 状态 |
|---|---|---|
| WebView2 Runtime | **已安装**，版本 154.0.4258.62（HKLM EdgeUpdate Clients `{F3017226-...}` 的 pv 与 `C:\Program Files (x86)\Microsoft\EdgeWebView\Application\154.0.4258.62` 目录互相印证） | [已验证] |
| Edge 浏览器 | 154.0.4258.62（与 WebView2 同版本，Evergreen 维护） | [已验证] |
| 版本是否满足 Tauri 2 | 满足（远高于 Tauri 2 最低要求） | [已验证] |

### 1.6 FFmpeg / FFprobe

| 检查项 | 实际结果 | 状态 |
|---|---|---|
| FFmpeg / FFprobe | **未安装**。已查：PATH（cmd/PowerShell/Git Bash 三路）、`C:\ffmpeg`、`D:\ffmpeg`、chocolatey bin、scoop shims、WinGet Links、`D:\anaconda3\Library\bin`、`D:\anaconda3\Scripts`、`D:\Python`、`C:\tools`、`D:\tools`，全部未命中 | [已验证（缺失）] → **P0** |
| 获取通道 | winget 可查询到 `Gyan.FFmpeg`，版本 9.0.2，元数据标注 **GPL-3.0**（静态完整版） | [已验证] |
| 许可证 | 具体构建的 `--enable-gpl` 等 configure flags 需在获取后复核（计划见 §9） | [待验证] |

### 1.7 网络与依赖可达性（全部实测 HTTP 状态）

| 目标 | 结果 | 状态 |
|---|---|---|
| registry.npmjs.org | 200 | [已验证] |
| index.crates.io / static.crates.io | 200 | [已验证] |
| api.nuget.org（Tauri 构建期 webview2-com 需要） | 200 | [已验证] |
| github.com | 200 | [已验证] |
| static.rust-lang.org（rustup 官方分发源） | 200（首字节 1.3s） | [已验证] |
| rsproxy.cn（国内 crates/rustup 镜像，备用） | 200 | [已验证] |
| 粗略吞吐抽样 | static.crates.io 单连接 ~0.4 MB/s；npmmirror ~0.13 MB/s（均为小文件单连接样本，仅供参考） | [已验证（抽样）][风险] → 首次依赖拉取预计 10–25 分钟，见 P1-3 |

### 1.8 运行依赖与打包环境

| 检查项 | 实际结果 | 状态 |
|---|---|---|
| VC++ 运行库（本机） | `C:\Windows\System32\vcruntime140.dll`、`msvcp140.dll` 均存在 | [已验证] |
| 干净目标机 VC++/WebView2 依赖 | 未在无依赖环境验证 | [待验证] → 打包验证清单见 §6 TC-12 |
| Tauri 打包器缓存 | `%LOCALAPPDATA%\tauri` 不存在（首次 `tauri build` 需联网下载 NSIS 等打包工具） | [已验证（缺失）][风险（低）] |
| Tauri 开发构建实测 | **无法在本阶段实测**（缺 Rust 与 MSVC，且本阶段不授权安装）。前置条件已具备：WebView2 已装、网络全通、winget 安装通道可用 | [待验证] → **Stage 1 Gate-0** |

### 1.9 已发现的本地环境缺陷

| 检查项 | 实际结果 | 状态 |
|---|---|---|
| Git Bash 的 $HOME | 显示为乱码路径 `/c/Users/瀹嬭垳姹�`（中文用户名编码问题）。含义：在 Git Bash 内运行依赖 $HOME 的工具（cargo/rustup/npm 的部分行为）可能解析到错误路径 | [已验证][风险] → P1-4 |
| 用户名 | `宋舜江`（中文）→ `C:\Users\宋舜江` | [已验证] |
| 项目路径 | `D:\应聘项目zcode`（含中文） | [已验证][风险] → P1-1 |

### 1.10 本阶段执行的检查命令（证据附录）

以下命令均为只读/非破坏性：`Get-CimInstance Win32_OperatingSystem`、`ls/find`（工作区）、`git rev-parse`、`git version`、`git config --global --list`、`node/npm --version`、`npm ls -g`、`npm config get registry|proxy`、`cmd where <tool...>`、PowerShell `Get-Command cl/link/lld-link/gcc`、`vswhere`（未找到）、`Get-ItemProperty` 注册表查询（EdgeUpdate Clients）、`Get-ChildItem` 目录探测（FFmpeg 候选路径、VS 目录、Windows Kits）、`Get-PSDrive`（磁盘）、`Get-CimInstance Win32_Processor/Win32_ComputerSystem`（CPU/内存）、`Test-Path`（vcruntime140.dll 等）、`Get-ItemProperty HKLM:\SYSTEM\...\FileSystem`（长路径）、`chcp`、`winget show`（三个包，只读查询）、`curl`（各注册表可达性与吞吐抽样）。

---

## 2. 工作区和 Git 状态

- `D:\应聘项目zcode` **为空目录**：无任何文件、无隐藏文件、无 `.git`。[已验证]
- 因此不存在覆盖、重建或重置已有项目的风险；本阶段也没有改动任何现有文件（新建 `docs/stage-0-audit.md` 为唯一新增）。
- 建议（Stage 1 执行，本阶段不做）：`git init` → 添加 `.gitignore`（node_modules、`target/`、`dist/`、证据大文件除外）与 `.gitattributes`（行尾策略，见 §10 决策 9）→ 首次提交骨架。
- 注意：项目路径含中文（`应聘项目zcode`），且用户名为中文（`宋舜江`）。构建与打包必须尽早在此真实路径冒烟验证（P1-1）。

---

## 3. 候选技术方案评估（Tauri 2 + React + TypeScript + FFmpeg/FFprobe CLI + Rust 后端）

### 3.1 当前环境是否适合该方案

**结论：适合，但存在一个必须先跨过的工具链门槛（非架构问题）。** [已验证 + 待验证]

- 适合的证据 [已验证]：WebView2 Runtime 已安装且版本足够；前端链路（Node 24 / npm 11）就绪；npm/crates/nuget/github 全部可达；winget 可安装 Rust 与 MSVC Build Tools；磁盘（D: 135GB）充足；12 核 / 15GB 内存足以支撑 Tauri 构建。
- 门槛 [已验证（缺失）]：Rust 工具链、MSVC Build Tools + Windows SDK、FFmpeg/FFprobe 三项全部缺席，且本阶段不授权安装 → 无法在本阶段实测 `tauri dev` / `tauri build`。[待验证] 的仅剩"安装后是否一次通过"，Stage 1 Gate-0 立即验证。
- 备选方案 **不启动**：无证据表明候选方案存在重大阻塞，故不提出变更技术栈；仅记录备选（见 §3.2 尾部）用于极端降级。

### 3.2 三天内实现并验证桌面客户端的风险

**结论：可控（若 Stage 1 首日上午通过 Gate-0），但打包与中文路径是本方案最大的两个验证风险点。** [风险]

关键路径与风险分解：

| 环节 | 预估工作量 | 主要风险 | 缓解 |
|---|---|---|---|
| 工具链安装（Rust+MSVC+FFmpeg） | 2–4h（含下载） | 下载慢（C 盘紧、带宽一般） | 授权后最先启动下载，并行做文档/设计 |
| Tauri 骨架 + dev 起窗 | 2–3h | 首次 cargo 构建耗时 10–25 分钟 | 保留增量缓存；开发期用 debug 构建 |
| ffprobe 元数据 + 缩略图 | 3–4h | 中文路径、黑帧、损坏文件 | Rust 传参（无 shell）、失败回退占位 |
| 转换核心 + 真实进度 + 状态机 | 4–5h | `-progress` 解析鲁棒性、duration 缺失 | ASCII key=value 解析；无 duration 显示不确定进度 |
| 队列 + 取消 + 重名 + 异常 | 3–4h | 取消后残留文件/进程 | `.part` 临时名 + kill + 清理策略 |
| Windows 打包（NSIS）+ 安装验证 | 2–4h | 首次 NSIS 下载、中文路径打包兼容性 | 提前触发一次打包；失败降级方案见 §7 |
| 文档 + 测试 + 提交 | 4–5h | 时间挤占 | 边开发边维护文档，末日晚间为缓冲 |

降级备选（仅当 Gate-0 或打包出现无法短期解决的问题时启用，需开发者授权）：
1. 在 ASCII 临时路径（如 `D:\clipforge-build`）完成构建/打包，仓库仍在本路径，问题记录到 decision-log；
2. 打包产物由 NSIS 安装包降级为 portable 目录（仍为真实桌面 EXE，非网页 Demo）；
3. 第二种输出格式由 WebM 降级为 MKV（重封装更快，仍满足"另一种有实际意义的格式"）。

### 3.3 FFmpeg 与 FFprobe 的分发、许可证、体积与路径管理

三种分发形态对比：

| 形态 | 做法 | 优点 | 缺点/成本 | 建议 |
|---|---|---|---|---|
| A. 系统依赖 + 应用内路径设置 | 应用按顺序探测：用户设置路径 → PATH → 常见安装目录；缺失时明确引导 | 开发/演示零体积成本；交付体积最小 | 目标机需自行具备 FFmpeg；依赖缺失是常见首跑问题 | **笔试交付默认采用**（配合清晰的缺失引导文案） |
| B. Tauri sidecar 打包 | `externalBin` 将 ffmpeg.exe/ffprobe.exe 随应用分发 | 开箱即用，演示最稳 | 安装包显著增大（二进制合计约 150–200MB 未压缩，NSIS 压缩后预计 +60–90MB，具体待获取实测）；需随附许可证文本 | Day 3 时间允许时作为加分项 |
| C. 运行期按需下载 | 首跑提示下载 | 包小 | 需要网络与校验流程，复杂度最高 | 不采用 |

许可证要点（详细核查计划见 §9）：
- winget 元数据已标注 Gyan 静态完整版为 **GPL-3.0** [已验证]；具体 `--enable-gpl` 等 flags 待获取后复核 [待验证]。
- GPL 构建含 libx264（MP4 的 H.264 编码所需），**副作用是本项目分发 FFmpeg 二进制时须遵守 GPL 条款**。本方案以独立进程方式调用 ffmpeg.exe（非静态链接进自有二进制），边界清晰；仍将在 README/LICENSE-NOTICE 中如实声明来源、版本、许可证与获取源码的途径。
- H.264 专利许可：本项目定位为技术笔试演示，不做商业分发；将在文档中声明。

路径管理：FFmpeg/FFprobe 可执行路径只来自"用户设置 → 探测结果"，绝不接受前端传来的任意命令字符串（见 §3.9）。

### 3.4 前端与 Rust 后端的职责边界

| 层 | 职责 | 明确不做 |
|---|---|---|
| Rust 后端（Tauri commands） | 探测/校验 FFmpeg 路径；spawn ffprobe 并解析 JSON；spawn ffmpeg 转换；进度事件；任务状态机；取消（kill + 清理）；文件系统操作（输出目录校验、重名探测、`.part` 改名）；缩略图生成与缓存管理；结构化日志 | 不把业务参数解析交给前端；不执行前端拼接的命令行 |
| React + TS 前端 | 导入交互（原生对话框）、信息展示、队列与进度视图、设置表单（输出目录/格式/质量/并发）、错误提示与引导 | 不拼接命令行；不直接访问文件系统（经 Rust command） |

IPC 设计：`invoke` 强类型命令（参数为枚举与数字，而非字符串命令）+ Rust → 前端 `emit` 进度/状态事件。Tauri capabilities 保持最小（默认核心集 + dialog），文件系统操作全部走自定义 Rust 命令，不开放宽泛的 fs 插件权限。

### 3.5 任务进度、取消、并发与异常处理方案

- **真实进度**：`ffmpeg -progress pipe:1 -nostats -y ...` 输出 ASCII `key=value`（如 `out_time_us`），以 `out_time / duration` 计算百分比；`duration` 来自 ffprobe。若 duration 缺失或为 0（部分流），显示**不确定进度**动画而非伪造百分比 [验收 D5 强相关]。抽样比对 ffmpeg 实际运行日志（TC-13）。
- **状态机**：`Pending → Running → (Completed | Failed(reason) | Canceled)`；禁止非法跃迁；每个任务保留 stderr 环形缓冲（尾部 N 行）与结构化错误码。
- **取消**：发送 kill（Windows 上终止子进程）；随后清理 `.part` 临时输出；若进程未在超时内退出则再次强杀并记录。取消后 UI 状态必须为 `Canceled` 而非 `Failed/Completed`。
- **并发**：默认并发 1（串行队列），设置中可选 1–2；用信号量控制同时运行的 ffmpeg 数；队列顺序稳定（FIFO）。
- **异常分类**：FFmpeg 缺失/不可执行（spawn 失败/EPERM）、输入不可读/损坏（ffprobe 失败）、编码器不支持、输出目录不可写、磁盘不足（预检 `GetDiskFreeSpaceEx` + 解析 ffmpeg stderr 的 `No space left`）、用户取消、未知（附带 stderr 尾部）。每类错误有独立、可追踪的提示与日志。
- **退出策略**：应用退出时先取消所有运行任务并等待退出，清理本次创建的 `.part` 文件；缓存按策略保留（见 §3.6）。

### 3.6 缩略图生成、缓存与清理方案

- 生成：`ffmpeg -ss <min(1s, 10%*duration)> -i <in> -frames:v 1 -vf "scale=480:-2" -f image2 <thumb.jpg>`；优先取 10% 时长处以减少黑帧；失败（不支持/损坏）时返回占位图 + 明确标签，不静默。
- 缓存：目录 `%LOCALAPPDATA%\ClipForge\thumbs\`；键 = `hash(绝对路径 + 文件大小 + mtime)`；命中直接复用。
- 并发：缩略图任务与转换任务共享同一队列信号量（缩略图优先级高、并发上限 2）。
- 清理：启动时按 LRU + 总大小上限（如 200MB）/条目上限（如 500）清理；任务被移除时可即时删除；提供"清空缓存"设置项。旋转元数据（rotation）需在缩略图管线中处理，避免横竖反转 [P2]。

### 3.7 中文路径、空格路径、特殊字符与文件重名处理

- **参数传递**：Rust 使用 `std::process::Command` + `OsString` 传参 → 走 Windows `CreateProcessW`，**无 shell 解析**，因此中文、空格、`&`、`^`、`%`、`"`、emoji 等字符均为字面量，无需转义、不可注入。这是选择 Tauri/Rust 而非"前端拼命令行"的核心安全收益（对应验收 E1）。
- **编码**：ffprobe 输出统一 `-print_format json`（UTF-8），Rust 侧按 UTF-8 解析；日志文件同样 UTF-8，避免 GBK 代码页（本机 936）污染。
- **重名**：输出前探测目标是否存在 → 默认自动追加 ` (n)` 后缀（`video (1).mp4`），可在设置中切换"询问/覆盖"；转换写到 `.part` 临时名，成功才原子改名，避免半成品污染与覆盖误判 [待开发者决策，§10]。
- **文件名安全**：非法字符校验（`<>:"/\|?*`、结尾点/空格）、路径长度提示（LongPaths 未启用，见 P1-5）、输出目录写权限与剩余空间预检。

### 3.8 Windows 打包后的运行依赖

| 依赖 | 本机状态 | 打包策略与风险 |
|---|---|---|
| WebView2 Runtime | 已装 154.x [已验证] | Tauri NSIS 默认 `downloadBootstrapper`：目标机缺失时联网获取；本机已装则零成本。README 中声明该依赖与离线场景说明 |
| VC++ 运行库（Rust MSVC 默认动态 CRT→ vcruntime140.dll） | 本机已装 [已验证] | 干净 Win10 若缺 vcruntime140.dll 将无法启动。计划：TC-12 在"可疑干净"条件验证；README 明确依赖；必要时 NSIS 增加检测提示（不默认内嵌） |
| FFmpeg / FFprobe | 未装 [已验证（缺失）] | 形态 A（系统依赖+设置）默认；sidecar 为可选加分（§3.3） |
| 网络 | 打包机需要（首次 NSIS/依赖下载） | 已验证可达 [已验证] |

### 3.9 如何避免前端调用任意系统命令

设计约束（写入代码评审清单与测试用例）：
1. 前端**只能**传入强类型枚举与数字：`outputFormat: "mp4" | "mkv" | "webm"`、`crf: number`、`preset: string(白名单)`、`scale: {mode: "keep"|"720p"|"1080p"}`、路径字符串（仅作为文件定位，不进入命令行解释）。
2. Rust 侧维护**固定映射表**：枚举 → 固定参数数组（如 `mp4` → `["-c:v","libx264","-c:a","aac","-movflags","+faststart"]`），不拼接、不解释、不做字符串替换。
3. FFmpeg/FFprobe 可执行文件路径仅来自"用户设置（原生文件对话框选择）→ 探测（PATH/常见目录）"；设置值必须是存在的文件且 file_name 匹配 `ffmpeg(.exe)?`。
4. 输入/输出路径必须通过 `PathBuf` 规范化并校验存在性/可写性/扩展名白名单，禁止 `..` 越权语义（仅作提示，非安全边界）。
5. Tauri capabilities 最小化，关闭不必要插件权限；无自定义 shell 插件。
6. 单元测试覆盖参数构造函数：给恶意字符串输入（`; rm -rf`、`&& calc`、`$(...)`、换行）断言其仅作为普通参数出现在 `OsString` 列表中 [验收 E1 证据]。

### 3.10 如何证明交付的是桌面应用而非网页 Demo

证据清单（写入 README 与 docs/test-report.md）：
1. `npm run tauri build` 的产物：`src-tauri\target\release\ClipForge.exe` 与 NSIS 安装包（记录 SHA256、文件大小、构建日期）。
2. 安装/解压后在 Windows 上独立启动的截图/录屏：原生窗口、Windows 任务栏、无浏览器地址栏/标签页、可最小化/最大化/关闭。
3. 进程证据：任务管理器中 `ClipForge.exe`（WebView2 子进程属正常架构，说明其为 Tauri 而非"用浏览器打开页面"）。
4. 功能演示走原生能力：原生文件选择器对话框、原生目录打开（资源管理器定位输出文件）。
5. 文档：可复现构建步骤（版本锁定：`package-lock.json` / `Cargo.lock` 入库），非"打开 localhost 页面"。

---

## 4. 风险清单（按 P0 / P1 / P2 排序）

### P0（阻塞项：必须在 Stage 1 开工前解决，均有已验证的解决路径）

| ID | 风险 | 影响 | 解决方式 | 验证门槛 |
|---|---|---|---|---|
| P0-1 | Rust 工具链未安装（rustup/rustc/cargo 全缺）[已验证] | 无法编译任何 Tauri 代码 | 授权后 `winget install Rustlang.Rustup`（或官方 rustup-init.exe，static.rust-lang.org 已验证可达）；**在 PowerShell 中执行**（规避 Git Bash HOME 乱码，P1-4） | `cargo --version`、`rustc --version` 正常；default host = `x86_64-pc-windows-msvc` |
| P0-2 | MSVC Build Tools + Windows SDK 未安装 [已验证] | 无法链接 Rust/Windows 二进制 | 授权后 `winget install Microsoft.VisualStudio.2022.BuildTools`（VC Tools 工作负载 + Windows SDK；注意 C: 空间，见 P1-2） | `vswhere` 可见安装；简单 Rust 项目链接成功（Gate-0） |
| P0-3 | FFmpeg/FFprobe 未安装 [已验证] | 视频信息、缩略图、转换全部无法开发与验收 | 授权后 `winget install Gyan.FFmpeg`（9.0.2）或官方 zip 解压至 `D:\tools\ffmpeg`，并记录版本/SHA256/许可证 flags | `ffprobe -v quiet -print_format json -show_format <样例>` 输出合法 JSON |

> P0 均为"缺失 + 已验证安装路径 + 无技术不确定性"，属**流程性阻塞**而非架构性阻塞。Stage 1 首个 Gate（Gate-0）完成即转为已验证。

### P1（高优先：开工后前 24 小时内必须验证或缓解）

| ID | 风险 | 证据/分析 | 缓解与验证 |
|---|---|---|---|
| P1-1 | 中文用户名（`C:\Users\宋舜江`）+ 中文项目路径（`D:\应聘项目zcode`）× 构建/打包兼容性 | 中文路径历史上对 NSIS 打包、部分构建脚本有兼容问题 [风险] | Day 1 即在真实路径下完成 hello-world 构建 + Tauri build 冒烟；如打包失败，启用 §3.2 降级方案并记录 decision-log |
| P1-2 | C: 盘仅剩 22.0GB（91% 满） | [已验证] BuildTools（约 5–8GB）+ rustup（约 1–2GB）+ cargo registry/npm 缓存 vs 余量 | 安装 BuildTools 仅选必需组件；`CARGO_TARGET_DIR=D:\cargo-target`（target 放 D:）；可选清理 npm 缓存（不擅自执行） |
| P1-3 | 首次依赖拉取量大且单连接速度一般（crates 抽样 ~0.4MB/s，npmmirror 抽样 ~0.13MB/s） | [已验证（抽样）] Tauri 依赖树数百个 crate（约数百 MB） | 工具链就绪后第一时间 `cargo fetch` 预热；备用 rsproxy.cn 镜像（已验证可达）；npm 已在用 npmmirror |
| P1-4 | Git Bash `$HOME` 乱码（`/c/Users/瀹嬭垳姹�`） | [已验证] 影响 cargo/rustup 在 Bash 会话中的 home 解析 | 工具链安装、构建、打包统一在 PowerShell/cmd 执行；如需 Bash，先 `export HOME="$(cygpath "$USERPROFILE")"` 并验证 |
| P1-5 | LongPathsEnabled=0（未启用），项目路径+node_modules/cargo 路径较深 | [已验证] | 保持构建路径短（项目根 `D:\应聘项目zcode\clipforge`、target 用 `D:\cargo-target`）；是否启用长路径注册表需开发者决定（需管理员） |
| P1-6 | 进度解析鲁棒性（duration 缺失/可变帧率/多流） | [风险] | 以 `-progress pipe:1` 的 `out_time` 为准；无 duration 显示不确定进度；TC-13 比对真实时间 |
| P1-7 | FFmpeg 缺失时的用户体验 | 验收 D3/TC-10 要求 | 启动时探测 + 首次转换前预检；缺失时给出"安装/选择路径"的明确引导，不崩溃、不伪成功 |
| P1-8 | 干净目标机的 VC++/WebView2 依赖未验证 | [待验证] | TC-12 打包验证清单逐项检查；README 声明依赖 |

### P2（低优先：记录并择机处理）

| ID | 风险 | 说明 |
|---|---|---|
| P2-1 | 缩略图黑帧/旋转元数据 | 取 10% 时长点；按 rotation 旋转；失败回退占位图 |
| P2-2 | 取消/崩溃后的 `.part` 残留与孤儿进程 | 启动时清扫与退出时清理；超时强杀 |
| P2-3 | sidecar 分发使安装包增量约 60–90MB | 仅当决定打包 FFmpeg 时发生；体积数据获取后实测更新 |
| P2-4 | 行尾策略未定（core.autocrlf 未设置） | Stage 1 `git init` 时用 `.gitattributes` 固定（见 §10 决策 9） |
| P2-5 | 首次 `tauri build` 需下载 NSIS 打包器（缓存目录当前不存在） | 网络已验证；首次打包预留时间 |
| P2-6 | UI 打磨（DPI、暗色、空状态、错误态文案） | 时间允许时处理，不影响验收 |

---

## 5. 功能需求与验收矩阵（覆盖招聘要求 A–G）

| 需求（原文要点） | 实现方案 | 验收证据 | 用例 | 阶段 |
|---|---|---|---|---|
| A1 真正的 Windows 桌面应用 | Tauri 2 原生窗口 + NSIS 安装包 | 安装包 SHA256 + 独立启动截图（§3.10 清单） | TC-12 | D1 骨架 / D3 打包 |
| A2 合理布局与清晰操作路径 | 单页三段式：导入区 → 队列/进度区 → 设置与日志抽屉；主操作按钮唯一 | UI 走查截图（含空状态/错误态） | TC-01/02 | D1 |
| A3 目标环境可启动 | 打包后在目标机安装启动 | 启动截图 + 进程证据 | TC-12 | D3 |
| B1 原生文件选择器导入 | tauri dialog 插件（多选、视频过滤器） | 对话框截图 + 导入后队列出现条目 | TC-01 | D1 |
| B2 文件名/大小/时长/分辨率/编码 | ffprobe `-print_format json` 解析（含音频流信息） | 界面截图 + 与 ffprobe CLI 输出并排比对 | TC-01 | D1 |
| B3 真实缩略图 | ffmpeg 抽帧（10% 时长点，480px 宽） | 截图 + 与源视频关键帧视觉比对说明（非占位图） | TC-02 | D1 |
| B4 不支持/损坏/不可读处理 | ffprobe 失败分类 + 行内错误态 | 错误态截图 + 日志片段 | TC-06 | D1–D2 |
| C1 FFmpeg CLI 真实转换 | Rust spawn ffmpeg（白名单参数） | 转换日志 + 输出文件 | TC-03 | D2 |
| C2 MP4 + 另一种有意义格式 | 预设表：MP4(H.264/AAC)；第二格式见 §10 决策 1 | 两种输出的 ffprobe 验证 JSON | TC-03/04 | D2 |
| C3 输出目录与文件名选择 | 原生目录对话框 + 文件名输入 + 校验 | 截图 + 输出落点证据 | TC-03 | D2 |
| C4 真实状态/进度/成败反馈 | 状态机 + `-progress` 事件 + 结果条与日志 | 状态流转截图序列 + 时间线比对 | TC-13 | D2 |
| C5 取消转换 | kill + `.part` 清理 + Canceled 状态 | 取消前后截图 + 无残留文件清单 + 进程列表 | TC-07 | D2 |
| C6 输出存在且可被读取 | 完成后 ffprobe 复核输出（编码/时长/可解码） | ffprobe 输出 JSON 附于 test-report | TC-03/04/12 | D2–D3 |
| D1 多文件导入与队列 | 多选导入 + FIFO 队列（默认并发 1） | 队列截图（多条目不同状态） | TC-09 | D2 |
| D2 合理默认设置 | 默认 MP4 + CRF 23 + 源分辨率 + 输出到源目录旁 | 默认值截图 + README 说明 | TC-03 | D2 |
| D3 重复任务/重名/磁盘不足/依赖缺失 | 去重提示 + ` (n)` 重命名 + 空间预检 + 依赖引导 | 各异常场景截图与日志 | TC-08/10/11/14 | D2 |
| D4 查看结果并打开输出目录 | 结果操作按钮（打开目录并选中文件，`explorer /select`） | 资源管理器截图 | TC-03 | D2 |
| D5 不模拟进度 | 进度只来自 `out_time`；无数据时不确定性动画 | TC-13 时间线比对记录 | TC-13 | D2 |
| E1 安全传参（无 shell 拼接） | OsString + 固定映射表（§3.9） | 单元测试（恶意字符串用例）+ 代码走查记录 | 自动 | D2 |
| E2 明确状态机与可追踪错误 | 枚举状态机 + 错误码 + 任务日志 | 状态机单元测试 + 错误场景日志 | TC-06/10/11 | D2 |
| E3 进程退出/取消/临时文件/资源清理策略 | `.part` 原子改名 + 启动/退出清扫 + 超时强杀 | 策略文档节 + 清理前后文件清单 | TC-07 | D2 |
| E4 自动化测试与真实视频验收 | `cargo test`（状态机/参数构造/重名/错误映射）+ 前端纯函数单测（可选）+ 真实视频手工矩阵 | 测试输出 + test-report.md | 全部 | D2–D3 |
| F1–F5 五份文档 + README | 见 §8 维护策略 | 文件存在 + 内容含真实决策/证据 | — | 持续 |
| G1 可复现构建 | 锁定 `package-lock.json`/`Cargo.lock` + 固定工具链版本说明 | 干净克隆按 README 构建成功记录 | TC-12 | D3 |
| G2 无密钥/隐私/无关本机文件 | `.gitignore` + 提交前扫描（密钥、绝对路径日志、证据大文件） | 扫描记录（如 grep 规则） | — | D3 |
| G3 清楚的安装/运行/使用说明 | README（含依赖前置、FFmpeg 获取、FAQ） | README 走查 | — | D3 |
| G4 HR 交付说明 | 仓库链接 + 一句话说明 + 演示要点 + 文档索引 | 交付说明文件/消息草稿 | — | D3 |

---

## 6. 测试用例矩阵（设计，尚未执行）

> 说明：以下均为**设计**用例，Stage 0 未执行任何一条。执行结果将在 `docs/test-report.md` 中逐条记录（含命令与原始输出/截图路径）。
> 证据统一存放 `docs/evidence/`（截图命名 `TC-xx-描述.png`，日志/JSON 同名）。"自动"列标注该用例是否可被自动化覆盖。

| ID | 场景 | 前置条件 | 操作步骤 | 预期结果 | 证据要求 | 方式 |
|---|---|---|---|---|---|---|
| TC-01 | 正常导入常见视频 | 打包/dev 应用可运行；准备 1 个 H.264+AAC 的 MP4（≥10s） | 点击导入 → 原生对话框选择该文件 → 等待解析 | 队列出现条目；文件名/大小/时长/分辨率/视频编码/音频编码与 ffprobe CLI 输出一致；无报错 | 导入后界面截图；ffprobe CLI 原始 JSON 与界面并排比对记录 | 手工+自动（解析层单测） |
| TC-02 | 缩略图与元数据真实显示 | TC-01 已导入 | 观察缩略图；与视频实际画面（用播放器定位 10% 位置）比对 | 缩略图为该视频真实帧（非占位/非默认图）；分辨率信息正确 | 界面截图 + 播放器同帧截图（并排） | 手工 |
| TC-03 | 成功转换为 MP4 | TC-01 完成；FFmpeg 可用 | 保持默认（MP4）→ 选择输出目录与文件名 → 开始转换 → 等待完成 | 状态 Pending→Running→Completed；进度单调递增且与真实耗时吻合；输出文件存在；`ffprobe` 复核容器/编码/时长有效；可播放 | 状态流转截图；输出目录文件列表；输出 ffprobe JSON；输出文件 SHA256 | 手工+自动（后端集成测试） |
| TC-04 | 转换为另一种输出格式 | 同上；第二格式确定（§10 决策 1） | 选择第二格式 → 转换 → 完成 | 输出文件容器/编码符合目标格式；ffprobe 可读；可播放 | 同 TC-03（目标格式） | 手工+自动 |
| TC-05 | 中文与空格路径 | 准备输入 `中文 目录\测试 视频 & 1.mp4`；输出目录含中文与空格 | 从该路径导入 → 输出到 `中文 输出 目录` | 导入、缩略图、转换全部成功；无编码/转义错误；输出文件名正确 | 路径截图（含资源管理器地址栏）+ ffprobe 输出 | 手工 |
| TC-06 | 无效文件与损坏文件 | 准备：改扩展名为 .mp4 的文本文件；截断的 MP4（保留头部） | 依次导入 | 条目显示明确"无法解析/损坏"错误态；应用不崩溃；日志含可追踪错误码与原因 | 错误态截图 + 日志片段 | 手工+自动（错误映射单测） |
| TC-07 | 取消正在运行的转换 | 准备较长视频（≥60s）使进度可见 | 开始转换 → 进度 ~30% 时点击取消 | 状态变为 Canceled（非 Failed/Completed）；ffmpeg 进程终止；无 `.part` 残留；输出目录无半成品文件；随后可继续发起新任务 | 取消前后截图；进程列表；输出目录文件清单 | 手工+自动（后端单测覆盖状态机） |
| TC-08 | 输出文件重名 | 输出目录已存在同名目标文件（含中文名） | 用相同输出名转换 | 按策略处理（默认自动 ` (1)` 后缀）；原文件不被破坏；UI 明确告知最终文件名 | 输出目录列表截图；最终文件名 | 手工+自动（重名函数单测） |
| TC-09 | 多任务排队 | FFmpeg 可用；准备 3 个不同视频 | 一次性导入 3 个 → 全部加入队列 → 开始 | 默认串行执行：第 2/3 个依次 Running；进度各自正确；全部完成或按序失败；UI 无状态串扰 | 队列多状态截图（至少一张含 1 running + 2 pending） | 手工 |
| TC-10 | FFmpeg 缺失或不可执行 | 将 FFmpeg 路径置空/指向不存在文件/指向不可执行文件 | 触发探测与一次转换尝试 | 应用明确提示依赖缺失与解决方式；不崩溃；不显示成功；日志含错误码 | 提示截图 + 日志 | 手工+自动（探测逻辑单测） |
| TC-11 | 转换失败后不显示成功 | 构造失败：输出目录只读；或（可选）小分区模拟磁盘不足；或输入中途损坏 | 触发转换 | 状态为 Failed + 原因（权限/空间/输入）；无成功提示；不残留 `.part`；可重试 | 失败态截图 + 日志 + 输出目录清单 | 手工 |
| TC-12 | 打包后目标环境启动与转换 | `tauri build` 产物（NSIS 或降级产物）；目标机（本机） | 安装 → 开始菜单启动 → 导入视频 → 转换 → 打开输出目录 | 独立 EXE 启动（无浏览器特征）；全流程成功；输出可被 ffprobe/播放器读取 | 安装包 SHA256；启动截图（含任务栏）；转换全流程截图；输出 ffprobe JSON | 手工（验收关键） |
| TC-13 | 进度真实性抽查 | 较长视频 | 转换过程中记录 UI 进度时间戳（含截图）并与 ffmpeg 日志时间线/系统时钟比对 | UI 进度变化与真实处理进度一致（误差在合理范围）；无"固定速率假进度"；无 duration 场景显示不确定态 | 时间线比对表（UI 截图时间 vs 日志 out_time） | 手工 |
| TC-14 | 重复任务与队列去重 | 已导入文件 A（未开始或已完成） | 再次导入同一文件 A | 按策略去重或明确提示重复（不静默创建难以察觉的重复项）；行为与文档一致 | 重复导入提示截图 | 手工+自动（去重逻辑单测） |

---

## 7. 三天开发计划与阶段依赖

原则：**每个阶段有明确 Gate，未过 Gate 不进入下一阶段；每晚预留 1–2 小时缓冲；Day 3 晚为总缓冲。**

### Day 1 — 工具链落地 + 应用骨架 + 导入与元数据（10h）

| 时段 | 任务 | Gate/依赖 |
|---|---|---|
| 0–3h | **[需授权]** 安装 Rust 工具链、MSVC Build Tools（VC Tools + Windows SDK）、FFmpeg；PowerShell 中执行；并行开始预热依赖 | P0-1/2/3 关闭条件 |
| 3–5h | **Gate-0 冒烟**：Rust hello-world 编译；`npm create tauri-app`（Tauri 2 + React + TS）；`npm run tauri dev` 起原生窗口；**在中文真实路径下验证** | **Gate-0：通过则继续；失败立即止损并重评方案（含 §3.2 降级）** |
| 5–6h | `git init` + `.gitignore`/`.gitattributes` + 骨架首提交；建立 `docs/` 与 `docs/evidence/` | Gate-0 通过 |
| 6–8h | 应用布局（三段式）；原生文件选择器；ffprobe 集成与元数据展示 | — |
| 8–10h | 缩略图生成 + 缓存雏形 + 错误态基础（损坏文件） | **Gate-1：导入视频显示真实信息与真实缩略图（TC-01/02 预演）** |

### Day 2 — 转换核心 + 队列与健壮性（10h）

| 时段 | 任务 | Gate/依赖 |
|---|---|---|
| 0–3h | 转换核心：参数白名单映射、输出目录/文件名、MP4 默认预设、`.part` 原子写入 | Gate-1 |
| 3–5h | `-progress` 解析 + 状态机 + 事件推送 + 任务日志 | — |
| 5–7h | 队列（多文件、FIFO、并发 1）+ 取消（kill+清理）+ 重名处理 | — |
| 7–9h | 第二输出格式 + 磁盘不足预检 + FFmpeg 缺失引导 + 打开输出目录 | — |
| 9–10h | 手工回归 | **Gate-2：TC-01…08、10、11、13、14 在 dev 模式通过（失败项记录并修复）** |

### Day 3 — 打包 + 自动化测试 + 文档 + 交付（10h）

| 时段 | 任务 | Gate/依赖 |
|---|---|---|
| 0–3h | `npm run tauri build`（NSIS）；安装/启动/转换验证（TC-12）；修复打包问题（中文路径兼容性在此暴露） | Gate-2 |
| 3–4h | 自动化测试补齐：`cargo test`（状态机/参数构造/重名/错误映射）+ 前端单测（可选） | — |
| 4–6h | 真实视频全量回归（TC 矩阵逐条）+ 证据归档到 `docs/evidence/` | — |
| 6–8h | 文档五件套 + README + LICENSE-NOTICE（FFmpeg 声明）+ 证据索引 | 测试执行完毕 |
| 8–9h | 清理（无密钥/无关文件）、可复现构建走查（README 步骤核验） | — |
| 9–10h（+缓冲） | 最终提交；HR 交付说明（仓库链接 + 使用说明 + 文档索引） | **Gate-3：打包产物可安装启动并真实转换；文档齐全真实；仓库可复现构建** |

### 阶段依赖链（单线关键路径）

`工具链安装 → Gate-0 骨架构建 → ffprobe/缩略图 → Gate-1 → 转换/进度 → 队列/取消 → Gate-2 → 打包 → Gate-3 → 文档/交付`

延迟传导规则：Gate-0 延期 >3h → 当天砍掉缩略图精修，保住导入+元数据；Gate-2 延期 → Day 3 上午仅做打包与 TC-12，自动化测试降级为关键单测；打包失败 >2h → 启用降级方案（portable 产物）并在文档如实记录。

---

## 8. 文档维护策略

维护对象（Stage 1 起持续更新，非最后补写）：

| 文档 | 内容 | 更新时机 | 真实性约束 |
|---|---|---|---|
| README.md | 项目说明、依赖前置、安装/运行/使用、可复现构建、FAQ（FFmpeg 获取） | 每个 Gate 后 + 打包变更时 | 步骤必须为实际执行通过的步骤 |
| docs/requirements-and-acceptance.md | 需求与验收矩阵（§5 的持续版本） | 需求/范围变化时 | 变更留痕，不删旧条目 |
| docs/decision-log.md | 关键决策：日期、背景、候选选项、决策、理由、影响（含被否方案） | 每个决策发生时（同日） | 不事后补造；失败决策也记录 |
| docs/ai-session-summary.md | 与 AI 的关键交互：任务、有效提示、AI 的错误与开发者的纠正与反馈、最终采用与否 | 每日收尾 + 重大转折时 | 原样记录真实交互，允许包含 AI 被纠正的案例 |
| docs/test-report.md | 每条 TC：执行时间、环境、命令、原始输出片段/截图路径、通过/失败/未执行（含原因） | 每轮测试执行后立即 | 未执行必须写"未执行+原因"；禁止把未执行写成通过 |
| docs/evidence/ | 截图、ffprobe JSON、日志、SHA256 清单 | 随测试同步 | 文件名对应 TC 编号 |
| LICENSE-NOTICE（或 README 章节） | FFmpeg 来源/版本/许可证与源码获取途径、H.264 专利声明 | FFmpeg 获取与最终分发时 | 与实际使用构建一致 |

本报告（`docs/stage-0-audit.md`）作为 Stage 0 的冻结基线，后续如结论被实测推翻（例如 Gate-0 失败），在文件末尾以"修订记录"追加，不重写历史。

---

## 9. FFmpeg 分发和许可证核查计划

1. **获取（Stage 1，需授权）**：`winget install Gyan.FFmpeg`（当前可见版本 9.0.2，元数据标注 GPL-3.0）或从 gyan.dev 官方页下载 zip 解压至 `D:\tools\ffmpeg`。
2. **完整性记录**：记录下载源 URL、版本号、构建日期、`ffmpeg.exe`/`ffprobe.exe` 的 SHA256，写入 `decision-log.md` 与 `LICENSE-NOTICE`。
3. **许可证判定**：执行 `ffmpeg -version` 读取 configure flags，确认 `--enable-gpl`、`--enable-nonfree`（不应存在）、是否含 `libx264`；GPL 构建 → 分发约束（提供许可证全文与源码获取指引，gyan.dev 提供官方源码链接）。
4. **分发形态决策（§10 决策 2）**：
   - 形态 A（推荐默认）：应用不携带二进制；文档指导用户安装；应用检测失败时给出指引。
   - 形态 B（可选加分）：sidecar 打包时，随附 `LICENSE`/`COPYING.GPLv3` 与来源说明；体积增量实测后更新文档（当前预估安装包 +60–90MB，[待验证]）。
5. **用法边界声明**：独立进程调用（非静态链接），应用自有代码不包含 FFmpeg 代码；文档中如实声明"以外部 GPL 工具执行转换"。
6. **专利声明**：H.264/MPEG-4 相关专利许可在商业分发场景需单独评估；本项目为技术演示，写入 README 声明。
7. **核查完成标准**：`LICENSE-NOTICE` 中的版本、SHA256、flags、许可证结论与实机产物一致，可被第三方复核。

---

## 10. 尚需开发者决定的问题

| # | 问题 | 选项 | 我的建议（供决策） |
|---|---|---|---|
| 1 | 第二种输出格式 | MKV（H.264+AAC，快）/ WebM（VP9+Opus，慢但格式差异明显）/ GIF（直观但非视频格式） | **MKV 为主**（转换快、演示稳）；WebM 若时间富余作为第三种 |
| 2 | FFmpeg 分发形态 | A 系统依赖+设置 / B sidecar 打包 | 默认 A；Day 3 打包顺利后视时间做 B（加分项） |
| 3 | 转换并发默认值 | 1 / 2 | 默认 1（安全、易解释），设置中允许 2 |
| 4 | 输出重名默认策略 | 自动 ` (n)` / 询问 / 覆盖 | 自动 ` (n)` 后缀，设置中可改 |
| 5 | 硬件加速（NVENC） | 开启 / 不开启 | 默认关闭，列为可选预设（本机 nvidia-smi 存在，可作演示加分） |
| 6 | 打包目标 | NSIS / MSI / portable zip | NSIS（Tauri 默认、体积小）；失败降级 portable |
| 7 | 是否启用系统长路径（需管理员） | 启用 / 保持关闭 | 保持关闭（用短路径规避），避免改动系统配置 |
| 8 | 仓库可见性与许可证 | 公开+MIT / 私有 | 公开仓库 + MIT（含 FFmpeg 声明；具体按求职意愿） |
| 9 | 行尾策略 | `.gitattributes` 统一 LF / 默认 | 统一 LF（`* text=auto eol=lf`），避免 Windows 提交噪音 |
| 10 | 测试样片来源 | ffmpeg `testsrc` 生成小样片 + 自录短片段 / 外部素材 | 用 testsrc 生成脚本 + 1–2 个真实短片段（不入库超大文件，>10MB 排除） |
| 11 | 是否允许 Stage 1 安装软件 | 是 / 否 | 必须为"是"，否则 P0-1/2/3 无法关闭（本阶段已按规则未安装） |

---

## 11. Stage 0 结论

### 结论：**CONDITIONAL PASS**

**依据（对照 PASS 条件）：**

| PASS 条件 | 判定 | 说明 |
|---|---|---|
| 环境可行性已验证 | ⚠️ 部分 | 前端链路、WebView2（154.x 已装）、网络（五个注册表全通）、winget 安装通道（三包可查）[已验证]；但 Rust/MSVC/FFmpeg 缺失且本阶段不授权安装，**无法实测 Tauri 构建与打包** [待验证] → 构成条件项 |
| 关键架构不存在未解决的 P0 风险 | ✅ | 架构层面无 P0；三个 P0 均为"工具缺失 + 已验证的一键安装路径 + 无技术不确定性"，属流程性阻塞，有明确关闭门槛 |
| 三天范围可控 | ✅ | 关键路径清晰（§7），每个 Gate 有失败降级策略，晚间断点即止损点 |
| 每项招聘要求都有对应验收标准 | ✅ | §5 矩阵覆盖 A–G 全部条目并映射到 §6 用例 |
| 下一阶段实施顺序与测试门槛明确 | ✅ | §7 的 Gate-0 → 1 → 2 → 3 与 §6 的 TC 矩阵一一挂钩 |

**CONDITIONAL PASS 的条件（Stage 1 开工前必须满足）：**

1. **授权安装三项 P0 依赖**（Rust 工具链、MSVC Build Tools + Windows SDK、FFmpeg/FFprobe），并使用 PowerShell 执行以规避 Git Bash HOME 乱码（P1-4）。
2. **Gate-0 冒烟验证通过**：在中文真实路径 `D:\应聘项目zcode` 下完成 Rust hello-world 编译 + Tauri 2 + React + TS 骨架 `tauri dev` 起窗。
3. **P1-1（中文路径打包兼容性）与 P1-5（长路径/短路径策略）在 Day 1 给出验证结论**；未通过则启用 §3.2 降级方案并记录。

**明确阻塞项（当前状态）：**

- 无**架构性**阻塞；存在**流程性阻塞**：P0-1/P0-2/P0-3（依赖缺失，等待 Stage 1 授权安装）。
- 若因故不允许安装 Rust/MSVC：则该方案在本机**无法实现**，届时结论应改判 FAIL 并重新选择技术栈——这是本报告最重要的前置假设。

**风险提示（不影响结论，需持续跟踪）：** C: 盘余量 22GB（P1-2）、首次依赖拉取速度（P1-3）、干净目标机 VC++/WebView2 依赖验证（P1-8）。

### 停止声明

本阶段到此停止：未创建应用、未开始任何业务功能实现、未安装/修改系统、未执行 `git init`/提交/推送、未创建远程仓库。工作区唯一新增文件为本报告 `docs/stage-0-audit.md`。等待开发者对 §10 决策项与 §11 条件的明确授权后进入 Stage 1。

---

# Stage 1 修订记录（2026-10-10 追加；本报告正文保持 Stage 0 原始结论不变）

> 追加原因：开发者在 Stage 1 授权安装依赖并进行 Gate-0 验证。本记录只追加，不重写历史。
> 详细命令、退出码、耗时与证据见 `docs/test-report.md` 与 `docs/evidence/`。

## 1. P0 关闭情况

| 原 P0 | 状态 | 实测结果 |
|---|---|---|
| P0-1 Rust 工具链缺失 | **已关闭** | winget `Rustlang.Rustup` 1.29.1 安装 EXIT=0；rustc/cargo 1.99.0；host 与 target = `x86_64-pc-windows-msvc` |
| P0-2 MSVC + Windows SDK 缺失 | **已关闭** | VS BuildTools 17.14.37710.0（VC Tools 14.44.35207、SDK 10.0.26100.0、MSBuild）安装 EXIT=0；Gate-0A 链接实测通过 |
| P0-3 FFmpeg/FFprobe 缺失 | **已关闭** | Gyan.FFmpeg 9.0.2（GPL-3.0）安装 EXIT=0；版本/哈希/configure flags 已记录；Gate-0C 全通过 |

## 2. Stage 0 环境假设的修正（实测推翻/更新）

1. **P1-4 Git Bash HOME 乱码的范围收窄 [已验证]**：乱码仅存在于 Git Bash 侧；PowerShell 会话内 `HOME`/`USERPROFILE` 均为正确的 `C:\Users\宋舜江`，中文参数与中文路径往返正常。缓解措施从"修正 HOME"改为"安装/构建统一在 PowerShell 执行"（已执行）。
2. **FFmpeg 的 PATH 注册方式 [已验证]**：winget 未使用 `WinGet\Links` 别名目录（该目录为空），而是把安装 bin 目录直接写入**用户 PATH**（与 Rustup 写入 `.cargo\bin` 方式相同）。已在运行的进程继承旧环境快照，需显式路径或新进程生效——Stage 2 应用必须实现运行时探测（设置路径 > PATH > WinGet Packages 目录 > 常见目录），不得假设 `ffmpeg` 命令必然可见。
3. **UAC 交互假设 [已验证]**：本机 `ConsentPromptBehaviorAdmin=0`（静默提权）且当前用户属于 Administrators 组，安装全程无需人工点击 UAC；Stage 0 中"需要管理员交互则暂停"的风险未触发。
4. **磁盘风险量化 [已验证]**：安装后 C: 由 21.9GB 降至 12.03GB（VS BuildTools 与缓存占约 10GB）。P1-2 风险仍成立但可控（构建产物已全部导向 `D:\cargo-target`，D: 余 132.12GB）。

## 3. Gate-0 结果（全部实测）

| Gate | 结论 | 一句话证据 |
|---|---|---|
| Gate-0A Rust 工具链 | **PASS** | 中文用户名路径下 `cargo build`（1.37s, EXIT=0）与 `cargo run`（`Hello, world!`, EXIT=0） |
| Gate-0B Tauri 桌面骨架 | **PASS** | 346 个编译单元 2m20s 完成；原生窗口显示/响应/关闭/重启全部验证（含 4 张截图与 UIA→Rust IPC 交互证据）；重启仅 5.5s，关闭后 1.15s 全链路退出、零残留 |
| Gate-0C FFmpeg 基础验证 | **PASS** | testsrc2 样片生成、ffprobe JSON 读取、libx264 真实 MP4 转换（0.2s）、全片解码 EXIT=0；附加：`测试 目录\输出 视频.mp4` 中文+空格路径转换成功 |

**P1-1（中文路径 × 构建/打包兼容性）的实质结论 [待验证（打包部分）]**：在中文用户名 + 中文项目路径下，Rust 编译链接、Tauri dev 构建运行、FFmpeg 转换均已实测成功；**NSIS 打包的兼容性仍待 Stage 3 实测**（Gate-0 未包含 release 打包）。

## 4. 其他环境变化记录

- 新增用户级环境变量 `CARGO_TARGET_DIR=D:\cargo-target`（开发者指令，D-0005）。
- 用户 PATH 新增（由安装器写入）：`%USERPROFILE%\.cargo\bin`、FFmpeg 9.0.2 bin 目录。
- 新增文件：`clipforge\`（Tauri 骨架，含 package-lock.json、src-tauri\Cargo.lock）、`docs/decision-log.md`、`docs/ai-session-summary.md`、`docs/test-report.md`、`docs/evidence\*`。未创建 Git 仓库，未提交，未推送。

## 5. 修订后的阶段结论

- Stage 0 的 CONDITIONAL PASS 三项条件已全部满足（授权安装、Gate-0 冒烟、P1 验证结论）。
- **结论更新：PASS（Stage 1）。** 允许在开发者下一次明确授权后进入 Stage 2（正式业务功能开发）；Stage 2 范围建议以本报告 §5 验收矩阵与 §6 用例矩阵为准。

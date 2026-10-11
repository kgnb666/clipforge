# ClipForge 测试报告（Test Report）

> 原则：只记录**实际执行过**的测试与真实输出；未执行的测试明确标注"未执行"及原因。
> 所有证据文件位于 `docs/evidence/`（截图 PNG、命令行日志、媒体产物），日志同时在 `D:\cargo-target\logs\` 保留原件。

---

## 1. 执行环境

| 项 | 值 |
|---|---|
| 日期 | 2026-10-10（17:46 – 18:04，UTC+8） |
| 机器 | Windows 10 专业版 22H2（10.0.19045，x64），12 逻辑核 / 15.2GB RAM |
| 项目路径 | `D:\应聘项目zcode\clipforge`（含中文路径） |
| 用户目录 | `C:\Users\宋舜江`（中文用户名） |
| 终端 | PowerShell 5.1（由 Git Bash 会话派生；所有安装/构建命令均在 PowerShell 中执行） |
| 权限 | 非管理员会话；系统 UAC 为静默提权（ConsentPromptBehaviorAdmin=0），安装无需人工交互 |
| 构建产物目录 | `CARGO_TARGET_DIR=D:\cargo-target`（用户级环境变量，本次设置） |

---

## 2. 依赖安装记录（全部使用 winget，未换源；安装前已复核与 Stage 0 记录一致）

| # | 软件包 | winget ID / 版本 | 安装程序来源与 SHA256 | 结果 | 证据 |
|---|---|---|---|---|---|
| 1 | Rust 工具链（Rustup） | `Rustlang.Rustup` 1.29.1 | `static.rust-lang.org/rustup/archive/1.29.1/x86_64-pc-windows-msvc/rustup-init.exe`，SHA256 `6f4bef66…bdb7e` | **成功 EXIT=0**（17:47 完成） | `stage1-rustup-install.log` |
| 2 | VS 2022 Build Tools | `Microsoft.VisualStudio.2022.BuildTools` 17.14.41 | `download.visualstudio.microsoft.com/.../vs_BuildTools.exe`，SHA256 `37bb0fb4…fd6eeb` | **成功 EXIT=0**（17:54:34 完成） | `stage1-vsbuildtools-install.log` |
| 3 | FFmpeg / FFprobe | `Gyan.FFmpeg` 9.0.2（portable zip，GPL-3.0） | `github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-full_build.zip`，SHA256 `759d0a98…9206f6b` | **成功 EXIT=0**（17:57:38 完成） | `stage1-ffmpeg-install.log` |

安装选项：VS Build Tools 使用 `--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --includeRecommended`（不装无关工作负载；`--nocache` 节约 C 盘）。

### 2.1 安装后验证（实测输出）

**Rust 工具链**
- `rustc 1.99.0 (b940084d7 2026-09-28)`；`cargo 1.99.0 (5f94df478 2026-08-27)`；`rustup 1.29.1`
- `rustup show`：Default host `x86_64-pc-windows-msvc`；active/default toolchain `stable-x86_64-pc-windows-msvc`
- `rustup target list --installed`：`x86_64-pc-windows-msvc` ✓（符合 Gate-0A 对 MSVC target 的要求）

**MSVC / Windows SDK**（vswhere 与文件系统双重确认）
- 实例：`C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`（17.14.37710.0），`vswhere -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64` 可命中
- MSVC 工具集 `14.44.35207`：`cl.exe` 与 `link.exe` 存在于 `VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\`
- Windows SDK：Include/Lib 均为 `10.0.26100.0`；`MSBuild.exe`（`MSBuild\Current\Bin`）与 `vcvars64.bat` 存在

**FFmpeg / FFprobe**
- 实际路径：`C:\Users\宋舜江\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin\ffmpeg.exe`（同目录 `ffprobe.exe`）
- 版本：`ffmpeg version 9.0.2-full_build-www.gyan.dev`，built with gcc 16.2.0 (MSYS2)
- 许可证核查（configure flags 实测）：`--enable-gpl --enable-version3 --enable-libx264 --enable-libx265 --enable-libvpx --enable-libaom …（含 --enable-nvenc）`；**未出现 `--enable-nonfree`** → GPLv3 构建，与 winget 元数据标注一致
- SHA256：`ffmpeg.exe` = `589E50B766D251AFDF181DD664D40BD94407E200B019989FD7468C7D118A28D0`；`ffprobe.exe` = `02264DFA4F56BAAA31E443ECE8AA16D397F6B008200E7FD184D22B9009E75FD3`
- 证据：`stage1-ffmpeg-verify.log`；`winget list` 确认 FFmpeg 9.0.2 已安装

**关于 ffmpeg 命令 PATH 的说明（记录）**：winget 安装时已将 FFmpeg 的 bin 目录写入**用户 PATH**（实测值末尾含 `…Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin;`），且 Rustup 已将 `%USERPROFILE%\.cargo\bin` 写入用户 PATH。但**已在运行中的进程（如本会话）继承的是安装前的环境快照**，因此本次验证使用显式完整路径调用；新建进程（含 Stage 2 的应用与开发终端）可直接使用 `ffmpeg`/`ffprobe` 命令。winget 的 `WinGet\Links` 别名目录未生成 FFmpeg 别名（该目录为空）。

**npm 依赖（`npm install` 结果，27 个包，55 秒，保留 package-lock.json）**
@tauri-apps/api 2.12.2、@tauri-apps/cli 2.12.1、@tauri-apps/plugin-opener 2.7.0、react/react-dom 19.3.0、@types/react(-dom) 19.3.0、typescript 6.0.3、vite 8.3.4、@vitejs/plugin-react 6.1.2。Rust 侧依赖：`cargo fetch` 预热 EXIT=0，registry 缓存 623.1 MB / 25,418 文件；`src-tauri\Cargo.lock` 已生成。

**磁盘变化**：C: 21.9GB → 12.03GB（VS BuildTools 与各类缓存）；D: 135.1GB → 132.12GB（构建产物与缓存）。

---

## 3. Gate-0A：Rust 工具链与 MSVC 链接验证 —— **PASS**

- 测试工程：`C:\Users\宋舜江\AppData\Local\Temp\clipforge-gate0a`（`cargo new --vcs none` 生成，独立临时目录，未触碰既有文件）

| 步骤 | 命令 | 退出码 | 耗时 | 结果 |
|---|---|---|---|---|
| 编译+链接 | `cargo build`（cwd=测试工程，CARGO_TARGET_DIR=D:\cargo-target） | **0** | 1.37s | `Finished dev profile` |
| 运行 | `cargo run` | **0** | 0.01s | 标准输出 `Hello, world!` |
| 产物 | `D:\cargo-target\debug\clipforge-gate0a.exe`（134,656 B） | — | — | 存在且可执行；MSVC 链接实际发生（Rust windows-msvc 目标必须经 link.exe 链接才能产出该 EXE） |

- 工具链版本：rustc/cargo 1.99.0（见 §2.1）；工程位于中文用户名路径下，编译、链接、执行全部成功。
- 证据：`stage1-gate0a.log`。

---

## 4. Gate-0B：Tauri 2 + React + TS 桌面骨架 —— **PASS**

### 4.1 骨架与依赖
- `npm create tauri-app@latest clipforge -- --template react-ts --manager npm --identifier com.clipforge.app --tauri-version 2 --yes` → **EXIT=0**（create-tauri-app 4.7.5；生成 `D:\应聘项目zcode\clipforge`，未散落文件到工作区根目录）
- `npm install` → **EXIT=0**，27 包 / 55s，`package-lock.json` 已生成（见 §2.1 版本清单）
- `cargo fetch` → **EXIT=0**（首次尝试因我方命令未前置 `%USERPROFILE%\.cargo\bin` 失败，属操作失误、无副作用；重跑成功，详见决策日志 D-0007）
- 未实现任何视频业务功能；未创建 Git 仓库、未提交、未推送（符合阶段约束）

### 4.2 首次启动（run1）时间线与窗口验证

| 事件 | 时间戳 | 说明 |
|---|---|---|
| `npm run tauri dev` 启动 | 17:56:37.93 | Vite v8.3.4 ready in 517ms |
| cargo 编译完成 | ≈17:58:58 | `Finished dev profile in 2m 20s`（346 个编译单元） |
| 应用进程启动 | 17:59:04.90 | `Running D:\cargo-target\debug\clipforge.exe`（12,757,504 B） |
| 窗口属性检查 | 17:59:56.42 | PID 2096；标题 `clipforge`；`Responding=True`；可见；位置 (64,64)-(1082,861)（1018×797，对应 800×600 逻辑尺寸 ×125% DPI） |
| UIA 交互 | ≈18:00:xx | UI Automation 找到并 Invoke 了 `Greet` 按钮（该按钮经 Tauri IPC 调用 Rust 命令） |
| 交互结果截图 | ≈18:00:xx | 窗口显示 `Hello, ! You've been greeted from Rust!` —— 证明窗口真实响应且 **React→Rust IPC 往返成功**（输入框文字未设置成功的原因：WebView2 的 input 未以 Edit 控件类型暴露给 UIA；不影响 IPC 证据） |
| 关闭（CloseMainWindow） | 18:01:23.97 | 返回 True |
| 全链路退出 | 18:01:25.12 | `== tauri dev EXITED`（≈1.15s；npm/cargo/vite/应用进程全部退出） |
| 残留检查 | 18:01:27 | clipforge 相关进程 0 个；端口 1420 未监听 |

窗口证据文件：
- `gate0b-window-run1-front.png`（置前后屏幕捕获，含桌面任务栏环境）
- `gate0b-window-run1-print.png`（PrintWindow 窗口内容捕获）
- `gate0b-window-run1-greet.png`（IPC 交互后结果）
- `gate0b-window-run1.png` —— **首次抓屏作废**：窗口当时位于 ZCode 窗口之后，屏幕捕获区域内容被遮挡（未采用，保留记录）；已改用"置前 + PrintWindow"方式重新取证。

### 4.3 重新启动（run2）验证

| 事件 | 时间戳 | 说明 |
|---|---|---|
| `npm run tauri dev` 重启 | 18:01:47.70 | Vite ready in 312ms；cargo 增量 `Finished in 0.70s`（无重编译） |
| 应用进程启动 | 18:01:53.22 | 重启总耗时 ≈5.5s |
| 窗口属性检查 | ≈18:01:55 | PID 23352；标题 `clipforge`；`Responding=True`；截图 `gate0b-window-run2.png` |
| 关闭（CloseMainWindow） | 18:03:04.67 | 返回 True |
| 全链路退出 | 18:03:05.82 | `== tauri dev RUN2 EXITED`（≈1.15s） |
| 残留检查 | 18:03:07 | clipforge 相关进程 0 个；端口 1420 未监听 |

**检查方法更正说明**：run2 关闭时，我的检查脚本一度输出 `process_exited=False`。经核对 dev2 日志时间戳，实际退出发生在关闭后约 1.15 秒——该 `False` 是检查脚本缺陷（Wait-Process 在特定时序下提前返回，随即读取到正在退出的进程），**非应用行为问题**。以日志时间戳与残留检查为准：两轮关闭均干净、快速。

---

## 5. Gate-0C：FFmpeg / FFprobe 基础验证 —— **PASS**

工作目录：`C:\Users\宋舜江\AppData\Local\Temp\clipforge-gate0c`（位于中文用户名路径下）。样片由 FFmpeg `testsrc2` + `sine` 生成，未使用外部素材。

| 步骤 | 命令（要点） | 退出码 | 结果与数据 |
|---|---|---|---|
| 1. 生成样片 | `ffmpeg -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440 -t 5 -c:v mpeg4 -c:a aac sample_src.mkv` | **0** | 产出 `sample_src.mkv` 1,236,377 B（5.023s，640×360，mpeg4+aac） |
| 2. ffprobe 读取源 | `ffprobe -print_format json -show_format -show_streams` | **0** | JSON 确认 codec mpeg4/aac、640×360、duration 5.023、容器 `matroska,webm` |
| 3. 真实转换为 MP4 | `ffmpeg -i sample_src.mkv -c:v libx264 -crf 23 -preset veryfast -pix_fmt yuv420p -c:a aac -movflags +faststart out_mp4.mp4` | **0** | 耗时 0.2s；产出 `out_mp4.mp4` 528,501 B；SHA256 `04156286BBCC67FC8828E54961A8DDCDD0A43CE44CD792AEC716C5639129C953` |
| 4a. ffprobe 复核输出 | 同步骤 2 | **0** | codec **h264** + aac、640×360、duration 5.0155、容器 `mov,mp4,m4a,3gp,3g2,mj2` |
| 4b. 完整解码验证 | `ffmpeg -v error -i out_mp4.mp4 -f null -` | **0** | 无任何错误输出 = 全片可完整解码（解码级验证；未使用播放器 UI 播放） |
| 5.（附加）中文+空格路径 | 输出至 `测试 目录\输出 视频.mp4`，命令同上（crf 28/ultrafast） | **0** | 产出 935,946 B；ffprobe 复核 EXIT=0 |

- 版本 / SHA256 / 许可证：见 §2.1（GPL-3.0，含 libx264；独立进程调用）。
- 证据：`stage1-gate0c.log`；媒体产物已归档 `docs/evidence/gate0c-media/`。
- 说明：本验证仅证明工具链可用，**不代表 ClipForge 业务转换功能完成**（业务功能按范围约束尚未实现）。

---

## 6. 未执行项（如实记录）

| 项 | 原因 |
|---|---|
| `npm run tauri build`（release 构建 / NSIS 打包） | Stage 1 范围不含；计划 Stage 3 执行（届时验证打包后目标环境运行） |
| ClipForge 业务功能（导入/元数据/缩略图/转换/队列/取消等） | 按阶段约束"不得提前实现完整视频转换功能" |
| 业务测试用例 TC-01…TC-14 | 待 Stage 2+（用例定义见 `stage-0-audit.md` §6） |
| Git 仓库初始化 / 提交 / 推送 | 本阶段明确禁止 |
| 干净目标机（无 VC++/WebView2 环境）依赖验证 | 计划随 Stage 3 打包验证执行 |
| 磁盘不足 / 损坏文件 / 取消转换等异常路径 | 属业务功能测试范围（Stage 2+） |

---

## 7. Gate 结论汇总

| Gate | 内容 | 结论 | 关键证据 |
|---|---|---|---|
| Gate-0A | Rust + MSVC target 编译链接执行 | **PASS** | `stage1-gate0a.log`（build/run EXIT=0，Hello, world!） |
| Gate-0B | Tauri 2 桌面窗口：显示/响应/关闭/重启 | **PASS** | 4 张窗口截图、2 份 dev 日志、UIA 交互（IPC）证据 |
| Gate-0C | FFmpeg 生成/读取/转换/解码 | **PASS** | `stage1-gate0c.log`、媒体产物、版本/哈希/许可证记录 |

**Stage 1 总结论：PASS**（三项 Gate 全部满足验收条件；均为实测，无未执行项冒充通过）。

# Stage 4 Delivery Report（交付包装：产品化定稿、NSIS 打包与安装验收）

- 日期：2026-10-11（深夜）～ 2026-10-12（凌晨）
- 阶段：Stage 4 —— 交付包装（用户指令："改成 ClipForge，图标要有特色的 / 继续"）
- 依据：D-0029；笔试题第 5/6/7 条（GitHub 提交、客户端选型、给人用且自己测过）
- **判定：打包与安装验收 PASS（2 轮迭代后全绿）；GitHub 推送待用户凭据（本报告记录到"本地交付就绪"为止）**

---

## 1. 本阶段目标与范围

用户就"笔试题未要求打包，打包是加分项还是减分项"征询判断，结论与范围确认如下：

1. **打包是加分项**：直接命中第 7 条（审核人"双击安装即用"，而非先装 Node+Rust 自行构建）与第 6 条（可安装的 Windows 客户端是最硬的"客户端关联"证据）；不改任何业务功能。
2. **前提约束**：不得挤占第 5 条（GitHub 提交）时间；打包前仅允许"交付外观"配置级改动，改后必须回归。
3. **本阶段范围**：产品名/标题/图标/窗口定稿 → NSIS 打包 → 安装/启动/核心链路/中文路径/卸载验收 → 回归与加固 → 入库裁剪 → 交付文档（README/截图/Demo GIF）。

## 2. 修改文件清单（含哈希与原因）

| 文件 | 状态 | SHA256(前 16) | 原因 |
|---|---|---|---|
| `src-tauri/tauri.conf.json` | 修改 | `5f53d8e8f87d2519` | `productName`: clipforge→**ClipForge**；`mainBinaryName`: **ClipForge**（安装后主程序名一致，第二轮修正）；窗口标题→ClipForge、尺寸 1024×720（min 900×600）；`bundle.publisher`: **ClipForge**（"应用和功能"发布者，第二轮修正）；`identifier` 不变（日志目录不受影响） |
| `src-tauri/icons/**`（17 个文件全量重生成） | 修改 | `icon.ico 349bf6da67bef7d7`、`32x32 f18f42a92cc6a803`、`128x128 9ae9125bae37b176`、`128x128@2x 1111734b4df8dc86`、`icon.icns 30d5ef4f56cfb1ff` | 特色图标全套（见 §3） |
| `index.html` | 修改 | `47a224f88e817b93` | `<title>` 模板默认→**ClipForge**（D-0028 登记的范围外观察）；favicon→`/icon.png` |
| `public/icon.png` | 新增 | `383c2cc76c5e62ac` | 图标源图（1024）供 favicon；删除无引用的 `public/tauri.svg`、`public/vite.svg` |
| `.gitignore`（仓库根） | 新增 | — | 入库裁剪（§7） |
| `LICENSE` | 新增 | — | MIT（公开仓库交付用） |
| `README.md`（仓库根，主） | 重写 | — | 交付说明：审核人 30 秒看懂（安装即用/截图/Demo GIF/功能/架构/测试/文档索引） |
| `clipforge/README.md` | 重写 | — | 简化为源码目录说明 + 指向根 README |

**未动核心文件复核：16 个受约束文件（`converter.rs`/`thumbnail.rs`/`probe.rs`/`import.rs`/`picker.rs`/`probe_lifecycle.rs`/`logging.rs`/`lib.rs`/`main.rs`/`importApi.ts`/`App.css`/`Cargo.toml`/`Cargo.lock`/`package.json`/`package-lock.json`/`capabilities/default.json`）哈希与 Stage 3C 冻结基线**逐项一致（16/16）**。App.tsx 为 D-0028 已批准的 1 行文案改动（`45a7416cf295b6c8`）。

## 3. 图标与产品化定稿

**设计（"特色"取舍）**：靛蓝→青对角渐变圆角方块（客户端底色）+ 白色胶片画框（顶/底齿孔，打穿露底）+ 金→橙渐变播放三角（圆角顶点 + 柔和投影）。三元素对应"视频 / 剪辑 / 转换"，在 16–32 px 级别仍可辨识。

- 生成脚本：`docs/evidence/stage4/stage4-make-icon.py`（Pillow，**仅生成期使用、不进产品依赖**；1024 源图 `clipforge-icon-1024.png`）
- 全套平台图标：`npx tauri icon`（日志 `stage4-tauri-icon.log`）；删除其顺带生成的 `icons/android`、`icons/ios`（桌面交付无关）
- 窗口/任务栏/安装包/快捷方式/标题栏均已换新图标（见截图与安装体核对）

## 4. 打包（含一次真实失败与修复）

| 项 | 结果 |
|---|---|
| 命令 | `npm run tauri build -- --bundles nsis`（`bundle.targets` 配置保持 `"all"` 不动，用 CLI 参数限定本轮产物） |
| release 编译 | **3m06s**，产物 `D:\cargo-target\release\ClipForge.exe` |
| **失败与修复** | 首次打包在 bundling 阶段失败：`failed to bundle project: timeout: global` —— **NSIS 工具包从 GitHub Release 下载被网络阻断**（curl 实测 HTTP=000）。修复：使用 tauri-bundler 官方镜像开关 `TAURI_BUNDLER_TOOLS_GITHUB_MIRROR=https://gh-proxy.com` 重试（日志可见下载 URL 已改写）；**下载物 SHA1 与 bundler 内置校验值 `EF7FF767E5CBD9EDD22ADD3A32C9B8F4500BB10D` 完全一致**（`validating hash` 通过），完整性未降级。证据：`stage4-tauri-build.log`（失败）、`stage4-tauri-build2/3-*.log`（成功） |
| 最终安装包 | `ClipForge_0.1.0_x64-setup.exe` **1,645,833 B**，SHA256 `5B14DC7A884F2BDBC5C9EBE94930C6F3B6CEA84A110E05857BA2E966C1FDAB9F` |
| release 加固复核 | release 二进制中 `CLIPFORGE_TEST` 字符串出现 **0 次**（D-0023 承诺的"测试覆盖仅 Debug 存在"在打包产物上再次成立） |

## 5. 安装验收（两轮，全流程真实 UI 驱动）

**第一轮（`stage4-acceptance.ps1`，日志 `stage4-acceptance.log`）**：
- 通过：静默安装、安装体核对（目录/注册表/开始菜单+桌面快捷方式/VersionInfo）、窗口就绪（`name=[ClipForge] class=[Tauri Window]`）、**AVI→WebM 真实转换**（`sample_converted_2.webm` 31,157 B，ffprobe vp8+vorbis）、干净关闭（残留进程 0、`shutdown cleanup … remaining=0`）、静默卸载（目录/注册表/快捷方式全部删除）。
- **失败（如实记录）**：T7（中文特殊路径）步骤——文件对话框的路径注入 `SetValue` **报成功但未被对话框采用**，导致误导入了对话框记忆的桌面旧文件；且脚本未在该步骤中止（`wait-entry` 已报 FAIL 但流程继续）。副产物（桌面文件夹内 1 个转换输出，470,796 B）已记录哈希后删除，用户原文件未动。
- 修正：helper 升级 v2 —— ①路径注入后**核验编辑框实际值**，不通过则回退"点击+全选+剪贴板粘贴"再核验（仍不过即抛错中止）；②去掉会干扰对话框的盲点击；③新增 `wait-path` 动作，**导入后断言界面出现完整目标路径**；④验收脚本任何 helper 非零退出即中止。

**第二轮（`stage4-smoke-t7.ps1`，日志 `stage4-smoke-t7.log`）—— 全绿**：

| 检查项 | 结果 |
|---|---|
| 静默安装 | 退出码 0；`ClipForge.exe` 4,930,048 B；VersionInfo `ProductName=ClipForge` / `CompanyName=ClipForge` / `0.1.0` |
| 注册表 | `DisplayName=ClipForge`、`Publisher=ClipForge`、`MainBinaryName=ClipForge.exe`、InstallLocation/UninstallString 正确 |
| 启动 | 窗口就绪 `name=[ClipForge]` |
| **T7 中文特殊路径导入** | `setvia=ValuePattern+verified`；**界面断言通过**：条目显示 `…\测试 & 视频 #1 (终版)'s\sample.mp4`（532.41 KiB / 00:05 / 640×360 / H.264 / AAC） |
| 缩略图 | `视频缩略图` 渲染（真实帧） |
| MP4 转换 | `已输出 MP4（490 KB）`；输出 `sample_converted_6.mp4` **501,946 B**（与历史确定性基线一致）；ffprobe `h264 + aac / 5.000s` |
| 关闭与生命周期 | 进程退出、clipforge/ffmpeg/ffprobe 残留 **0**；应用日志 `shutdown cleanup cancelled=0 reaped=0 remaining=0` |
| 静默卸载 | 退出码 0；安装目录、注册表项、快捷方式**全部删除** |

**截图（release 版实机，`docs/evidence/stage4/`）**：`stage4-release-main.png`（T7 条目：元数据+缩略图）、`stage4-release-converted.png`（已输出 MP4）、`stage4-release-webm.png`（并行条目 WebM 完成态）、`stage4-demo.gif`（**Demo 动图**：真实素材 Big Buck Bunny 720p HEVC → 元数据 → 缩略图 → **HEVC→H.264 转换 "已输出 MP4（1914 KB）"**，24s 实时，136 KB）。

GIF 方法说明：逐帧 `PrintWindow(PW_RENDERFULLCONTENT)` 抓应用窗口（不受遮挡影响，延续 D-0012/D-0028 方法学）；文件对话框为独立顶层窗口（`#32770`），每帧单独抓取后**按其偏移钳制合成**进帧（钳制仅用于展示，不用于测量）。脚本：`stage4-gif-capture.ps1` + `stage4-gif.ps1`。

## 6. 环境事实与偏差记录

1. **项目根目录已变更**：历史文档记录的 `D:\应聘项目zcode` 已不存在，当前工作区为 **`D:\Cliporge`**（`clipforge/` + `docs/` + `test-assets/`）。历史证据中的旧路径为当时记录，不回改；本阶段新增脚本一律使用新路径。
2. 首轮误导入副产物已清理（见 §5）；桌面用户原文件（3 个）未触碰。
3. 应用数据路径未变：`identifier` 保持 `com.clipforge.app`，日志仍写入 `%LOCALAPPDATA%\com.clipforge.app\logs\clipforge.log`（D-0020 不受影响）。

## 7. 入库裁剪（`.gitignore`）

原则：源码、文档、证据（日志/截图）、生成脚本全部入库；体积大且可由已入库脚本或公开链接复现的媒体与构建产物不入库。

- 排除：`clipforge/node_modules/`、`clipforge/dist/`、`**/target/`、`docs/evidence/stage2/test-assets/`（约 532 MB）、`test-assets/stage3c/`、`test-assets/real-world/*.{mp4,webm,mkv,mov,avi}`（约 196 MB）。
- **入库实测：363 个文件 / 9.3 MB**（最大单文件 1.2 MB），含 `docs/` 全量文档与证据链。

## 8. 交付物

| 交付物 | 位置/说明 |
|---|---|
| 安装包 | `D:\cargo-target\release\bundle\nsis\ClipForge_0.1.0_x64-setup.exe`（1.57 MiB，未签名——首次运行有 SmartScreen"未知发布者"提示，README 已说明） |
| README | `clipforge/README.md`（重写：功能、安装即用、截图/GIF、架构、测试与文档索引） |
| LICENSE | 仓库根 MIT |
| 会话总结 | `docs/ai-session-summary.md`（本阶段补齐 Stage 2/3/4 会话，含 AI 失误与更正记录——对应笔试题第 4 条） |
| 决策日志 | `docs/decision-log.md` D-0001~D-0029 |
| 证据 | `docs/evidence/stage4/`（图标脚本与日志、构建日志、安装验收日志×2、GIF 脚本与日志、截图、GIF） |

## 9. 遗留事项（如实）

1. **GitHub 推送待执行**：本机无 `gh` CLI、无 SSH key、无凭据 helper——`git init` 与入库裁剪已完成（main 分支待首次提交），远程仓库创建与推送需用户提供凭据（或用户自行执行两条命令）。
2. **安装包未签名**：SmartScreen 首启提示为预期现象（用自签名证书同样会提示，正式代码签名需购买证书，超出本项目范围）。
3. **WebM 编码耗时**（3C 遗留）：VP8 约为 x264 的 5 倍；README 已提示长视频转 WebM 需耐心等待（默认超时 300s 内）。
4. **MSI 未产出**：本轮仅 NSIS（指定 `--bundles nsis`）；如后续需要 MSI 需引入 WiX 工具链（且同样面临 GitHub 下载问题，可用同一镜像开关）。
5. **`CONV_TIMEOUT`/`CONV_CANCELLED` 未实机触发**（3C 遗留，未变）。

## 10. 交付就绪判定

| 判定项 | 结果 |
|---|---|
| □ 产品化定稿（名称/标题/图标/窗口/发布者） | ✅ 第二轮安装体核对全部一致 |
| □ release 构建成功且加固复核通过 | ✅ 3m06s；测试字符串 0 次出现 |
| □ NSIS 安装包产出（含下载阻断的修复） | ✅ SHA256 `5B14DC7A…`，工具链镜像下载 SHA1 校验一致 |
| □ 安装 → 启动 → 核心链路（含中文路径）→ 关闭 → 卸载 | ✅ 第二轮全绿（含输出二次 ffprobe 核验） |
| □ 回归不下降 | ✅ `cargo test` 65/0/7 EXIT=0；`npm run build` EXIT=0 |
| □ 核心源码零改动 | ✅ 16/16 哈希与 3C 基线一致 |
| □ 交付文档齐备（README/截图/GIF/会话总结/决策日志） | ✅ |
| □ 仓库本地就绪（git init + 裁剪 + 提交内容 ≤10 MB） | ✅ 363 文件 / 9.3 MB |
| □ GitHub 远程推送 | ⏳ **待用户凭据** |

**判定：本地交付就绪（PASS）。** 剩余唯一动作是创建远程仓库并推送（+ 在 Releases 挂安装包），阻塞点为外部凭据，非技术问题。

# Stage 3C 基线检查（Baseline Check）

- 日期：2026-10-11
- 阶段：Stage 3C —— 真实多格式视频转换兼容性验收
- 依据：Stage 3B Implementation Report（Gate-3B PASS）+ 用户 Stage 3C 授权
- **结论：基线检查通过（PASS），允许开工。**

---

## 1. Git 工作区状态

```
$ git status   (D:\应聘项目zcode)
fatal: not a git repository (or any of the parent directories): .git
```

**结论：本项目自 Stage 0 起即为**非 Git 仓库**（无 `.git` 目录，`D:\应聘项目zcode` 与 `D:\应聘项目zcode\clipforge` 均非仓库）。因此不存在"工作区脏/净"概念，改动追踪完全依赖**文件哈希比对**（与 Stage 1..3B 一贯做法一致）。如实记录，不冒充已纳入版本控制。**

## 2. Stage 3B 冻结基线哈希核验

对照 Stage 3B Implementation Report 所载哈希（前 16 位）：

| 文件 | 3B 报告哈希（前16） | 3C 开工实测 | 结论 |
|---|---|---|---|
| `src-tauri/src/converter.rs` | `8d8f0d44b2592149` | `8d8f0d44b2592149` | **一致** |
| `src-tauri/src/thumbnail.rs` | `8ebd21c7e5cc0f39` | `8ebd21c7e5cc0f39` | **一致** |
| `src-tauri/src/probe.rs` | `bee57a7c…` | `bee57a7c8e160556` | **一致** |
| `src-tauri/src/import.rs` | `ee4d3d9b…` | `ee4d3d9bd3996c10` | **一致** |
| `src-tauri/src/picker.rs` | `789a1387…` | `789a1387ba592a78` | **一致** |
| `src-tauri/src/probe_lifecycle.rs` | `c231c2be…` | `c231c2bed3713a50` | **一致** |
| `src-tauri/src/logging.rs` | `b5c92f9f…` | `b5c92f9fae3d818e` | **一致** |
| `src-tauri/src/lib.rs` | `a9bf518b930c1d53` | `a9bf518b930c1d53` | **一致** |
| `src/App.tsx` | `f9b9845494cb4d0a` | `f9b9845494cb4d0a` | **一致** |
| `src/importApi.ts` | `9b1b39db9c19791f` | `9b1b39db9c19791f` | **一致** |
| `src/App.css` | `238a9fc71e846291` | `238a9fc71e846291` | **一致** |
| `src-tauri/Cargo.toml` | 冻结（Stage 2D Final） | `10cc68559711c143` | **一致** |
| `src-tauri/Cargo.lock` | 冻结 | `f5bd42fbe1d145b5` | **一致** |
| `package.json` | 冻结 | `6aafd96da0f055f2` | **一致** |
| `package-lock.json` | 冻结 | `f14f03cf4a66ed67` | **一致** |
| `src-tauri/capabilities/default.json` | 冻结 | `f4e450983bbc94f2` | **一致** |
| `src-tauri/tauri.conf.json` | 冻结 | `bb6dc6fb736a3a18` | **一致** |

**结论：Stage 3B 结束时点冻结的 18 个文件在 Stage 3C 开工前零漂移；`converter.rs`/`thumbnail.rs`/`probe.rs` 等核心文件与 3B 报告记录完全一致，未被任何后续操作改动。**

（完整日志：`docs/evidence/stage3/3c/stage3c-baseline.log` §2）

## 3. 运行环境洁净度

| 检查项 | 命令 | 结果 | 结论 |
|---|---|---|---|
| ClipForge 残留进程 | `Get-Process -Name clipforge` | count=0 | 无残留 |
| FFmpeg 残留进程 | `Get-Process -Name ffmpeg` | count=0 | 无残留 |
| FFprobe 残留进程 | `Get-Process -Name ffprobe` | count=0 | 无残留 |
| Node（dev server）残留 | `Get-Process -Name node` | count=0 | 无残留 |
| 端口 1420（Vite dev） | `netstat -ano \| Select-String ':1420\|:9333'` | listening_count=0 | 端口空闲 |
| 端口 9333（CDP 调试口） | 同上 | listening_count=0 | 端口空闲 |
| `CLIPFORGE_*` 测试环境变量 | `Get-ChildItem env:` 过滤 | count=0 | **测试环境变量为空** |

**结论：无进程残留、无端口残留、测试环境变量为空——满足 Stage 3C "干净起点" 要求。**

（完整日志：`stage3c-baseline.log` §3/§4/§5）

## 4. 外部依赖（FFmpeg）可用性

| 项 | 值 |
|---|---|
| ffmpeg | `C:\Users\宋舜江\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin\ffmpeg.exe` |
| ffprobe | 同目录 `ffprobe.exe` |
| 版本 | `ffmpeg version 9.0.2-full_build-www.gyan.dev` |
| 关键编码器 | `libx264`（h264）/ `libvpx`（VP8）/ `libvorbis` / `aac` —— `ffmpeg -encoders` 实测全部存在 |

**结论：MP4（libx264+aac）与 WebM（libvpx+libvorbis）两条预设路径所需编码器在真实 FFmpeg 构建中均存在——WebM 实机验证的**外部前置条件成立**。**

（完整日志：`stage3c-baseline.log` §6）

## 5. 构建/测试基线（用于 Gate-3C "不下降" 比对）

| 命令 | 退出码 | 结果 |
|---|---|---|
| `cargo test`（`src-tauri/`） | **EXIT=0** | **65 passed / 0 failed / 7 ignored** |
| `npm run build`（`clipforge/`） | **EXIT=0** | tsc + vite 构建通过（19 modules） |

（日志：`stage3c-baseline-cargo-test.log`、`stage3c-baseline-npm-build.log`）

## 6. 基线检查判定

| 检查项 | 判定 |
|---|---|
| ① Git 工作区状态已记录 | ✅（非仓库，如实记录） |
| ② Stage 3B 关键源码哈希核验一致 | ✅ 18/18 |
| ③ `converter.rs` 等核心文件未变化 | ✅ |
| ④ 无 ClipForge 残留进程 | ✅ |
| ⑤ 无端口残留 | ✅ |
| ⑥ 测试环境变量为空 | ✅ |
| ⑦ 依赖（FFmpeg 编码器）可用 | ✅ |

**判定：PASS —— 允许进入 Step 1（测试素材准备）。**

**本阶段约束（自授权书，全阶段有效）：** 不修改 `converter.rs` / `thumbnail.rs` / `probe.rs` / UI / FFmpeg 参数预设；不新增依赖；不扩展功能；不进入 GitHub 交付阶段。测试素材与证据文件均在 `test-assets/`、`docs/` 下新增，不触碰产品源码。

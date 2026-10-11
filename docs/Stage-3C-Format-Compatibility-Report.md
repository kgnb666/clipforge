# Stage 3C Format Compatibility Report（真实多格式视频转换兼容性验收）

- 日期：2026-10-11
- 阶段：Stage 3C —— 真实多格式视频转换兼容性验收（授权范围：仅测试，不改代码）
- 依据：用户 Stage 3C 授权书 + `docs/Stage-3C-Baseline-Check.md`（基线 PASS）
- **Gate-3C 判定：PASS**（判定依据见 §9）

---

## 1. 测试环境

| 项 | 值 |
|---|---|
| 操作系统 | Windows 10.0.19045 x64（win32） |
| 被测应用 | ClipForge（Tauri 2 + React 19 + TS），**dev 构建**：`npm run tauri dev`（Vite 8.3.4 + `cargo run --no-default-features`，debug profile） |
| 应用二进制 | `D:\cargo-target\debug\clipforge.exe` |
| FFmpeg / FFprobe | Gyan **ffmpeg 9.0.2-full_build**（`…\WinGet\Packages\Gyan.FFmpeg_…\ffmpeg-9.0.2-full_build\bin\`）；`libx264 / libvpx / libvorbis / aac` 编码器实测均存在 |
| 仓库状态 | **非 Git 仓库**（无 `.git`）；改动追踪依赖 SHA256 哈希比对 |
| 测试起点洁净度 | 开工时：clipforge/ffmpeg/ffprobe/node 进程均 0，端口 1420/9333 无监听，`CLIPFORGE_*` 环境变量为 0 —— 见 `stage3c-baseline.log` §3/§4/§5 |
| 驱动方式 | Windows UI Automation（`stage3c-ui-helper.ps1`）驱动**真实 UI 元素**：导入按钮 → 系统文件对话框 → 转换按钮（MP4/WebM）；**全程未调用任何 Tauri IPC / 转换 API** |
| 受控测试环境变量 | **未使用**（`CLIPFORGE_TEST_CONV_TIMEOUT_MS` 等，全阶段为空 → 转换超时为生产默认 300s） |

**测试形态说明：** 由于 UI 在转换完成后只提供"重新转换"（同格式）按钮，且同一路径重复导入会命中判重（P2A-007），本轮验收按 **4 个独立 dev 会话**组织，每个用例从"导入 → 元数据 → 缩略图 → 点击转换 → 等待结论 → 读文本/截图 → 核对输出文件"完整走一遍真实用户流程。

## 2. 测试素材列表（`test-assets/stage3c/`）

生成脚本：`docs/evidence/stage3/3c/stage3c-make-assets.ps1`（日志：`stage3c-asset-creation.log`）。素材全部由 FFmpeg lavfi 合成（`testsrc2`/`testsrc`/`smptebars` 等测试图案 + `sine` 音频），不引入第三方媒体文件。

| 用例 | 文件（相对 `test-assets/stage3c/`） | 大小 (B) | SHA256（前 16） | mtime | ffprobe 特征 |
|---|---|---|---|---|---|
| T1 | `sample.mp4` | 545,189 | `0e401a5aae76e2a1` | 2026-10-11T21:51:03.849+08:00 | mp4 / h264 + aac / 5.000s / 640×360 |
| T2 | （复用 T1 的 `sample.mp4`） | — | — | — | 同上 |
| T3 | `sample.mkv` | 69,562 | `79a0744184a0c7e7` | 2026-10-11T21:51:03.986+08:00 | matroska / h264 + aac / 4.023s / 640×360 |
| T4 | `sample.mov` | 73,000 | `d08eb9c3fcd2f1cf` | 2026-10-11T21:51:04.156+08:00 | mov / h264 + aac / 3.000s / 640×360 |
| T5 | `sample.avi` | 145,884 | `bf2f5e486cfa97a6` | 2026-10-11T21:51:04.237+08:00 | avi / **mpeg4 + mp3** / 3.040s / 640×360 / 25fps |
| T6 | `no_audio.mp4` | 276,158 | `64f840078d128087` | 2026-10-11T21:51:04.371+08:00 | mp4 / h264，**无音频流** / 3.000s |
| T7 | `测试 & 视频 #1 (终版)'s\sample.mp4` | 545,189 | `0e401a5aae76e2a1` | 2026-10-11T21:51:03.849+08:00 | mp4 / h264 + aac / 5.000s（= T1 内容，特殊路径） |
| T8 | `truncated.mp4` | 33,937 | `4c459506e71c6887` | 2026-10-11T21:51:04.579+08:00 | **ffprobe_exit=1：`moov atom not found`**（完整文件前 30% 字节） |
| T8b | `corrupt_mdat.mp4` | 3,486 | `3b6ce1df6a6dbd08` | 2026-10-11T21:51:04.751+08:00 | **ffprobe_exit=0**（元数据可读：3.40 KiB / 4.000s / 320×180 / h264+aac）+ stderr `stream 0, offset 0xdae: partial file` |

**T7 路径字符覆盖：** 中文（`测试`/`视频`/`终版`）+ 空格 + `&` + `#` + `'` + 括号 —— 五类特殊字符全部落在同一路径上。

**T8/T8b 的设计说明（重要）：** 授权书要求 T8 的最终判定为 `CONV_NONZERO_EXIT`，但代码存在**元数据前置门**（`convert_video`：条目需导入校验通过 **且** 元数据解析成功，否则在进入 FFmpeg 之前即拒绝）。因此：
- `truncated.mp4`（moov 丢失 → ffprobe 非零退出）**无法到达转换阶段**，其正确行为是"元数据门拦截"（见 §6 T8）；
- 为真实验证 `CONV_NONZERO_EXIT`，额外构造 `corrupt_mdat.mp4`：**保留 ftyp+moov、切除全部 mdat 媒体数据**，使容器元数据可读（ffprobe exit=0）而媒体不可解码 —— 该样品成功进入转换并触发 `CONV_NONZERO_EXIT`（见 §6 T8b）。

**T8b 行为预核验（素材准备期，非产品调用）：** `ffmpeg -v error -i corrupt_mdat.mp4 -f null -` → `ffmpeg_exit=-1094995529`（`AVERROR_INVALIDDATA`，即 FFmpeg 的 `FFERRTAG('I','N','D','A')`），stderr：`stream 0, offset 0xdae: partial file` / `Cannot determine format of input 0:0 after EOF`。

## 3. 每个格式结果（真实客户端实测）

触发链路（每个用例均相同，全部经真实 UI）：**导入视频（系统对话框）→ 元数据加载 → 缩略图渲染 → 点击 MP4/WebM → 等待结论 → 核对输出**。

| 用例 | 输入 → 目标 | UI 结论（界面文本） | 输出文件 | 输出大小 (B) | 转换耗时 | 判定 |
|---|---|---|---|---|---|---|
| **T1** | MP4 → MP4 | `已输出 MP4（490 KB）` | `sample_converted.mp4` | 501,946 | 212 ms | **PASS** |
| **T2** | MP4 → **WebM** | `已输出 WEBM（633 KB）` | `sample_converted.webm` | 648,297 | 1,074 ms | **PASS** |
| **T3** | MKV → MP4 | `已输出 MP4（70 KB）` | `sample_converted_2.mp4` | 71,985 | 160 ms | **PASS** |
| **T4** | MOV → MP4 | `已输出 MP4（69 KB）` | `sample_converted_3.mp4` | 70,366 | 160 ms | **PASS** |
| **T5** | AVI → MP4 | `已输出 MP4（52 KB）` | `sample_converted_4.mp4` | 53,474 | 108 ms | **PASS** |
| **T6** | 无音轨 MP4 → MP4 | `已输出 MP4（243 KB）` | `no_audio_converted.mp4` | 249,292 | 159 ms | **PASS** |
| **T7** | 特殊路径 MP4 → MP4 | `已输出 MP4（490 KB）` | `测试 & 视频 #1 (终版)'s\sample_converted.mp4` | 501,946 | 212 ms | **PASS** |
| **T8** | 损坏（moov 丢失）→ MP4 | `转换失败：元数据解析失败（FFPROBE_NONZERO_EXIT），无法转换` | 无（未产生） | — | 未进入 FFmpeg | **PASS（错误处理）** |
| **T8b** | 损坏（媒体数据切除）→ MP4 | `转换失败（CONV_NONZERO_EXIT）：FFmpeg 以非零退出码结束（-1094995529）…` | 无（已清理） | — | 60 ms（快速失败） | **PASS（错误处理）** |

**耗时口径：** 应用日志 `conv start → conv complete/failed` 的墙钟差值（毫秒）。

**其他实测确认：**
- **缩略图**：T1~T7 全部渲染真实帧（截图可见 `testsrc2`/`smptebars` 图案）；T6（无音轨）正常渲染；T8b **不冒充**缩略图，显示 `缩略图生成失败（THUMB_NONZERO_EXIT）` + 原始原因。
- **输出冲突自动递增**：多份 `sample_converted.mp4` 已存在时，输出依次命名为 `_2`/`_3`/`_4`/`_5`…（实测至 `_8`），**不覆盖**已有文件、**不覆盖**源文件。
- **确定性复现**：相同输入在多轮转换中的输出字节大小完全一致（T1 三轮均 501,946 B；T3 两轮均 71,985 B；T5 两轮均 53,474 B；T6 两轮均 249,292 B），说明转码参数路径稳定。

### 3.1 Step 4 稳定性检查（单会话连续 6 次转换）

第 4 个 dev 会话中，按 `T1 → T3 → T4 → T5 → T6 → T7` 顺序**连续导入并转换 6 个不同格式素材**（每步均经"点击导入 → 等待元数据 → 点击 MP4 → 等待收敛"，无人工干预、无重启）。日志：`stage3c-stability.log`。

| 次序 | 输入 | 输出 | 耗时 (ms) | 转换后 ffmpeg 残留 | 转换后 ffprobe 残留 |
|---|---|---|---|---|---|
| 1 | `sample.mp4` | `sample_converted_5.mp4` (501,946 B) | 267 | 0 | 0 |
| 2 | `sample.mkv` | `sample_converted_6.mp4` (71,985 B) | 163 | 0 | 0 |
| 3 | `sample.mov` | `sample_converted_7.mp4` (70,366 B) | 160 | 0 | 0 |
| 4 | `sample.avi` | `sample_converted_8.mp4` (53,474 B) | 110 | 0 | 0 |
| 5 | `no_audio.mp4` | `no_audio_converted_2.mp4` (249,292 B) | 161 | 0 | 0 |
| 6 | 特殊路径 `sample.mp4` | `…(终版)'s\sample_converted_2.mp4` (501,946 B) | 212 | 0 | 0 |

| 稳定性检查项 | 结果 |
|---|---|
| 无死锁 | ✅ 6 次全部在 110~267 ms 内收敛；UI 每次 `wait-settled` 均返回"进行中=0"，无卡死 |
| 无残留 FFmpeg/FFprobe | ✅ 每次转换后进程计数均为 0（6/6） |
| 应用正常关闭 | ✅ `WindowPattern.Close` 后 `clipforge=0 / node=0 / 端口 1420 无监听`；应用日志 `shutdown cleanup cancelled=0 reaped=0 remaining=0 peak=1 elapsed_ms=0 errors=[]` |
| 日志完整 | ✅ 6 组 `conv register → conv start → conv complete` 事件齐全，与 UI 结论一一对应 |

（会话 2 中另有一次**更长的连续链路**：`T2(WebM) → T3 → T4 → T5 → T6 → T7 → T8(拒绝)` 共 7 次背靠背操作，同样无死锁、无残留，结束时 `remaining=0`。）

## 4. UI 截图索引（`docs/evidence/stage3/3c/`）

| 截图 | 内容（实测所见） |
|---|---|
| `stage3c-T1-before.png` | T1 导入完成：元数据（532.41 KiB / 00:05 / 640×360 / H.264 / AAC）+ 真实缩略图 + `转换 MP4 WebM` 按钮 |
| `stage3c-T1-done.png` | T1 转换完成：`已输出 MP4（490 KB）` + `重新转换` |
| `stage3c-T2-before.png` | T2 导入完成（同一 `sample.mp4`，新会话）：等待点击 WebM |
| **`stage3c-T2-done.png`** | **T2 WebM 完成：`已输出 WEBM（633 KB）` —— WebM 实机验证的核心 UI 证据** |
| `stage3c-T3-before.png` | T3 导入完成（`sample.mkv`：67.93 KiB / 00:04 / MPEG-4→H.264 / AAC） |
| `stage3c-T3-done.png` | T3 完成：`已输出 MP4（70 KB）`（同屏可见 T2 的 `已输出 WEBM（633 KB）`） |
| `stage3c-T4-before.png` / `stage3c-T4-done.png` | T4（`sample.mov`）转换前后 |
| `stage3c-T5-before.png` / `stage3c-T5-done.png` | T5（`sample.avi`，`MPEG-4 Video` + `MP3`）转换前后：`已输出 MP4（52 KB）` |
| `stage3c-T6-before.png` / `stage3c-T6-done.png` | T6（`no_audio.mp4`，音频编码 `无音轨`）转换前后：`已输出 MP4（243 KB）` |
| `stage3c-T7-before.png` / `stage3c-T7-done.png` | T7 特殊路径条目（界面显示 `D:\…\测试 & 视频 #1 (终版)'s\sample.mp4`）转换前后 |
| `stage3c-T8-before.png` | T8：元数据错误态 `元数据读取失败（FFPROBE_NONZERO_EXIT）…moov atom not found` + `重试`，**无缩略图冒充** |
| `stage3c-T8-after.png` | T8：点击 MP4 后顶部通知 `转换失败：元数据解析失败（FFPROBE_NONZERO_EXIT），无法转换`，条目仍可交互 |
| `stage3c-T8b-before.png` | T8b：元数据**成功**（3.40 KiB / 00:04 / 320×180 / H.264 / AAC）+ 缩略图失败原因 + `转换 MP4 WebM` 可用 |
| **`stage3c-T8b-after.png`** | **T8b：`转换失败（CONV_NONZERO_EXIT）：FFmpeg 以非零退出码结束（-1094995529）：… stream 0, offset 0xdae: partial file` + `重试` —— CONV_NONZERO_EXIT 原始原因的核心 UI 证据** |
| `stage3c-stability-final.png` | Step 4 连续 6 次转换后的界面：多条目并存，末两条为 `no_audio.mp4`→`已输出 MP4（243 KB）` 与特殊路径 →`已输出 MP4（490 KB）` |

## 5. ffprobe 验证结果

**日志：`docs/evidence/stage3/3c/ffprobe-crosscheck.log`**（脚本 `stage3c-ffprobe-crosscheck.ps1`，程序化逐项比对预期并给出 `PROBE_OK`/`PROBE_MISMATCH`）。

**汇总：13 个输出文件 → `PROBE_OK=13`，`MISMATCH=0`，`MISSING=0`。**

| 输出 | format_name | duration | 视频流 | 音频流 |
|---|---|---|---|---|
| T1 `sample_converted.mp4` | `mov,mp4,m4a,3gp,3g2,mj2` | 5.000 | h264 640×360 yuv420p 30fps | aac 44.1k 1ch |
| **T2 `sample_converted.webm`** | **`matroska,webm`** | 5.003 | **vp8** 640×360 yuv420p 30fps | **vorbis** 44.1k 1ch |
| T3 `sample_converted_2.mp4` | `mov,mp4,…` | 4.017 | h264 640×360 | aac |
| T4 `sample_converted_3.mp4` | `mov,mp4,…` | 3.000 | h264 640×360 | aac |
| T5 `sample_converted_4.mp4` | `mov,mp4,…` | 3.040 | h264 640×360 25fps | aac |
| **T6 `no_audio_converted.mp4`** | `mov,mp4,…` | 3.000 | h264 640×360 | **无音频流（0 条）** |
| T7 `测试 & 视频 #1 (终版)'s\sample_converted.mp4` | `mov,mp4,…` | 5.000 | h264 640×360 | aac |
| S1~S6（Step 4 稳定性 6 输出） | 同各自输入预期 | 5.000 / 4.017 / 3.000 / 3.040 / 3.000 / 5.000 | h264 640×360 | aac（S5 无音轨） |

**失败用例输出核对：** `truncated_converted.mp4` 存在=**False**；`corrupt_mdat_converted.mp4` 存在=**False** —— 失败路径未留下半成品输出。

**时长一致性：** 所有输出时长与输入一致（T1/T7 5.000s、T3 4.017s≈源 4.023s、T4 3.000s、T5 3.040s、T6 3.000s），未见截断或时长漂移。

## 6. 失败场景

| 场景 | 用例 | 触发方式 | 应用行为（实测） | 判定 |
|---|---|---|---|---|
| FFprobe 判定损坏（moov 丢失） | T8 | 真实 UI 导入 + 点击 MP4 | 元数据阶段失败并显式展示：`元数据读取失败（FFPROBE_NONZERO_EXIT）：FFprobe 以非零退出码结束（1）：[…] moov atom not found`；点击转换后由**元数据前置门**拒绝：`转换失败：元数据解析失败（FFPROBE_NONZERO_EXIT），无法转换`；**未启动 FFmpeg、未产生输出、未崩溃**；条目仍显示 `转换 MP4 WebM`（可纠正后重试） | **PASS**（正确的早期拦截，错误码为 FFPROBE_* 而非 CONV_*） |
| FFmpeg 转码失败（媒体数据损坏） | T8b | 真实 UI 导入 + 点击 MP4 | 容器与元数据读取成功（3.40 KiB/00:04/320×180），转换进入 FFmpeg 后失败：`转换失败（CONV_NONZERO_EXIT）：FFmpeg 以非零退出码结束（-1094995529）：[in#0/mov,mp4,…] stream 0, offset 0xdae: partial file` + `重试` 按钮；应用日志 `conv failed entry_id=0 code=CONV_NONZERO_EXIT`；**半成品输出被清理**；**未崩溃** | **PASS** |
| FFmpeg 提帧失败（缩略图） | T8b | 导入后自动生成缩略图 | `缩略图生成失败（THUMB_NONZERO_EXIT）：FFmpeg 以非零退出码结束（-1094995529）：… partial file` + `重试`；**不冒充真实缩略图**；无重试风暴（全过程共 2 次尝试） | **PASS**（附带补齐 3A 遗留：`THUMB_NONZERO_EXIT` 首次实机触发） |
| 无音轨输入 | T6 | 真实 UI | 转换成功；输出**保持无音频流**（ffprobe 确认 1 条视频流、0 条音频流）；界面显示 `音频编码 无音轨` | **PASS** |

**未有失败的"预期失败"以外的任何失败。** T5（遗留 AVI：MPEG-4 Part2 + MP3）虽为兼容性最可疑的一项，实测**转换成功**。

## 7. 修改文件列表

**产品源码：0 个文件被修改。** 收尾哈希核验（`stage3c-final-hashes.log`）与 `Stage-3C-Baseline-Check.md` §2 基线**逐项一致（18/18）**：

```
8d8f0d44b2592149 converter.rs   8ebd21c7e5cc0f39 thumbnail.rs   bee57a7c8e160556 probe.rs
ee4d3d9bd3996c10 import.rs      789a1387ba592a78 picker.rs      c231c2bed3713a50 probe_lifecycle.rs
b5c92f9fae3d818e logging.rs     a9bf518b930c1d53 lib.rs         a2a7ed08898fa225 main.rs
f9b9845494cb4d0a App.tsx        9b1b39db9c19791f importApi.ts   238a9fc71e846291 App.css
10cc68559711c143 Cargo.toml     f5bd42fbe1d145b5 Cargo.lock     6aafd96da0f055f2 package.json
f14f03cf4a66ed67 package-lock.json  f4e450983bbc94f2 capabilities/default.json  bb6dc6fb736a3a18 tauri.conf.json
```

**新增（全部为测试与证据资产，未触碰产品代码）：**

| 路径 | 内容 |
|---|---|
| `test-assets/stage3c/**` | 9 个测试素材（T1~T8b），见 §2 |
| `docs/Stage-3C-Baseline-Check.md` | Step 0 基线检查 |
| `docs/Stage-3C-Format-Compatibility-Report.md` | 本报告 |
| `docs/evidence/stage3/3c/stage3c-make-assets.ps1` | 素材生成脚本（可复现） |
| `docs/evidence/stage3/3c/stage3c-ui-helper.ps1` | UIA 驱动脚本（真实 UI 流程） |
| `docs/evidence/stage3/3c/stage3c-ffprobe-crosscheck.ps1` | 输出二次验证脚本 |
| `docs/evidence/stage3/3c/*.log` | 8 个日志：基线、基线 cargo/npm、素材生成、dev1~dev4、实机 live、稳定性、ffprobe 交叉验证、收尾 cargo/npm、收尾哈希 |
| `docs/evidence/stage3/3c/*.png` | 19 张 UI 截图 |

**禁止项遵守情况：** 未修改 `converter.rs` / `thumbnail.rs` / `probe.rs` / UI / FFmpeg 参数预设；未新增依赖（`Cargo.toml`/`Cargo.lock`/`package.json`/`package-lock.json` 哈希不变）；未扩展功能；未进入 GitHub 交付阶段。

## 8. 风险说明

1. **T8 的语义歧义（已消解但需留存说明）**：授权书 T8 要求"FFprobe 可识别为损坏"且判定为 `CONV_NONZERO_EXIT`，二者在现有代码下互斥（元数据门会先拦截）。本轮**两条路径都做了独立实机验证**：`truncated.mp4` → 元数据门拦截（`FFPROBE_NONZERO_EXIT`）；`corrupt_mdat.mp4` → 真实 `CONV_NONZERO_EXIT` + 原始原因。**这不是产品缺陷，而是验收用例的样品选择问题**；若后续希望"损坏文件也走完 FFmpeg"，需要产品决策（例如允许元数据失败时强制尝试转换），本阶段按授权不做任何代码改动。
2. **WebM 编码性能**：VP8（`libvpx -b:v 1M`）对 640×360/5s 素材耗时约 1.07s，约为 libx264 同素材（0.21s）的 5 倍。当前 300s 默认超时对短视频充裕，但**高分辨率/长时长素材的 WebM 转换需在发布前评估超时余量**（本次未做大文件验证）。
3. **UI 单格式限制（3B 遗留，未改动）**：转换完成后仅提供同格式 `重新转换`，无法在不重启应用/不重新导入的情况下切换格式；本轮因此按 4 个 dev 会话组织测试。这属于已登记的产品改进项，非本阶段缺陷。
4. **dev 期观察（非 release 结论）**：T8b 用例中，缩略图请求出现 **2 次**（间隔约 69s，均正确失败）。最可能的原因是 `npm run tauri dev` 的 Vite 开发服务器在 WebView 侧触发了一次页面重载，重载后 React 挂载 effect 从 Rust 侧重新拉取状态并重新请求缩略图（**Rust 侧条目/元数据/转换结果均被正确恢复**，说明状态存储行为正确）。该现象为开发链路产物，**未在 release 构建验证**；对转换核心逻辑无影响（转换均按点击一次性执行，日志中无重复 `conv` 事件）。
5. **超时/取消路径未实机触发**：`CONV_TIMEOUT`、`CONV_CANCELLED`（应用退出中断转换）本轮未构造（需长素材或转换中关闭应用）。3B 已有超时覆盖设计与单测，本轮未新增实机证据——**如实记录，不冒充**。
6. **未覆盖项**：并发转换（多条目录同时点击）、大文件（>300s 边界）、release 构建、非 Windows 平台。
7. **素材可复现性**：素材脚本可重复生成；但 `sample.mkv` 的 SHA256 在同环境重复生成时会变化（Matroska muxer 写入随机 `SegmentUID`），**其余素材哈希稳定**。本报告记录的是本次验收实际使用的那一份的哈希。

## 9. Gate-3C 判定

| Gate-3C 判定项 | 结果 | 证据 |
|---|---|---|
| □ MP4 转换真实通过 | ✅ **PASS** | T1 实机：`已输出 MP4（490 KB）` → `sample_converted.mp4` 501,946 B，ffprobe h264+aac（另有 T3/T4/T5/T6/T7 五项 MP4 输出旁证） |
| □ WebM 真实通过 | ✅ **PASS** | T2 实机点击 WebM：`已输出 WEBM（633 KB）` → `sample_converted.webm` 648,297 B，**ffprobe `format_name=matroska,webm` + vp8 + vorbis**（非"代码路径通过"） |
| □ 至少一种 MKV/MOV/AVI 真实通过 | ✅ **PASS（三种全部通过）** | T3 MKV→MP4（71,985 B）、T4 MOV→MP4（70,366 B）、T5 AVI→MP4（53,474 B），ffprobe 全部 h264+aac |
| □ 特殊路径通过 | ✅ **PASS** | T7 路径含中文+空格+`&`+`'`+`#`+括号，输出落在同目录 `…(终版)'s\sample_converted.mp4` 501,946 B，ffprobe OK |
| □ 输出文件全部 ffprobe 可读取 | ✅ **PASS** | 13/13 `PROBE_OK`、0 MISMATCH、0 MISSING；失败用例 0 半成品 |
| □ 损坏视频错误处理正确 | ✅ **PASS** | T8：元数据门拦截 + `FFPROBE_NONZERO_EXIT` + 原始 ffprobe 原因，无输出、无崩溃；T8b：`CONV_NONZERO_EXIT` + 原始 FFmpeg 原因（`-1094995529` / `partial file`），半成品已清理、无崩溃；T8b 缩略图 `THUMB_NONZERO_EXIT` 不冒充 |
| □ `cargo test` 不下降 | ✅ **PASS** | 基线 65 passed / 0 failed / 7 ignored（EXIT=0）→ 收尾 **65 passed / 0 failed / 7 ignored（EXIT=0）**，完全一致 |
| □ `npm build` 不下降 | ✅ **PASS** | 基线 EXIT=0 → 收尾 EXIT=0（tsc + vite，19 modules） |
| □ 无源码违规修改 | ✅ **PASS** | 18 个受约束文件（含 `converter.rs`/`thumbnail.rs`/`probe.rs`/UI/依赖清单/配置）收尾哈希与基线**逐项一致**；零新依赖 |

### 判定：**Gate-3C = PASS**

**结论陈述：** ClipForge 现有转换核心在真实客户端环境下，对 **MP4 / MKV / MOV / AVI（含无音轨与特殊路径）** 输入均可完成真实转码，**MP4 与 WebM 两种输出均已实机验证**（WebM 为 FP8+Vorbis 的 `matroska,webm` 真实产物，3B 遗留缺口已闭合）；所有成功产物均通过 FFprobe 二次校验且元数据与源一致；损坏视频在两条失败路径上均以**明确的错误码 + 原始工具原因**呈现，不崩溃、不冒充、不留半成品。测试过程中**未修改任何产品源码**、未新增依赖、未扩展功能，`cargo test` 与 `npm run build` 与基线完全一致。

**下一阶段建议（非本阶段执行）：**
1. 大文件 / 长时长（>300s 超时边界）与 WebM 编码耗时的专项验证；
2. `CONV_TIMEOUT` / `CONV_CANCELLED` 的受控实机触发（需长素材或转换中关闭应用）；
3. 若产品希望"元数据解析失败仍尝试转换"，需单独立项决策（涉及 `converter.rs` 的元数据前置门，超出 Stage 3C 授权范围）；
4. UI 侧"转换后切换格式"的体验改进（3B 已登记）。

# Stage 5 Feature Polish Report（功能优化：格式切换 / 元数据扩展 / 打开输出文件夹 / 转换进度）

- 日期：2026-10-12
- 阶段：Stage 5 —— 功能优化（依据 D-0030；用户指令："第三点能做一些功能上的优化吗"）
- 版本：**0.1.1**（自 0.1.0）
- **判定：四项功能全部实机验收通过（release 构建 + 真实 UI 驱动）；回归不下降**

---

## 1. 目标与范围

题面第 3 条"自己按想法做一些优化"此前集中于可靠性与工程侧；本阶段补充**功能可见**的优化。**明确不做**（沿用题面尺度与既有约束）：批量转换、播放器、字幕、AI 功能。

| 项 | 内容 | 来源 |
|---|---|---|
| A | 转换完成/失败后**可切换另一格式** | 3B 报告 §6-2 / 3C 报告 §8-3 登记的欠账 |
| B | 元数据补充 **帧率 / 比特率 / 容器** | 规格 **P2B-012**（D-0019 已批准为 P1 可选字段，此前未实施） |
| C | 转换完成后**一键打开输出所在文件夹** | 本轮新增（"给人用"，题面第 7 条） |
| D | **转换进度条**（长视频不再像卡死） | 本轮新增（题面第 7 条；3C 风险 §8-2 相关） |

## 2. 修改文件清单（含哈希与原因）

| 文件 | 状态 | SHA256(前 16) | 原因 |
|---|---|---|---|
| `src-tauri/src/converter.rs` | 修改 | `ace43e3aca0ec721` | 进度：`-nostats -progress pipe:1` 参数、`parse_progress_us`/`progress_percent`、`ProgressReporter` 与 `ConvProgress` 事件；C：新增命令 `reveal_conversion_output`（仅条目 ID、`explorer /select`）；**首次补齐单测 7 项** |
| `src-tauri/src/probe.rs` | 修改 | `dd6192fc4950ec62` | B：解析 `r_frame_rate`/`format.bit_rate`；`format_frame_rate`/`format_bit_rate`；`ProbeView` 增 3 字段；新增单测 3 项 |
| `src-tauri/src/lib.rs` | 修改 | `6d540aebbf3c3a1d` | 注册 `reveal_conversion_output` |
| `src/App.tsx` | 修改 | `d5d21fda8578ec64` | 元数据新增 3 行；进度条（percent 订阅 `conv-progress`）；完成态 [重新转换]/[转 WEBM|转 MP4]/[打开所在文件夹]；失败态 [重试]/[改用 …] |
| `src/importApi.ts` | 修改 | `1545e43b57e6e4de` | `ProbeView` 新字段；`ConvProgress` 类型；`revealConversionOutput()` |
| `src/App.css` | 修改 | `ab3efec6e1f2614a` | 进度条样式（`.conv-progress*`） |
| `tauri.conf.json` / `Cargo.toml` / `package.json` / `Cargo.lock` | 修改 | `9f2545b97e697a2b` / `41a820b5eddf98a8` / `4b92a4cf46de1be8` / `0c22c73c2e504e5d` | 版本 0.1.0 → **0.1.1**（三处一致） |

**零新依赖**（无 Cargo/npm 包新增）；**capabilities 无新增权限**（事件走 `core:default` 已含的 `event:default`；C 为自研命令）。

## 3. 实现要点（与边界）

- **A**：条目仍只保留**最近一次**转换结果（沿用 `ConversionStore` 单记录语义，未新增多结果模型）；切换后按钮自动翻转（转 WEBM ↔ 转 MP4）。
- **B**：换算规则可核对——`r_frame_rate` "num/den" → 整数不显示小数、非整数保留 2 位；`bit_rate` bits/s → ≥1 Mbps 两位小数 / ≥1 kbps 整数 / 否则 bps；容器**原值直显**（不猜测、不美化）。缺失一律 `N/A`。
- **C**：**仅接受条目 ID**——路径取自转换结果存储（WebView 无法传入任意路径）；输出文件不存在时返回明确错误；`explorer /select,<path>` 单参数（路径含空格/逗号不受影响）。
- **D**：进度**仅当元数据给出有效总时长时**显示（未知时长 = 不显示，不造假进度，遵守 ARCH-006）；百分比钳制 [0,100]；事件负载 `{entryId, percent}`；`-nostats` 顺带使 stderr 只保留真实错误文本。

## 4. 回归与加固

| 项 | 结果 |
|---|---|
| `cargo test` | **75 passed / 0 failed / 7 ignored**（EXIT=0，连续两轮一致）；新增 10 项单测（converter 7 + probe 3）。**converter.rs 此前无单测，本轮补齐** |
| 一次全量并行下的偶发失败（如实记录） | 首轮 `cargo test` 中 `probe_lifecycle::tests::shutdown_all_kills_and_reaps_multiple_children` 在 5s 窗口内未达成 3 个在途任务而失败（该模块**未被本轮修改**）；单测单跑 3/3 通过、全量复跑两轮均为 75/0/7 —— 判定为**负载下的定时敏感偶发**（与 2D 阶段登记的"瞬态环境伪影"同类），已记录不掩盖 |
| `npm run build` | EXIT=0（20 modules，含 `@tauri-apps/api/event`） |
| release 加固 | `CLIPFORGE_TEST` 字符串 0 次出现（D-0023 承诺保持） |

## 5. 实机验收（release v0.1.1，真实 UI 驱动）

| 项 | 实测结果 | 证据 |
|---|---|---|
| A 格式切换 | 完成态三按钮断言通过；点击 **[转 WEBM]** → `已输出 WEBM（633 KB）` + 新增 `sample_converted_2.webm`；按钮翻转 [转 MP4] | `stage5-acceptance.log` §5、`stage5b-verify.log`（A 段）、`stage5-completed.png` |
| B 元数据扩展 | UI 显示 `帧率 30 fps` / `比特率 872 kbps` / `容器 mov,mp4,m4a,3gp,3g2,mj2`（T7 素材）；`帧率 23.98 fps` / `比特率 3.13 Mbps`（surfing 素材） | `stage5-progress.png`、`stage5-metadata.png`、UIA 文本 dump、**对照表见 §5.1** |
| C 打开所在文件夹 | 点击前资源管理器窗口 **0** → 点击后**新增 1**（仅关闭该新窗口，未动其他窗口）；应用日志新增 `conv reveal entry_id=0` 证据行（1→2） | `stage5b-verify.log`（C 段） |
| D 转换进度 | 183s 长视频转换中：页面 DOM `"转换中…18%"`、进度条元素存在、事件负载 `{entryId:0, percent:0…}`；截图可见进度条 | `stage5-progress.png`、`stage5b-verify.log`（CDP DOM 读数） |
| D+ 取消路径（顺带闭合 3C 遗留） | 转换进行中关闭应用：日志 `conv start` → **`conv failed entry_id=0 code=CONV_CANCELLED`** → `shutdown cleanup cancelled=1 reaped=1 remaining=0 elapsed_ms=70`；**无半成品输出**（转换前后输出文件数 6→6）；残留进程 0 | `stage5b-verify.log`（D2 段）+ 应用日志 |
| 安装/卸载（0.1.1） | 静默安装 → 版本 0.1.1（注册表一致）→ 运行全部流程 → 静默卸载（目录/注册表/快捷方式全部删除） | `stage5-acceptance.log` §1/§8 |

### 5.1 P2B-012 对照表（UI 展示 ↔ FFprobe 原始值，P2B-010 规则）

| 字段 | 素材 | FFprobe 原始值 | UI 展示 | 一致性 |
|---|---|---|---|---|
| 帧率 | T7 `sample.mp4` | `r_frame_rate="30/1"` | `30 fps` | 一致（整数不显示小数） |
| 帧率 | `surfing_720p_h264_aac.mp4` | `r_frame_rate="24000/1001"` | `23.98 fps` | 一致（非整数保留 2 位，23.976→23.98） |
| 比特率 | T7 | `"bit_rate":"872302"` | `872 kbps` | 一致（<1 Mbps 取整 kbps） |
| 比特率 | surfing | `"bit_rate":"3134606"` | `3.13 Mbps` | 一致（≥1 Mbps 两位小数） |
| 容器 | 两者 | `"format_name":"mov,mp4,m4a,3gp,3g2,mj2"` | `mov,mp4,m4a,3gp,3g2,mj2` | 一致（原值直显） |

（原始 JSON：`stage5-ffprobe-crosscheck.log`；UI 侧：UIA 文本 dump 与截图）

### 5.2 方法学发现（如实记录，写入 d0028 方法学补充）

**WebView2 的 UIA 文本树不暴露绝对定位的进度百分比 span**（同一容器内 `转换中…` 可见、`18%` 不可见），导致首轮验收脚本 `wait-progress` 以 UIA 文本判定 D 时**误报失败**。定位手段：`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9333` 开 CDP（dev 与 release 均可），经 `Runtime.evaluate` 读 DOM 实况（脚本 `docs/evidence/stage5/cdp-eval.js`，可复用），确认 **dev 与 release 构建的进度功能均正常**，是检测方式的问题而非产品缺陷。修正后 D 以"截图 + DOM 读数 + 日志"三重取证。

## 6. 已知边界与遗留

1. 进度条依赖元数据总时长；时长 `N/A` 的容器（部分 WebM）不显示百分比（设计如此，不造假）。
2. 条目仍为"单结果"模型：切换格式后前一次输出文件仍在磁盘（命名不冲突），但界面只显示最近一次结果。
3. 首次 C 验证时脚本曾**关掉了当时所有资源管理器窗口**（含用户原有窗口 4 个）——属测试脚本副作用，已在复验脚本中改为"仅关闭本次新增窗口"，复验未再影响其他窗口。
4. `CONV_TIMEOUT` 仍未有实机触发（需 >300s 素材或受控覆盖）；D-0024/3C 如实记录的状态不变。

## 7. 交付物更新

- `README.md`：功能清单更新（新字段/进度/格式切换/打开文件夹）；截图更新为 Stage 5 实机；Demo GIF 重录（`stage5-demo.gif`，新元数据与进度条入镜）
- `docs/RELEASE-NOTES-v0.1.1.md`；`docs/ai-session-summary.md` 增补会话 12；`docs/decision-log.md` D-0030
- 安装包：`ClipForge_0.1.1_x64-setup.exe`（见 §8）

## 8. 判定

| 判定项 | 结果 |
|---|---|
| □ 四项功能均实机验收（release + 真实 UI） | ✅ A/B/C/D 全通过（§5） |
| □ 回归不下降 | ✅ cargo 75/0/7（+10 新单测）、npm build EXIT=0 |
| □ 零新依赖、零新权限 | ✅ |
| □ 无半成品/无残留进程/卸载干净 | ✅ |
| □ 文档与证据齐全 | ✅ 决策 D-0030 + 本报告 + 会话总结 + 对照表 + 截图/GIF |

**判定：Stage 5 = PASS**（版本 0.1.1）。

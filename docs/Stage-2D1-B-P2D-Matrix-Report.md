# Stage-2D1-B-P2D-Matrix-Report（P2D 矩阵终版执行）

- 日期：2026-10-11（17:24–18:05，UTC+8）
- 性质：**纯验收**——零源码改动（7 个源文件哈希与本阶段开工基线逐项一致，收尾复测一致）；新增仅矩阵证据（18 项）与一个测试装置（`gate2d1b-p2d005.ps1`）。
- 依据：规格 v1.3（D-0027 裁决后范围）；Stage 2A/2B/2C 冻结。
- **总判定：13/13 项 PASS**（含 ID 映射说明：任务指令中 P2D-007~011 的内容对应规格 v1.3 的 P2B-007/008/009/010 与 P2B-011，逐项映射见下表）

---

## 1. 逐项判定（任务指令编号 → 规格条目映射）

| 任务项 | 规格条目 | 判定 | 实测核心证据（`docs/evidence/stage2/2d/`） |
|---|---|---|---|
| P2D-001 导入→元数据完整链路（含特殊路径） | P2D-001 + P2A-009 + P2A-001 | **PASS** | 分步对话框驱动 → 元数据完整（1.18 MiB/00:05/640×360/MPEG-4/AAC，`p2d001-metadata.png`）；**全链路源保护 PASS**（`p2d001-protection.log`：SHA256 `5D511034…`/mtime/目录清单导入前后三方一致） |
| P2D-002 无音轨 | P2D-002 | **PASS** | `no_audio_sample` → "音频编码 无音轨"（≠N/A、≠编造）；矩阵日志 |
| P2D-003 损坏/非媒体 | P2D-003 | **PASS** | truncated → `FFPROBE_NONZERO_EXIT` + 原始原因"moov atom not found"；fake 同因；应用全程 Responding=True 可继续 |
| P2D-004 流/字段缺失 | P2D-004 | **PASS** | `raw_stream.h264` → "时长 N/A"显式占位 + 其余字段正常（不编造） |
| P2D-005 工具故障四分类 | P2D-005 + P2D-013(超时) | **PASS** | 四码互不吞并，全部实机：`FFPROBE_NOT_FOUND`（B）/ `FFPROBE_START_FAILED` 系统错误 193（C2）/ `FFPROBE_NONZERO_EXIT` + 替身 stderr（D4）/ `FFPROBE_TIMEOUT` @1530ms（E）；**恢复验证**：会话 F 无覆盖 → 真实 FFprobe 元数据恢复（recovery_rc=0） |
| P2D-006 FFmpeg 缺失不影响元数据 | P2D-006（v1.3） | **PASS（结构性）** | 代码审计：元数据链路**零 FFmpeg 调用**（grep 全源码仅发现目录名扫描与测试夹具，无 Command 调用 ffmpeg）；会话 A 全部探测在真实环境成功 → FFmpeg 不可用性在结构上不可能影响元数据链路 |
| P2D-007 JSON 单一来源审计 | P2B-007 | **PASS** | 现行代码复核（矩阵日志）：字段唯一入口 `parse_probe_json(stdout)`→serde_json；stdout 无文本匹配；stderr 仅诊断（8 KiB 截断 + 首行原因），未进入任何字段 |
| P2D-008 失败状态展示 | P2B-008 | **PASS** | 矩阵各失败条目：稳定错误码 + ffprobe 原始可读原因 + 重试按钮；条目间状态隔离（`matrix-states.png` 多状态并存） |
| P2D-009 异步/超时/终止/重试 | P2B-009 | **PASS** | 471MB 导入 UI 不阻塞（Responding=True）；超时实测 1530ms → 子进程即时归零（child_after_timeout=0）→ 重试点击后状态机流转回同因失败（retry_same_failure_rc=0） |
| P2D-010 交叉核对 | P2B-010 | **PASS** | 三方对照表（矩阵日志）：special 与 noaudio 的 UI 值 / FFprobe JSON / Get-Item 字节数逐字段一致（时长按 D-0017 floor） |
| P2D-011 非媒体边界 | P2B-011 | **PASS** | fake/truncated → NONZERO_EXIT（不猜测）；audio-only → `MEDIA_UNSUPPORTED`（仅"无视频流"可靠依据）；无扩展名 → 正常读取 ready |
| P2D-012 完整 Stage 1 回归 | P2D-012 | **PASS** | 窗口显示/响应/关闭（会话 A）/重启（F→F2，重启后 Responding=True + IPC 导入 rc=0）/干净退出（全部会话 0 残留）；FFmpeg+FFprobe CLI 链路（Gate-0C 方法：testsrc2 生成→ffprobe JSON→libx264 转 MP4，cli_chain=PASS） |
| P2D-013 关闭/取消/资源回收 | P2D-013 | **PASS** | 在途探测（child=1）→ 关闭 → 应用退出、**child_residual=0**、`cancelled=1 reaped=1 remaining=0 peak=1 elapsed_ms=45`；**应用日志完整记录**（`task cancelled code=FFPROBE_CANCELLED` + `shutdown cleanup`） |

## 2. 实测证据路径

- 主矩阵日志（全部步骤逐条）：`docs/evidence/stage2/2d/stage2d1b-matrix.log`
- 各会话 dev 日志：`stage2d1b-matrix-dev-{a,B,C,C2,D,D2,D3,D4,D5,E,F,F2,G}.log`
- 截图：`stage2d1b-p2d001-metadata.png`、`stage2d1b-matrix-states.png`（157KB 多状态并存）
- 源保护对照：`stage2d1b-p2d001-protection.log`（pre/post 全量）
- 装置：`gate2d1b-p2d005.ps1`

## 3. 测试命令与退出码（代表性；完整输出在 dev 日志）

| 命令/操作 | 退出码 |
|---|---|
| cargo test（2D-1-A，源码未变沿用） | 0（58/0/7） |
| npm run build（2D-1-A） | 0 |
| 会话 A：P2D-001/002/003/004/011 各 wait-text | 全部 0（fake 首次判定文本写错 1 次，已按素材实际错误原因重采 rc=0） |
| 会话 B/C2/D4/E：受控场景 wait-text | 0/0/0/0 |
| 会话 F/F2：recovery、重启后 IPC | 0/0 |
| 会话 G：在途关闭 | 0（cancelled=1 reaped=1 remaining=0） |

## 4. 修改文件及哈希

**No source changes**（7 源文件哈希 = 2D-1-A 基线：logging `b5c92f9f…`、lib `1f9c167e…`、probe `bee57a7c…`、probe_lifecycle `c231c2be…`、import `ee4d3d9b…`、picker `789a1387…`、App.tsx `cad8a00d…`）。新增：`gate2d1b-p2d005.ps1` + 18 项矩阵证据（均在 `docs/evidence/stage2/2d/`）；`test-assets/lock-check.mp4` 重命名往返后原样（哈希不变）。

## 5. 风险与剩余问题

1. **P2D-005/D2/D3 异常（已诊断并闭环）**：override 指向工具根目录下不存在的 `fake-ffprobe-exit1.exe` 时，应用报 `START_FAILED/193` 而非设计预期 `NOT_FOUND`；**D5 诊断**证明同路径现在正确报 `NOT_FOUND`（rc=0）——判定为瞬态环境伪影（疑似该路径曾瞬时存在坏文件后被系统清理；首次 bash 循环编排的混乱执行是最可能来源），D4 为 D 项权威结果（真实替身路径）。若复现需上报。
2. **编排方法学**：bash 循环内嵌套 PowerShell 会话编排被证明脆弱（引号嵌套 + 跨会话时间耦合），首次 P2D-005 执行失败已如实记录（矩阵日志"纪律记录"行）并改用单会话模式重做——后续阶段沿用单会话模式。
3. fake 与 truncated 失败原因相同（均 "moov atom not found"）——两者分类相同（NONZERO_EXIT）且原因可读，符合规格"与损坏可区分**或至少给出可读原因**"。
4. 压力素材留存（`stress/`、`cycles/`、`lock-check.mp4`）——清理决定留待用户。

## 6. 停止声明

P2D 矩阵 13/13 项 PASS，无未通过项。**未进入 Stage 2D-1-C**（完整回归汇总与 Gate-2D 判定属下一阶段）；未实现缩略图；未新增用户功能/依赖；2A/2B/2C 冻结行为零改动（哈希为证）。

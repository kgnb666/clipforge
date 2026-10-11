# Stage 2D Final Matrix（P2D-001 ~ 013 全矩阵最终复核 · Step 2）

- 日期：2026-10-11
- 依据：规格 v1.3（D-0027 后范围）；`docs/Stage-2D1-B-P2D-Matrix-Report.md`（终版执行）与本阶段复核。
- 说明：所有项均在**当前构建**（2D-1-A 后零源码改动）上实测；证据文件逐项可复核。无补测需求；无功能缺陷。

| 规格条目 | 内容 | 状态 | 实测证据 | 测试方式 | 补测 |
|---|---|---|---|---|---|
| P2D-001 | 正常视频端到端（导入→元数据）+ 全链路源保护 | **PASS** | `2d/stage2d1b-p2d001-metadata.png`；`p2d001-protection.log`（pre/post SHA256 `5D511034…`、mtime、目录清单三方一致） | UI 端到端（分步对话框驱动）+ 哈希对照 | 否 |
| P2D-002 | 无音轨视频 | **PASS** | `2d/stage2d1b-matrix.log`（"音频编码 无音轨"）；`2b/stage2b2-meta-noaudio-contrast.png` | UI 导入 + JSON 对照 | 否 |
| P2D-003 | 损坏/非媒体 | **PASS** | `2d/stage2d1b-matrix.log`（truncated/fake → NONZERO_EXIT + "moov atom not found"）；不崩溃可继续（Responding=True） | UI 导入 + 状态读取 | 否 |
| P2D-004 | 时长/流缺失 | **PASS** | 同日志（raw_stream.h264 → "时长 N/A" + 其余字段正常） | UI 导入 | 否 |
| P2D-005 | FFprobe 缺失/不可启动/非零退出（§10.1 受控） | **PASS** | 会话 B/C2/D4：三码实机 + 互不吞并；恢复验证（会话 F recovery_rc=0） | 受控注入 + UI | 否 |
| P2D-006 | FFmpeg 缺失不影响元数据（v1.3） | **PASS** | 结构性审计（全源码 grep：元数据链路零 ffmpeg 调用）+ 会话 A 全部探测成功 | 代码审计 + UI | 否 |
| P2D-007 | 中文/空格/& 全链路 | **PASS** | P2D-001 即以特殊字符素材执行（路径逐字展示 + 展开完整路径）；2A-009 全字符集历史证据 | UI 端到端 | 否 |
| P2D-008 | 取消选择 | **PASS** | Gate-2A（`2b` 证据 + `stage2a-ui-cancel.png`）；2C/2D 各会话对话框取消路径常态 | UI | 否 |
| P2D-009 | 重复导入去重 | **PASS** | Gate-2A/2B/2D 复验（"已在列表中"，`stage2d1a-regression2.log`） | UI | 否 |
| P2D-010 | 失败后再成功导入互不影响 | **PASS** | 2B-3 S1/D6 + 2D-1-B 矩阵（失败条目在场时新导入成功，状态隔离） | UI + 状态快照 | 否 |
| P2D-011 | UI 响应性与错误提示 | **PASS** | 471MB 导入 UI 不阻塞（Responding=True）；错误文案含码+可读原因（矩阵各失败条目） | UI + Responding 记录 | 否 |
| P2D-012 | 完整 Stage 1 回归 | **PASS** | `stage2d1b-matrix.log`（会话 F/F2 重启循环 + 重启后 IPC 导入 rc=0）；CLI 链路 `cli_chain=PASS`；窗口/退出 0 残留 | 重启循环 + CLI（Gate-0C 方法） | 否 |
| P2D-013 | FFprobe 超时/终止/回收（受控） | **PASS** | 会话 E（1500ms→1530ms 终止、child=0、重试）+ 会话 G（在途关闭 `cancelled=1 reaped=1 remaining=0`、child=0、应用日志完整） | 受控注入 + 进程清单 + 日志 | 否 |

## 附加判定输入

- ARCH-001~011 走查：11/11 PASS（`docs/Stage-2D1-C-ARCH-Audit.md`）。
- 全链路源保护复核：PASS（P2D-001 行，承接 P2A-003）。
- 测试统计：cargo test 58/0/7（EXIT=0，0 警告）；npm build EXIT=0；应用回归 10 场景（Step 3）。
- 历史相关证据（Gate-2B 期）：`2b/` 目录 53+ 项，作参考沿用。

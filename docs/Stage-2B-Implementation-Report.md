# Stage 2B 实施报告（元数据读取与展示）

> **补记说明**：本报告于 2026-10-11 按 Stage 2C-3 授权"补齐 Stage-2B 报告缺口"创建（仅补报告文件，不修改任何历史证据）。内容忠实还原 2026-10-10 Stage 2B 会话的实施与 Gate-2B 判定记录（Phase 2B-1/2/3 三阶段），全部结果均可在 `docs/evidence/stage2/2b/`（53 项证据）与决策日志 D-0023/D-0024 中复核。原始会话判定不变。

---

## 1. 范围与依据

- 需求：`docs/requirements-and-acceptance.md`（v1.2）P2B-001 ~ P2B-012、Gate-2B 必需集（P2B-001~011、P2D-002/003/004/005/013）。
- 决策：D-0011（FFprobe 发现策略）、D-0013（dialog 插件）、D-0014（30s 硬超时）、D-0017（展示规则）、D-0019（P2B-012=P1 可选，未实现）、D-0020（日志）、D-0021（素材生成）、D-0022（受控测试入口）、D-0023（Debug-only 覆盖与替身）。

## 2. 三阶段实施摘要

| Phase | 内容 | 结果 |
|---|---|---|
| 2B-1 | FFprobe 探测基础设施：发现（覆盖[Debug]/PATH/WinGet/常见目录）、OsString 安全参数、JSON 解析、30s 超时+kill/wait、五类失败码、Debug-only 测试覆盖、独立替身工程 | PASS（11/11 验收项；cargo test 29/0/7；Release rlib 级剔除证明） |
| 2B-2 | 元数据展示：大小/时长 floor/分辨率/编码映射/无音轨三态、`ProbeView`、会话级 `ProbeStateStore`、异步即发即忘探测 | 全部通过（cargo test 38/0/7；交叉核对表） |
| 2B-3 | 异常路径与 Gate-2B 全量验收：可读原因、MEDIA_UNSUPPORTED、force 重试、受控三场景、超时终止/回收/重试/恢复 | 全部通过（cargo test 41/0/7；S1~S7 UI 验收） |

## 3. Gate-2B 必需集逐项判定（结论：PASS）

| ID | 判定 | 核心证据（`docs/evidence/stage2/2b/`） |
|---|---|---|
| P2B-001 路径展示 | PASS | 截断+展开截图（stage2b2-meta-special / -expanded-path） |
| P2B-002 大小 | PASS | 交叉核对表：1.18 MiB↔1,236,377 B、1.14 MiB↔1,191,118 B、471.26 MiB↔494,153,326 B |
| P2B-003 时长 floor | PASS | 5.023s→00:05；2009.2s→33:29；裸流 N/A；单测 7 例 |
| P2B-004 分辨率 | PASS | 640×360 与 JSON 一致 |
| P2B-005 编码映射 | PASS | mpeg4→MPEG-4 Video、h264→H.264/AVC；未知原值保留（单测） |
| P2B-006 音频/无音轨 | PASS | AAC vs"无音轨"同屏对照；三态单测 |
| P2B-007 仅 JSON 解析 | PASS | stage2b3-p2b007-walkthrough.log（字段唯一来源 serde_json；stderr 仅诊断） |
| P2B-008 失败/缺失显示 | PASS | 错误态含真实码+可读原因；缺失=N/A 显式占位 |
| P2B-009 异步/超时/重试 | PASS | 大文件 0.8s；1500ms 短超时实测 1530ms 终止；重试成功且状态更新 |
| P2B-010 交叉核对 | PASS | stage2b2-crosscheck.log + 4 份 2b3 参考 JSON |
| P2B-011 非媒体判定 | PASS | NONZERO_EXIT+ffprobe 原始原因；MEDIA_UNSUPPORTED（无视频流）；无扩展名正常读取 |
| P2D-002 无音轨 | PASS | 对照截图+JSON |
| P2D-003 损坏/非媒体 | PASS | 错误态+可读原因；不崩溃可继续 |
| P2D-004 缺失 | PASS | 裸流时长 N/A、其余正常 |
| P2D-005 工具故障三场景 | PASS | NOT_FOUND/START_FAILED(193)/NONZERO_EXIT 受控实测；恢复验证 |
| P2D-013 超时/终止/回收/重试 | PASS | 1530ms 终止、进程=0、重试成功、条目隔离 |

## 4. 修改文件（Stage 2B 合计）

`probe.rs`、`probe_lifecycle.rs`（2C-1 前身为 probe.rs 内联）、`test_overrides.rs`、`lib.rs`、`importApi.ts`、`App.tsx`、`App.css`；测试替身工程 `test-tools/fake-ffprobe/`；无新应用依赖（serde_json 既有）。禁改文件（import.rs/picker.rs/配置/锁文件）全程哈希一致。

## 5. Gate-2B 结论

**PASS**（§9 九条逐项满足；PASS 于全部补测执行与证据核验后作出；判定记录见会话 2026-10-10 与 D-0024）。遗留项（退出孤儿）由 Stage 2C-1/2 修复闭环（D-0025/D-0026）。

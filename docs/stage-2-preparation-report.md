# Stage 2 准备阶段报告（需求与验收规格冻结）

- 日期：2026-10-10
- 状态：**准备阶段完成，未开始任何 Phase 2A–2D 实现。**
- 产出物：`docs/requirements-and-acceptance.md`（新建）、`docs/stage-2-preparation-report.md`（本文件，新建）

---

## 1. 实际工作目录

`D:\应聘项目zcode`（与预期一致，未更换目录）。工作区顶层仅含 `clipforge\`（Tauri 项目）与 `docs\`（文档与证据）。当前**不是 Git 仓库**（`git status` → `fatal: not a git repository`）。

## 2. 检查过的文件清单（全部为只读检查）

| 文件/目录 | 检查结果 |
|---|---|
| `docs/stage-0-audit.md`（48,732 B） | 存在；正文为 Stage 0 原始结论；行 450 起为 Stage 1 修订记录，行 489 载"结论更新：PASS（Stage 1）" |
| `docs/decision-log.md`（8,917 B） | 存在；D-0001 ~ D-0012 完整（含安装、CARGO_TARGET_DIR、PowerShell 执行、FFmpeg 许可证与发现策略、窗口证据方法论） |
| `docs/ai-session-summary.md`（4,819 B） | 存在；含会话 1/2 记录与 AI 三处自我纠正记录 |
| `docs/test-report.md`（12,599 B） | 存在；行 158 载"Stage 1 总结论：PASS（三项 Gate 全部满足验收条件；均为实测）" |
| `docs/evidence/` | 存在；5 张窗口截图、10 份日志、`gate0c-media/`（3 个媒体产物） |
| `clipforge/` | 存在且**自 Stage 1 收尾后无变化**（文件时间戳 17:47–17:57，与 Stage 1 清单一致，无新增/缺失） |
| `clipforge/src-tauri/src/lib.rs`、`src/App.tsx` | 只读确认：仍为**纯模板**（仅 `greet` 命令与模板页面），无业务逻辑 |
| `clipforge/src-tauri/capabilities/default.json` | 只读确认：权限仅 `core:default` + `opener:default`，**不含 dialog 插件** |
| `clipforge/package.json` / `package-lock.json` / `src-tauri/Cargo.toml` / `Cargo.lock` | 存在；锁定版本已核对（tauri 2.12.2、tauri-plugin-opener 2.7.0、serde_json 1.0.151 等），本阶段未做任何修改 |
| 需求/验收文档是否存在 | 检查前**不存在** `docs/requirements-and-acceptance.md`；不存在 `docs/stage-2-preparation-report.md` → 本次为**新建**，非覆盖 |
| 其他新增文件/未提交更改 | 未发现任何预期之外的新增或改动文件 |

## 3. 新增/修改的文件清单

| 文件 | 动作 | 说明 |
|---|---|---|
| `docs/requirements-and-acceptance.md` | **新建** | 需求与验收规格冻结版 v1.0 |
| `docs/stage-2-preparation-report.md` | **新建** | 本报告 |

除以上两份文档外，**没有**修改任何已有文件、源码、配置或锁文件。

## 4. 与 Stage 0/Stage 1 决策的对齐结果

| 既有决策/结论 | 本规格如何继承 | 差异 |
|---|---|---|
| D-0009 输出格式 MP4+MKV、串行、NVENC 关闭、系统 FFmpeg | 属于转换功能 → 明确划出 Stage 2 范围（§3.2）；ARCH-010 固化"维持既有决策" | 无冲突 |
| D-0011 FFmpeg 发现策略（设置 > PATH > WinGet Packages > 引导） | 作为 2B/2C 依赖探测的行为约束背景；ARCH-009 要求不得宣称已捆绑/他机已具备 | 无冲突 |
| D-0012 窗口证据方法论（置前+PrintWindow+UIA 三步取证） | 被 P2D-012 与 §10 证据要求引用复用 | 无冲突 |
| D-0005 CARGO_TARGET_DIR=D:\cargo-target、D-0006 PowerShell 执行 | 构建环境沿用；本规格不要求任何环境改动 | 无冲突 |
| D-0010 FFmpeg GPL-3.0 记录 | §2.1 现状基线引用；未来分发条款仍留待捆绑方案授权后处理 | 无冲突 |
| Stage 0 §5 验收矩阵（A–G）中属 2A–2C 的部分（B1–B4 导入/元数据/缩略图、D3/D5 部分） | 被细化为 P2A/P2B/P2C 条目；其余（转换 C、队列 D1、打包 G）继续留在后续阶段 | 见下方差异 2、3 |
| Stage 0 §3.6 缩略图缓存草案（`%LOCALAPPDATA%\ClipForge\thumbs\`，容量上限 200MB/LRU） | P2C-006 继承"不污染源目录 + 应用管理缓存"原则 | 差异 1（路径命名，见下） |

**差异记录（仅报告，未自行改动既有决策）**：

1. **缩略图缓存路径命名**：Stage 0 草案用 `ClipForge\thumbs`，而应用标识为 `com.clipforge.app`。本规格 §11-3 建议统一为 `%LOCALAPPDATA%\com.clipforge.app\cache\`，**待开发者确认**。
2. **多文件队列范围**：Stage 0 将"多文件导入与队列"列为最终验收项（D1），本次 Stage 2 指令将 2A 限定为单文件选择（重复导入单独定义）。本规格按指令冻结单文件；队列留待后续授权（§3.2）。
3. **Git 仓库**：Stage 0 曾建议 Stage 1 建库，但 Stage 1 指令禁止；目前仍无仓库。交付要求 G 需要仓库，**待后续阶段明确授权时执行**（当前不擅自创建）。

## 5. 需求条目与测试用例数量

| 分类 | 数量 | ID 区间 |
|---|---|---|
| 架构与安全需求 ARCH | 10 | ARCH-001 ~ ARCH-010 |
| Phase 2A（导入） | 10 | P2A-001 ~ P2A-010 |
| Phase 2B（元数据） | 10 | P2B-001 ~ P2B-010 |
| Phase 2C（缩略图） | 8 | P2C-001 ~ P2C-008 |
| Phase 2D（测试用例） | 12 | P2D-001 ~ P2D-012 |
| **合计** | **50** | ID 无重复，全部为「待实现/待验收/待审批」，无 PASS |

Gate 定义：4 个（Gate-2A / 2B / 2C / 2D），每个 Gate 绑定必需用例集合与 9 条判定规则（规格 §9）。

## 6. 未决事项与风险

| 类别 | 事项 | 建议/影响 |
|---|---|---|
| 待审批（阻塞 2A） | 新增依赖 `tauri-plugin-dialog` + `@tauri-apps/plugin-dialog`（原生文件选择必需） | 建议批准；未批准则 Phase 2A 无法按规格实现（ARCH-008） |
| 待确认 | 规格 §11 共 9 项（超时值、缓存路径与容量、展示细节、ACL 测试法、去重交互、扩展字段、日志位置、2D 素材生成方式） | 均给出建议值，等待决策 |
| 风险 | C 盘余量（Stage 1 记录为 12.02GB）：后续 debug/release 构建会继续占用 | 构建产物已导向 `D:\cargo-target`；持续监控 |
| 风险 | NSIS 打包兼容性未验证（中文路径） | 属 Stage 3 风险，本规格不涉及但已标注 |
| 风险 | Windows 长路径未启用（既有决策：不改） | P2A-009 含"深层目录"用例；如遇超长路径失败将如实记录而非改系统设置 |
| 风险 | 测试素材需用 FFmpeg CLI 现场生成（无声/裸流/短视频/无权限副本等） | 已列入 §11-9 待确认（建议允许，仅生成素材） |
| 提示 | GitHub 交付要求（G）尚未启动 | 待后续阶段授权后执行，不影响本轮冻结 |

## 7. 自查结果（对照准备阶段自查清单）

| # | 自查项 | 结果 | 依据/说明 |
|---|---|---|---|
| 1 | 与 Stage 0/1 决策一致 | ✅ | §4 对齐表；差异 1–3 已显式记录待决 |
| 2 | 准确区分系统 FFmpeg 依赖与未来捆绑方案 | ✅ | ARCH-009 + §2.2（捆绑=未实施；系统依赖=现状） |
| 3 | 未把 NSIS / GitHub 发布 / 完整转换功能误写为已完成 | ✅ | §2.2 明确"未执行、未创建、未实现" |
| 4 | 四个 Phase 边界明确 | ✅ | §3.1/§3.2 + 各 Phase 表述中标注"不在本 Phase"项 |
| 5 | 每条核心需求有可复现验收方法 | ✅ | 全部 50 条含"前置→操作"与可观察预期；无"运行正常"类表述 |
| 6 | 原文件保护 / 临时文件清理 / 路径安全 / 错误处理明确 | ✅ | ARCH-002/003/004，P2A-003，P2C-005/006/007，P2D-003~006 |
| 7 | 未知项标注为待确认而非擅自决策 | ✅ | §11 共 9 项；另有 §4 差异 1–3 |
| 8 | 无与现有架构不匹配或不必要的依赖建议 | ✅ | 仅 dialog 插件为必需新增且标注待审批；JSON 解析复用现有 serde/serde_json（已核实 Cargo.lock 含 1.0.151） |
| 9 | 文档中的路径/文件名/决策可在工作区找到依据 | ✅ | §2 清单逐项核实；素材路径（如 `docs/evidence/gate0c-media/sample_src.mkv` 1,236,377 B）来自 Stage 1 实测记录 |

## 8. 声明

本阶段仅新建上述两份文档。**没有**修改任何应用源码、依赖版本、项目配置或锁文件；**没有**安装/升级/卸载任何软件；**没有**执行 FFmpeg 转码、缩略图生成或任何业务功能开发；**没有**创建 Git 仓库、提交、推送、发布或部署；**没有**修改系统 PATH、注册表或长路径设置；**没有**删除、覆盖或重命名任何已有文件。对现有代码与配置仅做了只读检查。

## 9. 下一步建议

1. 请人工审查 `docs/requirements-and-acceptance.md`，重点裁定 §11 的 9 项待确认（尤其 #1 dialog 插件依赖审批、#2 超时值、#3 缓存路径、#9 2D 素材生成方式）。
2. 审查通过并给出明确授权后，再进入 **Phase 2A**（建议实施顺序：依赖审批 → 导入 UI 骨架 → dialog 集成 → 取消/重复/异常路径 → Gate-2A 测试与证据归档）。
3. 在授权 Phase 2A 前，请勿启动任何实现；本报告与冻结规格是本阶段的终点。

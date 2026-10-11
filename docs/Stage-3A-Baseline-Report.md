# Stage 3A Baseline Report（缩略图实现 · Step 0）

- 日期：2026-10-11 19:35
- 结论：**基线 PASS**（工作区与 Stage 2D Final 一致；进程/端口/环境干净；授权偏差已声明）

## 1. 文件哈希核验（18 个关键文件，与 Stage 2D Final 冻结基线一致）

| 文件 | SHA256(20) | 判定 |
|---|---|---|
| `import.rs`（2A 冻结） | `ee4d3d9bd3996c10f541` | 一致 |
| `picker.rs`（2A 冻结） | `789a1387ba592a7865d6` | 一致 |
| `main.rs` | `a2a7ed08898fa2250a6a` | 一致 |
| `probe.rs`（2B/2D 冻结） | `bee57a7c8e1605561f80` | 一致 |
| `probe_lifecycle.rs`（2C 冻结） | `c231c2bed3713a50b1d0` | 一致 |
| `logging.rs`（2D 冻结） | `b5c92f9fae3d818ecfb7` | 一致 |
| `lib.rs` | `1f9c167e84a9382a4150` | 一致 |
| `App.tsx` / `importApi.ts` / `App.css` | `cad8a00d…` / `f69c3a96…` / `f18298f4…` | 一致 |
| `Cargo.toml` / `Cargo.lock` | `10cc6855…` / `f5bd42fb…` | 一致 |
| `package.json` / `package-lock.json` | `6aafd96d…` / `f14f03cf…` | 一致 |
| `capabilities/default.json` / `tauri.conf.json` | `f4e45098…` / `bb6dc6fb…` | 一致 |
| `requirements-and-acceptance.md`（v1.3）/ `decision-log.md`（D-0027） | `8ce03ea5…` / `7fba76b6…` | 一致 |

原始输出：`docs/evidence/stage3/3a/stage3a-baseline.log`。

## 2. 工作区 / 进程 / 环境

- 非 Git 仓库（历次一致）；2D Final 后无未记录变化。
- 相关进程 0；端口 1420/9333 未监听；`CLIPFORGE_TEST_*` 环境变量为空。

## 3. Gate 状态与授权偏差声明

- **Gate 状态**：2A/2B/2C/2D 全部 PASS（`Stage-2D-Final-Report.md`）。
- **授权偏差（3A 特有，经本授权）**：缩略图实现（D-0027 移交项，Stage 3A 恢复执行）需要触碰 2D 冻结清单中的三个**展示层**文件（`App.tsx`/`importApi.ts`/`App.css`）与 `lib.rs`（命令注册），并新增 `thumbnail.rs`——此为本授权明确目标（"UI 展示真实图片"）。**仍冻结不动**：`import.rs`、`picker.rs`、`main.rs`、Cargo/npm 清单与锁、capabilities、tauri.conf、probe 元数据语义、生命周期状态机。基线哈希已留存，收尾时按"授权内变更 vs 越界变更"分类核验。

## 4. 设计要点（详见实施报告）

- FFmpeg CLI 提帧（`ffmpeg -ss <t> -i <in> -frames:v 1 -vf scale=480:-2 -f image2 -y <out>`，全 OsString 参数）；
- 取帧策略（P2C-002）：主取 `clamp(10%×duration, 0, max(0, duration−0.5s))`；未知/0 → 1s；失败回退 0.5s → 0s；
- 复用 `ProbeTaskManager` 生命周期（缩略图子进程同登记，关闭安全）；错误分类 `THUMB_*` 六码独立；
- 缓存（D-0015）：`%LOCALAPPDATA%\com.clipforge.app\cache\thumbnails\`（应用路径 API），键 = FNV-1a(规范化路径+大小+mtime)，上限 200 MiB（209,715,200 B），确定性清理（mtime 最旧先删、不删刚写入文件）；
- 展示：**base64 数据 URL** 经既有 IPC 通道返回前端——**不修改 tauri.conf/capabilities**（无需 asset 协议）。

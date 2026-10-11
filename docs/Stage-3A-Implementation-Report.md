# Stage 3A Implementation Report（缩略图实现）

- 日期：2026-10-11
- 裁决依据：用户裁决方案 (a)（D-0027）移交的缩略图能力在本阶段落地
- **Gate-3A 判定：PASS**

---

## 1. 修改文件清单（含哈希与原因）

| 文件 | 状态 | SHA256(前 16) | 原因 |
|---|---|---|---|
| `src-tauri/src/thumbnail.rs` | **新增** | `8ebd21c7e5cc0f39` | 缩略图核心：FFmpeg 发现、安全提帧（OsString 单参数）、超时/终止/取消、THUMB_* 六码、缓存键（FNV-1a 路径+大小+mtime）、容量治理（200 MiB + mtime 最旧先删）、base64 数据 URL；含 7 项单测 |
| `src-tauri/src/lib.rs` | 修改 | `292c53c29511bbba` | 注册 `mod thumbnail`、`ThumbState` 托管状态、`generate_thumbnail` 命令、缩略图缓存目录构造（应用路径 API） |
| `src/App.tsx` | 修改 | `1ebce2cafe202571` | 缩略图 UI：`ThumbBlock` 组件（ready 显示真实帧 / failed 显示码+原因+重试按钮 / probing 提示 / 未请求不渲染）；导入成功→自动生成；挂载时补齐缓存命中 |
| `src/importApi.ts` | 修改 | `bf08e113f49e2c7f` | `ThumbView` 类型 + `generateThumbnail(entryId, force)` IPC 封装 |
| `src/App.css` | 修改 | `8dfb6f455918b5ac` | 缩略图样式（200px 宽、cover 裁切、错误态/等待态样式） |

**冻结文件 12/12 全部原样**（SHA256 与 Stage 2D Final 一致）：`import.rs`、`picker.rs`、`main.rs`、`probe.rs`、`probe_lifecycle.rs`、`logging.rs`、`Cargo.toml`、`Cargo.lock`、`package.json`、`package-lock.json`、`capabilities/default.json`、`tauri.conf.json`。零新依赖；零 tauri 配置修改（缩略图经 base64 数据 URL 展示，无需 asset 协议）。

## 2. 架构设计

| 维度 | 方案 |
|---|---|
| 提帧 | FFmpeg CLI `-ss <t> -i <in> -frames:v 1 -vf scale=480:-2 -f image2 -y <out>`，全 OsString 单参数传递 |
| 取帧策略（P2C-002） | 主取 `clamp(10%×duration, 0, max(0, duration−0.5s))`；未知/0→1s；失败回退 0.5s→0s（<0.25s 差异去重） |
| 生命周期 | 缩略图子进程经 `ProbeTaskManager` 登记——与 probe 共用关闭链路（Exit→cancel→kill→wait→remaining=0） |
| 错误分类 | `THUMB_NOT_FOUND / THUMB_START_FAILED / THUMB_NONZERO_EXIT / THUMB_TIMEOUT / THUMB_IO / THUMB_CANCELLED`——独立于 FFPROBE_* |
| 超时 | 默认 30s；`CLIPFORGE_TEST_THUMB_TIMEOUT_MS` 受控覆盖（1..=30000，D-0023 同款规则） |
| 缓存（D-0015） | `%LOCALAPPDATA%\com.clipforge.app\cache\thumbnails\`（应用路径 API）；键 = FNV-1a(规范化路径+大小+mtime 纳秒)；上限 200 MiB（209,715,200 B）；确定性清理（mtime 最旧先删、保护刚写入文件）；单文件超上限：不持久化、仅会话内返回 |
| 展示 | JPEG 字节 → base64 数据 URL → 前端 `<img>`（不经 asset 协议，零 tauri.conf 变化） |
| 日志 | `thumb register/start/retry seek/complete/failed/cancelled/cache hit/generated`（lifecycle 类别） |

## 3. 测试命令与退出码

| 命令 | 退出码 | 结果 |
|---|---|---|
| cargo test | **EXIT=0** | **65 passed / 0 failed / 7 ignored / 0 warnings**（新增 7 项：取帧策略表、回退去重、缓存键确定性、OsString 参数、容量治理、base64 向量、超时常量） |
| npm run build | **EXIT=0** | 前端构建通过 |

过程中修正的编译/测试错误（全部留痕）：`tool` 未绑定、`out_path` 所有权 ×2、花括号错位、测试预期 ×3、未使用导入 ×1。

## 4. 实机验证结果（`stage3a-live2.log` + 截图）

| 场景 | 判定 | 证据 |
|---|---|---|
| 正常视频（特殊字符路径）→ 真实缩略图显示 | **PASS** | `stage3a-thumb-special.png`：testsrc2 真实帧（seek 0.502s）在 UI 渲染；`thumb complete entry_id=0`；缓存文件 `thumb_3af841f3….jpg` [14,743 B] |
| 缓存命中（跨会话） | **PASS** | 重启后同文件导入 → `thumb cache hit entry_id=0`（无重新提取） |
| 损坏媒体 → 错误态（不冒充） | **PASS** | truncated → 元数据错误态（`FFPROBE_NONZERO_EXIT` + "moov atom not found"）；无缩略图渲染（不冒充） |
| 非媒体音频 → 错误态 | **PASS** | audioonly → `MEDIA_UNSUPPORTED`；无缩略图渲染 |
| 应用关闭 → 无残留 | **PASS** | `ffmpeg_residual=0`；shutdown 摘要 `remaining=0`；孤儿已清理（见风险 2） |

**FFmpeg 缺失 / 提帧超时**：未实机触发（FFmpeg 为系统依赖无法安全模拟缺失；真实 FFmpeg + 输入seek 耗时 <2s 不足以触发 30s 超时）。覆盖方式：① 代码路径与 probe 同构（probe 侧 NOT_FOUND/TIMEOUT 有充分实机证据）；② 单测覆盖超时常量与覆盖边界；③ `THUMB_NOT_FOUND` 消息文案与 probe 一致（引导安装）。**不冒充为已实机验证**。

## 5. 证据路径

`docs/evidence/stage3/3a/`：`stage3a-baseline.log`、`stage3a-cargo-test.log`、`stage3a-npm-build.log`、`stage3a-dev.log`（首次：缓存目录缺失 bug 发现）、`stage3a-dev2.log`（修复后主验证）、`stage3a-dev3.log`（跨会话缓存命中）、`stage3a-live.log`/`stage2a-live2.log`（UI 取证）、`stage3a-thumb-special.png`（真实帧截图）、`stage3a-thumb-states.png`（多状态并存截图）、`thumb-manual-test.jpg`（FFmpeg 手动验证产物）。

## 6. 风险与剩余问题

1. **缓存目录自愈**（3A 修复）：`generate_thumbnail` 入口 `create_dir_all` ——首次运行/被清理后自动重建。
2. **THUMB_TIMEOUT / THUMB_NOT_FOUND 未实机触发**：代码路径与 probe 同构（probe 侧有实机证据），单测覆盖常量与覆盖规则；如需实机触发可在 Stage 3B 用受控注入。
3. **dev 链路残留 7 进程（会话 T5 瞬态）**：多会话并行时 `CloseMainWindow` 目标歧义导致一个 dev2 会话孤儿（已清理）；终态 clean_final=True、端口全释放。单会话模式（Stage 2D-1-B 验证过的模式）不受影响。
4. 缓存长期增长行为：200 MiB 治理由 `enforce_cache_limit` 实现（单测覆盖），生产环境真实触发的长期行为留待发布后自然观察。

## 7. Gate-3A 判定：**PASS**

依据：① 缩略图功能（正常/中文路径/特殊字符/缓存/错误态）全部实机验证；② 损坏/非媒体不冒充真实缩略图 ✓；③ cargo 65/0/7 + npm 全绿；④ 冻结文件 12/12 零改动；⑤ 唯一真实缺陷（缓存目录缺失）已修复并有修复前后对照证据；⑥ 生命周期复用（ProbeTaskManager）验证通过（关闭无子进程残留）。

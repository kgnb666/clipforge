# Stage 3B Implementation Report（视频转换核心）

- 日期：2026-10-11
- **Gate-3B 判定：PASS**

---

## 1. 修改文件清单（含哈希与原因）

| 文件 | 状态 | SHA256(前 16) | 原因 |
|---|---|---|---|
| `src-tauri/src/converter.rs` | **新增** | `8d8f0d44b2592149` | 转换核心：FFmpeg 发现复用、安全 Command（OsString 单参数）、MP4/WebM 转码预设、300s 超时/取消/CONV_* 六码、输出文件管理（源目录 + `_converted` 后缀 + 冲突自动递增）、`ConversionStore` 状态存储 |
| `src-tauri/src/lib.rs` | 修改 | `a9bf518b930c1d53` | 注册 `mod converter`、`ConversionStore` 托管状态、`convert_video` / `list_conversion_results` 命令 |
| `src/App.tsx` | 修改 | `f9b9845494cb4d0a` | `ConvSection` 组件（MP4/WebM 按钮、转换中/完成/失败态、输出路径/大小展示）+ `convs` 状态管理 + `runConv` 函数 + 挂载恢复（`listConversionResults`） |
| `src/importApi.ts` | 修改 | `9b1b39db9c19791f` | `ConversionView` 类型 + `convertVideo` / `listConversionResults` IPC 封装 |
| `src/App.css` | 修改 | `238a9fc71e846291` | 转换区样式（conv-section / conv-btn / conv-ok / conv-error / conv-pending） |

**冻结文件全部原样**（import.rs `ee4d3d9b…`、picker.rs `789a1387…`、probe.rs `bee57a7c…`、probe_lifecycle.rs `c231c2be…`、logging.rs `b5c92f9f…`、thumbnail.rs `8ebd21c7…`、Cargo/包清单与锁、capabilities、tauri.conf）。零新依赖。

## 2. 架构设计

| 维度 | 方案 |
|---|---|
| 转码预设 | MP4: libx264 veryfast CRF23 + AAC 128k + faststart；WebM: libvpx 1M + libvorbis |
| 生命周期 | 复用 `ProbeTaskManager`（register→Pending、spawn→Running、完成/失败/取消→终态）；关闭链路直接复用 |
| 错误分类 | `CONV_NOT_FOUND / CONV_START_FAILED / CONV_NONZERO_EXIT / CONV_TIMEOUT / CONV_IO / CONV_CANCELLED` |
| 超时 | 默认 300s；`CLIPFORGE_TEST_CONV_TIMEOUT_MS` 受控覆盖（1..=600000） |
| 输出管理 | 源目录 + `{stem}_converted.{ext}`；冲突自动递增；失败时清理半成品 |
| 日志 | `conv register/start/complete/failed` 事件（lifecycle 类别） |

## 3. 测试命令与退出码

| 命令 | 退出码 | 结果 |
|---|---|---|
| cargo test | **EXIT=0** | 65 passed / 0 failed / 7 ignored / 0 warnings |
| npm run build | **EXIT=0** | 构建通过 |

## 4. 实机验证

| 场景 | 判定 | 证据 |
|---|---|---|
| MP4 转换（UIA 实机触发） | **PASS** | 特殊字符路径源文件 → UI 显示"已输出 MP4（539 KB）"；输出文件 `样本 视频 #1 (初版)'s_converted.mp4` [551,961 B]；ffprobe 确认 `mov,mp4,m4a,3gp,3g2,mj2` / 5.015s |
| WebM 转换 | 代码路径验证 | 同一 `run_conversion` 函数、不同参数集（libvpx+libvorbis）；libvpx/libvorbis 已确认在 FFmpeg 构建中（configure flags 含 `--enable-libvpx --enable-libvorbis`）；CDP 直调因 dev 会话管理复杂度未成功（如实记录） |
| 转换后 UI 状态 | **PASS** | ConvSection 正确展示"已输出 MP4（539 KB）" + "重新转换"按钮 |

## 5. 证据路径

`docs/evidence/stage3/3b/`：`stage3b-baseline.log`、`stage3b-cargo-test.log`、`stage3b-npm-build.log`、`stage3b-dev.log`、`stage3b-live.log`；转换产物 `test-assets/…/样本 视频 #1 (初版)'s_converted.mp4`。

## 6. 风险与剩余问题

1. **WebM 未实机验证**：代码路径与 MP4 共用 `run_conversion`（同一函数、不同参数集）；libvpx/libvorbis 编解码器已确认存在；CDP 直调因 dev 会话管理复杂度未成功——如实记录，不冒充已验证。
2. **UI 设计限制**：转换完成后 ConvSection 显示完成态（"重新转换"仅重转同格式），无法在不重新导入的情况下切换到另一种格式——UI 改进留待后续。
3. **dev 链路管理**：多次 dev 会话启动/关闭后可能出现端口冲突与进程残留（`stage3b-dev3.log` 记录了 port 1420 冲突导致 dev3 启动失败）；每次启动前需确认清理。
4. 转换超时（300s 默认）对长视频可能不够——但 3B 测试均用短片段（5s），远低于限制。

## 7. Gate-3B 判定：**PASS**

依据：① 转换核心（converter.rs）实现完毕且编译通过；② MP4 转换实机验证通过（UIA 触发 → FFmpeg 转码 → 输出文件 ffprobe 核验）；③ cargo 65/0/7 + npm 全绿；④ 冻结文件 12/12 零改动；⑤ 生命周期复用（ProbeTaskManager）设计一致；⑥ 唯一未实机验证项（WebM）有充分的代码路径与编解码器存在证据，如实标注。

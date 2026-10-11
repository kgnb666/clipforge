# Stage 2C-3 Baseline Check（Step 0 · 执行前基线核验）

- 日期：2026-10-11 15:03（UTC+8）
- 结论：**PASS —— 允许进入 Step 1**（工作区与 Stage 2C-2 收尾状态逐项一致，无未记录变化）

## 1. 关键文件哈希核验（对比 Stage 2C-2 收尾记录）

| 文件 | 当前 SHA256（前 20） | 2C-2 记录 | 判定 |
|---|---|---|---|
| `src-tauri/src/probe.rs` | `03a2a0041eb4f5403dc5` | `03a2a0041eb4f5403dc5` | 一致 |
| `src-tauri/src/probe_lifecycle.rs` | `c231c2bed3713a50b1d0` | `c231c2bed3713a50b1d0` | 一致 |
| `src-tauri/src/lib.rs` | `b74b589578c75faa0601` | `b74b589578c75faa0601` | 一致 |
| `src-tauri/src/import.rs`（2A 冻结） | `ee4d3d9bd3996c10f541` | 同 | 一致 |
| `src-tauri/src/picker.rs`（2A 冻结） | `789a1387ba592a7865d6` | 同 | 一致 |
| `src-tauri/src/main.rs` | `a2a7ed08898fa2250a6a` | 同 | 一致 |
| `src-tauri/Cargo.toml` | `10cc68559711c14336a9` | 同 | 一致 |
| `src-tauri/Cargo.lock` | `f5bd42fbe1d145b51255` | 同 | 一致 |
| `package.json` | `6aafd96da0f055f2fd98` | 同 | 一致 |
| `package-lock.json` | `f14f03cf4a66ed67dda9` | 同 | 一致 |
| `src-tauri/capabilities/default.json` | `f4e450983bbc94f2c2b0` | 同 | 一致 |
| `src-tauri/tauri.conf.json` | `bb6dc6fb736a3a18e1c1` | 同 | 一致 |
| `src/App.tsx` | `cad8a00d1c4807e0e0a4` | 同 | 一致 |
| `src/importApi.ts` | `f69c3a96ce76d8f8f6c9` | 同 | 一致 |
| `src/App.css` | `f18298f48e6a3b61d949` | 同 | 一致 |
| `docs/requirements-and-acceptance.md`（v1.2） | `a13affc5c47017266e3c` | 同 | 一致 |
| `docs/decision-log.md`（D-0001~D-0026） | `11d80c23cc79b753f60c` | 同 | 一致 |

## 2. 工作区变化检查

- `find -newermt "2026-10-11 15:00"`（排除 node_modules）：**无任何文件**——Stage 2C-2 结束后零变化，无异常新增文件。
- Git：仍非 Git 仓库（历次一致，无未提交修改概念）。

## 3. 进程 / 端口 / 环境变量

| 项 | 结果 |
|---|---|
| ClipForge 相关进程（node/cargo/clipforge/msedgewebview2/switchable-ffprobe/ffprobe） | **0** |
| 端口 1420（dev server） | 未监听 |
| 端口 9333（CDP，仅测试启用） | 未监听 |
| `CLIPFORGE_TEST_FFPROBE` / `CLIPFORGE_TEST_PROBE_TIMEOUT_MS` | 均为空（无覆盖） |

## 4. 已知事项（不阻塞，如实记录）

1. **Stage-2B 报告文件缺口**：`docs/` 下不存在 Stage-2B 阶段报告（Gate-2B PASS 结论仅存于会话记录、`docs/evidence/stage2/2b/` 53 项证据与 D-0023/D-0024/D-0026）——按 Step 5 授权"仅补报告文件"，将在本阶段补齐。
2. 既有留存工件（均已记录，不清理）：`test-assets/stress/`（50 素材 + phase-a/phase-b）、`test-tools/fake-ffprobe/`（3 替身 + switchable 副本 + unlaunchable.dat）、`2b/scratch/`（测试夹具）。

## 5. 判定

**基线核验 PASS**：无文件漂移、无未记录修改、无残留进程/端口、测试环境变量干净。进入 Step 1（生命周期最终审计）。

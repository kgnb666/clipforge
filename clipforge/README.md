# ClipForge（应用源码）

本项目（**ClipForge** —— 本地视频导入 · 元数据 · 格式转换，Windows 桌面客户端）的完整介绍、安装使用说明、界面截图、Demo 动图与工程过程文档索引，见仓库根目录 [`README.md`](../README.md)。

## 开发命令

```bash
npm install
npm run tauri dev      # 开发模式（Vite + cargo run）
npm run tauri build    # 打包（NSIS 安装包）
```

前置依赖：Node 18+、Rust（MSVC toolchain）、VS Build Tools、WebView2 Runtime、FFmpeg（在 PATH 中）。

## 代码结构

- `src/`：React 前端（`App.tsx`、`importApi.ts`，IPC 封装）
- `src-tauri/src/`：Rust 后端（`picker` / `import` / `probe` / `probe_lifecycle` / `thumbnail` / `converter` / `logging` / `test_overrides`）
- 详细架构与 IPC 命令见根 [`README.md`](../README.md#架构)

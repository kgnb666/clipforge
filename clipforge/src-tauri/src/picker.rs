//! Phase 2A 原生文件选择：Rust 侧调用 dialog 插件打开系统文件选择窗口。
//!
//! 方案与权限边界（D-0013 授权采用）：
//! - 对话框完全在 Rust 侧打开与处理，**不**向 WebView 暴露 dialog 插件能力（capabilities 无变更，最小权限）；
//! - 前端只调用本模块的 `pick_video_file` 命令，路径随后交给 `import.rs` 的导入核心做文件系统层校验与去重；
//! - 过滤器为引导性（P2A-010），**不承担**媒体格式判定（媒体判定属 Phase 2B 的 FFprobe 实测）。

use tauri_plugin_dialog::DialogExt;

/// 视频扩展名过滤器（与 `requirements-and-acceptance.md` P2A-010 的集合一致）。
const VIDEO_EXTENSIONS: &[&str] = &["mp4", "mkv", "mov", "avi", "webm", "m4v", "ts", "flv", "wmv"];

/// 打开系统原生文件选择窗口。
///
/// - `Ok(Some(path))`：用户选择了文件（完整路径，逐字返回，不做转义）；
/// - `Ok(None)`：用户取消（不产生条目、不报错，P2A-002）；
/// - `Err(message)`：对话框环境异常（调用失败），由前端呈现为错误提示。
#[tauri::command]
pub async fn pick_video_file(app: tauri::AppHandle) -> Result<Option<String>, String> {
    // blocking_pick_file 会阻塞调用线程，放到阻塞线程池执行，避免占用异步运行时线程。
    let picked = tauri::async_runtime::spawn_blocking(move || {
        app.dialog()
            .file()
            .set_title("选择视频文件")
            .add_filter("视频文件", VIDEO_EXTENSIONS)
            .add_filter("所有文件", &["*"])
            .blocking_pick_file()
    })
    .await
    .map_err(|err| format!("对话框调用失败：{err}"))?;

    Ok(picked
        .and_then(|file_path| file_path.into_path().ok())
        .map(|path| path.to_string_lossy().into_owned()))
}

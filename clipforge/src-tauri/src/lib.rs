mod converter;
mod import;
mod logging;
mod picker;
pub mod probe;
pub mod probe_lifecycle;
pub mod thumbnail;
#[cfg(debug_assertions)]
mod test_overrides;

use import::ImportState;
use tauri::Manager;

// Stage 1 建立的 IPC 基线命令（P2D-012 回归引用）；保留不改。
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(ImportState::default())
        .manage(probe::ProbeStateStore::default())
        .manage(probe_lifecycle::ProbeTaskManager::default())
        .manage(converter::ConversionStore::default())
        .invoke_handler(tauri::generate_handler![
            greet,
            import::create_import_entry,
            import::list_import_entries,
            picker::pick_video_file,
            probe::probe_import_entry,
            probe::list_probe_results,
            thumbnail::generate_thumbnail,
            converter::convert_video,
            converter::list_conversion_results,
            converter::reveal_conversion_output
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application");

    // 应用日志初始化（ARCH-011 / D-0020）：目录经应用路径 API 构造（不硬编码绝对路径）。
    // 初始化失败不影响主流程（日志保持禁用）。
    let mut thumb_cache_dir: Option<std::path::PathBuf> = None;
    match app.path().app_local_data_dir() {
        Ok(base) => {
            let log_dir = base.join("logs");
            match logging::init(&log_dir) {
                Ok(()) => println!("[logging] initialized at {}", log_dir.display()),
                Err(err) => println!("[logging] init failed (logging disabled): {err}"),
            }
            thumb_cache_dir = Some(base.join("cache").join("thumbnails"));
        }
        Err(err) => println!("[logging] app data dir unavailable (logging disabled): {err}"),
    }
    app.manage(thumbnail::ThumbState { cache_dir: thumb_cache_dir });
    logging::log_line("app", "application start");

    app.run(|app_handle, event| {
        // 应用退出清理（Phase 2C-1，D-0024/D-0025）：事件循环退出时，
        // 取消全部在途探测任务并终止/回收其 FFprobe 子进程（有界等待 ≤2s），
        // 防止 Windows 下父进程退出不级联终止而产生的孤儿进程。
        if let tauri::RunEvent::Exit = event {
            let manager = app_handle.state::<probe_lifecycle::ProbeTaskManager>();
            let summary =
                manager.shutdown_all(std::time::Duration::from_secs(2));
            println!(
                "[lifecycle] exit cleanup: cancelled={} reaped={} remaining={} peak={} elapsed_ms={} errors={:?}",
                summary.cancelled, summary.reaped, summary.remaining, summary.peak_running, summary.elapsed_ms, summary.errors
            );
            logging::log_line(
                "lifecycle",
                &format!(
                    "shutdown cleanup cancelled={} reaped={} remaining={} peak={} elapsed_ms={} errors={:?}",
                    summary.cancelled, summary.reaped, summary.remaining, summary.peak_running, summary.elapsed_ms, summary.errors
                ),
            );
        }
    });
}

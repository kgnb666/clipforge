//! Stage 3B：视频转换核心（FFmpeg CLI；MP4/WebM 输出）。
//!
//! 边界与保证：
//! - 仅调用 FFmpeg CLI，全参数 `OsString` 传递，禁止 shell 拼接；
//! - 复用 [`crate::probe_lifecycle::ProbeTaskManager`]：转换子进程同登记，退出被 `shutdown_all` 终止回收；
//! - 错误分类 `CONV_*` 独立，不与 FFPROBE_*/THUMB_* 吞并；
//! - 输出文件：源目录 + `_converted` 后缀（不覆盖源文件），自动避免文件名冲突；
//! - 无新增依赖。

use crate::logging;
use crate::probe_lifecycle::{lock_child, ProbeTask, ProbeTaskManager, ProbeTaskStatus};
use crate::thumbnail::discover_ffmpeg;
use serde::Serialize;
use std::collections::HashMap;
use std::ffi::OsString;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};
use tauri::Emitter;

/// 转换默认硬超时：300 秒（5 分钟；覆盖 3B 测试与一般短视频场景）。
pub const CONV_TIMEOUT_DEFAULT_MS: u64 = 300_000;
/// 超时覆盖上限：600 秒。
pub const CONV_TIMEOUT_OVERRIDE_MAX_MS: u64 = 600_000;
/// 轮询间隔。
const POLL_INTERVAL_MS: u64 = 50;
/// stderr 尾部上限。
const STDERR_TAIL_LIMIT_BYTES: usize = 8 * 1024;

// ---------------- 输出格式 ----------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConversionFormat {
    Mp4,
    WebM,
}

impl ConversionFormat {
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "mp4" => Some(Self::Mp4),
            "webm" => Some(Self::WebM),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Mp4 => "mp4",
            Self::WebM => "webm",
        }
    }

    pub fn extension(self) -> &'static str {
        self.as_str()
    }
}

/// 构造 FFmpeg 转码参数（全 OsString；输入/输出单参数原样传递）。
/// `-progress pipe:1 -nostats`：进度以 key=value 行写入 stdout（供进度条解析），
/// 并关闭默认 stderr 统计行，保证 stderr 只保留真实错误文本。
pub fn build_convert_args(input: &Path, output: &Path, format: ConversionFormat) -> Vec<OsString> {
    let mut args: Vec<OsString> = vec![
        OsString::from("-v"),
        OsString::from("error"),
        OsString::from("-nostats"),
        OsString::from("-progress"),
        OsString::from("pipe:1"),
        OsString::from("-i"),
        input.as_os_str().to_os_string(),
    ];
    match format {
        ConversionFormat::Mp4 => {
            args.extend([
                OsString::from("-c:v"),
                OsString::from("libx264"),
                OsString::from("-preset"),
                OsString::from("veryfast"),
                OsString::from("-crf"),
                OsString::from("23"),
                OsString::from("-c:a"),
                OsString::from("aac"),
                OsString::from("-b:a"),
                OsString::from("128k"),
                OsString::from("-movflags"),
                OsString::from("+faststart"),
            ]);
        }
        ConversionFormat::WebM => {
            args.extend([
                OsString::from("-c:v"),
                OsString::from("libvpx"),
                OsString::from("-b:v"),
                OsString::from("1M"),
                OsString::from("-c:a"),
                OsString::from("libvorbis"),
            ]);
        }
    }
    args.push(OsString::from("-y"));
    args.push(output.as_os_str().to_os_string());
    args
}

/// 计算输出路径：源目录 + `{stem}_converted.{ext}`；冲突自动递增后缀。
pub fn compute_output_path(source: &str, format: ConversionFormat) -> PathBuf {
    let source_path = Path::new(source);
    let stem = source_path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "output".to_string());
    let dir = source_path.parent().unwrap_or(Path::new(".")).to_path_buf();
    let ext = format.extension();
    let mut candidate = dir.join(format!("{}_converted.{}", stem, ext));
    let mut counter = 2;
    while candidate.exists() {
        candidate = dir.join(format!("{}_converted_{}.{}", stem, counter, ext));
        counter += 1;
    }
    candidate
}

// ---------------- 进度（Stage 5） ----------------

/// 进度上报器：总时长（微秒）+ 回调（百分比 0–100）。
#[derive(Clone)]
pub struct ProgressReporter {
    pub duration_us: u64,
    pub sink: Arc<dyn Fn(f64) + Send + Sync>,
}

/// 进度事件负载（WebView 侧 `listen("conv-progress")`）。
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConvProgress {
    pub entry_id: u64,
    pub percent: f64,
}

/// 解析 FFmpeg `-progress` 输出的时间戳行（微秒）。
/// 说明：ffmpeg 的 `out_time_us` 与 `out_time_ms` 语义同为微秒（历史命名），二者等价；
/// 其余键（frame/fps/bitrate/progress=…）与无法解析的行一律返回 None（不猜测）。
pub fn parse_progress_us(line: &str) -> Option<u64> {
    let (key, value) = line.split_once('=')?;
    match key.trim() {
        "out_time_us" | "out_time_ms" => value
            .trim()
            .parse::<i64>()
            .ok()
            .filter(|v| *v >= 0)
            .map(|v| v as u64),
        _ => None,
    }
}

/// 进度百分比：总时长已知（>0）时计算并钳制到 [0,100]；未知总时长返回 None（不显示假进度）。
pub fn progress_percent(current_us: u64, duration_us: u64) -> Option<f64> {
    if duration_us == 0 {
        return None;
    }
    let pct = (current_us as f64 / duration_us as f64) * 100.0;
    Some(pct.clamp(0.0, 100.0))
}

// ---------------- 错误分类 ----------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConversionFailureCode {
    ConvNotFound,
    ConvStartFailed,
    ConvNonZeroExit,
    ConvTimeout,
    ConvIo,
    ConvCancelled,
}

impl ConversionFailureCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ConvNotFound => "CONV_NOT_FOUND",
            Self::ConvStartFailed => "CONV_START_FAILED",
            Self::ConvNonZeroExit => "CONV_NONZERO_EXIT",
            Self::ConvTimeout => "CONV_TIMEOUT",
            Self::ConvIo => "CONV_IO",
            Self::ConvCancelled => "CONV_CANCELLED",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ConversionFailure {
    pub code: ConversionFailureCode,
    pub message: String,
    pub exit_code: Option<i32>,
    pub stderr_tail: Option<String>,
}

// ---------------- 超时 ----------------

pub fn effective_conv_timeout_ms() -> u64 {
    if let Some(raw) = std::env::var_os("CLIPFORGE_TEST_CONV_TIMEOUT_MS") {
        if let Ok(ms) = raw.to_string_lossy().trim().parse::<u64>() {
            if ms > 0 && ms <= CONV_TIMEOUT_OVERRIDE_MAX_MS {
                return ms;
            }
        }
    }
    CONV_TIMEOUT_DEFAULT_MS
}

// ---------------- 状态存储 ----------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConvRecordState {
    Converting,
    Completed,
    Failed,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversionView {
    pub entry_id: u64,
    pub state: String,
    pub format: Option<String>,
    pub output_path: Option<String>,
    pub output_size: Option<u64>,
    pub failure_code: Option<String>,
    pub failure_message: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ConversionRecord {
    state: ConvRecordState,
    format: String,
    output_path: Option<PathBuf>,
    output_size: Option<u64>,
    failure_code: Option<String>,
    failure_message: Option<String>,
}

/// 转换状态存储（Arc 共享，可移入 spawn_blocking）。
#[derive(Debug, Clone, Default)]
pub struct ConversionStore {
    results: Arc<Mutex<HashMap<u64, ConversionRecord>>>,
}

impl ConversionStore {
    fn lock(&self) -> MutexGuard<'_, HashMap<u64, ConversionRecord>> {
        self.results
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub fn set_converting(&self, entry_id: u64, format: &str) {
        self.lock().insert(
            entry_id,
            ConversionRecord {
                state: ConvRecordState::Converting,
                format: format.to_string(),
                output_path: None,
                output_size: None,
                failure_code: None,
                failure_message: None,
            },
        );
    }

    pub fn set_finished(&self, entry_id: u64, record: ConversionRecord) {
        self.lock().insert(entry_id, record);
    }

    /// 该条目最近一次成功输出的路径（供"打开所在文件夹"；仅接受条目 ID，不暴露任意路径）。
    pub fn output_path_of(&self, entry_id: u64) -> Option<PathBuf> {
        self.lock().get(&entry_id).and_then(|r| r.output_path.clone())
    }

    pub fn all(&self) -> Vec<ConversionView> {
        let mut items: Vec<(u64, ConversionRecord)> =
            self.lock().iter().map(|(k, v)| (*k, v.clone())).collect();
        items.sort_by_key(|(k, _)| *k);
        items
            .into_iter()
            .map(|(id, r)| ConversionView {
                entry_id: id,
                state: match r.state {
                    ConvRecordState::Converting => "converting".to_string(),
                    ConvRecordState::Completed => "completed".to_string(),
                    ConvRecordState::Failed => "failed".to_string(),
                },
                format: Some(r.format),
                output_path: r.output_path.map(|p| p.to_string_lossy().into_owned()),
                output_size: r.output_size,
                failure_code: r.failure_code,
                failure_message: r.failure_message,
            })
            .collect()
    }
}

// ---------------- FFmpeg 执行 ----------------

fn stderr_tail(bytes: &[u8]) -> Option<String> {
    let tail = if bytes.len() > STDERR_TAIL_LIMIT_BYTES {
        &bytes[bytes.len() - STDERR_TAIL_LIMIT_BYTES..]
    } else {
        bytes
    };
    let text = String::from_utf8_lossy(tail).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

fn run_conversion(
    tool: &Path,
    input: &Path,
    output: &Path,
    format: ConversionFormat,
    timeout_ms: u64,
    task: &ProbeTask,
    progress: Option<&ProgressReporter>,
) -> Result<u64, ConversionFailure> {
    let started = Instant::now();
    let mut child = Command::new(tool)
        .args(build_convert_args(input, output, format))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| ConversionFailure {
            code: ConversionFailureCode::ConvStartFailed,
            message: format!(
                "无法启动 FFmpeg（系统错误 {}）：{err}",
                err.raw_os_error().unwrap_or(0)
            ),
            exit_code: None,
            stderr_tail: None,
        })?;

    let stdout_pipe = child.stdout.take().expect("stdout piped");
    let stderr_pipe = child.stderr.take().expect("stderr piped");
    let progress_owned = progress.cloned();
    let stdout_reader = std::thread::spawn(move || {
        use std::io::BufRead;
        let mut reader = std::io::BufReader::new(stdout_pipe);
        let mut buf = Vec::new();
        loop {
            buf.clear();
            match reader.read_until(b'\n', &mut buf) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    if let Some(reporter) = progress_owned.as_ref() {
                        let line = String::from_utf8_lossy(&buf);
                        if let Some(us) = parse_progress_us(line.trim()) {
                            if let Some(pct) = progress_percent(us, reporter.duration_us) {
                                (reporter.sink)(pct);
                            }
                        }
                    }
                }
            }
        }
    });
    let stderr_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = { let mut p = stderr_pipe; p.read_to_end(&mut buf) };
        buf
    });

    let child_slot = task.child.clone();
    {
        let mut slot = lock_child(&child_slot);
        *slot = Some(child);
    }
    task.set_status(ProbeTaskStatus::Running);

    enum Outcome {
        Finished(std::process::ExitStatus),
        TimedOut,
        Cancelled,
    }

    let deadline = Duration::from_millis(timeout_ms);
    let outcome = loop {
        if task.cancel.is_cancelled() {
            break Outcome::Cancelled;
        }
        {
            let mut slot = lock_child(&child_slot);
            match slot.as_mut() {
                Some(c) => match c.try_wait() {
                    Ok(Some(status)) => break Outcome::Finished(status),
                    Ok(None) => {
                        if started.elapsed() >= deadline {
                            break Outcome::TimedOut;
                        }
                    }
                    Err(err) => {
                        let taken = slot.take();
                        drop(slot);
                        if let Some(mut c) = taken {
                            let _ = c.kill();
                            let _ = c.wait();
                        }
                        let _ = stdout_reader.join();
                        let _ = stderr_reader.join();
                        return Err(ConversionFailure {
                            code: ConversionFailureCode::ConvStartFailed,
                            message: format!("等待 FFmpeg 进程失败：{err}"),
                            exit_code: None,
                            stderr_tail: None,
                        });
                    }
                },
                None => break Outcome::Cancelled,
            }
        }
        std::thread::sleep(Duration::from_millis(POLL_INTERVAL_MS));
    };

    match outcome {
        Outcome::Finished(status) => {
            {
                let mut slot = lock_child(&child_slot);
                slot.take();
            }
            let stderr = stderr_reader.join().unwrap_or_default();
            let _ = stdout_reader.join();
            if !status.success() {
                let reason = String::from_utf8_lossy(&stderr);
                let first_line = reason.lines().map(str::trim).find(|l| !l.is_empty());
                let _ = std::fs::remove_file(output);
                return Err(ConversionFailure {
                    code: ConversionFailureCode::ConvNonZeroExit,
                    message: match first_line {
                        Some(r) => format!("FFmpeg 以非零退出码结束（{}）：{r}", status.code().unwrap_or(-1)),
                        None => format!("FFmpeg 以非零退出码结束（{}）", status.code().unwrap_or(-1)),
                    },
                    exit_code: status.code(),
                    stderr_tail: stderr_tail(&stderr),
                });
            }
            match std::fs::metadata(output) {
                Ok(md) if md.len() > 0 => Ok(md.len()),
                _ => {
                    let _ = std::fs::remove_file(output);
                    Err(ConversionFailure {
                        code: ConversionFailureCode::ConvIo,
                        message: "FFmpeg 成功退出但未产生有效输出文件".to_string(),
                        exit_code: Some(0),
                        stderr_tail: stderr_tail(&stderr),
                    })
                }
            }
        }
        Outcome::TimedOut => {
            let taken = lock_child(&child_slot).take();
            let elapsed_ms = started.elapsed().as_millis();
            let mut message = format!(
                "FFmpeg 转换超时（>{timeout_ms} ms，实际约 {elapsed_ms} ms），已终止子进程"
            );
            if let Some(mut c) = taken {
                if let Err(err) = c.kill() {
                    message.push_str(&format!("；终止子进程时出现错误：{err}"));
                }
                if c.wait().is_err() {
                    message.push_str("；回收子进程等待失败");
                }
            }
            let _ = stdout_reader.join();
            let _ = stderr_reader.join();
            let _ = std::fs::remove_file(output);
            Err(ConversionFailure {
                code: ConversionFailureCode::ConvTimeout,
                message,
                exit_code: None,
                stderr_tail: None,
            })
        }
        Outcome::Cancelled => {
            let taken = lock_child(&child_slot).take();
            if let Some(mut c) = taken {
                let _ = c.kill();
                let _ = c.wait();
            }
            let _ = stdout_reader.join();
            let _ = stderr_reader.join();
            let _ = std::fs::remove_file(output);
            Err(ConversionFailure {
                code: ConversionFailureCode::ConvCancelled,
                message: "转换已取消（应用退出或任务被取消）".to_string(),
                exit_code: None,
                stderr_tail: None,
            })
        }
    }
}

// ---------------- Tauri 命令 ----------------

fn log_conv(event: &str, entry_id: u64, detail: &str) {
    logging::log_line("lifecycle", &format!("conv {event} entry_id={entry_id}{detail}"));
}

fn conv_view(entry_id: u64, format: &str, result: &Result<u64, ConversionFailure>, output: &Path) -> ConversionView {
    let (state, failure_code, failure_message, output_size) = match result {
        Ok(size) => ("completed", None, None, Some(*size)),
        Err(f) => ("failed", Some(f.code.as_str().to_string()), Some(f.message.clone()), None),
    };
    ConversionView {
        entry_id,
        state: state.to_string(),
        format: Some(format.to_string()),
        output_path: Some(output.to_string_lossy().into_owned()),
        output_size,
        failure_code,
        failure_message,
    }
}

/// 为指定条目启动视频转换（阻塞至完成；生命周期经 ProbeTaskManager 登记）。
#[tauri::command]
pub async fn convert_video(
    app: tauri::AppHandle,
    import_state: tauri::State<'_, crate::import::ImportState>,
    probe_state: tauri::State<'_, crate::probe::ProbeStateStore>,
    task_manager: tauri::State<'_, ProbeTaskManager>,
    conv_store: tauri::State<'_, ConversionStore>,
    entry_id: u64,
    format: String,
) -> Result<ConversionView, String> {
    let fmt = ConversionFormat::from_str(&format)
        .ok_or_else(|| format!("不支持的输出格式：{format}"))?;

    let entry = import_state
        .list_entries()
        .into_iter()
        .find(|e| e.id == entry_id)
        .ok_or_else(|| format!("条目 {entry_id} 不存在"))?;
    if entry.status != crate::import::EntryStatus::Ready {
        return Err("该条目未通过导入校验，无法转换".to_string());
    }
    let probe_record = probe_state
        .cached(entry_id)
        .ok_or_else(|| "请先完成元数据解析".to_string())?;
    if let crate::probe::ProbeState::Failed(f) = &probe_record.state {
        return Err(format!("元数据解析失败（{}），无法转换", f.code.as_str()));
    }

    let output = compute_output_path(&entry.path, fmt);

    if !probe_state.begin(entry_id) {
        return Err("该条目正在解析中".to_string());
    }

    conv_store.set_converting(entry_id, fmt.as_str());

    let input_path = PathBuf::from(&entry.path);
    let timeout_ms = effective_conv_timeout_ms();
    let manager: ProbeTaskManager = task_manager.clone_shared();
    let task = manager.register(entry_id);
    let store_clone: ConversionStore = conv_store.inner().clone();
    let fmt_str = fmt.as_str().to_string();
    let output_for_closure = output.clone();

    // 进度（Stage 5）：仅当元数据给出有效总时长时启用（未知时长不显示假进度）。
    let duration_us = match &probe_record.state {
        crate::probe::ProbeState::Ready(meta) => meta
            .duration_secs
            .map(|s| (s.max(0.0) * 1_000_000.0) as u64)
            .filter(|v| *v > 0),
        _ => None,
    };
    let progress = duration_us.map(|dur| ProgressReporter {
        duration_us: dur,
        sink: {
            let app = app.clone();
            Arc::new(move |pct: f64| {
                let _ = app.emit(
                    "conv-progress",
                    ConvProgress { entry_id, percent: pct },
                );
            })
        },
    });
    if progress.is_some() {
        let _ = app.emit(
            "conv-progress",
            ConvProgress { entry_id, percent: 0.0 },
        );
    }

    log_conv("register", entry_id, &format!(" format={}", fmt.as_str()));

    let probed = tauri::async_runtime::spawn_blocking(move || {
        let tool: PathBuf = match discover_ffmpeg() {
            Some(t) => t.path,
            None => {
                log_conv("failed", entry_id, " code=CONV_NOT_FOUND");
                store_clone.set_finished(entry_id, ConversionRecord {
                    state: ConvRecordState::Failed,
                    format: fmt_str.clone(),
                    output_path: None,
                    output_size: None,
                    failure_code: Some(ConversionFailureCode::ConvNotFound.as_str().to_string()),
                    failure_message: Some("未发现可用的 FFmpeg（请安装 FFmpeg）".to_string()),
                });
                return (Err(ConversionFailure {
                    code: ConversionFailureCode::ConvNotFound,
                    message: "未发现可用的 FFmpeg（请安装 FFmpeg 或在后续阶段于设置中指定路径）".to_string(),
                    exit_code: None,
                    stderr_tail: None,
                }), output_for_closure);
            }
        };
        log_conv("start", entry_id, "");
        let result = run_conversion(
            &tool,
            &input_path,
            &output_for_closure,
            fmt,
            timeout_ms,
            &task,
            progress.as_ref(),
        );
        match &result {
            Ok(size) => log_conv("complete", entry_id, &format!(" output_size={size}")),
            Err(f) => log_conv("failed", entry_id, &format!(" code={}", f.code.as_str())),
        }
        (result, output_for_closure)
    })
    .await;

    let _ = manager.take_finished(entry_id);

    let (result, output_path) = match probed {
        Ok(pair) => pair,
        Err(err) => {
            probe_state.abort(entry_id);
            conv_store.set_finished(entry_id, ConversionRecord {
                state: ConvRecordState::Failed,
                format: fmt.as_str().to_string(),
                output_path: None,
                output_size: None,
                failure_code: None,
                failure_message: Some(format!("调度失败：{err}")),
            });
            return Err(format!("转换任务调度失败：{err}"));
        }
    };

    let cancelled = matches!(&result, Err(f) if f.code == ConversionFailureCode::ConvCancelled);
    if cancelled {
        probe_state.abort(entry_id);
        return Err("转换已取消（应用退出）".to_string());
    }

    let record = ConversionRecord {
        state: if result.is_ok() { ConvRecordState::Completed } else { ConvRecordState::Failed },
        format: fmt.as_str().to_string(),
        output_path: if result.is_ok() { Some(output_path.clone()) } else { None },
        output_size: match result { Ok(size) => Some(size), Err(_) => None },
        failure_code: result.as_ref().err().map(|f| f.code.as_str().to_string()),
        failure_message: result.as_ref().err().map(|f| f.message.clone()),
    };
    conv_store.set_finished(entry_id, record);
    probe_state.abort(entry_id);

    Ok(conv_view(entry_id, fmt.as_str(), &result, &output_path))
}

/// 返回全部转换结果（供页面挂载恢复状态）。
#[tauri::command]
pub fn list_conversion_results(conv_store: tauri::State<'_, ConversionStore>) -> Vec<ConversionView> {
    conv_store.all()
}

/// 打开该条目最近一次转换输出所在的文件夹（资源管理器 `/select`）。
/// 仅接受条目 ID——路径取自转换结果存储（WebView 无法指定任意路径）；
/// explorer 以 `/select,<path>` 单参数调用（路径含空格/逗号不受影响）。
#[tauri::command]
pub fn reveal_conversion_output(
    conv_store: tauri::State<'_, ConversionStore>,
    entry_id: u64,
) -> Result<String, String> {
    let path = conv_store
        .output_path_of(entry_id)
        .ok_or_else(|| "该条目暂无转换输出".to_string())?;
    if !path.exists() {
        return Err(format!("输出文件不存在：{}", path.display()));
    }
    std::process::Command::new("explorer")
        .arg(format!("/select,{}", path.display()))
        .spawn()
        .map_err(|err| format!("无法打开资源管理器：{err}"))?;
    logging::log_line(
        "lifecycle",
        &format!("conv reveal entry_id={entry_id}"),
    );
    Ok(path.to_string_lossy().into_owned())
}

// ---------------- 单元测试（Stage 5 补充：此前 converter.rs 无单测） ----------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn convert_args_mp4_contain_expected_flags_and_raw_paths() {
        let input = Path::new("D:/素材 目录 & qa/输入 视频'1.mp4");
        let output = Path::new("D:/素材 目录 & qa/输入 视频'1_converted.mp4");
        let args = build_convert_args(input, output, ConversionFormat::Mp4);
        let strs: Vec<String> = args.iter().map(|a| a.to_string_lossy().into_owned()).collect();
        assert_eq!(strs[0], "-v");
        assert!(strs.contains(&"-nostats".to_string()));
        assert!(strs.contains(&"-progress".to_string()));
        assert!(strs.contains(&"pipe:1".to_string()));
        assert!(strs.windows(2).any(|w| w == ["-c:v", "libx264"]));
        assert!(strs.windows(2).any(|w| w == ["-crf", "23"]));
        assert!(strs.windows(2).any(|w| w == ["-movflags", "+faststart"]));
        // 路径原样单参数传递（不经 shell；空格/&/'/中文均不受影响）
        assert!(strs.contains(&input.to_string_lossy().into_owned()));
        assert_eq!(strs[strs.len() - 1], output.to_string_lossy());
        assert_eq!(strs[strs.len() - 2], "-y");
    }

    #[test]
    fn convert_args_webm_use_libvpx_libvorbis() {
        let args = build_convert_args(
            Path::new("in.webm"),
            Path::new("out.webm"),
            ConversionFormat::WebM,
        );
        let strs: Vec<String> = args.iter().map(|a| a.to_string_lossy().into_owned()).collect();
        assert!(strs.windows(2).any(|w| w == ["-c:v", "libvpx"]));
        assert!(strs.windows(2).any(|w| w == ["-c:a", "libvorbis"]));
        assert!(!strs.contains(&"libx264".to_string()));
    }

    #[test]
    fn conversion_format_from_str_round_trip() {
        assert_eq!(ConversionFormat::from_str("MP4"), Some(ConversionFormat::Mp4));
        assert_eq!(ConversionFormat::from_str("webm"), Some(ConversionFormat::WebM));
        assert_eq!(ConversionFormat::from_str("mkv"), None);
        assert_eq!(ConversionFormat::Mp4.as_str(), "mp4");
        assert_eq!(ConversionFormat::WebM.extension(), "webm");
    }

    #[test]
    fn compute_output_path_increments_on_conflict_and_keeps_source_dir() {
        let dir = std::env::temp_dir().join(format!("clipforge-conv-path-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let src = dir.join("样本 视频 #1.mp4");
        std::fs::write(&src, b"x").unwrap();
        let src_str = src.to_string_lossy().into_owned();

        let p1 = compute_output_path(&src_str, ConversionFormat::Mp4);
        assert_eq!(p1.parent().unwrap(), dir.as_path());
        assert_eq!(p1.file_name().unwrap().to_string_lossy(), "样本 视频 #1_converted.mp4");
        assert!(!p1.exists());

        std::fs::write(&p1, b"y").unwrap();
        let p2 = compute_output_path(&src_str, ConversionFormat::Mp4);
        assert_eq!(p2.file_name().unwrap().to_string_lossy(), "样本 视频 #1_converted_2.mp4");
        std::fs::write(&p2, b"z").unwrap();
        let p3 = compute_output_path(&src_str, ConversionFormat::WebM);
        assert_eq!(p3.file_name().unwrap().to_string_lossy(), "样本 视频 #1_converted.webm");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn parse_progress_us_reads_time_keys_and_ignores_others() {
        assert_eq!(parse_progress_us("out_time_us=1234567"), Some(1_234_567));
        assert_eq!(parse_progress_us("out_time_ms=2000000"), Some(2_000_000)); // 语义同为微秒
        assert_eq!(parse_progress_us("frame=42"), None);
        assert_eq!(parse_progress_us("progress=continue"), None);
        assert_eq!(parse_progress_us("out_time_us=-9223372036854775807"), None); // 启动初期负值 → 忽略
        assert_eq!(parse_progress_us("out_time_us=abc"), None);
        assert_eq!(parse_progress_us("no_equals_sign"), None);
    }

    #[test]
    fn progress_percent_clamps_and_requires_duration() {
        assert_eq!(progress_percent(0, 5_000_000), Some(0.0));
        assert_eq!(progress_percent(2_500_000, 5_000_000), Some(50.0));
        assert_eq!(progress_percent(6_000_000, 5_000_000), Some(100.0)); // 钳制
        assert_eq!(progress_percent(1_000_000, 0), None); // 总时长未知 → 不显示假进度
    }

    #[test]
    fn conversion_store_transitions_and_output_lookup() {
        let store = ConversionStore::default();
        store.set_converting(3, "mp4");
        let all = store.all();
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].state, "converting");
        assert_eq!(all[0].format.as_deref(), Some("mp4"));
        assert!(store.output_path_of(3).is_none(), "转换中不应有输出路径");

        store.set_finished(
            3,
            ConversionRecord {
                state: ConvRecordState::Completed,
                format: "mp4".to_string(),
                output_path: Some(PathBuf::from("D:/out/样本_converted.mp4")),
                output_size: Some(123),
                failure_code: None,
                failure_message: None,
            },
        );
        assert_eq!(
            store.output_path_of(3),
            Some(PathBuf::from("D:/out/样本_converted.mp4"))
        );
        assert_eq!(store.all()[0].state, "completed");
        assert_eq!(store.all()[0].output_size, Some(123));
    }
}

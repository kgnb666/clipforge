//! Stage 3A：视频缩略图基础设施（P2C 移交项落地；D-0015/D-0026/D-0027）。
//!
//! 边界与保证：
//! - 仅调用 **FFmpeg CLI**（禁用 API），全参数 `OsString` 传递，禁止 shell 拼接（ARCH-001 精神）；
//! - 复用 [`crate::probe_lifecycle::ProbeTaskManager`]：缩略图子进程同登记，应用退出被
//!   `shutdown_all` 终止回收（2C 冻结行为直接复用，状态机零改动）；
//! - 错误分类 `THUMB_*` 六码独立，不与 `FFPROBE_*` 吞并；
//! - 缓存（D-0015）：目录经应用路径 API 构造；键 = FNV-1a(规范化路径+大小+mtime)；
//!   上限 **200 MiB（209,715,200 字节）**，确定性清理（mtime 最旧先删、保护刚写入文件）；
//!   **单文件超上限：不持久化缓存、仅会话内返回（base64），不得无限重试**（D-0026）；
//! - 展示：JPEG 字节 base64 数据 URL 经既有 IPC 返回——不修改 tauri.conf/capabilities。

use serde::Serialize;
use std::ffi::OsString;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::logging;
use crate::probe_lifecycle::{lock_child, ProbeTask, ProbeTaskStatus};
/// 单次 FFmpeg 提帧默认硬超时（与 FFprobe 同为 30 秒；仅适用于缩略图提取）。
pub const THUMB_TIMEOUT_DEFAULT_MS: u64 = 30_000;
/// 缓存容量上限：200 MiB（D-0015）。
pub const CACHE_CAP_BYTES: u64 = 209_715_200;
/// 超时覆盖环境变量（D-0023 同款规则：仅 Debug 生效由 env 机制天然限定，1..=30000）。
pub const THUMB_TIMEOUT_OVERRIDE_ENV: &str = "CLIPFORGE_TEST_THUMB_TIMEOUT_MS";
/// 轮询间隔。
const POLL_INTERVAL_MS: u64 = 50;
/// stderr 尾部上限（与 probe 一致，8 KiB）。
const STDERR_TAIL_LIMIT_BYTES: usize = 8 * 1024;

// ---------------- 错误分类（THUMB_* 独立，不与 FFPROBE_* 吞并） ----------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThumbFailureCode {
    /// 未发现可用的 FFmpeg
    ThumbNotFound,
    /// 候选存在但无法启动
    ThumbStartFailed,
    /// FFmpeg 以非零退出码结束
    ThumbNonZeroExit,
    /// 超时，已终止并回收子进程
    ThumbTimeout,
    /// 成功退出但输出文件缺失/为空等 IO 异常
    ThumbIo,
    /// 应用退出导致的取消
    ThumbCancelled,
}

impl ThumbFailureCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ThumbNotFound => "THUMB_NOT_FOUND",
            Self::ThumbStartFailed => "THUMB_START_FAILED",
            Self::ThumbNonZeroExit => "THUMB_NONZERO_EXIT",
            Self::ThumbTimeout => "THUMB_TIMEOUT",
            Self::ThumbIo => "THUMB_IO",
            Self::ThumbCancelled => "THUMB_CANCELLED",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ThumbFailure {
    pub code: ThumbFailureCode,
    pub message: String,
    pub exit_code: Option<i32>,
    pub stderr_tail: Option<String>,
}

// ---------------- 发现（FFmpeg；与 probe 同序：覆盖→PATH→WinGet→常见目录） ----------------

#[derive(Debug, Clone, PartialEq)]
pub struct DiscoveredFfmpeg {
    pub path: PathBuf,
}

/// 真实环境发现（缩略图使用；发现顺序与 probe 一致，查找 ffmpeg.exe）。
pub fn discover_ffmpeg() -> Option<DiscoveredFfmpeg> {
    // 1) PATH
    if let Some(path_env) = std::env::var_os("PATH") {
        for entry in path_env.to_string_lossy().split(';') {
            let entry = entry.trim().trim_matches('"');
            if entry.is_empty() {
                continue;
            }
            let candidate = Path::new(entry).join("ffmpeg.exe");
            if candidate.is_file() {
                return Some(DiscoveredFfmpeg { path: candidate });
            }
        }
    }
    // 2) WinGet Packages（名称含 ffmpeg 的包目录，深度 ≤3）
    if let Some(lad) = std::env::var_os("LOCALAPPDATA").map(PathBuf::from) {
        let packages_root = lad.join("Microsoft").join("WinGet").join("Packages");
        if let Some(found) = scan_winget_packages(&packages_root) {
            return Some(DiscoveredFfmpeg { path: found });
        }
    }
    // 3) 常见目录兜底
    for candidate in common_candidates() {
        if candidate.is_file() {
            return Some(DiscoveredFfmpeg { path: candidate });
        }
    }
    None
}

fn scan_winget_packages(packages_root: &Path) -> Option<PathBuf> {
    let entries = std::fs::read_dir(packages_root).ok()?;
    let mut found: Vec<PathBuf> = Vec::new();
    for entry in entries.flatten() {
        let dir = entry.path();
        if !dir.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_lowercase();
        if !name.contains("ffmpeg") {
            continue;
        }
        collect_ffmpeg(&dir, 3, &mut found);
    }
    found.sort();
    found.pop()
}

fn collect_ffmpeg(dir: &Path, depth: u32, out: &mut Vec<PathBuf>) {
    if depth == 0 {
        return;
    }
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_ffmpeg(&path, depth - 1, out);
        } else if path
            .file_name()
            .map(|n| n.to_string_lossy().eq_ignore_ascii_case("ffmpeg.exe"))
            .unwrap_or(false)
        {
            out.push(path);
        }
    }
}

fn common_candidates() -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(lad) = std::env::var_os("LOCALAPPDATA").map(PathBuf::from) {
        candidates.push(lad.join("Microsoft").join("WinGet").join("Links").join("ffmpeg.exe"));
    }
    candidates.push(PathBuf::from("C:\\ffmpeg\\bin\\ffmpeg.exe"));
    candidates.push(PathBuf::from("D:\\ffmpeg\\bin\\ffmpeg.exe"));
    if let Some(up) = std::env::var_os("USERPROFILE").map(PathBuf::from) {
        candidates.push(up.join("scoop").join("shims").join("ffmpeg.exe"));
    }
    candidates.push(PathBuf::from("C:\\tools\\ffmpeg\\bin\\ffmpeg.exe"));
    candidates.push(PathBuf::from("D:\\tools\\ffmpeg\\bin\\ffmpeg.exe"));
    candidates
}

// ---------------- 取帧策略与缓存键 ----------------

/// 取帧策略（P2C-002）：主取 `clamp(10%×duration, 0, max(0, duration−0.5s))`；
/// duration 未知/≤0 → 1s。失败回退序列由调用方按 0.5s → 0s 处理。
pub fn compute_seek_time(duration_secs: Option<f64>) -> f64 {
    match duration_secs {
        Some(d) if d > 0.0 => {
            let primary = 0.1 * d;
            let upper = (d - 0.5).max(0.0);
            primary.clamp(0.0, upper)
        }
        _ => 1.0,
    }
}

/// FNV-1a 64（缓存键用；非加密场景）。
fn fnv1a(data: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for &b in data {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// 缓存键：规范化路径 + 大小 + mtime（纳秒）——源文件变化即失效（D-0015）。
pub fn cache_key(path: &str, size: u64, mtime_nanos: u128) -> String {
    let mut material = Vec::new();
    material.extend_from_slice(path.as_bytes());
    material.extend_from_slice(format!("|size={size}|mtime={mtime_nanos}").as_bytes());
    format!("{:016x}", fnv1a(&material))
}

// ---------------- 缓存容量治理（D-0015：200 MiB + 确定性清理） ----------------

/// 目录内缩略图总字节数（*.jpg，一层）。
pub fn cache_total_bytes(dir: &Path) -> u64 {
    std::fs::read_dir(dir)
        .map(|entries| {
            entries
                .flatten()
                .filter(|e| e.path().extension().map(|x| x == "jpg").unwrap_or(false))
                .filter_map(|e| e.metadata().ok())
                .map(|m| m.len())
                .sum()
        })
        .unwrap_or(0)
}

/// 容量治理：总量超过 `cap` 时按 mtime 最旧先删（确定性），直至 ≤ cap；
/// `protect` 文件（刚写入者）不参与删除；目录/文件缺失等情况静默成功（治理尽力而为）。
/// 返回删除的文件数。
pub fn enforce_cache_limit(dir: &Path, cap: u64, protect: &Path) -> usize {
    let mut evicted = 0usize;
    let Ok(entries) = std::fs::read_dir(dir) else {
        return 0;
    };
    let mut candidates: Vec<(std::time::SystemTime, PathBuf, u64)> = entries
        .flatten()
        .filter(|e| e.path().extension().map(|x| x == "jpg").unwrap_or(false))
        .filter(|e| e.path() != protect)
        .filter_map(|e| {
            let md = e.metadata().ok()?;
            Some((md.modified().ok()?, e.path(), md.len()))
        })
        .collect();
    let protected_size = std::fs::metadata(protect).map(|m| m.len()).unwrap_or(0);
    let mut total = cache_total_bytes(dir);
    if total <= cap {
        return 0;
    }
    candidates.sort_by_key(|(t, _, _)| *t);
    for (_, path, size) in candidates {
        if total <= cap {
            break;
        }
        if std::fs::remove_file(&path).is_ok() {
            total = total.saturating_sub(size);
            evicted += 1;
        }
    }
    let _ = protected_size;
    evicted
}

// ---------------- FFmpeg CLI 执行 ----------------

/// 构造 FFmpeg 提帧参数（全 OsString；输入/输出作为单个参数原样传递，禁止 shell 拼接）。
fn build_thumb_args(input: &Path, output: &Path, seek: f64) -> Vec<OsString> {
    vec![
        OsString::from("-v"),
        OsString::from("error"),
        OsString::from("-ss"),
        OsString::from(format!("{seek:.3}")),
        OsString::from("-i"),
        input.as_os_str().to_os_string(),
        OsString::from("-frames:v"),
        OsString::from("1"),
        OsString::from("-vf"),
        OsString::from("scale=480:-2"),
        OsString::from("-f"),
        OsString::from("image2"),
        OsString::from("-y"),
        output.as_os_str().to_os_string(),
    ]
}

/// 生效超时：合法测试覆盖优先（1..=30000），否则默认 30 秒。
pub fn effective_thumb_timeout_ms() -> u64 {
    if let Some(raw) = std::env::var_os(crate::thumbnail::THUMB_TIMEOUT_OVERRIDE_ENV) {
        if let Ok(ms) = raw.to_string_lossy().trim().parse::<u64>() {
            if ms > 0 && ms <= 30_000 {
                return ms;
            }
        }
    }
    THUMB_TIMEOUT_DEFAULT_MS
}

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

/// 提取失败时的回退序列（P2C-002）：主取帧点失败 → 0.5s → 0s（去重）。
fn seek_attempts(primary: f64) -> Vec<f64> {
    let mut attempts = vec![primary];
    for fallback in [0.5, 0.0] {
        if attempts.iter().all(|a| (a - fallback).abs() >= 0.25) {
            attempts.push(fallback);
        }
    }
    attempts
}

/// 执行一次 FFmpeg 提帧（只读输入；输出写入 `output`）。
/// 超时/取消路径已终止并回收子进程；成功后校验输出存在且非空。
fn generate_thumb_file(
    tool: &Path,
    input: &Path,
    output: &Path,
    seek: f64,
    timeout_ms: u64,
    task: Option<&ProbeTask>,
) -> Result<(), ThumbFailure> {
    let started = Instant::now();
    let mut child = Command::new(tool)
        .args(build_thumb_args(input, output, seek))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| ThumbFailure {
            code: ThumbFailureCode::ThumbStartFailed,
            message: format!(
                "无法启动 FFmpeg（系统错误 {}）：{err}",
                err.raw_os_error().unwrap_or(0)
            ),
            exit_code: None,
            stderr_tail: None,
        })?;

    let stdout_pipe = child.stdout.take().expect("stdout 已设为 piped");
    let stderr_pipe = child.stderr.take().expect("stderr 已设为 piped");
    let stdout_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = { let mut p = stdout_pipe; p.read_to_end(&mut buf) };
        buf
    });
    let stderr_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = { let mut p = stderr_pipe; p.read_to_end(&mut buf) };
        buf
    });

    // 句柄登记：任务存在时与生命周期表共享同一槽位。
    let child_slot = match task {
        Some(t) => t.child.clone(),
        None => std::sync::Arc::new(std::sync::Mutex::new(None)),
    };
    {
        let mut slot = lock_child(&child_slot);
        *slot = Some(child);
    }
    if let Some(t) = task {
        // 生命周期状态：子进程已 spawn 并入槽 → Running（与 probe 同构）。
        t.set_status(ProbeTaskStatus::Running);
    }

    enum Outcome {
        Finished(std::process::ExitStatus),
        TimedOut,
        Cancelled,
    }

    let deadline = Duration::from_millis(timeout_ms);
    let outcome = loop {
        if let Some(t) = task {
            if t.cancel.is_cancelled() {
                break Outcome::Cancelled;
            }
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
                        return Err(ThumbFailure {
                            code: ThumbFailureCode::ThumbStartFailed,
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
                return Err(ThumbFailure {
                    code: ThumbFailureCode::ThumbNonZeroExit,
                    message: match first_line {
                        Some(r) => format!("FFmpeg 以非零退出码结束（{}）：{r}", status.code().unwrap_or(-1)),
                        None => format!("FFmpeg 以非零退出码结束（{}）", status.code().unwrap_or(-1)),
                    },
                    exit_code: status.code(),
                    stderr_tail: stderr_tail(&stderr),
                });
            }
            match std::fs::metadata(output) {
                Ok(md) if md.len() > 0 => Ok(()),
                _ => Err(ThumbFailure {
                    code: ThumbFailureCode::ThumbIo,
                    message: "FFmpeg 成功退出但未产生有效缩略图文件".to_string(),
                    exit_code: Some(0),
                    stderr_tail: stderr_tail(&stderr),
                }),
            }
        }
        Outcome::TimedOut => {
            let taken = lock_child(&child_slot).take();
            let elapsed_ms = started.elapsed().as_millis();
            let mut message = format!(
                "FFmpeg 提帧超时（>{timeout_ms} ms，实际约 {elapsed_ms} ms），已终止子进程"
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
            Err(ThumbFailure {
                code: ThumbFailureCode::ThumbTimeout,
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
            Err(ThumbFailure {
                code: ThumbFailureCode::ThumbCancelled,
                message: "缩略图提取已取消（应用退出或任务被取消）".to_string(),
                exit_code: None,
                stderr_tail: None,
            })
        }
    }
}

// ---------------- 命令层（缓存 + base64 展示） ----------------

/// 缩略图缓存目录托管状态（lib.rs 经应用路径 API 构造；None = 缓存不可用）。
#[derive(Debug, Clone, Default)]
pub struct ThumbState {
    pub cache_dir: Option<PathBuf>,
}

/// 前端视图（serde camelCase；state = "ready" | "failed"）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThumbView {
    pub entry_id: u64,
    pub state: String,
    /// `data:image/jpeg;base64,…`（ready 时存在；缓存命中与新生成同构）
    pub data_url: Option<String>,
    pub failure_code: Option<String>,
    pub failure_message: Option<String>,
    /// 本次是否直接命中磁盘缓存
    pub cache_hit: bool,
}

/// base64 编码（std-only；标准字母表 + padding）。
pub fn base64_encode(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = chunk.get(1).copied().unwrap_or(0) as u32;
        let b2 = chunk.get(2).copied().unwrap_or(0) as u32;
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(ALPHABET[(n >> 18) as usize & 63] as char);
        out.push(ALPHABET[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { ALPHABET[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { ALPHABET[n as usize & 63] as char } else { '=' });
    }
    out
}

fn data_url(bytes: &[u8]) -> String {
    format!("data:image/jpeg;base64,{}", base64_encode(bytes))
}

/// 生命周期日志（缩略图任务；与 probe 六事件同构）。
fn log_thumb(event: &str, entry_id: u64, detail: &str) {
    logging::log_line("lifecycle", &format!("thumb {event} entry_id={entry_id}{detail}"));
}

/// 为指定导入条目生成/读取缩略图（异步、非阻塞；磁盘缓存键含源文件大小+mtime）。
/// `force = true` 忽略缓存重新提取。仅接受条目 ID（路径来自导入登记表）。
///
/// 生命周期：FFmpeg 子进程经 [`ProbeTaskManager`] 登记，退出时由 `shutdown_all` 终止回收。
#[tauri::command]
pub async fn generate_thumbnail(
    import_state: tauri::State<'_, crate::import::ImportState>,
    probe_state: tauri::State<'_, crate::probe::ProbeStateStore>,
    task_manager: tauri::State<'_, crate::probe_lifecycle::ProbeTaskManager>,
    thumb_state: tauri::State<'_, ThumbState>,
    entry_id: u64,
    force: bool,
) -> Result<ThumbView, String> {
    let cache_dir = thumb_state
        .cache_dir
        .clone()
        .ok_or_else(|| "缩略图缓存目录不可用".to_string())?;
    // 缓存目录自愈（ffmpeg 不会创建父目录；首次运行/被清理后自动重建）
    if let Err(err) = std::fs::create_dir_all(&cache_dir) {
        return Err(format!("缩略图缓存目录创建失败：{err}"));
    }
    let entry = import_state
        .list_entries()
        .into_iter()
        .find(|e| e.id == entry_id)
        .ok_or_else(|| format!("条目 {entry_id} 不存在"))?;
    if entry.status != crate::import::EntryStatus::Ready {
        return Err("该条目未通过导入校验，跳过缩略图生成".to_string());
    }

    // 缓存键（源路径 + 大小 + mtime）与缓存命中
    let (size, mtime_nanos) = match std::fs::metadata(&entry.path) {
        Ok(md) => (
            md.len(),
            md.modified()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_nanos())
                .unwrap_or(0),
        ),
        Err(_) => (0, 0),
    };
    let key = cache_key(&entry.path, size, mtime_nanos);
    let cache_path = cache_dir.join(format!("thumb_{key}.jpg"));

    if !force && cache_path.is_file() {
        if let Ok(bytes) = std::fs::read(&cache_path) {
            if !bytes.is_empty() {
                log_thumb("cache hit", entry_id, "");
                return Ok(ThumbView {
                    entry_id,
                    state: "ready".to_string(),
                    data_url: Some(data_url(&bytes)),
                    failure_code: None,
                    failure_message: None,
                    cache_hit: true,
                });
            }
        }
    }

    // 会话内互斥（复用 probe 的 begin/abort；缩略图不写 probe 结果）
    if !probe_state.begin(entry_id) {
        return Err("该条目正在解析中".to_string());
    }

    // 取帧点：优先使用已缓存的探测时长（duration 未知/0 → 1s）
    let duration = match probe_state.cached(entry_id) {
        Some(crate::probe::ProbeRecord { state: crate::probe::ProbeState::Ready(meta), .. }) => meta.duration_secs,
        _ => None,
    };
    let attempts = seek_attempts(compute_seek_time(duration));

    let path = PathBuf::from(&entry.path);
    let timeout_ms = effective_thumb_timeout_ms();
    let out_path_for_closure = cache_path.clone();
    let out_path = cache_path.clone();

    // 登记 + 生命周期日志（与 probe 同构）
    let manager = task_manager.clone_shared();
    let task = manager.register(entry_id);
    log_thumb("register", entry_id, "");

    let probed = tauri::async_runtime::spawn_blocking(move || {
        let mut last: Option<ThumbFailure> = None;
        let mut generated = false;
        // FFmpeg 发现（fs 扫描在阻塞线程执行）；未发现 → THUMB_NOT_FOUND（不回退）
        let tool: Option<PathBuf> = match discover_ffmpeg() {
            Some(t) => Some(t.path),
            None => {
                last = Some(ThumbFailure {
                    code: ThumbFailureCode::ThumbNotFound,
                    message: "未发现可用的 FFmpeg（请安装 FFmpeg 或在后续阶段于设置中指定路径）".to_string(),
                    exit_code: None,
                    stderr_tail: None,
                });
                None
            }
        };
        let attempts: Vec<f64> = if tool.is_some() { attempts } else { Vec::new() };
        for (idx, seek) in attempts.iter().enumerate() {
            let tool = tool.as_ref().expect("attempts 非空则 tool 必存在");
            if task.cancel.is_cancelled() {
                last = Some(ThumbFailure {
                    code: ThumbFailureCode::ThumbCancelled,
                    message: "缩略图提取已取消（应用退出或任务被取消）".to_string(),
                    exit_code: None,
                    stderr_tail: None,
                });
                break;
            }
            if idx == 0 {
                log_thumb("start", entry_id, &format!(" seek={seek:.3}"));
            } else {
                log_thumb("retry seek", entry_id, &format!(" seek={seek:.3}"));
            }
            let _ = std::fs::remove_file(&out_path_for_closure); // 清理上次尝试的残留
            match generate_thumb_file(tool, &path, &out_path_for_closure, *seek, timeout_ms, Some(&task)) {
                Ok(()) => {
                    generated = true;
                    break;
                }
                Err(f) if f.code == ThumbFailureCode::ThumbCancelled => {
                    last = Some(f);
                    break;
                }
                Err(f) => {
                    last = Some(f);
                    // 其余失败也重试回退点（损坏/非媒体在三次尝试后稳定失败）
                }
            }
        }
        if generated {
            log_thumb("complete", entry_id, "");
        } else if let Some(f) = &last {
            let detail = format!(" code={} ", f.code.as_str());
            log_thumb(
                if f.code == ThumbFailureCode::ThumbCancelled { "cancelled" } else { "failed" },
                entry_id,
                &detail,
            );
        }
        (last, generated)
    })
    .await;

    let (last, generated) = match probed {
        Ok(value) => value,
        Err(err) => {
            probe_state.abort(entry_id);
            let _ = manager.take_finished(entry_id);
            return Err(format!("缩略图任务调度失败：{err}"));
        }
    };
    let _ = manager.take_finished(entry_id);

    if !generated {
        probe_state.abort(entry_id);
        // 清理可能的残留/半成品（避免污染缓存）
        let _ = std::fs::remove_file(&out_path);
        let failure = last.unwrap_or(ThumbFailure {
            code: ThumbFailureCode::ThumbIo,
            message: "缩略图生成失败（未知原因）".to_string(),
            exit_code: None,
            stderr_tail: None,
        });
        return Ok(ThumbView {
            entry_id,
            state: "failed".to_string(),
            data_url: None,
            failure_code: Some(failure.code.as_str().to_string()),
            failure_message: Some(failure.message),
            cache_hit: false,
        });
    }

    probe_state.abort(entry_id);

    // 读取并按容量治理（单文件超上限：不持久化、仅会话内返回——D-0026）
    let bytes = std::fs::read(&out_path).map_err(|err| format!("读取缩略图失败：{err}"))?;
    let oversized = bytes.len() as u64 > CACHE_CAP_BYTES;
    if oversized {
        let _ = std::fs::remove_file(&cache_path);
    } else {
        enforce_cache_limit(&cache_dir, CACHE_CAP_BYTES, &cache_path);
    }
    logging::log_line(
        "lifecycle",
        &format!(
            "thumb generated entry_id={entry_id} bytes={} cache_hit=false oversized={oversized}",
            bytes.len()
        ),
    );
    Ok(ThumbView {
        entry_id,
        state: "ready".to_string(),
        data_url: Some(data_url(&bytes)),
        failure_code: None,
        failure_message: None,
        cache_hit: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn seek_time_policy_table() {
        assert_eq!(compute_seek_time(Some(5.0)), 0.5, "10% × 5s");
        assert_eq!(compute_seek_time(Some(100.0)), 10.0, "10% × 100s");
        assert_eq!(compute_seek_time(Some(0.4)), 0.0, "短于 0.5s → clamp 至 0");
        assert_eq!(compute_seek_time(Some(0.0)), 1.0, "duration 0 → 1s");
        assert_eq!(compute_seek_time(None), 1.0, "duration 未知 → 1s");
        assert_eq!(compute_seek_time(Some(2.0)), 0.2);
    }

    #[test]
    fn seek_attempts_dedups_fallbacks() {
        assert_eq!(seek_attempts(3.0), vec![3.0, 0.5, 0.0]);
        // 4s 视频主取 0.4s：0.5s 与主取点相差 <0.25s（重试无意义）被去重，直接回退 0s
        assert_eq!(seek_attempts(0.4), vec![0.4, 0.0]);
        assert_eq!(seek_attempts(0.5), vec![0.5, 0.0], "主取即 0.5 → 不重复");
        // 短视频主取 0 → 0.0 与主取重复被去重，仅尝试 0.5（超出时长将失败并进入错误态）
        assert_eq!(seek_attempts(0.0), vec![0.0, 0.5]);
    }

    #[test]
    fn cache_key_is_deterministic_and_sensitive() {
        let base = cache_key(r"D:\v\a.mkv", 100, 1_000);
        assert_eq!(base, cache_key(r"D:\v\a.mkv", 100, 1_000), "同输入同键");
        assert_ne!(base, cache_key(r"D:\v\a.mkv", 101, 1_000), "大小变化 → 键变化");
        assert_ne!(base, cache_key(r"D:\v\a.mkv", 100, 2_000), "mtime 变化 → 键变化");
        assert_ne!(base, cache_key(r"D:\v\b.mkv", 100, 1_000), "路径变化 → 键变化");
        assert_eq!(base.len(), 16, "64-bit FNV 十六进制");
    }

    #[test]
    fn build_args_passes_paths_as_single_osstrings() {
        let input = Path::new(r"D:\vids\中文 空格 & 路径's.mp4");
        let output = Path::new(r"D:\cache\thumb_x.jpg");
        let args = build_thumb_args(input, output, 0.5);
        assert_eq!(args[0], OsString::from("-v"));
        assert_eq!(args[2], OsString::from("-ss"));
        assert_eq!(args[3], OsString::from("0.500"));
        assert_eq!(args[5], input.as_os_str().to_os_string(), "输入原样单参数");
        assert_eq!(args[13], output.as_os_str().to_os_string(), "输出原样单参数");
        assert_eq!(args.len(), 14);
    }

    #[test]
    fn enforce_cache_limit_evicts_oldest_and_protects_new_file() {
        let dir = std::env::temp_dir().join(format!("clipforge-thumb-cap-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let mk = |name: &str| {
            let p = dir.join(name);
            fs::write(&p, vec![b'x'; 100]).unwrap();
            p
        };
        let a = mk("a.jpg");
        std::thread::sleep(std::time::Duration::from_millis(20));
        let b = mk("b.jpg");
        std::thread::sleep(std::time::Duration::from_millis(20));
        let c = mk("c.jpg");
        // 总量 300 > cap 250 → 最旧（a）被清除；protect=c 不参与删除
        let evicted = enforce_cache_limit(&dir, 250, &c);
        assert_eq!(evicted, 1);
        assert!(!a.exists(), "最旧缩略图应被清理");
        assert!(b.exists() && c.exists());
        assert!(cache_total_bytes(&dir) <= 250);
        // 容量已达标 → 幂等
        assert_eq!(enforce_cache_limit(&dir, 250, &c), 0);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn base64_known_vectors() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_encode(b"f"), "Zg==");
        assert_eq!(base64_encode(b"fo"), "Zm8=");
        assert_eq!(base64_encode(b"foo"), "Zm9v");
        assert_eq!(base64_encode(b"foob"), "Zm9vYg==");
        assert_eq!(base64_encode(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn thumb_timeout_override_bounds() {
        // 无覆盖 → 默认 30s
        if std::env::var_os(THUMB_TIMEOUT_OVERRIDE_ENV).is_none() {
            assert_eq!(effective_thumb_timeout_ms(), THUMB_TIMEOUT_DEFAULT_MS);
            assert_eq!(THUMB_TIMEOUT_DEFAULT_MS, 30_000);
        }
    }
}

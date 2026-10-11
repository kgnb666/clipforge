//! Phase 2B-1：FFprobe 探测基础设施（发现 / 安全参数 / 执行 / 超时终止回收 / JSON 解析 / 失败分类）。
//!
//! 边界（严格对应 `docs/requirements-and-acceptance.md` v1.2 与 D-0011 / D-0014 / ARCH-001/002/005）：
//! - 元数据**仅**来自 `ffprobe -v error -print_format json -show_format -show_streams <file>` 的结构化输出（P2B-007）；
//!   失败分类只使用"退出码 + stderr 尾部"作为诊断信息，**不用于字段推断**；
//! - 所有参数经 `OsString` 传递，禁止 shell 字符串拼接（ARCH-001）；输入文件按只读使用（ARCH-003）；
//! - 单次调用默认 30 秒硬超时，超时后终止并回收子进程（D-0014；仅适用于 FFprobe 元数据调用）；
//! - 失败分类互不吞并：ToolNotFound / ToolStartFailed / NonZeroExit / Timeout / ParseFailed（P2D-005 / P2D-013）；
//! - 无音轨与"有音轨但编码未知"使用不同语义（`has_audio` 标志与 `audio_codec` 缺失，P2B-006/008）。

use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::ffi::{OsStr, OsString};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::logging;
use crate::probe_lifecycle::{lock_child, ProbeTask, ProbeTaskManager, ProbeTaskStatus};

/// 单次 FFprobe 调用默认硬超时（D-0014：30 秒）。
pub const PROBE_TIMEOUT_DEFAULT_MS: u64 = 30_000;
/// stderr 尾部保留上限（ARCH-004 / D-0020：8 KiB = 8,192 字节）。
pub const STDERR_TAIL_LIMIT_BYTES: usize = 8 * 1024;
/// 超时轮询间隔。
const POLL_INTERVAL_MS: u64 = 50;

/// 失败分类码（互不吞并；与导入核心的 NOT_FOUND / PERMISSION_DENIED 等码不重叠）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProbeFailureCode {
    /// 未发现可用的 FFprobe（发现阶段无候选；含测试覆盖指向不存在的文件）
    ToolNotFound,
    /// 候选存在但无法启动（spawn 失败，如不可执行文件）
    ToolStartFailed,
    /// 已启动但以非零退出码结束
    NonZeroExit,
    /// 超过硬超时，已终止并回收子进程
    Timeout,
    /// 退出码为 0 但输出无法按 JSON 解析
    ParseFailed,
    /// 解析成功但文件中没有可用视频流（视频工具场景下的非视频媒体；P2B-011）
    MediaUnsupported,
    /// 探测被取消（应用退出清理；Phase 2C-1 生命周期修复新增）
    Cancelled,
}

impl ProbeFailureCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ToolNotFound => "FFPROBE_NOT_FOUND",
            Self::ToolStartFailed => "FFPROBE_START_FAILED",
            Self::NonZeroExit => "FFPROBE_NONZERO_EXIT",
            Self::Timeout => "FFPROBE_TIMEOUT",
            Self::ParseFailed => "FFPROBE_PARSE_FAILED",
            Self::MediaUnsupported => "MEDIA_UNSUPPORTED",
            Self::Cancelled => "FFPROBE_CANCELLED",
        }
    }
}

/// 失败详情（含诊断信息；stderr 尾部已按上限截断）。
#[derive(Debug, Clone, PartialEq)]
pub struct ProbeFailure {
    pub code: ProbeFailureCode,
    pub message: String,
    pub exit_code: Option<i32>,
    pub stderr_tail: Option<String>,
}

/// FFprobe 结构化输出解析结果（缺失字段一律为 None，不猜测、不以 0 代替）。
#[derive(Debug, Clone, PartialEq)]
pub struct ProbeMetadata {
    /// 容器时长（秒，原文数值；展示层按 D-0017 floor 到秒）
    pub duration_secs: Option<f64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub video_codec: Option<String>,
    /// 是否存在音频流——与 `audio_codec` 的缺失语义区分：false=无音轨；true+None=有音轨但编码未知。
    pub has_audio: bool,
    pub audio_codec: Option<String>,
    /// 容器格式（ffprobe `format.format_name` 原值）
    pub container: Option<String>,
}

/// 发现命中的策略（用于记录与审计）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToolStrategy {
    TestOverride,
    PathEnv,
    WingetPackages,
    CommonDirs,
}

impl ToolStrategy {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::TestOverride => "test_override",
            Self::PathEnv => "path_env",
            Self::WingetPackages => "winget_packages",
            Self::CommonDirs => "common_dirs",
        }
    }
}

/// 发现结果：可执行文件路径 + 命中的策略。
#[derive(Debug, Clone, PartialEq)]
pub struct DiscoveredTool {
    pub path: PathBuf,
    pub strategy: ToolStrategy,
}

/// 真实环境发现（顺序：测试覆盖[仅 Debug] → PATH → WinGet Packages → 常见目录；遵守 D-0011，设置路径 UI 留待后续阶段）。
pub fn discover_ffprobe() -> Option<DiscoveredTool> {
    #[cfg(debug_assertions)]
    let override_path = crate::test_overrides::ffprobe_override_path();
    #[cfg(not(debug_assertions))]
    let override_path: Option<PathBuf> = None;

    let local_app_data = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
    let user_profile = std::env::var_os("USERPROFILE").map(PathBuf::from);
    discover_with(
        std::env::var_os("PATH").as_deref(),
        local_app_data.as_deref(),
        user_profile.as_deref(),
        override_path,
    )
}

/// 可测的发现实现（搜索来源全部作为参数注入）。
pub(crate) fn discover_with(
    path_env: Option<&OsStr>,
    local_app_data: Option<&Path>,
    user_profile: Option<&Path>,
    override_path: Option<PathBuf>,
) -> Option<DiscoveredTool> {
    // 1) 测试覆盖（仅 Debug 传入）：覆盖值为最终答案，不被发现回退掩盖（保证"不存在"场景可复现）。
    if let Some(p) = override_path {
        return if p.is_file() {
            Some(DiscoveredTool { path: p, strategy: ToolStrategy::TestOverride })
        } else {
            None
        };
    }
    // 2) PATH 查找
    if let Some(path_env) = path_env {
        for entry in path_env.to_string_lossy().split(';') {
            let entry = entry.trim().trim_matches('"');
            if entry.is_empty() {
                continue;
            }
            let candidate = Path::new(entry).join("ffprobe.exe");
            if candidate.is_file() {
                return Some(DiscoveredTool { path: candidate, strategy: ToolStrategy::PathEnv });
            }
        }
    }
    // 3) WinGet Packages 常见安装目录
    if let Some(lad) = local_app_data {
        let packages_root = lad.join("Microsoft").join("WinGet").join("Packages");
        if let Some(found) = scan_winget_packages(&packages_root) {
            return Some(DiscoveredTool { path: found, strategy: ToolStrategy::WingetPackages });
        }
    }
    // 4) 常见目录兜底
    for candidate in common_candidates(local_app_data, user_profile) {
        if candidate.is_file() {
            return Some(DiscoveredTool { path: candidate, strategy: ToolStrategy::CommonDirs });
        }
    }
    None
}

/// 在 `Packages` 下扫描名称含 "FFmpeg" 的包目录，深度 ≤3 查找 `ffprobe.exe`；多个候选按路径排序后取字典序最大者。
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
        collect_ffprobe(&dir, 3, &mut found);
    }
    found.sort();
    found.pop()
}

fn collect_ffprobe(dir: &Path, depth: u32, out: &mut Vec<PathBuf>) {
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
            collect_ffprobe(&path, depth - 1, out);
        } else if path
            .file_name()
            .map(|n| n.to_string_lossy().eq_ignore_ascii_case("ffprobe.exe"))
            .unwrap_or(false)
        {
            out.push(path);
        }
    }
}

fn common_candidates(local_app_data: Option<&Path>, user_profile: Option<&Path>) -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(lad) = local_app_data {
        candidates.push(lad.join("Microsoft").join("WinGet").join("Links").join("ffprobe.exe"));
    }
    candidates.push(PathBuf::from("C:\\ffmpeg\\bin\\ffprobe.exe"));
    candidates.push(PathBuf::from("D:\\ffmpeg\\bin\\ffprobe.exe"));
    if let Some(up) = user_profile {
        candidates.push(up.join("scoop").join("shims").join("ffprobe.exe"));
    }
    candidates.push(PathBuf::from("C:\\tools\\ffmpeg\\bin\\ffprobe.exe"));
    candidates.push(PathBuf::from("D:\\tools\\ffmpeg\\bin\\ffprobe.exe"));
    candidates
}

/// 生效超时：合法测试覆盖优先（仅 Debug），否则默认 30 秒。
pub fn effective_timeout_ms() -> u64 {
    #[cfg(debug_assertions)]
    {
        if let Some(ms) = crate::test_overrides::timeout_override_ms() {
            return ms;
        }
    }
    PROBE_TIMEOUT_DEFAULT_MS
}

/// 构造 FFprobe 参数（全部为 `OsString`；输入路径作为**单个参数**原样传递，任何字符都不会被解释——ARCH-001）。
fn build_probe_args(input: &Path) -> Vec<OsString> {
    vec![
        OsString::from("-v"),
        OsString::from("error"),
        OsString::from("-print_format"),
        OsString::from("json"),
        OsString::from("-show_format"),
        OsString::from("-show_streams"),
        input.as_os_str().to_os_string(),
    ]
}

/// 经发现流程执行一次探测（2B-2 起的常规入口）：
/// 未发现工具时不回退、不猜测，直接返回 `ToolNotFound` 分类失败。
pub fn probe_with_discovery(input: &Path, timeout_ms: u64) -> Result<ProbeMetadata, ProbeFailure> {
    match discover_ffprobe() {
        Some(tool) => probe_file(&tool.path, input, timeout_ms).and_then(ensure_video_stream),
        None => Err(ProbeFailure {
            code: ProbeFailureCode::ToolNotFound,
            message: "未发现可用的 FFprobe（请安装 FFmpeg 或在后续阶段于设置中指定路径）".to_string(),
            exit_code: None,
            stderr_tail: None,
        }),
    }
}

/// [`probe_with_discovery`] 的生命周期管理版本（Phase 2C-1）：
/// 探测任务登记进 [`ProbeTaskManager`]，应用退出时由 `shutdown_all` 终止并回收。
/// 终态按**最终**结果推进（含 `ensure_video_stream` 的 MEDIA_UNSUPPORTED → Failed）。
pub fn probe_with_discovery_managed(
    input: &Path,
    timeout_ms: u64,
    manager: &ProbeTaskManager,
    entry_id: u64,
) -> Result<ProbeMetadata, ProbeFailure> {
    match discover_ffprobe() {
        Some(tool) => {
            let task = manager.register(entry_id);
            logging::log_line("lifecycle", &format!("task register entry_id={entry_id}"));
            let result = probe_file_managed_task(&tool.path, input, timeout_ms, task.clone())
                .and_then(ensure_video_stream);
            task.set_status(match &result {
                Ok(_) => ProbeTaskStatus::Completed,
                Err(failure) => {
                    if failure.code == ProbeFailureCode::Cancelled {
                        ProbeTaskStatus::Cancelled
                    } else {
                        ProbeTaskStatus::Failed
                    }
                }
            });
            let _ = manager.take_finished(entry_id);
            log_terminal(entry_id, &result);
            result
        }
        None => Err(ProbeFailure {
            code: ProbeFailureCode::ToolNotFound,
            message: "未发现可用的 FFprobe（请安装 FFmpeg 或在后续阶段于设置中指定路径）".to_string(),
            exit_code: None,
            stderr_tail: None,
        }),
    }
}

/// 执行一次 FFprobe 调用（只读；不纳入生命周期管理——供既有测试与无管理场景使用）。
///
/// - 成功：`Ok(ProbeMetadata)`（结构化 JSON 解析结果）；
/// - 失败：`Err(ProbeFailure)`，分类码见 [`ProbeFailureCode`]；超时路径已终止并回收子进程。
pub fn probe_file(tool: &Path, input: &Path, timeout_ms: u64) -> Result<ProbeMetadata, ProbeFailure> {
    probe_file_inner(tool, input, timeout_ms, None)
}

/// 执行一次**纳入生命周期管理**的 FFprobe 调用（Phase 2C-1，D-0024 修复）：
/// 任务先登记进 [`ProbeTaskManager`]（含子进程句柄槽位与取消令牌），应用退出时
/// `shutdown_all` 可经登记终止并回收在途子进程；调用返回前保证移除登记（幂等）。
pub fn probe_file_managed(
    tool: &Path,
    input: &Path,
    timeout_ms: u64,
    manager: &ProbeTaskManager,
    entry_id: u64,
) -> Result<ProbeMetadata, ProbeFailure> {
    let task = manager.register(entry_id);
    logging::log_line("lifecycle", &format!("task register entry_id={entry_id}"));
    let result = probe_file_managed_task(tool, input, timeout_ms, task);
    let _ = manager.take_finished(entry_id);
    log_terminal(entry_id, &result);
    result
}

/// 终态旁路日志（register/start/complete/failed/cancelled/shutdown 六事件之一组）。
/// 仅记录，不改变任何返回值或状态（Stage 2D-1-A）。
fn log_terminal(entry_id: u64, result: &Result<ProbeMetadata, ProbeFailure>) {
    match result {
        Ok(_) => logging::log_line("lifecycle", &format!("task complete entry_id={entry_id}")),
        Err(failure) => {
            let code = failure.code.as_str();
            if failure.code == ProbeFailureCode::Cancelled {
                logging::log_line("lifecycle", &format!("task cancelled entry_id={entry_id} code={code}"));
            } else {
                logging::log_line("lifecycle", &format!("task failed entry_id={entry_id} code={code}"));
            }
        }
    }
}

/// 以**既登记**的任务执行探测，并按最终结果推进任务终态（Stage 2C-2 状态模型）：
/// `Ok` → `Completed`；`Err(FFPROBE_CANCELLED)` → `Cancelled`；其他 `Err` → `Failed`。
/// 本函数不接触 `ProbeStateStore`（结果持久化由命令层决定——取消路径不覆盖既有结果）。
pub fn probe_file_managed_task(
    tool: &Path,
    input: &Path,
    timeout_ms: u64,
    task: Arc<ProbeTask>,
) -> Result<ProbeMetadata, ProbeFailure> {
    let result = probe_file_inner(tool, input, timeout_ms, Some(task.as_ref()));
    task.set_status(match &result {
        Ok(_) => ProbeTaskStatus::Completed,
        Err(failure) => {
            if failure.code == ProbeFailureCode::Cancelled {
                ProbeTaskStatus::Cancelled
            } else {
                ProbeTaskStatus::Failed
            }
        }
    });
    result
}

/// `probe_file` 的统一实现：任务存在时子进程句柄与生命周期表共享同一槽位。
fn probe_file_inner(
    tool: &Path,
    input: &Path,
    timeout_ms: u64,
    task: Option<&ProbeTask>,
) -> Result<ProbeMetadata, ProbeFailure> {
    let started = Instant::now();
    let mut child = Command::new(tool)
        .args(build_probe_args(input))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| ProbeFailure {
            code: ProbeFailureCode::ToolStartFailed,
            message: format!(
                "无法启动 FFprobe（系统错误 {}）：{err}",
                err.raw_os_error().unwrap_or(0)
            ),
            exit_code: None,
            stderr_tail: None,
        })?;

    // 并发排空 stdout/stderr，避免管道缓冲导致子进程阻塞。
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

    // 句柄登记：任务存在时与 ProbeTaskManager 共享同一槽位（退出/取消路径可取走并终止）。
    let child_slot: Arc<Mutex<Option<Child>>> = match task {
        Some(t) => t.child.clone(),
        None => Arc::new(Mutex::new(None)),
    };
    {
        let mut slot = lock_child(&child_slot);
        *slot = Some(child);
    }
    if let Some(t) = task {
        // 生命周期状态：子进程已 spawn 并入槽 → Running（Stage 2C-2）。
        t.set_status(ProbeTaskStatus::Running);
        logging::log_line("lifecycle", &format!("task start entry_id={}", t.entry_id));
    }

    enum PollOutcome {
        Finished(std::process::ExitStatus),
        TimedOut,
        Cancelled,
    }

    let deadline = Duration::from_millis(timeout_ms);
    let outcome = loop {
        // 取消检查优先于超时判断：关闭路径置位后立即终止。
        if let Some(t) = task {
            if t.cancel.is_cancelled() {
                break PollOutcome::Cancelled;
            }
        }
        {
            let mut slot = lock_child(&child_slot);
            match slot.as_mut() {
                Some(c) => match c.try_wait() {
                    Ok(Some(status)) => break PollOutcome::Finished(status),
                    Ok(None) => {
                        if started.elapsed() >= deadline {
                            break PollOutcome::TimedOut;
                        }
                    }
                    Err(err) => {
                        // 进程状态查询失败：终止+回收后按启动类错误上报（保持分类互不吞并）。
                        let taken = slot.take();
                        drop(slot);
                        if let Some(mut c) = taken {
                            let _ = c.kill();
                            let _ = c.wait();
                        }
                        let _ = stdout_reader.join();
                        let _ = stderr_reader.join();
                        return Err(ProbeFailure {
                            code: ProbeFailureCode::ToolStartFailed,
                            message: format!("等待 FFprobe 进程失败：{err}"),
                            exit_code: None,
                            stderr_tail: None,
                        });
                    }
                },
                None => break PollOutcome::Cancelled, // 句柄已被 shutdown_all 取走并处理
            }
        }
        std::thread::sleep(Duration::from_millis(POLL_INTERVAL_MS));
    };

    match outcome {
        PollOutcome::Finished(status) => {
            // try_wait 已回收退出状态；清空槽位避免 shutdown 重复处理。
            {
                let mut slot = lock_child(&child_slot);
                slot.take();
            }
            let stdout = stdout_reader.join().unwrap_or_default();
            let stderr = stderr_reader.join().unwrap_or_default();
            if !status.success() {
                return Err(ProbeFailure {
                    code: ProbeFailureCode::NonZeroExit,
                    message: nonzero_exit_message(status.code(), &stderr),
                    exit_code: status.code(),
                    stderr_tail: non_empty_tail(&stderr),
                });
            }
            parse_probe_json(&stdout).map_err(|parse_message| ProbeFailure {
                code: ProbeFailureCode::ParseFailed,
                message: parse_message,
                exit_code: Some(0),
                stderr_tail: non_empty_tail(&stderr),
            })
        }
        PollOutcome::TimedOut => {
            let taken = lock_child(&child_slot).take();
            let elapsed_ms = started.elapsed().as_millis();
            let mut message = format!(
                "FFprobe 超时（>{timeout_ms} ms，实际约 {elapsed_ms} ms），已终止子进程"
            );
            match taken {
                Some(mut c) => {
                    if let Err(err) = c.kill() {
                        message.push_str(&format!("；终止子进程时出现错误：{err}"));
                    }
                    if c.wait().is_err() {
                        message.push_str("；回收子进程等待失败");
                    }
                }
                None => message.push_str("（句柄已由退出清理接管）"),
            }
            let stderr = stderr_reader.join().unwrap_or_default();
            let _ = stdout_reader.join();
            Err(ProbeFailure {
                code: ProbeFailureCode::Timeout,
                message,
                exit_code: None,
                stderr_tail: non_empty_tail(&stderr),
            })
        }
        PollOutcome::Cancelled => {
            // 槽位仍有句柄时由本路径终止回收；已被 shutdown_all 取走时其已完成 kill+wait。
            let taken = lock_child(&child_slot).take();
            if let Some(mut c) = taken {
                let _ = c.kill();
                let _ = c.wait();
            }
            let _ = stdout_reader.join();
            let _ = stderr_reader.join();
            Err(ProbeFailure {
                code: ProbeFailureCode::Cancelled,
                message: "FFprobe 探测已取消（应用退出或任务被取消）".to_string(),
                exit_code: None,
                stderr_tail: None,
            })
        }
    }
}

fn non_empty_tail(bytes: &[u8]) -> Option<String> {
    let tail = tail_truncate_lossy(bytes, STDERR_TAIL_LIMIT_BYTES);
    if tail.is_empty() {
        None
    } else {
        Some(tail)
    }
}

/// stderr 尾部截断（保留最后 `limit` 字节；UTF-8 无损失败时按 lossy 转换）。
fn tail_truncate_lossy(bytes: &[u8], limit: usize) -> String {
    let tail = if bytes.len() > limit {
        &bytes[bytes.len() - limit..]
    } else {
        bytes
    };
    String::from_utf8_lossy(tail).trim().to_string()
}

/// 从 stderr 提取可读原因：首个非空行（去首尾空白；超长截断 200 字符）。
/// 仅用于**错误诊断呈现**，绝不用于元数据字段解析（P2B-007）。
fn extract_readable_reason(stderr: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(stderr);
    let line = text.lines().map(str::trim).find(|line| !line.is_empty())?;
    let mut reason = line.to_string();
    const MAX_CHARS: usize = 200;
    if reason.chars().count() > MAX_CHARS {
        reason = reason.chars().take(MAX_CHARS).collect::<String>() + "…";
    }
    Some(reason)
}

/// 非零退出的可读消息（含 FFprobe 自身给出的原因；无原因时仅报退出码）。
fn nonzero_exit_message(code: Option<i32>, stderr: &[u8]) -> String {
    let code_text = code
        .map(|c| c.to_string())
        .unwrap_or_else(|| "未知".to_string());
    match extract_readable_reason(stderr) {
        Some(reason) => format!("FFprobe 以非零退出码结束（{code_text}）：{reason}"),
        None => format!("FFprobe 以非零退出码结束（{code_text}）"),
    }
}

/// 分类策略（P2B-011）：解析成功但报告不出任何可用视频流信息时 → `MEDIA_UNSUPPORTED`。
/// **不**进一步推断"非媒体 vs 损坏"（无可靠依据时不得猜测），疑难情形由可读原因呈现。
fn ensure_video_stream(meta: ProbeMetadata) -> Result<ProbeMetadata, ProbeFailure> {
    if meta.video_codec.is_none() && meta.width.is_none() && meta.height.is_none() {
        return Err(ProbeFailure {
            code: ProbeFailureCode::MediaUnsupported,
            message: "文件中未发现视频流（可能为音频或其他非视频媒体）".to_string(),
            exit_code: None,
            stderr_tail: None,
        });
    }
    Ok(meta)
}

/// 解析 FFprobe 的结构化输出（**仅** JSON 字段；缺失字段为 None，未知编码保留原值）。
pub fn parse_probe_json(stdout: &[u8]) -> Result<ProbeMetadata, String> {
    let value: serde_json::Value =
        serde_json::from_slice(stdout).map_err(|err| format!("FFprobe 输出 JSON 解析失败：{err}"))?;

    let format = value.get("format");
    let duration_secs = format
        .and_then(|f| f.get("duration"))
        .and_then(|d| d.as_f64().or_else(|| d.as_str().and_then(|s| s.parse::<f64>().ok())));
    let container = format
        .and_then(|f| f.get("format_name"))
        .and_then(|c| c.as_str())
        .map(str::to_string);

    let mut width = None;
    let mut height = None;
    let mut video_codec = None;
    let mut video_taken = false;
    let mut has_audio = false;
    let mut audio_codec = None;
    let mut audio_taken = false;

    if let Some(streams) = value.get("streams").and_then(|s| s.as_array()) {
        for stream in streams {
            match stream.get("codec_type").and_then(|t| t.as_str()) {
                Some("video") if !video_taken => {
                    video_taken = true;
                    width = stream
                        .get("width")
                        .and_then(|w| w.as_u64())
                        .map(|w| w as u32);
                    height = stream
                        .get("height")
                        .and_then(|h| h.as_u64())
                        .map(|h| h as u32);
                    video_codec = stream
                        .get("codec_name")
                        .and_then(|c| c.as_str())
                        .map(str::to_string);
                }
                Some("audio") if !audio_taken => {
                    audio_taken = true;
                    has_audio = true;
                    audio_codec = stream
                        .get("codec_name")
                        .and_then(|c| c.as_str())
                        .map(str::to_string);
                }
                _ => {}
            }
        }
    }

    Ok(ProbeMetadata {
        duration_secs,
        width,
        height,
        video_codec,
        has_audio,
        audio_codec,
        container,
    })
}

// ================= Phase 2B-2：展示格式化、视图与探测状态存储 =================
//
// 说明：探测结果存放在本模块的独立会话级存储（与 `import::ImportState` 分离），
// 既不修改 Stage 2A 的导入状态/判重语义，也不向 IPC 暴露任何路径或可执行文件参数。

/// 单条目探测结果。
#[derive(Debug, Clone, PartialEq)]
pub enum ProbeState {
    Ready(ProbeMetadata),
    Failed(ProbeFailure),
}

/// 存储记录：文件大小在探测时快照（读取失败保持 None，不猜测）。
#[derive(Debug, Clone, PartialEq)]
pub struct ProbeRecord {
    pub size_bytes: Option<u64>,
    pub state: ProbeState,
}

/// 探测状态存储（Tauri 托管状态；会话级）。
#[derive(Debug, Default)]
pub struct ProbeStateStore {
    inner: Mutex<ProbeStoreInner>,
}

#[derive(Debug, Default)]
struct ProbeStoreInner {
    results: HashMap<u64, ProbeRecord>,
    inflight: HashSet<u64>,
}

impl ProbeStateStore {
    fn lock(&self) -> std::sync::MutexGuard<'_, ProbeStoreInner> {
        // 锁中毒时恢复内部数据：命令层不允许 panic（ARCH-005）。
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub fn cached(&self, entry_id: u64) -> Option<ProbeRecord> {
        self.lock().results.get(&entry_id).cloned()
    }

    /// 标记开始探测；该条目已在解析中则返回 false（防并发重复探测）。
    pub fn begin(&self, entry_id: u64) -> bool {
        self.lock().inflight.insert(entry_id)
    }

    /// 调度失败等异常路径：结束在途标记且不写入结果。
    pub fn abort(&self, entry_id: u64) {
        self.lock().inflight.remove(&entry_id);
    }

    pub fn finish(&self, entry_id: u64, record: ProbeRecord) {
        let mut inner = self.lock();
        inner.inflight.remove(&entry_id);
        inner.results.insert(entry_id, record);
    }

    pub fn all(&self) -> Vec<(u64, ProbeRecord)> {
        let mut items: Vec<(u64, ProbeRecord)> = self
            .lock()
            .results
            .iter()
            .map(|(id, record)| (*id, record.clone()))
            .collect();
        items.sort_by_key(|(id, _)| *id);
        items
    }
}

/// 文件大小：底层字节数原值（另附于视图）的人类可读形式（1024 进制；<1 KiB 显示字节，其余两位小数）。
pub fn format_size(bytes: u64) -> String {
    const KIB: f64 = 1024.0;
    let value = bytes as f64;
    if value < KIB {
        format!("{bytes} B")
    } else if value < KIB * KIB {
        format!("{:.2} KiB", value / KIB)
    } else if value < KIB * KIB * KIB {
        format!("{:.2} MiB", value / (KIB * KIB))
    } else {
        format!("{:.2} GiB", value / (KIB * KIB * KIB))
    }
}

/// 时长显示（D-0017）：不保留小数秒，**向下取整（floor）到秒**；≥1 小时用 `HH:MM:SS`，否则 `MM:SS`。
pub fn format_duration_floor(secs: f64) -> String {
    let total = secs.max(0.0).floor() as u64;
    let hours = total / 3600;
    let minutes = (total % 3600) / 60;
    let seconds = total % 60;
    if hours > 0 {
        format!("{hours:02}:{minutes:02}:{seconds:02}")
    } else {
        format!("{minutes:02}:{seconds:02}")
    }
}

/// 视频编码映射（P2B-005）：常规编码给可读名；**未识别一律保留原值**，禁止猜测。
pub fn map_video_codec(codec_name: &str) -> String {
    match codec_name.to_lowercase().as_str() {
        "h264" => "H.264 / AVC".to_string(),
        "hevc" | "h265" => "H.265 / HEVC".to_string(),
        "mpeg4" => "MPEG-4 Video".to_string(),
        "mpeg2video" => "MPEG-2 Video".to_string(),
        "mpeg1video" => "MPEG-1 Video".to_string(),
        "vp8" => "VP8".to_string(),
        "vp9" => "VP9".to_string(),
        "av1" => "AV1".to_string(),
        "theora" => "Theora".to_string(),
        "prores" => "ProRes".to_string(),
        "mjpeg" => "Motion JPEG".to_string(),
        "wmv3" | "vc1" => "VC-1 / WMV".to_string(),
        _ => codec_name.to_string(),
    }
}

/// 音频编码映射（P2B-006；未识别保留原值）。
pub fn map_audio_codec(codec_name: &str) -> String {
    match codec_name.to_lowercase().as_str() {
        "aac" => "AAC".to_string(),
        "mp3" => "MP3".to_string(),
        "mp2" => "MP2".to_string(),
        "ac3" => "AC-3".to_string(),
        "eac3" => "E-AC-3".to_string(),
        "flac" => "FLAC".to_string(),
        "opus" => "Opus".to_string(),
        "vorbis" => "Vorbis".to_string(),
        "alac" => "ALAC".to_string(),
        "dts" => "DTS".to_string(),
        "pcm_s16le" => "PCM 16-bit".to_string(),
        "pcm_s24le" => "PCM 24-bit".to_string(),
        _ => codec_name.to_string(),
    }
}

/// 音频显示语义（P2B-006 与 P2B-008 的区分）：
/// - 无音轨 → `Some("无音轨")`（明确状态，不等于 N/A）；
/// - 有音轨且编码已知 → `Some(可读名)`；
/// - 有音轨但编码缺失 → `None`（前端显示 N/A，绝不编造）。
fn audio_text(meta: &ProbeMetadata) -> Option<String> {
    if !meta.has_audio {
        Some("无音轨".to_string())
    } else {
        meta.audio_codec.as_deref().map(map_audio_codec)
    }
}

/// 前端视图（serde camelCase；字段缺失一律为 null，由前端渲染 N/A）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProbeView {
    pub entry_id: u64,
    /// "ready" | "failed"
    pub state: String,
    pub size_bytes: Option<u64>,
    pub size_text: Option<String>,
    pub duration_text: Option<String>,
    pub resolution_text: Option<String>,
    pub video_codec_text: Option<String>,
    pub audio_text: Option<String>,
    pub failure_code: Option<String>,
    pub failure_message: Option<String>,
}

fn build_view(entry_id: u64, record: &ProbeRecord) -> ProbeView {
    match &record.state {
        ProbeState::Ready(meta) => ProbeView {
            entry_id,
            state: "ready".to_string(),
            size_bytes: record.size_bytes,
            size_text: record.size_bytes.map(format_size),
            duration_text: meta.duration_secs.map(format_duration_floor),
            resolution_text: match (meta.width, meta.height) {
                (Some(width), Some(height)) => Some(format!("{width}×{height}")),
                _ => None,
            },
            video_codec_text: meta.video_codec.as_deref().map(map_video_codec),
            audio_text: audio_text(meta),
            failure_code: None,
            failure_message: None,
        },
        ProbeState::Failed(failure) => ProbeView {
            entry_id,
            state: "failed".to_string(),
            size_bytes: record.size_bytes,
            size_text: record.size_bytes.map(format_size),
            duration_text: None,
            resolution_text: None,
            video_codec_text: None,
            audio_text: None,
            failure_code: Some(failure.code.as_str().to_string()),
            failure_message: Some(failure.message.clone()),
        },
    }
}

/// 为指定导入条目执行一次元数据探测（异步、非阻塞；会话级缓存，重复调用返回缓存）。
/// `force = true` 时忽略缓存重新探测（供元数据失败后的"重试"使用；在途防并发仍然生效）。
///
/// 安全边界：**仅接受条目 ID**——媒体路径一律取自导入登记表（用户经原生对话框选择后登记），
/// 前端无法指定任意路径、任意可执行文件，也无法经 IPC 启用测试覆盖机制（覆盖仅经 Debug 环境变量生效）。
///
/// 生命周期（Phase 2C-1）：探测在 `spawn_blocking` 中经 [`ProbeTaskManager`] 登记，
/// 应用退出（`RunEvent::Exit`）时由 `shutdown_all` 取消、终止并回收在途子进程。
#[tauri::command]
pub async fn probe_import_entry(
    import_state: tauri::State<'_, crate::import::ImportState>,
    probe_state: tauri::State<'_, ProbeStateStore>,
    task_manager: tauri::State<'_, crate::probe_lifecycle::ProbeTaskManager>,
    entry_id: u64,
    force: bool,
) -> Result<ProbeView, String> {
    if !force {
        if let Some(record) = probe_state.cached(entry_id) {
            return Ok(build_view(entry_id, &record));
        }
    }
    let entry = import_state
        .list_entries()
        .into_iter()
        .find(|e| e.id == entry_id)
        .ok_or_else(|| format!("条目 {entry_id} 不存在"))?;
    if entry.status != crate::import::EntryStatus::Ready {
        return Err("该条目未通过导入校验，跳过元数据探测".to_string());
    }
    if !probe_state.begin(entry_id) {
        return Err("该条目正在解析中".to_string());
    }
    let path = PathBuf::from(&entry.path);
    let timeout_ms = effective_timeout_ms();
    let manager = task_manager.clone_shared();
    let probed = tauri::async_runtime::spawn_blocking(move || {
        let size_bytes = std::fs::metadata(&path).ok().map(|m| m.len());
        let result = probe_with_discovery_managed(&path, timeout_ms, &manager, entry_id);
        (size_bytes, result)
    })
    .await;
    let (size_bytes, result) = match probed {
        Ok(value) => value,
        Err(err) => {
            probe_state.abort(entry_id);
            return Err(format!("探测任务调度失败：{err}"));
        }
    };
    let record = ProbeRecord {
        size_bytes,
        state: match result {
            Ok(meta) => ProbeState::Ready(meta),
            Err(failure) => ProbeState::Failed(failure),
        },
    };
    let cancelled = matches!(&record.state, ProbeState::Failed(f) if f.code == ProbeFailureCode::Cancelled);
    if cancelled {
        // 应用退出导致的取消：不写入结果——保留该条目既有探测状态，
        // 避免未完成的重试覆盖既有错误结果（Stage 2C-2 一致性要求）。
        probe_state.abort(entry_id);
    } else {
        probe_state.finish(entry_id, record.clone());
    }
    Ok(build_view(entry_id, &record))
}

/// 列出会话内已缓存的全部探测结果（供前端挂载时合并渲染）。
#[tauri::command]
pub fn list_probe_results(probe_state: tauri::State<'_, ProbeStateStore>) -> Vec<ProbeView> {
    probe_state
        .all()
        .into_iter()
        .map(|(id, record)| build_view(id, &record))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    /// 测试文件仅写入已批准目录：`docs/evidence/stage2/2b/scratch/`。
    fn scratch_dir(sub: &str) -> PathBuf {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("docs")
            .join("evidence")
            .join("stage2")
            .join("2b")
            .join("scratch")
            .join(sub);
        fs::create_dir_all(&dir).expect("创建 scratch 目录失败");
        dir
    }

    fn sample_video() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("docs")
            .join("evidence")
            .join("gate0c-media")
            .join("sample_src.mkv")
    }

    fn special_char_video() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("docs")
            .join("evidence")
            .join("stage2")
            .join("test-assets")
            .join("测试 目录 & 素材 #1 (终版)'s")
            .join("样本 视频 #1 (初版)'s.mkv")
    }

    // ---------- 常量与超时 ----------

    #[test]
    fn default_timeout_is_30_seconds() {
        assert_eq!(PROBE_TIMEOUT_DEFAULT_MS, 30_000);
        assert_eq!(STDERR_TAIL_LIMIT_BYTES, 8 * 1024);
    }

    #[test]
    fn effective_timeout_defaults_without_override() {
        // 该测试在无覆盖环境变量时运行；断言默认值被采用。
        if std::env::var_os("CLIPFORGE_TEST_PROBE_TIMEOUT_MS").is_none() {
            assert_eq!(effective_timeout_ms(), PROBE_TIMEOUT_DEFAULT_MS);
        }
    }

    // ---------- 安全参数构造（ARCH-001） ----------

    #[test]
    fn build_args_passes_input_as_single_osstring_verbatim() {
        let malicious = [
            "; rm -rf /",
            "&& calc",
            "$(whoami)",
            "a\nb",
            "\"quoted\"",
            "..\\..\\escape",
            "中文 空格 & 路径 #1 (初版)'s.mp4",
            "%PATH%",
            "^caret^",
        ];
        for raw in malicious {
            let input = PathBuf::from(format!("D:\\videos\\{raw}"));
            let args = build_probe_args(&input);
            assert_eq!(args.len(), 7);
            assert_eq!(args[0], OsString::from("-v"));
            assert_eq!(args[1], OsString::from("error"));
            assert_eq!(args[2], OsString::from("-print_format"));
            assert_eq!(args[3], OsString::from("json"));
            assert_eq!(args[4], OsString::from("-show_format"));
            assert_eq!(args[5], OsString::from("-show_streams"));
            // 输入以单个 OsString 原样传递：不做转义、不拼接 shell。
            assert_eq!(args[6], input.as_os_str().to_os_string());
        }
    }

    // ---------- JSON 解析（P2B-007 / P2B-006 / P2B-008 语义） ----------

    const FULL_JSON: &str = r#"{
      "streams": [
        {"codec_type": "video", "codec_name": "h264", "width": 640, "height": 360},
        {"codec_type": "audio", "codec_name": "aac"}
      ],
      "format": {"duration": "5.023000", "format_name": "matroska,webm"}
    }"#;

    #[test]
    fn parse_full_json_fields() {
        let meta = parse_probe_json(FULL_JSON.as_bytes()).unwrap();
        assert_eq!(meta.duration_secs, Some(5.023));
        assert_eq!(meta.width, Some(640));
        assert_eq!(meta.height, Some(360));
        assert_eq!(meta.video_codec.as_deref(), Some("h264"));
        assert!(meta.has_audio);
        assert_eq!(meta.audio_codec.as_deref(), Some("aac"));
        assert_eq!(meta.container.as_deref(), Some("matroska,webm"));
    }

    #[test]
    fn parse_no_audio_stream_semantics() {
        let json = r#"{"streams":[{"codec_type":"video","codec_name":"h264","width":320,"height":240}],"format":{"duration":"1.0","format_name":"mp4"}}"#;
        let meta = parse_probe_json(json.as_bytes()).unwrap();
        assert!(!meta.has_audio, "无音轨必须是 has_audio=false");
        assert_eq!(meta.audio_codec, None);
    }

    #[test]
    fn parse_audio_stream_without_codec_name_keeps_distinct_semantics() {
        let json = r#"{"streams":[{"codec_type":"video"},{"codec_type":"audio"}],"format":{}}"#;
        let meta = parse_probe_json(json.as_bytes()).unwrap();
        assert!(meta.has_audio, "存在音频流 → has_audio=true（与无音轨区分）");
        assert_eq!(meta.audio_codec, None, "编码未知 → 保留 None（展示层用 N/A）");
    }

    #[test]
    fn parse_missing_duration_is_none_not_zero() {
        let json = r#"{"streams":[],"format":{"format_name":"h264"}}"#;
        let meta = parse_probe_json(json.as_bytes()).unwrap();
        assert_eq!(meta.duration_secs, None);
    }

    #[test]
    fn parse_unknown_codec_preserved_verbatim() {
        let json = r#"{"streams":[{"codec_type":"video","codec_name":"weird_codec_x"}],"format":{}}"#;
        let meta = parse_probe_json(json.as_bytes()).unwrap();
        assert_eq!(meta.video_codec.as_deref(), Some("weird_codec_x"));
    }

    #[test]
    fn parse_duration_as_number_and_string() {
        let as_number = r#"{"streams":[],"format":{"duration":5.5}}"#;
        assert_eq!(parse_probe_json(as_number.as_bytes()).unwrap().duration_secs, Some(5.5));
        let as_string = r#"{"streams":[],"format":{"duration":"12.25"}}"#;
        assert_eq!(parse_probe_json(as_string.as_bytes()).unwrap().duration_secs, Some(12.25));
    }

    #[test]
    fn parse_malformed_json_is_parse_failure() {
        let err = parse_probe_json(b"{ this is not json").unwrap_err();
        assert!(err.contains("解析失败"), "错误信息应指明解析失败：{err}");
    }

    #[test]
    fn tail_truncate_keeps_last_bytes_and_is_bounded() {
        let mut data = vec![b'a'; 10_000];
        data.extend_from_slice(b"TAIL-MARKER");
        let out = tail_truncate_lossy(&data, 64);
        assert!(out.len() <= 64);
        assert!(out.ends_with("TAIL-MARKER"));
    }

    // ---------- 发现（顺序与策略记录） ----------

    #[test]
    fn discovery_path_env_strategy_hits_expected_entry() {
        let dir = scratch_dir("path-env");
        let bin = dir.join("bin");
        fs::create_dir_all(&bin).unwrap();
        let exe = bin.join("ffprobe.exe");
        fs::write(&exe, b"stub").unwrap();
        let path_env = OsString::from(format!("C:\\nonexistent;{}", bin.to_string_lossy()));
        let found = discover_with(Some(&path_env), None, None, None).expect("应命中 PATH 策略");
        assert_eq!(found.strategy, ToolStrategy::PathEnv);
        assert_eq!(found.path, exe);
    }

    #[test]
    fn discovery_override_replaces_search_and_missing_file_is_not_found() {
        let dir = scratch_dir("override-missing");
        let missing = dir.join("missing-ffprobe.exe");
        let _ = fs::remove_file(&missing);
        // 即使 PATH 中有可用 ffprobe，只要给了覆盖就只看覆盖（覆盖值为最终答案）。
        let path_env = OsString::from("C:\\whatever");
        let found = discover_with(Some(&path_env), None, None, Some(missing.clone()));
        assert_eq!(found, None, "覆盖指向不存在的文件 → 未发现（不回退）");
    }

    #[test]
    fn discovery_override_used_when_file_exists() {
        let dir = scratch_dir("override-present");
        let exe = dir.join("fake-ffprobe-stub.exe");
        fs::write(&exe, b"stub").unwrap();
        let found = discover_with(None, None, None, Some(exe.clone())).expect("应命中覆盖");
        assert_eq!(found.strategy, ToolStrategy::TestOverride);
        assert_eq!(found.path, exe);
    }

    #[test]
    fn discovery_winget_packages_strategy_deep_scan() {
        let lad = scratch_dir("fake-lad");
        let pkg = lad
            .join("Microsoft")
            .join("WinGet")
            .join("Packages")
            .join("Gyan.FFmpeg_TestSource_abcdef")
            .join("ffmpeg-1.0-full_build")
            .join("bin");
        fs::create_dir_all(&pkg).unwrap();
        let exe = pkg.join("ffprobe.exe");
        fs::write(&exe, b"stub").unwrap();
        let found = discover_with(None, Some(&lad), None, None).expect("应命中 WinGet 策略");
        assert_eq!(found.strategy, ToolStrategy::WingetPackages);
        assert_eq!(found.path, exe);
    }

    #[test]
    fn discovery_common_dirs_last_resort() {
        let up = scratch_dir("fake-up");
        let shims = up.join("scoop").join("shims");
        fs::create_dir_all(&shims).unwrap();
        let exe = shims.join("ffprobe.exe");
        fs::write(&exe, b"stub").unwrap();
        let found = discover_with(None, None, Some(&up), None).expect("应命中常见目录策略");
        assert_eq!(found.strategy, ToolStrategy::CommonDirs);
        assert_eq!(found.path, exe);
    }

    #[test]
    fn discovery_returns_none_when_nothing_found() {
        let empty = scratch_dir("empty");
        let path_env = OsString::from(format!("C:\\nonexistent-a;{}", empty.join("nope").to_string_lossy()));
        let found = discover_with(Some(&path_env), Some(&empty), Some(&empty), None);
        assert_eq!(found, None);
    }

    // ---------- 集成测试（需真实环境/替身；显式运行：cargo test -- --ignored --nocapture） ----------

    /// 真机发现验证（中文用户名路径）：记录命中策略与实际路径。
    #[test]
    #[ignore = "需要本机已安装 FFprobe（真机发现验证）"]
    fn real_discovery_reports_strategy_and_path() {
        let found = discover_ffprobe().expect("本机应能发现 FFprobe");
        println!(
            "DISCOVERY strategy={} path={}",
            found.strategy.as_str(),
            found.path.display()
        );
        assert!(found.path.is_file());
    }

    /// 真机探测 5 秒样片：字段与既有 Gate-0C 记录一致（mpeg4 + aac，640×360，≈5.02s）。
    #[test]
    #[ignore = "需要本机已安装 FFprobe（真机探测验证）"]
    fn real_probe_sample_metadata() {
        let tool = discover_ffprobe().expect("本机应能发现 FFprobe");
        let meta = probe_file(&tool.path, &sample_video(), effective_timeout_ms()).expect("探测应成功");
        println!("PROBE sample_src.mkv => {meta:?}");
        let duration = meta.duration_secs.expect("应有 duration");
        assert!((duration - 5.023).abs() < 0.05, "duration≈5.023，实际 {duration}");
        assert_eq!(meta.width, Some(640));
        assert_eq!(meta.height, Some(360));
        assert_eq!(meta.video_codec.as_deref(), Some("mpeg4"));
        assert!(meta.has_audio);
        assert_eq!(meta.audio_codec.as_deref(), Some("aac"));
    }

    /// 真机探测中文+空格+`&`+`'` 路径（ARCH-001 / 中文路径端到端）。
    #[test]
    #[ignore = "需要本机已安装 FFprobe（中文路径验证）"]
    fn real_probe_special_char_path() {
        let tool = discover_ffprobe().expect("本机应能发现 FFprobe");
        let meta = probe_file(&tool.path, &special_char_video(), effective_timeout_ms()).expect("中文路径探测应成功");
        println!("PROBE special-char path => {meta:?}");
        assert_eq!(meta.width, Some(640));
    }

    /// 覆盖场景 (a)：工具文件不存在 → 未发现 → `ToolNotFound`（与"无法启动"严格区分）。
    #[test]
    #[ignore = "需设置 CLIPFORGE_TEST_FFPROBE 指向替身目录内不存在的文件"]
    fn override_scenario_missing_file_is_not_found() {
        let found = discover_ffprobe();
        println!("OVERRIDE missing => {:?}", found.as_ref().map(|f| f.strategy.as_str()));
        assert_eq!(found, None);
        let err = probe_with_discovery(&sample_video(), effective_timeout_ms()).unwrap_err();
        println!("OVERRIDE missing probe => code={} message={}", err.code.as_str(), err.message);
        assert_eq!(err.code, ProbeFailureCode::ToolNotFound);
    }

    /// 覆盖场景 (b)：存在但无法启动 → ToolStartFailed。
    #[test]
    #[ignore = "需设置 CLIPFORGE_TEST_FFPROBE 指向替身目录内不可启动文件"]
    fn override_scenario_unlaunchable_start_failed() {
        let tool = discover_ffprobe().expect("覆盖指向存在的文件 → 应有候选");
        assert_eq!(tool.strategy, ToolStrategy::TestOverride);
        let err = probe_file(&tool.path, &sample_video(), effective_timeout_ms()).unwrap_err();
        println!("OVERRIDE unlaunchable => code={} message={}", err.code.as_str(), err.message);
        assert_eq!(err.code, ProbeFailureCode::ToolStartFailed);
    }

    /// 覆盖场景 (c)：替身非零退出 → NonZeroExit（含退出码与 stderr 尾部）。
    #[test]
    #[ignore = "需设置 CLIPFORGE_TEST_FFPROBE 指向 fake-ffprobe-exit1 替身"]
    fn override_scenario_nonzero_exit() {
        let tool = discover_ffprobe().expect("覆盖应命中");
        let err = probe_file(&tool.path, &sample_video(), effective_timeout_ms()).unwrap_err();
        println!(
            "OVERRIDE exit1 => code={} exit_code={:?} stderr_tail={:?}",
            err.code.as_str(),
            err.exit_code,
            err.stderr_tail
        );
        assert_eq!(err.code, ProbeFailureCode::NonZeroExit);
        assert_eq!(err.exit_code, Some(1));
        assert!(err.stderr_tail.as_deref().unwrap_or("").contains("fake-ffprobe-exit1"));
    }

    /// 覆盖超时：短超时 + 延迟替身 → Timeout，子进程被终止回收；实际耗时远小于替身挂起时长。
    #[test]
    #[ignore = "需设置 CLIPFORGE_TEST_FFPROBE=延迟替身 且 CLIPFORGE_TEST_PROBE_TIMEOUT_MS=1500"]
    fn override_scenario_timeout_kills_child() {
        let timeout = effective_timeout_ms();
        println!("OVERRIDE timeout_ms_effective={timeout}");
        assert_eq!(timeout, 1500, "应读取到受控短超时覆盖");
        let tool = discover_ffprobe().expect("覆盖应命中");
        let started = Instant::now();
        let err = probe_file(&tool.path, &sample_video(), timeout).unwrap_err();
        let elapsed = started.elapsed();
        println!(
            "OVERRIDE timeout => code={} elapsed_ms={} message={}",
            err.code.as_str(),
            elapsed.as_millis(),
            err.message
        );
        assert_eq!(err.code, ProbeFailureCode::Timeout);
        assert!(elapsed.as_secs() < 10, "超时应迅速终止（实际 {elapsed:?}），而非等待替身自然结束（120s）");
        assert!(elapsed.as_millis() >= 1_400, "应至少在超时阈值附近终止（实际 {elapsed:?}）");
    }
}

#[cfg(test)]
mod tests_2b2 {
    use super::*;

    fn empty_meta() -> ProbeMetadata {
        ProbeMetadata {
            duration_secs: None,
            width: None,
            height: None,
            video_codec: None,
            has_audio: false,
            audio_codec: None,
            container: None,
        }
    }

    #[test]
    fn format_size_boundaries() {
        assert_eq!(format_size(0), "0 B");
        assert_eq!(format_size(1023), "1023 B");
        assert_eq!(format_size(1024), "1.00 KiB");
        assert_eq!(format_size(1536), "1.50 KiB");
        assert_eq!(format_size(1_236_377), "1.18 MiB"); // 与 sample_src.mkv 实际大小对照
        assert_eq!(format_size(1024 * 1024 * 1024), "1.00 GiB");
    }

    #[test]
    fn format_duration_floor_table() {
        assert_eq!(format_duration_floor(5.023), "00:05"); // floor，非四舍五入
        assert_eq!(format_duration_floor(59.999), "00:59");
        assert_eq!(format_duration_floor(60.0), "01:00");
        assert_eq!(format_duration_floor(3599.99), "59:59");
        assert_eq!(format_duration_floor(3600.0), "01:00:00");
        assert_eq!(format_duration_floor(90061.9), "25:01:01");
        assert_eq!(format_duration_floor(0.0), "00:00");
    }

    #[test]
    fn codec_mapping_known_and_unknown_verbatim() {
        assert_eq!(map_video_codec("h264"), "H.264 / AVC");
        assert_eq!(map_video_codec("hevc"), "H.265 / HEVC");
        assert_eq!(map_video_codec("mpeg4"), "MPEG-4 Video");
        assert_eq!(map_video_codec("weird_codec_x"), "weird_codec_x"); // 未识别 → 原值
        assert_eq!(map_audio_codec("aac"), "AAC");
        assert_eq!(map_audio_codec("unknown_audio_1"), "unknown_audio_1");
    }

    #[test]
    fn audio_text_semantics_three_states() {
        let no_audio = empty_meta();
        assert_eq!(audio_text(&no_audio).as_deref(), Some("无音轨"));
        let with_codec = ProbeMetadata {
            has_audio: true,
            audio_codec: Some("aac".to_string()),
            ..no_audio.clone()
        };
        assert_eq!(audio_text(&with_codec).as_deref(), Some("AAC"));
        let missing_codec = ProbeMetadata {
            has_audio: true,
            audio_codec: None,
            ..no_audio
        };
        assert_eq!(audio_text(&missing_codec), None, "有音轨但编码未知 → None（展示 N/A），不得编造");
    }

    #[test]
    fn build_view_ready_maps_all_fields() {
        let meta = ProbeMetadata {
            duration_secs: Some(5.023),
            width: Some(640),
            height: Some(360),
            video_codec: Some("mpeg4".to_string()),
            has_audio: true,
            audio_codec: Some("aac".to_string()),
            container: Some("matroska,webm".to_string()),
        };
        let record = ProbeRecord {
            size_bytes: Some(1_236_377),
            state: ProbeState::Ready(meta),
        };
        let view = build_view(7, &record);
        assert_eq!(view.entry_id, 7);
        assert_eq!(view.state, "ready");
        assert_eq!(view.size_bytes, Some(1_236_377));
        assert_eq!(view.size_text.as_deref(), Some("1.18 MiB"));
        assert_eq!(view.duration_text.as_deref(), Some("00:05"));
        assert_eq!(view.resolution_text.as_deref(), Some("640×360"));
        assert_eq!(view.video_codec_text.as_deref(), Some("MPEG-4 Video"));
        assert_eq!(view.audio_text.as_deref(), Some("AAC"));
        assert!(view.failure_code.is_none());
        assert!(view.failure_message.is_none());
    }

    #[test]
    fn build_view_missing_fields_stay_none_not_fabricated() {
        let record = ProbeRecord {
            size_bytes: None,
            state: ProbeState::Ready(empty_meta()),
        };
        let view = build_view(1, &record);
        assert_eq!(view.size_text, None);
        assert_eq!(view.duration_text, None);
        assert_eq!(view.resolution_text, None);
        assert_eq!(view.video_codec_text, None);
        assert_eq!(view.audio_text.as_deref(), Some("无音轨")); // 无音轨是明确状态而非缺失
    }

    #[test]
    fn build_view_failed_never_renders_as_success() {
        let failure = ProbeFailure {
            code: ProbeFailureCode::Timeout,
            message: "FFprobe 超时（>1500 ms），已终止子进程".to_string(),
            exit_code: None,
            stderr_tail: None,
        };
        let record = ProbeRecord {
            size_bytes: Some(10),
            state: ProbeState::Failed(failure),
        };
        let view = build_view(3, &record);
        assert_eq!(view.state, "failed");
        assert_eq!(view.failure_code.as_deref(), Some("FFPROBE_TIMEOUT"));
        assert!(view.failure_message.as_deref().unwrap_or("").contains("超时"));
        assert!(view.duration_text.is_none());
        assert!(view.resolution_text.is_none());
        assert!(view.video_codec_text.is_none());
        assert!(view.audio_text.is_none());
    }

    #[test]
    fn probe_view_serializes_camel_case_for_ipc() {
        let record = ProbeRecord {
            size_bytes: Some(1),
            state: ProbeState::Ready(empty_meta()),
        };
        let value = serde_json::to_value(build_view(9, &record)).unwrap();
        assert_eq!(value["entryId"], 9);
        assert_eq!(value["state"], "ready");
        assert!(value.get("sizeText").is_some());
        assert!(value.get("failureCode").is_some());
    }

    #[test]
    fn store_caches_and_guards_inflight() {
        let store = ProbeStateStore::default();
        assert!(store.cached(1).is_none());
        assert!(store.begin(1), "首次 begin 应为 true");
        assert!(!store.begin(1), "解析中重复 begin 应为 false");
        let record = ProbeRecord {
            size_bytes: None,
            state: ProbeState::Failed(ProbeFailure {
                code: ProbeFailureCode::ToolNotFound,
                message: "x".to_string(),
                exit_code: None,
                stderr_tail: None,
            }),
        };
        store.finish(1, record.clone());
        assert_eq!(store.cached(1), Some(record));
        assert!(store.begin(2));
        store.abort(2);
        assert!(store.begin(2), "abort 后应可重新开始");
        assert_eq!(store.all().len(), 1);
    }

    // ---------- Phase 2B-3：可读原因 / 分类 / 重试支持 ----------

    #[test]
    fn extract_readable_reason_takes_first_nonempty_line() {
        assert_eq!(extract_readable_reason(b""), None);
        assert_eq!(extract_readable_reason(b"\n   \n\t\n"), None);
        assert_eq!(
            extract_readable_reason(b"\nmoov atom not found\nInvalid data found\n"),
            Some("moov atom not found".to_string())
        );
        let long = "x".repeat(500);
        let reason = extract_readable_reason(long.as_bytes()).unwrap();
        assert!(reason.chars().count() <= 201, "超长原因应截断（含省略号）");
        assert!(reason.ends_with('…'));
    }

    #[test]
    fn nonzero_exit_message_includes_reason_when_available() {
        let with_reason = nonzero_exit_message(Some(1), b"Invalid data found when processing input\n");
        assert!(with_reason.contains("（1）"));
        assert!(with_reason.contains("Invalid data found when processing input"));
        let without = nonzero_exit_message(Some(2), b"");
        assert_eq!(without, "FFprobe 以非零退出码结束（2）");
    }

    #[test]
    fn ensure_video_stream_classifies_no_video_media() {
        let audio_like = ProbeMetadata {
            duration_secs: Some(5.0),
            width: None,
            height: None,
            video_codec: None,
            has_audio: true,
            audio_codec: Some("aac".to_string()),
            container: Some("mov,mp4,m4a".to_string()),
        };
        let err = ensure_video_stream(audio_like).unwrap_err();
        assert_eq!(err.code, ProbeFailureCode::MediaUnsupported);
        assert_eq!(err.code.as_str(), "MEDIA_UNSUPPORTED");
        assert!(err.message.contains("未发现视频流"));

        let with_video = ProbeMetadata {
            duration_secs: None,
            width: Some(640),
            height: Some(360),
            video_codec: Some("h264".to_string()),
            has_audio: false,
            audio_codec: None,
            container: None,
        };
        assert!(ensure_video_stream(with_video).is_ok());
    }
}

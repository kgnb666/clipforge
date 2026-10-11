//! Stage 2D-1-A：应用日志基础设施（ARCH-011 / D-0020 / D-0027）。
//!
//! 边界与保证：
//! - **std-only**（零第三方依赖）；日志目录由调用方经应用路径 API 构造后传入（不得硬编码绝对路径）；
//! - 单文件上限 **5 MiB（5,242,880 字节）**，写入将超限即轮转；**保留最近 3 份（含当前）**；
//! - `log_line` 任何错误**静默忽略**——日志异常不得影响主流程；未初始化时为 no-op；
//! - 行格式：`<UTC 时间> [类别] 消息`（单行；换行转义、超长截断）。

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

/// 单文件上限：5 MiB（D-0020）。
pub const MAX_FILE_BYTES: u64 = 5 * 1024 * 1024;
/// 保留最近 3 份日志（含当前）（D-0020）。
pub const KEEP_FILES: usize = 3;
/// 单行消息长度上限（防止异常输出无限增长；ARCH-004 精神）。
const MAX_LINE_CHARS: usize = 4096;
const CURRENT_NAME: &str = "clipforge.log";

struct LogState {
    dir: PathBuf,
    max_file_bytes: u64,
    keep_files: usize,
}

static STATE: OnceLock<Mutex<Option<LogState>>> = OnceLock::new();

fn state() -> &'static Mutex<Option<LogState>> {
    STATE.get_or_init(|| Mutex::new(None))
}

/// 初始化日志（生产入口）：目录经应用路径 API 构造（lib.rs 传入）。
/// 幂等——首次初始化生效；失败返回 Err 且日志保持禁用（不影响主流程）。
pub fn init(base_dir: &Path) -> Result<(), io::Error> {
    init_with(base_dir.to_path_buf(), MAX_FILE_BYTES, KEEP_FILES)
}

/// 以显式参数初始化（测试注入用；生产请用 [`init`]）。
pub fn init_with(dir: PathBuf, max_file_bytes: u64, keep_files: usize) -> Result<(), io::Error> {
    fs::create_dir_all(&dir)?;
    let mut guard = state().lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if guard.is_none() {
        *guard = Some(LogState { dir, max_file_bytes, keep_files });
    }
    Ok(())
}

/// 记录一行日志（类别 + 消息）。任何错误静默忽略；未初始化为 no-op。
pub fn log_line(category: &str, message: &str) {
    let guard = state().lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(st) = guard.as_ref() {
        let _ = write_line(st, category, message);
    }
}

fn write_line(st: &LogState, category: &str, message: &str) -> io::Result<()> {
    let line = format!("{} [{}] {}\n", utc_now_string(), category, sanitize(message));
    let current = st.dir.join(CURRENT_NAME);
    let size = fs::metadata(&current).map(|m| m.len()).unwrap_or(0);
    if size > 0 && size + line.len() as u64 > st.max_file_bytes {
        rotate(&st.dir, st.keep_files)?;
    }
    let mut file = open_append(&st.dir, &current)?;
    file.write_all(line.as_bytes())
}

/// 打开当前日志文件（追加）；若失败（如目录被外部删除）则重建目录后重试一次——自愈，不向外传播。
fn open_append(dir: &Path, current: &Path) -> io::Result<File> {
    match OpenOptions::new().create(true).append(true).open(current) {
        Ok(file) => Ok(file),
        Err(first_err) => {
            fs::create_dir_all(dir)?;
            OpenOptions::new()
                .create(true)
                .append(true)
                .open(current)
                .map_err(|_| first_err)
        }
    }
}

/// 轮转：删除最旧一份，其余依次下移，当前 → `.1`。
/// 保留 keep 份（含当前）：`clipforge.log`、`clipforge.log.1`、…、`clipforge.log.(keep-1)`。
fn rotate(dir: &Path, keep: usize) -> io::Result<()> {
    if keep < 2 {
        // 极端配置：不保留历史，直接截断当前文件。
        let _ = fs::remove_file(dir.join(CURRENT_NAME));
        return Ok(());
    }
    let _ = fs::remove_file(dir.join(format!("{CURRENT_NAME}.{}", keep - 1)));
    for i in (1..keep - 1).rev() {
        let from = dir.join(format!("{CURRENT_NAME}.{i}"));
        let to = dir.join(format!("{CURRENT_NAME}.{}", i + 1));
        let _ = fs::rename(from, to);
    }
    fs::rename(dir.join(CURRENT_NAME), dir.join(format!("{CURRENT_NAME}.1")))
}

/// 单行净化：换行转义为 `\n` 字面量、去除控制噪音、超长截断。
fn sanitize(message: &str) -> String {
    let mut out = String::with_capacity(message.len().min(MAX_LINE_CHARS));
    for ch in message.chars() {
        if out.chars().count() >= MAX_LINE_CHARS {
            out.push('…');
            break;
        }
        match ch {
            '\n' => out.push_str("\\n"),
            '\r' => {}
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\x{:02x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// 当前 UTC 时间（RFC 3339 风格，毫秒精度）；std-only 民历换算。
fn utc_now_string() -> String {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    utc_from_secs_millis(now.as_secs(), now.subsec_millis())
}

fn utc_from_secs_millis(secs: u64, millis: u32) -> String {
    let days = (secs / 86_400) as i64;
    let sod = secs % 86_400;
    let (y, m, d) = civil_from_days(days);
    format!("{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{millis:03}Z", sod / 3600, (sod % 3600) / 60, sod % 60)
}

/// Howard Hinnant civil_from_days：天数（自 1970-01-01）→ (年, 月, 日)。
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn production_constants_match_d0020() {
        assert_eq!(MAX_FILE_BYTES, 5_242_880, "单文件上限 5 MiB = 5,242,880 字节（D-0020）");
        assert_eq!(KEEP_FILES, 3, "保留最近 3 份（含当前）（D-0020）");
    }

    #[test]
    fn utc_format_known_timestamps() {
        assert_eq!(utc_from_secs_millis(0, 0), "1970-01-01T00:00:00.000Z");
        assert_eq!(utc_from_secs_millis(1_767_225_600, 250), "2026-01-01T00:00:00.250Z");
        assert_eq!(utc_from_secs_millis(951_782_400, 1), "2000-02-29T00:00:00.001Z", "闰年 2 月 29 日");
        assert_eq!(utc_from_secs_millis(1_234_567_890, 999), "2009-02-13T23:31:30.999Z");
    }

    #[test]
    fn sanitize_replaces_newlines_and_caps_length() {
        // \r 被直接丢弃；\n 与 \t 转义为字面量
        assert_eq!(sanitize("a\nb\rc\td"), "a\\nbc\\td");
        let long = "x".repeat(5_000);
        let out = sanitize(&long);
        assert_eq!(out.chars().count(), MAX_LINE_CHARS + 1, "截断至上限并追加省略号");
        assert!(out.ends_with('…'));
        assert!(!out.contains('\n'), "单行输出");
    }

    /// 端到端（对显式 LogState 直测内部函数，绕开全局态——其他单测会并发写全局日志）：
    /// 轮转 → 保留 3 份 → 最旧滚出 → 目录删除后不 panic 且自动重建。
    #[test]
    fn logging_rotation_direct_state() {
        let dir = std::env::temp_dir().join(format!("clipforge-logging-rot-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let st = LogState { dir: dir.clone(), max_file_bytes: 200, keep_files: 3 };

        for i in 1..=30 {
            let _ = write_line(
                &st,
                "lifecycle",
                &format!("rotation test line {i:03} — padding to exceed the injected limit"),
            );
        }
        // 保留 3 份：current、.1、.2 存在；.3 不存在；各文件非空
        assert!(dir.join(CURRENT_NAME).is_file(), "当前日志应存在");
        assert!(dir.join(format!("{CURRENT_NAME}.1")).is_file(), "轮转历史 .1 应存在");
        assert!(dir.join(format!("{CURRENT_NAME}.2")).is_file(), "轮转历史 .2 应存在");
        assert!(!dir.join(format!("{CURRENT_NAME}.3")).exists(), "不得超过 3 份");
        let retained: String = [
            CURRENT_NAME.to_string(),
            format!("{CURRENT_NAME}.1"),
            format!("{CURRENT_NAME}.2"),
        ]
        .iter()
        .map(|n| fs::read_to_string(dir.join(n)).unwrap())
        .collect();
        assert!(retained.contains("line 030"), "最新内容应在保留窗口内");
        assert!(
            !retained.contains("line 001"),
            "最旧内容应被轮转删除（保留 3 份语义）"
        );

        // 日志异常不影响主流程：删除目录后继续写入（IO 失败静默、随后自动重建文件）
        fs::remove_dir_all(&dir).unwrap();
        let _ = write_line(&st, "lifecycle", "after dir removal (must not panic)");
        let _ = write_line(&st, "lifecycle", "recreate after removal");
        assert!(dir.join(CURRENT_NAME).is_file(), "写入应自动重建文件");
        let _ = fs::remove_dir_all(&dir);
    }

    /// 全局路径（顺序无关断言）：初始化失败 → Err 且保持禁用；初始化成功 → 写入产生文件。
    #[test]
    fn logging_global_init_paths() {
        let dir = std::env::temp_dir().join(format!("clipforge-logging-init-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        // 初始化失败（目录路径是已存在的文件）→ Err
        fs::create_dir_all(&dir).unwrap();
        let blocker = dir.join("blocker.txt");
        fs::write(&blocker, b"not a directory").unwrap();
        assert!(init_with(blocker.clone(), 200, 3).is_err(), "以文件路径为目录应失败");
        // 成功初始化（全局；其他并发测试的写入可能混入——只断言文件存在）
        let real_dir = dir.join("logs");
        init_with(real_dir.clone(), 200, 3).expect("初始化应成功");
        log_line("lifecycle", "global init smoke line");
        assert!(real_dir.join(CURRENT_NAME).is_file(), "全局初始化后应产生日志文件");
        let _ = fs::remove_dir_all(&dir);
    }

    /// 全局态顺序无关断言：未初始化/任意状态下 log_line 不 panic（主流程不受影响）。
    #[test]
    fn log_line_never_panics() {
        log_line("lifecycle", "never-panics probe (initialized or not)");
    }
}

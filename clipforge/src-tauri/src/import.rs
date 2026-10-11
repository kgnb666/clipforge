//! Phase 2A 导入基础：文件系统层校验、规范化去重与条目状态。
//!
//! 阶段边界（严格对应 `docs/requirements-and-acceptance.md` 的 P2A-001 ~ P2A-010 与修订后的 Gate-2A）：
//! - 本模块只负责"导入条目"的创建与登记，**不读取媒体信息**（FFprobe 属 Phase 2B），
//!   因此**不按扩展名判断媒体真伪**——媒体"非媒体"判定由 Phase 2B 基于 FFprobe 实测完成（P2A-006 / P2B-011）。
//! - 只读访问用户文件：校验仅打开读句柄，不写入、不移动、不删除、不修改源文件（ARCH-003）。
//! - 路径按不可信输入处理：只交给文件系统 API，绝不拼接进任何 shell 命令（ARCH-001 / ARCH-002）。
//! - 单条失败不崩溃：一切校验失败都以结构化的"失败条目"返回（ARCH-005）。

use serde::Serialize;
use std::fs::File;
use std::path::Path;
use std::sync::Mutex;

/// 条目可观察状态（P2A-008：Phase 2A 独立定义；不含 2B 的"读取中/已就绪"）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum EntryStatus {
    /// 已导入（路径校验通过）——仅代表文件系统层校验通过；媒体有效性属 Phase 2B。
    Ready,
    /// 导入失败（文件系统层），原因见 error_code / error_message。
    Failed,
}

/// 失败原因码（稳定标识，供 UI 与测试引用；与展示文案解耦）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ErrorCode {
    /// 路径为空或仅空白
    InvalidPath,
    /// 文件不存在或无法访问（P2A-004；不依赖任何媒体解析）
    NotFound,
    /// 路径存在但不是文件（如目录）
    NotAFile,
    /// 权限不足、无法读取（P2A-005；与 NotFound 可区分）
    PermissionDenied,
    /// 其他访问失败（附 OS 错误码）
    AccessFailed,
}

impl ErrorCode {
    fn as_str(self) -> &'static str {
        match self {
            ErrorCode::InvalidPath => "INVALID_PATH",
            ErrorCode::NotFound => "NOT_FOUND",
            ErrorCode::NotAFile => "NOT_A_FILE",
            ErrorCode::PermissionDenied => "PERMISSION_DENIED",
            ErrorCode::AccessFailed => "ACCESS_FAILED",
        }
    }
}

/// 前端可见的条目视图。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportEntry {
    pub id: u64,
    /// 文件名（展示用，与系统一致；不做转义）
    pub file_name: String,
    /// 完整路径——**始终保留完整值**；界面可截断显示，但内部操作与 DOM 均以完整路径为准。
    pub path: String,
    pub status: EntryStatus,
    /// 失败时的稳定错误码
    pub error_code: Option<String>,
    /// 失败时的可读原因
    pub error_message: Option<String>,
}

/// 内部存储：条目 + 判重键（判重键不对外暴露）。
#[derive(Debug, Clone)]
struct StoredEntry {
    entry: ImportEntry,
    /// 规范化路径 + 大小写折叠（Windows 路径大小写不敏感；D-0016）
    comparison_key: String,
}

#[derive(Debug, Default)]
struct Registry {
    entries: Vec<StoredEntry>,
    next_id: u64,
}

/// 导入登记表（Tauri 托管状态；进程内会话级）。
#[derive(Debug, Default)]
pub struct ImportState {
    registry: Mutex<Registry>,
}

/// 创建结果。
/// - `outcome = "created"`：新增条目（状态可能为 Ready 或 Failed）；
/// - `outcome = "duplicate"`：同路径已在列表中——不新增条目，既有条目状态不变（P2A-007）。
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateImportResult {
    pub outcome: String,
    pub entry: ImportEntry,
}

impl ImportState {
    /// 新增导入条目（含失败登记）。重复路径按规范化判重键去重。
    pub fn create_entry(&self, path: &str) -> CreateImportResult {
        let mut registry = self.lock();
        let key = comparison_key(path);
        if let Some(existing) = registry.entries.iter().find(|e| e.comparison_key == key) {
            return CreateImportResult {
                outcome: "duplicate".to_string(),
                entry: existing.entry.clone(),
            };
        }
        let id = registry.next_id;
        registry.next_id += 1;
        let entry = build_entry(id, path);
        registry.entries.push(StoredEntry {
            entry: entry.clone(),
            comparison_key: key,
        });
        CreateImportResult {
            outcome: "created".to_string(),
            entry,
        }
    }

    /// 当前条目列表（按创建顺序）。
    pub fn list_entries(&self) -> Vec<ImportEntry> {
        self.lock().entries.iter().map(|e| e.entry.clone()).collect()
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Registry> {
        // 互斥锁中毒时恢复内部数据：命令层不允许 panic（ARCH-005）。
        self.registry
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

/// 为给定路径构建条目（含文件系统层校验；不修改源文件）。
fn build_entry(id: u64, path_str: &str) -> ImportEntry {
    let (status, error_code, error_message) = match validate_readable_file(path_str) {
        Ok(()) => (EntryStatus::Ready, None, None),
        Err((code, message)) => (
            EntryStatus::Failed,
            Some(code.as_str().to_string()),
            Some(message),
        ),
    };

    ImportEntry {
        id,
        file_name: file_name_of(path_str),
        path: path_str.to_string(),
        status,
        error_code,
        error_message,
    }
}

/// 展示用文件名：取路径末段；末段缺失（如以分隔符结尾）时回退为完整路径字符串。
fn file_name_of(path_str: &str) -> String {
    Path::new(path_str)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| path_str.to_string())
}

/// 只读校验：失败返回 `(错误码, 可读原因)`。
fn validate_readable_file(path_str: &str) -> Result<(), (ErrorCode, String)> {
    if path_str.trim().is_empty() {
        return Err((ErrorCode::InvalidPath, "未提供文件路径".to_string()));
    }
    let path = Path::new(path_str);
    if !path.exists() {
        // P2A-004：不存在/无效路径（父级不可达等同此语义）；纯文件系统检查，不依赖媒体解析。
        return Err((
            ErrorCode::NotFound,
            "文件不存在或无法访问".to_string(),
        ));
    }
    if !path.is_file() {
        return Err((ErrorCode::NotAFile, "所选路径不是文件".to_string()));
    }
    match File::open(path) {
        Ok(_) => Ok(()),
        Err(err) => match err.kind() {
            std::io::ErrorKind::PermissionDenied => Err((
                ErrorCode::PermissionDenied,
                "权限不足：无法读取所选文件".to_string(),
            )),
            _ => Err((
                ErrorCode::AccessFailed,
                format!(
                    "无法访问所选文件（系统错误 {}）",
                    err.raw_os_error().unwrap_or(0)
                ),
            )),
        },
    }
}

/// 判重键：能解析时用 canonicalize（解析 `..`、链接与真实大小写）；否则退化为绝对化路径；
/// 最后做大小写折叠（Windows 路径大小写不敏感，D-0016）。
fn comparison_key(path_str: &str) -> String {
    if path_str.trim().is_empty() {
        // NUL 不可能出现在 Windows 路径中：为无效路径提供互不冲突的判重键。
        return format!("\u{0}invalid:{path_str}");
    }
    let raw = Path::new(path_str);
    let normalized = std::fs::canonicalize(raw).unwrap_or_else(|_| {
        if raw.is_absolute() {
            raw.to_path_buf()
        } else {
            std::env::current_dir()
                .map(|cwd| cwd.join(raw))
                .unwrap_or_else(|_| raw.to_path_buf())
        }
    });
    normalized.to_string_lossy().to_lowercase()
}

/// 为给定路径创建导入条目（路径一律按不可信输入在 Rust 侧校验；前端不做文件系统判断）。
#[tauri::command]
pub fn create_import_entry(state: tauri::State<'_, ImportState>, path: String) -> CreateImportResult {
    state.create_entry(&path)
}

/// 返回当前导入条目列表（按创建顺序）。
#[tauri::command]
pub fn list_import_entries(state: tauri::State<'_, ImportState>) -> Vec<ImportEntry> {
    state.list_entries()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::path::PathBuf;
    use std::time::SystemTime;

    fn tests_dir() -> PathBuf {
        let dir = std::env::temp_dir().join("clipforge-gate2a-tests");
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn temp_path(name: &str) -> PathBuf {
        tests_dir().join(name)
    }

    fn write_temp(name: &str, bytes: &[u8]) -> PathBuf {
        let path = temp_path(name);
        let mut file = File::create(&path).unwrap();
        file.write_all(bytes).unwrap();
        file.flush().unwrap();
        path
    }

    fn snapshot(path: &Path) -> (SystemTime, Vec<u8>) {
        let metadata = std::fs::metadata(path).unwrap();
        (metadata.modified().unwrap(), std::fs::read(path).unwrap())
    }

    #[test]
    fn valid_file_imports_ready_and_source_untouched() {
        // P2A-003（2A 范围）：导入校验只读，源文件内容与 mtime 不变。
        let path = write_temp("valid_case.mp4", b"placeholder content, kept as-is");
        let before = snapshot(&path);
        let state = ImportState::default();
        let result = state.create_entry(&path.to_string_lossy());
        assert_eq!(result.outcome, "created");
        assert_eq!(result.entry.status, EntryStatus::Ready);
        assert!(result.entry.error_code.is_none());
        let after = snapshot(&path);
        assert_eq!(before, after, "导入校验不得修改源文件（内容与 mtime）");
    }

    #[test]
    fn fake_extension_is_not_judged_in_phase_2a() {
        // P2A-006（2A 范围）：不按扩展名判定媒体真伪——
        // 文本内容改名的 .mp4 与无扩展名文件均应正常登记；媒体判定属 Phase 2B（P2B-011）。
        let fake = write_temp("fake_text.mp4", b"this is plain text, not a video");
        let no_extension = write_temp("no_extension_file", b"plain content");
        let state = ImportState::default();
        assert_eq!(
            state.create_entry(&fake.to_string_lossy()).entry.status,
            EntryStatus::Ready
        );
        assert_eq!(
            state.create_entry(&no_extension.to_string_lossy()).entry.status,
            EntryStatus::Ready
        );
    }

    #[test]
    fn nonexistent_path_fails_with_not_found() {
        let missing = temp_path("definitely_missing_file_xyz.mp4");
        let _ = std::fs::remove_file(&missing);
        let state = ImportState::default();
        let result = state.create_entry(&missing.to_string_lossy());
        assert_eq!(result.entry.status, EntryStatus::Failed);
        assert_eq!(result.entry.error_code.as_deref(), Some("NOT_FOUND"));
    }

    #[test]
    fn directory_fails_with_not_a_file() {
        let dir = tests_dir();
        let state = ImportState::default();
        let result = state.create_entry(&dir.to_string_lossy());
        assert_eq!(result.entry.status, EntryStatus::Failed);
        assert_eq!(result.entry.error_code.as_deref(), Some("NOT_A_FILE"));
    }

    #[test]
    fn empty_path_fails_with_invalid_path() {
        let state = ImportState::default();
        assert_eq!(
            state.create_entry("").entry.error_code.as_deref(),
            Some("INVALID_PATH")
        );
        assert_eq!(
            state.create_entry("   ").entry.error_code.as_deref(),
            Some("INVALID_PATH")
        );
    }

    #[test]
    fn duplicate_same_path_not_added_twice() {
        // P2A-007：重复选择同一文件不新增条目，返回既有条目。
        let path = write_temp("dup_case.mp4", b"x");
        let state = ImportState::default();
        let first = state.create_entry(&path.to_string_lossy());
        let second = state.create_entry(&path.to_string_lossy());
        assert_eq!(first.outcome, "created");
        assert_eq!(second.outcome, "duplicate");
        assert_eq!(second.entry.id, first.entry.id, "重复选择必须返回既有条目");
        assert_eq!(state.list_entries().len(), 1);
    }

    #[test]
    fn duplicate_detection_is_case_insensitive_for_unresolvable_paths() {
        // 不存在的路径无法 canonicalize：验证"绝对化 + 大小写折叠"判重键（D-0016）。
        let first_input = r"C:\ClipForge_NoSuchDir_QA\Sample.MP4";
        let second_input = r"c:\clipforge_nosuchdir_qa\sample.mp4";
        let state = ImportState::default();
        assert_eq!(state.create_entry(first_input).outcome, "created");
        let second = state.create_entry(second_input);
        assert_eq!(second.outcome, "duplicate");
        assert_eq!(state.list_entries().len(), 1);
    }

    #[test]
    fn failed_entry_is_not_replaced_on_repick() {
        // P2A-007：既有条目状态不变——失败条目再次选择同一路径返回 duplicate，不覆盖原状态。
        let missing = temp_path("not_present_repick.mp4");
        let _ = std::fs::remove_file(&missing);
        let state = ImportState::default();
        let first = state.create_entry(&missing.to_string_lossy());
        assert_eq!(first.entry.status, EntryStatus::Failed);
        let second = state.create_entry(&missing.to_string_lossy());
        assert_eq!(second.outcome, "duplicate");
        assert_eq!(second.entry.status, EntryStatus::Failed);
    }

    #[test]
    fn special_character_paths_are_handled_verbatim() {
        // P2A-009（2A 范围）：中文/空格/& 等路径的登记与展示值不做转义、不改写。
        let dir = std::env::temp_dir().join("clipforge-gate2a-测试 目录 & qa");
        std::fs::create_dir_all(&dir).unwrap();
        let name = "样本 视频 #1 (初版)'s.mp4";
        let path = dir.join(name);
        let mut file = File::create(&path).unwrap();
        file.write_all(b"pi").unwrap();
        drop(file);

        let state = ImportState::default();
        let given = path.to_string_lossy().into_owned();
        let result = state.create_entry(&given);
        assert_eq!(result.entry.status, EntryStatus::Ready);
        assert_eq!(result.entry.file_name, name);
        assert_eq!(result.entry.path, given, "展示路径必须与选择值逐字一致（不转义、不改写）");
    }
}

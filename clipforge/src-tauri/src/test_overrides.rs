//! Phase 2B-1：仅 Debug 构建启用的受控测试覆盖（依据 D-0023、规格 §10.1 / §10.3）。
//!
//! 安全边界：
//! - 本模块整体仅在 `#[cfg(debug_assertions)]` 下编译（见 `lib.rs`），Release 构建不含任何覆盖逻辑；
//! - 工具路径覆盖（`CLIPFORGE_TEST_FFPROBE`）必须为绝对路径、不含 `..`，且**必须位于专用测试替身目录**
//!   `stage2\test-tools\fake-ffprobe\` 之下（路径标记校验）；不满足即忽略（返回 None）；
//! - 超时覆盖（`CLIPFORGE_TEST_PROBE_TIMEOUT_MS`）仅接受 1..=30000 毫秒的整数；非法值忽略；
//! - 覆盖值为"配置的最终答案"：设置有效工具覆盖后**不再回退**常规发现（保证"工具不存在"场景可复现）；
//! - 环境变量名以 `CLIPFORGE_TEST_` 前缀隔离，正常用户环境不会意外触发。

use std::path::{Component, Path, PathBuf};

/// 工具路径覆盖环境变量名。
pub const FFPROBE_OVERRIDE_ENV: &str = "CLIPFORGE_TEST_FFPROBE";
/// 超时覆盖环境变量名（毫秒）。
pub const TIMEOUT_OVERRIDE_ENV: &str = "CLIPFORGE_TEST_PROBE_TIMEOUT_MS";
/// 超时覆盖允许的最大值（毫秒；不得放大默认 30 秒硬超时）。
pub const TIMEOUT_OVERRIDE_MAX_MS: u64 = 30_000;

/// 测试替身目录的路径标记（规范化、小写化后必须包含；以分隔符结尾）。
const ALLOWED_TOOLS_MARKER: &str = "stage2\\test-tools\\fake-ffprobe\\";

/// 读取并校验工具路径覆盖；无效一律返回 None（不报错、不回退判断由调用方执行）。
pub fn ffprobe_override_path() -> Option<PathBuf> {
    let raw = std::env::var_os(FFPROBE_OVERRIDE_ENV)?;
    validate_override_path(Path::new(&raw))
}

/// 纯校验函数（可单测）：绝对路径 + 无 `..` + 位于测试替身目录标记之下。
pub(crate) fn validate_override_path(path: &Path) -> Option<PathBuf> {
    if !path.is_absolute() {
        return None;
    }
    if path
        .components()
        .any(|c| matches!(c, Component::ParentDir))
    {
        return None;
    }
    let mut normalized = path.to_string_lossy().replace('/', "\\").to_lowercase();
    if !normalized.ends_with('\\') {
        normalized.push('\\');
    }
    if !normalized.contains(ALLOWED_TOOLS_MARKER) {
        return None;
    }
    Some(path.to_path_buf())
}

/// 读取并校验超时覆盖（毫秒）；非法值返回 None。
pub fn timeout_override_ms() -> Option<u64> {
    let raw = std::env::var_os(TIMEOUT_OVERRIDE_ENV)?;
    validate_timeout_override(&raw.to_string_lossy())
}

/// 纯校验函数（可单测）：1..=30000 的整数（允许首尾空白）。
pub(crate) fn validate_timeout_override(raw: &str) -> Option<u64> {
    let ms: u64 = raw.trim().parse().ok()?;
    if ms == 0 || ms > TIMEOUT_OVERRIDE_MAX_MS {
        return None;
    }
    Some(ms)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tools_dir_exe(name: &str) -> String {
        // 仅用于校验测试的字符串（不需要真实存在）。
        format!(
            "D:\\应聘项目zcode\\docs\\evidence\\stage2\\test-tools\\fake-ffprobe\\target\\debug\\{name}"
        )
    }

    #[test]
    fn validate_override_path_accepts_paths_inside_tools_dir() {
        let p = PathBuf::from(tools_dir_exe("fake-ffprobe-exit1.exe"));
        assert_eq!(validate_override_path(&p), Some(p.clone()));
        // 大小写与正斜杠也应通过（规范化为小写 + 反斜杠）
        let alt = PathBuf::from(tools_dir_exe("X").replace("test-tools", "TEST-TOOLS").replace('\\', "/"));
        assert!(validate_override_path(&alt).is_some());
    }

    #[test]
    fn validate_override_path_rejects_relative_missing_marker_and_parent_dir() {
        assert_eq!(validate_override_path(Path::new("fake-ffprobe.png")), None); // 相对路径
        assert_eq!(
            validate_override_path(Path::new("D:\\other\\fake-ffprobe.exe")),
            None // 目录标记不匹配
        );
        let with_parent = PathBuf::from(format!(
            "D:\\docs\\stage2\\..\\test-tools\\fake-ffprobe\\a.exe"
        ));
        assert_eq!(validate_override_path(&with_parent), None); // 含 ..
    }

    #[test]
    fn validate_timeout_override_bounds() {
        assert_eq!(validate_timeout_override("1500"), Some(1500));
        assert_eq!(validate_timeout_override(" 200 "), Some(200));
        assert_eq!(validate_timeout_override("1"), Some(1));
        assert_eq!(validate_timeout_override("30000"), Some(30_000));
        assert_eq!(validate_timeout_override("0"), None);
        assert_eq!(validate_timeout_override("30001"), None);
        assert_eq!(validate_timeout_override("abc"), None);
        assert_eq!(validate_timeout_override("-5"), None);
        assert_eq!(validate_timeout_override(""), None);
    }
}

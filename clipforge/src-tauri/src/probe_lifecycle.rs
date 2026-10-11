//! Phase 2C-1 Step 2：Probe 生命周期管理（D-0024 修复；方案 A：取消令牌 + Child 句柄登记）。
//!
//! 职责（对应 Stage 2C-1 Step 1 基线报告 §3/§4 的根因）：
//! - 登记运行中的探测任务（按条目 ID），与探测线程共享**同一**子进程句柄槽位与取消令牌；
//! - 提供统一的 `shutdown_all`：应用退出（`RunEvent::Exit`，见 `lib.rs`）时取消全部任务、
//!   终止并回收（kill + wait）在途 FFprobe 子进程，等待任务收敛（有界，默认 ≤2 秒）；
//! - std-only 实现（`Arc`/`Mutex`/`AtomicBool`），不新增任何依赖。

use std::collections::HashMap;
use std::process::Child;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// 取消令牌：探测轮询循环在每次迭代检查；置位后任务应终止子进程并尽快返回。
/// 克隆共享同一布尔值（`Arc<AtomicBool>`）。
#[derive(Debug, Clone, Default)]
pub struct CancelToken(Arc<AtomicBool>);

impl CancelToken {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.0.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }
}

/// 任务生命周期状态（Stage 2C-2，C2-D1：仅后端内部管理；不暴露 UI、不改变任何错误分类语义）。
///
/// 转移（进入 → 退出）：
/// - `Pending`：`register` 登记成功（工具已发现）→ spawn 成功后 `Running`；关闭时 → `Cancelled`。
/// - `Running`：子进程句柄已入共享槽位 → 进程退出后 `Completed`/`Failed`（按最终结果）；
///   关闭时 → `Cancelled`。
/// - `Completed`：探测成功返回（含"无音轨"等正常数据）。
/// - `Failed`：返回任何非取消错误（START_FAILED / NONZERO_EXIT / TIMEOUT / PARSE_FAILED / MEDIA_UNSUPPORTED）。
/// - `Cancelled`：`shutdown_all` 置位，或结果为 `FFPROBE_CANCELLED`。
/// 终态任务由探测线程路径 `take_finished` 移除登记；`shutdown_all` 有界等待该收敛。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProbeTaskStatus {
    Pending,
    Running,
    Completed,
    Failed,
    Cancelled,
}

impl ProbeTaskStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "Pending",
            Self::Running => "Running",
            Self::Completed => "Completed",
            Self::Failed => "Failed",
            Self::Cancelled => "Cancelled",
        }
    }
}

/// 运行中的探测任务：句柄槽位（`Some` = 子进程在途）、取消令牌与生命周期状态。
/// 由探测线程与 `ProbeTaskManager` 经 `Arc` 共享；不自持线程句柄（线程随进程退出）。
#[derive(Debug)]
pub struct ProbeTask {
    pub entry_id: u64,
    /// 子进程句柄槽位：spawn 后由探测线程放入；完成/超时/取消/shutdown 路径取走。
    pub child: Arc<Mutex<Option<Child>>>,
    pub cancel: CancelToken,
    status: Mutex<ProbeTaskStatus>,
}

impl ProbeTask {
    /// 存入子进程句柄（spawn 成功后调用）。
    pub fn store_child(&self, child: Child) {
        *lock_child(&self.child) = Some(child);
    }

    /// 取走子进程句柄（若存在）。
    pub fn take_child(&self) -> Option<Child> {
        lock_child(&self.child).take()
    }

    /// 子进程句柄当前是否在槽（非破坏性检查；供生命周期测试与审计）。
    pub fn has_child(&self) -> bool {
        lock_child(&self.child).is_some()
    }

    /// 当前生命周期状态。
    pub fn status(&self) -> ProbeTaskStatus {
        *lock_status(&self.status)
    }

    /// 推进状态（由探测封装路径按转移规则调用；仅后端内部使用）。
    pub fn set_status(&self, status: ProbeTaskStatus) {
        *lock_status(&self.status) = status;
    }

    /// 仅当任务仍处于活动态（Pending/Running）时标记为 `Cancelled`；
    /// 已到终态（Completed/Failed）的任务不被关闭路径改写。
    pub fn mark_cancelled_if_active(&self) {
        let mut status = lock_status(&self.status);
        if matches!(*status, ProbeTaskStatus::Pending | ProbeTaskStatus::Running) {
            *status = ProbeTaskStatus::Cancelled;
        }
    }
}

/// 统一任务管理器：登记运行中的探测任务，提供退出清理入口。
/// 克隆廉价（内部 `Arc`），可整体移动进 `spawn_blocking` 闭包。
#[derive(Debug, Clone, Default)]
pub struct ProbeTaskManager {
    running: Arc<Mutex<HashMap<u64, Arc<ProbeTask>>>>,
    peak_running: Arc<AtomicUsize>,
}

/// `shutdown_all` 的结果摘要（用于退出日志与验收证据）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShutdownSummary {
    /// 被取消（置位令牌）的任务数。
    pub cancelled: usize,
    /// 完成终止并回收（kill + wait 成功）的子进程数。
    pub reaped: usize,
    /// 清理后仍在登记表中的任务数（有界等待结束时；正常应為 0）。
    pub remaining: usize,
    /// 本次进程生命周期内登记表达到的峰值任务数（观测用）。
    pub peak_running: usize,
    pub elapsed_ms: u128,
    /// 逐任务错误（kill/wait 失败等；正常为空）。
    pub errors: Vec<String>,
}

impl ProbeTaskManager {
    /// 登记任务（状态置 `Pending`；同条目重复登记将覆盖旧条目——常规流程由
    /// `ProbeStateStore::begin` 防并发，不应发生）。
    pub fn register(&self, entry_id: u64) -> Arc<ProbeTask> {
        let task = Arc::new(ProbeTask {
            entry_id,
            child: Arc::new(Mutex::new(None)),
            cancel: CancelToken::new(),
            status: Mutex::new(ProbeTaskStatus::Pending),
        });
        let count = {
            let mut running = self.lock_running();
            running.insert(entry_id, task.clone());
            running.len()
        };
        self.peak_running.fetch_max(count, Ordering::SeqCst);
        task
    }

    /// 移除并返回任务（终态路径；幂等——不存在时返回 `None`）。
    pub fn take_finished(&self, entry_id: u64) -> Option<Arc<ProbeTask>> {
        self.lock_running().remove(&entry_id)
    }

    pub fn running_count(&self) -> usize {
        self.lock_running().len()
    }

    pub fn contains(&self, entry_id: u64) -> bool {
        self.lock_running().contains_key(&entry_id)
    }

    /// 登记表在本进程生命周期内的峰值任务数（观测用）。
    pub fn peak_running(&self) -> usize {
        self.peak_running.load(Ordering::SeqCst)
    }

    /// 取得共享同一登记表的克隆（供移动进 `spawn_blocking` 闭包；廉价——内部为 `Arc`）。
    pub fn clone_shared(&self) -> Self {
        self.clone()
    }

    /// 取消全部任务并终止/回收其子进程，随后有界等待任务收敛（探测线程经取消路径自行移除登记）。
    ///
    /// - 立即：对所有登记任务置位取消令牌、把活动态（Pending/Running）任务标记为 `Cancelled`
    ///   （不覆盖 Completed/Failed 终态），并取走已 spawn 的子进程句柄（kill + wait）；
    /// - 等待：直到登记表清空或 `max_wait` 到期；
    /// - 尚未 spawn 的任务（槽位为空）由探测线程在 spawn 后的自检中终止（取消标志优先）。
    pub fn shutdown_all(&self, max_wait: Duration) -> ShutdownSummary {
        let started = Instant::now();
        let mut cancelled = 0usize;
        let mut taken: Vec<(u64, Child)> = Vec::new();
        {
            let running = self.lock_running();
            for (id, task) in running.iter() {
                task.cancel.cancel();
                task.mark_cancelled_if_active();
                cancelled += 1;
                if let Some(child) = task.take_child() {
                    taken.push((*id, child));
                }
            }
        }
        let mut reaped = 0usize;
        let mut errors = Vec::new();
        for (id, mut child) in taken {
            if let Err(err) = child.kill() {
                errors.push(format!("task {id}: kill 失败：{err}"));
            }
            match child.wait() {
                Ok(_) => reaped += 1,
                Err(err) => errors.push(format!("task {id}: wait 失败：{err}")),
            }
        }
        // 有界等待收敛：探测线程经取消路径移除登记（轮询间隔 50ms 量级）。
        while started.elapsed() < max_wait {
            if self.running_count() == 0 {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let remaining = self.running_count();
        ShutdownSummary {
            cancelled,
            reaped,
            remaining,
            peak_running: self.peak_running(),
            elapsed_ms: started.elapsed().as_millis(),
            errors,
        }
    }

    fn lock_running(&self) -> std::sync::MutexGuard<'_, HashMap<u64, Arc<ProbeTask>>> {
        self.running
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

pub(crate) fn lock_child(slot: &Mutex<Option<Child>>) -> std::sync::MutexGuard<'_, Option<Child>> {
    slot.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn lock_status(slot: &Mutex<ProbeTaskStatus>) -> std::sync::MutexGuard<'_, ProbeTaskStatus> {
    slot.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::{Command, Stdio};

    /// 直接子进程（ping.exe，约存活 29 秒；测试经 shutdown 终止并回收，不产生孤儿）。
    fn spawn_long_child() -> Child {
        Command::new("ping")
            .args(["-n", "30", "127.0.0.1"])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn ping")
    }

    #[test]
    fn cancel_token_propagates_through_clones() {
        let token = CancelToken::new();
        let clone = token.clone();
        assert!(!token.is_cancelled());
        assert!(!clone.is_cancelled());
        clone.cancel();
        assert!(token.is_cancelled(), "克隆与本体共享取消状态");
        assert!(clone.is_cancelled());
    }

    #[test]
    fn register_and_remove_task() {
        let manager = ProbeTaskManager::default();
        assert_eq!(manager.running_count(), 0);
        let task = manager.register(42);
        assert!(manager.contains(42));
        assert_eq!(manager.running_count(), 1);
        assert_eq!(task.entry_id, 42);
        assert_eq!(task.status(), ProbeTaskStatus::Pending, "登记即 Pending");
        assert!(!task.cancel.is_cancelled());
        assert!(task.take_child().is_none(), "刚登记的任务无子进程");
        let taken = manager.take_finished(42);
        assert!(taken.is_some(), "移除已存在任务返回 Some");
        assert_eq!(taken.unwrap().status(), ProbeTaskStatus::Pending);
        assert!(!manager.contains(42));
        assert!(manager.take_finished(42).is_none(), "重复移除幂等返回 None");
        assert_eq!(manager.running_count(), 0);
    }

    #[test]
    fn shutdown_all_with_no_tasks_is_noop() {
        let manager = ProbeTaskManager::default();
        let summary = manager.shutdown_all(Duration::from_millis(100));
        assert_eq!(summary.cancelled, 0);
        assert_eq!(summary.reaped, 0);
        assert_eq!(summary.remaining, 0);
        assert!(summary.errors.is_empty());
        assert!(summary.elapsed_ms < 1000, "空表应立即返回");
    }

    #[test]
    fn shutdown_all_cancels_tasks_without_children() {
        let manager = ProbeTaskManager::default();
        let t1 = manager.register(1);
        let t2 = manager.register(2);
        // 无真实探测线程的登记任务不会自行移除：等待将耗尽 max_wait（有界），任务保持登记。
        let summary = manager.shutdown_all(Duration::from_millis(120));
        assert_eq!(summary.cancelled, 2);
        assert_eq!(summary.reaped, 0, "无子进程可回收");
        assert!(t1.cancel.is_cancelled() && t2.cancel.is_cancelled(), "shutdown 必须向全部任务传播取消");
        assert_eq!(summary.remaining, 2, "无探测线程的登记项由调用方负责（测试内显式清理）");
        assert!(summary.elapsed_ms >= 100, "有界等待应生效");
        assert!(manager.take_finished(1).is_some());
        assert!(manager.take_finished(2).is_some());
        assert_eq!(manager.running_count(), 0);
    }

    #[test]
    fn shutdown_all_kills_and_reaps_multiple_children() {
        // 端到端：3 个真实探测线程（managed 路径）在途 → shutdown_all 取消、终止、回收、收敛。
        // 使用已构建的延迟替身（登记于证据目录，随仓库提供）；输入用既有样片。
        use crate::probe::{probe_file_managed, ProbeFailureCode};
        let base = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("docs")
            .join("evidence")
            .join("stage2");
        let delay_exe = base
            .join("test-tools")
            .join("fake-ffprobe")
            .join("target")
            .join("debug")
            .join("fake-ffprobe-delay.exe");
        assert!(delay_exe.is_file(), "延迟替身应已构建：{}", delay_exe.display());
        let sample = base.join("..").join("gate0c-media").join("sample_src.mkv");
        assert!(sample.is_file(), "样片应存在：{}", sample.display());

        let manager = ProbeTaskManager::default();
        let handles: Vec<_> = [21u64, 22, 23]
            .into_iter()
            .map(|id| {
                let manager = manager.clone();
                let tool = delay_exe.clone();
                let input = sample.clone();
                std::thread::spawn(move || {
                    probe_file_managed(&tool, &input, 30_000, &manager, id)
                })
            })
            .collect();
        // 等待三个任务全部登记并完成 spawn（子进程句柄入槽）。
        let deadline = Instant::now() + Duration::from_secs(5);
        while manager.running_count() < 3 && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        std::thread::sleep(Duration::from_millis(300));
        assert_eq!(manager.running_count(), 3, "三个探测任务应全部在途");

        let summary = manager.shutdown_all(Duration::from_secs(2));
        assert_eq!(summary.cancelled, 3, "全部任务被取消");
        assert_eq!(summary.reaped, 3, "全部子进程由 shutdown 完成 kill+wait");
        assert_eq!(summary.remaining, 0, "探测线程经取消路径移除登记，登记表收敛为空");
        assert!(summary.errors.is_empty(), "不应有 kill/wait 错误：{:?}", summary.errors);
        assert!(summary.elapsed_ms < 2000, "应在有界时间内完成（实际 {}ms）", summary.elapsed_ms);

        for handle in handles {
            let result = handle.join().expect("探测线程不应 panic");
            let failure = result.expect_err("被取消的探测必须返回 Cancelled 错误");
            assert_eq!(failure.code, ProbeFailureCode::Cancelled);
        }
        assert_eq!(manager.running_count(), 0);
    }

    #[test]
    fn shutdown_all_waits_for_worker_convergence() {
        // 模拟真实探测线程：登记 → 存入子进程 → 收到取消后经取消路径移除登记（有延迟）。
        let manager = ProbeTaskManager::default();
        let task = manager.register(9);
        task.store_child(spawn_long_child());
        let worker = {
            let manager = manager.clone();
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_millis(300));
                let _ = manager.take_finished(9);
            })
        };
        let summary = manager.shutdown_all(Duration::from_secs(2));
        let _ = worker.join();
        assert_eq!(summary.cancelled, 1);
        assert_eq!(summary.reaped, 1, "shutdown 侧完成 kill+wait");
        assert_eq!(summary.remaining, 0, "探测线程的移除发生在有界等待内");
        assert!(summary.elapsed_ms >= 300, "应等待任务实际收敛（实际 {}ms）", summary.elapsed_ms);
        assert!(summary.elapsed_ms < 2000);
    }
}

#[cfg(test)]
mod tests_2c2 {
    //! Stage 2C-2 生命周期测试（T1–T4；依赖已构建的受控替身与既有样片）。
    use super::*;
    use crate::probe::{probe_file_managed_task, ProbeFailureCode};
    use std::path::PathBuf;

    fn tool_exe(name: &str) -> PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("docs")
            .join("evidence")
            .join("stage2")
            .join("test-tools")
            .join("fake-ffprobe")
            .join("target")
            .join("debug")
            .join(name)
    }

    fn ok_double() -> PathBuf {
        tool_exe("fake-ffprobe-ok.exe")
    }

    fn exit1_double() -> PathBuf {
        tool_exe("fake-ffprobe-exit1.exe")
    }

    fn delay_double() -> PathBuf {
        tool_exe("fake-ffprobe-delay.exe")
    }

    fn sample() -> PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("docs")
            .join("evidence")
            .join("gate0c-media")
            .join("sample_src.mkv")
    }

    /// 生产等价 worker：以既登记任务执行探测 → 按结果推进终态 → 移除登记（与
    /// `probe_with_discovery_managed` 的序列一致；区别仅在于工具路径由测试直接给定）。
    fn spawn_worker(
        manager: ProbeTaskManager,
        entry_id: u64,
        tool: PathBuf,
        task: Arc<ProbeTask>,
    ) -> std::thread::JoinHandle<Result<crate::probe::ProbeMetadata, crate::probe::ProbeFailure>> {
        let input = sample();
        std::thread::spawn(move || {
            let result = probe_file_managed_task(&tool, &input, 30_000, task);
            let _ = manager.take_finished(entry_id);
            result
        })
    }

    fn wait_status(task: &ProbeTask, want: ProbeTaskStatus, timeout: Duration) -> bool {
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if task.status() == want {
                return true;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        task.status() == want
    }

    /// Test 1：正常完成 —— Pending → (Running) → Completed，结果字段来自结构化 JSON，task 清理。
    #[test]
    fn t1_normal_completion_lifecycle() {
        assert!(ok_double().is_file(), "ok 替身应已构建：{}", ok_double().display());
        assert!(sample().is_file());
        let manager = ProbeTaskManager::default();
        let task = manager.register(101);
        assert_eq!(task.status(), ProbeTaskStatus::Pending, "登记即 Pending");
        let worker = spawn_worker(manager.clone(), 101, ok_double(), task.clone());
        let result = worker.join().expect("worker 不应 panic");
        let meta = result.expect("ok 替身应成功");
        // 结果写入验证：解析字段与 ok 替身的结构化 JSON 一致（不猜测、不失真）。
        assert_eq!(meta.width, Some(320));
        assert_eq!(meta.height, Some(240));
        assert_eq!(meta.video_codec.as_deref(), Some("mpeg4"));
        assert!(meta.has_audio);
        assert_eq!(meta.audio_codec.as_deref(), Some("aac"));
        assert_eq!(meta.duration_secs, Some(1.75));
        assert_eq!(task.status(), ProbeTaskStatus::Completed, "正常完成终态");
        assert!(
            manager.take_finished(101).is_none(),
            "task 已由探测路径（生产序列）移除"
        );
        assert_eq!(manager.running_count(), 0, "task 清理完成");
        assert_eq!(manager.peak_running(), 1);
    }

    /// Test 2：失败流程 —— 原错误码保持（FFPROBE_NONZERO_EXIT），状态 Failed（≠Cancelled），task 清理。
    #[test]
    fn t2_failure_flow_preserves_error_code() {
        assert!(exit1_double().is_file());
        let manager = ProbeTaskManager::default();
        let task = manager.register(102);
        let worker = spawn_worker(manager.clone(), 102, exit1_double(), task.clone());
        let result = worker.join().expect("worker 不应 panic");
        let failure = result.expect_err("exit1 替身必须失败");
        assert_eq!(failure.code, ProbeFailureCode::NonZeroExit, "原错误码保持不变");
        assert_eq!(failure.code.as_str(), "FFPROBE_NONZERO_EXIT");
        assert_eq!(failure.exit_code, Some(1));
        assert!(failure.stderr_tail.as_deref().unwrap_or("").contains("fake-ffprobe-exit1"));
        assert_eq!(task.status(), ProbeTaskStatus::Failed, "失败流程终态为 Failed（≠Cancelled）");
        assert!(manager.take_finished(102).is_none(), "task 已由探测路径移除");
        assert_eq!(manager.running_count(), 0, "task 清理完成");
    }

    /// Test 3：关闭取消 —— 导入→FFprobe 运行→shutdown：child=0、task=0、状态 Cancelled（≠Timeout/Failed）。
    #[test]
    fn t3_shutdown_cancel_lifecycle() {
        assert!(delay_double().is_file());
        let manager = ProbeTaskManager::default();
        let task = manager.register(103);
        let worker = spawn_worker(manager.clone(), 103, delay_double(), task.clone());
        assert!(
            wait_status(&task, ProbeTaskStatus::Running, Duration::from_secs(5)),
            "延迟替身窗口内应观察到 Running"
        );
        assert!(task.has_child(), "在途子进程句柄应已入槽");
        let summary = manager.shutdown_all(Duration::from_secs(2));
        assert_eq!(summary.cancelled, 1);
        assert_eq!(summary.reaped, 1, "child=0：唯一子进程由 shutdown kill+wait 回收");
        assert_eq!(summary.remaining, 0, "task=0：探测线程经取消路径收敛移除");
        assert!(summary.errors.is_empty(), "{:?}", summary.errors);
        let result = worker.join().expect("worker 不应 panic");
        let failure = result.expect_err("被取消的探测必须返回错误");
        assert_eq!(failure.code, ProbeFailureCode::Cancelled, "Cancelled ≠ Timeout/Failed");
        assert_eq!(failure.code.as_str(), "FFPROBE_CANCELLED");
        assert_eq!(task.status(), ProbeTaskStatus::Cancelled);
        assert_eq!(manager.running_count(), 0);
    }

    /// Test 4：重试竞态 —— 失败 → retry → shutdown：无重复任务、单 Child、不覆盖既有错误结果。
    #[test]
    fn t4_retry_then_shutdown_no_duplicates() {
        assert!(exit1_double().is_file() && delay_double().is_file());
        let manager = ProbeTaskManager::default();
        // 第一次探测：失败（exit1）
        let t1 = manager.register(201);
        let w1 = spawn_worker(manager.clone(), 201, exit1_double(), t1.clone());
        let r1 = w1.join().expect("worker 不应 panic");
        assert_eq!(r1.unwrap_err().code, ProbeFailureCode::NonZeroExit);
        assert_eq!(t1.status(), ProbeTaskStatus::Failed);
        assert!(manager.take_finished(201).is_none(), "失败任务已由探测路径清理");
        // retry：同一条目重新登记（此刻在途任务唯一）
        let t2 = manager.register(201);
        assert_eq!(manager.running_count(), 1, "重试期间同一时刻仅一个登记任务（无重复任务）");
        let w2 = spawn_worker(manager.clone(), 201, delay_double(), t2.clone());
        assert!(
            wait_status(&t2, ProbeTaskStatus::Running, Duration::from_secs(5)),
            "重试在途应进入 Running"
        );
        assert_eq!(manager.running_count(), 1, "仍仅一个任务 → 不产生多个 Child 槽位");
        assert!(t2.has_child());
        // shutdown 命中重试在途
        let summary = manager.shutdown_all(Duration::from_secs(2));
        assert_eq!(summary.reaped, 1, "单 Child 被回收（child=0）");
        assert_eq!(summary.cancelled, 1);
        assert_eq!(summary.remaining, 0);
        let r2 = w2.join().expect("worker 不应 panic");
        assert_eq!(r2.unwrap_err().code, ProbeFailureCode::Cancelled);
        assert_eq!(t2.status(), ProbeTaskStatus::Cancelled);
        assert_eq!(manager.running_count(), 0);
        // 不覆盖既有错误结果（结构性保证）：探测封装不接触 ProbeStateStore；
        // 命令层对 Cancelled 结果仅 abort（不写 store），首次 Failed 记录保持原样。
    }

    /// 状态模型转移（C2-D1）：终态不可被关闭路径改写。
    #[test]
    fn status_model_transitions_and_terminal_protection() {
        let manager = ProbeTaskManager::default();
        let t = manager.register(301);
        assert_eq!(t.status(), ProbeTaskStatus::Pending);
        t.set_status(ProbeTaskStatus::Running);
        t.mark_cancelled_if_active();
        assert_eq!(t.status(), ProbeTaskStatus::Cancelled, "活动态可被取消");
        // 终态保护
        t.set_status(ProbeTaskStatus::Completed);
        t.mark_cancelled_if_active();
        assert_eq!(t.status(), ProbeTaskStatus::Completed, "Completed 不被覆盖");
        t.set_status(ProbeTaskStatus::Failed);
        t.mark_cancelled_if_active();
        assert_eq!(t.status(), ProbeTaskStatus::Failed, "Failed 不被覆盖");
        manager.take_finished(301);
    }
}

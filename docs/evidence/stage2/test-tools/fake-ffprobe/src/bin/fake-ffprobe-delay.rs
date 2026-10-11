//! 受控测试替身（仅测试用途；D-0023）：模拟"FFprobe 长时间挂起不返回"。
//! 用途：Phase 2B-1 —— 受控短超时下的子进程终止与回收验证（P2D-013 数据层）。
//! 行为：忽略传入参数（应用会传 FFprobe 风格参数），睡眠 120 秒后自然结束；
//!       超时测试中它必须在超时点被外部终止，实际耗时远小于 120 秒。

use std::process::exit;

fn main() {
    let sleep_ms: u64 = 120_000;
    std::thread::sleep(std::time::Duration::from_millis(sleep_ms));
    eprintln!("fake-ffprobe-delay: finished naturally after {sleep_ms} ms (timeout test should have killed me)");
    exit(0);
}

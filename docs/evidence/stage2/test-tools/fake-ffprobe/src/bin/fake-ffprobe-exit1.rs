//! 受控测试替身（仅测试用途；D-0023）：模拟"FFprobe 启动后返回非零退出码"。
//! 用途：Phase 2B-1 场景 (c) —— 失败分类 NonZeroExit（含退出码与 stderr 尾部）。
//! 不解析任何参数；固定输出可识别的 stderr 标识后以退出码 1 结束。

use std::process::exit;

fn main() {
    eprintln!("fake-ffprobe-exit1: simulated probe failure (controlled test double, exit=1)");
    exit(1);
}

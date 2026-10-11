//! 受控测试替身（仅测试用途；D-0023/D-0026）：模拟"FFprobe 成功返回结构化 JSON"。
//! 用途：生命周期测试的正常完成路径（T1）——输出固定 ffprobe JSON 后以退出码 0 结束。

fn main() {
    println!(
        "{{\"streams\":[{{\"codec_type\":\"video\",\"codec_name\":\"mpeg4\",\"width\":320,\"height\":240}},{{\"codec_type\":\"audio\",\"codec_name\":\"aac\"}}],\"format\":{{\"duration\":\"1.75\",\"format_name\":\"matroska,webm\"}}}}"
    );
}

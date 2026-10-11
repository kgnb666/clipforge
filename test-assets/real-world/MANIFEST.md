# 真实世界测试视频（手测用素材）

- 目的：给**人工测试**提供真实来源、真实内容、可播放的视频，覆盖常见容器与编码组合。
- 获取日期：2026-10-11
- 目录：`test-assets/real-world/`（共 10 个文件，约 196 MB）
- 与合成素材的区别：这里的文件全部从公网下载（非 lavfi 合成），内容是真动画/实拍画面，可用播放器直接观看。

## 文件清单

| # | 文件 | 大小 | SHA256(前16) | 容器 / 编码 | 时长 | 音轨 | 来源 |
|---|---|---|---|---|---|---|---|
| 1 | `Big_Buck_Bunny_1080p_h264.mp4` | 5,238,714 | `e131ad4262144275` | MP4 / H.264 1080p | 10.0s | ✗ 无 | test-videos.co.uk |
| 2 | `Big_Buck_Bunny_720p_h265.mp4` | 1,059,427 | `3d07dcc53f7e8a64` | MP4 / **HEVC(H.265)** 720p | 10.0s | ✗ 无 | test-videos.co.uk |
| 3 | `Big_Buck_Bunny_720p_av1.webm` | 1,058,361 | `bf9f19211a860daf` | WebM / **AV1** 720p | 10.0s | ✗ 无 | test-videos.co.uk |
| 4 | `Jellyfish_1080p_vp9.webm` | 2,101,388 | `efea4114a2827ec0` | WebM / VP9 1080p | 10.0s | ✗ 无 | test-videos.co.uk |
| 5 | `Jellyfish_1080p_h264.mkv` | 2,078,619 | `f161cbf468b7e50b` | **MKV** / H.264 1080p | 10.0s | ✗ 无 | test-videos.co.uk |
| 6 | `ocean_960x400_vp9_opus.webm` | 17,249,599 | `aa57a444d305a586` | WebM / VP9 + **Opus** | 46.6s | ✓ 立体声 | filesamples.com |
| 7 | `ocean_960x400.avi` | 5,590,100 | `ac5e0300d55074ac` | **AVI** / MPEG-4 + MP3 | 46.7s | ✓ 立体声 | filesamples.com |
| 8 | `surfing_720p_h264_aac.mp4` | 71,753,110 | `e658303f72fa7cec` | MP4 / H.264 + AAC | 183.1s | ✓ 立体声 | filesamples.com |
| 9 | `surfing_720p_h264.mov` | 71,753,201 | `3c2a5602243db42e` | **MOV** / H.264 + AAC | 183.1s | ✓ 立体声 | filesamples.com |
| 10 | `surfing_720p.avi` | 26,622,154 | `66f65364a657ca48` | **AVI** / MPEG-4 + MP3 | 183.2s | ✓ 立体声 | filesamples.com |

来源 URL：
- test-videos.co.uk：`https://test-videos.co.uk/vids/{bigbuckbunny|jellyfish}/{mp4|webm|mkv}/...`
- filesamples.com：`https://filesamples.com/samples/video/{mp4|webm|mkv|mov|avi}/...`

## 全部文件已通过的校验（2026-10-11，FFmpeg 9.0.2）

1. **元数据可读**：`ffprobe -show_format -show_streams` 全部退出码 0。
2. **真实解码**：`ffmpeg -i <file> -f null -` 全部退出码 0、无错误输出 → 确实能播。
3. **完整性**：容器声明时长与最后一个视频包时间戳一致（≤2s 差）→ 没有下到一半的残缺文件。

## 手测时的预期（本机实测）

| 操作 | 实测耗时 |
|---|---|
| 183s 720p → **MP4**（`libx264 veryfast CRF23 + AAC`） | **约 12 秒** |
| 183s 720p → **WebM**（`libvpx 1M + libvorbis`） | **约 77 秒**（明显慢于 MP4，属正常） |

- 应用默认转换超时 **300 秒**：上表两档都在限内，但**长视频转 WebM 请耐心等 1 分钟以上**，不要误判为卡死。
- 10s 的短视频两种格式都在 1 秒上下。

## 已知的真实世界"非理想"情况（不是 bug）

- `surfing_720p_h264.mov` 与 `surfing_720p.avi` 是**同一段 3 分钟冲浪视频**的 MOV/AVI 两个版本（另有 MP4 版），便于对比同内容在不同容器下的转换表现；体积较大，不需要可直接删。
- 前 5 个 Big Buck Bunny / Jellyfish 片段**没有音轨**（来源站点的无声测试片段）——界面会正确显示"音频编码 无音轨"，这是预期行为。
- 若导入某些 **WebM** 时"时长"显示 `N/A`：部分 WebM 容器不写时长字段，应用会如实显示 N/A 而不编造数值（本目录的 WebM 目前都带正常时长）。

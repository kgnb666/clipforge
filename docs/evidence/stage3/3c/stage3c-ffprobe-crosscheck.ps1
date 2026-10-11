# stage3c-ffprobe-crosscheck.ps1 — Stage 3C 输出文件二次验证（2026-10-11）
#
# 用途：对 Stage 3C 真实客户端流程产出的每个输出文件做 FFprobe 二次验证，
#       检查 format / duration / video stream / audio stream / codec，
#       并与每个测试用例的预期做程序化比对（判定 PROBE_OK / PROBE_MISMATCH）。
# 边界：只读取文件，不修改任何产物；不涉及产品源码。

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$ffp = (Get-Command ffprobe).Source
$TA  = 'D:\应聘项目zcode\test-assets\stage3c'
$SPEC = Join-Path $TA "测试 & 视频 #1 (终版)'s"

function Quote-Arg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -match '[\s"]') { return '"' + ($a -replace '(\\*)"', '$1$1\"') + '"' }
  return $a
}

function Invoke-Ffprobe([string]$path) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $ffp
  $psi.Arguments = ((@('-v','error','-print_format','json','-show_format','-show_streams',$path) | ForEach-Object { Quote-Arg $_ }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $p = [System.Diagnostics.Process]::Start($psi)
  $so = $p.StandardOutput.ReadToEnd()
  $se = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Out = $so; Err = $se; Code = $p.ExitCode }
}

Write-Output "===== Stage 3C 输出文件 FFprobe 二次验证 $(Get-Date -Format o) ====="
Write-Output "ffprobe = $ffp"
Write-Output ""

# 用例清单：id / 文件 / 预期容器 / 预期视频编码 / 预期音频编码（"-" = 必须无音频流）
$cases = @(
  @{ Id = 'T1 '; Path = (Join-Path $TA 'sample_converted.mp4');                 Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'T2 '; Path = (Join-Path $TA 'sample_converted.webm');                Fmt = 'matroska,webm'; Vid = 'vp8'; Aud = 'vorbis' },
  @{ Id = 'T3 '; Path = (Join-Path $TA 'sample_converted_2.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'T4 '; Path = (Join-Path $TA 'sample_converted_3.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'T5 '; Path = (Join-Path $TA 'sample_converted_4.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'T6 '; Path = (Join-Path $TA 'no_audio_converted.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = '-' },
  @{ Id = 'T7 '; Path = (Join-Path $SPEC 'sample_converted.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'S1 '; Path = (Join-Path $TA 'sample_converted_5.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'S2 '; Path = (Join-Path $TA 'sample_converted_6.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'S3 '; Path = (Join-Path $TA 'sample_converted_7.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'S4 '; Path = (Join-Path $TA 'sample_converted_8.mp4');               Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' },
  @{ Id = 'S5 '; Path = (Join-Path $TA 'no_audio_converted_2.mp4');             Fmt = 'mov,mp4'; Vid = 'h264'; Aud = '-' },
  @{ Id = 'S6 '; Path = (Join-Path $SPEC 'sample_converted_2.mp4');             Fmt = 'mov,mp4'; Vid = 'h264'; Aud = 'aac' }
)

$pass = 0; $fail = 0; $missing = 0
foreach ($c in $cases) {
  Write-Output ("--- [" + $c.Id + "] " + $c.Path)
  if (-not (Test-Path $c.Path)) {
    Write-Output "    RESULT=MISSING（文件不存在）"
    $missing++
    Write-Output ""
    continue
  }
  $fi = Get-Item $c.Path
  $r = Invoke-Ffprobe $c.Path
  Write-Output ("    ffprobe_exit=" + $r.Code + "  文件大小=" + $fi.Length + " B  mtime=" + $fi.LastWriteTime.ToString('o'))
  if ($r.Err.Trim()) { Write-Output ("    [stderr] " + ($r.Err.Trim() -replace "`r?`n", " | ")) }
  if ($r.Code -ne 0) { Write-Output "    RESULT=PROBE_FAIL"; $fail++; Write-Output ""; continue }

  $j = $r.Out | ConvertFrom-Json
  $fmt = $j.format.format_name
  $dur = $j.format.duration
  $vstreams = @($j.streams | Where-Object { $_.codec_type -eq 'video' })
  $astreams = @($j.streams | Where-Object { $_.codec_type -eq 'audio' })
  Write-Output ("    format_name=" + $fmt + "  duration=" + $dur + "  bit_rate=" + $j.format.bit_rate)
  foreach ($i in 0..([Math]::Max(0, @($j.streams).Count - 1))) {
    $s = @($j.streams)[$i]
    $extra = ""
    if ($s.codec_type -eq 'video') { $extra = " " + $s.width + "x" + $s.height + " pix_fmt=" + $s.pix_fmt + " r_frame_rate=" + $s.r_frame_rate }
    if ($s.codec_type -eq 'audio') { $extra = " sample_rate=" + $s.sample_rate + " channels=" + $s.channels }
    Write-Output ("    stream[" + $s.index + "] " + $s.codec_type + " codec=" + $s.codec_name + $extra)
  }

  $ok = $true
  if ($fmt -notlike ($c.Fmt + "*")) { $ok = $false; Write-Output ("    MISMATCH format: 期望 " + $c.Fmt + " 实际 " + $fmt) }
  if ($vstreams.Count -lt 1) { $ok = $false; Write-Output "    MISMATCH 无视频流" }
  elseif ($vstreams[0].codec_name -ne $c.Vid) { $ok = $false; Write-Output ("    MISMATCH 视频编码: 期望 " + $c.Vid + " 实际 " + $vstreams[0].codec_name) }
  if ($c.Aud -eq '-') {
    if ($astreams.Count -ne 0) { $ok = $false; Write-Output ("    MISMATCH 期望无音频流，实际 " + $astreams.Count + " 条") }
  } else {
    if ($astreams.Count -lt 1) { $ok = $false; Write-Output "    MISMATCH 无音频流" }
    elseif ($astreams[0].codec_name -ne $c.Aud) { $ok = $false; Write-Output ("    MISMATCH 音频编码: 期望 " + $c.Aud + " 实际 " + $astreams[0].codec_name) }
  }
  if ($ok) { Write-Output "    RESULT=PROBE_OK"; $pass++ } else { Write-Output "    RESULT=PROBE_MISMATCH"; $fail++ }
  Write-Output ""
}

# 失败用例的输出文件必须不存在（CONV_* 失败时清理半成品）
Write-Output "--- [T8 / T8b] 失败用例不应留下输出文件"
foreach ($p in @((Join-Path $TA 'truncated_converted.mp4'), (Join-Path $TA 'corrupt_mdat_converted.mp4'))) {
  $exists = Test-Path $p
  Write-Output ("    " + [System.IO.Path]::GetFileName($p) + " 存在=" + $exists + "  " + $(if ($exists) { "RESULT=FAIL(存在半成品)" } else { "RESULT=OK(已清理/未产生)" }))
}
Write-Output ""

Write-Output ("===== 汇总：PROBE_OK=" + $pass + "  PROBE_MISMATCH/FAIL=" + $fail + "  MISSING=" + $missing + " =====")
Write-Output ("DONE " + (Get-Date -Format o))

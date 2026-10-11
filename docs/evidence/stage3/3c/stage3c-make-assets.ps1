# stage3c-make-assets.ps1 — Stage 3C 受控测试素材生成脚本（2026-10-11）
#
# 用途：为 Stage 3C「真实多格式视频转换兼容性验收」生成受控测试素材（T1..T8）。
# 边界：只在 D:\应聘项目zcode\test-assets\stage3c\ 下写入文件；不触碰产品源码；
#       不修改任何系统设置；所有命令与产物哈希在日志中留痕。
#
# 说明：素材全部由 FFmpeg lavfi 合成（testsrc2/smptebars 等测试图案 + sine 音频），
#       不引入任何第三方媒体文件，内容可复现。
# 注意：本文件必须保存为 UTF-8 with BOM —— Windows PowerShell 5.1 对无 BOM 的
#       .ps1 按 ANSI 代码页解码，会导致中文字面量（含路径）变成乱码。

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$ff   = (Get-Command ffmpeg).Source
$ffp  = (Get-Command ffprobe).Source
$TA   = 'D:\应聘项目zcode\test-assets\stage3c'
$SPEC = Join-Path $TA "测试 & 视频 #1 (终版)'s"

if (Test-Path $TA) { Remove-Item -Recurse -Force $TA }
New-Item -ItemType Directory -Force -Path $TA   | Out-Null
New-Item -ItemType Directory -Force -Path $SPEC | Out-Null

Write-Output "== Stage 3C 素材生成 $(Get-Date -Format o) =="
Write-Output "ffmpeg  = $ff"
Write-Output ("ffmpeg  version = " + (& $ff -version | Select-Object -First 1))
Write-Output "TA      = $TA"
Write-Output ""

# ---------------- 原生命令辅助 ----------------
function Write-Lines {
  param([string]$Text, [int]$Max = 4)
  $lines = @(($Text -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
  $n = [Math]::Min($Max, $lines.Count)
  for ($i = 0; $i -lt $n; $i++) { Write-Output ("    " + $lines[$i].Trim()) }
}

function Quote-Arg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -match '[\s"]') { return '"' + ($a -replace '(\\*)"', '$1$1\"') + '"' }
  return $a
}

function Invoke-Native {
  # 经 .NET Process 直接取 stdout/stderr：既避免 Windows PowerShell 5.1 把原生
  # stderr 包装成 NativeCommandError 错误记录（污染日志），又能完整保留原始 stderr
  # （ffprobe/ffmpeg 对损坏文件的诊断信息正是本阶段要取证的内容）。
  param([string]$Exe, [string[]]$FArgs)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = (($FArgs | ForEach-Object { Quote-Arg $_ }) -join ' ')
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

function New-Clip {
  param([string]$Out, [string[]]$FArgs)
  Write-Output ("--- [生成] " + $Out)
  Write-Output ("    ffmpeg " + ($FArgs -join ' ') + " <out>")
  $r = Invoke-Native -Exe $ff -FArgs (@('-y','-hide_banner','-loglevel','error') + $FArgs + @($Out))
  if ($r.Code -ne 0) {
    Write-Output "    [stderr]"
    Write-Lines $r.Err 6
    throw "ffmpeg 生成失败 ($($r.Code)): $Out"
  }
}

# ---------------- T1：基础 MP4（H264 + AAC） ----------------
New-Clip -Out (Join-Path $TA 'sample.mp4') -FArgs @(
  '-f','lavfi','-i','testsrc2=size=640x360:rate=30:duration=5',
  '-f','lavfi','-i','sine=frequency=440:sample_rate=44100:duration=5',
  '-c:v','libx264','-preset','veryfast','-crf','23','-pix_fmt','yuv420p',
  '-c:a','aac','-b:a','128k','-movflags','+faststart'
)

# ---------------- T3：MKV（H264 + AAC） ----------------
New-Clip -Out (Join-Path $TA 'sample.mkv') -FArgs @(
  '-f','lavfi','-i','smptebars=size=640x360:rate=30:duration=4',
  '-f','lavfi','-i','sine=frequency=660:sample_rate=44100:duration=4',
  '-c:v','libx264','-preset','veryfast','-crf','23','-pix_fmt','yuv420p',
  '-c:a','aac','-b:a','128k'
)

# ---------------- T4：MOV（H264 + AAC） ----------------
New-Clip -Out (Join-Path $TA 'sample.mov') -FArgs @(
  '-f','lavfi','-i','testsrc=size=640x360:rate=30:duration=3',
  '-f','lavfi','-i','sine=frequency=880:sample_rate=44100:duration=3',
  '-c:v','libx264','-preset','veryfast','-crf','23','-pix_fmt','yuv420p',
  '-c:a','aac','-b:a','128k'
)

# ---------------- T5：AVI（MPEG-4 Part2 + MP3：典型遗留 AVI） ----------------
New-Clip -Out (Join-Path $TA 'sample.avi') -FArgs @(
  '-f','lavfi','-i','smptehdbars=size=640x360:rate=25:duration=3',
  '-f','lavfi','-i','sine=frequency=220:sample_rate=44100:duration=3',
  '-c:v','mpeg4','-q:v','4',
  '-c:a','libmp3lame','-b:a','128k'
)

# ---------------- T6：无音轨 MP4（H264，-an） ----------------
New-Clip -Out (Join-Path $TA 'no_audio.mp4') -FArgs @(
  '-f','lavfi','-i','testsrc2=size=640x360:rate=30:duration=3',
  '-c:v','libx264','-preset','veryfast','-crf','23','-pix_fmt','yuv420p',
  '-an'
)

# ---------------- T7：特殊路径素材（中文 + 空格 + & + ' + #） ----------------
Copy-Item (Join-Path $TA 'sample.mp4') (Join-Path $SPEC 'sample.mp4')
Write-Output ""
Write-Output "--- [复制] T7 特殊路径素材"
Write-Output ("    copy sample.mp4 -> " + (Join-Path $SPEC 'sample.mp4'))

# ---------------- T8：损坏素材 A —— 截断（尾部切除，moov 丢失） ----------------
$t8full = Join-Path $TA '_t8_full_no_faststart.mp4'
New-Clip -Out $t8full -FArgs @(
  '-f','lavfi','-i','testsrc2=size=320x180:rate=15:duration=4',
  '-f','lavfi','-i','sine=frequency=330:sample_rate=44100:duration=4',
  '-c:v','libx264','-preset','veryfast','-crf','28','-pix_fmt','yuv420p',
  '-c:a','aac','-b:a','96k'
)
$t8bytes = [System.IO.File]::ReadAllBytes($t8full)
$keep = [int][Math]::Floor($t8bytes.Length * 0.30)
$t8 = Join-Path $TA 'truncated.mp4'
[System.IO.File]::WriteAllBytes($t8, $t8bytes[0..($keep - 1)])
Write-Output ""
Write-Output "--- [损坏A] truncated.mp4 = 完整文件前 30% 字节"
Write-Output ("    源大小=" + $t8bytes.Length + " 截断后=" + (Get-Item $t8).Length + " 保留比例=0.30")
Remove-Item $t8full -Force

# ---------------- T8b：损坏素材 B —— moov 完整但媒体数据被切除 ----------------
# 目的：构造「容器元数据可读、但媒体数据不可解码」的真实损坏文件，
#       使其能通过导入与元数据解析，从而进入转换阶段触发 CONV_NONZERO_EXIT。
$t8bfull = Join-Path $TA '_t8b_full_faststart.mp4'
New-Clip -Out $t8bfull -FArgs @(
  '-f','lavfi','-i','testsrc2=size=320x180:rate=15:duration=4',
  '-f','lavfi','-i','sine=frequency=330:sample_rate=44100:duration=4',
  '-c:v','libx264','-preset','veryfast','-crf','28','-pix_fmt','yuv420p',
  '-c:a','aac','-b:a','96k','-movflags','+faststart'
)

function Get-MoovEnd([byte[]]$b) {
  $pos = 0
  while ($pos + 8 -le $b.Length) {
    $size = [uint32]$b[$pos] * 16777216 + [uint32]$b[$pos+1] * 65536 + [uint32]$b[$pos+2] * 256 + [uint32]$b[$pos+3]
    $type = [System.Text.Encoding]::ASCII.GetString($b, $pos + 4, 4)
    if ($size -eq 1) {
      $hi = [uint32]$b[$pos+8] * 16777216 + [uint32]$b[$pos+9] * 65536 + [uint32]$b[$pos+10] * 256 + [uint32]$b[$pos+11]
      $lo = [uint32]$b[$pos+12] * 16777216 + [uint32]$b[$pos+13] * 65536 + [uint32]$b[$pos+14] * 256 + [uint32]$b[$pos+15]
      $size = [uint64]$hi * 4294967296 + [uint64]$lo
    }
    if ($size -eq 0) { $size = $b.Length - $pos }
    if ($type -eq 'moov') { return [int]($pos + $size) }
    $pos += [int]$size
  }
  return -1
}

$b8b = [System.IO.File]::ReadAllBytes($t8bfull)
$moovEnd = Get-MoovEnd $b8b
if ($moovEnd -le 0) { throw '未能在 faststart 文件中定位 moov atom' }
$t8b = Join-Path $TA 'corrupt_mdat.mp4'
[System.IO.File]::WriteAllBytes($t8b, $b8b[0..($moovEnd - 1)])
Write-Output ""
Write-Output "--- [损坏B] corrupt_mdat.mp4 = 保留 ftyp+moov，切除 mdat 全部媒体数据"
Write-Output ("    源大小=" + $b8b.Length + " moov 结束偏移=" + $moovEnd + " 截断后=" + (Get-Item $t8b).Length)
Remove-Item $t8bfull -Force

# ---------------- 清单：相对路径 / 大小 / SHA256 / mtime ----------------
Write-Output ""
Write-Output "== 素材清单（relative-path / size / sha256 / mtime）=="
$files = Get-ChildItem -Recurse -File $TA | Sort-Object FullName
foreach ($f in $files) {
  $rel = $f.FullName.Substring($TA.Length + 1)
  $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
  Write-Output ("{0,-40} {1,10} B  {2}  {3}" -f $rel, $f.Length, $h, $f.LastWriteTime.ToString('o'))
}

# ---------------- 输入素材特征（ffprobe 容器 + 编码） ----------------
Write-Output ""
Write-Output "== 输入素材 ffprobe 特征（format / streams）=="
foreach ($f in $files) {
  $rel = $f.FullName.Substring($TA.Length + 1)
  $r = Invoke-Native -Exe $ffp -FArgs @(
    '-v','error','-show_entries','format=format_name,duration',
    '-show_entries','stream=codec_type,codec_name',
    '-of','default=noprint_wrappers=1', $f.FullName
  )
  Write-Output ("--- " + $rel + "  ffprobe_exit=" + $r.Code)
  Write-Lines $r.Out 8
  if ($r.Err.Trim()) { Write-Output "    [stderr]"; Write-Lines $r.Err 3 }
}

# ---------------- 损坏性核验（供 T8 设计与取证） ----------------
Write-Output ""
Write-Output "== 损坏素材行为核验 A（ffprobe 元数据读取：-show_format -show_streams）=="
foreach ($cand in @($t8, $t8b)) {
  $r = Invoke-Native -Exe $ffp -FArgs @('-v','error','-print_format','json','-show_format','-show_streams',$cand)
  Write-Output ("--- " + (Split-Path $cand -Leaf) + "  ffprobe_exit=" + $r.Code)
  if ($r.Err.Trim()) { Write-Output "    [stderr]"; Write-Lines $r.Err 3 }
}
Write-Output ""
Write-Output "== 损坏素材行为核验 B（ffmpeg 解码探测：-f null -）=="
foreach ($cand in @($t8, $t8b)) {
  $r = Invoke-Native -Exe $ff -FArgs @('-hide_banner','-v','error','-i',$cand,'-f','null','-')
  Write-Output ("--- " + (Split-Path $cand -Leaf) + "  ffmpeg_exit=" + $r.Code)
  if ($r.Err.Trim()) { Write-Output "    [stderr]"; Write-Lines $r.Err 4 }
}

Write-Output ""
Write-Output "DONE $(Get-Date -Format o)"

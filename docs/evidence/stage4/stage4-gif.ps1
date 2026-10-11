<#
  stage4-gif.ps1 — Demo GIF 驱动脚本（2026-10-11）

  流程：启动逐帧采集器（独立进程）→ 启动 release 版 ClipForge →
        真实 UI 流程：导入真实素材 Big Buck Bunny 720p（HEVC, 无音轨）
        → 元数据/缩略图 → 点击 MP4 转换 → 等待结论 → 关闭应用
        → 等待采集结束 → ffmpeg 调色板两遍法编码 GIF。

  输出：docs/evidence/stage4/stage4-demo.gif（README 引用）
  日志：docs/evidence/stage4/stage4-gif.log
  帧目录：%TEMP%\clipforge-gif（编码后自行清理；不入库）
#>
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$S4     = "D:\Cliporge\docs\evidence\stage4"
$LOG    = Join-Path $S4 "stage4-gif.log"
$CAPTURE= Join-Path $S4 "stage4-gif-capture.ps1"
$HELPER = Join-Path $S4 "stage4-release-ui-helper.ps1"
$EXE    = "D:\cargo-target\release\ClipForge.exe"
$FRAMES = "$env:TEMP\clipforge-gif"
$GIF    = Join-Path $S4 "stage4-demo.gif"
$BBB    = "D:\Cliporge\test-assets\real-world\Big_Buck_Bunny_720p_h265.mp4"
$DUR    = 24

function W([string]$s) { $s | Out-File -Append -Encoding utf8 $LOG; Write-Host $s }
function H2 { param([string]$a, [hashtable]$kw)
  $pre = @()
  foreach ($k in $kw.Keys) { $pre += "-$k"; $pre += [string]$kw[$k] }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $HELPER -Action $a @pre 2>&1
  $code = $LASTEXITCODE
  $out | ForEach-Object { W ("    " + $_) }
  W ("    [helper exit={0}]" -f $code)
  if ($code -ne 0) { throw ("helper 失败: " + $a) }
  return ($out -join "`n")
}

"=== Stage 4 Demo GIF 录制 ===" | Out-File -Encoding utf8 $LOG
W ("开始时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
W ("release 可执行文件: " + $EXE + "  存在=" + (Test-Path $EXE))

# 清理遗留
Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600

try {
  W "--- 启动采集器（${DUR}s）---"
  $cap = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$CAPTURE,"-DurationSec","$DUR","-ProcName","ClipForge") -PassThru -WindowStyle Hidden
  Start-Sleep -Milliseconds 800

  W "--- 启动应用 ---"
  Start-Process -FilePath $EXE | Out-Null
  [void](H2 "wait-window" @{})
  Start-Sleep -Milliseconds 1500

  W "--- 导入 Big Buck Bunny 720p (HEVC) ---"
  [void](H2 "import" @{ Scenario = "bbb" })
  [void](H2 "wait-path" @{ Path = $BBB; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  Start-Sleep -Milliseconds 2500   # 让缩略图渲染进帧

  W "--- 点击 MP4 转换 ---"
  [void](H2 "click-conv" @{ Format = "mp4" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  Start-Sleep -Milliseconds 2800   # 完成态停留

  W "--- 关闭应用 ---"
  [void](H2 "close-app" @{})
  Start-Sleep -Milliseconds 1200

  W "--- 等待采集器结束 ---"
  $cap.WaitForExit()
  $frameCount = @(Get-ChildItem $FRAMES -Filter "*.png" -ErrorAction SilentlyContinue).Count
  W ("采集帧数: " + $frameCount)
  if ($frameCount -lt 50) { throw "帧数过少，录制失败" }

  W "--- ffmpeg 编码 GIF（palettegen + paletteuse，按实际采集速率=实时）---"
  $fps = [Math]::Round($frameCount / $DUR, 3)
  W ("    实际采集速率: " + $fps + " fps（帧数/采集时长）")
  $vf = "scale=760:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"
  $ff = & ffmpeg -y -framerate $fps -i (Join-Path $FRAMES "frame_%04d.png") -vf $vf -loop 0 $GIF 2>&1
  $ff | Select-Object -Last 4 | ForEach-Object { W ("    " + $_) }
  if (Test-Path $GIF) {
    W ("GIF: " + $GIF + "  " + [Math]::Round((Get-Item $GIF).Length / 1MB, 2) + " MB  " + (Get-Item $GIF).Length + " B")
  } else { throw "GIF 未生成" }
} catch {
  W ("FAIL: " + $_.Exception.Message)
  Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
}
W ("结束时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

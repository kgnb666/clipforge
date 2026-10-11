<#
  stage5-gif.ps1 — Demo GIF 重录（Stage 5：新元数据字段 + 转换进度条入镜）
  与 stage4-gif.ps1 的差异：使用 stage5 helper（新按钮映射）、素材改为 Big Buck Bunny 720p（HEVC→H.264，
  转换约数秒，可看到进度条），输出 stage5-demo.gif。
#>
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$S5 = "D:\Cliporge\docs\evidence\stage5"
$LOG = Join-Path $S5 "stage5-gif.log"
$CAPTURE = "D:\Cliporge\docs\evidence\stage4\stage4-gif-capture.ps1"
$HELPER = Join-Path $S5 "stage5-ui-helper.ps1"
$EXE = "D:\cargo-target\release\ClipForge.exe"
$FRAMES = "$env:TEMP\clipforge-gif"   # 必须与采集器默认 OutDir 一致（或显式传 -OutDir）
$GIF = Join-Path $S5 "stage5-demo.gif"
$BBB = "D:\Cliporge\test-assets\real-world\Big_Buck_Bunny_720p_h265.mp4"
$DUR = 20
function W([string]$s) { $s | Out-File -Append -Encoding utf8 $LOG; Write-Host $s }
function H2 { param([string]$a, [hashtable]$kw)
  $pre = @(); foreach ($k in $kw.Keys) { $pre += "-$k"; $pre += [string]$kw[$k] }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $HELPER -Action $a @pre 2>&1
  if ($LASTEXITCODE -ne 0) { throw ("helper 失败: " + $a) }
  return ($out -join "`n")
}
"=== Stage 5 Demo GIF 录制 ===" | Out-File -Encoding utf8 $LOG
W ("开始: " + (Get-Date -Format "HH:mm:ss"))
Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 600
try {
  $cap = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$CAPTURE,"-DurationSec","$DUR","-ProcName","ClipForge") -PassThru -WindowStyle Hidden
  Start-Sleep -Milliseconds 800
  Start-Process -FilePath $EXE | Out-Null
  [void](H2 "wait-window" @{})
  Start-Sleep -Milliseconds 1500
  [void](H2 "import" @{ Scenario = "bbb" })
  [void](H2 "wait-path" @{ Path = $BBB; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  Start-Sleep -Milliseconds 2500
  [void](H2 "click-conv" @{ Format = "mp4" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  Start-Sleep -Milliseconds 2500
  [void](H2 "close-app" @{})
  $cap.WaitForExit()
  $n = @(Get-ChildItem $FRAMES -Filter "*.png" -ErrorAction SilentlyContinue).Count
  W ("采集帧数: " + $n)
  if ($n -lt 40) { throw "帧数过少" }
  $fps = [Math]::Round($n / $DUR, 3)
  W ("实际采集速率: " + $fps + " fps")
  $vf = "scale=760:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"
  $ff = & ffmpeg -y -framerate $fps -i (Join-Path $FRAMES "frame_%04d.png") -vf $vf -loop 0 $GIF 2>&1
  $ff | Select-Object -Last 2 | ForEach-Object { W ("    " + $_) }
  W ("GIF: " + $GIF + "  " + (Get-Item $GIF).Length + " B")
} catch {
  W ("FAIL: " + $_.Exception.Message)
  Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
}
W ("结束: " + (Get-Date -Format "HH:mm:ss"))

<#
  review-install.ps1 — 审核人路径验收：用"从 GitHub 下载的安装包"完成 安装→使用→卸载
  流程：静默安装下载物 → 安装体核对(0.1.1) → 启动 → T7 中文特殊路径 导入/元数据/缩略图/MP4 转换
        → 完成态按钮断言 → 长视频转换中截图（进度条）→ 转换中关闭应用（取消路径）
        → 清理核验 → 静默卸载 → 卸载核验。日志：reviewer-download.log（UTF-8）
#>
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$RD     = "D:\Cliporge\docs\evidence\reviewer-download"
$LOG    = Join-Path $RD "reviewer-download.log"
$SETUP  = Join-Path $RD "direct.exe"
$HELPER = "D:\Cliporge\docs\evidence\stage5\stage5-ui-helper.ps1"
$APPDIR = Join-Path $env:LOCALAPPDATA "ClipForge"
$EXE    = Join-Path $APPDIR "ClipForge.exe"
$UNINST = Join-Path $APPDIR "uninstall.exe"
$T7PATH = "D:\Cliporge\test-assets\stage3c\测试 & 视频 #1 (终版)'s\sample.mp4"
$T7DIR  = Split-Path $T7PATH
$SURF   = "D:\Cliporge\test-assets\real-world\surfing_720p_h264_aac.mp4"
$SURFDIR= Split-Path $SURF
$APPLOG = Join-Path $env:LOCALAPPDATA "com.clipforge.app\logs\clipforge.log"
function W([string]$s) { $s | Out-File -Append -Encoding utf8 $LOG; Write-Host $s }
function H2 { param([string]$a, [hashtable]$kw)
  $pre = @(); foreach ($k in $kw.Keys) { $pre += "-$k"; $pre += [string]$kw[$k] }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $HELPER -Action $a @pre 2>&1
  $code = $LASTEXITCODE
  $out | ForEach-Object { W ("    " + $_) }
  W ("    [helper exit={0}]" -f $code)
  if ($code -ne 0) { throw ("helper 失败: Action=$a exit=$code") }
  return ($out -join "`n")
}
function Wait-Until([scriptblock]$cond, [int]$timeoutSec, [string]$label) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 700 }
  W ("    !! 等待超时: " + $label); return $false
}
W ""
W "--- ③ 用下载的安装包安装并使用 ---"
$failed = $false
try {
  $p = Start-Process -FilePath $SETUP -ArgumentList "/S" -PassThru -Wait
  W ("安装器退出码: " + $p.ExitCode)
  if (-not (Wait-Until { Test-Path $UNINST } 60 "uninstall.exe")) { throw "安装未完成" }
  $vi = (Get-Item $EXE).VersionInfo
  $reg = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge"
  W ("安装体: ClipForge.exe " + (Get-Item $EXE).Length + " B | ProductName=" + $vi.ProductName + " | 文件版本=" + $vi.FileVersion + " | 注册表版本=" + $reg.DisplayVersion + " | Publisher=" + $reg.Publisher)

  Start-Process -FilePath $EXE | Out-Null
  [void](H2 "wait-window" @{})
  Start-Sleep -Milliseconds 1200
  W "  [使用] T7 中文特殊路径：导入 → 元数据 → 缩略图 → MP4 转换"
  [void](H2 "import" @{ Scenario = "t7" })
  [void](H2 "wait-path" @{ Path = $T7PATH; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  [void](H2 "wait-thumb" @{ Timeout = 60 })
  [void](H2 "click-conv" @{ Format = "mp4" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  $texts = H2 "read-app-text" @{}
  if ($texts -notmatch "已输出 MP4") { throw "未出现 已输出 MP4" }
  if ($texts -notmatch "转 WEBM") { throw "完成态缺少[转 WEBM]" }
  if ($texts -notmatch "打开所在文件夹") { throw "完成态缺少[打开所在文件夹]" }
  if ($texts -notmatch "帧率") { throw "元数据缺少帧率字段" }
  W "    断言通过：已输出 MP4 + [重新转换][转 WEBM][打开所在文件夹] + 帧率字段"
  $before = @(Get-ChildItem $T7DIR -Filter "*_converted*.mp4" | Select-Object -ExpandProperty Name)

  W "  [使用] 长视频转换中截图（进度条）并测试转换中关闭应用"
  [void](H2 "import" @{ Scenario = "surf" })
  [void](H2 "wait-path" @{ Path = $SURF; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  $beforeLong = @(Get-ChildItem $SURFDIR -Filter "surfing_720p_h264_aac_converted*" | Select-Object -ExpandProperty Name)
  [void](H2 "click-conv" @{ Format = "mp4" })
  Start-Sleep -Seconds 3
  [void](H2 "shot-app" @{ Out = (Join-Path $RD "review-progress.png") })
  Start-Sleep -Seconds 3
  [void](H2 "close-app" @{})
  $gone = Wait-Until { -not (Get-Process ClipForge -ErrorAction SilentlyContinue) } 30 "进程退出"
  W ("    应用进程已退出: " + $gone + " | 残留进程: " + @(Get-Process clipforge, ffmpeg, ffprobe -ErrorAction SilentlyContinue).Count)
  Get-Content $APPLOG -Tail 4 | ForEach-Object { W ("    " + $_) }
  $afterLong = @(Get-ChildItem $SURFDIR -Filter "surfing_720p_h264_aac_converted*" | Select-Object -ExpandProperty Name)
  $newLong = @($afterLong | Where-Object { $beforeLong -notcontains $_ })
  W ("    转换中关闭后新增输出: " + $(if ($newLong.Count -eq 0) { "无（无半成品）" } else { ($newLong -join ", ") }))

  W "  [卸载] 静默卸载"
  $p2 = Start-Process -FilePath $UNINST -ArgumentList "/S" -PassThru -Wait
  W ("卸载器退出码: " + $p2.ExitCode)
  $dirGone = Wait-Until { -not (Test-Path $APPDIR) } 120 "安装目录删除"
  $regGone = Wait-Until { -not (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge" -ErrorAction SilentlyContinue) } 30 "注册表项删除"
  $smGone  = Wait-Until { -not (Test-Path (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ClipForge.lnk")) } 30 "快捷方式删除"
  W ("    安装目录已删除: " + $dirGone + " | 注册表已删除: " + $regGone + " | 快捷方式已删除: " + $smGone)
} catch {
  $failed = $true
  W ("FAIL: " + $_.Exception.Message)
  Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
  if (Test-Path $UNINST) { Start-Process -FilePath $UNINST -ArgumentList "/S" -Wait | Out-Null }
}
W ("--- 审核人路径验收结束（" + $(if ($failed) { "有失败项" } else { "全部通过" }) + "）" + (Get-Date -Format " HH:mm:ss") + " ---")

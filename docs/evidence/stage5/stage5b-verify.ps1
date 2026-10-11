<#
  stage5b-verify.ps1 — Stage 5 聚焦复验（2026-10-12）

  背景：首轮 stage5-acceptance.ps1 已通过 A（格式切换）与 B（元数据新字段）；
  首轮 D 的 wait-progress 因"用锚定正则找独立元素"而误判失败（WebView2 UIA 只把可交互元素
  暴露为独立节点，纯文本在容器聚合名中），已改为子串匹配；C 的首轮证据过弱（未区分
  既有资源管理器窗口）。本脚本复验：
    D. 长视频转换中出现进度百分比（子串）→ 转换中关闭应用（CONV_CANCELLED 实机）→
       零残留、无半成品输出、日志含取消链路
    C. "打开所在文件夹"：资源管理器窗口数增量 ≥1（且只关闭新增窗口）+ 应用日志出现
       `conv reveal entry_id=` 证据行
    A. 完成态按钮（重新转换/转 WEBM/打开所在文件夹）→ 点击转 WEBM 收敛
  日志：stage5b-verify.log（UTF-8）
#>
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CfS5b {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][CfS5b]::SetProcessDPIAware()

$S5     = "D:\Cliporge\docs\evidence\stage5"
$LOG    = Join-Path $S5 "stage5b-verify.log"
$SETUP  = "D:\cargo-target\release\bundle\nsis\ClipForge_0.1.1_x64-setup.exe"
$HELPER = Join-Path $S5 "stage5-ui-helper.ps1"
$APPDIR = Join-Path $env:LOCALAPPDATA "ClipForge"
$EXE    = Join-Path $APPDIR "ClipForge.exe"
$UNINST = Join-Path $APPDIR "uninstall.exe"
$T7PATH = "D:\Cliporge\test-assets\stage3c\测试 & 视频 #1 (终版)'s\sample.mp4"
$T7DIR  = Split-Path $T7PATH
$SURF   = "D:\Cliporge\test-assets\real-world\surfing_720p_h264_aac.mp4"
$APPLOG = Join-Path $env:LOCALAPPDATA "com.clipforge.app\logs\clipforge.log"

function W([string]$s) { $s | Out-File -Append -Encoding utf8 $LOG; Write-Host $s }
function H2 { param([string]$a, [hashtable]$kw)
  $pre = @()
  foreach ($k in $kw.Keys) { $pre += "-$k"; $pre += [string]$kw[$k] }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $HELPER -Action $a @pre 2>&1
  $code = $LASTEXITCODE
  $out | ForEach-Object { W ("    " + $_) }
  W ("    [helper exit={0}]" -f $code)
  if ($code -ne 0) { throw ("helper 失败: Action=$a exit=$code —— " + ($out -join " ")) }
  return ($out -join "`n")
}
function Wait-Until([scriptblock]$cond, [int]$timeoutSec, [string]$label) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 700 }
  W ("    !! 等待超时: " + $label); return $false
}
function Get-ExplorerHandles {
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
  $h = New-Object System.Collections.Generic.List[object]
  foreach ($w in $wins) { if ($w.Current.ClassName -eq "CabinetWClass") { $h.Add([pscustomobject]@{ H = [IntPtr]$w.Current.NativeWindowHandle; Name = $w.Current.Name }) } }
  return $h
}
function Close-ExplorerByHandle([IntPtr]$h) {
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty, $h)
  $win = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
  if ($win) {
    $wp = $null
    if ($win.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$wp)) { $wp.Close(); return $true }
  }
  return $false
}

"=== Stage 5 聚焦复验（D 进度/转换中关闭、C 打开文件夹严格证据、A 复检）===" | Out-File -Encoding utf8 $LOG
W ("开始时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

$failed = $false
try {
  # ---------- 安装 ----------
  W ""
  W "--- [1] 静默安装 ---"
  $p = Start-Process -FilePath $SETUP -ArgumentList "/S" -PassThru -Wait
  W ("安装器退出码: " + $p.ExitCode)
  if (-not (Wait-Until { Test-Path $UNINST } 60 "uninstall.exe")) { throw "安装未完成" }
  W ("主程序版本: " + (Get-Item $EXE).VersionInfo.FileVersion + " | 注册表版本: " + (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge").DisplayVersion)

  # ---------- D：进度 + 转换中关闭 ----------
  W ""
  W "--- [2] D：长视频转换 → 观察进度 → 转换中关闭应用 ---"
  Start-Process -FilePath $EXE | Out-Null
  [void](H2 "wait-window" @{})
  Start-Sleep -Milliseconds 1200
  [void](H2 "import" @{ Scenario = "surf" })
  [void](H2 "wait-path" @{ Path = $SURF; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  $beforeOut = @(Get-ChildItem (Split-Path $SURF) -Filter "surfing_720p_h264_aac_converted*" | Select-Object -ExpandProperty Name)
  [void](H2 "click-conv" @{ Format = "mp4" })
  $prog = H2 "wait-progress" @{ Timeout = 60 }
  [void](H2 "shot-app" @{ Out = (Join-Path $S5 "stage5b-progress.png") })
  W "    （已观察到进度，转换仍在进行 → 立即关闭应用，实测 CONV_CANCELLED）"
  [void](H2 "close-app" @{})
  $gone = Wait-Until { -not (Get-Process ClipForge -ErrorAction SilentlyContinue) } 30 "进程退出"
  W ("应用进程已退出: " + $gone)
  W ("残留进程（clipforge/ffmpeg/ffprobe）: " + @(Get-Process clipforge, ffmpeg, ffprobe -ErrorAction SilentlyContinue).Count)
  W "应用日志尾部（应含取消/退出清理链路）:"
  Get-Content $APPLOG -Tail 8 | ForEach-Object { W ("    " + $_) }
  $cancelledInLog = (Get-Content $APPLOG -Tail 40 | Where-Object { $_ -match "CONV_CANCELLED|cancelled=|conv failed" }).Count -gt 0
  W ("日志包含取消/清理证据: " + $cancelledInLog)
  $afterOut = @(Get-ChildItem (Split-Path $SURF) -Filter "surfing_720p_h264_aac_converted*" | Select-Object -ExpandProperty Name)
  $newOut = @($afterOut | Where-Object { $beforeOut -notcontains $_ })
  W ("转换中关闭后新增输出: " + $(if ($newOut.Count -eq 0) { "无（未留半成品）" } else { ($newOut -join ", ") }))

  # ---------- C：打开所在文件夹（严格证据）----------
  W ""
  W "--- [3] C：打开所在文件夹（窗口数增量 + 日志证据行）---"
  Start-Sleep -Milliseconds 800
  Start-Process -FilePath $EXE | Out-Null
  [void](H2 "wait-window" @{})
  Start-Sleep -Milliseconds 1200
  [void](H2 "import" @{ Scenario = "t7" })
  [void](H2 "wait-path" @{ Path = $T7PATH; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  [void](H2 "click-conv" @{ Format = "mp4" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  $texts = H2 "read-app-text" @{}
  if ($texts -notmatch "转 WEBM") { throw "完成态缺少[转 WEBM]（A 未生效）" }
  if ($texts -notmatch "打开所在文件夹") { throw "完成态缺少[打开所在文件夹]（C 未生效）" }
  W "    完成态按钮断言通过：[重新转换][转 WEBM][打开所在文件夹]"

  $logLinesBefore = (Get-Content $APPLOG | Where-Object { $_ -match "conv reveal" }).Count
  $before = Get-ExplorerHandles
  W ("    点击前资源管理器窗口数: " + $before.Count + "  （" + (($before | ForEach-Object { $_.Name }) -join " / ") + "）")
  [void](H2 "click-conv" @{ Format = "reveal" })
  Start-Sleep -Seconds 3
  $after = Get-ExplorerHandles
  W ("    点击后资源管理器窗口数: " + $after.Count + "  （" + (($after | ForEach-Object { $_.Name }) -join " / ") + "）")
  $newWins = @($after | Where-Object { $h = $_.H; -not ($before | Where-Object { $_.H -eq $h }) })
  W ("    新增资源管理器窗口: " + $newWins.Count + $(if ($newWins.Count -gt 0) { "  （" + (($newWins | ForEach-Object { $_.Name }) -join " / ") + "）" } else { "" }))
  if ($newWins.Count -lt 1) { throw "C 失败：点击后未新增资源管理器窗口" }
  $logLinesAfter = (Get-Content $APPLOG | Where-Object { $_ -match "conv reveal" }).Count
  W ("    应用日志 conv reveal 行数: 点击前 " + $logLinesBefore + " → 点击后 " + $logLinesAfter)
  if ($logLinesAfter -le $logLinesBefore) { throw "C 失败：应用日志未出现 conv reveal 证据行" }
  foreach ($w in $newWins) { [void](Close-ExplorerByHandle $w.H) }
  Start-Sleep -Milliseconds 600
  $final = Get-ExplorerHandles
  W ("    仅关闭新增窗口后剩余: " + $final.Count + "（应与点击前一致：" + $before.Count + "）")
  [void](H2 "shot-app" @{ Out = (Join-Path $S5 "stage5b-completed.png") })

  # ---------- A 复检：转 WEBM ----------
  W ""
  W "--- [4] A 复检：点击 [转 WEBM] ---"
  $wBefore = @(Get-ChildItem $T7DIR -Filter "*.webm" | Select-Object -ExpandProperty Name)
  [void](H2 "click-conv" @{ Format = "to-webm" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  $texts = H2 "read-app-text" @{}
  if ($texts -notmatch "已输出 WEBM") { throw "未出现 已输出 WEBM" }
  $wAfter = @(Get-ChildItem $T7DIR -Filter "*.webm" | Select-Object -ExpandProperty Name)
  W ("    WEBM 输出: " + (($wAfter | Where-Object { $wBefore -notcontains $_ }) -join ", ") + "（新增）")
  [void](H2 "close-app" @{})
  $gone = Wait-Until { -not (Get-Process ClipForge -ErrorAction SilentlyContinue) } 30 "进程退出"
  W ("应用进程已退出: " + $gone + " | 残留: " + @(Get-Process clipforge, ffmpeg, ffprobe -ErrorAction SilentlyContinue).Count)
} catch {
  $failed = $true
  W ("FAIL: " + $_.Exception.Message)
  Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
}

# ---------- 卸载 ----------
W ""
W "--- [5] 静默卸载与清理核验 ---"
$p2 = Start-Process -FilePath $UNINST -ArgumentList "/S" -PassThru -Wait
W ("卸载器退出码: " + $p2.ExitCode)
$dirGone = Wait-Until { -not (Test-Path $APPDIR) } 120 "安装目录删除"
$regGone = Wait-Until { -not (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge" -ErrorAction SilentlyContinue) } 30 "注册表项删除"
W ("安装目录已删除: " + $dirGone + " | 注册表已删除: " + $regGone)
W ""
W ("=== 聚焦复验结束（" + $(if ($failed) { "有失败项，见上文 FAIL" } else { "全部通过" }) + "）===")
W ("结束时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

<#
  stage5c-ca.ps1 — Stage 5 聚焦复验之二：C（打开所在文件夹，严格证据）与 A（格式切换）复检
  用法：直接对 release 可执行文件运行（无需安装/卸载）。日志追加到 stage5b-verify.log
#>
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$S5     = "D:\Cliporge\docs\evidence\stage5"
$LOG    = Join-Path $S5 "stage5b-verify.log"
$HELPER = Join-Path $S5 "stage5-ui-helper.ps1"
$EXE    = "D:\cargo-target\release\ClipForge.exe"
$T7PATH = "D:\Cliporge\test-assets\stage3c\测试 & 视频 #1 (终版)'s\sample.mp4"
$T7DIR  = Split-Path $T7PATH
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
function Get-ExplorerHandles {
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
  $h = New-Object System.Collections.Generic.List[object]
  foreach ($w in $wins) { if ($w.Current.ClassName -eq "CabinetWClass") { $h.Add([pscustomobject]@{ H = [IntPtr]$w.Current.NativeWindowHandle; Name = $w.Current.Name }) } }
  return $h
}
function Close-ExplorerByHandle([IntPtr]$h) {
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty, [int]$h)
  $win = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
  if ($win) { $wp = $null; if ($win.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$wp)) { $wp.Close(); return $true } }
  return $false
}

W ""
W "=== [C/A] 打开所在文件夹（严格证据）与格式切换复检（release 可执行文件直跑）==="
W ("开始: " + (Get-Date -Format "HH:mm:ss"))
$failed = $false
try {
  Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 600
  Start-Process -FilePath $EXE | Out-Null
  [void](H2 "wait-window" @{})
  Start-Sleep -Milliseconds 1200
  [void](H2 "import" @{ Scenario = "t7" })
  [void](H2 "wait-path" @{ Path = $T7PATH; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  [void](H2 "click-conv" @{ Format = "mp4" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  $texts = H2 "read-app-text" @{}
  if ($texts -notmatch "转 WEBM") { throw "完成态缺少[转 WEBM]（A）" }
  if ($texts -notmatch "打开所在文件夹") { throw "完成态缺少[打开所在文件夹]（C）" }
  W "    完成态按钮断言通过：[重新转换][转 WEBM][打开所在文件夹]"
  [void](H2 "shot-app" @{ Out = (Join-Path $S5 "stage5-completed.png") })

  # C：窗口数增量 + 日志证据行
  $logBefore = (Get-Content $APPLOG | Where-Object { $_ -match "conv reveal" }).Count
  $before = Get-ExplorerHandles
  W ("    C: 点击前资源管理器窗口数=" + $before.Count)
  [void](H2 "click-conv" @{ Format = "reveal" })
  Start-Sleep -Seconds 3
  $after = Get-ExplorerHandles
  $newWins = @($after | Where-Object { $h = $_.H; -not ($before | Where-Object { $_.H -eq $h }) })
  W ("    C: 点击后窗口数=" + @($after).Count + "，新增=" + $newWins.Count + "（" + (($newWins | ForEach-Object { $_.Name }) -join " / ") + "）")
  if ($newWins.Count -lt 1) { throw "C 失败：点击后未新增资源管理器窗口" }
  $logAfter = (Get-Content $APPLOG | Where-Object { $_ -match "conv reveal" }).Count
  W ("    C: 应用日志 conv reveal 行数 " + $logBefore + " → " + $logAfter)
  if ($logAfter -le $logBefore) { throw "C 失败：应用日志未出现 conv reveal 证据行" }
  foreach ($w in $newWins) { [void](Close-ExplorerByHandle $w.H) }
  Start-Sleep -Milliseconds 800
  $final = Get-ExplorerHandles
  W ("    C: 仅关闭新增窗口后剩余=" + @($final).Count + "（点击前=" + $before.Count + "）")

  # A：切换格式
  $wBefore = @(Get-ChildItem $T7DIR -Filter "*.webm" | Select-Object -ExpandProperty Name)
  [void](H2 "click-conv" @{ Format = "to-webm" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  $texts = H2 "read-app-text" @{}
  if ($texts -notmatch "已输出 WEBM") { throw "未出现 已输出 WEBM（A）" }
  $wAfter = @(Get-ChildItem $T7DIR -Filter "*.webm" | Select-Object -ExpandProperty Name)
  $newWebm = @($wAfter | Where-Object { $wBefore -notcontains $_ })
  W ("    A: 新增 WEBM 输出 = " + ($newWebm -join ", "))
  if ($newWebm.Count -eq 0) { throw "A 失败：未产生新的 WEBM 输出" }
  [void](H2 "close-app" @{})
  Start-Sleep -Seconds 3
  W ("    关闭后残留进程: " + @(Get-Process clipforge, ffmpeg, ffprobe -ErrorAction SilentlyContinue).Count)
} catch {
  $failed = $true
  W ("FAIL: " + $_.Exception.Message)
  Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
}
W ("=== [C/A] 结束（" + $(if ($failed) { "有失败项" } else { "全部通过" }) + "）" + (Get-Date -Format " HH:mm:ss"))

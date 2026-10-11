<#
  gate2c2-round.ps1 — Stage 2C-2 Step 5：单轮生命周期循环（启动→导入→探测→关闭→检查）。

  参数：
    -Round      轮次号（记录用）
    -UseDelay   $true = 以延迟替身覆盖启动（在途关闭场景）；$false = 真实 FFprobe
    -Scenario   UI 辅助脚本的导入场景名
    -WaitText   探测完成的判定文本（如 "1.18 MiB"）；空串 = 等待 "解析中" 后直接关闭（在途场景）

  每轮检查并追加到 stage2c2-rounds.log：
    窗口启动、探测结果、关闭、应用退出、相关残留、ffprobe/替身残留、端口 1420、退出清理摘要行。
#>
param(
  [Parameter(Mandatory = $true)][int]$Round,
  [int]$UseDelay = 0,
  [Parameter(Mandatory = $true)][string]$Scenario,
  [string]$WaitText = ""
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Root = "D:\应聘项目zcode"
$Helper = "$Root\docs\evidence\stage2\2b\gate2b3-ui-helper.ps1"
$RoundsLog = "$Root\docs\evidence\stage2\2c\stage2c2-rounds.log"
$DevLog = "$Root\docs\evidence\stage2\2c\stage2c2-round-dev-$Round.log"

"===== Round $Round (UseDelay=$UseDelay scenario=$Scenario) $(Get-Date -Format o) =====" | Add-Content -Encoding UTF8 $RoundsLog

# 1) 启动 dev（Start-Job 子运行空间；输出重定向到轮次日志）
$envLine = $(if ($UseDelay -eq 1) {
    "`$env:CLIPFORGE_TEST_FFPROBE = 'D:\应聘项目zcode\docs\evidence\stage2\test-tools\fake-ffprobe\switchable-ffprobe.exe';"
  } else { "" })
$job = Start-Job -ScriptBlock {
    param($envLine, $devLog)
    if ($envLine -ne "") { Invoke-Expression $envLine }
    $env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
    $env:CARGO_TARGET_DIR = "D:\cargo-target"
    Set-Location "D:\应聘项目zcode\clipforge"
    & npm run tauri dev 2>&1 | Out-File -Encoding UTF8 $devLog
    "== ROUND DEV EXITED ==" | Add-Content -Encoding UTF8 $devLog
  } -ArgumentList $envLine, $DevLog
"job_id=$($job.Id)" | Add-Content -Encoding UTF8 $RoundsLog

# 2) 等待应用窗口（≤100s）
$window = $null
$deadline = (Get-Date).AddSeconds(100)
while ((Get-Date) -lt $deadline) {
  $window = Get-Process clipforge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($window) { break }
  Start-Sleep -Milliseconds 800
}
if (-not $window) {
  "RESULT=FAIL: 窗口未出现（100s 超时）" | Add-Content -Encoding UTF8 $RoundsLog
  Stop-Job $job -ErrorAction SilentlyContinue
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  exit 1
}
"window_pid=$($window.Id) title=[$($window.MainWindowTitle)] responding=$($window.Responding)" | Add-Content -Encoding UTF8 $RoundsLog

# 3) 导入素材（原生对话框）
$imp = & powershell -NoProfile -ExecutionPolicy Bypass -File $Helper -Action import -Scenario $Scenario 2>&1
"import=$imp" | Add-Content -Encoding UTF8 $RoundsLog

# 4) 等待探测结果 / 在途状态
if ($WaitText -ne "") {
  $wt = & powershell -NoProfile -ExecutionPolicy Bypass -File $Helper -Action wait-text -Scenario $WaitText 2>&1
  "probe_wait=$wt" | Add-Content -Encoding UTF8 $RoundsLog
} else {
  Start-Sleep -Seconds 2
  $wt = & powershell -NoProfile -ExecutionPolicy Bypass -File $Helper -Action read-app-text 2>&1 | Select-String "解析中" | Select-Object -First 1
  "probing_visible=$([bool]$wt)" | Add-Content -Encoding UTF8 $RoundsLog
}

# 5) 关闭窗口
$app = Get-Process clipforge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$appPid = $app.Id
$closed = $app.CloseMainWindow()
"close_sent=$closed app_pid=$appPid time=$(Get-Date -Format o)" | Add-Content -Encoding UTF8 $RoundsLog
Start-Sleep -Seconds 6

# 6) 检查
$still = Get-Process -Id $appPid -ErrorAction SilentlyContinue
"app_exited=$($null -eq $still)" | Add-Content -Encoding UTF8 $RoundsLog
$procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "clipforge" -and $_.Name -in @("node.exe", "cargo.exe", "clipforge.exe", "msedgewebview2.exe") }
"clipforge_leftover=$(if ($procs) { @($procs).Count } else { 0 })" | Add-Content -Encoding UTF8 $RoundsLog
$ff = @(Get-Process -Name ffprobe -ErrorAction SilentlyContinue).Count
$sw = @(Get-Process -Name switchable-ffprobe -ErrorAction SilentlyContinue).Count
"ffprobe_residual=$ff switchable_residual=$sw" | Add-Content -Encoding UTF8 $RoundsLog
$conn = Get-NetTCPConnection -LocalPort 1420 -ErrorAction SilentlyContinue
"port1420_released=$(-not [bool]$conn)" | Add-Content -Encoding UTF8 $RoundsLog
$cleanup = Select-String -Path $DevLog -Pattern "\[lifecycle\] exit cleanup" | Select-Object -Last 1
"shutdown_line=$($cleanup.Line)" | Add-Content -Encoding UTF8 $RoundsLog
$null = Wait-Job $job -Timeout 30000
"dev_exited=$($job.State -eq 'Completed')" | Add-Content -Encoding UTF8 $RoundsLog
Remove-Job $job -Force -ErrorAction SilentlyContinue

# 7) 轮次判定
$ok = ($null -eq $still) -and ($ff -eq 0) -and ($sw -eq 0) -and ($null -ne $cleanup) -and ($cleanup.Line -match "remaining=0")
"RESULT=$(if ($ok) { 'PASS' } else { 'FAIL' })" | Add-Content -Encoding UTF8 $RoundsLog
Write-Output "ROUND${Round}=$(if ($ok) { 'PASS' } else { 'FAIL' })"
if ($ok) { exit 0 } else { exit 1 }

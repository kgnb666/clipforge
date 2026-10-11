<#
  gate2d1b-p2d005.ps1 — Stage 2D-1-B：P2D-005 单场景受控执行（启动→导入→断言错误码→关闭→检查）。
  参数：-Tag 会话标签；-OverrideRel 替身相对路径（test-tools\fake-ffprobe 下）；-ExpectCode 期望错误码；-TimeoutMs 可选超时覆盖。
#>
param(
  [Parameter(Mandatory = $true)][string]$Tag,
  [Parameter(Mandatory = $true)][string]$OverrideRel,
  [Parameter(Mandatory = $true)][string]$ExpectCode,
  [string]$TimeoutMs = ""
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Root = "D:\应聘项目zcode"
$Helper = "$Root\docs\evidence\stage2\2b\gate2b3-ui-helper.ps1"
$M = "$Root\docs\evidence\stage2\2d\stage2d1b-matrix.log"
$DevLog = "$Root\docs\evidence\stage2\2d\stage2d1b-matrix-dev-$Tag.log"

"--- [P2D-005/$Tag] override=$OverrideRel 期望=$ExpectCode $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $M

$envLine = "`$env:CLIPFORGE_TEST_FFPROBE = 'D:\应聘项目zcode\docs\evidence\stage2\test-tools\fake-ffprobe\$OverrideRel';"
if ($TimeoutMs -ne "") {
  $envLine += " `$env:CLIPFORGE_TEST_PROBE_TIMEOUT_MS = '$TimeoutMs';"
}
$job = Start-Job -ScriptBlock {
    param($envLine, $devLog)
    Invoke-Expression $envLine
    $env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
    $env:CARGO_TARGET_DIR = "D:\cargo-target"
    Set-Location "D:\应聘项目zcode\clipforge"
    & npm run tauri dev 2>&1 | Out-File -Encoding UTF8 $devLog
    "== EXITED ==" | Add-Content -Encoding UTF8 $devLog
  } -ArgumentList $envLine, $DevLog

$window = $null
$deadline = (Get-Date).AddSeconds(100)
while ((Get-Date) -lt $deadline) {
  $window = Get-Process clipforge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($window) { break }
  Start-Sleep -Milliseconds 800
}
if (-not $window) {
  "P2D005_${Tag}=FAIL: 窗口未出现" | Add-Content -Encoding UTF8 $M
  Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
  exit 1
}
"window_pid=$($window.Id)" | Add-Content -Encoding UTF8 $M

$imp = & powershell -NoProfile -ExecutionPolicy Bypass -File $Helper -Action import -Scenario special 2>&1
"import=$imp" | Add-Content -Encoding UTF8 $M
$wt = & powershell -NoProfile -ExecutionPolicy Bypass -File $Helper -Action wait-text -Scenario $ExpectCode 2>&1
"probe_wait=$wt" | Add-Content -Encoding UTF8 $M
$readOk = (& powershell -NoProfile -ExecutionPolicy Bypass -File $Helper -Action read-app-text 2>&1) -join "`n"
"app_text_has_code=$($readOk.Contains($ExpectCode))" | Add-Content -Encoding UTF8 $M

$app = Get-Process clipforge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$appPid = $app.Id
$null = $app.CloseMainWindow()
Start-Sleep -Seconds 5
$exited = -not (Get-Process -Id $appPid -ErrorAction SilentlyContinue)
$procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "clipforge" -and $_.Name -in @("node.exe", "cargo.exe", "clipforge.exe", "msedgewebview2.exe") }
"app_exited=$exited leftover=$(if ($procs) { @($procs).Count } else { 0 })" | Add-Content -Encoding UTF8 $M
$cleanup = Select-String -Path $DevLog -Pattern "\[lifecycle\] exit cleanup" | Select-Object -Last 1
"shutdown_line=$($cleanup.Line)" | Add-Content -Encoding UTF8 $M
$null = Wait-Job $job -Timeout 30000
"dev_exited=$($job.State -eq 'Completed')" | Add-Content -Encoding UTF8 $M
Remove-Job $job -Force -ErrorAction SilentlyContinue

$ok = ($wt -match "OK:") -and $exited -and ($cleanup -and $cleanup.Line -match "remaining=0")
"P2D005_${Tag}=$(if ($ok) { 'PASS' } else { 'FAIL' })" | Add-Content -Encoding UTF8 $M
Write-Output "P2D005_${Tag}=$(if ($ok) { 'PASS' } else { 'FAIL' })"
if ($ok) { exit 0 } else { exit 1 }

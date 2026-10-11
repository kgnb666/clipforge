$HELPER = "D:\Cliporge\docs\evidence\stage5\stage5-ui-helper.ps1"
$EXE = "D:\cargo-target\release\ClipForge.exe"
$SURF = "D:\Cliporge\test-assets\real-world\surfing_720p_h264_aac.mp4"
function H2 { param([string]$a, [hashtable]$kw)
  $pre = @(); foreach ($k in $kw.Keys) { $pre += "-$k"; $pre += [string]$kw[$k] }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $HELPER -Action $a @pre 2>&1
  return ($out -join "`n")
}
Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
Start-Process -FilePath $EXE | Out-Null
[void](H2 "wait-window" @{})
Start-Sleep -Milliseconds 1200
Write-Output ("IMPORT: " + (H2 "import" @{ Scenario = "surf" }))
Write-Output ("PATH: " + (H2 "wait-path" @{ Path = $SURF; Timeout = 30 }))
Start-Sleep -Milliseconds 800
Write-Output ("CLICK: " + (H2 "click-conv" @{ Format = "mp4" }))
for ($i = 1; $i -le 12; $i++) {
  Start-Sleep -Milliseconds 1000
  $t = H2 "read-app-text" @{}
  $pct = ($t -split "`n" | Where-Object { $_ -match '^\s+TXT: \d{1,3}%\s*$' }) -join " | "
  $conv = ($t -split "`n" | Where-Object { $_ -match 'TXT:.*(转换中|已输出|转换失败)' } | Select-Object -First 1)
  Write-Output ("t=" + $i + "s  PCT=[" + $pct + "]")
  if ($conv) { Write-Output ("        " + $conv.Trim()) ; if ($conv -match "已输出|转换失败") { break } }
}
Start-Sleep -Milliseconds 500
Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Output "DIAG_DONE"

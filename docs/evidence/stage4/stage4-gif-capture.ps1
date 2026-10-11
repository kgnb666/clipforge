<#
  stage4-gif-capture.ps1 — Demo GIF 逐帧采集器（2026-10-11）

  与主窗口截图同源方法（D-0012/D-0028 方法学）：对应用窗口用
  PrintWindow(PW_RENDERFULLCONTENT) 抓取自身像素（不受遮挡影响）；
  文件对话框为独立顶层窗口（class #32770，同进程），每帧单独抓取后
  按其相对应用窗口的偏移**叠加合成**到帧上 —— 因此帧里能完整看到
  "系统文件对话框"这一段真实交互，且不依赖窗口是否在最前。

  用法：由 stage4-gif.ps1 驱动（后台进程），本脚本按 -DurationSec 循环采集。
#>
param(
  [int]$DurationSec = 22,
  [int]$IntervalMs = 120,
  [string]$OutDir = "$env:TEMP\clipforge-gif",
  [string]$ProcName = "clipforge"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CfGifW32 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][CfGifW32]::SetProcessDPIAware()

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutDir | Out-Null

function Get-AppWin {
  $p = Get-Process $ProcName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { return $null }
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $condPid = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $condPid)
  foreach ($w in $wins) { if ($w.Current.ClassName -eq "Tauri Window") { return $w } }
  foreach ($w in $wins) { if ($w.Current.Name -like "*ClipForge*") { return $w } }
  return $null
}

function Get-DialogWin {
  $p = Get-Process $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $p) { return $null }
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $condPid = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $condPid)
  foreach ($w in $wins) { if ($w.Current.ClassName -eq "#32770" -and $w.Current.IsOffscreen -eq $false) { return $w } }
  return $null
}

function Capture-Hwnd([IntPtr]$h) {
  $r = New-Object CfGifW32+RECT
  [void][CfGifW32]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  if ($w -le 0 -or $ht -le 0) { return $null }
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [void][CfGifW32]::PrintWindow($h, $hdc, 2)
  $g.ReleaseHdc($hdc); $g.Dispose()
  return @{ bmp = $bmp; rect = $r }
}

$deadline = (Get-Date).AddSeconds($DurationSec)
$frame = 0
while ((Get-Date) -lt $deadline) {
  $t0 = Get-Date
  $app = Get-AppWin
  if ($app) {
    $h = [IntPtr]$app.Current.NativeWindowHandle
    $cap = Capture-Hwnd $h
    if ($cap) {
      $bmp = $cap.bmp
      $dlg = Get-DialogWin
      if ($dlg) {
        $dh = [IntPtr]$dlg.Current.NativeWindowHandle
        $dcap = Capture-Hwnd $dh
        if ($dcap) {
          $offX = $dcap.rect.Left - $cap.rect.Left
          $offY = $dcap.rect.Top - $cap.rect.Top
          # 展示性钳制：对话框实际可能部分位于应用窗口之外；为得到无黑边定尺寸帧，
          # 将其偏移钳制到帧内（仅用于 GIF 合成展示，不用于任何测量）。
          $offX = [Math]::Max(0, [Math]::Min($offX, $bmp.Width - $dcap.bmp.Width))
          $offY = [Math]::Max(0, [Math]::Min($offY, $bmp.Height - $dcap.bmp.Height))
          $g = [System.Drawing.Graphics]::FromImage($bmp)
          $g.DrawImage($dcap.bmp, $offX, $offY, $dcap.bmp.Width, $dcap.bmp.Height)
          $g.Dispose()
          $dcap.bmp.Dispose()
        }
      }
      $path = Join-Path $OutDir ("frame_{0:d4}.png" -f $frame)
      $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
      $bmp.Dispose()
      $frame++
    }
  }
  $elapsed = ((Get-Date) - $t0).TotalMilliseconds
  $sleep = $IntervalMs - $elapsed
  if ($sleep -gt 0) { Start-Sleep -Milliseconds ([int]$sleep) }
}
Write-Output ("CAPTURE_DONE frames=" + $frame)

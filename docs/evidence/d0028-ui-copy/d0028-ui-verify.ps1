<#
  d0028-ui-verify.ps1 - D-0028 evidence helper (Windows UI Automation; 2026-10-11)

  Purpose: capture the ClipForge dev window header state after the D-0028 copy change
  (header subtitle de-staged: "Stage 2B . ..." -> product copy).
    -Action dump     : list visible UI text elements; plus a HEADER section (top < 180 px, sorted)
    -Action shot     : restore if minimized, bring to front (z-order safe, D-0012 method), save a PNG
    -Action restore  : un-minimize the app window (WebView2 content is not materialized while minimized)
    -Action minimize : re-minimize the app window (hand the desktop back in its previous state)

  Read-only: never clicks or types; only reads the UIA tree and screen pixels.
  Requires: the ClipForge dev session is already running (window title "clipforge").
  Encoding: keep this file UTF-8 with BOM (Windows PowerShell 5.1 reads it under the ANSI code page otherwise).
#>
param(
  [Parameter(Mandatory = $true)][string]$Action,
  [string]$Out = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CfW32d {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][CfW32d]::SetProcessDPIAware()

function Get-AppProc {
  $p = Get-Process clipforge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { throw "ClipForge window not found" }
  return $p
}

function Get-MainWin {
  $p = Get-AppProc
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $condPid = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $condPid)
  foreach ($w in $wins) { if ($w.Current.Name -eq "clipforge" -and $w.Current.ClassName -eq "Tauri Window") { return $w } }
  foreach ($w in $wins) { if ($w.Current.Name -eq "clipforge") { return $w } }
  throw "ClipForge main window not found"
}

function Get-AppHwnd {
  # Use the UIA element's native handle: Process.MainWindowHandle pointed at a 14x14 helper
  # window of the Tauri process, not the real app window (observed 2026-10-11).
  $w = Get-MainWin
  return [IntPtr]$w.Current.NativeWindowHandle
}

function Invoke-Dump {
  $root = Get-MainWin
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($el in $all) {
    $n = $el.Current.Name
    if ($n -and $n.Trim().Length -gt 0) {
      $r = $el.Current.BoundingRectangle
      $rows.Add([pscustomobject]@{ Top = [int]$r.Top; Left = [int]$r.Left; Name = $n })
    }
  }
  $sorted = @($rows | Sort-Object Top, Left)
  Write-Output ("ELEMENTS_WITH_TEXT: " + $sorted.Count)
  Write-Output "--- HEADER (top < 180) ---"
  $sorted | Where-Object { $_.Top -lt 180 } | ForEach-Object { Write-Output ("TXT[{0},{1}]: {2}" -f $_.Top, $_.Left, $_.Name) }
  Write-Output "--- ALL TEXTS ---"
  $sorted | ForEach-Object { Write-Output ("TXT: " + $_.Name) }
}

function Test-Blank([System.Drawing.Bitmap]$bmp) {
  # Sample a grid of pixels; 2 or fewer distinct colors => treat as blank (PrintWindow miss).
  $seen = New-Object 'System.Collections.Generic.HashSet[int]'
  for ($x = 5; $x -lt $bmp.Width; $x += 40) {
    for ($y = 5; $y -lt $bmp.Height; $y += 40) {
      [void]$seen.Add($bmp.GetPixel($x, $y).ToArgb())
      if ($seen.Count -gt 2) { return $false }
    }
  }
  return $true
}

function Invoke-Shot([string]$dest) {
  $h = Get-AppHwnd
  if ([CfW32d]::IsIconic($h)) {
    [void][CfW32d]::ShowWindow($h, 9)   # SW_RESTORE
    Start-Sleep -Milliseconds 1500      # let WebView2 re-render
  }
  $r = New-Object CfW32d+RECT
  [void][CfW32d]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top

  # Path 1: PrintWindow captures the window's own pixels regardless of z-order
  # (SetForegroundWindow fails from a background process - observed 2026-10-11).
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  $ok = [CfW32d]::PrintWindow($h, $hdc, 2)   # PW_RENDERFULLCONTENT
  $g.ReleaseHdc($hdc)
  if ($ok -and -not (Test-Blank $bmp)) {
    $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output ("SAVED(PrintWindow): {0} ({1} bytes, window {2}x{3})" -f $dest, (Get-Item $dest).Length, $w, $ht)
    return
  }
  $g.Dispose(); $bmp.Dispose()

  # Path 2 (fallback): attach to the foreground thread to legitimately raise the window, then screen-copy.
  $fg = [CfW32d]::GetForegroundWindow()
  $fgTid = [CfW32d]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $myTid = [CfW32d]::GetCurrentThreadId()
  [void][CfW32d]::AttachThreadInput($myTid, $fgTid, $true)
  [void][CfW32d]::BringWindowToTop($h)
  [void][CfW32d]::SetForegroundWindow($h)
  [void][CfW32d]::AttachThreadInput($myTid, $fgTid, $false)
  Start-Sleep -Milliseconds 900
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  if (Test-Blank (New-Object System.Drawing.Bitmap($dest))) { Write-Output "WARNING: capture looks blank (both paths)" }
  Write-Output ("SAVED(screen, raised): {0} ({1} bytes, window {2}x{3} at {4},{5})" -f $dest, (Get-Item $dest).Length, $w, $ht, $r.Left, $r.Top)
}

switch ($Action) {
  "dump" { Invoke-Dump }
  "shot" {
    if (-not $Out) { throw "-Out is required for action shot" }
    Invoke-Shot $Out
  }
  "restore" {
    $h = Get-AppHwnd
    [void][CfW32d]::ShowWindow($h, 9)   # SW_RESTORE
    Start-Sleep -Milliseconds 1500
    [void][CfW32d]::SetForegroundWindow($h)
    Write-Output ("RESTORED hwnd={0} iconic={1}" -f $h, [CfW32d]::IsIconic($h))
  }
  "minimize" {
    $h = Get-AppHwnd
    [void][CfW32d]::ShowWindow($h, 6)   # SW_MINIMIZE
    Start-Sleep -Milliseconds 500
    Write-Output ("MINIMIZED hwnd={0} iconic={1}" -f $h, [CfW32d]::IsIconic($h))
  }
  default { throw "unknown action: $Action" }
}

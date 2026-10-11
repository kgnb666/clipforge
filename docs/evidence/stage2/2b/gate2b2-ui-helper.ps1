<#
  gate2b2-ui-helper.ps1 — Phase 2B-2 UI 验收辅助脚本（Stage 2B 证据工件；2026-10-10）

  用途：以 UI Automation 驱动 ClipForge（dev 构建）完成元数据展示验收：
        原生对话框导入指定素材、读取界面文本（含元数据行）、截图、展开完整路径。
  约束：只操作 ClipForge 自己的窗口与其打开的系统文件对话框；场景路径仅限专用测试素材。

  用法示例：
    powershell -NoProfile -ExecutionPolicy Bypass -File gate2b2-ui-helper.ps1 -Action import -Scenario special
    powershell -NoProfile -ExecutionPolicy Bypass -File gate2b2-ui-helper.ps1 -Action read-app-text
#>
param(
  [Parameter(Mandatory = $true)][string]$Action,
  [string]$Scenario = "",
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
public class CfW32B {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][CfW32B]::SetProcessDPIAware()

$TA = "D:\应聘项目zcode\docs\evidence\stage2\test-assets"
$scenarios = @{
  "special" = Join-Path $TA "测试 目录 & 素材 #1 (终版)'s\样本 视频 #1 (初版)'s.mkv"
  "samplea" = "D:\应聘项目zcode\docs\evidence\gate0c-media\sample_src.mkv"
  "noaudio" = Join-Path $TA "no_audio_sample.mkv"
}

function Get-AppProc {
  $p = Get-Process clipforge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { throw "ClipForge 窗口未找到" }
  return $p
}

function Get-MainWin {
  $p = Get-AppProc
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $condPid = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $condPid)
  foreach ($w in $wins) { if ($w.Current.Name -eq "clipforge" -and $w.Current.ClassName -eq "Tauri Window") { return $w } }
  foreach ($w in $wins) { if ($w.Current.Name -eq "clipforge") { return $w } }
  throw "主窗口未找到"
}

function Get-DialogWin {
  $p = Get-AppProc
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $condPid = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $condPid)
  foreach ($w in $wins) {
    if ($w.Current.ClassName -eq "#32770" -and -not $w.Current.IsOffscreen) { return $w }
  }
  return $null
}

function Wait-DialogWin([int]$timeoutSec) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    $w = Get-DialogWin
    if ($w) { return $w }
    Start-Sleep -Milliseconds 400
  }
  return $null
}

function Wait-DialogClosed([int]$timeoutSec) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (-not (Get-DialogWin)) { return $true }
    Start-Sleep -Milliseconds 400
  }
  return $false
}

function Save-Shot([IntPtr]$h, [string]$dest) {
  $r = New-Object CfW32B+RECT
  [void][CfW32B]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return (Get-Item $dest).Length
}

function Get-AppTexts {
  $root = Get-MainWin
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $names = New-Object System.Collections.Generic.List[string]
  foreach ($el in $all) {
    $n = $el.Current.Name
    if ($n -and $n.Trim().Length -gt 0 -and -not $names.Contains($n)) { $names.Add($n) }
  }
  return $names
}

function Find-ButtonByName($root, [string]$name, [int]$timeoutSec = 8) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    $condB = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condB)
    foreach ($b in $btns) { if ($b.Current.Name -eq $name) { return $b } }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Click-At([double]$x, [double]$y) {
  [void][CfW32B]::SetCursorPos([int]$x, [int]$y)
  Start-Sleep -Milliseconds 200
  [CfW32B]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
  [CfW32B]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 200
}

function Commit-DialogInput($w) {
  $r = $w.Current.BoundingRectangle
  Click-At ($r.X + $r.Width / 2) ($r.Y + 14)
  Start-Sleep -Milliseconds 250
}

function Do-ClickImport {
  $root = Get-MainWin
  $btn = Find-ButtonByName $root "导入视频"
  if (-not $btn) { $btn = Find-ButtonByName $root "选择中…" 1 }
  if (-not $btn) { throw "导入按钮未找到" }
  ($btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
}

function Do-SetFilename([string]$scenario) {
  $path = $scenarios[$scenario]
  if (-not $path) { throw "未知场景: $scenario" }
  $w = Wait-DialogWin 10
  if (-not $w) { throw "对话框未出现" }
  [void][CfW32B]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)
  Start-Sleep -Milliseconds 500
  $condId = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "1148")
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $cands = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condId)
    foreach ($el in $cands) {
      $vp = $null
      if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
        try { $vp.SetValue($path); Start-Sleep -Milliseconds 250; Commit-DialogInput $w; return ("ValuePattern attempt=" + $attempt) } catch { }
      }
    }
    Start-Sleep -Milliseconds 400
  }
  throw "无法写入文件名（ValuePattern 不可用）"
}

function Do-ClickDialogButton([string]$which) {
  $w = Wait-DialogWin 8
  if (-not $w) { throw "对话框未出现" }
  $autoid = $(if ($which -eq "ok") { "1" } else { "2" })
  $prefix = $(if ($which -eq "ok") { "打开" } else { "取消" })
  $condId = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $autoid)
  $cands = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condId)
  $elem = $null
  foreach ($el in $cands) {
    if ($el.Current.Name -like ($prefix + "*")) { $elem = $el; break }
  }
  if (-not $elem) { throw ("未找到对话框按钮: " + $which) }
  $p = $null
  if ($elem.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); Start-Sleep -Milliseconds 400; return "InvokePattern" }
  throw ("按钮不支持调用: " + $which)
}

try {
  switch ($Action) {
    "import" {
      Do-ClickImport
      Start-Sleep -Milliseconds 700
      $method = Do-SetFilename $Scenario
      $clicked = Do-ClickDialogButton "ok"
      $closed = Wait-DialogClosed 12
      Write-Output ("OK: 导入流程完成 scenario={0} {1} {2} dialog_closed={3}" -f $Scenario, $method, $clicked, $closed)
    }
    "import-cancel" {
      Do-ClickImport
      Start-Sleep -Milliseconds 700
      $null = Wait-DialogWin 12
      $clicked = Do-ClickDialogButton "cancel"
      $closed = Wait-DialogClosed 12
      Write-Output ("OK: 取消完成 {0} dialog_closed={1}" -f $clicked, $closed)
    }
    "wait-entry" {
      $basename = Split-Path $scenarios[$Scenario] -Leaf
      if (-not $basename) { throw "未知场景: $Scenario" }
      $deadline = (Get-Date).AddSeconds(15)
      $hit = $null
      while ((Get-Date) -lt $deadline) {
        foreach ($t in (Get-AppTexts)) { if ($t.Contains($basename)) { $hit = $t; break } }
        if ($hit) { break }
        Start-Sleep -Milliseconds 500
      }
      if (-not $hit) { throw ("界面未出现条目: " + $basename) }
      Write-Output ("OK: 条目已出现 [{0}]" -f $hit)
    }
    "read-app-text" {
      foreach ($t in (Get-AppTexts)) { Write-Output ("TXT: " + $t) }
      Write-Output "OK: read-app-text 完成"
    }
    "shot-app" {
      $mw = Get-MainWin
      $h = [IntPtr]$mw.Current.NativeWindowHandle
      [void][CfW32B]::SetForegroundWindow($h)
      Start-Sleep -Milliseconds 700
      $len = Save-Shot $h $Out
      Write-Output ("OK: shot-app {0} ({1} B)" -f $Out, $len)
    }
    "click-entry-path" {
      $root = Get-MainWin
      $condB = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
      $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condB)
      $candidates = New-Object System.Collections.Generic.List[object]
      foreach ($b in $btns) {
        $n = $b.Current.Name
        if ($n -ne "导入视频" -and $n -ne "选择中…") { $candidates.Add($b) }
      }
      if ($candidates.Count -lt 1) { throw "无条目路径按钮" }
      $b = $candidates[0]
      $name = $b.Current.Name
      ($b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
      Write-Output ("OK: 已点击条目路径按钮 [{0}]" -f $name)
    }
    default { throw ("未知 Action: " + $Action) }
  }
  exit 0
} catch {
  Write-Output ("FAIL: " + $_.Exception.Message)
  exit 1
}

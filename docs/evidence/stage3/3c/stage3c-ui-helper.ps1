<#
  stage3c-ui-helper.ps1 — Stage 3C 真实客户端测试辅助脚本（UI Automation；2026-10-11）

  用途：以 Windows UI Automation 驱动 ClipForge（dev 构建）完成 Stage 3C 的真实用户流程：
        点击"导入视频" → 驱动系统文件对话框（设置文件名 / 打开）→ 等待元数据与缩略图
        → 点击转换按钮（MP4 / WebM）→ 等待转换结论 → 截图 / 读取可见文本 → 关闭应用。

  约束：只操作 ClipForge 进程自己的窗口与其打开的系统文件对话框；不修改任何文件；
        所有场景路径映射到 D:\应聘项目zcode\test-assets\stage3c\ 的 Stage 3C 专用素材。
        本脚本**不调用**任何 Tauri IPC / 转换 API —— 全部经真实 UI 元素驱动。

  与 Stage 2A 辅助脚本的差异：新增 click-conv / wait-conv / wait-meta / wait-thumb /
  close-app 五个动作（Stage 3C 需要驱动转换按钮并判定转换结论）。

  用法示例：
    powershell -NoProfile -ExecutionPolicy Bypass -File stage3c-ui-helper.ps1 -Action import -Scenario t1
    powershell -NoProfile -ExecutionPolicy Bypass -File stage3c-ui-helper.ps1 -Action click-conv -Format webm
    powershell -NoProfile -ExecutionPolicy Bypass -File stage3c-ui-helper.ps1 -Action wait-conv -Timeout 120
#>
param(
  [Parameter(Mandatory = $true)][string]$Action,
  [string]$Scenario = "",
  [string]$Format = "",
  [string]$Out = "",
  [int]$Timeout = 60,
  [int]$Index = 0,
  [int]$Expect = 1
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
public class CfW32c {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][CfW32c]::SetProcessDPIAware()

$TA = 'D:\应聘项目zcode\test-assets\stage3c'
$scenarios = @{
  "t1"        = Join-Path $TA "sample.mp4"
  "t3"        = Join-Path $TA "sample.mkv"
  "t4"        = Join-Path $TA "sample.mov"
  "t5"        = Join-Path $TA "sample.avi"
  "t6"        = Join-Path $TA "no_audio.mp4"
  "t7"        = Join-Path $TA "测试 & 视频 #1 (终版)'s\sample.mp4"
  "t8"        = Join-Path $TA "truncated.mp4"
  "t8b"       = Join-Path $TA "corrupt_mdat.mp4"
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
  throw "ClipForge 主窗口未找到"
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

function Save-Shot([IntPtr]$h, [string]$dest) {
  $r = New-Object CfW32c+RECT
  [void][CfW32c]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return (Get-Item $dest).Length
}

function Click-At([double]$x, [double]$y) {
  [void][CfW32c]::SetCursorPos([int]$x, [int]$y)
  Start-Sleep -Milliseconds 200
  [CfW32c]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
  [CfW32c]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 200
}

function Invoke-Element($el) {
  $p = $null
  if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return "InvokePattern" }
  try {
    $p = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern, [ref]$p)) { $p.DoDefaultAction(); return "LegacyIAccessible" }
  } catch { }
  $p = $null
  if ($el.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { $p.Select(); return "SelectionItem" }
  return "none"
}

function Find-ButtonByName($root, [string]$name, [int]$timeoutSec = 6) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    $condB = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condB)
    foreach ($b in $btns) { if ($b.Current.Name -eq $name) { return $b } }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Find-ButtonsByName($root, [string]$name) {
  $condB = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condB)
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($b in $btns) { if ($b.Current.Name -eq $name) { $res.Add($b) } }
  return $res
}

function Do-ClickImport {
  $root = Get-MainWin
  $btn = Find-ButtonByName $root "导入视频"
  if (-not $btn) { $btn = Find-ButtonByName $root "选择中…" 1 }
  if (-not $btn) { throw "导入按钮未找到" }
  ($btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
}

function Commit-DialogInput($w) {
  $r = $w.Current.BoundingRectangle
  Click-At ($r.X + $r.Width / 2) ($r.Y + 14)
  Start-Sleep -Milliseconds 250
}

function Do-SetFilename([string]$scenario) {
  $path = $scenarios[$scenario]
  if (-not $path) { throw "未知场景: $scenario" }
  $w = Wait-DialogWin 10
  if (-not $w) { throw "对话框未出现（无法设置文件名）" }
  [void][CfW32c]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)
  Start-Sleep -Milliseconds 500
  $condId = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "1148")
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $cands = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condId)
    foreach ($el in $cands) {
      $vp = $null
      if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
        try { $vp.SetValue($path); Start-Sleep -Milliseconds 250; Commit-DialogInput $w; return ("ValuePattern(1148) attempt=" + $attempt) } catch { }
      }
      $subs = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
      foreach ($se in $subs) {
        $vp2 = $null
        if ($se.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp2)) {
          try { $vp2.SetValue($path); Start-Sleep -Milliseconds 250; Commit-DialogInput $w; return ("ValuePattern(1148-sub) attempt=" + $attempt) } catch { }
        }
      }
    }
    Start-Sleep -Milliseconds 400
  }
  $cands2 = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condId)
  if ($cands2.Count -gt 0) {
    $rect = $cands2[$cands2.Count - 1].Current.BoundingRectangle
    Click-At ($rect.X + $rect.Width / 2) ($rect.Y + $rect.Height / 2)
    Start-Sleep -Milliseconds 400
  }
  [System.Windows.Forms.Clipboard]::SetText($path)
  Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Start-Sleep -Milliseconds 400
  $verified = $false
  foreach ($el in $cands2) {
    $vp3 = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp3)) {
      if ($vp3.Current.Value -eq $path) { $verified = $true; break }
    }
  }
  return ("ClipboardPaste verified=" + $verified)
}

function Do-ClickDialogButton([string]$which) {
  $w = Wait-DialogWin 8
  if (-not $w) { throw "对话框未出现（无法点击按钮）" }
  $autoid = $(if ($which -eq "ok") { "1" } else { "2" })
  $prefix = $(if ($which -eq "ok") { "打开" } else { "取消" })
  $condId = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $autoid)
  $cands = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condId)
  $elem = $null
  $aux = $null
  foreach ($el in $cands) {
    $ct = $el.Current.ControlType
    if ($el.Current.Name -like ($prefix + "*")) { $elem = $el; break }
    if (-not $aux -and $ct -ne [System.Windows.Automation.ControlType]::ListItem -and $ct -ne [System.Windows.Automation.ControlType]::DataItem) { $aux = $el }
  }
  if (-not $elem) { $elem = $aux }
  if (-not $elem) {
    $all = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el2 in $all) {
      $ct2 = $el2.Current.ControlType
      if ($el2.Current.Name -like ($prefix + "*") -and $ct2 -ne [System.Windows.Automation.ControlType]::ListItem) { $elem = $el2; break }
    }
  }
  if ($elem) {
    $nm = $elem.Current.Name; $ctn = $elem.Current.ControlType.ProgrammaticName.Replace("ControlType.", "")
    $mode = Invoke-Element $elem
    if ($mode -ne "none") {
      Start-Sleep -Milliseconds 400
      return ("{0} (元素[{1}] name=[{2}])" -f $mode, $ctn, $nm)
    }
    $r = $elem.Current.BoundingRectangle
    Click-At ($r.X + $r.Width / 2) ($r.Y + $r.Height / 2)
    Start-Sleep -Milliseconds 400
    return ("MouseClick (元素[{0}] name=[{1}])" -f $ctn, $nm)
  }
  $w2 = Get-DialogWin
  if ($w2) {
    [void][CfW32c]::SetForegroundWindow([IntPtr]$w2.Current.NativeWindowHandle)
    Start-Sleep -Milliseconds 300
    if ($which -eq "ok") {
      $condId2 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "1148")
      $edit = $w2.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condId2)
      if ($edit) { $r2 = $edit.Current.BoundingRectangle; Click-At ($r2.X + $r2.Width / 2) ($r2.Y + $r2.Height / 2) }
    }
    if ($which -eq "ok") { [System.Windows.Forms.SendKeys]::SendWait("{ENTER}") } else { [System.Windows.Forms.SendKeys]::SendWait("{ESC}") }
    Start-Sleep -Milliseconds 300
    return "SendKeys"
  }
  throw ("未找到对话框按钮: " + $which)
}

function Wait-Text([string[]]$patterns, [int]$timeoutSec, [string]$label) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    foreach ($t in (Get-AppTexts)) {
      foreach ($p in $patterns) {
        if ($t -like ("*" + $p + "*")) { return $t }
      }
    }
    Start-Sleep -Milliseconds 500
  }
  throw ("等待超时（" + $timeoutSec + "s）：未出现 " + $label + " —— 期望任一 [" + ($patterns -join " | ") + "]")
}

try {
  switch ($Action) {
    "wait-window" {
      $w = Get-MainWin
      Write-Output ("OK: 主窗口就绪 name=[{0}] class=[{1}]" -f $w.Current.Name, $w.Current.ClassName)
    }
    "import" {
      Do-ClickImport
      Start-Sleep -Milliseconds 700
      $method = Do-SetFilename $Scenario
      Do-ClickDialogButton "ok" | Out-Null
      $closed = Wait-DialogClosed 12
      Write-Output ("OK: 导入流程完成 scenario={0} setvia={1} dialog_closed={2}" -f $Scenario, $method, $closed)
    }
    "wait-entry" {
      $basename = Split-Path $scenarios[$Scenario] -Leaf
      if (-not $basename) { throw "未知场景: $Scenario" }
      $hit = Wait-Text @($basename) 15 ("条目文本 " + $basename)
      Write-Output ("OK: 界面已出现条目文本 [{0}]" -f $hit)
    }
    "wait-meta" {
      $hit = Wait-Text @("时长", "元数据读取失败") $Timeout "元数据结论（成功或失败）"
      Write-Output ("OK: 元数据已结论 [{0}]" -f $hit)
    }
    "wait-thumb" {
      $hit = Wait-Text @("视频缩略图") $Timeout "缩略图元素"
      Write-Output ("OK: 缩略图已渲染 [{0}]" -f $hit)
    }
    "click-conv" {
      $map = @{ "mp4" = "MP4"; "webm" = "WebM"; "retry" = "重新转换" }
      $name = $map[$Format.ToLower()]
      if (-not $name) { throw ("未知格式: " + $Format) }
      $root = Get-MainWin
      $btns = Find-ButtonsByName $root $name
      if ($btns.Count -eq 0) {
        # 转换中/失败态下按钮名可能是 重试
        $btns = Find-ButtonsByName $root "重试"
      }
      if ($btns.Count -eq 0) { throw ("未找到转换按钮: " + $name) }
      $i = [Math]::Min($Index, $btns.Count - 1)
      $el = $btns[$i]
      $mode = Invoke-Element $el
      if ($mode -eq "none") {
        $r = $el.Current.BoundingRectangle
        Click-At ($r.X + $r.Width / 2) ($r.Y + $r.Height / 2)
        $mode = "MouseClick"
      } else {
        Start-Sleep -Milliseconds 200
      }
      Write-Output ("OK: 已点击转换按钮 [{0}] (匹配数={1} 选中 index={2} 方式={3})" -f $name, $btns.Count, $i, $mode)
    }
    "wait-conv" {
      $hit = Wait-Text @("已输出", "转换失败") $Timeout "转换结论"
      Write-Output ("OK: 转换已结论 [{0}]" -f $hit)
    }
    "wait-settled" {
      # 精确收敛判定：界面无"转换中"且"已结论"条目数达到 Expect（累计值）。
      # 使用累计 Expect 可避免"上一条目的结论文本被误判为本次结论"。
      $deadline = (Get-Date).AddSeconds($Timeout)
      while ((Get-Date) -lt $deadline) {
        $texts = Get-AppTexts
        $busy = @($texts | Where-Object { $_ -like "*转换中*" }).Count
        $done = @($texts | Where-Object { $_ -like "*已输出*" -or $_ -like "*转换失败*" }).Count
        if ($busy -eq 0 -and $done -ge $Expect) {
          Write-Output ("OK: 转换已收敛（已结论条目=" + $done + " 期望>=" + $Expect + " 进行中=" + $busy + "）")
          exit 0
        }
        Start-Sleep -Milliseconds 500
      }
      throw ("等待超时（" + $Timeout + "s）：未收敛到 已结论>=" + $Expect + " 且 进行中=0")
    }
    "wait-notice" {
      $hit = Wait-Text @("转换失败：") $Timeout "转换失败通知"
      Write-Output ("OK: 已出现失败通知 [{0}]" -f $hit)
    }
    "read-app-text" {
      foreach ($t in (Get-AppTexts)) { Write-Output ("TXT: " + $t) }
      Write-Output "OK: read-app-text 完成"
    }
    "shot-app" {
      $mw = Get-MainWin
      $h = [IntPtr]$mw.Current.NativeWindowHandle
      [void][CfW32c]::SetForegroundWindow($h)
      Start-Sleep -Milliseconds 700
      $len = Save-Shot $h $Out
      Write-Output ("OK: shot-app {0} ({1} B)" -f $Out, $len)
    }
    "close-app" {
      $w = Get-MainWin
      $wp = $null
      if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$wp)) {
        $wp.Close()
        Start-Sleep -Milliseconds 600
        Write-Output "OK: 已请求关闭主窗口(WindowPattern.Close)"
      } else {
        throw "主窗口不支持 WindowPattern.Close"
      }
    }
    default { throw ("未知 Action: " + $Action) }
  }
  exit 0
} catch {
  Write-Output ("FAIL: " + $_.Exception.Message)
  exit 1
}

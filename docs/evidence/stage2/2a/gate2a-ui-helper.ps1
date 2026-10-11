<#
  gate2a-ui-helper.ps1 — Gate-2A UI 验收辅助脚本（Stage 2A 证据工件；2026-10-10）

  用途：以 UI Automation 驱动 ClipForge（dev 构建）完成 Gate-2A 的 UI 级验收操作：
        点击"导入视频"、等待并驱动系统文件对话框（设置文件名/打开/取消）、切换文件类型过滤器、
        截图、读取应用可见文本、展开条目完整路径。

  约束：只操作 ClipForge 进程自己的窗口与其打开的系统文件对话框；
        不修改任何用户文件、系统设置；所有场景路径映射到 docs/evidence/stage2/test-assets/ 的专用素材。

  用法示例：
    powershell -NoProfile -ExecutionPolicy Bypass -File gate2a-ui-helper.ps1 -Action import -Scenario special
    powershell -NoProfile -ExecutionPolicy Bypass -File gate2a-ui-helper.ps1 -Action shot-app -Out x.png
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
public class CfW32 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][CfW32]::SetProcessDPIAware()

$TA = Join-Path $PSScriptRoot "..\test-assets"
$scenarios = @{
  "special" = Join-Path $TA "测试 目录 & 素材 #1 (终版)'s\样本 视频 #1 (初版)'s.mkv"
  "fake"    = Join-Path $TA "fake_text.mp4"
  "noext"   = Join-Path $TA "no_extension_sample"
  "acl"     = Join-Path $TA "acl-test-copy.mkv"
  "broken"  = Join-Path $TA "broken-link.mp4"
  "locked"  = Join-Path $TA "locked-test-copy.mkv"
  "longpath" = (Get-Content -Raw (Join-Path $TA "longpath.txt")).Trim()
  "truncated" = Join-Path $TA "truncated_sample.mp4"
  "samplea" = "D:\应聘项目zcode\docs\evidence\gate0c-media\sample_src.mkv"
}

function Get-AppProc {
  $p = Get-Process clipforge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { throw "ClipForge 窗口未找到" }
  return $p
}

function Get-MainWin {
  # 主窗口：标题为 clipforge 的顶层窗口（类名 Tauri Window）。
  # 注意：对话框打开期间 Process.MainWindowHandle 可能指向其他窗口，不能使用。
  $p = Get-AppProc
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $condPid = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $condPid)
  foreach ($w in $wins) { if ($w.Current.Name -eq "clipforge" -and $w.Current.ClassName -eq "Tauri Window") { return $w } }
  foreach ($w in $wins) { if ($w.Current.Name -eq "clipforge") { return $w } }
  throw "ClipForge 主窗口未找到"
}

function Get-AppRoot {
  return Get-MainWin
}

function Get-DialogWin {
  # 系统文件对话框：仅认类名 #32770（排除输入法状态窗 SoPY_Status、WebView/Tao 内部窗口等）。
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

function Find-ByName($root, [string]$name, $ctype) {
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
  if ($ctype) {
    $cond = New-Object System.Windows.Automation.AndCondition($cond, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ctype)))
  }
  return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

function Find-ByAutoId($root, [string]$id) {
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
  return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

function Save-Shot([IntPtr]$h, [string]$dest) {
  $r = New-Object CfW32+RECT
  [void][CfW32]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
  $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  return (Get-Item $dest).Length
}

function Get-AppTexts {
  $root = Get-AppRoot
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $names = New-Object System.Collections.Generic.List[string]
  foreach ($el in $all) {
    $n = $el.Current.Name
    if ($n -and $n.Trim().Length -gt 0 -and -not $names.Contains($n)) { $names.Add($n) }
  }
  return $names
}

function Find-ButtonByName($root, [string]$name, [int]$timeoutSec = 6) {
  # WebView2 的 UIA 树在新客户端首次查询时可能尚未就绪：带重试的按钮查找。
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    $condB = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
    $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condB)
    foreach ($b in $btns) { if ($b.Current.Name -eq $name) { return $b } }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Do-ClickImport {
  $root = Get-AppRoot
  $btn = Find-ButtonByName $root "导入视频"
  if (-not $btn) { $btn = Find-ButtonByName $root "选择中…" 1 }
  if (-not $btn) { throw "导入按钮未找到" }
  ($btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
}

function Click-At([double]$x, [double]$y) {
  [void][CfW32]::SetCursorPos([int]$x, [int]$y)
  Start-Sleep -Milliseconds 200
  [CfW32]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
  [CfW32]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 200
}

function Invoke-Element($el) {
  # 多模式调用：本机文件对话框的部分控件为 DirectUI 元素，需要多种模式依次尝试。
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

function Commit-DialogInput($w) {
  # 点击对话框标题栏区域使输入失焦（DirectUI 组合框在失焦时提交文本）
  $r = $w.Current.BoundingRectangle
  Click-At ($r.X + $r.Width / 2) ($r.Y + 14)
  Start-Sleep -Milliseconds 250
}

function Do-SetFilename([string]$scenario) {
  $path = $scenarios[$scenario]
  if (-not $path) { throw "未知场景: $scenario" }
  $w = Wait-DialogWin 10
  if (-not $w) { throw "对话框未出现（无法设置文件名）" }
  [void][CfW32]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)
  Start-Sleep -Milliseconds 500
  # 1) ValuePattern（对 autoid=1148 及其子元素；带重试，覆盖对话框初始化竞态）
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
  # 2) 兜底：点击文件名区域聚焦 → 剪贴板粘贴 → 回读校验
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
  # 注意：清单列表项的 autoid 也是 0,1,2...，必须排除 ListItem/DataItem 并按名称优先匹配
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
  # 键盘兜底：先点击文件名区域聚焦，再按默认按钮（打开=回车 / 取消=ESC）
  $w2 = Get-DialogWin
  if ($w2) {
    [void][CfW32]::SetForegroundWindow([IntPtr]$w2.Current.NativeWindowHandle)
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

function Click-EntryButton([int]$index) {
  $root = Get-AppRoot
  $condB = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condB)
  $candidates = New-Object System.Collections.Generic.List[object]
  foreach ($b in $btns) {
    $n = $b.Current.Name
    if ($n -ne "导入视频" -and $n -ne "选择中…") { $candidates.Add($b) }
  }
  if ($candidates.Count -le $index) { throw ("条目路径按钮不足: 需要 index=" + $index + " 实际=" + $candidates.Count) }
  $b = $candidates[$index]
  $name = $b.Current.Name
  ($b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
  Write-Output ("OK: 已点击条目路径按钮 [{0}]" -f $name)
}

try {
  switch ($Action) {
    "click-import" {
      Do-ClickImport
      Write-Output "OK: 已点击导入视频"
    }
    "wait-dialog" {
      $w = Wait-DialogWin 15
      if (-not $w) { throw "对话框未出现" }
      Write-Output ("OK: dialog name=[{0}] class=[{1}] hwnd={2}" -f $w.Current.Name, $w.Current.ClassName, $w.Current.NativeWindowHandle)
    }
    "wait-closed" {
      if (Wait-DialogClosed 12) { Write-Output "OK: 对话框已关闭" } else { throw "对话框未在期限内关闭" }
    }
    "set-filename" {
      $method = Do-SetFilename $Scenario
      Write-Output ("OK: 已设置文件名（{0}）场景={1}" -f $method, $Scenario)
    }
    "click-ok" {
      Do-ClickDialogButton "ok"
      Write-Output "OK: 已点击 打开"
    }
    "click-cancel" {
      Do-ClickDialogButton "cancel"
      Write-Output "OK: 已点击 取消"
    }
    "close-dialog" {
      $w = Get-DialogWin
      if (-not $w) { Write-Output "OK: 无对话框可关闭"; exit 0 }
      $wp = $null
      if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$wp)) {
        $wp.Close()
        Start-Sleep -Milliseconds 400
        Write-Output "OK: 已请求关闭对话框(WindowPattern)"
      } else {
        throw "对话框不支持 WindowPattern.Close"
      }
    }
    "dump-dialog" {
      $w = Wait-DialogWin 10
      if (-not $w) { throw "对话框未出现" }
      Write-Output ("dialog=[{0}] class=[{1}]" -f $w.Current.Name, $w.Current.ClassName)
      $all = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
      $count = 0
      foreach ($el in $all) {
        $c = $el.Current
        if ($c.Name -or $c.AutomationId) {
          $nm = $c.Name; if ($nm.Length -gt 64) { $nm = $nm.Substring(0, 64) }
          Write-Output ("  [{0}] name=[{1}] autoid=[{2}]" -f $c.ControlType.ProgrammaticName.Replace("ControlType.", ""), $nm, $c.AutomationId)
          $count++
          if ($count -ge 70) { break }
        }
      }
      Write-Output "OK: dump 完成（上限 70 项）"
    }
    "import" {
      Do-ClickImport
      Start-Sleep -Milliseconds 700
      $method = Do-SetFilename $Scenario
      Do-ClickDialogButton "ok"
      $closed = Wait-DialogClosed 12
      Write-Output ("OK: 导入流程完成 scenario={0} setvia={1} dialog_closed={2}" -f $Scenario, $method, $closed)
    }
    "import-cancel" {
      Do-ClickImport
      Start-Sleep -Milliseconds 700
      $w = Wait-DialogWin 12
      if (-not $w) { throw "对话框未出现" }
      Do-ClickDialogButton "cancel"
      $closed = Wait-DialogClosed 12
      Write-Output ("OK: 取消流程完成 dialog_closed={0}" -f $closed)
    }
    "switch-filter-allfiles" {
      $w = Wait-DialogWin 10
      if (-not $w) { throw "对话框未出现" }
      $condId = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "1136")
      $combo = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condId)
      if (-not $combo) { throw "未找到过滤器控件(autoid=1136)" }
      $ecp = $null
      if ($combo.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$ecp)) {
        $ecp.Expand()
      } else {
        $r0 = $combo.Current.BoundingRectangle
        Click-At ($r0.X + $r0.Width / 2) ($r0.Y + $r0.Height / 2)
      }
      Start-Sleep -Milliseconds 700
      $condL = New-Object System.Windows.Automation.OrCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem))
      )
      $chosen = $null
      foreach ($scope in @($w, [System.Windows.Automation.AutomationElement]::RootElement)) {
        $items = $scope.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condL)
        foreach ($it in $items) { if ($it.Current.Name -like "所有文件*") { $chosen = $it; break } }
        if ($chosen) { break }
      }
      if (-not $chosen) { throw "未找到'所有文件'过滤器项" }
      $name = $chosen.Current.Name
      $mm = Invoke-Element $chosen
      if ($mm -eq "none") {
        $r1 = $chosen.Current.BoundingRectangle
        Click-At ($r1.X + $r1.Width / 2) ($r1.Y + $r1.Height / 2)
        $mm = "MouseClick"
      }
      Start-Sleep -Milliseconds 400
      Write-Output ("OK: 已切换过滤器 -> [{0}] via {1}" -f $name, $mm)
    }
    "shot-app" {
      $mw = Get-MainWin
      $h = [IntPtr]$mw.Current.NativeWindowHandle
      [void][CfW32]::SetForegroundWindow($h)
      Start-Sleep -Milliseconds 700
      $len = Save-Shot $h $Out
      Write-Output ("OK: shot-app {0} ({1} B)" -f $Out, $len)
    }
    "shot-dialog" {
      $w = Wait-DialogWin 10
      if (-not $w) { throw "对话框未出现" }
      $len = Save-Shot ([IntPtr]$w.Current.NativeWindowHandle) $Out
      Write-Output ("OK: shot-dialog {0} ({1} B)" -f $Out, $len)
    }
    "read-app-text" {
      foreach ($t in (Get-AppTexts)) { Write-Output ("TXT: " + $t) }
      Write-Output "OK: read-app-text 完成"
    }
    "click-entry-path" {
      Click-EntryButton 0
    }
    "wait-entry" {
      $basename = Split-Path $scenarios[$Scenario] -Leaf
      if (-not $basename) { throw "未知场景: $Scenario" }
      $deadline = (Get-Date).AddSeconds(10)
      $hit = $null
      while ((Get-Date) -lt $deadline) {
        foreach ($t in (Get-AppTexts)) { if ($t.Contains($basename)) { $hit = $t; break } }
        if ($hit) { break }
        Start-Sleep -Milliseconds 500
      }
      if (-not $hit) { throw ("未在界面中找到条目文本: " + $basename) }
      Write-Output ("OK: 界面已出现条目文本 [{0}]" -f $hit)
    }
    default { throw ("未知 Action: " + $Action) }
  }
  exit 0
} catch {
  Write-Output ("FAIL: " + $_.Exception.Message)
  exit 1
}

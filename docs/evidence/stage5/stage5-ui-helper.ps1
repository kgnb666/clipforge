<#
  stage5-ui-helper.ps1 — Stage 5 功能优化验收辅助脚本（UI Automation；2026-10-12）

  用途：驱动**已安装的 release 版 ClipForge**（%LOCALAPPDATA%\ClipForge\ClipForge.exe）
        完成真实用户流程：导入 → 元数据 → 缩略图 → 点击转换 → 等待结论 → 截图 → 关闭。
        全部经真实 UI 元素驱动；不调用任何 Tauri IPC / 转换 API。

  相较 stage4-release-ui-helper.ps1 新增：wait-progress / wait-explorer / close-explorer；
  click-conv 增加 to-mp4 / to-webm / reveal 按钮名映射（Stage 5 新功能）。原差异说明：
    1. 目标进程名 ClipForge（release 产品名），窗口标题 "ClipForge"；
    2. 素材根路径改为 D:\Cliporge\test-assets\stage3c（项目已迁移自 D:\应聘项目zcode）；
    3. 截图优先 PrintWindow(PW_RENDERFULLCONTENT)（防遮挡，D-0012/D-0028 方法学），
       CopyFromScreen 仅作后备；截图前自动还原最小化窗口。

  用法示例：
    powershell -NoProfile -ExecutionPolicy Bypass -File stage4-release-ui-helper.ps1 -Action wait-window
    powershell -NoProfile -ExecutionPolicy Bypass -File stage4-release-ui-helper.ps1 -Action import -Scenario t7
    powershell -NoProfile -ExecutionPolicy Bypass -File stage4-release-ui-helper.ps1 -Action click-conv -Format mp4
#>
param(
  [Parameter(Mandatory = $true)][string]$Action,
  [string]$Scenario = "",
  [string]$Format = "",
  [string]$Out = "",
  [string]$Path = "",
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
public class CfW32s4 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][CfW32s4]::SetProcessDPIAware()

$TA = 'D:\Cliporge\test-assets\stage3c'
$scenarios = @{
  "t1"        = Join-Path $TA "sample.mp4"
  "t3"        = Join-Path $TA "sample.mkv"
  "t4"        = Join-Path $TA "sample.mov"
  "t5"        = Join-Path $TA "sample.avi"
  "t6"        = Join-Path $TA "no_audio.mp4"
  "t7"        = Join-Path $TA "测试 & 视频 #1 (终版)'s\sample.mp4"
  "t8"        = Join-Path $TA "truncated.mp4"
  "t8b"       = Join-Path $TA "corrupt_mdat.mp4"
  "bbb"       = "D:\Cliporge\test-assets\real-world\Big_Buck_Bunny_720p_h265.mp4"
  "surf"      = "D:\Cliporge\test-assets\real-world\surfing_720p_h264_aac.mp4"
}

function Get-AppProc {
  $p = Get-Process ClipForge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $p) { throw "ClipForge 进程/窗口未找到" }
  return $p
}

function Get-MainWin {
  $p = Get-AppProc
  $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
  $condPid = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
  $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, $condPid)
  foreach ($w in $wins) { if ($w.Current.Name -eq "ClipForge" -and $w.Current.ClassName -eq "Tauri Window") { return $w } }
  foreach ($w in $wins) { if ($w.Current.Name -eq "ClipForge") { return $w } }
  throw "ClipForge 主窗口未找到"
}

function Get-MainHwnd {
  $w = Get-MainWin
  return [IntPtr]$w.Current.NativeWindowHandle
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

function Test-Blank([System.Drawing.Bitmap]$bmp) {
  $seen = New-Object 'System.Collections.Generic.HashSet[int]'
  for ($x = 5; $x -lt $bmp.Width; $x += 40) {
    for ($y = 5; $y -lt $bmp.Height; $y += 40) {
      [void]$seen.Add($bmp.GetPixel($x, $y).ToArgb())
      if ($seen.Count -gt 2) { return $false }
    }
  }
  return $true
}

function Save-Shot([IntPtr]$h, [string]$dest) {
  if ([CfW32s4]::IsIconic($h)) { [void][CfW32s4]::ShowWindow($h, 9) }   # SW_RESTORE
  $r = New-Object CfW32s4+RECT
  [void][CfW32s4]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  # Path 1: PrintWindow（不受遮挡影响）
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  $ok = [CfW32s4]::PrintWindow($h, $hdc, 2)
  $g.ReleaseHdc($hdc)
  $g.Dispose()
  if ($ok -and -not (Test-Blank $bmp)) {
    $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return ("SAVED(PrintWindow): " + (Get-Item $dest).Length)
  }
  $bmp.Dispose()
  # Path 2: 屏幕像素（后备）
  $bmp2 = New-Object System.Drawing.Bitmap($w, $ht)
  $g2 = [System.Drawing.Graphics]::FromImage($bmp2)
  $g2.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp2.Size)
  $bmp2.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
  $g2.Dispose(); $bmp2.Dispose()
  return ("SAVED(CopyFromScreen fallback): " + (Get-Item $dest).Length)
}

function Click-At([double]$x, [double]$y) {
  [void][CfW32s4]::SetCursorPos([int]$x, [int]$y)
  Start-Sleep -Milliseconds 200
  [CfW32s4]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
  [CfW32s4]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
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

function Set-FilenameVerified($w, [string]$path) {
  # 设置“文件名”编辑框并**核验生效**；失败时回退为 点击+全选+剪贴板粘贴。
  # v2（2026-10-11 深夜）：第一轮验收中出现“SetValue 报成功但对话框实际未采用”，
  # 导致误导入对话框记忆的上次文件（桌面旧文件）——本版以“核验+断言”取代盲信与盲点击。
  $condId = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "1148")
  $cands = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condId)
  foreach ($el in $cands) {
    $targets = New-Object System.Collections.Generic.List[object]
    $targets.Add($el)
    foreach ($se in $el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) { $targets.Add($se) }
    foreach ($t in $targets) {
      $vp = $null
      if ($t.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) {
        try {
          $vp.SetValue($path)
          Start-Sleep -Milliseconds 300
          if ($vp.Current.Value -eq $path) { return "ValuePattern+verified" }
        } catch { }
      }
    }
  }
  foreach ($el in $cands) {
    $r = $el.Current.BoundingRectangle
    if ($r.Width -gt 0 -and $r.Height -gt 0) {
      Click-At ($r.X + $r.Width / 2) ($r.Y + $r.Height / 2)
      Start-Sleep -Milliseconds 300
      [System.Windows.Forms.SendKeys]::SendWait("^a")
      Start-Sleep -Milliseconds 150
      [System.Windows.Forms.Clipboard]::SetText($path)
      Start-Sleep -Milliseconds 200
      [System.Windows.Forms.SendKeys]::SendWait("^v")
      Start-Sleep -Milliseconds 400
      $vp2 = $null
      if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp2)) {
        if ($vp2.Current.Value -eq $path) { return "ClickPaste+verified" }
      }
    }
  }
  return "UNVERIFIED"
}

function Do-SetFilename([string]$scenario) {
  $path = $scenarios[$scenario]
  if (-not $path) { throw "未知场景: $scenario" }
  $w = Wait-DialogWin 10
  if (-not $w) { throw "对话框未出现（无法设置文件名）" }
  [void][CfW32s4]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)
  Start-Sleep -Milliseconds 500
  $method = Set-FilenameVerified $w $path
  if ($method -eq "UNVERIFIED") { throw ("文件名核验失败：编辑框值不等于目标路径 —— " + $path) }
  return $method
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
    [void][CfW32s4]::SetForegroundWindow([IntPtr]$w2.Current.NativeWindowHandle)
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
    "wait-path" {
      if (-not $Path) { throw "缺少 -Path 参数" }
      $hit = Wait-Text @($Path) $Timeout ("完整路径 " + $Path)
      Write-Output ("OK: 界面已出现完整路径 [{0}]" -f $hit)
    }
    "wait-meta" {
      $hit = Wait-Text @("时长", "元数据读取失败") $Timeout "元数据结论（成功或失败）"
      Write-Output ("OK: 元数据已结论 [{0}]" -f $hit)
    }
    "wait-thumb" {
      $hit = Wait-Text @("视频缩略图", "缩略图生成失败") $Timeout "缩略图元素"
      Write-Output ("OK: 缩略图已结论 [{0}]" -f $hit)
    }
    "click-conv" {
      $map = @{ "mp4" = "MP4"; "webm" = "WebM"; "retry" = "重新转换"; "to-mp4" = "转 MP4"; "to-webm" = "转 WEBM"; "reveal" = "打开所在文件夹" }
      $name = $map[$Format.ToLower()]
      if (-not $name) { throw ("未知格式: " + $Format) }
      $root = Get-MainWin
      $btns = Find-ButtonsByName $root $name
      if ($btns.Count -eq 0) { $btns = Find-ButtonsByName $root "重试" }
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
    "wait-progress" {
      # 轮询界面文本中出现"xx%"（转换进度条文本），返回首个命中值；仅在前台转换中才有此文本。
      $deadline = (Get-Date).AddSeconds($Timeout)
      # 说明：WebView2 的 UIA 只暴露可交互元素为独立节点；纯文本（进度百分比 span）出现在
      # 容器聚合名中 —— 因此用**子串**匹配（不加 ^$ 锚定），与既有 wait-meta/-settled 的通配语义一致。
      $rx = [regex]'\d{1,3}%'
      while ((Get-Date) -lt $deadline) {
        foreach ($t in (Get-AppTexts)) { if ($rx.IsMatch($t.Trim())) { Write-Output ("OK: 观察到进度文本 [{0}]" -f $t.Trim()); exit 0 } }
        Start-Sleep -Milliseconds 250
      }
      throw ("等待超时（" + $Timeout + "s）：未观察到进度百分比文本")
    }
    "wait-explorer" {
      # 等待资源管理器窗口（CabinetWClass）出现，返回其标题。
      $deadline = (Get-Date).AddSeconds($Timeout)
      $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
      while ((Get-Date) -lt $deadline) {
        $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($w in $wins) {
          if ($w.Current.ClassName -eq "CabinetWClass") {
            Write-Output ("OK: 资源管理器窗口已出现 [{0}]" -f $w.Current.Name)
            exit 0
          }
        }
        Start-Sleep -Milliseconds 400
      }
      throw ("等待超时（" + $Timeout + "s）：未出现资源管理器窗口")
    }
    "close-explorer" {
      $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
      $wins = $rootEl.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
      $closed = 0
      foreach ($w in $wins) {
        if ($w.Current.ClassName -eq "CabinetWClass") {
          $wp = $null
          if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$wp)) { $wp.Close(); $closed++ }
        }
      }
      Start-Sleep -Milliseconds 600
      Write-Output ("OK: 已关闭资源管理器窗口 " + $closed + " 个")
    }
    "wait-settled" {
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
    "read-app-text" {
      foreach ($t in (Get-AppTexts)) { Write-Output ("TXT: " + $t) }
      Write-Output "OK: read-app-text 完成"
    }
    "shot-app" {
      $h = Get-MainHwnd
      [void][CfW32s4]::SetForegroundWindow($h)
      Start-Sleep -Milliseconds 700
      $res = Save-Shot $h $Out
      Write-Output ("OK: shot-app {0} ({1})" -f $Out, $res)
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

<#
  stage4-acceptance.ps1 — Stage 4 安装验收总脚本（2026-10-11）

  流程：静默安装 → 安装体核对（目录/注册表/快捷方式/版本信息）→ 启动应用
        → UIA 真实流程冒烟：T7 中文特殊路径 MP4 转换 + T5 AVI→WebM 转换（含截图）
        → 关闭应用 → 进程/日志检查 → 输出文件 ffprobe 核验
        → 静默卸载 → 清理核验（目录/注册表/快捷方式）

  所有输出写入 UTF-8 日志：docs/evidence/stage4/stage4-acceptance.log
  依赖：stage4-release-ui-helper.ps1（同目录）、FFprobe（PATH）
#>
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$S4     = "D:\Cliporge\docs\evidence\stage4"
$LOG    = Join-Path $S4 "stage4-acceptance.log"
$SETUP  = "D:\cargo-target\release\bundle\nsis\ClipForge_0.1.0_x64-setup.exe"
$HELPER = Join-Path $S4 "stage4-release-ui-helper.ps1"
$APPDIR = Join-Path $env:LOCALAPPDATA "ClipForge"
$EXE    = Join-Path $APPDIR "ClipForge.exe"
$UNINST = Join-Path $APPDIR "uninstall.exe"
$SM     = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ClipForge.lnk"
$DESK   = Join-Path ([Environment]::GetFolderPath("Desktop")) "ClipForge.lnk"
$T7DIR  = "D:\Cliporge\test-assets\stage3c\测试 & 视频 #1 (终版)'s"
$T5FILE = "D:\Cliporge\test-assets\stage3c\sample.avi"
$APPLOG = Join-Path $env:LOCALAPPDATA "com.clipforge.app\logs\clipforge.log"

function W([string]$s) { $s | Out-File -Append -Encoding utf8 $LOG; Write-Host $s }
function H2 { param([string]$a, [hashtable]$kw)
  $pre = @()
  foreach ($k in $kw.Keys) { $pre += "-$k"; $pre += [string]$kw[$k] }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $HELPER -Action $a @pre 2>&1
  $code = $LASTEXITCODE
  $out | ForEach-Object { W ("    " + $_) }
  W ("    [helper exit={0}]" -f $code)
  return ($out -join "`n")
}
function Wait-Until([scriptblock]$cond, [int]$timeoutSec, [string]$label) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (& $cond) { return $true }
    Start-Sleep -Milliseconds 700
  }
  W ("    !! 等待超时: " + $label)
  return $false
}

"=== Stage 4 安装验收 ===" | Out-File -Encoding utf8 $LOG
W ("开始时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
W ("安装包: " + $SETUP)
W ("安装包 SHA256: " + (Get-FileHash $SETUP -Algorithm SHA256).Hash)

# ---------- 1. 静默安装 ----------
W ""
W "--- [1] 静默安装 (/S) ---"
$p = Start-Process -FilePath $SETUP -ArgumentList "/S" -PassThru -Wait
W ("安装器退出码: " + $p.ExitCode)
$ok = Wait-Until { Test-Path $UNINST } 60 "uninstall.exe 出现"
W ("安装完成: " + $ok)

# ---------- 2. 安装体核对 ----------
W ""
W "--- [2] 安装体核对 ---"
W ("安装目录: " + $APPDIR)
Get-ChildItem $APPDIR | ForEach-Object { W ("    " + $_.Name + "  " + $_.Length + " B") }
if (Test-Path $EXE) {
  $vi = (Get-Item $EXE).VersionInfo
  W ("主程序: " + $EXE)
  W ("    ProductName    = " + $vi.ProductName)
  W ("    FileDescription= " + $vi.FileDescription)
  W ("    FileVersion    = " + $vi.FileVersion)
  W ("    CompanyName    = " + $vi.CompanyName)
} else { W "!! 主程序 ClipForge.exe 不存在" }
$reg = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge" -ErrorAction SilentlyContinue
if ($reg) {
  W ("注册表: DisplayName=" + $reg.DisplayName + " | DisplayVersion=" + $reg.DisplayVersion + " | Publisher=" + $reg.Publisher + " | MainBinaryName=" + $reg.MainBinaryName)
  W ("        InstallLocation=" + $reg.InstallLocation)
  W ("        UninstallString=" + $reg.UninstallString)
} else { W "!! 注册表卸载项不存在" }
W ("开始菜单快捷方式: " + (Test-Path $SM) + "  ($SM)")
W ("桌面快捷方式:     " + (Test-Path $DESK) + "  ($DESK)")

# ---------- 3. 启动应用 ----------
W ""
W "--- [3] 启动已安装应用 ---"
Start-Process -FilePath $EXE | Out-Null
$r = H2 "wait-window" @{}
W ("窗口就绪: " + ($r -match "OK:"))

# ---------- 4. UIA 冒烟：T7 中文特殊路径 → MP4 ----------
W ""
W "--- [4] T7 中文/特殊路径 导入 → 元数据 → 缩略图 ---"
$r = H2 "import" @{ Scenario = "t7" }
$r = H2 "wait-entry" @{ Scenario = "t7" }
$r = H2 "wait-meta" @{ Timeout = 60 }
$r = H2 "wait-thumb" @{ Timeout = 60 }
$r = H2 "shot-app" @{ Out = (Join-Path $S4 "stage4-release-main.png") }
W "--- 点击 MP4 并等待收敛 ---"
$r = H2 "click-conv" @{ Format = "mp4" }
$r = H2 "wait-settled" @{ Timeout = 300; Expect = 1 }
$r = H2 "shot-app" @{ Out = (Join-Path $S4 "stage4-release-converted.png") }
W "--- 界面文本（转换结论）---"
$r = H2 "read-app-text" @{}

# ---------- 5. UIA 冒烟：T5 AVI → WebM（第二条目）----------
W ""
W "--- [5] T5 AVI 导入 → WebM 转换（第二条目并行存在）---"
$r = H2 "import" @{ Scenario = "t5" }
$r = H2 "wait-entry" @{ Scenario = "t5" }
$r = H2 "wait-meta" @{ Timeout = 60 }
$r = H2 "click-conv" @{ Format = "webm"; Index = 0 }
$r = H2 "wait-settled" @{ Timeout = 600; Expect = 2 }
$r = H2 "shot-app" @{ Out = (Join-Path $S4 "stage4-release-webm.png") }

# ---------- 6. 关闭应用 + 进程/日志检查 ----------
W ""
W "--- [6] 关闭应用 ---"
$r = H2 "close-app" @{}
$gone = Wait-Until { -not (Get-Process ClipForge -ErrorAction SilentlyContinue) } 30 "ClipForge 进程退出"
W ("应用进程已退出: " + $gone)
$left = @(Get-Process clipforge, ffmpeg, ffprobe -ErrorAction SilentlyContinue).Count
W ("残留进程（clipforge/ffmpeg/ffprobe）: " + $left)
W ("应用日志尾部（shutdown cleanup）:")
Get-Content $APPLOG -Tail 4 | ForEach-Object { W ("    " + $_) }

# ---------- 7. 输出文件核验 ----------
W ""
W "--- [7] 输出文件核验 ---"
$newT7 = Get-ChildItem $T7DIR -Filter "*_converted*" | Sort-Object LastWriteTime -Descending | Select-Object -First 2
foreach ($f in $newT7) { W ("    " + $f.Name + "  " + $f.Length + " B  " + $f.LastWriteTime.ToString("HH:mm:ss")) }
$newT5 = Get-ChildItem (Split-Path $T5FILE) -Filter "sample_converted*" | Sort-Object LastWriteTime -Descending | Select-Object -First 2
foreach ($f in $newT5) { W ("    " + $f.Name + "  " + $f.Length + " B  " + $f.LastWriteTime.ToString("HH:mm:ss")) }
foreach ($f in @($newT7[0], $newT5[0])) {
  if ($f) {
    $pr = & ffprobe -v error -show_entries "format=format_name,duration" -show_entries "stream=codec_name,codec_type,width,height" -of default=noprint_wrappers=1 $f.FullName 2>&1
    W ("    ffprobe [" + $f.Name + "]: " + (($pr | Where-Object { $_ -match "=" }) -join "; "))
  }
}

# ---------- 8. 静默卸载 ----------
W ""
W "--- [8] 静默卸载 ---"
$p2 = Start-Process -FilePath $UNINST -ArgumentList "/S" -PassThru -Wait
W ("卸载器退出码: " + $p2.ExitCode)
$dirGone = Wait-Until { -not (Test-Path $APPDIR) } 120 "安装目录删除"
$regGone = Wait-Until { -not (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge" -ErrorAction SilentlyContinue) } 30 "注册表项删除"
$smGone  = Wait-Until { -not (Test-Path $SM) -and -not (Test-Path $DESK) } 30 "快捷方式删除"
W ("安装目录已删除: " + $dirGone)
W ("注册表项已删除: " + $regGone)
W ("快捷方式已删除: " + $smGone)
W ""
W "=== Stage 4 安装验收结束 ==="
W ("结束时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

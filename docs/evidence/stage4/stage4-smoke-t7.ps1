<#
  stage4-smoke-t7.ps1 — Stage 4 修正版冒烟（第二轮，2026-10-11 深夜）

  背景：第一轮（stage4-acceptance.ps1）在 T7 步骤出现"对话框路径注入未生效 →
        误导入对话框记忆的桌面旧文件"，且脚本未中止。归因见 stage4-acceptance.log 与报告。
  本脚本（第二轮）：
    1) helper 升级为"路径设置后核验 + 导入后断言完整路径"，任何一步失败立即中止；
    2) 聚焦 T7（中文+空格+&+#+' 特殊路径）→ MP4 转换；
    3) 完成后重拍 README 用主界面/转换完成截图（覆盖第一轮的无效截图）；
    4) 安装→冒烟→卸载全链路重跑，输出 UTF-8 日志 stage4-smoke-t7.log。
#>
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$S4     = "D:\Cliporge\docs\evidence\stage4"
$LOG    = Join-Path $S4 "stage4-smoke-t7.log"
$SETUP  = "D:\cargo-target\release\bundle\nsis\ClipForge_0.1.0_x64-setup.exe"
$HELPER = Join-Path $S4 "stage4-release-ui-helper.ps1"
$APPDIR = Join-Path $env:LOCALAPPDATA "ClipForge"
$EXE    = Join-Path $APPDIR "ClipForge.exe"
$UNINST = Join-Path $APPDIR "uninstall.exe"
$T7PATH = "D:\Cliporge\test-assets\stage3c\测试 & 视频 #1 (终版)'s\sample.mp4"
$T7DIR  = Split-Path $T7PATH
$APPLOG = Join-Path $env:LOCALAPPDATA "com.clipforge.app\logs\clipforge.log"

function W([string]$s) { $s | Out-File -Append -Encoding utf8 $LOG; Write-Host $s }
function H2 { param([string]$a, [hashtable]$kw)
  $pre = @()
  foreach ($k in $kw.Keys) { $pre += "-$k"; $pre += [string]$kw[$k] }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $HELPER -Action $a @pre 2>&1
  $code = $LASTEXITCODE
  $out | ForEach-Object { W ("    " + $_) }
  W ("    [helper exit={0}]" -f $code)
  if ($code -ne 0) { throw ("helper 失败: Action=$a exit=$code —— " + ($out -join " ")) }
  return ($out -join "`n")
}
function Wait-Until([scriptblock]$cond, [int]$timeoutSec, [string]$label) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 700 }
  W ("    !! 等待超时: " + $label); return $false
}

"=== Stage 4 冒烟（第二轮，T7 中文特殊路径，修正版）===" | Out-File -Encoding utf8 $LOG
W ("开始时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
W ("安装包 SHA256: " + (Get-FileHash $SETUP -Algorithm SHA256).Hash)

try {
  # ---------- 1. 安装 ----------
  W ""
  W "--- [1] 静默安装 + 安装体快核 ---"
  $p = Start-Process -FilePath $SETUP -ArgumentList "/S" -PassThru -Wait
  W ("安装器退出码: " + $p.ExitCode)
  if (-not (Wait-Until { Test-Path $UNINST } 60 "uninstall.exe")) { throw "安装未完成" }
  $vi = (Get-Item $EXE).VersionInfo
  $reg = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge"
  W ("主程序: ClipForge.exe " + (Get-Item $EXE).Length + " B | ProductName=" + $vi.ProductName + " | 版本=" + $vi.FileVersion + " | CompanyName=" + $vi.CompanyName)
  W ("注册表: DisplayName=" + $reg.DisplayName + " | Publisher=" + $reg.Publisher + " | MainBinaryName=" + $reg.MainBinaryName)

  # ---------- 2. 启动 ----------
  W ""
  W "--- [2] 启动应用 ---"
  Start-Process -FilePath $EXE | Out-Null
  [void](H2 "wait-window" @{})

  # ---------- 3. T7 全流程 ----------
  W ""
  W "--- [3] T7 导入（含路径核验）---"
  $before = @(Get-ChildItem $T7DIR -Filter "*_converted*" | Select-Object -ExpandProperty Name)
  W ("    导入前 T7 目录已有输出: " + ($before -join ", "))
  [void](H2 "import" @{ Scenario = "t7" })
  [void](H2 "wait-path" @{ Path = $T7PATH; Timeout = 30 })   # 断言：界面条目为 T7 完整路径
  [void](H2 "wait-meta" @{ Timeout = 60 })
  [void](H2 "wait-thumb" @{ Timeout = 60 })
  [void](H2 "shot-app" @{ Out = (Join-Path $S4 "stage4-release-main.png") })
  W "--- 点击 MP4 并等待收敛 ---"
  [void](H2 "click-conv" @{ Format = "mp4" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  [void](H2 "shot-app" @{ Out = (Join-Path $S4 "stage4-release-converted.png") })
  $texts = H2 "read-app-text" @{}
  if ($texts -notmatch "已输出 MP4") { throw "未出现 已输出 MP4 结论" }
  W "    断言通过：界面出现 [已输出 MP4] 结论"

  # ---------- 4. 关闭 + 复核 ----------
  W ""
  W "--- [4] 关闭应用与进程复核 ---"
  [void](H2 "close-app" @{})
  $gone = Wait-Until { -not (Get-Process ClipForge -ErrorAction SilentlyContinue) } 30 "进程退出"
  W ("应用进程已退出: " + $gone)
  W ("残留进程（clipforge/ffmpeg/ffprobe）: " + @(Get-Process clipforge, ffmpeg, ffprobe -ErrorAction SilentlyContinue).Count)
  Get-Content $APPLOG -Tail 3 | ForEach-Object { W ("    " + $_) }

  # ---------- 5. 输出核验 ----------
  W ""
  W "--- [5] T7 输出文件核验 ---"
  $after = @(Get-ChildItem $T7DIR -Filter "*_converted*" | Sort-Object LastWriteTime -Descending)
  $new = @($after | Where-Object { $before -notcontains $_.Name })
  foreach ($f in $new) { W ("    新增: " + $f.Name + "  " + $f.Length + " B  " + $f.LastWriteTime.ToString("HH:mm:ss")) }
  if ($new.Count -eq 0) { throw "T7 目录未出现新输出" }
  $pr = & ffprobe -v error -show_entries "format=format_name,duration" -show_entries "stream=codec_name,codec_type,width,height" -of default=noprint_wrappers=1 $new[0].FullName 2>&1
  W ("    ffprobe: " + (($pr | Where-Object { $_ -match "=" }) -join "; "))

  # ---------- 6. 卸载 ----------
  W ""
} catch {
  W ("FAIL: " + $_.Exception.Message)
}
# ---------- 6. 静默卸载与清理核验（无论上文成败均执行）----------
W "--- [6] 静默卸载与清理核验 ---"
$p2 = Start-Process -FilePath $UNINST -ArgumentList "/S" -PassThru -Wait
W ("卸载器退出码: " + $p2.ExitCode)
$dirGone = Wait-Until { -not (Test-Path $APPDIR) } 120 "安装目录删除"
$regGone = Wait-Until { -not (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge" -ErrorAction SilentlyContinue) } 30 "注册表项删除"
$smGone  = Wait-Until { -not (Test-Path (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ClipForge.lnk")) } 30 "开始菜单快捷方式删除"
W ("安装目录已删除: " + $dirGone + " | 注册表已删除: " + $regGone + " | 快捷方式已删除: " + $smGone)
W ""
W "=== 第二轮冒烟结束 ==="
W ("结束时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

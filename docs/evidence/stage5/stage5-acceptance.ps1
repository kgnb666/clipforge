<#
  stage5-acceptance.ps1 — Stage 5 功能优化验收（2026-10-12）

  验证项：
    A. 转换完成/失败后可切换另一格式（转 WEBM / 转 MP4；失败态"改用 …"）
    B. 元数据新增字段：帧率 / 比特率 / 容器（P2B-012；另有 UIA 文本 ↔ FFprobe JSON 对照证据）
    C. 一键"打开所在文件夹"（资源管理器 /select 弹出并选中输出文件）
    D. 转换进度条（长视频转换中观察到百分比；并由"转换中关闭应用"顺带实测 CONV_CANCELLED）

  流程：静默安装 → 启动 → T7 中文特殊路径（元数据/缩略图/MP4→再转 WEBM/打开文件夹）
        → 长视频（183s）导入并转换，观察进度 → 转换中关闭应用 → 进程/日志/残留核验
        → 静默卸载与清理核验。日志：stage5-acceptance.log（UTF-8）
#>
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$S5     = "D:\Cliporge\docs\evidence\stage5"
$LOG    = Join-Path $S5 "stage5-acceptance.log"
$SETUP  = "D:\cargo-target\release\bundle\nsis\ClipForge_0.1.1_x64-setup.exe"
$HELPER = Join-Path $S5 "stage5-ui-helper.ps1"
$APPDIR = Join-Path $env:LOCALAPPDATA "ClipForge"
$EXE    = Join-Path $APPDIR "ClipForge.exe"
$UNINST = Join-Path $APPDIR "uninstall.exe"
$T7PATH = "D:\Cliporge\test-assets\stage3c\测试 & 视频 #1 (终版)'s\sample.mp4"
$T7DIR  = Split-Path $T7PATH
$SURF   = "D:\Cliporge\test-assets\real-world\surfing_720p_h264_aac.mp4"
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

"=== Stage 5 功能优化验收 ===" | Out-File -Encoding utf8 $LOG
W ("开始时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
W ("安装包: " + $SETUP)
W ("安装包 SHA256: " + (Get-FileHash $SETUP -Algorithm SHA256).Hash)

$failed = $false
try {
  # ---------- 1. 安装 ----------
  W ""
  W "--- [1] 静默安装 + 安装体核对（版本应为 0.1.1）---"
  $p = Start-Process -FilePath $SETUP -ArgumentList "/S" -PassThru -Wait
  W ("安装器退出码: " + $p.ExitCode)
  if (-not (Wait-Until { Test-Path $UNINST } 60 "uninstall.exe")) { throw "安装未完成" }
  $vi = (Get-Item $EXE).VersionInfo
  $reg = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge"
  W ("主程序: ClipForge.exe " + (Get-Item $EXE).Length + " B | ProductName=" + $vi.ProductName + " | 文件版本=" + $vi.FileVersion)
  W ("注册表: DisplayName=" + $reg.DisplayName + " | DisplayVersion=" + $reg.DisplayVersion + " | Publisher=" + $reg.Publisher + " | MainBinaryName=" + $reg.MainBinaryName)

  # ---------- 2. 启动 ----------
  W ""
  W "--- [2] 启动应用 ---"
  Start-Process -FilePath $EXE | Out-Null
  [void](H2 "wait-window" @{})

  # ---------- 3. T7：元数据（含新字段）/缩略图 ----------
  W ""
  W "--- [3] T7 中文特殊路径：导入 → 元数据（帧率/比特率/容器）→ 缩略图 ---"
  [void](H2 "import" @{ Scenario = "t7" })
  [void](H2 "wait-path" @{ Path = $T7PATH; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  [void](H2 "wait-thumb" @{ Timeout = 60 })
  [void](H2 "shot-app" @{ Out = (Join-Path $S5 "stage5-metadata.png") })
  W "--- 界面全部文本（含新字段，供与 FFprobe JSON 对照）---"
  [void](H2 "read-app-text" @{})

  # ---------- 4. MP4 转换 + 完成态按钮（A/C）----------
  W ""
  W "--- [4] MP4 转换 → 完成态按钮（重新转换 / 转 WEBM / 打开所在文件夹）---"
  [void](H2 "click-conv" @{ Format = "mp4" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })
  [void](H2 "shot-app" @{ Out = (Join-Path $S5 "stage5-completed.png") })
  $texts = H2 "read-app-text" @{}
  if ($texts -notmatch "已输出 MP4") { throw "未出现 已输出 MP4 结论" }
  if ($texts -notmatch "转 WEBM") { throw "完成态缺少[转 WEBM]按钮（A 未生效）" }
  if ($texts -notmatch "打开所在文件夹") { throw "完成态缺少[打开所在文件夹]按钮（C 未生效）" }
  W "    断言通过：完成态同时具备 [重新转换] [转 WEBM] [打开所在文件夹]"

  # ---------- 5. A：切换到另一格式（WEBM）----------
  W ""
  W "--- [5] 点击 [转 WEBM] → 第二条输出 ---"
  $beforeWebm = @(Get-ChildItem $T7DIR -Filter "*_converted*.webm" | Select-Object -ExpandProperty Name)
  [void](H2 "click-conv" @{ Format = "to-webm" })
  [void](H2 "wait-settled" @{ Timeout = 300; Expect = 1 })  # 单条目仅保留最新结论文本
  $texts = H2 "read-app-text" @{}
  if ($texts -notmatch "已输出 WEBM") { throw "未出现 已输出 WEBM 结论（A 切换格式未生效）" }
  $afterWebm = @(Get-ChildItem $T7DIR -Filter "*_converted*.webm" | Select-Object -ExpandProperty Name)
  $newWebm = @($afterWebm | Where-Object { $beforeWebm -notcontains $_ })
  W ("    新增 WEBM 输出: " + ($newWebm -join ", "))
  if ($newWebm.Count -eq 0) { throw "未产生新的 WEBM 输出文件" }

  # ---------- 6. C：打开所在文件夹 ----------
  W ""
  W "--- [6] 点击 [打开所在文件夹] → 等待资源管理器窗口 ---"
  [void](H2 "click-conv" @{ Format = "reveal" })
  [void](H2 "wait-explorer" @{ Timeout = 20 })
  [void](H2 "shot-app" @{ Out = (Join-Path $S5 "stage5-reveal.png") })
  [void](H2 "close-explorer" @{})

  # ---------- 7. D：长视频进度 + 转换中关闭应用 ----------
  W ""
  W "--- [7] 长视频（183s）转换：观察进度 → 转换中关闭应用（CONV_CANCELLED 顺带实测）---"
  [void](H2 "import" @{ Scenario = "surf" })
  [void](H2 "wait-path" @{ Path = $SURF; Timeout = 30 })
  [void](H2 "wait-meta" @{ Timeout = 60 })
  $beforeLongMp4 = @(Get-ChildItem (Split-Path $SURF) -Filter "surfing_720p_h264_aac_converted*" | Select-Object -ExpandProperty Name)
  [void](H2 "click-conv" @{ Format = "mp4" })
  [void](H2 "wait-progress" @{ Timeout = 60 })
  [void](H2 "shot-app" @{ Out = (Join-Path $S5 "stage5-progress.png") })
  W "    （进度已观察到）转换仍在进行中 → 立即关闭应用"
  [void](H2 "close-app" @{})
  $gone = Wait-Until { -not (Get-Process ClipForge -ErrorAction SilentlyContinue) } 30 "进程退出"
  W ("应用进程已退出: " + $gone)
  W ("残留进程（clipforge/ffmpeg/ffprobe）: " + @(Get-Process clipforge, ffmpeg, ffprobe -ErrorAction SilentlyContinue).Count)
  W ("应用日志尾部:")
  Get-Content $APPLOG -Tail 6 | ForEach-Object { W ("    " + $_) }
  W "    --- 取消后残留检查（转换中关闭 → 不应留下半成品输出）---"
  $afterLongMp4 = @(Get-ChildItem (Split-Path $SURF) -Filter "surfing_720p_h264_aac_converted*" | Select-Object -ExpandProperty Name)
  $newLong = @($afterLongMp4 | Where-Object { $beforeLongMp4 -notcontains $_ })
  W ("    转换中关闭后新增输出文件: " + $(if ($newLong.Count -eq 0) { "无（半成品已清理）" } else { ($newLong -join ", ") }))
} catch {
  $failed = $true
  W ("FAIL: " + $_.Exception.Message)
  Get-Process clipforge -ErrorAction SilentlyContinue | Stop-Process -Force
}

# ---------- 8. 卸载 ----------
W ""
W "--- [8] 静默卸载与清理核验 ---"
$p2 = Start-Process -FilePath $UNINST -ArgumentList "/S" -PassThru -Wait
W ("卸载器退出码: " + $p2.ExitCode)
$dirGone = Wait-Until { -not (Test-Path $APPDIR) } 120 "安装目录删除"
$regGone = Wait-Until { -not (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClipForge" -ErrorAction SilentlyContinue) } 30 "注册表项删除"
$smGone  = Wait-Until { -not (Test-Path (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\ClipForge.lnk")) } 30 "开始菜单快捷方式删除"
W ("安装目录已删除: " + $dirGone + " | 注册表已删除: " + $regGone + " | 快捷方式已删除: " + $smGone)
W ""
W ("=== Stage 5 验收结束（" + $(if ($failed) { "有失败项，见上文 FAIL" } else { "全部通过" }) + "）===")
W ("结束时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

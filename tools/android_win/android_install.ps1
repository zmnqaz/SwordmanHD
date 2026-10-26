# 一键把 Android 的 APK 装到 USB 连着的手机, 并把资源包 (resource/ 与 mod/ 两个文件夹) 推进手机 (Windows)。双击 install_android.bat 即可。
#   install_android.bat                          自动找 APK (本目录 / 下载文件夹里最新的 SwordmanHD*.apk) 和资源包 (本目录\pck、C:\pck、下载\pck)
#   install_android.bat 路径\SwordmanHD.apk       或把 APK 拖到 install_android.bat 上
#   install_android.bat -Pck D:\包目录            指定资源包目录
#   install_android.bat -SkipApk                  只推资源包 (APK 已装过)
# 第一次自动下载 Google 官方 platform-tools (adb) 到本目录 bin\。手机要先开 USB 调试并连着线, 弹出授权点「允许」。
param(
    [Parameter(Position = 0)][string]$Apk,
    [string]$Pck,
    [switch]$SkipApk
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Here = $PSScriptRoot
$Bin = Join-Path $Here "bin"
$Adb = Join-Path $Bin "platform-tools\adb.exe"
$ToolUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
$Downloads = Join-Path $env:USERPROFILE "Downloads"
$Package = "com.tdj.swordmanhd"
$DeviceDir = "/sdcard/Android/data/$Package/files"   # 与 ResPacks.android_dirs 一致

function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "`n错误: $m" -ForegroundColor Red; exit 1 }
# adb 把进度写到 stderr, 脚本是 Stop 模式, 直接调用会被当异常; 这里统一放宽并看退出码
function Adb {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $Adb @args 2>&1 | Out-Host; return $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
}
function AdbOut {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { return (& $Adb @args 2>&1 | Out-String) } finally { $ErrorActionPreference = $prev }
}

# 1. adb
if (-not (Test-Path $Adb)) {
    Step "下载 Google 官方 platform-tools (只第一次, 约 7MB)"
    New-Item -ItemType Directory -Force $Bin | Out-Null
    $zip = Join-Path $Bin "platform-tools.zip"
    try { Invoke-WebRequest $ToolUrl -OutFile $zip -UseBasicParsing -TimeoutSec 600 }
    catch { Fail ("下载失败: " + $_.Exception.Message + "`n手动办法: 浏览器打开 $ToolUrl 下载, 解压到 $Bin (得到 $Bin\platform-tools\adb.exe) 再重跑") }
    Expand-Archive -Force $zip $Bin
    Remove-Item $zip
    if (-not (Test-Path $Adb)) { Fail "解压后没找到 $Adb (可能被杀毒软件删除)" }
}

# 2. 手机
Step "检查手机"
[void](AdbOut start-server)
$devs = (AdbOut devices) -split "`r?`n" | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }
if (-not $devs) { Fail "没找到手机。打开手机 设置→开发者选项→USB 调试 (开发者选项: 设置→关于手机→连点版本号), 用数据线连上, 手机弹出授权点「允许」后重跑" }
if ($devs -match "unauthorized") { Fail "手机还没授权这台电脑: 看手机屏幕上的「允许 USB 调试」点允许 (勾选一律允许), 然后重跑" }
if ($devs -match "offline") { Fail "手机状态是 offline: 拔了线重插, 或手机里关开一次 USB 调试, 然后重跑" }
if (@($devs | Where-Object { $_ -match "\sdevice$" }).Count -gt 1) { Fail "连了不止一台设备, 请只留一台" }
Write-Host ($devs -join "`n")

# 3. 装 APK
if (-not $SkipApk) {
    Step "找 APK"
    if (-not $Apk) {
        $c = Get-ChildItem $Here, $Downloads -Filter "SwordmanHD*.apk" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($c) { $Apk = $c.FullName }
    }
    if (-not $Apk -or -not (Test-Path $Apk)) { Fail "没找到 APK。把 SwordmanHD.apk 放进本目录或下载文件夹, 或拖到 install_android.bat 上; 只推资源包就加 -SkipApk" }
    $Apk = (Resolve-Path $Apk).Path
    Write-Host ("APK: {0} ({1:N1} MB)" -f $Apk, ((Get-Item $Apk).Length / 1MB))
    Step "安装 APK (覆盖安装, 不清数据)"
    if ((Adb install -r $Apk) -ne 0) { Fail "adb install 失败 (上面是原因; 常见: 手机上的安装确认没点 / 旧版签名不同要先卸载 / 存储空间不足)" }
}

# 4. 资源包
Step "推资源包"
$PckDir = $null
foreach ($c in @($Pck, (Join-Path $Here "pck"), "C:\pck", (Join-Path $Downloads "pck"))) {
    if ($c -and (Test-Path (Join-Path $c "resource\common_assets.pck"))) { $PckDir = $c; break }
}
if (-not $PckDir) { Fail "没找到资源包目录 (要有 resource\common_assets.pck)。放进 C:\pck 或本目录\pck, 或用 -Pck 指定" }
Write-Host "资源包目录: $PckDir"
foreach ($d in "resource", "mod") {
    $dir = Join-Path $PckDir $d
    if (-not (Test-Path $dir)) { continue }
    [void](Adb shell mkdir -p "$DeviceDir/$d")
    foreach ($item in (Get-ChildItem $dir -Filter "*.pck" | Sort-Object Name)) {
        $f = $item.FullName; $n = "$d/$($item.Name)"
        $size = $item.Length
        $remote = (AdbOut shell stat -c %s "$DeviceDir/$n").Trim()
        if ($remote -eq "$size") { Write-Host ("  = {0} 已在手机上且大小一致, 跳过" -f $n); continue }
        Write-Host ("  + {0} ({1:N0} MB) ..." -f $n, ($size / 1MB))
        if ((Adb push $f "$DeviceDir/$n") -ne 0) { Fail "推 $n 失败 (手机存储空间够吗? 约需 2GB; 线拔了吗?)" }
    }
}

Write-Host "`n完成。打开手机上的「天地劫」。" -ForegroundColor Green
Write-Host "资源包已在手机上的 $DeviceDir ; 以后只更新 APK 时不用再推 (脚本会按大小跳过)。"

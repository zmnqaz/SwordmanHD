# 一键把 iOS 的 IPA 自签并装到 USB 连着的 iPad/iPhone (Windows)。双击 install_ios.bat 即可; 说明见 docs/打包/iOS.md。
#   install_ios.bat                              自动找 IPA (本目录 / 下载文件夹里的 SwordmanHD-unsigned*.ipa 或 GitHub 下的 zip)
#   install_ios.bat 路径\SwordmanHD-unsigned.ipa   或把 IPA 拖到 install_ios.bat 上
#   install_ios.bat -From 用户@开发机:<仓库>/dist/ios/SwordmanHD-unsigned.ipa    用 scp 从开发机拉
# 签名用 plumesign (Plume Impactor 的命令行, 开源), 第一次自动下载到本目录 bin\。Apple ID 密码与二次验证码在窗口里输入, 登录状态由 plumesign 保存, 本脚本不碰密码。
param(
    [Parameter(Position = 0)][string]$Ipa,
    [string]$From,
    [switch]$Relogin
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Here = $PSScriptRoot
$Bin = Join-Path $Here "bin"
$Exe = Join-Path $Bin "plumesign.exe"
$ToolUrl = "https://github.com/claration/impactor/releases/download/v2.6.5/plumesign-windows-x86_64.exe"
$ToolSha256 = "2311ed3090253bcc63ebb96a92ebca5f373f5344e8462ed089cf3bec6a75186b"
$Downloads = Join-Path $env:USERPROFILE "Downloads"

function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "`n错误: $m" -ForegroundColor Red; exit 1 }

# 1. 找 IPA
Step "找 IPA"
if ($From) {
    if (-not (Get-Command scp -ErrorAction SilentlyContinue)) { Fail "没有 scp (Windows 设置 → 可选功能 → OpenSSH 客户端)" }
    $Ipa = Join-Path $Here "SwordmanHD-unsigned.ipa"
    scp $From $Ipa
    if ($LASTEXITCODE -ne 0) { Fail "scp 失败" }
}
if (-not $Ipa) {
    $zip = Get-ChildItem $Downloads, $Here -Filter "SwordmanHD-unsigned-ipa*.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $cand = Get-ChildItem $Here, $Downloads -Filter "SwordmanHD-unsigned*.ipa" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($zip -and (-not $cand -or $zip.LastWriteTime -gt $cand.LastWriteTime)) {
        Write-Host "解压 $($zip.FullName)"
        Expand-Archive -Force $zip.FullName $Here
        $cand = Get-Item (Join-Path $Here "SwordmanHD-unsigned.ipa") -ErrorAction SilentlyContinue
    }
    if ($cand) { $Ipa = $cand.FullName }
}
if (-not $Ipa -or -not (Test-Path $Ipa)) {
    Fail "没找到 IPA。把 SwordmanHD-unsigned.ipa (或 GitHub 下的 SwordmanHD-unsigned-ipa.zip) 放进本目录或下载文件夹, 或把 IPA 拖到 install_ios.bat 上, 或加 -From 用户@开发机:路径"
}
$Ipa = (Resolve-Path $Ipa).Path
Write-Host ("IPA: {0} ({1:N1} MB)" -f $Ipa, ((Get-Item $Ipa).Length / 1MB))

# 2. Apple 的 USB 驱动 (iTunes 带的 Apple Mobile Device Service)
Step "检查 Apple 设备驱动"
if (-not (Get-Service "Apple Mobile Device Service" -ErrorAction SilentlyContinue)) {
    Write-Host "没装 iTunes (它带的服务负责认出 iPad)。需要装非 Microsoft Store 版的 iTunes。"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $a = Read-Host "现在用 winget 安装 iTunes? (Y/n)"
        if ($a -ne "n") {
            winget install -e --id Apple.iTunes --accept-package-agreements --accept-source-agreements
            Write-Host "装好后如提示重启, 请重启电脑再运行本脚本。"
        }
    } else {
        Write-Host "请从 https://www.apple.com/itunes/ 下载 Windows 版 iTunes (不要用 Store 版) 安装后再运行。"
    }
    if (-not (Get-Service "Apple Mobile Device Service" -ErrorAction SilentlyContinue)) { Fail "仍未检测到 Apple Mobile Device Service" }
}

# 3. plumesign (Plume Impactor 的命令行, 开源, 单个 exe 不带 DLL 依赖; Sideloader 的 Windows 版缺 plist.dll 跑不起来)
if (-not (Test-Path $Exe)) {
    Step "下载 plumesign (只第一次)"
    New-Item -ItemType Directory -Force $Bin | Out-Null
    $tmp = "$Exe.part"
    try { Invoke-WebRequest $ToolUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 600 }
    catch {
        Fail ("下载 plumesign 失败: " + $_.Exception.Message + "`n手动办法: 用浏览器打开 $ToolUrl 下载, 把文件改名为 plumesign.exe 放进 $Bin 再重跑 (GitHub 在国内常断, 可挂代理或多试几次)")
    }
    if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -ne $ToolSha256) { Remove-Item $tmp; Fail "plumesign 下载文件校验不符, 已删除" }
    Move-Item $tmp $Exe
    Start-Sleep -Seconds 2
    if (-not (Test-Path $Exe)) { Fail "plumesign.exe 下载后被删掉了, 多半是 Windows 安全中心/杀毒软件拦截 (签名工具常被误报)。把 $Bin 加入排除项后重跑" }
}

# 4. 登录 Apple ID: 只第一次。登录成功后在 bin\apple_id.txt 记下邮箱 (密码不记), 之后直接跳过; 换账号或签名提示未登录时加 -Relogin
Step "Apple ID"
$Marker = Join-Path $Bin "apple_id.txt"
if ((Test-Path $Marker) -and -not $Relogin) {
    Write-Host ("已登录: " + (Get-Content $Marker -Raw).Trim() + "  (要换账号或重新登录: install_ios.bat -Relogin)")
} else {
    $mail = Read-Host "Apple ID 邮箱"
    Write-Host "接着输入密码, 以及 iPad/iPhone 上弹出的二次验证码。"
    & $Exe account login -u $mail
    if ($LASTEXITCODE -ne 0) { Fail "登录失败 (退出码 $LASTEXITCODE)" }
    Set-Content -Path $Marker -Value $mail -Encoding UTF8
}

# 5. 签名并安装
Step "签名并安装 (请先用数据线连好 iPad, 点 '信任此电脑'; 开发者模式要装完才出现, 不用提前开)"
& $Exe sign --package $Ipa --apple-id --register-and-install
if ($LASTEXITCODE -ne 0) { Fail "plumesign 退出码 $LASTEXITCODE (上面是它的输出; 常见: 没点信任 / 驱动没装 / Apple ID 本周新建 App ID 过多; 提示要开发者模式就去 设置→隐私与安全性 打开后重启, 再重跑; 提示没登录/凭据失效就加 -Relogin 重跑)" }

Write-Host "`n已装到设备。接下来在 iPad 上依次做 (iOS/iPadOS 16+ 的开发者模式开关要装过一次才会出现):" -ForegroundColor Green
Write-Host "  1. 设置 → 隐私与安全性 → 最下面「开发者模式」→ 打开 → 按提示重启 → 重启后再点一次「打开」并输入密码"
Write-Host "  2. 设置 → 通用 → VPN 与设备管理 → 你的 Apple ID → 信任"
Write-Host "  3. 打开「天地劫」"
Write-Host "免费 Apple ID 的证书 7 天有效, 到期重跑本脚本重新签名即可 (存档和资源包不丢)。"
Write-Host "下一步: 把 resource、mod 文件夹里的 .pck 资源包推进应用, 双击 push_packs.bat (见 docs/打包/iOS.md)。"

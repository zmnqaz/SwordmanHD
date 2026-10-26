# 一键把资源包 (resource/ 与 mod/ 里的 .pck) 推进 USB 连着的 iPad/iPhone 上的应用 (Windows), 不用 iTunes。双击 push_packs.bat。
#   push_packs.bat                    包目录自动找 (本目录\pck、C:\pck、下载\pck 里有 resource\common_assets.pck 的)
#   push_packs.bat -Pck D:\包目录      指定包目录
#   push_packs.bat -Only common_assets,common_story,classic_images    只推这几个包名 (不写就推 resource/ 与 mod/ 里全部)
# 需要: 已装好 iOS 应用、iPad 连着并点过「信任」、装过 iTunes (Apple 设备驱动)、Python 3.9+ (python.org 装, 勾 Add to PATH)。
# 第一次会在本目录 bin\pmd 建一个独立 Python 环境并装 pymobiledevice3 (开源, 约 50MB)。
param(
    [string]$Pck,
    [string[]]$Only = @()
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }   # 进度条方块字符在 GBK 控制台里会乱码
$Here = $PSScriptRoot
$Venv = Join-Path $Here "bin\pmd"
$Pmd = Join-Path $Venv "Scripts\pymobiledevice3.exe"
$Downloads = Join-Path $env:USERPROFILE "Downloads"

function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "`n错误: $m" -ForegroundColor Red; exit 1 }
# 原生命令的 stderr 在 Stop 模式下会被当异常, 统一放宽后看退出码
function Run { $p = $ErrorActionPreference; $ErrorActionPreference = "Continue"; try { & $args[0] @($args | Select-Object -Skip 1) | Out-Host; return $LASTEXITCODE } finally { $ErrorActionPreference = $p } }   # 输出直接打到屏幕: 不然输出行会混进返回值, 退出码判断永远为真; 不合并 stderr (合并会把进度条显示成红色 NativeCommandError)

# 生成占位 lzfse wheel (纯 Python, 1KB): 等价于仓库里的 lzfse-0.4.2-py3-none-any.whl
function New-LzfseStub($path) {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $files = [ordered]@{
        "lzfse/__init__.py" = "def _no(*a, **k):`n    raise NotImplementedError('lzfse placeholder: no LZFSE implementation')`n`n`ncompress = decompress = _no`n"
        "lzfse-0.4.2.dist-info/METADATA" = "Metadata-Version: 2.1`nName: lzfse`nVersion: 0.4.2`nSummary: placeholder stub (no LZFSE implementation)`n"
        "lzfse-0.4.2.dist-info/WHEEL" = "Wheel-Version: 1.0`nGenerator: hand`nRoot-Is-Purelib: true`nTag: py3-none-any`n"
        "lzfse-0.4.2.dist-info/RECORD" = "lzfse/__init__.py,,`nlzfse-0.4.2.dist-info/METADATA,,`nlzfse-0.4.2.dist-info/WHEEL,,`nlzfse-0.4.2.dist-info/RECORD,,`n"
    }
    if (Test-Path $path) { Remove-Item $path -Force }
    $z = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($k in $files.Keys) {
            $e = $z.CreateEntry($k)
            $w = New-Object IO.StreamWriter($e.Open(), (New-Object Text.UTF8Encoding($false)))
            $w.Write($files[$k]); $w.Dispose()
        }
    } finally { $z.Dispose() }
}

Step "找资源包"
$PckDir = $null
foreach ($c in @($Pck, (Join-Path $Here "pck"), "C:\pck", (Join-Path $Downloads "pck"))) {
    if ($c -and (Test-Path (Join-Path $c "resource\common_assets.pck"))) { $PckDir = $c; break }
}
if (-not $PckDir) { Fail "没找到资源包目录 (要有 resource\common_assets.pck)。放进 C:\pck 或本目录\pck, 或用 -Pck 指定" }
# 要推的包: resource\*.pck 与 mod\*.pck (相对路径 resource/xxx.pck、mod/xxx.pck 也是它们在应用里的位置)
$files = @()
foreach ($d in "resource", "mod") {
    $dir = Join-Path $PckDir $d
    if (-not (Test-Path $dir)) { continue }
    foreach ($item in (Get-ChildItem $dir -Filter "*.pck" | Sort-Object Name)) {
        if ($Only.Count -eq 0 -or $Only -contains $item.BaseName) { $files += $item.FullName }
    }
}
Write-Host "目录: $PckDir"
$files | ForEach-Object { Write-Host ("  {0}/{1}  {2:N0} MB" -f (Split-Path (Split-Path $_) -Leaf), (Split-Path $_ -Leaf), ((Get-Item $_).Length / 1MB)) }

if (-not (Test-Path $Pmd)) {
    Step "安装 pymobiledevice3 (只第一次)"
    $py = (Get-Command python -ErrorAction SilentlyContinue), (Get-Command py -ErrorAction SilentlyContinue) | Where-Object { $_ } | Select-Object -First 1
    if (-not $py) { Fail "没找到 Python。去 https://www.python.org/downloads/ 装 3.9 以上, 安装时勾 'Add python.exe to PATH', 装完重开本脚本" }
    if ((Run $py.Source -m venv $Venv) -ne 0) { Fail "建 Python 环境失败" }
    $vpy = Join-Path $Venv "Scripts\python.exe"
    Write-Host ("Python: " + (& $vpy --version 2>&1))
    # 国内镜像优先 (官方 PyPI 超时严重), 依次: 清华 (实测最快) -> 阿里云 (原淘宝源) -> 官方
    $mirrors = @("https://pypi.tuna.tsinghua.edu.cn/simple", "https://mirrors.aliyun.com/pypi/simple/", "https://pypi.org/simple")
    # 先装占位 lzfse: pymobiledevice3 -> pyimg4 -> lzfse, Windows + Python 3.13 没有编译好的包, 现场编译要 Visual C++; 推文件用不到它
    $stub = Join-Path $Here "lzfse-0.4.2-py3-none-any.whl"
    if (-not (Test-Path $stub)) { New-LzfseStub $stub }   # 文件没拷过来时自己生成, 只靠本脚本也能跑
    if ((Run $vpy -m pip install --no-index $stub) -ne 0) { Fail "装占位 lzfse 失败 (缺少 $stub ?)" }
    $ok = $false
    foreach ($m in $mirrors) {
        Write-Host "pip 源: $m"
        if ((Run $vpy -m pip install --prefer-binary --default-timeout 60 -i $m pymobiledevice3) -eq 0) { $ok = $true; break }
    }
    if (-not $ok) { Fail "pip 安装 pymobiledevice3 失败, 上面最后几行红字是原因 (三个源都试过了: 网络不通可挂代理)" }
}

Step "找应用"
$prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
$json = (& $Pmd apps list --type User 2>$null | Out-String)
$ErrorActionPreference = $prev
if (-not $json.Trim()) { Fail "读不到设备上的应用: iPad 连好线了吗? 点过「信任」了吗? 装了 iTunes 吗?" }
# 不用 ConvertFrom-Json: PowerShell 5.1 不分大小写, 遇到应用信息里 BUILD_ID / build_id 这种只差大小写的键会报"重复的键"。
# 顶层键就是包名, 后面跟冒号 (值里的 CFBundleIdentifier 后面跟逗号, 不会误中), 直接按名字找
$bid = $null
$hit = [regex]::Match($json, '"([A-Za-z0-9._-]*swordmanhd[A-Za-z0-9._-]*)"\s*:', "IgnoreCase")
if ($hit.Success) { $bid = $hit.Groups[1].Value }
if (-not $bid) { Fail "设备上没找到「天地劫」(包名含 swordmanhd)。先用 install_ios.bat 装好应用" }
Write-Host "应用: $bid"

Step "推送 (每个文件几分钟, 别拔线)"
# house_arrest 的根目录因系统版本而异 (整个容器 / 只有 Documents), 路径写错会报 AFC FILE_OPEN status 10 (权限被拒): 依次试, 哪种能写就记住用它
#   A 整个容器 + /Documents/文件   B 只 Documents + /文件   C 只 Documents + 相对路径
$modes = @(
    @{ name = "容器 /Documents/<名>"; docs = $false; fmt = "/Documents/{0}" },
    @{ name = "Documents /<名>"; docs = $true; fmt = "/{0}" },
    @{ name = "Documents 相对路径"; docs = $true; fmt = "{0}" }
)
$mode = $null
foreach ($f in $files) {
    $n = (Split-Path (Split-Path $f) -Leaf) + "/" + (Split-Path $f -Leaf)   # resource/xxx.pck 或 mod/xxx.pck
    Write-Host ("  + {0} ..." -f $n)
    $try = if ($mode) { @($mode) } else { $modes }
    $done = $false
    foreach ($m in $try) {
        $a = @("apps", "push")
        if ($m.docs) { $a += "--documents" }
        $a += @($bid, $f, ($m.fmt -f $n))
        if ($mode -eq $null) { Write-Host ("    试写法: " + $m.name) }
        if ((Run $Pmd @a) -eq 0) { $mode = $m; $done = $true; break }
    }
    if (-not $done) { Fail "推 $n 失败 (三种路径写法都被拒/出错, 见上面 pymobiledevice3 的原文; 检查: iPad 存储空间够吗? 约需 2GB; 线拔了吗? 应用是不是开着? 应用是用开发者证书装的吗?)" }
}
Write-Host "`n完成。把 iPad 上的「天地劫」从后台划掉再重新打开。" -ForegroundColor Green

# iOS 版打包 (iPhone / iPad, 自用)

能在 **Linux/Windows/macOS 上导出 iOS 的 Xcode 工程**, 在 macOS (自己的 Mac 或 GitHub 的云 Mac) 上编出**未签名的 IPA**,
再用自签工具以你自己的 Apple ID 签名装到 iPhone/iPad。**编译 iOS 必须有 Apple 的 Xcode (只有 macOS 有)**, 所以编译这一步离不开 Mac, 但那台 Mac 不必是你自己的。
**已在真机验证可用** (Windows 一键签名装机 + 推资源包整条流程)。不懂编程的玩家按 [安装与运行](../安装与运行.md#iphone--ipad-自己签名安装) 操作即可。

原版素材有版权: IPA 里**不含**任何原版资源, 资源包 (`resource/` 与 `mod/` 文件夹里的 .pck, 约 1.5~2GB) 由玩家用 资源生成工具 从自己的原版生成, 装好后拷进应用的文件夹。

## 流程

1. **导出 Xcode 工程** (任何系统): `python3 tools/platform/build_ios.py` → 工程放在 `dist/ios/xcode/` (工程 + 引擎库 + pck), 成品是 `dist/ios/SwordmanHD-xcode.zip` (约 110MB); `dist/ios/` 顶层只放成品 (xcode.zip、IPA)。
   需要 Godot 4.7.2 + 同版本导出模板 (含 `ios.zip`, 官方 `.tpz`)。
2. **编译成未签名 IPA**, 三选一:
   - 自己的 Mac: `python3 tools/platform/build_ios.py --ipa` (要装 Xcode), 得 `dist/ios/SwordmanHD-unsigned.ipa`; 或把 xcode 压缩包拷过去用 Xcode 打开 `SwordmanHD.xcodeproj` 直接 Run 到连着的 iPhone/iPad。
   - 没有 Mac: 在 GitHub 的 Actions 里手动运行 "iOS (unsigned IPA)" (`.github/workflows/ios.yml`, 用 GitHub 的 macOS 机器编译, 免费额度够用), 下载产物 `SwordmanHD-unsigned-ipa`。仓库里只有代码, 没有原版资源。
   - 借/租一台 Mac (如 MacinCloud 按小时租)。
3. **签名并装机**: 用 Sideloader / Sideloadly / AltStore 这类自签工具 (Linux、Windows、macOS 都有), 用你的 Apple ID 给 IPA 签名, USB 或同一 Wi-Fi 装到 iPhone/iPad。
   - 免费 Apple ID: 证书只有 **7 天**, 到期要重签 (AltStore 在同一 Wi-Fi 下能自动续); 同一账号同时最多 3 个自签 App。
   - 付费开发者账号 (99 美元/年): 证书一年, 也能用 TestFlight。
   - 工程里的 Team ID 是占位值 `0000000000`, 自签工具会换成你自己的。
4. **放资源包**: 装好后第一次启动会提示缺资源包并写出路径。把 `resource` 文件夹 (有 mod 就连 `mod` 文件夹) 整个拷进应用的文件夹 (保持 `resource/common_assets.pck` 这样的层级):
   - iPhone/iPad 的「文件」App → 我的 iPhone(iPad) → 天地劫 (导出时开了文件共享), 或
   - 电脑上 Finder (macOS) / iTunes (Windows) → 设备 → 文件共享 → 天地劫。
   游戏从应用的 Documents 目录挂载它们 (`ResPacks.ios_pack_dir`)。

### 家里 Windows 电脑一键签名安装 (开发机远程时用)

开发机不连 iPad 时, 在连着 iPad 的 Windows 电脑上用 `tools/ios_win/`: 把这个目录拷过去 (或整个仓库), IPA 放进同目录或「下载」文件夹 (GitHub Actions 下载的 `SwordmanHD-unsigned-ipa.zip` 也认), 双击 `install_ios.bat`。
它会: 找 IPA (也可拖到 bat 上, 或 `-From 用户@开发机:<仓库>/dist/ios/SwordmanHD-unsigned.ipa` 用 scp 拉) → 检查 iTunes 的 Apple 设备服务 (没有就用 winget 装) → 下载 plumesign (Plume Impactor 的命令行, 单文件) 到 `bin\` (校验 SHA256) → `account login` 登录一次 → `sign --apple-id --register-and-install` 签名装机 (Sideloader 的 Windows 版缺 plist.dll, 已弃用)。
Apple ID 密码和二次验证码在窗口里输入, 不落盘。
iPad 端: 数据线连好、点「信任此电脑」; **开发者模式的开关装完才会出现** (iOS/iPadOS 16+), 装完后依次: 设置 → 隐私与安全性 → 开发者模式 → 打开并重启 → 设置 → 通用 → VPN 与设备管理 → 信任证书 → 打开应用。7 天到期重跑即可。
**资源包不在 `install_ios.bat` 里**: 它只负责签名装机, 装完会提示下一步。资源包用下面的 `push_packs.bat` 推, 或用「文件」App / Finder 拷; 想装完直接能玩, 给 IPA 做**整包** (见本页「整包」一节, `tools/platform/bundle_ipa.py`)。完整步骤见 [手机安装与资源包.md](../手机安装与资源包.md)。
**登录**: 第一次输邮箱+密码+验证码, 之后记在 `bin\apple_id.txt` (只记邮箱) 不再问; 换账号或提示凭据失效加 `-Relogin`。
**一键推资源包**: 双击 `tools/ios_win/push_packs.bat`, 不用 iTunes。包放 `C:\pck` (或 `pck` 子目录、`-Pck 目录`); 第一次自动在 `bin\pmd` 建 Python 环境装 pymobiledevice3 (要先装 Python 3.9+); 它找到应用 (包名含 swordmanhd) 后用 `apps push --documents` 把 `.pck` 推进应用的 Documents。`-Only original,content` 只推必需的两个先试玩。重装 IPA 后如果包丢了, 再双击一次。


## 整包 (资源直接打进 IPA, 装完就能玩; 只自用)

iPhone / iPad 上往「文件」App 拷资源比较麻烦, 可以给编好的未签名 IPA 加上预制资源包, 出「整包」:

```bash
python3 tools/platform/build_ios.py --ipa --bundle                         # macOS: 编 IPA 后直接打整包
python3 tools/platform/bundle_ipa.py dist/ios/SwordmanHD-unsigned.ipa      # 已经有 IPA (macOS 编的或 GitHub Actions ios.yml 出的): 任何系统都能做
python3 tools/platform/bundle_ipa.py <ipa> --edition classic               # 原版画质 (约 0.8 GB, 缺省 hd 约 1.4 GB)
```

- 资源从仓库根的 `pkgs/` 取 (整个目录被 `.gitignore` 忽略, 资源不入库); `--pkgs <目录>` 指定别处, `--no-mod` 不带 mod 包。
- **只自用, 不要公开发布** (含原作衍生资源)。
- 做法: IPA 就是 zip, 把 `bundled/{manifest.json, resource/*.pck, mod/*.pck}` 放进 `Payload/<名>.app/` 里; 之后 Sideloader / Sideloadly / AltStore 签名时一起封进签名。运行时 `ResPacks.bundled_dir()` 读 `.app` 里的 `bundled/` 并挂载 (`game/engine/core/res_packs.gd`)。
- 包大 (GB 级), 自签工具上传要等一会。

## 工程设置 (`game/export_presets.cfg` 的 "iOS" 预设)

- 包名 `com.tdj.swordmanhd` (与 Android、代码里一致), 最低 iOS 14.0, arm64, 横屏 (iPhone 与 iPad 都是), 高分屏。
- `application/export_project_only=true`: Godot 只出工程, 编译由 `build_ios.py --ipa` / Xcode 做 (Linux 上 Godot 也只能出工程)。
- 文件共享打开 (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`), 资源包靠它拷进去。
- 应用图标 `game/assets/app_icon.png` (1024x1024, 无透明; `python3 tools/platform/make_app_icon.py` 生成, 不含原版素材)。
- 触屏操作盘 (摇杆 + 确认/取消/查看/菜单) 与 Android 通用,。

## 已知的待办

- 仍待细调 (帧率、内存: 贴图缓存预算 `--tex-budget` 缺省 768MB, 手机/平板可能要降; 运行时 6 倍人物贴图着色器速度; 高清视频解码)。
- 没做: App Store / TestFlight 发布 (要付费账号、隐私清单、发布签名)、iOS 上的 Play Asset Delivery 类按需资源。

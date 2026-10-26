# Android 版打包

能出 Android 包 (arm64 手机, minSdk 24, 横屏)。**APK 只含引擎和手写内容 (约 40MB), 原版资源包 (约 1.5GB) 另放在手机上**:
原版素材有版权, 仓库和 APK 都不带, 玩家用 资源生成工具 从自己的原版生成资源包, 自己装到自己的手机 (带原版素材的包不能分发)。

## 一次性准备

```bash
python3 tools/platform/setup_android.py          # 装 JDK 17 + Android SDK 最小集 + 调试签名到 tools/android/ (约 1~2GB, 已 gitignore)
python3 tools/platform/setup_android.py --check  # 只检查环境齐不齐
```
- 已经装过的目录可复用: `--home ~/Android` 或环境变量 `TDJ_ANDROID_HOME` (已装好的部分跳过)。
- 同时幂等地写 Godot 编辑器设置里的 `export/android/*` 五项 (导出 Android 只认编辑器设置, 环境变量不起作用), 改之前备份 `.bak-时间戳`; 不想改用 `--no-godot-config`。
- 下载走直连、忽略代理环境变量, 支持断点续传。
- 还需要: Godot 4.7.2 + **同版本导出模板** (官方 `Godot_v4.7.2-stable_export_templates.tpz`, 含 `android_debug.apk`), 见 `docs/打包/Windows.md` 的装法。
- 版本与 Godot 导出模板一致 (build-tools 36.1.0、platform 36、JDK 17, 见 `setup_android.py` 的 `SDK_VERSIONS`); 升级 Godot 时对一下它的 `android_source.zip/config.gradle`。

## 出包

```bash
python3 tools/platform/build_android.py                # dist/android/SwordmanHD.apk (dist/packs/ 里有资源包就一并推到手机)
python3 tools/platform/build_android.py --install      # 出包后 adb 装到手机并推资源包 (手机开 USB 调试并连着)
python3 tools/platform/build_android.py --push-packs   # 只推资源包 (APK 已装过)
python3 tools/platform/build_android.py --no-packs      # 只出 APK, 不推资源包
```
资源包是 `resource/` 与 `mod/` 里的 `.pck` (布局见 [资源包](资源包.md)), 放进 `dist/packs/`。

## 整包 (资源直接打进 APK, 装完就能玩; 只自用)

手机上装 APK 再拷资源比较麻烦, 可以出「整包」: 把预制的资源包一起打进 APK, 装完直接玩。

```bash
python3 tools/platform/build_android.py --bundle                    # 高清画质, 约 1.3 GB: dist/android/SwordmanHD-bundled-hd.apk
python3 tools/platform/build_android.py --bundle --edition classic  # 原版画质, 约 0.8 GB
```

- **资源从哪来**: 仓库根的 `pkgs/` (`pkgs/resource/*.pck`、`pkgs/mod/*.pck`, 就是资源包的两个文件夹)。**整个 `pkgs/` 被 `.gitignore` 忽略, 资源不入库**; `--pkgs <目录>` 可以指到别处, `--no-mod` 不带港漫头像等 mod 包。
- **只自用, 不要公开发布**: 整包含原作衍生资源, 不能放进 Releases / 网盘 / 任何公开的地方 (README 声明)。公开发布的包仍然只含程序。
- **做法**: 在导出的 APK 里加 `assets/bundled/{manifest.json, resource/*.pck, mod/*.pck}` (包不压缩), 去掉旧签名, `zipalign` 后用调试签名重新签 (`tools/platform/bundle_pack.py`)。
- **运行时** (`game/engine/core/res_packs.gd`): 启动时读 `res://bundled/manifest.json`, 把里面的包**原地挂载** (APK 的 assets 就是 `res://`, 不占两份空间); 原地挂不上就拷到应用目录 `user://bundled/` 再挂 (只第一次拷, 手机上占两份空间)。整包里的包先挂, 之后外部目录 (`adb push` 放的) 里同名的包照旧覆盖它们, 所以整包也能用 adb 更新单个包。
- **限制**: APK 体积到 GB 级, 有的手机 / 安装器装不上; 签名是调试签名, 换密钥需卸载重装。桌面上用 `--bundled=<目录>` 模拟验证过清单和挂载顺序; 整包 APK 的签名、对齐、资源包存放方式 (不压缩) 用 `apksigner` / `zipalign` 验证过。

## Windows 一键安装 / 推资源包 (手机连在另一台 Windows 电脑上时)

`build_android.py` 出 APK 时会把 `install_android.bat` + `android_install.ps1` 一起放进 `dist/android/`, 把整个 `dist/android/` 拷过去 (资源包放它里面的 `pck\resource`、`pck\mod` 最省事) 就行; 或者手动把 `tools/android_win/` 拷过去, APK (`SwordmanHD.apk`) 放进同目录或「下载」, `resource`、`mod` 两个文件夹放进 `C:\pck`, 手机开 USB 调试并连线, 双击 `install_android.bat`: 自动下 Google 官方 platform-tools (adb) → `adb install -r` 覆盖安装 → 把资源包推到 `/sdcard/Android/data/com.tdj.swordmanhd/files/` (手机上已有且大小一致的包自动跳过)。`-SkipApk` 只推资源包, `-Pck 目录` 指定包目录。**没在 Windows 和真机上跑过。**

## 签名

Android **必须签名才能安装** (没签名的 APK 手机直接拒绝); 它只检查「有没有签、签得对不对」, 不检查「是谁签的」。

### 项目的发布密钥 (GitHub 上自动打出来的 APK 用它)

- 发布密钥是一把 RSA 4096 的 PKCS12 密钥库 `release.keystore`, 别名 `swordmanhd`, 有效 100 年。**它不入库**: 放在仓库**外面** (例如与仓库同级的 `SwordmanHD-keys/`), 另有 `android.env` 存别名和密码; `.gitignore` 里的 `*.keystore`、`*.jks`、`android.env` 再兜一层。
- **请备份这个目录** (密码管理器 / 加密网盘)。丢了就没法再用同一个签名发更新, 玩家只能先卸载再装 (存档会丢); 泄露了别人就能冒充你发更新, 所以也别发给别人、别贴到聊天里。
- **验证 APK 是不是本项目发的**: 项目发布 APK 的证书 SHA-256 指纹是
  `9fb46d0f0b2e5d614415f3a501c3adac3e48e5e8ac71b9ed00bd6185201aa73c`
  (`apksigner verify --print-certs SwordmanHD.apk` 里的 `certificate SHA-256 digest` 应该是它)。指纹不一样 = 不是本项目的发布签名 (比如玩家自己打的整包)。

**配到 GitHub** (仓库建好之后, 一次): 在已登录 `gh` 的终端运行

```bash
tools/release/set_android_secrets.sh <owner/repo> <密钥目录>      # 例: ... zmnqaz/SwordmanHD ../SwordmanHD-keys
```

它把密钥库转 base64 存进 Secrets `ANDROID_KEYSTORE_BASE64`、密码存 `ANDROID_KEYSTORE_PASSWORD`、别名存 `ANDROID_KEY_ALIAS` (Secrets 只能被工作流使用, 页面上读不回来, 也不会给 fork 来的 PR)。之后 `.github/workflows/build.yml` 的 android 任务检测到它们就用 `--release` 签名, 打出来的 APK 永远是同一个签名, 新版能覆盖安装旧版。**没配的话** 工作流退回临时调试签名 (密钥放在云端缓存里, 缓存被清或脚本一改就换一把) 并打出警告「新版不能覆盖安装旧版」。

**本机用发布密钥打包**:

```bash
source ../SwordmanHD-keys/android.env        # 设 GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
python3 tools/platform/build_android.py --release
```

不加 `--release` 用 `setup_android.py` 生成的**调试签名** (用户名 `androiddebugkey`, 密码 `android`, 公开已知), 只适合自己装机测试。
**换签名必须先卸载** (调试签名的包和发布签名的包不能互相覆盖安装, 存档和资源包会被一起删)。

### 自己把 APK 和资源打到一起, 怎么签名

整包 (`build_android.py --bundle`) 或对**下载来的 APK** 用 `tools/platform/bundle_apk.py` 加资源, 往 APK 里加了文件后原来的签名就失效了, **必须重新签名**, 用**你自己的密钥**就行, 用不着也拿不到项目的发布密钥:

```bash
python3 tools/platform/bundle_apk.py SwordmanHD.apk --pkgs <资源包目录>      # 资源包目录里是 resource/ 与 mod/
```

- 第一次运行会**自动生成你的个人密钥** `~/.swordmanhd/bundle.keystore` (密码在同目录 `.pass` 文件里), 以后一直用它: 你以后更新整包可以直接覆盖安装。**这个目录请自己备份**, 丢了以后更新整包要先卸载。
- 想用自己已有的密钥: `--keystore <文件> --alias <别名> --ks-pass <密码>` (或环境变量 `BUNDLE_KS_PASS`)。
- 签完的整包和 GitHub 上的发布 APK **签名不同, 不能互相覆盖安装**: 手机上装着发布版的话, 先卸载 (存档会丢, 先备份) 再装整包。
- 需要 JDK 17 + Android build-tools (`zipalign` / `apksigner` / `keytool`): `python3 tools/platform/setup_android.py` 一次性装好, 或自己装好加进 PATH。
- 手动做也行 (不用我们的脚本): 用任何 zip 工具把资源包以**不压缩**方式加进 APK 的 `assets/bundled/` (含 `manifest.json`, 格式见 `tools/platform/bundle_pack.py`), 删掉 `META-INF/`, 然后
  ```bash
  zipalign -f -p 4 in.apk aligned.apk
  keytool -genkeypair -keystore my.keystore -alias me -keyalg RSA -keysize 2048 -validity 36500     # 只第一次
  apksigner sign --ks my.keystore --ks-key-alias me --out out.apk aligned.apk
  ```
- 整包只能自己用, 不能公开发布 (含原作衍生资源)。

## 手机上的位置

- 游戏从 `/sdcard/Android/data/com.tdj.swordmanhd/files/` 挂载资源包 (`ResPacks.android_pack_dir`); 缺包时屏幕上直接提示这个路径。
- Android 11 以后手机自带的文件管理器常常不能写 `Android/data`, 用 `adb push` (`--install` / `--push-packs` 就是它)。
- 存档和设置在应用沙盒 (`user://`), 不用管。
- 返回键 = 取消 (不退出); 横屏锁定 (`display/window/handheld/orientation=4` 传感器横屏, 只在两个横向之间翻转; 曾误设成 6 = 含竖屏, 竖屏进游戏再横竖切换显示会被拉伸、触摸不准, 2026-10-25 魅族 20 Pro 反馈后改, `tools/tests/test_project_orientation.py` 守着); 触屏操作盘见 3 (摇杆 + 确认/取消/查看/菜单)。

## 现状与待办

- 已验证: 导出的 debug APK 包信息/签名/arm64 库齐全 (`aapt2 dump badging`、`apksigner verify`); 桌面 `--touch` 模式下操作盘截图核对。
- 手机上的帧率、内存 (贴图缓存预算 `--tex-budget` 缺省 768MB, 手机可能要降)、运行时 6 倍人物贴图着色器的速度、高清视频解码、触控手感, 欢迎带着机型反馈。
- 应用图标 `game/assets/app_icon.png` (`python3 tools/platform/make_app_icon.py` 生成, 与 iOS 共用)。
- Google Play 的资源分发 (Play Asset Delivery) 没做。

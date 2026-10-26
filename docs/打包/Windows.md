# Windows 版打包

exe 内嵌主 pck（脚本、场景、字体、手写内容包），资源放在 exe 旁的资源包里（`resource/` 文件夹里的必备包，另有可选的 `mod/` 文件夹，启动时 `ResPacks` 挂载）。`Assets` 在导出版里把资源根设为 exe 所在目录（见 `game/engine/render/assets.gd`）。

## 打包

Windows 原生也可打包: `python tools\build_windows.py ...`（参数同下; 与 .sh 同一实现; Export templates 目录为 `%APPDATA%\Godot\export_templates\<版本>\`, 详见 `docs/Windows开发.md`）。

```bash
tools/build_windows.sh                    # dist/windows/SwordmanHD/ (资源包硬链接自 dist/packs/)
tools/build_windows.sh --zip              # 另打 dist/windows/SwordmanHD-win64.7z
tools/build_windows.sh --zip --split=2g   # 7z 分卷 (.7z.001, .002 ...)
tools/build_windows.sh --linux            # Linux 版 dist/linux/SwordmanHD/
```

前提:
- `tools/godot/godot` 4.7.2 与同版本 export templates, 装在 `~/.local/share/godot/export_templates/4.7.2.stable/`
  (官方 `Godot_v4.7.2-stable_export_templates.tpz`, GitHub releases 下载后解压 templates/ 到该目录)。想要导出包里也有图片压缩（BC7），再编自制模板，见下。
- 资源包 (可选): 放进 `dist/packs/` (`resource/`、`mod/`); 没有就加 `--engine-only` 只出引擎。
- 图标: 自制的 `game/assets/app_icon.png` 会被转成多尺寸 `game/assets/icon.ico` (不入库)。

导出预设在 `game/export_presets.cfg` 的「Windows Desktop」: x86_64, 主 pck 嵌入 exe, 附带 `SwordmanHD.console.exe` (看日志)。
脚本末尾有「必带清单校验」: 按 fonts.json 逐个检查字体文件与许可文本、各资源包是否齐全, 缺了直接报错; 以后加字体只改 fonts.json 即可自动纳入校验。
许可文本（英文）放在包内 `licenses/`，包根目录只有 `README.txt`（英文使用说明）。

## 目录结构与体积

```
SwordmanHD/
  SwordmanHD.exe           94 MB   Godot 运行时 + 内嵌主 pck (自制模板; 官方模板约 105 MB)
  SwordmanHD.console.exe   27 KB   控制台版, 显示日志
  resource/                必备资源 (common_*.pck 必放; hd_* / classic_* 画质二选一)
  mod/                     可选 mod (face_hk.pck 等)
  BUILD.json  README.txt  licenses/
```

各 pck 的内容与大小见 [资源包.md](资源包.md), 合计约 2.04 GB。
打包用到的 `tools/godot`、`icon.ico` 都不入库: 用 `tools/dev_env.json` / 环境变量指到位置, 或放在对应的默认目录 (Windows 见 [Windows 开发](../Windows开发.md) §3)。

## 资源包只存一份

`resource/*.pck` 与 `mod/*.pck` 全平台只打一份放 `dist/packs/`（约 2GB）。`tools/build_windows.py` 打完后用**硬链接**放进 `dist/windows/SwordmanHD/`（不能硬链接时才复制; `--edition=hd` 只发高清版: 不带 `classic_images` / `classic_movies`，`--edition=classic` 反之），Android 推手机与 iOS 拷进应用也从 `dist/packs/` 取。
所以 `dist/` 总共：`packs/`（一份资源）+ 各平台的 exe / apk / ipa（各一份，几十到一百多 MB）。要整包拷走或打 7z 时是真实文件。

## 自制导出模板

官方 Windows release 模板不带图片压缩器，贴图 BC7 压缩在导出包里用不了。先 `tools/platform/build_template_windows.sh`（下载 Godot 源码和 llvm-mingw，约 5 分钟）编出 `.work/templates/windows_release_x86_64.exe`，再 `tools/build_windows.sh`，脚本检测到就自动用（打印「用自制模板」）。没编模板也能打包，只是不压缩（显存约 4 倍）。自制模板不含 ANGLE / D3D12 / AccessKit（游戏只用 gl_compatibility；`--rendering-driver opengl3_angle` 兜底在自制包里不可用）。

## 运行时缓存

游戏第一次进某个场景时会把像素画贴图烘焙并压缩，结果存在 `%APPDATA%\SwordmanHD\hq_cache\`（Linux `~/.local/share/SwordmanHD/hq_cache/`），默认上限 3GB，超了自动删最旧的；之后读缓存不再烘焙。
删掉这个目录只是让游戏重新烘焙一遍，没有别的影响。`--hq-cache-mb=0` 关闭磁盘缓存，`--hq-codec=off` 关闭压缩。说明见 `game/engine/render/hq/README.md`。

## 在 Windows 上运行

1. 把整个 `SwordmanHD/` 文件夹 (或 7z 解压后) 拷到 Windows, 路径可含中文。
2. 双击 `SwordmanHD.exe`。窗口默认 1280x800 (4 倍); 人物等像素画贴图运行时生成 6 倍, 任何窗口大小都清晰。
3. 存档与设置: `%APPDATA%\SwordmanHD\` (Linux 开发版: `~/.local/share/SwordmanHD/`)。
   首次启动会把旧目录 `%APPDATA%\Godot\app_userdata\天地劫：神魔至尊傳 復刻\` 的存档/设置复制过来 (`game/scripts/user_dir_migrate.gd`)。
   存档原子写入, 旁边的 `.bak` 是上一版 (正式文件损坏时自动改读), 带 "version" 按版本迁移 (`game/engine/core/save_file.gd`)。
   想沿用 Linux 上的存档, 把 `~/.local/share/SwordmanHD/save*.json` 拷到上面目录即可。
4. 自动测试参数在导出版同样可用:
   `SwordmanHD.console.exe --fixed-fps 25 -- --scene=stage1 --skip-movies --shot=60:C:/tmp/a.png --quit=61`。
   GUI 版 `SwordmanHD.exe` 同样接受这些参数。

渲染器为 gl_compatibility (OpenGL 3.3)。显卡驱动不支持 OpenGL 时可用 `SwordmanHD.exe --rendering-driver opengl3_angle`
(导出时 ANGLE 设为自动, 模板自带)。

## 已知问题

- 过场动画用转好的 .ogv; 原版 Bink/mp4 不带。Theora 解码在 CPU, 慢机器上可能掉帧。
- `--sysfont` (系统明体) 读 Linux 字体路径, Windows 上无效 (默认字体不受影响)。
- 未签名 exe, Windows SmartScreen 首次运行会提示「未知发布者」, 选「仍要运行」。

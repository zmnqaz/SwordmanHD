# tools/ 说明

构建、打包、检查用的脚本。Python 脚本都能在 Windows / macOS / Linux 上跑 (`.sh` 是薄封装, 转调同名 `.py`)。
各脚本开头写两行 `import _boot` 就能互相按模块名 import (见 `_boot.py`)。

## 入口

| 脚本 | 做什么 |
|---|---|
| `ci.py` (`ci.sh`) | 本地与 CI 共用的检查入口。`fast`: Godot 导入 + 无头测试 + 内容包校验 + 文本 / 布局 / 文档检查 + Python 测试; `full`: 再加慢测试组。步骤、环境变量见文件头 |
| `run_game.py` (`run_game.sh`) | 运行游戏; `--` 之前的参数给 Godot, 之后的给游戏 (测试参数见 `game/engine/core/debug_args.gd`) |
| `paths.py` | Godot / Python 等路径的统一解析 (环境变量 > `tools/dev_env.json` > 默认位置); `python3 tools/paths.py` 打印并检查 |
| `ci_install_godot.sh` | CI 里下载安装 Godot 4.7.2 (和导出模板) |
| `build_windows.py` (`.sh`) | 导出桌面版 (Windows; `--linux` / `--mac`) 并组装发布目录、校验必带文件、打 7z / tar.xz / zip; `--engine-only` 只出引擎 |

## platform/ — 各平台构建

| 脚本 | 做什么 |
|---|---|
| `build_android.py` | 导出 Android APK, 可选 `--install` 装到手机; `--bundle` 出整包, `--release` 用自己的密钥签名 |
| `setup_android.py` | 一次性装好 Android 构建环境 (JDK 17 + SDK + 调试签名) |
| `apk_sign.py` | APK 的 zipalign + apksigner + 密钥管理 |
| `bundle_pack.py` / `bundle_apk.py` / `bundle_ipa.py` | 往 APK / IPA 里加资源包 (整包, 自用) |
| `build_ios.py` | 生成 Xcode 工程; 在 macOS 上编未签名 IPA |
| `build_template_windows.sh` | 自编 Windows 导出模板 (带图片压缩) |
| `make_app_icon.py` / `make_ico.py` | 生成应用图标 / `.ico` |

`android_win/`、`ios_win/`: Windows 上一键装 APK / 签名装 IPA / 推资源包的 bat + PowerShell 脚本。

## checks/ — 检查

| 脚本 | 检查什么 |
|---|---|
| `content_schema.py` | 内容包结构与 `.evs` 脚本 (`--pack <目录>` 校验自己的包, `--strict` 更严) |
| `check_ui_text.py` | 代码里不能写死玩家可见的中文 (走 `UiStrings`, 白名单 `ui_text_allow.txt`) |
| `check_docs.py` | 文档断链 / 未被索引 / 生成的文档是否过期 |
| `layout_stats.py` | 界面布局表统计与基线 |
| `check_eol.py` | 换行符 (仓库一律 LF) |
| `no_abs_paths.py` | 代码里不许写死本机路径 |

## 其他

| 脚本 | 做什么 |
|---|---|
| `assets/compile_events.py` | `.evs` 剧情脚本的编译器与指令表定义 (指令表导出到 `game/engine/script/evs_ops.json`) |
| `docgen/gen_evs_doc.py` / `docgen/reserved_vars.py` | 由指令表 / 保留变量定义生成 `docs/` 里对应的文档 |
| `legal/spdx_headers.py` | 检查源文件第一行的 SPDX 许可头 |
| `release/pack_pck.gd` / `unpack_pck.gd` | 把目录打成 `.pck` / 把 `.pck` 解开 (`godot --headless --script ...`) |
| `release/godot_licenses.gd` | 汇总 Godot 自带的第三方许可文本 |
| `hooks/` | 可选的 git hook (`pre-commit`、`pre-push`) |
| `tests/` | 上述脚本的 Python 单元测试 (`ci.py` 的 `python-tests` 步骤跑它们) |

# Windows 上开发与打包

目标: 在 Windows 上不装 WSL, 用 PowerShell 或 cmd 完成开发、测试、运行、打包。遇到问题请直接修脚本并更新本文。

## 1. 需要准备的东西

| 项 | 版本 / 说明 |
|---|---|
| Git for Windows | 含 Git Bash (`tools/hooks/*`、`tools/*.sh` 是 bash 脚本, 用它运行) |
| Python | 3.10+, 安装时勾选 Add to PATH |
| Godot | **4.7.2 标准版** (不是 .NET 版), `Godot_v4.7.2-stable_win64.exe.zip`, 解压后有 `…_win64.exe` 与 `…_win64_console.exe` |
| Export templates (仅打包) | 同版本的 `Godot_v4.7.2-stable_export_templates.tpz`: 编辑器里 项目 > 导出 > 管理导出模板 > 从文件安装; 或解压 `templates/` 到 `%APPDATA%\Godot\export_templates\4.7.2.stable\` |
| 7-Zip (仅出 7z 包) | 没有会退回 .zip |

## 2. 环境搭建

```powershell
# 1. Git 设置 (全局, 一次性)
git config --global core.longpaths true
git config --global core.autocrlf false      # 仓库用 .gitattributes 固定 LF, 不要让 git 转换

# 2. 取代码 (路径用英文、无空格的短路径, 避开 OneDrive / 网盘同步目录)
git clone https://github.com/zmnqaz/SwordmanHD.git D:\work\swordmanhd
cd D:\work\swordmanhd

# 3. Python 依赖
python -m pip install -r tools\requirements-ci.txt
$env:PYTHONUTF8 = "1"    # 建议永久设置 (系统环境变量), 避免中文输出 / 文件名乱码

# 4. 告诉脚本 Godot 在哪 (见 §3)
copy tools\dev_env.example.json tools\dev_env.json
notepad tools\dev_env.json
python tools\paths.py          # 检查: 每一项应为 OK

# 5. 首次导入并跑检查 (命令行一律用 console 版 Godot: GUI 版不会把输出写到管道)
python tools\ci.py fast
```

cmd 里等价写法: `set PYTHONUTF8=1`、`copy tools\dev_env.example.json tools\dev_env.json`。

## 3. 路径配置

Python 工具 (`tools/paths.py`) 读同一来源, 优先级: **环境变量 > `tools/dev_env.json` > 默认位置**。

| 项 | 环境变量 | dev_env.json 键 | 默认 |
|---|---|---|---|
| Godot | `TDJ_GODOT` (兼容 `CI_GODOT`) | `godot` | `tools\godot\godot.exe`, 其次 PATH 里的 `godot` |
| Python | `TDJ_PYTHON` | `python` | 当前解释器 |

- `tools/dev_env.json` 不入库 (已 `.gitignore`); 相对路径相对仓库根; 路径用正斜杠 (`D:/tools/godot/…`) 免转义。
- 缺失时脚本会提示「找不到 Godot … 设 TDJ_GODOT 或写 dev_env.json」。`python tools\paths.py` 一次列出所有项的状态。
- 没有资源包也能跑 `ci.py fast`: 依赖资源包的测试自动 SKIP。
- 导出的 Windows 包不读 dev_env.json, 资源包固定在 exe 旁。

## 4. 日常命令

`<godot>` 指 console 版 exe 路径 (配了 dev_env.json 后用 `tools\*.py` 入口就不用写)。

| 目的 | 命令 |
|---|---|
| 检查路径配置 | `python tools\paths.py` |
| 快速检查 | `python tools\ci.py fast` |
| 再加慢测试组 | `python tools\ci.py full` |
| 只跑无头单元测试 | `<godot> --headless --path game --script res://tests/run_tests.gd` (加 `-- 过滤串` 只跑某文件) |
| 刷新类名缓存 | `<godot> --headless --path game --import` |
| 运行游戏 | `python tools\run_game.py` |
| 用 Godot 编辑器打开 | `<GUI 版 godot.exe> --path game --editor` |
| 打包 Windows 版 | `python tools\build_windows.py --engine-only [--zip [--split=2g]]` (说明 [打包/Windows](打包/Windows.md)) |

日志与中间产物放仓库外的临时目录或 `.work/` (已忽略)。`ci.py` 把 `APPDATA` / `LOCALAPPDATA` 指到 `.work\ci\home` 隔离设置与存档, 不会碰你本机真实存档 (游戏正常运行时存档在 `%APPDATA%\SwordmanHD\`)。

## 5. 跨平台入口

| 入口 | 说明 |
|---|---|
| `tools/ci.py` | `ci.sh` 的实现; 步骤、环境变量、退出码 (0 / 1 / 2) 见文件头 |
| `tools/run_game.py` | `run_game.sh` 的实现 |
| `tools/build_windows.py` | `build_windows.sh` 的实现; 硬链接失败退回复制, 没有 7z 退回 zip |
| `tools/paths.py` | 路径与 Godot 解析 (§3) |

对应的 `.sh` 保留为几行薄封装 (找 `python3` / `python` 后转调), Linux / CI 用法不变。

## 6. Git hook (可选)

hook 是 bash 脚本, Git for Windows 会用自带 sh 执行。Windows 不要用 `ln -s` (无权限), 改复制:

```powershell
copy tools\hooks\pre-push .git\hooks\pre-push
```

跳过一次: `$env:SKIP_CI="1"; git push ...`。

## 7. 常见问题

- **中文路径 / 文件名**: Godot 与 Python 都支持, 但控制台编码可能乱码: 设 `PYTHONUTF8=1`, PowerShell 用 `chcp 65001`。`docs/` 下有中文文件名, `git config --global core.quotepath false` 让 git 正常显示。
- **换行**: 仓库入库全是 LF, `.gitattributes` 对 .gd / .json / .py / .sh / .md / .evs 等强制 `eol=lf`, `.editorconfig` 让编辑器保持 LF; `.sh` 变成 CRLF 会报 `\r: command not found`。编辑器别自动转 CRLF。克隆时若 `core.autocrlf=true` (Git for Windows 装机默认), 部分文件仍可能被写成 CRLF: `git config core.autocrlf false` 后用 `git ls-files --eol | findstr w/crlf` 找出来重新 checkout (先提交或 stash 本地修改)。
- **无头输出为空 / 测试「无输出」**: 用了 GUI 版 exe。无头与管道场景一律用 `*_console.exe`。
- **Python 缺省编码**: Godot 的 `OS.execute` 按 ANSI (GBK) 解码, Python 缺省 UTF-8, 两边对不上; 凡 Godot → Python 取中文输出的地方都应走文件或只匹配 ASCII 关键词。
- **显卡驱动 / 画面异常**: 游戏要求 OpenGL 3.3 兼容渲染。打不开或黑屏时更新驱动, 或 `python tools\run_game.py --rendering-driver opengl3_angle` (经 ANGLE / D3D11); 打包版同理 `SwordmanHD.exe --rendering-driver opengl3_angle`。虚拟机 / 远程桌面无 GPU 时只能跑 `--headless` (测试都是 headless, 不受影响)。
- **杀毒软件 / Defender**: 扫描工程缓存会让 clone / 导入慢很多, 也可能误删刚导出的 exe。把仓库、`.work`、`dist` 目录加入排除项。
- **长路径**: `core.longpaths true`, 并在 Windows 启用长路径 (组策略 / 注册表 `LongPathsEnabled=1`)。
- **文件占用**: 测试被杀后残留的 Godot 进程会占用 `.godot` 文件, 任务管理器结束 `godot*.exe` 后重试。
- **出包慢**: `--zip` 在 Windows 上比 Linux 慢很多 (大头是硬链接与压缩, Defender 实时扫描也会拖慢)。没装 7-Zip 时走 zip 兜底。

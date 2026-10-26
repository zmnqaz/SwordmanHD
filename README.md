# SwordmanHD

用 [Godot 4](https://godotengine.org/) 写的 RPG 复刻引擎: 引擎、界面、规则与手写内容在本仓库, 游戏数据与素材以**内容包**和**资源包**的形式放在仓库之外, 一份程序可以在 Windows / macOS / Linux / Android / iPhone / iPad 上运行。
本仓库提供源码、编译打包的方法和二次开发 (做 mod、接入新内容) 所需的资料。

> ⚠️ **声明**
> - 本项目是**非官方、非营利的同人技术项目**, 与相关作品的权利人没有任何关联, 也未获其授权或认可, 仅供个人学习、研究与技术交流。
> - 本仓库只含引擎代码、手写的内容与文档, **不含**任何原作的美术、音乐、视频文件, 也不含原作的数据文件或对白文本; 引擎按原作的数据格式读取使用者自备的资源包。原作的一切权利归其权利人所有。
> - 运行游戏需要使用者**自备合法拥有的原作副本**所对应的资源包 (`.pck`); 资源包不在本仓库中, 也不得上传到本仓库或任何公开平台、再分发或商用。
> - 权利人如有异议, 请通过 [Issues](https://github.com/zmnqaz/SwordmanHD/issues) 联系, 会及时处理。许可与完整声明见文末 [许可](#许可)。

## 仓库里有什么

```
game/                  Godot 4.7.2 工程
  engine/              引擎: 战斗规则、事件脚本虚拟机、界面、渲染、输入、音频 …… (内容无关)
  scripts/             组装层: 启动、场景流转、命令行测试参数
  scenes/ shaders/     场景与着色器
  content/
    remake/            手写内容: 界面布局与文案 (含繁体叠加层)、字体清单、演出定位
    templates/         全新内容包的最小模板 (minimal_game)
    example_mod/       改动包示例: 改数值 + 一整关新关卡
  tests/               无头单元测试 (GDScript)
tools/                 构建、打包、检查脚本 (Python / bash)
docs/                  文档, 入口见 docs/README.md
```

引擎和内容是分开的: 引擎只通过「内容包」(目录里的 JSON + 剧情脚本 `.evs`) 读取数据, 通过「资源包」(`.pck`) 读取图像和声音。要做自己的内容, 不用改引擎代码。

## 快速开始

需要 [Godot 4.7.2](https://godotengine.org/) (标准版, 不是 .NET 版)。

```bash
git clone https://github.com/zmnqaz/SwordmanHD.git && cd SwordmanHD
python3 tools/paths.py                         # 检查 Godot 路径配置 (TDJ_GODOT 或 tools/dev_env.json)
python3 tools/ci.py fast                       # 导入工程 + 全部无头测试 + 各项检查
python3 tools/run_game.py                      # 运行 (没有资源包时, 屏幕上会写出缺什么、该放哪里)
```

Windows 开发见 [Windows开发](docs/Windows开发.md)。

## 运行与操作

安装、启动和常见问题见 [安装与运行](docs/安装与运行.md); 键盘 / 鼠标 / 手柄 / 触屏的按键见 [操作说明](docs/操作说明.md)。

## 资源包

游戏的图像、声音、数据表等素材不在本仓库。引擎启动时从程序旁的 `resource/` (必备) 和 `mod/` (可选) 两个文件夹里挂载 `.pck`,
文件夹结构、各包的角色和挂载规则见 [资源包](docs/打包/资源包.md)。手机怎么放见 [手机安装与资源包](docs/手机安装与资源包.md)。

## 编译与打包

| 目标 | 命令 |
|---|---|
| Windows / Linux / macOS 桌面包 (只含引擎) | `python3 tools/build_windows.py [--linux \| --mac] --engine-only --zip` |
| Android APK | `python3 tools/platform/build_android.py` (先 `python3 tools/platform/setup_android.py` 装 JDK / SDK) |
| iOS | `python3 tools/platform/build_ios.py` (需要 macOS + Xcode), 或用 GitHub Actions 的 `ios` 工作流 |
| 全平台 (云端) | GitHub Actions → `build` → Run workflow |

需要 Godot 4.7.2 与同版本的导出模板。完整步骤和签名说明见 [编译指南](docs/编译指南.md), 各平台细节见 `docs/打包/`。

## 二次开发

- **改数值、加关卡、写剧情**: 内容包是一个目录, 只写要改的部分, 按键深合并到基础内容上。从 [`game/content/example_mod/`](game/content/example_mod/) 复制起步:
  ```bash
  cp -r game/content/example_mod game/content/my_mod      # manifest.json 里的 id 改成 my_mod
  python3 tools/checks/content_schema.py my_mod           # 校验 (纯 Python)
  python3 tools/run_game.py -- --mods=my_mod              # 加载你的 mod 运行
  ```
- **做全新的游戏**: 从 [`game/content/templates/minimal_game/`](game/content/templates/minimal_game/) 开始, 教程见 [新游戏接入指南](docs/新游戏接入指南.md)。
- **素材 mod**: 把自己的图像 / 音乐按相同的目录结构打成 `.pck` 放进 `mod/`, 后挂载的同路径文件覆盖先挂载的, 见 [资源包](docs/打包/资源包.md)。
- 字段与格式: [内容格式](docs/内容格式.md)、[剧情脚本格式](docs/剧情脚本格式.md) 与 [指令表](docs/剧情脚本格式_指令表.md)、[规则参数表](docs/规则参数表.md)、[保留变量表](docs/保留变量表.md)、[AI 行为注册表](docs/AI行为注册表.md)。
- 引擎结构: [架构设计](docs/架构设计.md)。

mod 里只放你自己的数据和原创 (或有授权的) 素材, 不要分发原作素材。

## 参与开发

文档入口 [docs/README.md](docs/README.md), 贡献规范 [CONTRIBUTING.md](CONTRIBUTING.md), 脚本说明 [tools/README.md](tools/README.md)。提交前跑 `python3 tools/ci.py fast`。

## 许可

代码与文档按 **GPL-3.0-only** 授权 ([LICENSE](LICENSE)), 第三方组件见 [NOTICE.md](NOTICE.md)。GPL 只覆盖本项目自己写的代码和文档, **不覆盖、也不授予任何原作内容的权利**。

- 相关作品的名称、角色、画面、音乐、视频、文本等的全部权利归原权利人所有。
- 任何由原作生成或衍生的资源包 (含 AI 放大、AI 重绘的结果) 仅限使用者个人学习研究, 且以拥有原作正版为前提; 不得转载、再分发、二次打包, 不得用于商业用途。
- 使用者自行承担使用本项目及相关资源的责任。

*Unofficial, non-profit fan technology project, not affiliated with or endorsed by the rights holders of the original game.
This repository contains engine code, hand-written content and documentation only — no assets of the original game.
Resource packs derived from the original game are for personal use by owners of a legitimate copy, and must not be redistributed or used commercially.*

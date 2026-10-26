# 参与贡献

欢迎 Issue 与 PR。先读 `README.md` 开头的声明: 本仓库不含原作资源, 贡献也不能含。

## 红线

PR 不得包含:
- 原作的游戏文件、画面截图 (包括以原作美术为主体的复刻画面截图);
- 资源包 `.pck`、从原作解出的数据表、对白文本、AI 放大 / 重绘的结果;
- 第三方论坛帖或攻略的成段原文 (文档里只写变量、条件、数值和你自己的结论, 引用请转述并附出处);
- 无许可或许可不兼容项目的代码;
- 签名密钥、密码、个人账号信息。

## 许可与 DCO

- 提交的代码与文档按项目许可 GPL-3.0-only (`LICENSE`) 授权; 新源文件请带 SPDX 头 (`python3 tools/legal/spdx_headers.py --check`)。
- 采用 [DCO 1.1](https://developercertificate.org/), 不要求 CLA: 每个提交带 `Signed-off-by: 姓名 <邮箱>` (`git commit -s`), 表示代码是你写的或你有权按该许可提交。

## 开发环境

```bash
git clone https://github.com/zmnqaz/SwordmanHD.git && cd SwordmanHD
git config core.autocrlf false        # Windows 必做: 仓库全是 LF, CRLF 会让 .sh 无法运行、让校验不一致
pip install -r tools/requirements-ci.txt
# 下载 Godot 4.7.2 到 tools/godot/ (或 tools/ci_install_godot.sh); python3 tools/paths.py 自检
python3 tools/ci.py fast              # 提交前必须绿
```

没有资源包也能跑完 `ci.py fast`: 依赖资源包的测试自动 SKIP (输出里列出原因与数量), 其余必须全过。Windows 开发见 `docs/Windows开发.md`。

## 提交规范

- 提交信息写清「改了什么、为什么」, 一个主题一个提交 (例: `fix: 反击判定漏了蓄劲状态`)。
- 行为改动要带测试。

## 内容包 / 模板

- 做改动包或全新游戏先读 `docs/新游戏接入指南.md`; 起手模板 `game/content/templates/minimal_game/` (全新游戏) 与 `game/content/example_mod/` (改动包)。
- 提交前 `python3 tools/checks/content_schema.py --pack <你的包目录> --strict` 必须通过。
- 新增 `.evs` 指令按 `docs/剧情脚本格式_指令表.md` 文末的步骤; 改了 `params.gd` / `reserved_vars.py` / `compile_events.py` 后重新生成对应文档。

## 行尾与编辑器

`.editorconfig` 已配置; 文本一律 LF、UTF-8。

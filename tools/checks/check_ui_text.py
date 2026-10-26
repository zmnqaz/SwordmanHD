#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""检查代码里写死的中文字符串 (设计 docs/设计_繁简切换.md §4): 玩家看得到的文字要走 UiStrings.t(键), 简体写在内容包 text/ui.json,
繁体写在 locale/hant/text/ui.json, 否则繁体模式下它会还是简体 (或简繁混杂)。
扫描 game/engine 与 game/scripts 下 .gd 的字符串字面量里含汉字的; 下面几类不算:
  - print / printerr / push_warning / push_error / assert / _log / prints 调用行 (日志, 不给玩家看)
  - 注释; tests/ 目录; 开发工具与诊断类文件 (DEV_FILES: 图鉴、脚本编译器报错、内容包加载报错、着色器自检等)
  - 已登记在 tools/checks/ui_text_allow.txt 的 (文件|字面量): 后备值 (内容包里取不到时才用)、数据键、开发者消息
新增的字面量不在白名单里就报错, 退出码 1。确属开发/日志用途: 加进白名单 (python3 tools/checks/check_ui_text.py --update 重生成,
评审时看白名单的变化)。
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/
import _boot  # noqa: E402,F401
from paths import REPO  # noqa: E402

ALLOW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui_text_allow.txt")
CJK = re.compile(r"[一-鿿]")
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
LOGCALL = re.compile(r"\b(print|printerr|push_warning|push_error|assert|_log|prints)\s*\(")
# 开发工具/诊断/内部数据: 整个文件不查
DEV_FILES = (
    "ui/gallery.gd", "ui/ui_layout.gd", "ui/ui_debug_overlay.gd", "ui/screen_layout.gd", "ui/ui_fonts.gd",
    "script/evs_compiler.gd", "content/content_db.gd", "content/content_compat.gd", "render/hq/hq_baker.gd",
    "core/save_file.gd", "core/game_saves.gd", "core/game_state.gd", "test/test_gcf.gd",
    "battle/battle_stats.gd",
    "scripts/monkey.gd", "scripts/autotest.gd", "scripts/user_dir_migrate.gd", "test/regress_log.gd",
)


def scan_lines(lines):
    """一个文件的各行 -> [(行号, 字面量)]: 跳过注释行与日志调用行"""
    out = []
    for i, line in enumerate(lines, 1):
        if line.strip().startswith("#"):
            continue
        code = line.split("  #")[0]
        if LOGCALL.search(code):
            continue
        for m in LIT.finditer(code):
            if CJK.search(m.group(1)):
                out.append((i, m.group(1)))
    return out


def scan():
    """[(相对 game/ 的文件, 行号, 字面量)]"""
    out = []
    for f in sorted(glob.glob(os.path.join(REPO, "game", "engine", "**", "*.gd"), recursive=True)
                    + glob.glob(os.path.join(REPO, "game", "scripts", "**", "*.gd"), recursive=True)):
        rel = os.path.relpath(f, os.path.join(REPO, "game")).replace(os.sep, "/")
        if "/tests/" in rel or rel.endswith(DEV_FILES):
            continue
        for i, t in scan_lines(open(f, encoding="utf-8").read().splitlines()):
            out.append((rel, i, t))
    return out


def load_allow():
    s = set()
    if os.path.isfile(ALLOW):
        for line in open(ALLOW, encoding="utf-8"):
            line = line.rstrip("\n")
            if line and not line.startswith("#"):
                s.add(line)
    return s


def main():
    found = scan()
    keys = sorted({"%s|%s" % (f, t) for f, _, t in found})
    if "--update" in sys.argv:
        with open(ALLOW, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("# 代码里允许保留的中文字符串字面量 (文件|字面量), 由 check_ui_text.py --update 生成; 新增前先想想能不能走 UiStrings.t(键)。\n")
            fh.write("# 都是: 内容包取不到时的后备值、数据键 (不显示)、开发者消息。玩家可见的新文字不要加到这里。\n")
            fh.write("\n".join(keys) + "\n")
        print("写入 %d 条 -> %s" % (len(keys), os.path.relpath(ALLOW, REPO)))
        return 0
    allow = load_allow()
    bad = [(f, i, t) for f, i, t in found if "%s|%s" % (f, t) not in allow]
    for f, i, t in bad:
        print("game/%s:%d: 写死的中文 %r" % (f, i, t[:40]))
    if bad:
        print("共 %d 处: 玩家可见的文字请改 UiStrings.t(键) 并在 game/content/remake/text/ui.json 加简体文案 (繁体跑 make_hant_text.py 生成);"
              " 确属开发/日志用途就 --update 登记白名单" % len(bad))
        return 1
    stale = allow - set(keys)
    if stale:
        print("提示: 白名单里有 %d 条已不存在 (可 --update 清理)" % len(stale))
    print("无新增写死的中文 (%d 处在白名单)" % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main())

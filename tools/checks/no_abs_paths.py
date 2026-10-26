#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""绝对路径守卫: 代码里不许写死本机路径 (用户主目录、工作区、worktree 名之类的本机路径)。
扫描 git 跟踪的 tools/ game/engine game/scripts game/tests game/tools 里的文本文件 (docs/ 与历史实测记录不管)。
  python3 tools/checks/no_abs_paths.py            列出命中, 有命中退出码 1 (ci.py 里先作为警告, 清零后改硬失败)
  python3 tools/checks/no_abs_paths.py --summary  只打印按文件统计
白名单: 该行 (或上一行) 含 `abs-path-ok: 原因` 注释即放行 (例如 usage 示例、纯说明)。
替代写法: Python 用 tools/paths.py (original_dir()/REPO/...) 或环境变量; GDScript 用 Assets / res:// / OS.get_environment; sh 用 $(dirname "$0")。
"""
import os
import re
import subprocess
import sys

import sys; sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/  # noqa: E702
import _boot  # noqa: E402

ROOT = _boot.REPO
SCOPES = ["tools", "game/engine", "game/scripts", "game/tests", "game/tools"]
PAT = re.compile(r"/home/[a-z][\w.-]*/|/Users/[A-Za-z][\w.-]*/|\bwt-[a-z0-9]+\b")
SELF = "tools/checks/no_abs_paths.py"
# 整文件放行 (原因): worktree 名在这些文件里是「数据/说明」, 不是路径
WHITELIST = {
    "tools/README.md": "说明守卫本身",
    "tools/_boot.py": "说明守卫本身",
}
WHITELIST_PREFIX = ("tools/tests/fixtures/",)  # 文档样例 (含 wt-xxx 归属标签)
TEXT_EXT = (".py", ".sh", ".gd", ".gdshader", ".json", ".md", ".txt", ".cfg", ".yml", ".yaml", ".bat", ".cmd", ".ps1", ".s", ".c", ".h", ".tscn")


def scan():
    r = subprocess.run(["git", "-C", ROOT, "ls-files", "--"] + SCOPES, capture_output=True, text=True, encoding="utf-8", errors="replace")
    files = r.stdout.splitlines() if r.returncode == 0 else []
    if not files:  # 非 git 目录: 直接遍历
        for sc in SCOPES:
            for dp, _, fns in os.walk(os.path.join(ROOT, sc)):
                files += [os.path.relpath(os.path.join(dp, f), ROOT).replace(os.sep, "/") for f in fns]
    hits = []
    for rel in files:
        if rel == SELF or rel in WHITELIST or rel.startswith(WHITELIST_PREFIX) or not rel.endswith(TEXT_EXT) or "/.godot/" in rel:
            continue
        try:
            with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as f:
                lines = f.read().split("\n")
        except OSError:
            continue
        for n, line in enumerate(lines):
            if PAT.search(line) and "abs-path-ok" not in line and not (n and "abs-path-ok" in lines[n - 1]):
                hits.append((rel, n + 1, line.strip()[:140]))
    return hits


def main(argv):
    hits = scan()
    if "--summary" in argv:
        per = {}
        for rel, _, _ in hits:
            per[rel] = per.get(rel, 0) + 1
        for rel, c in sorted(per.items(), key=lambda kv: -kv[1]):
            print("%4d  %s" % (c, rel))
    else:
        for rel, n, line in hits:
            print("%s:%d: %s" % (rel, n, line))
    print("绝对路径命中 %d 处 (%d 个文件); 用 tools/paths.py / 环境变量替代, 或加注释 abs-path-ok: 原因" % (len(hits), len({h[0] for h in hits})))
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

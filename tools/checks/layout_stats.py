#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""重算布局表 stats (元素数、各 status 数、已接入数 migrated), 写回 layout.json; --check 只比对不写 (不一致时退出码 1)。
用法: python tools/checks/layout_stats.py [--check] [布局表路径, 缺省 game/content/remake/ui_theme/layout.json]
status 含义 (verified / screenshot / conflict / unknown); migrated = 代码已改为读本表的元素数。
python-tests (tools/tests/test_layout_stats.py) 跑 --check, 改了布局表忘记重算会失败。"""
import collections
import json
import os
import sys

DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "content", "remake", "ui_theme", "layout.json")


def compute(d):
    els = d["elements"]
    c = collections.Counter(e.get("status", "unknown") for e in els.values() if isinstance(e, dict))
    st = {"elements": len(els)}
    for k in ("verified", "screenshot", "conflict", "unknown", "added"):
        if c.get(k):
            st[k] = c[k]
    for k in sorted(c):
        if k not in st:
            st[k] = c[k]
    st["migrated"] = sum(1 for e in els.values() if isinstance(e, dict) and e.get("migrated"))
    return st


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    path = args[0] if args else DEFAULT
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    st = compute(d)
    if "--check" in argv:
        ok = d.get("stats") == st
        print("stats", "ok" if ok else "不一致: 表里 %s, 实际 %s (python tools/checks/layout_stats.py 重算)" % (d.get("stats"), st))
        return 0 if ok else 1
    d["stats"] = st
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")
    print(json.dumps(st, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

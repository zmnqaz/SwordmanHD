#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""SPDX 许可头检查与写入 (项目许可 GPL-3.0-only, 2026-10-06 用户确认)。

  python3 tools/legal/spdx_headers.py --check      # 缺头/头不符的文件数; 有则退出码 1
  python3 tools/legal/spdx_headers.py --dry-run    # 打印每类文件「将会」插入什么 (前 N 个示例), 不改文件
  python3 tools/legal/spdx_headers.py --apply      # 给缺头的文件插入 (幂等; 头不符的只报告不改)
  选项: --license GPL-3.0-only (缺省) --examples N --repo DIR

约定:
  - 只处理 git 已跟踪的 .py .gd .gdshader .sh 文件 (.uid/.import/.json/.md/字体/贴图不加头)。
  - 头 = 一行注释 `SPDX-License-Identifier: <id>`, 放在 shebang 之后 (有 shebang 时) 的第一行; 检查只看前 6 行。
  - OVERRIDES: 第三方改写文件有自己的 id, 且保留原版权头 (头里写 SPDX 行之外, 版权行由人工保留, 脚本不碰):
      game/engine/render/hq/hqx.gdshader        LGPL-2.1-or-later
      game/engine/render/hq/xbrz6_alpha.gdshader GPL-3.0-only   (xBRZ 上游 GPL-3.0 无 or-later, 已核实)
  - EXCLUDE: 生成物/第三方/待删目录不检查 (hd4x、game/content/tdj、data、docs 下的非代码)。
  - --apply 写入时保留 CRLF/LF 原样, shebang 留在第一行 (见 insert_header)。
"""
import argparse
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMMENT = {".py": "#", ".gd": "#", ".sh": "#", ".gdshader": "//"}
OVERRIDES = {
    "game/engine/render/hq/hqx.gdshader": "LGPL-2.1-or-later",
    "game/engine/render/hq/xbrz6_alpha.gdshader": "GPL-3.0-only",
}
EXCLUDE = ("hd4x/", "data/", "game/content/tdj/", "demo/", "game/.godot/")
VENDOR_DIR = "/_vendor/"   # 随仓库带的第三方库 (各自带许可证), 任何目录下的 _vendor/ 都不加我们的头
SPDX_RE = re.compile(r"SPDX-License-Identifier:\s*(\S+)")


def tracked(repo):
    out = subprocess.run(["git", "-C", repo, "ls-files", "-z"], capture_output=True, check=True).stdout
    return [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]


def expected(path, default):
    ext = os.path.splitext(path)[1]
    if ext not in COMMENT or path.startswith(EXCLUDE) or VENDOR_DIR in "/" + path:
        return None
    return OVERRIDES.get(path, default)


def header_line(path, lic):
    return "%s SPDX-License-Identifier: %s" % (COMMENT[os.path.splitext(path)[1]], lic)


def insert_header(text, path, lic):
    """返回加头后的文本 (保留换行风格, shebang 在先)。"""
    nl = "\r\n" if "\r\n" in text[:2000] else "\n"
    line = header_line(path, lic) + nl
    if text.startswith("#!"):
        first, _, rest = text.partition("\n")
        return first + "\n" + line + rest
    return line + text


def current(text):
    for ln in text.splitlines()[:6]:
        m = SPDX_RE.search(ln)
        if m:
            return m.group(1)
    return None


def scan(repo, default):
    res = {"ok": [], "missing": [], "mismatch": [], "skipped": 0}
    for p in tracked(repo):
        lic = expected(p, default)
        if lic is None:
            res["skipped"] += 1
            continue
        try:
            with open(os.path.join(repo, p), encoding="utf-8", errors="replace") as f:
                cur = current(f.read(2000))
        except OSError:
            continue
        if cur is None:
            res["missing"].append((p, lic))
        elif cur != lic:
            res["mismatch"].append((p, lic, cur))
        else:
            res["ok"].append(p)
    return res


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true")
    g.add_argument("--dry-run", action="store_true")
    g.add_argument("--apply", action="store_true")
    ap.add_argument("--license", default="GPL-3.0-only")
    ap.add_argument("--examples", type=int, default=3)
    ap.add_argument("--repo", default=REPO)
    a = ap.parse_args(argv)
    r = scan(a.repo, a.license)
    print("SPDX: 合规 %d, 缺头 %d, 不符 %d, 跳过(非代码/排除) %d" % (len(r["ok"]), len(r["missing"]), len(r["mismatch"]), r["skipped"]))
    for p, lic, cur in r["mismatch"][:20]:
        print("  不符: %s 应为 %s 实为 %s" % (p, lic, cur))
    if a.apply:
        for p, lic in r["missing"]:
            full = os.path.join(a.repo, p)
            with open(full, encoding="utf-8", newline="") as f:
                text = f.read()
            with open(full, "w", encoding="utf-8", newline="") as f:
                f.write(insert_header(text, p, lic))
        print("SPDX: 已插入 %d 个文件" % len(r["missing"]))
        return 1 if r["mismatch"] else 0
    if a.dry_run:
        by_ext = {}
        for p, lic in r["missing"]:
            by_ext.setdefault(os.path.splitext(p)[1], []).append((p, lic))
        for ext, items in sorted(by_ext.items()):
            print("[dry-run] %s: %d 个文件将插入 `%s`" % (ext, len(items), header_line("x" + ext, items[0][1])))
            for p, lic in items[:a.examples]:
                with open(os.path.join(a.repo, p), encoding="utf-8", errors="replace") as f:
                    new = insert_header(f.read(400), p, lic)
                print("    %s ->\n      %s" % (p, "\n      ".join(new.splitlines()[:2])))
        print("[dry-run] 未修改任何文件")
        return 0
    return 1 if (r["missing"] or r["mismatch"]) else 0


if __name__ == "__main__":
    sys.exit(main())

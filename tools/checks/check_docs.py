#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""文档检查: docs/ 与根 README.md 里的相对链接是否有效; 哪些 docs/**/*.md 没有被 docs/README.md 直接引用。

用法:
  python tools/checks/check_docs.py            报告断链与未索引文件 (默认退出 0)
  python tools/checks/check_docs.py --strict   有断链或未索引文件时退出 1
  python tools/checks/check_docs.py --links-only / --index-only   只做其中一项
  python tools/checks/check_docs.py --generated        只检查生成物是否过期 (见下)
  python tools/checks/check_docs.py --all --strict     CI 用 (ci.py fast 的 docs-check 步骤): 链接 + 索引 + 生成物, 任何一项有问题退出 1
生成物过期闸门 (手改生成物 / 改了源忘记重生成时红): 剧情脚本格式_指令表.md (gen_evs_doc.py --check)、规则参数表.md (params_table.py --check-doc)、保留变量表.md (reserved_vars.py --check-doc)。
说明: 只检查 Markdown 内联链接 [文字](相对路径) 与 <相对路径>; 忽略 http(s)/mailto、纯 #锚点、代码块里的链接;
链接末尾的 #锚点 与 ?参数 去掉后再查文件/目录是否存在 (不校验锚点本身)。
docs/README.md 是分类索引, 新增文档时要在那里加一行 (「历史」「附件」类 md 也要列)。
索引 等生成物也会被检查链接。
"""
import argparse
import os
import re
import sys
from urllib.parse import unquote

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/
sys.path.insert(0, HERE)
import paths  # noqa: E402

ROOT = paths.REPO
DOCS = os.path.join(ROOT, "docs")
LINK_RE = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")


def md_files():
    out = [os.path.join(ROOT, "README.md")]
    for dp, dn, fn in os.walk(DOCS):
        dn[:] = sorted(d for d in dn if not d.startswith("."))
        for f in sorted(fn):
            if f.endswith(".md"):
                out.append(os.path.join(dp, f))
    return [p for p in out if os.path.exists(p)]


def links_of(path):
    """返回 [(行号, 目标)], 跳过围栏代码块与行内代码。"""
    res = []
    in_fence = False
    with open(path, encoding="utf-8") as f:
        for ln, line in enumerate(f, 1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            line = INLINE_CODE_RE.sub("", line)
            for m in LINK_RE.finditer(line):
                res.append((ln, m.group(1)))
    return res


def resolve(src, target):
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
        return None
    t = unquote(re.split(r"[#?]", target, maxsplit=1)[0])
    if not t:
        return None
    base = ROOT if t.startswith("/") else os.path.dirname(src)
    return os.path.normpath(os.path.join(base, t.lstrip("/")))


def private_only(path):
    """没有「只在别处存放」的文档: 断链就是断链"""
    return False


def check_links():
    bad = []
    for p in md_files():
        for ln, tgt in links_of(p):
            r = resolve(p, tgt)
            if r is not None and not os.path.exists(r) and not private_only(r):
                bad.append((os.path.relpath(p, ROOT), ln, tgt))
    return bad


def check_index():
    idx = os.path.join(DOCS, "README.md")
    if not os.path.exists(idx):
        return None, []
    linked = set()
    for ln, tgt in links_of(idx):
        r = resolve(idx, tgt)
        if r and os.path.exists(r):
            linked.add(r)
            # 链到目录算引用该目录下全部文件
            if os.path.isdir(r):
                for dp, _, fn in os.walk(r):
                    for f in fn:
                        linked.add(os.path.join(dp, f))
    miss = []
    for p in md_files():
        if p == idx or p == os.path.join(ROOT, "README.md"):
            continue
        if os.path.normpath(p) not in linked:
            miss.append(os.path.relpath(p, ROOT))
    return idx, miss


# (文档名, 命令参数 (相对 tools/), 重生成命令)
GENERATED = [
    ("剧情脚本格式_指令表.md", ["docgen/gen_evs_doc.py", "--check"], "python tools/docgen/gen_evs_doc.py"),
    ("规则参数表.md", ["docgen/params_table.py", "--check-doc"], "python tools/docgen/params_table.py --write-doc"),
    ("保留变量表.md", ["docgen/reserved_vars.py", "--check-doc"], "python tools/docgen/reserved_vars.py --write-doc"),
]


def check_generated(generated=None):
    """逐个跑生成物的 --check, 返回 [(文档名, 重生成命令, 输出)] (过期的)。"""
    import subprocess
    bad = []
    for name, cmd, regen in (GENERATED if generated is None else generated):
        r = subprocess.run([sys.executable, os.path.join(HERE, cmd[0])] + cmd[1:], capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ROOT)
        if r.returncode != 0:
            bad.append((name, regen, (r.stdout + r.stderr).strip()))
    return bad


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--links-only", action="store_true")
    ap.add_argument("--index-only", action="store_true")
    ap.add_argument("--generated", action="store_true", help="只检查生成物是否过期")
    ap.add_argument("--all", action="store_true", help="链接 + 索引 + 生成物 (CI 用)")
    a = ap.parse_args(argv)
    problems = 0
    if a.all:
        do_links, do_index, do_gen = True, True, True
    elif a.generated:
        do_links, do_index, do_gen = False, False, True
    else:
        do_links, do_index, do_gen = not a.index_only, not a.links_only, False
    if do_links:
        bad = check_links()
        for f, ln, t in bad:
            print("断链: %s:%d -> %s" % (f, ln, t))
        print("链接检查: %d 个文件, 断链 %d" % (len(md_files()), len(bad)))
        problems += len(bad)
    if do_index:
        idx, miss = check_index()
        if idx is None:
            print("没有 docs/README.md")
            problems += 1
        else:
            for m in miss:
                print("未被 docs/README.md 引用: %s" % m)
            print("索引检查: 未引用 %d 个" % len(miss))
            problems += len(miss)
    if do_gen:
        bad = check_generated()
        for name, regen, out in bad:
            print("生成物过期或被手改: docs/%s -> 运行 %s 并提交\n  %s" % (name, regen, out.splitlines()[0] if out else ""))
        print("生成物检查: %d 个文档, 过期 %d" % (len(GENERATED), len(bad)))
        problems += len(bad)
    return 1 if (a.strict and problems) else 0


if __name__ == "__main__":
    sys.exit(main())

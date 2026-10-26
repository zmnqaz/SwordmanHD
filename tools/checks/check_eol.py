#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""行尾检查: 用 `git ls-files --eol` 找出「应该是 LF 却不是」的文件 (docs/)。
.gitattributes 规定文本文件 (*.gd *.json *.py *.sh ...) 入库与工作区都是 LF; *.bat/*.cmd/*.ps1 入库 LF、工作区 CRLF。
Windows 上 core.autocrlf=true 的克隆会把整个工作区改成 CRLF (曾污染 551 个文件), sh 脚本带 CR 直接跑不起来。
  - 入库内容 (i/) 带 CR: 失败 (退出码 1)。
  - 工作区 (w/) 带 CR 而 .gitattributes 要求 eol=lf: 失败, 并提示 git config core.autocrlf false 后重新检出。
不是 git 仓库 (如源码包解压) 或没有 git 时跳过 (退出码 0)。
"""
import os
import re
import subprocess
import sys

import sys; sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/  # noqa: E702
import _boot  # noqa: E402

ROOT = _boot.REPO


def main():
    try:
        r = subprocess.run(["git", "-C", ROOT, "ls-files", "--eol"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    except OSError:
        print("SKIP: 没有 git")
        return 0
    if r.returncode != 0:
        print("SKIP: 不是 git 仓库")
        return 0
    bad_index, bad_work = [], []
    for line in r.stdout.splitlines():
        m = re.match(r"i/(\S+)\s+w/(\S+)\s+attr/(.*?)\t(.*)$", line)
        if not m:
            continue
        i, w, attr, path = m.groups()
        want_lf = "eol=lf" in attr
        want_crlf = "eol=crlf" in attr
        if not (want_lf or want_crlf):
            continue  # 没有行尾规则的文件 (二进制/日志等) 不管
        if i in ("crlf", "mixed"):
            bad_index.append(path)
        elif want_lf and w in ("crlf", "mixed"):
            bad_work.append(path)
    if bad_index:
        print("入库内容带 CR (应为 LF) %d 个:" % len(bad_index))
        print("\n".join("  " + p for p in bad_index[:30]))
    if bad_work:
        print("工作区带 CR 但 .gitattributes 要求 eol=lf, %d 个 (多半是 core.autocrlf=true):" % len(bad_work))
        print("\n".join("  " + p for p in bad_work[:30]))
        print("修复: git config core.autocrlf false && git rm --cached -r -q . && git reset --hard   (先提交或备份未提交改动)")
    if bad_index or bad_work:
        return 1
    print("行尾 OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

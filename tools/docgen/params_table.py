#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""从 game/engine/rules/params.gd 自动提取规则参数表 (名 / 类型 / 默认值 / 章节 / 注释), 不手抄。

params.gd 的约定: 文件头到 `func _init` 之间, 顶格的 `var 名 := 字面量  # 注释` 都是参数;
`# ---------------- NN 章节 ----------------` 是章节分隔; 紧邻上方的 `## ...` 行是该参数的补充说明。
字面量支持 int (含 0x..)、float、bool、字符串、数组、字典 (可跨行)。
rules.json 里的值允许 JSON 数字 (引擎把整数值的 float 转回 int), 校验规则见 check_value()。

用法: python3 tools/docgen/params_table.py            打印参数表 (名 类型 默认值)
      python3 tools/docgen/params_table.py --json     输出 JSON
      python3 tools/docgen/params_table.py --write-doc   生成 docs/规则参数表.md;  --check-doc 检查它没过期 (闸门)
作为模块: load_params() -> {名: {"type","default","section","doc"}}; check_params(dict) -> 错误列表
"""
import ast
import difflib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/
REPO = os.path.dirname(HERE)
PARAMS_GD = os.path.join(REPO, "game", "engine", "rules", "params.gd")

_VAR = re.compile(r"^var\s+([A-Za-z_]\w*)\s*(?::\s*\w+\s*)?:?=\s*(.*)$")
_SECTION = re.compile(r"^#\s*-{5,}\s*(.*?)\s*-{5,}\s*$")


def _split_comment(s):
    """去掉行尾 # 注释 (不在字符串里的第一个 #), 返回 (代码, 注释)"""
    q = None
    for i, ch in enumerate(s):
        if q:
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
        elif ch == "#":
            return s[:i].rstrip(), s[i + 1:].strip()
    return s.rstrip(), ""


def _balanced(code):
    return code.count("[") + code.count("{") + code.count("(") <= code.count("]") + code.count("}") + code.count(")")


def _literal(code):
    code = re.sub(r"\btrue\b", "True", code)
    code = re.sub(r"\bfalse\b", "False", code)
    return ast.literal_eval(code)


def type_of(v):
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, int):
        return "int"
    if isinstance(v, float):
        return "float"
    if isinstance(v, str):
        return "str"
    if isinstance(v, list):
        return "array"
    if isinstance(v, dict):
        return "dict"
    return "any"


def load_params(path=PARAMS_GD):
    """-> {参数名: {type, default, section, doc, line}} (按文件顺序)"""
    out = {}
    section, pending = "", []
    lines = open(path, encoding="utf-8").read().splitlines()
    i = 0
    while i < len(lines):
        ln = lines[i]
        i += 1
        if ln.startswith("func "):
            break
        m = _SECTION.match(ln)
        if m:
            section, pending = m.group(1), []
            continue
        if ln.startswith("##"):
            pending.append(ln.lstrip("#").strip())
            continue
        m = _VAR.match(ln)
        if not m:
            if not ln.strip():
                pending = []
            continue
        name = m.group(1)
        code, comment = _split_comment(m.group(2))
        start = i
        while not _balanced(code) and i < len(lines):  # 跨行字面量
            more, _ = _split_comment(lines[i])
            code += " " + more.strip()
            i += 1
        try:
            val = _literal(code)
        except (ValueError, SyntaxError) as e:
            raise ValueError("%s:%d 无法解析参数 %s 的默认值 %r: %s" % (path, start, name, code, e))
        doc = " ".join(pending + ([comment] if comment else []))
        out[name] = {"type": type_of(val), "default": val, "section": section, "doc": doc, "line": start}
        pending = []
    return out


def check_value(spec, v):
    """rules.json 的值是否符合参数类型; 返回错误文本或 None。JSON 数字: 整数值的 float 可作 int, int 可作 float"""
    t = spec["type"]
    if t == "bool":
        ok = isinstance(v, bool)
    elif t == "int":
        ok = (isinstance(v, int) and not isinstance(v, bool)) or (isinstance(v, float) and v == int(v))
    elif t == "float":
        ok = isinstance(v, (int, float)) and not isinstance(v, bool)
    elif t == "str":
        ok = isinstance(v, str)
    elif t == "array":
        ok = isinstance(v, list)
    elif t == "dict":
        ok = isinstance(v, dict)
    else:
        ok = True
    if not ok:
        return "类型应为 %s, 实际 %s (%s)" % (t, type(v).__name__, json.dumps(v, ensure_ascii=False)[:40])
    return None


def suggest(name, names):
    m = difflib.get_close_matches(name, list(names), n=1, cutoff=0.7)
    return m[0] if m else None


def check_params(params, table=None):
    """校验 rules.json 的 params 字典; 返回 [(参数名, 消息)]"""
    table = table or load_params()
    errs = []
    for k, v in params.items():
        if k.startswith("_"):
            continue
        if k not in table:
            s = suggest(k, table)
            errs.append((k, "未知参数 %s%s" % (k, ", 你是不是想写 %s" % s if s else "")))
            continue
        e = check_value(table[k], v)
        if e:
            errs.append((k, e))
    return errs


DOC = os.path.join(REPO, "docs", "规则参数表.md")


def markdown(t=None):
    t = t or load_params()
    L = ["# 规则参数表 (生成)", "",
         "<!-- 由 tools/docgen/params_table.py --write-doc 从 game/engine/rules/params.gd 生成, 请勿手改 (改 params.gd 的参数或注释后重新生成) -->", "",
         "内容包根目录的 `rules.json` (`{\"format\": \"tdj-rules/1\", \"params\": {参数名: 值}}`) 只写要改的参数, 后加载的包覆盖先加载的; 没写的取下表默认值。"
         "`python3 tools/checks/content_schema.py --strict` 会按本表检查参数名 (拼错给近似建议) 与类型。共 %d 个参数。" % len(t), ""]
    sec = None
    for k, v in t.items():
        if v["section"] != sec:
            sec = v["section"]
            L += ["", "## %s" % (sec or "(未分章)"), "", "| 参数 | 类型 | 默认值 | 说明 |", "|---|---|---|---|"]
        d = json.dumps(v["default"], ensure_ascii=False)
        L.append("| `%s` | %s | `%s` | %s |" % (k, v["type"], d.replace("|", "\\|"), v["doc"].replace("|", "\\|")))
    return "\n".join(L) + "\n"


def main(argv):
    if "--write-doc" in argv:
        open(DOC, "w", encoding="utf-8", newline="\n").write(markdown())
        print("写入", DOC)
        return 0
    if "--check-doc" in argv:
        cur = open(DOC, encoding="utf-8").read() if os.path.isfile(DOC) else ""
        if cur != markdown():
            print("docs/规则参数表.md 已过期: 运行 python3 tools/docgen/params_table.py --write-doc")
            return 1
        print("docs/规则参数表.md 是最新的")
        return 0
    t = load_params()
    if "--json" in argv:
        print(json.dumps(t, ensure_ascii=False, indent=1))
    else:
        for k, s in t.items():
            print("%-32s %-6s %s" % (k, s["type"], json.dumps(s["default"], ensure_ascii=False)[:60]))
        print("共 %d 个参数" % len(t))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

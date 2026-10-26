#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""内容包加载顺序 trace (X2, 对应 docs/新游戏接入指南.md「调试」章): 作者想知道「我改的东西最后是谁赢了」。

打印: ① 加载顺序 (base 递归在前, 后加载的覆盖先加载的); ② manifest 合并 (stage_count/town_count 取最大, 其余后者覆盖);
③ 每张数据表每个包新增/改/删多少条记录; ④ 同路径文件被覆盖 (整文件替换 / 逐元素叠加 / 参数合并 / 按表名替换) 与谁覆盖了谁;
⑤ rules.json 每个参数被哪些包设置; ⑥ 包内 assets/ 覆盖了哪些资源。
规则来源: engine/content/content_db.gd (find / _build_tables / _build_manifest)、engine/ui/ui_layout.gd、rules/params.gd。

用法: python3 tools/checks/content_schema.py --trace-load [包名 ... | --pack 目录]      (推荐入口)
      python3 tools/qa/content_trace.py [包名 ...]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/
sys.path.insert(0, HERE)
import _boot  # noqa: E402,F401  (assets/ checks/ qa/ 进 sys.path)
import paths  # noqa: E402
import content_schema as cs  # noqa: E402

# 同路径出现在多个包里时的合并语义
MERGE_KIND = {
    "ui_theme/layout.json": "逐元素叠加 (只写差异)",
    "rules.json": "按参数名合并",
    "text/system.json": "按表名替换",
}
SKIP = {"manifest.json"}
LIMIT = 40


def _rows(path):
    try:
        v = json.load(open(path, encoding="utf-8"))
        return v if isinstance(v, list) else []
    except (OSError, ValueError):
        return []


def _files(d):
    out = {}
    for r, _, fs in os.walk(d):
        for f in fs:
            p = os.path.join(r, f)
            out[os.path.relpath(p, d).replace(os.sep, "/")] = p
    return out


def trace(ids, extra=None):
    """-> 文本"""
    L = []
    cs.errors.clear()
    order = []
    for pid in ids:
        for x in cs.chain(pid, extra):
            if x not in order:
                order.append(x)
    dirs = {i: cs.pack_dir(i, extra) for i in order}
    man = {i: (cs.load_json(os.path.join(dirs[i], "manifest.json"), i) or {}) if dirs[i] else {} for i in order}
    L.append("== 加载顺序 (后者覆盖前者)")
    for n, i in enumerate(order, 1):
        m = man[i]
        L.append("  %d. %-14s %-8s base=%s  %s" % (n, i, m.get("version", "?"), m.get("base", []), paths.relpath(dirs[i], cs.os.path.dirname(cs.CONTENT)) if dirs[i] else "(找不到)"))
    L.append("")
    L.append("== manifest 合并")
    for k in ("stage_count", "town_count"):
        have = [(i, man[i][k]) for i in order if k in man[i]]
        if have:
            L.append("  %s = %s (取最大; 各包: %s)" % (k, max(v for _, v in have), ", ".join("%s=%s" % x for x in have)))
    for k in ("start", "ending_movies", "asset_roots", "save_neutral", "engine_min"):
        have = [(i, man[i][k]) for i in order if k in man[i]]
        if have:
            L.append("  %s = %s (由 %s 提供%s)" % (k, json.dumps(have[-1][1], ensure_ascii=False), have[-1][0],
                                              "; 覆盖了 %s" % ", ".join(i for i, _ in have[:-1]) if len(have) > 1 else ""))
    L.append("")
    tables = {}
    for i in order:
        tables.update(man[i].get("tables") or {})
    L.append("== 数据表 (按键逐条深合并, _delete 删除)")
    for name, spec in tables.items():
        key = spec.get("key", "id")
        seen, parts = set(), []
        for i in order:
            f = (man[i].get("tables") or {}).get(name, spec).get("file", spec.get("file", ""))
            p = os.path.join(dirs[i], f) if dirs[i] else ""
            if not os.path.isfile(p):
                continue
            add = mod = dele = 0
            for r in _rows(p):
                if not isinstance(r, dict) or key not in r:
                    continue
                if r.get("_delete") is True:
                    dele += 1
                    seen.discard(r[key])
                elif r[key] in seen:
                    mod += 1
                else:
                    add += 1
                    seen.add(r[key])
            parts.append("%s: +%d 改%d 删%d" % (i, add, mod, dele))
        L.append("  %-18s 合并后 %4d 条  [%s]" % (name, len(seen), "; ".join(parts) or "无文件"))
    L.append("")
    owners = {}
    for i in order:
        for rel, p in _files(dirs[i]).items():
            owners.setdefault(rel, []).append(i)
    L.append("== 同路径文件被覆盖")
    shown = 0
    table_files = {s.get("file") for s in tables.values()}
    for rel in sorted(owners):
        o = owners[rel]
        if len(o) < 2 or rel in SKIP or rel in table_files or rel.startswith("assets/"):
            continue
        kind = MERGE_KIND.get(rel, "整文件替换")
        L.append("  %s: %s  [%s]" % (rel, " -> ".join(o), kind))
        shown += 1
        if shown >= LIMIT:
            L.append("  ... (只列前 %d 条)" % LIMIT)
            break
    if not shown:
        L.append("  (无)")
    L.append("")
    L.append("== rules.json 参数 (后者覆盖前者)")
    params = {}
    for i in order:
        d = cs.load_json(os.path.join(dirs[i], "rules.json"), i) if dirs[i] and os.path.isfile(os.path.join(dirs[i], "rules.json")) else None
        for k, v in ((d or {}).get("params") or {}).items():
            params.setdefault(k, []).append((i, v))
    for k, vs in params.items():
        L.append("  %s = %s  [%s]" % (k, json.dumps(vs[-1][1], ensure_ascii=False), " -> ".join("%s:%s" % (i, json.dumps(v, ensure_ascii=False)) for i, v in vs)))
    if not params:
        L.append("  (无, 全部为 params.gd 默认值 = 原版)")
    L.append("")
    L.append("== 包内 assets/ 覆盖")
    shown = 0
    for rel in sorted(owners):
        if rel.startswith("assets/"):
            o = owners[rel]
            L.append("  %s: %s" % (rel, " -> ".join(o)) if len(o) > 1 else "  %s: 仅 %s 提供" % (rel, o[0]))
            shown += 1
            if shown >= LIMIT:
                L.append("  ... (只列前 %d 条)" % LIMIT)
                break
    if not shown:
        L.append("  (无)")
    if cs.errors:
        L.append("")
        L.append("== 加载问题")
        L += ["  " + e for e in cs.errors]
    return "\n".join(L) + "\n"


def main(argv):
    extra = None
    if argv[:1] == ["--pack"]:
        path = os.path.abspath(argv[1])
        extra, ids = os.path.dirname(path), [os.path.basename(path)]
    else:
        ids = argv or ["remake"]
    sys.stdout.write(trace(ids, extra))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

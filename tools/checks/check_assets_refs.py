#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""内容包里写的资源路径 (assets.dir / title_card / battle_floor / event_anims / image / anim / map_image / keeper_anim /
background_anim) 是否存在 (X2)。纯 Python, 不跑 Godot。

资源来源 (与运行时 Assets 的查找一致): 内容包链里每个包的 assets/ 目录 (大小写不敏感) + 原图仓库 index.json (有则用)。
没有原图仓库 (第三方作者没有原版) 时, 不在包内 assets/ 的路径无法验证, 只计数提示、不报错。
含占位符 (<n> {x} NN 等) 的是路径模板, 跳过; 布局表里的逻辑名 (ui_theme/assets.json 的 names) 先换成真实路径。

用法: python3 tools/checks/check_assets_refs.py [包名 ...]       默认校验 game/content/ 下的全部包
      python3 tools/checks/check_assets_refs.py --pack 目录      任意目录里的包 (base 包仍到 game/content/ 找)
退出码 0 通过, 1 有缺失。也由 content_schema.py --strict 调用 (check_refs(...))。
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/
sys.path.insert(0, HERE)
import _boot  # noqa: E402,F401  (assets/ checks/ qa/ 进 sys.path)
import content_schema as cs  # noqa: E402

KEYS = {"dir", "title_card", "battle_floor", "image", "anim", "map_image", "keeper_anim", "background_anim"}
NULLABLE = {"anim", "background_anim"}
SKIP_FILES = {"events_raw.json", "text.json", "manifest.json"}


def original_index():
    """原图仓库的 index.json -> 小写路径集合; 没有返回 None"""
    try:
        from paths import original_dir
        p = os.path.join(original_dir(), "index.json")
        if os.path.isfile(p):
            return {k.lower() for k in json.load(open(p, encoding="utf-8"))}
    except Exception:
        pass
    return None


def pack_assets(dirs):
    """各包 assets/ 下的小写相对路径集合"""
    out = set()
    for d in dirs:
        root = os.path.join(d, "assets")
        for r, _, fs in os.walk(root):
            for f in fs:
                out.add(os.path.relpath(os.path.join(r, f), root).replace(os.sep, "/").lower())
    return out


def refs_in_pack(d):
    """-> [(文件相对路径, 字段名, 资源路径)] (一个包目录内的全部引用)"""
    names = {}
    ap = os.path.join(d, "ui_theme", "assets.json")
    if os.path.isfile(ap):
        try:
            names = json.load(open(ap, encoding="utf-8")).get("names", {})
        except ValueError:
            pass
    out = []

    def walk(o, rel):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == "event_anims" and isinstance(v, dict):
                    for vv in v.values():
                        if isinstance(vv, str):
                            out.append((rel, k, names.get(vv, vv) if "/" not in vv else vv))
                elif k in KEYS and isinstance(v, str):
                    out.append((rel, k, names.get(v, v) if "/" not in v else v))
                elif k in KEYS and v is None and k not in NULLABLE:
                    out.append((rel, k, None))
                else:
                    walk(v, rel)
        elif isinstance(o, list):
            for v in o:
                walk(v, rel)

    for r, _, fs in os.walk(d):
        if os.path.relpath(r, d).replace(os.sep, "/").split("/")[0] == "assets":
            continue   # 包内 assets/ 是资源本身
        for f in fs:
            if f.endswith(".json") and f not in SKIP_FILES:
                rel = os.path.relpath(os.path.join(r, f), d).replace(os.sep, "/")
                try:
                    walk(json.load(open(os.path.join(r, f), encoding="utf-8")), rel)
                except ValueError:
                    pass
    return out


def exists(p, idx):
    low = p.lower().rstrip("/")
    return low in idx or low + "/anim.json" in idx or any(k.startswith(low + "/") for k in idx)


def check_refs(pack_dirs, orig=None, only_dir=None):
    """pack_dirs: 加载顺序里的包目录 (assets/ 取全部); only_dir: 只检查该包自带文件里的引用 (默认最后一个)。
    -> (错误列表, 无法验证的数量)"""
    orig = original_index() if orig is None else orig
    have = pack_assets(pack_dirs)
    idx = have | (orig or set())
    errs, unknown = [], 0
    for rel, key, p in refs_in_pack(only_dir or pack_dirs[-1]):
        if p is None:
            errs.append("%s: %s 为空" % (rel, key))
            continue
        if any(c in p for c in "<>{}|[]") or "NN" in p:
            continue
        if not exists(p, idx):
            if orig is None and not exists(p, have):
                unknown += 1   # 没有原图仓库: 可能在原版里, 无法判断
            else:
                errs.append("%s: %s 引用的资源不存在: %s" % (rel, key, p))
    return errs, unknown


def main(argv):
    extra = None
    if argv[:1] == ["--pack"]:
        path = os.path.abspath(argv[1])
        extra = os.path.dirname(path)
        ids = [os.path.basename(path)]
    elif argv:
        ids = argv
    else:
        ids = sorted(e for e in os.listdir(cs.CONTENT) if os.path.isfile(os.path.join(cs.CONTENT, e, "manifest.json")))
    orig = original_index()
    rc = 0
    for pid in ids:
        order = cs.chain(pid, extra)
        dirs = [cs.pack_dir(i, extra) for i in order]
        errs, unknown = check_refs(dirs, orig, dirs[-1])
        print("[%s] %s%s" % (pid, "资源引用全部存在" if not errs else "%d 处资源缺失" % len(errs),
                             "; %d 处无法验证 (没有原图仓库, 路径不在包内 assets/)" % unknown if unknown else ""))
        for e in errs[:50]:
            print("  %s: %s" % (pid, e))
        rc |= bool(errs)
    if cs.errors:
        print("\n".join(cs.errors))
        rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

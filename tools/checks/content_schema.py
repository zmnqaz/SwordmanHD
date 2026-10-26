#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""内容包 schema 校验 (docs/内容格式.md): 纯 Python, 不需要 Godot 与原版资源, 几秒内跑完。

检查每个包 (含 base 链): manifest 必填字段与类型、数据表记录的键与字段类型、关卡/城镇/营地/地图/图层/单位/对白文件结构,
以及跨文件引用 (关卡单位的模板 id、宝物物品 id、地图格事件号、胜负条件单位下标、城镇商店、营地城镇、脚本与对白文件)。
改动包 (manifest.base 非空) 的数据表只写要改的记录, 所以记录只要求键, 其余字段有就校验类型; 整文件替换的文件 (stage.json 等) 要求完整。
以 "_" 开头的字段是注释, 忽略。

--strict (X2): 额外查 未知字段名 (拼错的 turn_event 等, 带近似建议)、rules.json 参数名/类型 (对照 params.gd 自动提取的参数表)、
资源路径存在性 (check_assets_refs.py)、.evs 里写保留/越界变量 (reserved_vars.py)。--trace-load: 打印加载顺序与每个文件/数据表/参数由哪个包提供、被谁覆盖。

用法: python3 tools/checks/content_schema.py [包名 ...]     默认校验 game/content/ 下的全部包
      python3 tools/checks/content_schema.py --pack 目录     校验任意目录里的包 (base 包仍到 game/content/ 找)
两者都可加 --report 文件                          结果写 UTF-8 文件 (Godot 调用时中文 stdout 会乱)
        以及 --strict / --trace-load (见上)
退出码 0 通过, 1 有错误。
"""
import difflib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/
import _boot  # noqa: E402,F401  (check_assets_refs / params_table / reserved_vars 在 tools/ 顶层, 内部按需 import)
HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "game", "content")

# ---- 类型规格: "int" "str" "bool" "num" "list" "dict" "any", 后缀 "?" 可缺省, "|null" 可为 null; 嵌套: dict 规格 / ["元素规格"] ----
FORMAT = "tdj-content/1"
VERSION_RE = re.compile(r"^\d+(\.\d+)*$")   # 点分数字版本 (与 content_compat.gd 一致)


def engine_version():
    """引擎版本 = game/engine/content/content_compat.gd 的 ENGINE_VERSION (唯一来源)"""
    p = os.path.join(os.path.dirname(CONTENT), "engine", "content", "content_compat.gd")
    m = re.search(r'const ENGINE_VERSION := "([^"]+)"', open(p, encoding="utf-8").read())
    return m.group(1) if m else None


def vcmp(a, b):
    pa = [int(x) for x in a.split(".")]
    pb = [int(x) for x in b.split(".")]
    n = max(len(pa), len(pb))
    pa += [0] * (n - len(pa))
    pb += [0] * (n - len(pb))
    return (pa > pb) - (pa < pb)

STRICT = False   # --strict: 未知字段报错 (check(..., strict=True) 设置)

# manifest.start (X1): 新游戏起点。kind = stage (进第 id 关战场) | town (进第 id 个城镇的入口 entry); gold = 起始金钱 (缺省取 rules 参数 initial_gold); movie = 开场过场号 (缺省不播)
START = {"kind": "str", "id": "int", "entry": "int?", "gold": "int?", "movie": "int?"}
MANIFEST = {"format": "str", "id": "str", "name": "str", "version": "str", "base": "list?", "description": "str?",
            "asset_roots": "list?", "stage_count": "int?", "town_count": "int?", "ending_movies": "list?",
            "tables": "dict?", "import_warnings": "list?",
            "engine_min": "str?", "engine_max": "str?", "save_compat_min": "str?", "save_neutral": "bool?",
            "start": "dict?"}
TABLE_REF = {"file": "str", "key": "str"}
CELL_RECT = ["int"]
STAGE = {
    "id": "int", "name": "str", "music": "int",
    "briefing": {"title": "str", "win": "str", "lose": "str"},
    "assets": {"dir": "str", "title_card": "str|null", "battle_floor": "str|null", "event_anims": "dict"},
    "turn_events": [{"turn": "int", "timing": "int", "event": "int"}],
    "map_events": [{"index": "int", "type": "int", "trigger": "int", "event": "int", "item_type": "int", "item": "int",
                    "prompt": "int", "show": "int"}],
    "judge": {"win": [{"type": "int", "unit": "int", "event": "int"}], "lose": [{"type": "int", "unit": "int", "event": "int"}]},
    "script": {"source": "str?", "raw": "str?"},
    "text": "str",
}
STAGE_MAP = {"width": "int", "height": "int", "terrain": [CELL_RECT], "floor": [CELL_RECT], "event": [CELL_RECT]}
LAYER_BG = {"layer": "int", "z": "int", "view": ["int"], "draw_layer": "int", "file": "str", "image": "str|null?", "anim": "str|null?"}
LAYER_OBJ = {"layer": "int", "tag": "int", "x": "int", "y": "int", "flag_var": "int", "play_mode": "int", "delay": "int",
             "hidden": "int?", "file": "str", "anim": "str|null"}
STAGE_LAYERS = {"backgrounds": [LAYER_BG], "objects": [LAYER_OBJ]}
STAGE_UNIT = {"index": "int", "unit_id": "int", "x": "int?", "y": "int?", "lv": "int", "hp_add": "int", "hp_sub": "int",
              "mp_add": "int", "mp_sub": "int", "str": "int", "int": "int", "avg": "int", "vit": "int", "luk": "int",
              "spirit": "dict", "weapon": "int|null", "armor": "int|null", "accessory": "int|null", "items": ["int"],
              "skills": ["int"], "event_parm": ["int"], "kill_get_type": "int", "kill_get_parm": "int", "kill_event": "int",
              "ai": "int", "ai_target": ["int"],
              "xy_unit_id": "int?", "unknown44": "any?", "unknown48_57": "any?"}   # 后三个: 导入工具保留的原版未知字节/坐标来源, 引擎不读
TEXT = {"groups": [["str"]]}
TOWN = {
    "id": "int",
    "assets": {"dir": "str", "map_file": "str?", "map_image": "str|null"},
    "entries": [{"music": "int", "map_x": "int", "map_y": "int", "x": "int", "y": "int", "dir": "int"}],
    "shops": ["str"],
    "script": {"source": "str?", "raw": "str?"},
    "text": "str",
}
TOWN_MAP = {"width": "int", "height": "int", "block": [CELL_RECT], "talk": [CELL_RECT], "step": [CELL_RECT]}
TOWN_LAYERS = {"objects": [{"layer": "int", "tag": "int", "x": "int", "y": "int", "flag_var": "int", "play_mode": "int", "file": "str",
                            "delay": "int?", "hidden": "int?", "anim": "str|null?"}]}
CAMP = {"stage": "int", "background": "int", "town": "int", "town_entry": "int", "background_anim": "str|null"}

# 数据表: 表名 -> (键字段, 字段规格)。字段规格只列引擎确定会读、类型明确的字段; 其余字段不查
TABLES = {
    "units": ("id", {"id": "int", "name": "str", "attribute_defence_id": "int", "move_type": "int", "camp": "int", "hp": "int",
                     "mp": "int", "move": "int", "str": "int", "int": "int", "avg": "int", "vit": "int", "luk": "int",
                     "sprite": "int", "defence_type": "int", "attack_type": "int", "base_lv": "int", "base_exp": "int"}),
    "items": ("id", {"id": "int", "name": "str", "desc": "str", "type": "int", "equip_units": "list", "attack": "int",
                     "defence": "int", "price": "int", "attack_range": "dict", "attribute_defence": "dict", "use": "dict"}),
    "skills": ("id", {"id": "int", "name": "str", "desc": "str", "kind": "any", "target": "int", "range": "dict", "mp_cost": "int",
                      "power": "int", "attribute": "int", "spirit_addition": "list"}),
    "levelup": ("unit_id", {"unit_id": "int", "hp_rand": "int", "mp_rand": "int", "skills": "list"}),
    "party_init": ("unit_id", {"unit_id": "int", "lv": "int", "exp": "int", "hp": "int", "mp": "int", "spirit": "dict",
                               "weapon": "int|null", "armor": "int|null", "accessory": "int|null", "in_team": "any",
                               "spirit_points": "int", "items": "list", "skills": "list"}),
    "attribute_defense": ("index", {"index": "int", "values": "dict"}),
    "terrain": ("move_type", {"move_type": "int", "cost": "dict"}),
    "shops": ("id", {"id": "str", "type": "int", "keeper": "int", "items": ["int"], "keeper_anim": "str|null"}),
    "camps": ("stage", CAMP),
}

errors = []


def err(where, msg):
    errors.append("%s: %s" % (where, msg))


def _is(v, t):
    if t == "any":
        return True
    if t == "int":
        return isinstance(v, int) and not isinstance(v, bool)
    if t == "num":
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    if t == "str":
        return isinstance(v, str)
    if t == "bool":
        return isinstance(v, bool)
    if t == "list":
        return isinstance(v, list)
    if t == "dict":
        return isinstance(v, dict)
    raise ValueError("未知类型规格 " + t)


def validate(v, spec, where, partial=False, closed=True):
    """按规格校验 v, 错误记入 errors。partial: 字段可缺 (改动包的记录), 有就校验类型"""
    if isinstance(spec, str):
        opt = spec.endswith("?")
        spec = spec.rstrip("?")
        if v is None:
            return
        for t in spec.split("|"):
            if t == "null":
                continue
            if _is(v, t):
                return
        err(where, "类型应为 %s, 实际 %s (%r)" % (spec, type(v).__name__, str(v)[:40]))
        return
    if isinstance(spec, list):
        if not isinstance(v, list):
            err(where, "应为数组, 实际 %s" % type(v).__name__)
            return
        for i, e in enumerate(v):
            validate(e, spec[0], "%s[%d]" % (where, i), partial, closed)
            if len(errors) > 400:
                return
        return
    if not isinstance(v, dict):
        err(where, "应为对象, 实际 %s" % type(v).__name__)
        return
    if STRICT:
        unknown_fields(v, spec, where, closed)
    for k, s in spec.items():
        if k not in v:
            if isinstance(s, str) and (s.endswith("?") or partial):
                continue
            if partial:
                continue
            err(where, "缺字段 %s" % k)
            continue
        if v[k] is None and isinstance(s, str) and "null" not in s.split("|") and not s.endswith("?"):
            err("%s.%s" % (where, k), "不能为 null")
            continue
        validate(v[k], s, "%s.%s" % (where, k), partial, closed)


def unknown_fields(v, spec, where, closed):
    """--strict: 对象里规格没有的字段 (非 _ 开头)。closed=False (数据表记录: 规格只列了引擎确定会读的字段, 其余合法字段很多)
    只报「和某个规格字段很像」的 (拼错), 不报其他"""
    for k in v:
        if not isinstance(k, str) or k.startswith("_") or k in spec:
            continue
        m = difflib.get_close_matches(k, list(spec), n=1, cutoff=0.9 if not closed else 0.6)
        if closed or m:
            err("%s.%s" % (where, k), "未知字段 %s%s (引擎会静默忽略)" % (k, ", 你是不是想写 %s" % m[0] if m else ""))


def load_json(path, where):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        err(where, "文件不存在")
    except ValueError as e:
        err(where, "JSON 解析失败: %s" % e)
    return None


def pack_dir(pid, extra=None):
    for root in ([extra] if extra else []) + [CONTENT, os.path.join(CONTENT, "templates")]:
        d = os.path.join(root, pid)
        if os.path.isfile(os.path.join(d, "manifest.json")):
            return d
    return None


def _missing_base(pid, extra=None, seen=()):
    """pid 的 base 链里找不到的包 id 列表 (不报错, 只查)"""
    d = pack_dir(pid, extra)
    if d is None:
        return [pid] if seen else []
    try:
        with open(os.path.join(d, "manifest.json"), encoding="utf-8") as f:
            bases = json.load(f).get("base", [])
    except (OSError, ValueError):
        return []
    out = []
    for b in bases:
        if b in seen:
            continue
        out += _missing_base(b, extra, seen + (pid,)) if pack_dir(b, extra) else [b]
    return out


def chain(pid, extra=None, seen=None):
    """base 递归展开 (基础包在前)"""
    seen = seen or []
    if pid in seen:
        err(pid, "base 循环依赖")
        return []
    d = pack_dir(pid, extra)
    if d is None:
        err(pid, "找不到包目录")
        return []
    m = load_json(os.path.join(d, "manifest.json"), pid + "/manifest.json") or {}
    out = []
    for b in m.get("base", []):
        for x in chain(b, extra, seen + [pid]):
            if x not in out:
                out.append(x)
    out.append(pid)
    return out


def rel_exists(dirs, rel):
    return any(os.path.isfile(os.path.join(d, rel)) for d in dirs)


def find(dirs, rel):
    for d in reversed(dirs):
        p = os.path.join(d, rel)
        if os.path.isfile(p):
            return p
    return None


def check_versions(m, w):
    """manifest 的版本字段: version (包版本, 必填)、engine_min/engine_max/save_compat_min (可选) 都是点分数字; 引擎版本须落在要求范围内"""
    for k in ("version", "engine_min", "engine_max", "save_compat_min"):
        v = m.get(k)
        if isinstance(v, str) and not VERSION_RE.match(v):
            err(w + "/manifest", "%s=%r 不是点分数字版本号 (如 1.0.0)" % (k, v))
    ev = engine_version()
    if ev is None:
        return
    lo, hi = m.get("engine_min"), m.get("engine_max")
    if isinstance(lo, str) and VERSION_RE.match(lo) and vcmp(ev, lo) < 0:
        err(w + "/manifest", "engine_min %s 高于当前引擎 %s, 引擎不会加载本包" % (lo, ev))
    if isinstance(hi, str) and VERSION_RE.match(hi) and vcmp(ev, hi) > 0:
        err(w + "/manifest", "engine_max %s 低于当前引擎 %s, 引擎不会加载本包" % (hi, ev))
    v, c = m.get("version"), m.get("save_compat_min")
    if isinstance(v, str) and isinstance(c, str) and VERSION_RE.match(v) and VERSION_RE.match(c) and vcmp(c, v) > 0:
        err(w + "/manifest", "save_compat_min %s 高于包自己的 version %s" % (c, v))


def check_pack(pid, dirs_by_id, order):
    """校验一个包自带的文件; order = 加载顺序里到本包为止的包 id (用于合并视图的跨文件引用)"""
    d = dirs_by_id[pid]
    dirs = [dirs_by_id[i] for i in order]
    w = pid
    m = load_json(os.path.join(d, "manifest.json"), w + "/manifest.json")
    if not isinstance(m, dict):
        return
    validate(m, MANIFEST, w + "/manifest")
    if m.get("format") != FORMAT:
        err(w + "/manifest", "format 应为 %s" % FORMAT)
    if m.get("id") != pid:
        err(w + "/manifest", "id (%s) 必须等于目录名 (%s)" % (m.get("id"), pid))
    check_versions(m, w)
    partial = bool(m.get("base"))
    for name, t in (m.get("tables") or {}).items():
        validate(t, TABLE_REF, "%s/manifest.tables.%s" % (w, name))

    # 合并后的表声明 (后加载覆盖/追加)
    tables = {}
    for i in order:
        mm = load_json(os.path.join(dirs_by_id[i], "manifest.json"), i + "/manifest.json") or {}
        tables.update(mm.get("tables") or {})
    for name, t in tables.items():
        if name not in TABLES or not isinstance(t, dict):
            continue
        p = os.path.join(d, t.get("file", ""))
        if not os.path.isfile(p):
            continue  # 本包没有这个表文件 (沿用基础包)
        rows = load_json(p, "%s/%s" % (w, t["file"]))
        key, spec = TABLES[name]
        if rows is None:
            continue
        if not isinstance(rows, list):
            err("%s/%s" % (w, t["file"]), "数据表应为数组")
            continue
        seen = set()
        for i, r in enumerate(rows):
            wr = "%s/%s[%d]" % (w, t["file"], i)
            if not isinstance(r, dict) or key not in r:
                err(wr, "记录缺合并键 %s" % key)
                continue
            if r[key] in seen:
                err(wr, "键 %s=%r 重复" % (key, r[key]))
            seen.add(r[key])
            if r.get("_delete") is True:
                continue
            validate(r, spec, wr, partial=partial, closed=False)

    def table_keys(name):
        t = tables.get(name)
        keys = set()
        for i in order:
            p = os.path.join(dirs_by_id[i], t["file"]) if t else None
            if p and os.path.isfile(p):
                try:
                    for r in json.load(open(p, encoding="utf-8")):
                        if r.get("_delete") is True:
                            keys.discard(r.get(t["key"]))
                        else:
                            keys.add(r.get(t["key"]))
                except (ValueError, AttributeError):
                    pass
        return keys

    unit_ids, item_ids = table_keys("units"), table_keys("items")
    shop_ids = table_keys("shops")

    stage_count = max([int((load_json(os.path.join(dirs_by_id[i], "manifest.json"), "") or {}).get("stage_count", 0)) for i in order] + [0])
    town_count = max([int((load_json(os.path.join(dirs_by_id[i], "manifest.json"), "") or {}).get("town_count", 0)) for i in order] + [0])

    check_start(m, w, stage_count, town_count, dirs, d)
    for n in range(stage_count):
        sd = os.path.join(d, "stages", "%02d" % n)
        if not os.path.isdir(sd):
            continue
        check_stage(w, n, sd, dirs, unit_ids, item_ids, partial)
    for n in range(town_count):
        td = os.path.join(d, "towns", "%02d" % n)
        if os.path.isdir(td):
            check_town(w, n, td, dirs, shop_ids)
    # 目录名超出 stage_count 的关卡 (改动包忘了改 manifest)
    for sub, cnt in (("stages", stage_count), ("towns", town_count)):
        sdir = os.path.join(d, sub)
        if os.path.isdir(sdir):
            for e in os.listdir(sdir):
                if e.isdigit() and int(e) >= cnt:
                    err("%s/%s/%s" % (w, sub, e), "编号超出 manifest.%s (%d), 引擎不会加载" % (sub[:-1] + "_count", cnt))

    cp = os.path.join(d, "camps", "camps.json")
    if os.path.isfile(cp):
        for i, c in enumerate(load_json(cp, w + "/camps/camps.json") or []):
            if isinstance(c, dict) and isinstance(c.get("town"), int) and c["town"] >= town_count:
                err("%s/camps/camps.json[%d]" % (w, i), "town %d 超出 town_count %d" % (c["town"], town_count))
    sp = os.path.join(d, "text", "system.json")
    if os.path.isfile(sp):
        v = load_json(sp, w + "/text/system.json")
        if isinstance(v, dict):
            for k, t in v.items():
                if not k.startswith("_"):
                    validate(t, [["str"]], "%s/text/system.json.%s" % (w, k))
    rp = os.path.join(d, "rules.json")
    if os.path.isfile(rp):
        v = load_json(rp, w + "/rules.json")
        if isinstance(v, dict):
            validate(v, {"format": "str", "params": "dict"}, w + "/rules")
            if v.get("format") != "tdj-rules/1":
                err(w + "/rules", "format 应为 tdj-rules/1")
            if STRICT and isinstance(v.get("params"), dict):
                check_rules_params(v["params"], w + "/rules.json")
    for lp in (os.path.join(d, "ui_theme", "layout.json"), os.path.join(d, "ui_theme", "theme.json")):
        if os.path.isfile(lp):
            v = load_json(lp, w + "/ui_theme/" + os.path.basename(lp))
            if v is not None and not isinstance(v, dict):
                err(w + "/ui_theme/" + os.path.basename(lp), "应为对象")
    if STRICT:
        strict_pack_checks(w, d, dirs, merged_rows("skills", tables, order, dirs_by_id, "id"))


def merged_rows(name, tables, order, dirs_by_id, default_key):
    """按键合并 (深合并/_delete) 之后的数据表记录列表, 供需要看内容的检查用 (如召唤技能的标志变量)"""
    t = tables.get(name)
    if not t:
        return []
    key = t.get("key", default_key)
    out = {}
    for i in order:
        p = os.path.join(dirs_by_id[i], t["file"])
        if not os.path.isfile(p):
            continue
        try:
            rows = json.load(open(p, encoding="utf-8"))
        except ValueError:
            continue
        for r in rows if isinstance(rows, list) else []:
            if not isinstance(r, dict) or key not in r:
                continue
            if r.get("_delete") is True:
                out.pop(r[key], None)
            else:
                out[r[key]] = dict(out.get(r[key], {}), **r)
    return list(out.values())


def check_start(m, w, stage_count, town_count, dirs, d):
    """manifest.start (X1): 新游戏起点。只检查本包写了 start 的情形 (取值范围按合并后的关数/城镇数)"""
    st = m.get("start")
    if st is None:
        return
    validate(st, START, w + "/manifest.start")
    if not isinstance(st, dict):
        return
    if st.get("kind") not in ("stage", "town"):
        err(w + "/manifest.start.kind", "应为 stage 或 town, 实际 %r" % st.get("kind"))
    n = st.get("id")
    if isinstance(n, int):
        cnt, what = (stage_count, "stage_count") if st.get("kind") == "stage" else (town_count, "town_count")
        if st.get("kind") in ("stage", "town") and not 0 <= n < cnt:
            err(w + "/manifest.start.id", "%d 超出 %s (%d)" % (n, what, cnt))
    if st.get("kind") == "stage" and st.get("entry") is not None:
        err(w + "/manifest.start.entry", "entry 只用于 kind=town")
    if isinstance(st.get("gold"), int) and st["gold"] < 0:
        err(w + "/manifest.start.gold", "金钱不能为负")


def check_rules_params(params, where):
    """--strict: rules.json 的参数名与类型对照 params.gd (params_table.py 自动提取, 不手抄)"""
    import params_table
    table = params_table.load_params()
    for k, msg in params_table.check_params(params, table):
        err("%s.params.%s" % (where, k), msg)


def strict_pack_checks(w, d, dirs, merged_skills):
    """--strict 的包级检查: 资源路径存在性、.evs 写保留/越界变量"""
    import check_assets_refs
    import compile_events
    import reserved_vars
    errs, _unknown = check_assets_refs.check_refs(dirs, only_dir=d)
    for e in errs:
        err("%s/%s" % (w, e.split(": ", 1)[0]), e.split(": ", 1)[1])
    stage_count = 0
    for dd in dirs:
        mm = load_json(os.path.join(dd, "manifest.json"), "") or {}
        stage_count = max(stage_count, int(mm.get("stage_count", 0) or 0))
    sdir = os.path.join(d, "scripts")
    if not os.path.isdir(sdir):
        return
    for f in sorted(os.listdir(sdir)):
        if not f.endswith(".evs"):
            continue
        rel = "%s/scripts/%s" % (w, f)
        try:
            uses = compile_events.lint_vars(open(os.path.join(sdir, f), encoding="utf-8").read(), rel)
        except compile_events.ScriptError as e:
            err(rel, "脚本解析失败: %s" % e)
            continue
        for no, name, pname, var, is_write in uses:
            c = reserved_vars.classify(var, stage_count, merged_skills)
            if c is None or (c[0] == "tdj"):
                continue
            if c[0] == "range":
                err("%s:%d" % (rel, no), "%s %s=%d: %s" % (name, pname, var, c[1]))
            elif is_write:
                err("%s:%d" % (rel, no), "%s 写入保留变量 %s=%d: %s (见 docs/保留变量表.md)" % (name, pname, var, c[1]))


def grid_ok(g, wd, ht, where):
    if not isinstance(g, list) or len(g) != ht:
        err(where, "行数应为 height=%d" % ht)
        return
    for y, row in enumerate(g):
        if not isinstance(row, list) or len(row) != wd:
            err("%s[%d]" % (where, y), "列数应为 width=%d" % wd)
            return


def check_stage(w, n, sd, dirs, unit_ids, item_ids, partial):
    tag = "%s/stages/%02d" % (w, n)
    s = load_json(os.path.join(sd, "stage.json"), tag + "/stage.json") if os.path.isfile(os.path.join(sd, "stage.json")) else None
    if s is None:
        return
    validate(s, STAGE, tag + "/stage.json")
    if isinstance(s.get("id"), int) and s["id"] != n:
        err(tag + "/stage.json", "id %d 与目录 %d 不一致" % (s["id"], n))
    sc = s.get("script") or {}
    if isinstance(sc, dict) and not sc.get("source") and not sc.get("raw"):
        err(tag + "/stage.json.script", "source 与 raw 至少要有一个")
    for k in ("source", "raw"):
        if isinstance(sc, dict) and sc.get(k) and not rel_exists(dirs, sc[k]):
            err(tag + "/stage.json.script." + k, "文件不存在: %s" % sc[k])
    if isinstance(s.get("text"), str) and not rel_exists(dirs, s["text"]):
        err(tag + "/stage.json.text", "文件不存在: %s" % s["text"])
    # 单位
    up = os.path.join(sd, "units.json")
    units = load_json(up, tag + "/units.json") if os.path.isfile(up) else None
    n_units = 0
    if units is not None:
        validate(units, [STAGE_UNIT], tag + "/units.json")
        n_units = len(units) if isinstance(units, list) else 0
        for i, u in enumerate(units if isinstance(units, list) else []):
            if isinstance(u, dict):
                if u.get("index") != i:
                    err("%s/units.json[%d]" % (tag, i), "index 应等于下标 %d" % i)
                if isinstance(u.get("unit_id"), int) and unit_ids and u["unit_id"] not in unit_ids:
                    err("%s/units.json[%d]" % (tag, i), "unit_id %d 不在 units 表" % u["unit_id"])
                for k in ("weapon", "armor", "accessory"):
                    if isinstance(u.get(k), int) and item_ids and u[k] not in item_ids:
                        err("%s/units.json[%d].%s" % (tag, i, k), "物品 %d 不在 items 表" % u[k])
    # 地图
    mp = os.path.join(sd, "map.json")
    mevents = set()
    for e in s.get("map_events") or []:
        if isinstance(e, dict) and isinstance(e.get("index"), int):
            mevents.add(e["index"])
            if e.get("type") == 1 and e.get("item_type") == 1 and item_ids and e.get("item") not in item_ids:
                err(tag + "/stage.json.map_events", "宝物物品 %s 不在 items 表" % e.get("item"))
    if os.path.isfile(mp):
        mv = load_json(mp, tag + "/map.json")
        if mv is not None:
            validate(mv, STAGE_MAP, tag + "/map.json")
            if isinstance(mv, dict) and isinstance(mv.get("width"), int) and isinstance(mv.get("height"), int):
                for k in ("terrain", "floor", "event"):
                    grid_ok(mv.get(k), mv["width"], mv["height"], "%s/map.json.%s" % (tag, k))
                ev = mv.get("event")
                if isinstance(ev, list):
                    bad = {c for row in ev if isinstance(row, list) for c in row if isinstance(c, int) and c and c not in mevents}
                    if bad:
                        err(tag + "/map.json.event", "地图格引用了不存在的 map_events 下标 %s" % sorted(bad)[:8])
                # 出场格越出地图在原版数据里很常见 (由脚本放置), 不查
    for j in ((s.get("judge") or {}).get("win", []) + (s.get("judge") or {}).get("lose", [])) if isinstance(s.get("judge"), dict) else []:
        if isinstance(j, dict) and isinstance(j.get("unit"), int) and units is not None and j["unit"] >= n_units:
            err(tag + "/stage.json.judge", "单位下标 %d 超出 units (%d 个)" % (j["unit"], n_units))
    lp = os.path.join(sd, "layers.json")
    if os.path.isfile(lp):
        lv = load_json(lp, tag + "/layers.json")
        if lv is not None:
            validate(lv, STAGE_LAYERS, tag + "/layers.json")
    tp = os.path.join(sd, "text.json")
    if os.path.isfile(tp):
        tv = load_json(tp, tag + "/text.json")
        if tv is not None:
            validate(tv, TEXT, tag + "/text.json")


def check_town(w, n, td, dirs, shop_ids):
    tag = "%s/towns/%02d" % (w, n)
    tp = os.path.join(td, "town.json")
    t = load_json(tp, tag + "/town.json") if os.path.isfile(tp) else None
    if t is not None:
        validate(t, TOWN, tag + "/town.json")
        if isinstance(t.get("id"), int) and t["id"] != n:
            err(tag + "/town.json", "id %d 与目录 %d 不一致" % (t["id"], n))
        for sid in t.get("shops") or []:
            if shop_ids and sid not in shop_ids:
                err(tag + "/town.json.shops", "商店 %s 不在 shops 表" % sid)
        sc = t.get("script") or {}
        if isinstance(sc, dict):
            if not sc.get("source") and not sc.get("raw"):
                err(tag + "/town.json.script", "source 与 raw 至少要有一个")
            for k in ("source", "raw"):
                if sc.get(k) and not rel_exists(dirs, sc[k]):
                    err(tag + "/town.json.script." + k, "文件不存在: %s" % sc[k])
        if isinstance(t.get("text"), str) and not rel_exists(dirs, t["text"]):
            err(tag + "/town.json.text", "文件不存在: %s" % t["text"])
    mp = os.path.join(td, "map.json")
    if os.path.isfile(mp):
        mv = load_json(mp, tag + "/map.json")
        if mv is not None:
            validate(mv, TOWN_MAP, tag + "/map.json")
            if isinstance(mv, dict) and isinstance(mv.get("width"), int) and isinstance(mv.get("height"), int):
                for k in ("block", "talk", "step"):
                    grid_ok(mv.get(k), mv["width"], mv["height"], "%s/map.json.%s" % (tag, k))
    lp = os.path.join(td, "layers.json")
    if os.path.isfile(lp):
        lv = load_json(lp, tag + "/layers.json")
        if lv is not None:
            validate(lv, TOWN_LAYERS, tag + "/layers.json")


def check(pack_ids, extra=None, strict=False):
    """校验若干包 (含各自 base 链里的每个包), 返回错误列表。strict: 见文件头 --strict"""
    global STRICT
    STRICT = strict
    del errors[:]
    order, dirs = [], {}
    for pid in pack_ids:
        for x in chain(pid, extra):
            if x not in order:
                order.append(x)
                dirs[x] = pack_dir(x, extra)
    for i, pid in enumerate(order):
        if dirs.get(pid):
            check_pack(pid, dirs, order[: i + 1])
    return list(errors)


def main(argv):
    extra, report = None, None
    strict = "--strict" in argv
    trace = "--trace-load" in argv
    argv = [a for a in argv if a not in ("--strict", "--trace-load")]
    if "--report" in argv:
        # 结果写文件 (UTF-8): Godot 在 Windows 上按 ANSI 代码页解码子进程 stdout, 中文会乱, 机器消费走文件
        i = argv.index("--report")
        report, argv = argv[i + 1], argv[:i] + argv[i + 2:]
    if argv[:1] == ["--pack"]:
        path = os.path.abspath(argv[1])
        extra = os.path.dirname(path)
        ids = [os.path.basename(path)]
    elif argv:
        ids = argv
    else:
        ids = sorted(e for e in os.listdir(CONTENT) if os.path.isfile(os.path.join(CONTENT, e, "manifest.json")))
    # 依赖的基础包不在 (典型: 原版内容包 tdj 是生成物, 干净克隆里没有) -> 这些包无法校验, 友好跳过而不是报「找不到包目录」
    skipped = [i for i in ids if _missing_base(i, extra)]
    if skipped and not extra and not any(a for a in argv):
        ids = [i for i in ids if i not in skipped]
        require = os.environ.get("CI_REQUIRE_ORIGINAL") == "1"
        print("%s: content_schema 跳过 %s: 基础包 %s 不在 (由资源生成工具 生成)" % (
            "FAIL" if require else "SKIP", ", ".join(skipped), ", ".join(sorted({m for i in skipped for m in _missing_base(i, extra)}))))
        if require:
            return 1
        if not ids:
            return 0
    if trace:
        import content_trace
        text = content_trace.trace(ids, extra)
        if report:
            open(report, "w", encoding="utf-8", newline="\n").write(text)
        else:
            sys.stdout.write(text)
        return 0
    errs = check(ids, extra, strict)
    lines = ["[schema] " + e for e in errs[:200]]
    if len(errs) > 200:
        lines.append("[schema] ... 另有 %d 个错误" % (len(errs) - 200))
    lines.append("内容包 schema 校验%s: %s -> %s" % (" (strict)" if strict else "", ", ".join(ids), "通过" if not errs else "%d 个错误" % len(errs)))
    text = "\n".join(lines) + "\n"
    if report:
        with open(report, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0 if not errs else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

# SPDX-License-Identifier: GPL-3.0-only
class_name ContentDB
extends Node
## 内容包加载层 (autoload "Content")。运行时的游戏内容只从这里取 (docs/内容格式.md):
##   数据表 (单位/物品/技能/成长/抗性/地形/商店/营地)、关卡、城镇、剧情脚本 (.evs, 运行时编译)、对白、系统文本、
##   界面主题、规则参数 (各包 rules.json), 以及包内 assets/ 对资源路径的覆盖。
## 加载顺序: 主包 (默认见 default_main(): content/content.json 的 "main") 按 manifest.base 递归展开 (基础包在前), 再依次叠加改动包。后加载的覆盖先加载的:
##   普通文件同路径整个替换; manifest.tables 列出的数据表按键逐条深合并 (_delete 删除); text/system.json 按表名替换。
## 选包: 命令行 (-- 之后) --content=<主包> --mods=<包1>,<包2>; 或 user://settings.json 的 "mods": [...]。
## 包目录在 res://content/<id>、res://content/templates/<id> 或 user://content/<id> (靠前者优先)。
## 测试/工具可以 ContentDB.new() 后 load_packs([...]) 单独建一份, 不影响 autoload。

const FORMAT := "tdj-content/1"
const SEARCH_DIRS := ["res://content", "res://content/templates", "user://content"]   # templates/: 随引擎发布的内容包模板 (如 minimal_game), 可直接 --content= 选用
const CONFIG_FILE := "content.json"   # 包目录根下的配置 {"main": "<缺省主包 id>"}: 缺省主包由配置决定, 引擎代码里不写包名
const Params = preload("res://engine/rules/params.gd")

signal reloaded

var packs: Array = []        # [{id, dir, manifest}], 加载顺序 (基础包在前)
var manifest := {}           # 合并后的 manifest: stage_count/town_count 取最大, tables 合并, 其余后者覆盖
var errors: Array = []       # 加载时的错误 (找不到包、格式不对、脚本编译错误)
var _json := {}              # 绝对路径 -> 解析结果
var _live_groups := {}        # 对白表相对路径 -> 已经发给关卡/城镇对象的那个数组 (切语言时原地换内容, 对象手里的引用自动是新语言)
var _json_l := {}            # 语言叠加后的结果缓存: "<lang>@<相对路径>" -> 合并结果 (切换语言时清)
var _sys_l := {}             # 语言叠加后的系统文本: "<包下标>:<表名>" -> 句子表
## 当前语言: "" = 缺省 (简体, 不读叠加层); "hant" = 繁体。叠加层在包内 locale/<lang>/<同路径> (docs/设计_繁简切换.md)
var lang := ""
var _tables := {}            # 表名 -> {"key": 字段, "order": [键], "by_key": {键: 记录}}
var _arrays := {}            # 表名 -> 下标 = 键 的数组 (整数键的表)
var _scripts := {}           # 脚本引用 -> 编译结果
var _stages := {}            # 关卡号 -> BattleStage 用的结构缓存 (见 stage_raw)
var _assets := {}            # 小写相对路径 -> 包内 assets/ 下的文件路径 (后加载的包覆盖)


## 缺省主包 id: SEARCH_DIRS 里第一个 content.json 的 "main"; 都没有则取第一个没有 base 的包 (目录名排序); 一个包也没有返回 ""
static func default_main(dirs: Array = SEARCH_DIRS) -> String:
	for d in dirs:
		var c = _read_json_file(String(d).path_join(CONFIG_FILE))
		if c is Dictionary and String(c.get("main", "")) != "":
			return String(c["main"])
	for d in dirs:
		var da := DirAccess.open(d)
		if da == null:
			continue
		var ids := Array(da.get_directories())
		ids.sort()
		for id in ids:
			var m = _read_json_file(String(d).path_join(id).path_join("manifest.json"))
			if m is Dictionary and (m.get("base", []) as Array).is_empty():
				return String(id)
	return ""


func _ready() -> void:
	var main := default_main()
	var mods: Array = []
	var s = _read_json_file("user://settings.json")
	if s is Dictionary and s.get("mods") is Array:
		mods = s["mods"].filter(func(m): return m is String and m != "")  # 手改的设定文件里混进非字符串元素: 丢掉, 不让加载出错
	var dbg := DebugArgs.current()
	if dbg.content_main != "":   # 命令行 --content= / --mods= 优先
		main = dbg.content_main
	if dbg.mods != null:
		mods = dbg.mods
	load_packs([main] + mods)
	print("Content: %s" % ", ".join(packs.map(func(p): return "%s %s" % [p["id"], p["manifest"].get("version", "")])))
	for e in errors:
		push_error("Content: " + e)


# ---------------------------------------------------------------- 加载

## 按顺序加载包 (每个包先递归加载它的 base)。返回是否没有错误。
func load_packs(ids: Array) -> bool:
	packs.clear()
	manifest = {}
	errors.clear()
	_json.clear()
	_json_l.clear()
	_sys_l.clear()
	_tables.clear()
	_arrays.clear()
	_scripts.clear()
	_stages.clear()
	_assets.clear()
	for id in ids:
		_add_pack(String(id), [])
	_build_manifest()
	_build_tables()
	_index_assets()
	_refresh_live_groups()
	reloaded.emit()
	return errors.is_empty()


func pack_dir(id: String) -> String:
	for d in SEARCH_DIRS:
		var p: String = d.path_join(id)
		if FileAccess.file_exists(p.path_join("manifest.json")):
			return p
	return ""


func _add_pack(id: String, chain: Array) -> void:
	for p in packs:
		if p["id"] == id:
			return
	if id in chain:
		errors.append("内容包循环依赖: %s" % " -> ".join(chain + [id]))
		return
	var dir := pack_dir(id)
	if dir == "":
		errors.append("找不到内容包 %s (%s)" % [id, ", ".join(SEARCH_DIRS)])
		return
	var m = _read_json_file(dir.path_join("manifest.json"))
	if not m is Dictionary or String(m.get("format", "")) != FORMAT:
		errors.append("内容包 %s 的 manifest.json 不是 %s" % [id, FORMAT])
		return
	var engine_err := ContentCompat.engine_error(m)
	if engine_err != "":
		errors.append(engine_err)
		return
	for b in m.get("base", []):
		_add_pack(String(b), chain + [id])
	packs.append({"id": id, "dir": dir, "manifest": m})


func _build_manifest() -> void:
	var tables := {}
	for p in packs:
		var m: Dictionary = p["manifest"]
		for k in m:
			if k == "tables":
				for t in m["tables"]:
					tables[t] = m["tables"][t]
			elif k in ["stage_count", "town_count"]:
				manifest[k] = maxi(int(manifest.get(k, 0)), int(m[k]))
			else:
				manifest[k] = m[k]
	manifest["tables"] = tables


## 后加载的包里有这个文件就用它 (整个文件替换); 都没有返回 ""
func find(rel: String) -> String:
	var i := _find_index(rel)
	return packs[i]["dir"].path_join(rel) if i >= 0 else ""


## 提供该文件的包 (后加载优先) 的下标, 没有返回 -1
func _find_index(rel: String) -> int:
	for i in range(packs.size() - 1, -1, -1):
		if FileAccess.file_exists(packs[i]["dir"].path_join(rel)):
			return i
	return -1


## 第 i 个包里该文件的语言叠加层路径 (当前语言缺省时返回 "")
func _locale_path(i: int, rel: String) -> String:
	return "" if lang == "" else String(packs[i]["dir"]).path_join("locale").path_join(lang).path_join(rel)


## 切换语言 ("" / "hans" = 简体缺省, "hant" = 繁体)。重建数据表与缓存, 发 reloaded (界面文案表据此重读);
## 已经建好的界面/单位对象保持旧文字, 下一个画面起是新语言; 对白例外 (text_groups 的数组原地换内容, 之后每一句马上是新语言)。
func set_lang(l: String) -> void:
	l = "" if l == "hans" else l
	if l == lang:
		return
	lang = l
	if packs.is_empty():   # 内容包还没加载 (启动时设定先于内容包应用): 只记下语言, load_packs 建表时就按它来
		return
	_json.clear()
	_json_l.clear()
	_sys_l.clear()
	_tables.clear()
	_arrays.clear()
	_stages.clear()
	_build_tables()
	_refresh_live_groups()
	reloaded.emit()


## 对白表 text_groups 发出去的数组换成当前语言的内容 (原地改: 关卡/城镇对象早就拿着这个数组, 之后每一句对白马上是新语言;
## 已经显示在屏幕上的那一句不动)
func _refresh_live_groups() -> void:
	for rel in _live_groups:
		var arr: Array = _live_groups[rel]
		arr.clear()
		arr.append_array(_groups_of(rel))


func has_file(rel: String) -> bool:
	return find(rel) != ""


## 包内 JSON (同路径整个替换)。缺文件返回 null。数字按 Godot JSON 解析为 float (与原先读 data/*.json 相同)。
func json(rel: String) -> Variant:
	var i := _find_index(rel)
	if i < 0:
		return null
	var out = _cached_json(String(packs[i]["dir"]).path_join(rel))
	if lang == "" or not out is Dictionary:
		return out
	var key := "%s@%s" % [lang, rel]
	if not _json_l.has(key):
		var merged: Dictionary = out
		for j in range(i, packs.size()):   # 提供该文件的包及其后加载的包的叠加层, 依次合上 (对象深合并, 数组整个替换)
			var lp := _locale_path(j, rel)
			var o = _cached_json(lp) if FileAccess.file_exists(lp) else null
			if o is Dictionary:
				merged = deep_merge(merged, o)
		_json_l[key] = merged
	return _json_l[key]


func _cached_json(p: String) -> Variant:
	if not _json.has(p):
		_json[p] = _read_json_file(p)
	return _json[p]


static func _read_json_file(p: String) -> Variant:
	if not FileAccess.file_exists(p):
		return null
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(p)) != OK:
		if not p.begins_with("user://"):  # 玩家目录里的文件 (settings.json) 写坏了是正常情形, 返回 null 由调用方回退缺省; 内容包文件坏了才是错误
			push_error("JSON 解析失败 %s (行 %d): %s" % [p, j.get_error_line(), j.get_error_message()])
		return null
	return j.data


## 把整数值的 float 递归转成 int (关卡/城镇结构用, 与原先解析二进制得到的 int 一致)
static func ints(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	if v is Array:
		return v.map(func(x): return ints(x))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = ints(v[k])
		return d
	return v


# ---------------------------------------------------------------- 数据表 (按键合并)

static func _key(v: Variant) -> Variant:
	if v is float or v is int:
		return int(v)
	return String(v)


## 深合并: 对象递归合并, 数组与标量整个替换
static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in over:
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = deep_merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


func _build_tables() -> void:
	for name in manifest["tables"]:
		var spec: Dictionary = manifest["tables"][name]
		var key := String(spec.get("key", "id"))
		var t := {"key": key, "order": [], "by_key": {}}
		for p in packs:
			var spec_p: Dictionary = p["manifest"].get("tables", {}).get(name, spec)
			var f: String = p["dir"].path_join(String(spec_p.get("file", spec["file"])))
			var recs = _read_json_file(f)
			if recs == null:
				continue
			if not recs is Array:
				errors.append("%s: 数据表必须是数组" % f)
				continue
			for r in recs:
				if not r is Dictionary or not r.has(key):
					errors.append("%s: 记录缺少键 %s" % [f, key])
					continue
				var k = _key(r[key])
				if r.get("_delete", false):
					t["by_key"].erase(k)
					t["order"].erase(k)
				elif t["by_key"].has(k):
					t["by_key"][k] = deep_merge(t["by_key"][k], r)
				else:
					t["by_key"][k] = r
					t["order"].append(k)
			if lang != "":   # 这个包的语言叠加层: 只合并已有的记录 (叠加层只写不同的文字, 不新增记录)
				var lrecs = _read_json_file(String(p["dir"]).path_join("locale").path_join(lang).path_join(String(spec_p.get("file", spec["file"]))))
				if lrecs is Array:
					for r in lrecs:
						if r is Dictionary and r.has(key) and t["by_key"].has(_key(r[key])):
							t["by_key"][_key(r[key])] = deep_merge(t["by_key"][_key(r[key])], r)
		_tables[name] = t


func has_table(name: String) -> bool:
	return _tables.has(name)


## 表的全部记录 (加载顺序: 基础包的顺序, 新增的接在后面)
func table(name: String) -> Array:
	var t: Dictionary = _tables.get(name, {})
	return t.get("order", []).map(func(k): return t["by_key"][k])


## 整数键的表: 数组下标 = 键 (缺的位置是空字典)。原先读 data/*.json 的代码按下标取, 可直接替换。
func table_array(name: String) -> Array:
	if not _arrays.has(name):
		var t: Dictionary = _tables.get(name, {})
		var out: Array = []
		for k in t.get("order", []):
			if k is int and k >= 0:
				if k >= out.size():
					var n := out.size()
					out.resize(k + 1)
					for i in range(n, k + 1):
						out[i] = {}
				out[k] = t["by_key"][k]
		_arrays[name] = out
	return _arrays[name]


func record(name: String, key: Variant) -> Dictionary:
	var t: Dictionary = _tables.get(name, {})
	return t.get("by_key", {}).get(_key(key), {})


func unit(id: int) -> Dictionary:
	return record("units", id)


func item(id: int) -> Dictionary:
	return record("items", id)


func skill(id: int) -> Dictionary:
	return record("skills", id)


func units() -> Array:
	return table_array("units")


func items() -> Array:
	return table_array("items")


func skills() -> Array:
	return table_array("skills")


const ITEM_DEFAULT := {"name": "", "desc": "", "type": 0, "price": 0}  # 缺项时的安全缺省 (type 0 = 非装备)
var _warned_items := {}


## 按编号取物品记录 (界面/战斗取名字、类型用这个, 不要直接 items()[id]): 合法编号返回与 items()[id] 同一个字典;
## 越界、负数 (GDScript 负下标会静默取到最后一项)、表里的空位返回缺省记录, 并对该编号只警告一次, 不崩溃。
func item_at(id: int) -> Dictionary:
	var a := items()
	if id >= 0 and id < a.size() and not (a[id] as Dictionary).is_empty():
		return a[id]
	if not _warned_items.has(id):
		_warned_items[id] = true
		push_warning("物品编号无效: %d (表里 %d 项)" % [id, a.size()])
	return ITEM_DEFAULT.duplicate()


## 同 item_at, 按编号取单位 / 技能记录 (不要直接 units()[id] / skills()[id]): 越界、负数、空位返回缺省记录 (含界面/战场
## 直接下标取的键, 不崩溃), 并对该编号只报错一次。内容包 (mod) 写错编号时据此定位
const UNIT_DEFAULT := {"name": "", "sprite": 0, "camp": 0, "move": 0, "move_type": 0, "attribute_defence_id": 0}
const SKILL_DEFAULT := {"name": "", "desc": "", "mp_cost": 0, "move_cost": 0}
var _warned_rows := {}


func unit_at(id: int) -> Dictionary:
	return _row_at("units", "单位", id, UNIT_DEFAULT)


func skill_at(id: int) -> Dictionary:
	return _row_at("skills", "技能", id, SKILL_DEFAULT)


func _row_at(table: String, what: String, id: int, fallback: Dictionary) -> Dictionary:
	var a := table_array(table)
	if id >= 0 and id < a.size() and not (a[id] as Dictionary).is_empty():
		return a[id]
	var key := "%s:%d" % [table, id]
	if not _warned_rows.has(key):
		_warned_rows[key] = true
		push_error("%s编号无效: %d (表里 %d 项), 用缺省记录" % [what, id, a.size()])
	return fallback.duplicate()


func levelup(unit_id: int) -> Dictionary:
	return record("levelup", unit_id)


func party_init(unit_id: int) -> Dictionary:
	return record("party_init", unit_id)


## 我方角色 = party_init 表里有初始状态的单位模板 (原版 0~9, 曾写死为 uid < 10)
func is_hero(unit_id: int) -> bool:
	return _tables.has("party_init") and _tables["party_init"]["by_key"].has(unit_id)


func attribute_defense(index: int) -> Dictionary:
	return record("attribute_defense", index)


func terrain(move_type: int) -> Dictionary:
	return record("terrain", move_type)


func shop(id: String) -> Dictionary:
	return record("shops", id)


## 第 stage 关之后的营地 {background, town, town_entry, background_anim, background_show (SceneShow 配置)}; 没有记录时按原版缺省 (无背景, 直接下一关)
func camp(stage: int) -> Dictionary:
	var c := record("camps", stage)
	return c if not c.is_empty() else {"stage": stage, "background": 0, "town": -1, "town_entry": 0, "background_anim": null, "background_show": null}


func enums(name: String) -> Dictionary:
	var e = json("data/enums.json")
	return e.get(name, {}) if e is Dictionary else {}


# ---------------------------------------------------------------- 关卡 / 城镇 / 剧情 / 文本

func stage_count() -> int:
	return int(manifest.get("stage_count", 0))


func town_count() -> int:
	return int(manifest.get("town_count", 0))


func has_stage(n: int) -> bool:
	return has_file("stages/%02d/stage.json" % n)


## stage.json (整数化); 不存在返回 {}
func stage_info(n: int) -> Dictionary:
	var d = json("stages/%02d/stage.json" % n)
	return ints(d) if d is Dictionary else {}


func stage_name(n: int) -> String:
	return String(stage_info(n).get("name", ""))


## 关卡目录下的其他文件 (map/layers/units.json), 整数化
func stage_file(n: int, file: String) -> Variant:
	return ints(json("stages/%02d/%s" % [n, file]))


## 进关卡/城镇前的完整性检查: 返回 "" = 可进, 否则是缺什么 (场景流转据此回标题, 不让加载函数半途崩; 导出版里 assert 不生效)
func stage_error(n: int) -> String:
	return _files_error("stages/%02d/" % n, {"stage.json": TYPE_DICTIONARY, "units.json": TYPE_ARRAY, "map.json": TYPE_DICTIONARY, "layers.json": TYPE_DICTIONARY}, "关卡 %d" % n)


func town_error(n: int) -> String:
	var e := _files_error("towns/%02d/" % n, {"town.json": TYPE_DICTIONARY, "layers.json": TYPE_DICTIONARY, "map.json": TYPE_DICTIONARY}, "城镇 %d" % n)
	if e == "" and (town_info(n).get("entries", []) as Array).is_empty():
		return "城镇 %d 没有入口 (town.json entries 为空)" % n
	return e


func _files_error(dir: String, need: Dictionary, what: String) -> String:
	for f in need:
		var v = json(dir + f)
		if v == null:
			return "内容包缺少%s的文件 %s%s" % [what, dir, f]
		if typeof(v) != int(need[f]):
			return "%s的 %s%s 格式不对" % [what, dir, f]
	return ""


func town_info(n: int) -> Dictionary:
	var d = json("towns/%02d/town.json" % n)
	return ints(d) if d is Dictionary else {}


func town_file(n: int, file: String) -> Variant:
	return ints(json("towns/%02d/%s" % [n, file]))


## 剧情脚本: info 为 stage.json / town.json 的 script 字段。优先编译 source (.evs);
## 没有 source 文件时退回 raw (events_raw.json, 过渡期)。返回 [[{type, data}]] (EvsCompiler)
func events(info: Dictionary) -> Array:
	var src := String(info.get("source", ""))
	var raw := String(info.get("raw", ""))
	var key := src + "|" + raw
	if _scripts.has(key):
		return _scripts[key]
	var out: Array = []
	var p := find(src) if src != "" else ""
	if p != "":
		var r := EvsCompiler.compile(FileAccess.get_file_as_string(p), src)
		if r.has("error"):
			errors.append(r["error"])
			push_error("Content: 剧情脚本编译失败 " + String(r["error"]))
		else:
			out = r["events"]
	elif raw != "" and json(raw) is Array:
		for cmds in json(raw):
			out.append(cmds.map(func(c): return {"type": int(c["op"]), "data": String(c["data"]).hex_decode()}))
	_scripts[key] = out
	return out


## 对白表: text.json 的 groups。同一路径返回同一个数组, 切语言 / 重载内容包时原地换内容 (见 _refresh_live_groups),
## 所以关卡 / 城镇对象缓存着它也能即时跟上语言切换 (设定里切简繁, 对白马上生效)
func text_groups(rel: String) -> Array:
	if not _live_groups.has(rel):
		_live_groups[rel] = _groups_of(rel).duplicate()
	return _live_groups[rel]


func _groups_of(rel: String) -> Array:
	var d = json(rel)
	return d.get("groups", []) if d is Dictionary else []


## 系统文本 (text/system.json, 按表名替换): [[句子...], ...]
func system_text(name: String) -> Array:
	for i in range(packs.size() - 1, -1, -1):
		var d = _cached_json(packs[i]["dir"].path_join("text/system.json"))  # 战斗中每次调用都会取, 走缓存 (reload 时清)
		if d is Dictionary and d.has(name):
			if lang == "":
				return d[name]
			var key := "%d:%s" % [i, name]
			if not _sys_l.has(key):
				var lp := _locale_path(i, "text/system.json")   # 该包自己的叠加层 (按表名替换)
				var o = _cached_json(lp) if FileAccess.file_exists(lp) else null
				_sys_l[key] = o[name] if o is Dictionary and o.has(name) else d[name]
			return _sys_l[key]
	return []


## 界面主题 (ui_theme/theme.json)
func theme() -> Dictionary:
	var d = json("ui_theme/theme.json")
	return d if d is Dictionary else {}


## 新游戏起点 (manifest.start, X1): {kind: "stage"|"town", id, entry, gold, movie}。缺省 = 第 0 关、金钱取规则参数 initial_gold、不播开场过场
## (与原版 tdj 一致)。kind=town 时进第 id 个城镇的入口 entry, 出城去 state.next_stage (剧情脚本 set_stage 设置, 缺省第 0 关)。
func start() -> Dictionary:
	var m = manifest.get("start", {})
	var d: Dictionary = ints(m) if m is Dictionary else {}
	var kind := String(d.get("kind", "stage"))
	return {
		"kind": kind if kind in ["stage", "town"] else "stage",
		"id": int(d.get("id", 0)),
		"entry": int(d.get("entry", 0)),
		"gold": int(d["gold"]) if d.has("gold") else int(params().initial_gold),
		"movie": int(d.get("movie", -1)),
	}


## 播完后结束游戏回标题的过场视频号 (manifest.ending_movies; 原版 Movie_13 = 第 31 关结局)
func is_ending_movie(id: int) -> bool:
	for m in manifest.get("ending_movies", []):
		if int(m) == id:
			return true
	return false


# ---------------------------------------------------------------- 规则参数

func pack_dirs() -> Array:
	return packs.map(func(p): return p["dir"])


## 规则参数: 默认值 (原版) 上依次叠加各包根目录的 rules.json (每次新建一份, 调用方可以自由修改)
func params():
	return params_from_dirs(pack_dirs())


const RULES_FILE := "rules.json"     # 内容包 / 改动包根目录下的参数覆盖文件


## 规则引擎不读文件: 这里把各包的 rules.json 读成文档交给它; 没有该文件的包不改参数
static func params_from_dirs(dirs: Array):
	return Params.from_documents(dirs.map(func(d): return _read_json_file(str(d).path_join(RULES_FILE))))


## 存档里记录的内容包标识 [{id, version}]
func signature() -> Array:
	return _save_packs().map(func(p): return {"id": p["id"], "version": String(p["manifest"].get("version", ""))})


## 已加载内容包的版本信息 [{id, version, save_compat_min}], 读档时与存档记录比对 (ContentCompat.check_save)
func pack_infos() -> Array:
	return _save_packs().map(func(p): return {"id": p["id"], "version": String(p["manifest"].get("version", "")),
		"save_compat_min": String(p["manifest"].get("save_compat_min", ""))})


## 参与存档签名的包: manifest "save_neutral": true 的包只影响表现 (界面/字体/演出), 不记入存档、读档也不比对
func _save_packs() -> Array:
	return packs.filter(func(p): return not bool(p["manifest"].get("save_neutral", false)))


# ---------------------------------------------------------------- 资源覆盖 (包内 assets/)

func _index_assets() -> void:
	for p in packs:
		_walk_assets(p["dir"].path_join("assets"), "")


func _walk_assets(dir: String, rel: String) -> void:
	var d := DirAccess.open(dir.path_join(rel))
	if d == null:
		return
	for f in d.get_files():
		var r := rel.path_join(f) if rel != "" else f
		_assets[r.to_lower()] = dir.path_join(r)
	for sub in d.get_directories():
		_walk_assets(dir, rel.path_join(sub) if rel != "" else sub)


## 资源相对路径 (如 Stage/Stage05/map05.png) 在某个包的 assets/ 里有覆盖时返回文件路径, 否则 ""
## (Assets 再按原有顺序查 hd6x/hd4x/原图仓库)
func asset_file(rel: String) -> String:
	return _assets.get(rel.to_lower(), "")

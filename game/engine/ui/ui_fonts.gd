# SPDX-License-Identifier: GPL-3.0-only
class_name UiFonts
extends RefCounted
## 字库字体清单 (内容包 ui_theme/fonts.json, 格式): 设定里「字体」项的选项来自这里,
## 新增字体只需加一条数据 + 一个字体文件 (生成工具的脚本 裁子集并量基线)。
## 条目: id、name (设定里显示)、desc (一句话)、file (res:// 字体文件)、baseline_in_cell (12 号字格内基线, 原版像素)、
##   embolden (粗体变体的加粗量)、license / license_file (见 docs/字体许可.md)、full (可选, true = 完整字库: 其余裁过的子集字体缺字时回退到它, 见 complete_id)。
## 叠加: 按包加载顺序 (基础包在前) 合并, 同 id 后者覆盖, 新 id 追加在后; default 取最后一个写了的包。
## 缺失/损坏的清单退回内置思源黑体一项, 所以任何情况下都至少有一个可用字体。

const FILE := "ui_theme/fonts.json"
const FALLBACK := {"id": "sans", "name": "思源黑体", "desc": "", "file": "res://assets/font/NotoSansSC-Medium.otf",
	"baseline_in_cell": 10.75, "embolden": 0.6}

static var _list: Array = []
static var _default := "sans"
static var _loaded := false


static func reload() -> void:
	_loaded = false


## 合并若干包目录里的 fonts.json (测试直接传目录)
static func merge_dirs(dirs: Array) -> Dictionary:
	var order: Array = []
	var by_id := {}
	var def := ""
	for dir in dirs:
		var d = ContentDB._read_json_file(String(dir).path_join(FILE))
		if not (d is Dictionary):
			continue
		if d.get("default") is String:
			def = d["default"]
		for e in d.get("fonts", []):
			if not (e is Dictionary) or not (e.get("id") is String) or not (e.get("file") is String):
				continue
			if not by_id.has(e["id"]):
				order.append(e["id"])
			by_id[e["id"]] = by_id[e["id"]].merged(e, true) if by_id.has(e["id"]) else e
	var list: Array = []
	for id in order:
		list.append(by_id[id])
	return {"list": list, "default": def}


static func _ensure() -> void:
	if _loaded:
		return
	var dirs: Array = []
	var tree := Engine.get_main_loop() as SceneTree
	var c: Node = tree.root.get_node_or_null("Content") if tree else null
	if c != null:
		dirs = c.pack_dirs()
		if not c.reloaded.is_connected(reload):
			c.reloaded.connect(reload)
	var m := merge_dirs(dirs)
	_list = m["list"]
	if _list.is_empty():
		_list = [FALLBACK.duplicate()]
	_default = String(m["default"])
	if find(_default).is_empty():
		_default = String(_list[0]["id"])
	_loaded = not dirs.is_empty()  # 内容包还没加载时只给内置思源黑体, 不缓存


static func all() -> Array:
	_ensure()
	return _list


static func default_id() -> String:
	_ensure()
	return _default


## 缺字兜底字体: 清单里标了 "full": true 的第一个; 都没标就取内置思源黑体 (FALLBACK), 清单里也没有它才取缺省。
## 裁过的子集字体 (文楷 / 宋体, 含缺省) 缺的字 (繁体字、后加的界面用字) 都回退到它 —— 不能是「缺省字体」: 缺省字体可以本身就是子集 (现在是文楷), 它没有兜底就会丢字
static func complete_id() -> String:
	_ensure()
	for e in _list:
		if bool(e.get("full", false)):
			return String(e["id"])
	var b := String(FALLBACK["id"])
	return b if not find(b).is_empty() else _default


static func find(id: String) -> Dictionary:
	for e in _list:
		if e["id"] == id:
			return e
	return {}


## 未知/缺失的 id 回退缺省字体
static func get_or_default(id: String) -> Dictionary:
	_ensure()
	var e := find(id)
	return e if not e.is_empty() else find(_default)


## 设定选项 [{v, t, d}]
static func options() -> Array:
	var out: Array = []
	for e in all():
		out.append({"v": e["id"], "t": String(e.get("name", e["id"])), "d": String(e.get("desc", ""))})
	return out


## 12 号字格内的基线 (原版像素)
static func baseline(id: String) -> float:
	return float(get_or_default(id).get("baseline_in_cell", 10.75))

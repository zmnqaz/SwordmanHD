# SPDX-License-Identifier: GPL-3.0-only
class_name ThemeAssets
extends RefCounted
## 资源命名清单: 代码里不写原版资源路径, 只用逻辑名 (如 "camp.spirit"), 由内容包的 ui_theme/assets.json 映射到资源名。
## 换游戏或 mod = 换清单里的映射 (素材文件按资源名在原图/高清目录或内容包 assets/ 里找, 见 Assets)。
##
## 清单格式 (按内容包加载顺序叠加, 后面的包覆盖同名项; 值写 null = 删除):
##   {"names": {"camp.spirit": "Misc/SP_REV", ...},          固定资源名
##    "patterns": {"face": "Face/FACE%02d", ...}}            带 %d / %s 占位的资源名模板, 用 f() 套参数
## 用法:
##   ThemeAssets.p("camp.spirit")             -> "Misc/SP_REV"
##   ThemeAssets.f("face", [5])               -> "Face/FACE05"
## 缺项: 警告一次并返回 "" (多半是清单漏写或拼错)。测试或换包后 ThemeAssets.reload()。

const FILE := "ui_theme/assets.json"

static var _data := {}
static var _loaded := false
static var _missing := {}


static func reload() -> void:
	_loaded = false
	_data = {}
	_missing = {}


## 直接指定清单 (测试用)
static func use(d: Dictionary) -> void:
	reload()
	_data = d
	_loaded = true


static func data() -> Dictionary:
	if not _loaded:
		_load()
	return _data


static func _load() -> void:
	_loaded = true
	_data = {}
	var tree := Engine.get_main_loop() as SceneTree
	var c: Node = tree.root.get_node_or_null("Content") if tree else null
	if c == null:
		return
	if not c.reloaded.is_connected(reload):
		c.reloaded.connect(reload)
	for dir in c.pack_dirs():
		var d = ContentDB._read_json_file(String(dir).path_join(FILE))
		if d is Dictionary:
			_data = UiLayout.merge(_data, d)


## 固定资源名
static func p(key: String) -> String:
	var v = data().get("names", {}).get(key)
	if v is String:
		return v
	_warn(key)
	return ""


## 模板资源名套参数
static func f(key: String, args: Array) -> String:
	var v = data().get("patterns", {}).get(key)
	if v is String:
		return v % args
	_warn(key)
	return ""


static func has(key: String) -> bool:
	return data().get("names", {}).has(key) or data().get("patterns", {}).has(key)


static func _warn(key: String) -> void:
	if not _missing.has(key) and not data().is_empty():
		_missing[key] = true
		push_warning("ThemeAssets: 资源清单没有 " + key)

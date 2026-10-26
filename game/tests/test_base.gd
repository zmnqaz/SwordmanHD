# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 测试基类: 断言辅助 + 常用构造。断言失败只记录不中断。

const Params = preload("res://engine/rules/params.gd")
const Rng = preload("res://engine/rules/rng.gd")
const ScriptedRng = preload("res://engine/rules/scripted_rng.gd")
const Ctx = preload("res://engine/rules/context.gd")
const U = preload("res://engine/rules/unit_state.gd")
const Board = preload("res://engine/rules/board.gd")
const Stats = preload("res://engine/rules/stats.gd")

var current_test := ""
var failures := []
var assert_count := 0
var skipped_reason := ""  ## 非空 = 测试自己判断缺依赖而跳过 (run_tests.gd 记 SKIP, 不算失败也不算通过)

static var _tables_cache = null


## 测试里动态跳过: skip("缺原版 Item_dat.dat"); return。需要静态声明依赖的见 run_tests.gd 头注 (REQUIRES)。
func skip(reason: String) -> void:
	skipped_reason = reason


## 外部产物是否在: original (原版资源, 与 Assets 同一解析) / hd4x / content (game/content/tdj) / data (data/*.json)
static func has_resource(kind: String) -> bool:
	var root: Node = Engine.get_main_loop().root
	var A = root.get_node_or_null("Assets")
	match kind:
		"original":
			return A != null and FileAccess.file_exists(String(A.orig).path_join("index.json"))
		"hd4x":
			return A != null and FileAccess.file_exists(String(A.hd4_dir).path_join("hd4x.json"))
		"content":
			return FileAccess.file_exists("res://content/tdj/textures.json")
		"data":
			return FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join("../data/items.json").simplify_path())
	push_error("未知依赖类型 " + kind)
	return false


## 原版文件的真实路径 (经 Assets 索引, 大小写不敏感); 没有原版或文件不在返回 ""
static func original_file(rel: String) -> String:
	if not has_resource("original"):
		return ""
	var A = Engine.get_main_loop().root.get_node("Assets")
	var r: String = A.resolve(rel)
	return String(A.orig).path_join(r) if r != "" else ""


func check(cond: bool, msg: String = "") -> void:
	assert_count += 1
	if not cond:
		failures.append("断言失败: " + msg)


func eq(actual, expected, msg: String = "") -> void:
	assert_count += 1
	if typeof(actual) != typeof(expected) and not ((actual is int or actual is float) and (expected is int or expected is float)):
		failures.append("%s 期望 %s (%s), 实际 %s (%s)" % [msg, str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))])
	elif actual != expected:
		failures.append("%s 期望 %s, 实际 %s" % [msg, str(expected), str(actual)])


func near(actual: float, expected: float, tol: float, msg: String = "") -> void:
	assert_count += 1
	if absf(actual - expected) > tol:
		failures.append("%s 期望 %s ± %s, 实际 %s" % [msg, str(expected), str(tol), str(actual)])


## 规则上下文: rng 为 Scripted 队列 (默认空 → 每次 rand() 返回 0)
func ctx_scripted(values: Array = [], overrides: Dictionary = {}):
	return Ctx.new(Params.new(overrides), ScriptedRng.new(values))


func ctx_seeded(seed_value: int = 12345, overrides: Dictionary = {}):
	return Ctx.new(Params.new(overrides), Rng.new(seed_value))


## 带原版数据表 (仓库 data/*.json) 的上下文
func ctx_data(rng = null, overrides: Dictionary = {}):
	var c = Ctx.new(Params.new(overrides), rng if rng != null else ScriptedRng.new([]))
	c.load_records(_json("items.json"), _json("skills.json"), _json("attribute_defense.json"), _levelup_records(), _json("units.json"))
	return c


## 原版数据表 (规则引擎不读文件, 测试在这里读好再交给它)
func _json(name: String):
	var p := data_dir().path_join(name)
	return JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null


func _levelup_records():
	var lu = _json("levelup.json")
	return lu.get("units") if lu is Dictionary else lu


func data_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../data").simplify_path()


func unit(fields: Dictionary = {}):
	var u = U.new()
	u.hp = 100
	u.hp_max = 100
	u.mp = 100
	u.mp_max = 100
	u.stats = {"str": 50, "int": 50, "avg": 0, "vit": 20, "luk": 20}
	for k in fields:
		if k in ["str", "int", "avg", "vit", "luk"]:
			u.stats[k] = fields[k]
		else:
			u.set(k, fields[k])
	return u


## 给上下文加一件简单装备, 返回编号
func add_item(c, id: int, fields: Dictionary) -> int:
	var rec := {"id": id, "attack": 0, "defence": 0, "hit": 0, "miss": 0, "critical": 0, "double": 0,
		"attack_add": {"type": -1, "ratio": 0, "time": 0, "cost": 0},
		"attribute_defence": {"雷": 0, "火": 0, "冰": 0, "幻": 0, "光": 0, "暗": 0},
		"attack_range": {"type": 0, "area": 0, "min": -1, "max": 1}}
	for k in fields:
		rec[k] = fields[k]
	c.items[id] = rec
	return id

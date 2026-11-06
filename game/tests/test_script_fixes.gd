# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 剧情脚本修正表 scripts/fixes.json (ContentDB._apply_fixes, docs/内容格式.md §7.1): 删一行 / 换一行, 恰好匹配 1 处才应用,
## 多包按加载顺序叠加, 脚本被更后加载的包整个替换时下层修正不作用; 以及 remake 包的 (第 8 关开场不再覆盖送酒变量 var11)。
const REQUIRES_TEST := {"test_remake_d412_applied": ["content"]}

const ContentDBScript = preload("res://engine/content/content_db.gd")
const Evs = preload("res://engine/script/evs_compiler.gd")

const DIR := "user://content/"
const PACKS := ["test_fix_base", "test_fix_a", "test_fix_b", "test_fix_c"]
const SRC := "scripts/stage_00.evs"
const BASE_EVS := """script battle
events 3

event 0
    return

event 1
    set_var var=11 value=1    # 开场覆盖
    set_var var=9 value=0
    return

event 2
    set_var var=11 value=1
    set_var var=11 value=1
    set_var var=7 value=7
    return
"""


func _write(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(data if data is String else JSON.stringify(data))
	f.close()


func _pack(id: String, base: Array, fixes: Variant = null, evs := "") -> void:
	remove_tree(DIR + id)
	_write(DIR + id + "/manifest.json", {"format": "tdj-content/1", "id": id, "version": "1", "engine_min": "1.0.0", "base": base})
	if fixes != null:
		_write(DIR + id + "/scripts/fixes.json", fixes if fixes is String else {"format": "tdj-script-fixes/1", "fixes": fixes})
	if evs != "":
		_write(DIR + id + "/" + SRC, evs)


func _cleanup() -> void:
	for id in PACKS:
		remove_tree(DIR + id)


## 用 ids 加载, 返回 [编译结果, 错误表]
func _run(ids: Array) -> Array:
	var db = ContentDBScript.new()
	db.load_packs(ids)
	var ev: Array = db.events({"source": SRC})
	var errs: Array = db.errors.duplicate()
	db.free()
	return [ev, errs]


func _compiled(text: String) -> Array:
	var r: Dictionary = Evs.compile(text, SRC)
	check(not r.has("error"), "期望文本可编译: %s" % r.get("error", ""))
	return r.get("events", [])


func test_remove_and_replace():
	_pack("test_fix_base", [], null, BASE_EVS)
	_pack("test_fix_a", ["test_fix_base"], [
		{"id": "R1", "script": "stage_00.evs", "event": 1, "remove": "set_var  var=11 value=1  # 注释与多余空白不影响匹配", "note": "x"},
		{"id": "R2", "script": "stage_00.evs", "event": 2, "replace": {"find": "set_var var=7 value=7", "with": "set_var var=7 value=8"}}])
	var r := _run(["test_fix_a"])
	eq(r[1], [], "无错误")
	var want := BASE_EVS.replace("    set_var var=11 value=1    # 开场覆盖\n", "").replace("var=7 value=7", "var=7 value=8")
	eq(r[0], _compiled(want), "删掉事件 1 的一行、替换事件 2 的一行")
	eq(_run(["test_fix_base"])[0], _compiled(BASE_EVS), "不加载修正包时原样")
	_cleanup()


func test_no_match_or_many_not_applied():
	_pack("test_fix_base", [], null, BASE_EVS)
	_pack("test_fix_a", ["test_fix_base"], [
		{"id": "Z0", "script": "stage_00.evs", "event": 0, "remove": "set_var var=11 value=1"},       # 事件 0 没有这行 (事件 1/2 有也不算)
		{"id": "Z2", "script": "stage_00.evs", "event": 2, "remove": "set_var var=11 value=1"},       # 事件 2 有两处
		{"id": "Z9", "script": "stage_00.evs", "event": 9, "remove": "return"},                       # 没有事件 9
		{"id": "OK", "script": "stage_00.evs", "event": 2, "replace": {"find": "set_var var=7 value=7", "with": "set_var var=7 value=8"}},
		{"id": "NX", "script": "stage_99.evs", "event": 1, "remove": "set_var var=9 value=0"}])      # 别的脚本: 不作用于本脚本
	var r := _run(["test_fix_a"])
	eq(r[0], _compiled(BASE_EVS.replace("var=7 value=7", "var=7 value=8")), "匹配 0 处 / 多处的修正不应用, 其余照常")
	eq(r[1].size(), 3, "三条匹配失败各记一条错误: %s" % [r[1]])
	check(String(r[1][0]).contains("Z0") and String(r[1][0]).contains("找不到"), String(r[1][0]))
	check(String(r[1][1]).contains("Z2") and String(r[1][1]).contains("2 处"), String(r[1][1]))
	_cleanup()


func test_packs_stack_in_load_order():
	_pack("test_fix_base", [], null, BASE_EVS)
	_pack("test_fix_a", ["test_fix_base"], [{"id": "A", "script": "stage_00.evs", "event": 1, "replace": {"find": "set_var var=9 value=0", "with": "set_var var=9 value=5"}}])
	_pack("test_fix_b", ["test_fix_a"], [{"id": "B", "script": "stage_00.evs", "event": 1, "replace": {"find": "set_var var=9 value=5", "with": "set_var var=9 value=6"}}])
	var r := _run(["test_fix_b"])
	eq(r[1], [], "B 的修正在 A 之后应用, 能看到 A 改过的行")
	eq(r[0], _compiled(BASE_EVS.replace("var=9 value=0", "var=9 value=6")))
	# 脚本被更后加载的包整个替换: 下层 (A、B) 的修正不再作用, 也不报错; 替换包自己的修正照常
	var own := BASE_EVS.replace("var=9 value=0", "var=9 value=1")
	_pack("test_fix_c", ["test_fix_b"], [{"id": "C", "script": "stage_00.evs", "event": 2, "replace": {"find": "set_var var=7 value=7", "with": "set_var var=7 value=3"}}], own)
	r = _run(["test_fix_c"])
	eq(r[1], [])
	eq(r[0], _compiled(own.replace("var=7 value=7", "var=7 value=3")), "整文件替换覆盖下层修正")
	_cleanup()


func test_bad_format_reported():
	_pack("test_fix_base", [], null, BASE_EVS)
	_pack("test_fix_a", ["test_fix_base"], {"format": "x", "fixes": []})
	check(_run(["test_fix_a"])[1].size() == 1, "format 不对报错")
	_pack("test_fix_a", ["test_fix_base"], [
		{"script": "stage_00.evs", "event": 1, "remove": "return"},
		{"id": "E1", "script": "stage_00.evs", "event": 1},
		{"id": "E2", "script": "stage_00.evs", "event": 1, "remove": "return", "replace": {"find": "a", "with": "b"}},
		{"id": "E3", "script": "stage_00.evs", "event": -1, "remove": "return"},
		{"id": "E4", "script": "stage_00.evs", "event": 1, "replace": {"find": "return"}},
		{"id": "E5", "script": "stage_00.evs", "event": 1, "remove": "return", "typo": 1}])
	var r := _run(["test_fix_a"])
	eq(r[1].size(), 6, "每条格式错误都报: %s" % [r[1]])
	eq(r[0], _compiled(BASE_EVS), "格式错的条目不应用")
	_cleanup()


## remake 包删掉第 8 关 e1 的 set_var var=11 value=1, 其余逐条与原版相同; 只加载 tdj (原版) 时仍在
func test_remake_d412_applied():
	var tdj = ContentDBScript.new()
	tdj.load_packs(["tdj"])
	var rm = ContentDBScript.new()
	rm.load_packs(["remake"])
	eq(rm.errors, [], "remake 的修正全部匹配")
	var info: Dictionary = tdj.stage_info(8)["script"]
	var a: Array = tdj.events(info)
	var b: Array = rm.events(info)
	eq(a.size(), b.size())
	var set11 := {"type": 0x1E, "data": PackedByteArray([11, 0, 1, 0, 0, 0])}
	eq(a[1].filter(func(c): return c == set11).size(), 1, "原版 e1 有 var11 = 1")
	eq(b[1].filter(func(c): return c == set11).size(), 0, "复刻 e1 没有")
	eq(b[1].size(), a[1].size() - 1, "只少这一条")
	var rest: Array = a[1].duplicate()
	rest.erase(set11)
	eq(b[1], rest, "其余指令不变")
	for e in a.size():
		if e != 1:
			eq(b[e], a[e], "事件 %d 不变" % e)
	tdj.free()
	rm.free()

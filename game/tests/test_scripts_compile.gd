# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## engine/ 与 scripts/ 下每个脚本都能编译: 场景脚本 (rpg_scene、battle_scene...) 是运行时才 load() 的, 其它测试不一定会碰到,
## 一处类型推断/语法错误会让整个游戏进不去 (2026-10-20 rpg_scene.gd 的一处 := 推断就是这样漏到实机跑才发现)。


func _collect(dir: String, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for sub in da.get_directories():
		_collect(dir + "/" + sub, out)
	for f in da.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)


func test_every_engine_and_scene_script_compiles() -> void:
	var files: Array = []
	_collect("res://engine", files)
	_collect("res://scripts", files)
	check(files.size() > 100, "找到脚本 %d 个" % files.size())
	var broken: Array = []
	for p in files:
		var s = load(p)
		if not (s is GDScript) or not (s as GDScript).can_instantiate():
			broken.append(p)
	check(broken.is_empty(), "编译失败的脚本: %s" % [broken])

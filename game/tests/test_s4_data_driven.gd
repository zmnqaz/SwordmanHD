# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## S4 硬编码上移: 默认值必须与原版常量一致 (行为不变), 内容包可经 rules.json / 布局表覆盖


func test_reserved_var_defaults():
	var p = Params.new()
	eq(p.var_actor, 102, "当前行动单位变量号")
	eq(p.summon_flag_vars, [103, 104, 105, 106], "召唤标志变量号")
	eq(p.spirit_add_limit, 100, "五魂化蕴上限 (营地页读它)")


func test_reserved_var_override():
	var p = Params.from_documents([{"format": "tdj-rules/1", "params": {"var_actor": 90, "summon_flag_vars": [91.0, 92.0]}}])
	eq(p.var_actor, 90)
	eq(p.summon_flag_vars, [91, 92], "JSON 浮点数转整数")


func test_ai_enum_matches_enums_json():
	eq([U.AI_IDLE, U.AI_ACTIVE, U.AI_PASSIVE, U.AI_FOLLOW, U.AI_GOTO], [0, 1, 2, 3, 4])


func test_man_frames_from_layout():
	var db = ContentDB.new()
	db.load_packs(["remake"])
	UiLayout.use(UiLayout.merge_dirs(db.pack_dirs()))
	eq(UiProfile.man_frames(), [11, 10, 10, 10, 10, 6, 10, 4, 10, 8], "Camp_man 各人帧数 = 原版")
	UiLayout.use(null)
	db.free()

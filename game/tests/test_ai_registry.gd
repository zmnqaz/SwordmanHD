# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## AI 行为注册表 (X5#1): 默认 = 原版 5 种, mod 可注册第 6 种或经 rules.json 别名; 行为与改前一致

const AI = preload("res://engine/rules/ai.gd")
const Movement = preload("res://engine/rules/movement.gd")


func _setup(ai_type: int, enemy_pos: Vector2i) -> Dictionary:
	var c = ctx_data()
	add_item(c, 900, {"attack": 30, "hit": 100})
	var b = Board.new(15, 15, 0)
	var me = unit({"side": 1, "ai": ai_type, "uid": 10, "move_base": 20, "move_type": 0, "weapon": 900, "str": 50})
	me.set_pos(Vector2i(2, 2))
	var foe = unit({"side": 0, "uid": 1, "hp": 300, "hp_max": 300, "vit": 20})
	foe.set_pos(enemy_pos)
	b.add_unit(me)
	b.add_unit(foe)
	Movement.begin_phase(c, me)
	return {"c": c, "b": b, "me": me}


func test_default_five_registered():
	AI.reset_behaviors()
	for t in [0, 1, 2, 3, 4]:
		check(AI.has_behavior(t), "类型 %d 默认已注册" % t)
	check(not AI.has_behavior(5), "第 6 种默认未注册")


func test_unregistered_falls_back_to_active():
	var a := _setup(1, Vector2i(12, 2))
	var b := _setup(7, Vector2i(12, 2))   # 未注册 = 主动 (原版 default 分支)
	eq(AI.plan(b.c, b.b, b.me).move_to, AI.plan(a.c, a.b, a.me).move_to)


func test_register_sixth_type():
	AI.register_behavior(5, func(_c, _b, u, _stay): return {"move_to": u.pos() + Vector2i(1, 0), "action": {}})
	var s := _setup(5, Vector2i(12, 2))
	eq(AI.plan(s.c, s.b, s.me).move_to, Vector2i(3, 2), "自定义行为生效")
	AI.reset_behaviors()
	var s2 := _setup(5, Vector2i(12, 2))
	eq(AI.plan(s2.c, s2.b, s2.me).move_to, Vector2i(6, 2), "reset 后回到默认 (按主动)")


func test_override_builtin_and_alias():
	var s := _setup(0, Vector2i(3, 2))
	s.c.params.ai_type_alias = {"5": 0}
	s.me.ai = 5
	eq(AI.plan(s.c, s.b, s.me).move_to, Vector2i(2, 2), "别名 5 -> 0 待机")
	check(AI.plan(s.c, s.b, s.me).action.is_empty())

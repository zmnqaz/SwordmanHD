# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 规则参数与成长数据的校验 : 内容包写错的值在加载/使用时报错并回退, 不在战斗里除零、不静默变 0。

const Growth = preload("res://engine/rules/growth.gd")


func test_params_reject_zero_divisors():
	var p = Params.new({"crit_def_div": 0, "dmg_luk_div_span": 0, "bless_int_div_min": -3, "mp_absorb_div_ot1": 0, "poison_div": 4})
	eq(p.crit_def_div, 2, "*_div 写 0: 报错, 保留缺省")
	eq(p.dmg_luk_div_span, 11, "*_span 写 0: 保留缺省 (rand()%0 除零)")
	eq(p.bless_int_div_min, 5, "*_div_min 写负: 保留缺省 (min + rand%span 可能为 0)")
	eq(p.mp_absorb_div_ot1, 3, "*_div_ot1 同样校验")
	eq(p.poison_div, 4, "合法值照常覆盖")


func test_params_type_checked_and_numbers_converted():
	var p = Params.from_documents([{"format": "tdj-rules/1", "params": {"turn_limit": "abc", "unit_item_slots": 12.0, "guard_flash_sec": 1, "fix_ending_return_title": 0}}])
	eq(p.turn_limit, 100, "类型不对 (字符串): 报错, 保留缺省")
	eq(p.unit_item_slots, 12, "JSON 数字 (float) 转 int")
	check(p.guard_flash_sec is float and p.guard_flash_sec == 1.0, "整数写给小数参数: 转 float")
	eq(p.fix_ending_return_title, true, "布尔参数写成数字: 报错, 保留缺省")


func test_growth_negative_rand_does_not_divide_by_zero():
	var a = ctx_seeded(777)
	var b = ctx_seeded(777)
	eq(Growth._rand_term(a, -1), 0, "rand = -1 (以前 rand()%0 除零): 按 0")
	eq(Growth._rand_term(a, -5), 0, "rand 为负: 按 0")
	Growth._rand_term(b, 0)
	Growth._rand_term(b, 0)
	eq(a.rng.get_state(), b.rng.get_state(), "仍各抽一次数, 后续随机序列与 rand=0 一致")


func test_learn_skills_short_spirit_request():
	var c = ctx_seeded()
	var u = unit({"lv": 5})
	u.skills = [-1, -1, -1]
	u.spirit = [3, 0, 0, 0, 0]
	var got: Array = Growth.learn_skills(c, u, [
		{"lv": 1, "skill_id": 7, "spirit_request": [0, 0]},     # 不足 5 项 (以前越界): 缺项按 0
		{"lv": 1, "skill_id": 8, "spirit_request": [5]},        # 魂 0 需 >= 5, 不满足
		{"lv": 1, "skill_id": 9, "spirit_request": null},       # 类型不对: 按不限
	])
	eq(got, [7, 9], "短数组/类型错不崩溃, 已有项照常判定")


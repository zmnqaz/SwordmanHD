# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 地图法术结果的伤害/回复数字: 原版法术命中、回复后在目标身上弹数字, 和近景里是同一套字模 (Misc/Fig_misc 帧 4 红 / 5 蓝)
## 与同一张跳动表。依据: 实测逐帧录像 2026-10-13:
##   离火神诀: 敌人血 89 -> 32, 画面字形「五七」(红), 命中火花散去后出现; 气愈之术: 应奉仁 100 -> 177, 字形「七七」(蓝)。
##   字的竖向位置逐帧 = 近景跳动表 (-2,-4,-8,-6,-2,0,-1,0) 再每周期上移 1; 两位数的左上角在目标格左上角右 ~6.5、上 ~3 像素。

const REQUIRES_TEST := {  # 个别方法的依赖 (run_tests.gd 头注), 缺则 SKIP
	"test_two_digit_position_matches_original_frames": ["original"],
	"test_one_digit_position_is_centered_on_cell": ["original"],
	"test_damage_is_red_and_heal_is_blue_frame": ["original"],
	"test_closeup_digits_unchanged_by_the_extraction": ["original"],
	"test_view_digits_attach_to_units_node_regardless_of_popup_setting": ["original"]
}


class FakeScene:
	extends Node2D
	var units_node := Node2D.new()
	func _init() -> void:
		add_child(units_node)


## 只记录调用的 BattleView (不画)
class FakeView:
	extends BattleView
	var digits_calls: Array = []   # [[单位, 数值, 是否回复]]
	var popups: Array = []         # [[单位, 文字]] (文字飘字已撤: 应一直为空; popup 若又被调用会记下来)
	func _init() -> void:
		super(null, null)
	func res_anim(_u: BattleUnit, _dir: String, _a: int, _b: int, _wait := true, _tick := 0, _sound = null) -> void:
		pass
	func digits(u: BattleUnit, value: int, heal: bool) -> DamageDigits:
		digits_calls.append([u, value, heal])
		return null
	func popup(u: BattleUnit, text: String, _c: Color, _dy := 0.0) -> void:
		popups.append([u, text])


func _spell(result_type: int) -> Dictionary:
	return {"result_type": result_type, "move_attack_type": 0, "other_type": -1, "other_effect": -1, "result_effect": -1}


func _res(unit, over: Dictionary) -> Dictionary:
	var r := {"unit": unit, "hit": true, "invalid": false, "guard": false, "damage": 0, "healed": 0, "mp_drained": 0, "status": 0, "killed": false, "amount": 0, "code": 0}
	r.merge(over, true)
	return {"targets": [r]}


# ---------------- 字模与位置 ----------------

func test_two_digit_position_matches_original_frames():
	var d := DamageDigits.new("57", "map.damage", false, {"cx": 21, "cy": 7})
	eq(d.position, Vector2(21 * 30 + 15 - 8, 7 * 24 - 3), "两位数: 以格中心为中心 (步进 8 -> 左移 8), 字上沿在格上沿上 3 (原版录像 (151.5, 84.8) vs 格 (145, 88))")
	d.free()


func test_one_digit_position_is_centered_on_cell():
	var d := DamageDigits.new("9", "map.damage", false, {"cx": 4, "cy": 2})
	eq(d.position, Vector2(4 * 30 + 15 - 4, 2 * 24 - 3), "一位数左移 4")
	d.free()


func test_damage_is_red_and_heal_is_blue_frame():
	var red := DamageDigits.new("57", "map.damage", false, {"cx": 0, "cy": 0})
	var blue := DamageDigits.new("77", "map.damage", true, {"cx": 0, "cy": 0})
	eq(red.frame_index, 4, "伤害用 Fig_misc 帧 4 (红)")
	eq(blue.frame_index, 5, "回复用 Fig_misc 帧 5 (蓝)")
	red.free()
	blue.free()


func test_closeup_digits_unchanged_by_the_extraction():
	var d := DamageDigits.new("12", "closeup.damage.left")
	eq(d.position, Vector2(117 - 8, 77), "近景左侧数字位置不变 (中心 (117,77))")
	d.free()


# ---------------- 时间表: 逐帧录像量到的竖向位置 ----------------

func test_bounce_then_rise_matches_recording():
	var bounce := [-2, -4, -8, -6, -2, 0, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var want := [-2, -4, -8, -6, -2, 0, -1, 0]
	for k in want.size():
		eq(DamageDigits.dy_alpha(k, bounce).x, float(want[k]), "跳动第 %d 周期" % k)
	eq(DamageDigits.dy_alpha(15, bounce).x, 0.0, "停住")
	eq(DamageDigits.dy_alpha(16, bounce).x, -1.0, "第 16 周期起每周期上移 1")
	eq(DamageDigits.dy_alpha(20, bounce).x, -5.0)
	check(DamageDigits.dy_alpha(16, bounce).y > DamageDigits.dy_alpha(28, bounce).y, "上移的同时淡出")
	eq(DamageDigits.dy_alpha(-1, bounce).y, 0.0, "还没轮到的字不画 (错开 1 周期出现)")


# ---------------- 真 BattleView: 数字挂在人物层, 不受「伤害飘字」设定控制 ----------------

func test_view_digits_attach_to_units_node_regardless_of_popup_setting():
	var scene := FakeScene.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(scene)
	var ui := BattleUi.new(scene)
	scene.add_child(ui)
	var v := BattleView.new(scene, ui)
	scene.add_child(v)
	var u := BattleUnit.new()
	u.cx = 21
	u.cy = 7
	var n := v.digits(u, 57, false)
	eq(n.get_parent(), scene.units_node, "挂在人物层 (随镜头走)")
	eq(n.position, Vector2(21 * 30 + 15 - 8, 7 * 24 - 3), "目标格上")
	eq(n.text, "57")
	var m := v.digits(u, -3, true)
	eq(m.text, "0", "负数按 0 (回复走 heal 标志, 不靠符号)")
	scene.free()
	u.free()


# ---------------- 法术结果按结果码演出 (实测 2026-10-18) ----------------

## 一个目标的结果演出计划 (BattleActions.result_plan): 返回 [] (什么都没有) 或那一项 {frames, digit}
func _plan(sk: Dictionary, over: Dictionary) -> Array:
	var t := BattleUnit.new()
	var res := _res(t, over)
	var plan := BattleActions.result_plan(sk, res)
	t.free()
	return plan


func _phys(ot: int, oe: int) -> Dictionary:
	return {"move_attack_type": 1, "other_type": ot, "other_effect": oe, "result_type": -1, "result_effect": -1}


func test_spell_damage_hit_is_hit_anim_with_red_digits():
	var p := _plan(_spell(0), {"code": 2, "damage": 57})
	eq(p.size(), 1)
	eq(p[0].frames, [2, 10], "命中: MAN_RES 2~9 黄色爆光")
	eq(p[0].digit, {"value": 57, "heal": false}, "红数字 = 结算的伤害 (原版敌人 89 -> 32)")


func test_spell_freeze_success_is_red_whirl():
	var p := _plan(_spell(0), {"code": 13, "damage": 149})
	eq(p[0].frames, [32, 46], "冰結成功: 32~45 红色旋风 (实测, 旧代码一律 2~10)")
	eq(p[0].digit, {"value": 149, "heal": false})


func test_spell_miss_and_invalid_show_nothing():
	eq(_plan(_spell(0), {"code": 0, "hit": false}), [], "未命中: 没有动画也没有〇 (实测; 〇 只在近景普攻闪避)")
	eq(_plan(_spell(0), {"code": 0, "invalid": true}), [], "无效 (幻影/全禦): 同上")


func test_curse_success_whirl_without_digits_and_resist_nothing():
	var p := _plan(_spell(4), {"code": 8, "status": U.ST_PARALYZE})
	eq(p[0].frames, [32, 46], "诅咒成功 32~45")
	eq(p[0].digit, {}, "状态类没有数字")
	eq(_plan(_spell(4), {"code": 0}), [], "抵抗或未命中: 什么都没有")


func test_heal_blue_digit_even_when_zero():
	var p := _plan(_spell(1), {"code": 14, "amount": 77, "healed": 77})
	eq(p[0].frames, [46, 60])
	eq(p[0].digit, {"value": 77, "heal": true}, "蓝 (原版应奉仁 100 -> 177)")
	p = _plan(_spell(1), {"code": 14, "amount": 0})
	eq(p[0].frames, [46, 60], "满血照放治疗动画 (实测气愈之术满血 46~59)")
	eq(p[0].digit, {"value": 0, "heal": true}, "满血也弹蓝〇 (实测金创药满血)")


func test_full_heal_and_mp_restore_use_heal_segment_and_blue_digits():
	var p := _plan(_phys(2, 13), {"code": 21, "amount": 130})
	eq(p[0].frames, [46, 60], "天护灵烨全复: 46~59 (旧代码落到 81~99)")
	eq(p[0].digit, {"value": 130, "heal": true})
	p = _plan(_phys(2, 15), {"code": 26, "amount": 0})
	eq(p[0].digit, {"value": 0, "heal": true}, "天瑞仙舞满蓝: 蓝〇")


func test_purify_bless_and_special_segments():
	eq(_plan(_spell(2), {"code": 15})[0].frames, [46, 60], "净化: 46~59 (旧代码 60~80)")
	eq(_plan(_spell(3), {"code": 3})[0].frames, [18, 32], "增益: 18~31")
	var dispel := {"result_type": 5, "result_effect": 12, "move_attack_type": 0}
	eq(_plan(dispel, {"code": 19})[0].frames, [32, 46], "驱散: 32~45")
	var back := {"result_type": 5, "result_effect": 13, "move_attack_type": 0}
	eq(_plan(back, {"code": 20})[0].frames, [18, 32], "返召: 18~31")
	var burrow := {"result_type": 5, "result_effect": 16, "move_attack_type": 0}
	eq(_plan(burrow, {"code": 25}), [], "遁地神行: 没有动画")


func test_status_fall_back_to_hit_when_target_dies_from_the_blow():
	var p := _plan(_spell(0), {"code": 13, "damage": 200, "killed": true})
	eq(p[0].frames, [2, 10], "被这一击打死: 冰結退成命中段 (原版 字段 = 0)")


func test_physical_skill_results():
	var guard := _plan(_phys(0, -1), {"code": 1, "guard": true, "damage": 30})
	eq(guard[0].frames, [10, 18], "被格挡 10~17")
	eq(guard[0].digit, {"value": 30, "heal": false})
	var bind := _plan(_phys(2, 8), {"code": 12})
	eq(bind[0].frames, [32, 46], "地缚 32~45")
	eq(bind[0].digit, {}, "自身类绝技没有伤害数字")
	var drain := _plan(_phys(2, 7), {"code": 11, "damage": 0})
	eq(drain[0].frames, [2, 10], "吸术 2~9")
	eq(drain[0].digit, {}, "魔天降临类吸术没有数字")
	var ot1 := _plan(_phys(1, 3), {"code": 8, "damage": 41})
	eq(ot1[0].frames, [32, 46], "麻痹绝技附加成功 32~45")
	eq(ot1[0].digit, {"value": 41, "heal": false}, "带伤害的绝技照样弹伤害")


func test_absorbed_damage_is_blue():
	var p := _plan(_spell(0), {"code": 2, "damage": -20})
	eq(p[0].digit, {"value": 20, "heal": true}, "属性吸收: 值为负, 蓝色画绝对值")


func test_text_popups_are_gone():
	var bv := BattleView.new(null, null)
	check(not bv.has_method("popup"), "文字飘字功能已撤: 只剩数字")
	bv.free()
	eq(_plan(_spell(4), {"code": 9, "status": 1}).map(func(e): return e.digit), [{}], "状态名不弹字 (原版是靠状态外观 Man_eff 表现, 不是文字)")


func test_multi_target_each_decided_alone():
	var a := BattleUnit.new()
	var b := BattleUnit.new()
	var c := BattleUnit.new()
	var base := {"hit": true, "invalid": false, "guard": false, "damage": 0, "healed": 0, "mp_drained": 0, "status": 0, "killed": false, "amount": 0}
	var rs := []
	for x in [[a, 2, 147], [b, 0, 0], [c, 2, 147]]:
		var r := base.duplicate()
		r.merge({"unit": x[0], "code": x[1], "damage": x[2]}, true)
		rs.append(r)
	var p := BattleActions.result_plan(_spell(0), {"targets": rs})
	eq(p.size(), 2, "落空 (幻影) 的目标静默, 命中的两个各放各的 (实测多目标冰华之阵)")
	eq(p.map(func(e): return e.unit), [a, c])
	a.free()
	b.free()
	c.free()


func test_item_heal_and_poison_use_digits():
	var v := FakeView.new()
	var u := BattleUnit.new()
	v.digits(u, 12, true)
	eq(v.digits_calls[0][2], true, "道具回血走蓝色数字")
	u.free()
	v.free()


# ---------------- 道具使用 (实测 2026-10-17): 动画段与蓝数字 ----------------

func test_item_fx_ranges_limit_vs_others():
	for eff in [5, 6, 7, 8, 9, 10, 11]:
		eq(BattleActions.item_fx_range(eff), [18, 32], "上限提升 effect %d: 帧 18~31 (七种道具实测; 不是 60~80)" % eff)
	for eff in [0, 1, 2, 3, 4]:
		eq(BattleActions.item_fx_range(eff), [46, 60], "回血/回术力/解毒麻封 effect %d: 帧 46~59 (旧代码把两段对调了)" % eff)


func test_item_amount_is_what_was_gained():
	eq(BattleActions.item_amount({"healed": 40, "mp": 0, "raised": 0, "cured": 0}), 40, "金创药 +40")
	eq(BattleActions.item_amount({"healed": 0, "mp": 17, "raised": 0, "cured": 0}), 17, "返气丸 +17 术力")
	eq(BattleActions.item_amount({"healed": 0, "mp": 0, "raised": 7, "cured": 0}), 7, "灵泉玉露 +7 灵智上限")
	eq(BattleActions.item_amount({"healed": 0, "mp": 0, "raised": 15, "cured": 0}), 15, "八络血参 +15")
	eq(BattleActions.item_amount({"healed": 0, "mp": 0, "raised": 0, "cured": 1 << 12}), 0, "解状态没有数字")


func test_item_numbers_even_at_full_but_not_for_cures():
	for eff in [0, 1, 5, 6, 7, 8, 9, 10, 11]:
		check(BattleActions.item_has_number(eff), "effect %d 无条件弹蓝数字 (满血金创药 / 满蓝返气丸实测仍弹〇)" % eff)
	for eff in [2, 3, 4]:
		check(not BattleActions.item_has_number(eff), "effect %d 解毒/麻/封咒没有数字" % eff)

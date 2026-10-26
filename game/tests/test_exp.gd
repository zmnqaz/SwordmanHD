# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 08 经验 (测试数据全部来自玩家实测,)

const Exp = preload("res://engine/rules/exp.gd")


func _pc(lv: int):
	return unit({"lv": lv, "side": 0})


func _enemy(eff_lv: int, base_exp: int, hp_max: int = 1000):
	return unit({"side": 1, "lv": eff_lv, "base_lv": 0, "base_exp": base_exp, "hp_max": hp_max, "hp": hp_max})


## 第 14 幕高戚 (有效等级 41, base 500), 我方 31→51 级击杀 (网友数据 #5, 21 项逐项)
func test_gaoqi_21_levels():
	var c = ctx_scripted()
	var expect := [1000, 994, 979, 954, 919, 874, 819, 754, 679, 594, 499, 405, 320, 245, 180, 125, 80, 45, 20, 5, 1]
	var got := []
	for lv in range(31, 52):
		got.append(Exp.kill_exp(c, _pc(lv), _enemy(41, 500)))
	eq(got, expect, "高戚")


## 第 33 幕妖将 (有效等级 86, base 500), 我方 90~96 级: 最后一项 1 来自击杀经验保底
func test_yaojiang():
	var c = ctx_scripted()
	var got := []
	for lv in range(90, 97):
		got.append(Exp.kill_exp(c, _pc(lv), _enemy(86, 500)))
	eq(got, [180, 125, 80, 45, 20, 5, 1])


## 第 0 幕 3 级 / 4 级殷剑平杀夜魑 (有效等级 6, base 170): 256 / 231 (网友数据)
func test_stage0_kill_exp():
	var c = ctx_scripted()
	eq(Exp.kill_exp(c, _pc(3), _enemy(6, 170)), 256)
	eq(Exp.kill_exp(c, _pc(4), _enemy(6, 170)), 231)


## 第 0 幕 1 级殷剑平普攻夜魑 (HP 89) 伤 22 得 73, 格挡伤 9 得 30 (网友数据 #4); 未命中 0
func test_stage0_hit_exp():
	var c = ctx_scripted()
	var y = _pc(1)
	var e = _enemy(6, 170, 89)
	eq(Exp.attack_exp(c, y, e, true, 22, false), 73)
	eq(Exp.attack_exp(c, y, e, true, 9, false), 30)
	eq(Exp.attack_exp(c, y, e, false, 0, false), 0, "未命中 0")
	eq(Exp.attack_exp(c, y, _enemy(6, 170, 100000), true, 1, false), 1, "命中未杀至少 1")


## 多目标: 单杀羽魅 37, 离火杀 2 只 55, 杀 4 只 91 (网友数据; 羽魅 base 150, 我方高 5 级)
func test_multi_target_yumei():
	var c = ctx_scripted()
	var me = _pc(25)
	var entries := []
	var totals := []
	for i in 4:
		entries.append({"target": _enemy(20, 150), "damage": 9999, "killed": true})
		totals.append(Exp.skill_exp(c, me, entries))
	eq(totals[0], 37, "单杀")
	eq(totals[1], 55, "2 只 = 37 + 18")
	eq(totals[3], 91, "4 只 = 37 + 3×18")
	check(totals[3] != 37 * 4, "不是逐个相加")


## 只有阵营 0 非 NPC 非召唤物得经验
func test_exp_eligibility():
	var c = ctx_scripted()
	var e = _enemy(10, 100)
	eq(Exp.attack_exp(c, unit({"side": 0, "npc_ally": true, "lv": 1}), e, true, 1, true), 0, "友军 NPC")
	eq(Exp.attack_exp(c, unit({"side": 0, "summon": true, "lv": 1}), e, true, 1, true), 0, "召唤物")
	eq(Exp.attack_exp(c, unit({"side": 1, "lv": 1}), _pc(1), true, 1, true), 0, "敌人")


## 曲线: 同级 1, 高 10 级 2, 低 10 级 0; 龙吟表 我方高 1 级 81%、低 1 级 119%、低 5 级 175%
func test_curve_shape():
	var c = ctx_scripted()
	near(Exp.curve_k(c, 0), 1.0, 1e-6)
	near(Exp.curve_k(c, 10), 2.0, 1e-6)
	near(Exp.curve_k(c, -10), 0.0, 1e-6)
	near(Exp.curve_k(c, -1), 0.81, 1e-6)
	near(Exp.curve_k(c, 1), 1.19, 1e-6)
	near(Exp.curve_k(c, 5), 1.75, 1e-6)
	near(Exp.curve_k(c, 30), 2.0, 1e-6, "clamp 到 10")
	near(Exp.curve_k(c, -5, true), 0.125, 1e-6, "三次曲线")


## 治疗经验 = max(1, 200 × k × 回复量 / HPmax)
func test_heal_exp():
	var c = ctx_scripted()
	var me = _pc(10)
	var t = _pc(10)
	t.hp_max = 400
	eq(Exp.heal_exp(c, me, t, 100), 50, "200 × k(同级=1.0) × 100/400 = 50 (技能曲线 x² 先存 float32, 同级 k=1.0; 普攻曲线才是 0.99999997)")
	eq(Exp.heal_exp(c, me, t, 0), 1, "至少 1")


## 第 2 幕 (原版实测 2026-10-04): 封寒月 Lv1 打四象门剑 (Lv2 + base_lv 2 = 有效 4, base 220, HP 52):
## 击杀 332 (对话「获得332历练值」= 经验字段, 显示不做换算); 命中伤 44 → 280, 伤 33 → 210; Lv2 击杀 299
func test_stage2_fenghan_live():
	var c = ctx_scripted()
	var e = unit({"side": 1, "lv": 2, "base_lv": 2, "base_exp": 220, "hp_max": 52, "hp": 52})
	eq(Exp.kill_exp(c, _pc(1), e), 332)
	eq(Exp.attack_exp(c, _pc(1), e, true, 44, false), 280)
	eq(Exp.attack_exp(c, _pc(1), e, true, 33, false), 210)
	eq(Exp.kill_exp(c, _pc(2), e), 299)


## 治疗技能经验 (原版 官方 1.3 实测 2026-10-05, 殷剑平 Lv5 HPmax76 施「气愈之术/返命之阵」, 封寒月 Lv1 HPmax45; 对照_经验与成长.md §E):
##   单体治疗 d=-4 缺血 35/5/44 → 56/8/70; d=0 → 155; d=-2 → 99; d=+10 → 311; HPmax100 缺 75 → 54 (原版数据点 57/9/71/156/100/312/55 比这些各多 1,
##   因为那次选中的范围含殷剑平自己 (满血, 回复量 0, e2 = 1 照算))
func test_heal_exp_ref_points():
	var c = ctx_scripted()
	var f = _pc(1)
	f.hp_max = 45
	var yin = _pc(5)
	yin.hp_max = 76
	var single := func(caster, lvl, miss, hpmax):
		var t = _pc(lvl)
		t.hp_max = hpmax
		return Exp.heal_exp(c, caster, t, miss)
	eq(single.call(yin, 1, 35, 45), 56)
	eq(single.call(yin, 1, 5, 45), 8)
	eq(single.call(yin, 1, 44, 45), 70)
	eq(single.call(yin, 1, 75, 100), 54)
	eq(single.call(_pc(1), 1, 35, 45), 155)
	eq(single.call(_pc(3), 1, 35, 45), 99)
	eq(single.call(_pc(1), 11, 35, 45), 311)
	eq(single.call(yin, 5, 46, 76), 121, "原版: 自疗 缺 46/76")
	# 范围术: 总 = max(e1) + Σ 其余 e2 (三次曲线), 满血目标各贡献 1
	eq(Exp.heal_skill_exp(c, yin, [{"target": yin, "healed": 46}, {"target": f, "healed": 35}]), 154, "返命之阵 两人都缺血 121 + 33")
	eq(Exp.heal_skill_exp(c, yin, [{"target": yin, "healed": 0}, {"target": f, "healed": 35}]), 57, "只有封寒月缺血: 56 + 殷剑平满血 1")
	eq(Exp.heal_skill_exp(c, yin, [{"target": yin, "healed": 0}, {"target": f, "healed": 0}]), 2, "两人都满血 1 + 1")


## 伤害技能经验 (实测 S1: 殷剑平 Lv5 灭魂大法 范围内 3 个敌人): 击杀 (有效 Lv1, base 220) + 未击杀 B (有效 41, base 500, HP500, 伤 100)
## + 未击杀 C (有效 11, base 400, HP800, 伤 99) = 总经验 342 = B 的 e1 200 + A 的 e2 47 + C 的 e2 95
func test_skill_exp_ref_mixed():
	var c = ctx_scripted()
	var me = _pc(5)
	var a = _enemy(1, 220, 47)
	var b = _enemy(41, 500, 500)
	var cc = _enemy(11, 400, 800)
	eq(Exp.skill_exp(c, me, [{"target": a, "damage": 47, "killed": true}, {"target": b, "damage": 100, "killed": false}, {"target": cc, "damage": 99, "killed": false}]), 342)

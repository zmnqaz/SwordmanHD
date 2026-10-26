# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 敌方 (side 1) 带异常状态的招式能施加到我方单位, 与我方施放同一条结算路径、结果不分阵营。
## 用户 2026-10-17 「被怪物攻击时似乎不会产生异常状态, 看看是不是幻觉」: 结论是原版规则造成的观感 (主攻武器附加恒抵抗 T07、绝技附加要未格挡且命中且 R>=K),
## 这里把「敌方施放能中状态」固定下来, 防止以后有人在敌方路径上漏掉附加状态。
const REQUIRES := ["data"]

const Skills = preload("res://engine/rules/skills.gd")
const Attack = preload("res://engine/rules/attack.gd")
const Status = preload("res://engine/rules/status.gd")


func _caster(side: int):
	return unit({"side": side, "int": 150, "str": 150, "luk": 100, "lv": 30})


func _target(side: int):
	return unit({"side": side, "int": 40, "luk": 10, "vit": 20, "hp": 900, "hp_max": 900})


## 咒术诅咒 (封魔神道 32 封咒 / 夺魄鬼咒 34 麻痹) 与绝技 ot1 附加毒 (化血毒沫 69) / 地縛 (鬼缚之阵 78): 敌方 → 我方照样中
func test_enemy_cast_inflicts_status_on_player():
	var cases := {32: U.ST_SEAL, 34: U.ST_PARALYZE, 69: U.ST_POISON, 78: U.ST_BIND}
	for id in cases:
		var c = ctx_data()
		var t = _target(0)
		var out := Skills.resolve(c, _caster(1), c.skill(id), [t])
		check(not out.targets[0].invalid, "技能 %d 没被判无效" % id)
		check(t.has_status(int(cases[id])), "敌方放 %d → 我方中状态位 0x%x" % [id, int(cases[id])])
		check(t.status_k.has(int(cases[id])) and t.status_r.has(int(cases[id])), "R/K 已记")


## 同一招式、同样数值, 敌→我 与 我→敌 状态位与 R/K 完全一样 (结算不看阵营)
func test_status_result_does_not_depend_on_side():
	for id in [32, 34, 69, 78]:
		var c1 = ctx_data()
		var c2 = ctx_data()
		var a = _target(0)
		var b = _target(1)
		Skills.resolve(c1, _caster(1), c1.skill(id), [a])
		Skills.resolve(c2, _caster(0), c2.skill(id), [b])
		eq([a.status, a.status_r, a.status_k], [b.status, b.status_r, b.status_k], "技能 %d 不分阵营" % id)


## 武器附加毒/麻/封 (原版): 主攻 R=0<K 恒抵抗; 反击以 R=K=0 施加 (到目标阵营下一阶段开始即解除)。敌方持武器同理, 不是漏了
func test_weapon_add_main_resists_counter_applies():
	var c = ctx_data()
	var w := add_item(c, 900, {"attack_add": {"type": 1, "ratio": 100, "time": 0, "cost": 100}})
	var foe = unit({"side": 1, "weapon": w, "luk": 100})
	var hero = _target(0)
	var main := {"result": Attack.Result.HIT, "damage": 1, "add": true, "add_type": 1, "counter": false}
	Attack.apply_strike(c, foe, hero, main)
	check(not hero.has_status(U.ST_POISON), "主攻: 不施加 (原版 R=0<K)")
	var back := {"result": Attack.Result.HIT, "damage": 1, "add": true, "add_type": 1, "counter": true}
	var out := Attack.apply_strike(c, foe, hero, back)
	check(hero.has_status(U.ST_POISON) and out.status_applied == U.ST_POISON, "反击: R=K=0 施加")
	var r := Status.phase_tick(c, hero)
	check(U.ST_POISON in r.expired, "下一次本阵营阶段开始即解除")

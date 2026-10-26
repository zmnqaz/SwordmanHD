# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 04 咒术伤害、五魂修正、治疗、属性抗性

const Damage = preload("res://engine/rules/damage.gd")


func _spell(attr: int, power: int, spirit := []) -> Dictionary:
	var sa := []
	for i in 5:
		sa.append(spirit[i] if i < spirit.size() else {"type": -1, "request": 0, "plus": 0})
	return {"move_attack_type": 0, "power": power, "attribute": attr, "rate6": 100, "rate10": 0,
		"result_type": 0, "result_effect": -1, "spirit_addition": sa}


## P = power + Int/2 + 1 + rand%(Int/20+1); 技法提昇 power ×1.3
func test_spell_power():
	var c = ctx_scripted([3])
	var u = unit({"int": 100})
	eq(Damage.spell_power(c, u, _spell(1, 40)), 40 + 50 + 1 + 3)
	eq(Damage.spell_power(ctx_scripted([7]), u, _spell(1, 40)), 40 + 50 + 1 + 1, "rand%(100/20+1)=7%6")
	eq(Damage.spell_power(ctx_scripted(), u, _spell(1, 40), true), 40 + 50 + 1 + 2, "AI 估算 (Int/20)/2")
	u.status = U.ST_TECH_UP
	eq(Damage.spell_power(ctx_scripted(), u, _spell(1, 40)), 52 + 51, "技法提昇 power ×1.3 (不是 Int)")


## 五魂修正 S (只看目标): 区间外的差值累加, type 1 取反
func test_spirit_mod():
	var sk := _spell(2, 100, [{"type": -1, "request": 0, "plus": 0}, {"type": 1, "request": 30, "plus": 80}, {"type": -1, "request": 0, "plus": 0}, {"type": 1, "request": 15, "plus": 60}])
	var t = unit({})
	t.spirit = [50, 50, 50, 50, 50]
	eq(Damage.spirit_mod(t, sk), 0, "区间内")
	t.spirit = [50, 90, 50, 70, 50]
	eq(Damage.spirit_mod(t, sk), -20, "抗性型: 烈超 10、魔超 10 → -20")
	t.spirit = [50, 20, 50, 10, 50]
	eq(Damage.spirit_mod(t, sk), 15, "低于 req → 增伤 10 + 5")
	var heal := _spell(6, 60, [{"type": -1, "request": 0, "plus": 0}, {"type": -1, "request": 0, "plus": 0}, {"type": 0, "request": 0, "plus": 70}])
	t.spirit = [0, 0, 90, 0, 0]
	eq(Damage.spirit_mod(t, heal), 20, "易伤型 神 90 > 70")


## 咒术伤害: 护具/饰物抗性连乘, ×(100+S), ×MAG_OPP; 无保底; 抗性 >100 吸收
func test_spell_damage_resist():
	var c = ctx_scripted()
	c.mag_opp = [[100, 100, 100, 100, 100, 100], [75, 75, 75, 100, 75, 75], [100, 0, 100, 100, 100, 100]]
	add_item(c, 1, {"attribute_defence": {"雷": 0, "火": 20, "冰": 200, "幻": 0, "光": 0, "暗": 0}})
	add_item(c, 2, {"attribute_defence": {"雷": 0, "火": 50, "冰": 0, "幻": 0, "光": 0, "暗": 0}})
	var caster = unit({"int": 0})       # P = power + 1
	var t = unit({"armor": 1, "accessory": 2})
	eq(Damage.spell_damage(c, caster, t, _spell(1, 199)), 200 * 80 * 50 * 100 / 1000000, "火: 200×0.8×0.5 = 80")
	t.mag_opp_id = 1
	eq(Damage.spell_damage(c, caster, t, _spell(1, 199)), 60, "MAG_OPP 75%")
	t.mag_opp_id = 0
	t.accessory = -1
	eq(Damage.spell_damage(c, caster, t, _spell(2, 99)), -100, "冰抗 200 → 吸收 (负伤害)")
	t.mag_opp_id = 2
	eq(Damage.spell_damage(c, caster, t, _spell(1, 99)), 0, "MAG_OPP 0 → 免疫, 无保底")
	add_item(c, 3, {"attribute_defence": {"雷": 50, "火": 0, "冰": 0, "幻": 0, "光": 0, "暗": 0}})
	var t2 = unit({"weapon": 3})
	eq(Damage.spell_damage(c, caster, t2, _spell(0, 99)), 100, "武器的抗性字段不参与")


## 技能治疗: P × (100 + Vit/20 + S)/100 (对照原版); 中毒 ×0.8; 不超缺口
func test_heal_amount():
	var c = ctx_scripted()
	var caster = unit({"int": 0})
	var t = unit({"vit": 100, "hp": 1, "hp_max": 1000})
	var sk := _spell(6, 99)
	sk["result_type"] = 1
	eq(Damage.heal_amount(c, caster, t, sk), 105, "100 × 1.05 (Vit/20)")
	t.status = U.ST_POISON
	eq(Damage.heal_amount(c, caster, t, sk), 84, "中毒 ×0.8")
	t.status = 0
	t.hp = 950
	eq(Damage.heal_amount(c, caster, t, sk), 50, "不超过 HPmax")
	t.hp = 1
	eq(Damage.item_heal_hp(c, t, 100), 105, "物品回 HP ×(100+Vit/20)")
	t.mp = 0
	t.mp_max = 500
	t.stats["int"] = 200
	eq(Damage.item_heal_mp(c, t, 100), 110, "物品回 MP ×(100+Int/20)")


## ot0: phys(crit=0) → 攻升再 ×1.2 → + Str/(8+rand%13) → ×(100+S)
func test_ot0_damage():
	var c = ctx_scripted([0, 0])     # 运气除数 10, Str 除数 8
	var a = unit({"str": 160, "luk": 0})
	var d = unit({"vit": 120})      # DEF 60
	var sk := _spell(-1, 0)
	sk["move_attack_type"] = 1
	eq(Damage.skill_ot0_damage(c, a, d, sk), 100 + 20)
	a.status = U.ST_ATK_UP
	# ATK 192 - 60 = 132 → ×1.2 = 158 → + 160/8 = 178
	eq(Damage.skill_ot0_damage(ctx_scripted([0, 0]), a, d, sk), 178, "攻升对 ot0 生效两次")


## 自爆 = (HPmax-HP)/2 × MAG_OPP[火]/100
func test_self_destruct():
	var c = ctx_scripted()
	c.mag_opp = [[100, 50, 100, 100, 100, 100]]
	var s = unit({"hp": 100, "hp_max": 1000})
	var t = unit({})
	eq(Damage.self_destruct_damage(c, s, t), 225)


## 剧情扣血: 0x46 扣当前 HP 的 1/3 (最少剩 1, 不是 HPmax 33%); 0x4A HP、MP 各扣 1/3, MP<=0 置 1
func test_script_damage():
	var u = unit({"hp": 90, "hp_max": 500, "mp": 0})
	Damage.script_damage_46(u)
	eq(u.hp, 60)
	u.hp = 1
	Damage.script_damage_46(u)
	eq(u.hp, 1)
	var v = unit({"hp": 300, "mp": 0})
	Damage.script_damage_4a(v)
	eq([v.hp, v.mp], [200, 1])


## 属性无效 (-1) 的技能 (物理绝技的附加状态 R): 原版抗性乘数初值 0 → 伤害公式结果 0, 但威力随机数照取
func test_spell_damage_invalid_attribute_is_zero():
	var c = ctx_scripted([5])
	var caster = unit({"int": 100})
	var t = unit({"int": 0})
	var sk := _spell(-1, 300)
	eq(Damage.spell_damage(c, caster, t, sk), 0)
	eq(c.rng.used, 1, "威力随机数照取")


## 咒术伤害的 32 位乘法链会溢出 (原版 imul 回绕, 对照辉日圣烨): 22500 × 124 × 1001 = 2.79e9 > 2^31 → -1.50e9 → -1502
func test_spell_damage_int32_overflow():
	var c = ctx_scripted()
	add_item(c, 70, {"attribute_defence": {"雷": 0, "火": -50, "冰": 0, "幻": 0, "光": 0, "暗": 0}})
	add_item(c, 71, {"attribute_defence": {"雷": 0, "火": -50, "冰": 0, "幻": 0, "光": 0, "暗": 0}})
	c.mag_opp = [[100, 100, 100, 100, 100, 100]]
	var caster = unit({"int": 400})
	var t = unit({"armor": 70, "accessory": 71, "spirit": [0, 0, 0, 0, 1]})
	var none := {"type": -1, "request": 0, "plus": 0}
	var sk := _spell(1, 800, [none, none, none, none, {"type": 1, "request": 25, "plus": 85}])   # S = +24
	eq(Damage.spell_damage(c, caster, t, sk), -1502, "回绕成负 = 回血")

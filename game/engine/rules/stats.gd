# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 派生战斗值、敌人与召唤物属性 (规格 §3 §6)。

const Bits = preload("res://engine/rules/bits.gd")
const U = preload("res://engine/rules/unit_state.gd")
const AttrNames = preload("res://engine/rules/attr_names.gd")
const Ctx = preload("res://engine/rules/context.gd")


## ATK = Str + 武器.attack + 饰物.attack (护具不计)
static func atk(ctx, u) -> int:
	return u.get_stat("str") + int(ctx.item(u.weapon).get("attack", 0)) + int(ctx.item(u.accessory).get("attack", 0))


## DEF = 护具.defence + Vit/2 + 饰物.defence (武器不计)
## 爆發不降防; burst_def_num/den ≠ 1/1 时为魔改降防
static func def(ctx, u) -> int:
	var d: int = int(ctx.item(u.armor).get("defence", 0)) + u.get_stat("vit") / 2 + int(ctx.item(u.accessory).get("defence", 0))
	if u.burst_reserve != 0 and ctx.params.burst_def_num != ctx.params.burst_def_den:
		d = d * ctx.params.burst_def_num / ctx.params.burst_def_den
	return d


## MOV_base = Man_base.move + Avg/25
static func mov_base(ctx, u) -> int:
	return u.move_base + u.get_stat("avg") / ctx.params.move_avg_div


## 装备字段求
static func equip_sum(ctx, u, field: String, slots: Array) -> int:
	var s := 0
	for slot in slots:
		var id: int = u.get(slot)
		s += int(ctx.item(id).get(field, 0))
	return s


## 当前武器射程; 无武器 = 物品 -1 的全 0 记录 → 菱形 min0/max0 只含自身格
static func weapon_range(ctx, u) -> Dictionary:
	var w: Dictionary = ctx.item(u.weapon)
	if w.has("attack_range"):
		return w["attack_range"]
	return ctx.params.default_attack_range


## 目标对某属性的减伤 (护具、饰物; 武器的抗性字段不计)
static func resist(ctx, u, slot: String, attribute: int) -> int:
	if attribute < 0 or attribute > 5:
		return 0
	var rec: Dictionary = ctx.item(u.get(slot))
	if not rec.has("attribute_defence"):
		return 0
	return int(rec["attribute_defence"].get(Ctx.ATTR_KEYS[attribute], 0))


## MAG_OPP 抗性表行号 [原版 对照]:
##   默认 = 单位 +2 (Man_base.attribute_defence_id); 但护具记录 字段 ≠ -1 时用护具的值 (数据里全是 -1, 魔改可用);
##   无护具 (-1) 时读到物品 -1 = 全 0 记录, 字段 = 0 ≠ -1 → 行 0 (与单位自己的抗性表无关)
static func mag_row(ctx, u) -> int:
	if u.armor < 0:
		return 0
	var v: int = int(ctx.item(u.armor).get("unknown33", -1))
	return u.mag_opp_id if v == -1 else v


## 敌人 / NPC: 属性 = 基础 + 成长 × MAN.lv + MAN 加值; 有效等级 = MAN.lv + base_lv
## base_def = units.json 记录; plus = {hp,mp,str,int,avg,vit,luk} 加值 (MAN 表)
static func make_enemy(base_def: Dictionary, man_lv: int, plus: Dictionary = {}, side: int = 1):
	var u = U.new()
	u.unit_id = int(base_def.get("id", -1))
	u.name = str(base_def.get("name", ""))
	u.side = side
	u.lv = man_lv
	u.base_lv = int(base_def.get("base_lv", 0))
	u.base_exp = int(base_def.get("base_exp", 0))
	u.hp_max = int(base_def.get("hp", 1)) + int(base_def.get("hp_grow", 0)) * man_lv + int(plus.get("hp", 0))
	u.hp = u.hp_max
	u.mp_max = int(base_def.get("mp", 0)) + int(base_def.get("mp_grow", 0)) * man_lv + int(plus.get("mp", 0))
	u.mp = u.mp_max
	for k in AttrNames.STAT_KEYS:
		u.stats[k] = int(base_def.get(k, 0)) + int(base_def.get(k + "_grow", 0)) * man_lv + int(plus.get(k, 0))
	u.move_base = int(base_def.get("move", 20))
	u.move_type = int(base_def.get("move_type", 0))
	u.mag_opp_id = int(base_def.get("attribute_defence_id", 0))
	# 字段 = Man_base[40] (units.json defence_type), 只有齐祀 uid85 = 1: 不计入全灭
	u.annihilation_exempt = int(base_def.get("defence_type", 0)) != 0
	u.ai = 1
	return u


## 召唤物: 各项 = 施术者当时值 × Man_base 百分比 / 100, 五项属性封顶 500; lv = 施术者 lv
## base_def 的 hp/mp/str/... 字段在召唤物记录里就是百分比。召唤时物品栏清空。
static func make_summon(ctx, caster, base_def: Dictionary):
	var u = U.new()
	u.unit_id = int(base_def.get("id", -1))
	u.name = str(base_def.get("name", ""))
	u.side = caster.side
	u.summon = true
	u.lv = caster.lv
	# HP: u16 读 x u16 百分比 / 100, 低 16 位写回 (HPmax 65000 x 150% -> 31964); MP: s16 读 x s16 百分比 / 100, 低 16 位写回 (读回仍是 s16)
	# [实机: 原版召唤物 HPmax 31964/18964/2714]
	u.hp_max = Bits.u16(Bits.u16(caster.hp_max) * Bits.u16(int(base_def.get("hp", 100))) / 100)
	u.hp = u.hp_max
	u.mp_max = Bits.s16(Bits.s16(caster.mp_max) * Bits.s16(int(base_def.get("mp", 100))) / 100)
	u.mp = u.mp_max
	for k in AttrNames.STAT_KEYS:
		u.stats[k] = mini(ctx.params.stat_cap, caster.get_stat(k) * int(base_def.get(k, 100)) / 100)
	u.move_base = int(base_def.get("move", 20))
	u.move_type = int(base_def.get("move_type", 0))
	u.mag_opp_id = int(base_def.get("attribute_defence_id", 0))
	u.items = []
	u.ai = -1
	return u

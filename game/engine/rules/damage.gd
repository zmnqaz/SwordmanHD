# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 伤害与回复。`/` = C 整数除法 (向零截断), 浮点乘法 = _ftol 截断; 这里一律写成整数分数。

const Bits = preload("res://engine/rules/bits.gd")
const U = preload("res://engine/rules/unit_state.gd")
const Stats = preload("res://engine/rules/stats.gd")
const Status = preload("res://engine/rules/status.gd")


## 物理伤害 (普攻、反击、物理绝技共用)
## crit: 会心 = 守方防御再减半; ai_estimate: 运气项固定 Luk/15
## 返回 >= 0 (保底在调用方)
static func phys_damage(ctx, a, d, crit: bool, ai_estimate: bool = false) -> int:
	var p = ctx.params
	var atk: int = Stats.atk(ctx, a)
	if a.has_status(U.ST_ATK_UP):
		atk = atk * p.atk_up_num / p.atk_up_den
	if a.has_status(U.ST_BERSERK):
		atk = atk * p.berserk_atk_mult
	var df: int = Stats.def(ctx, d)
	if d.has_status(U.ST_DEF_UP):
		df = df * p.def_up_num / p.def_up_den
	if d.has_status(U.ST_BERSERK):
		df = df / p.berserk_def_div
	if crit:
		df = df / p.crit_def_div
	var luck: int
	if ai_estimate:
		luck = a.get_stat("luk") / p.ai_luk_div
	else:
		luck = a.get_stat("luk") / (p.dmg_luk_div_min + ctx.rng.mod(p.dmg_luk_div_span))
	return maxi(0, atk - df + luck)


## 普攻/反击最终伤害: 保底 1 → 连击 ×2 → 格挡 dmg/2 - 守Vit/10 (保底 1)
static func strike_damage(ctx, raw: int, double: bool, guard: bool, defender) -> int:
	var p = ctx.params
	var dmg := raw
	if dmg <= 0:
		dmg = p.min_hit_damage
	if double:
		dmg *= p.double_mult
	if guard:
		dmg = dmg / 2 - defender.get_stat("vit") / p.guard_vit_div
		if dmg <= 0:
			dmg = p.min_guard_damage
	return dmg


## 咒术威力 P = pw + Int/2 + 1 + r; 技法提昇 power ×1.3; r = rand%(Int/20+1), AI 估算 (Int/20)/2
## 高。power_override >= 0 时用它 (物品发动: 物品 字段)
static func spell_power(ctx, caster, skill: Dictionary, ai_estimate: bool = false, power_override: int = -1) -> int:
	var p = ctx.params
	var pw: int = power_override if power_override >= 0 else int(skill.get("power", 0))
	if caster.has_status(U.ST_TECH_UP):
		pw = pw * p.tech_up_num / p.tech_up_den
	var iv: int = caster.get_stat("int")
	var r: int
	if ai_estimate:
		r = (iv / p.spell_int_rand_div) / 2
	else:
		r = ctx.rng.mod(iv / p.spell_int_rand_div + 1)
	return pw + iv / 2 + 1 + r


## 五魂修正 S (只看【目标】五魂)
## 三元组 (type, req, plus): v<req → v-req; v>plus → v-plus; 否则 0; type 1 取反; 加法累计
static func spirit_mod(target, skill: Dictionary) -> int:
	var s := 0
	var arr: Array = skill.get("spirit_addition", [])
	for i in mini(5, arr.size()):
		var e: Dictionary = arr[i]
		var t: int = int(e.get("type", -1))
		if t == -1:
			continue
		var req: int = int(e.get("request", 0))
		var plus: int = int(e.get("plus", 0))
		var v: int = int(target.spirit[i])
		var dlt := 0
		if v < req:
			dlt = v - req
		elif v > plus:
			dlt = v - plus
		if t == 1:
			dlt = -dlt
		s += dlt
	return s


## 咒术伤害 (rt0; 诅咒剩余值也用它):
##   d = P × (100-护具抗) × (100-饰物抗) × (100+S) / 1e6 ; d = d × MAG_OPP[表][属性] / 100
## 可为负 (回血)、可为 0, 无保底 高; (100+S)<0 按 0
static func spell_damage(ctx, caster, target, skill: Dictionary, ai_estimate: bool = false, power_override: int = -1) -> int:
	var attr: int = int(skill.get("attribute", -1))
	var pp: int = spell_power(ctx, caster, skill, ai_estimate, power_override)   # 威力的随机数照取
	if attr < 0 or attr > 5:
		# 属性无效 (-1: 全部物理绝技的 R 计算, 如 ot1 的麻/毒/封): 的抗性乘数初值 0, 不进属性跳转 → 结果 0
		# [原版 对照: 天罚神脚 / 无极天光 的 R 恒为 0, 持续只有 1 次结算]
		return 0
	var s: int = maxi(0, 100 + spirit_mod(target, skill))
	# 32 位 imul 链: (100-护具抗)(100-饰物抗)(100+S) × P 可能溢出 int32 (威力大 + 抗性为负 / 五魂修正大), 原版回绕成负数
	# → 变成回血 / 0 辉日圣烨 P≈1000 × 抗 -50 × S 24 溢出, 原版得负值而 64 位算法得 1779
	var prod: int = _i32((100 - Stats.resist(ctx, target, "armor", attr)) * (100 - Stats.resist(ctx, target, "accessory", attr)))
	prod = _i32(prod * s)
	prod = _i32(prod * pp)
	var d: int = prod / 1000000
	d = _i32(d * ctx.mag_opp_value(Stats.mag_row(ctx, target), attr)) / 100
	return d


## 回绕成有符号 32 位 (模拟 x86 imul)
static func _i32(v: int) -> int:
	v = v & 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


## ot0 物理绝技 (無方飛劍等): phys(crit=0); 攻升再 ×1.2; + Str/(8+rand%13); × (100+S)/100
## 格挡由调用方判定 (d/2, 无保底) 高; S 取整
## ai_estimate (AI 估价, flag=1): 运气项【真掷】1 次, Str 除数固定 14 [原版 直接调用:
## 估价一次 ot0 消耗 2 次随机数 = 运气项 + 格挡; 旧复刻运气项固定 Luk/15]
static func skill_ot0_damage(ctx, a, d, skill: Dictionary, ai_estimate: bool = false) -> int:
	var p = ctx.params
	var dmg: int = phys_damage(ctx, a, d, false, false)
	if a.has_status(U.ST_ATK_UP):
		dmg = dmg * p.atk_up_num / p.atk_up_den
	var div: int
	if ai_estimate:
		div = p.skill_str_div_min + (p.skill_str_div_span - 1) / 2
	else:
		div = p.skill_str_div_min + ctx.rng.mod(p.skill_str_div_span)
	dmg += a.get_stat("str") / div
	dmg = dmg * maxi(0, 100 + spirit_mod(d, skill)) / 100
	return dmg


## 技能治疗 h = P × (100 + 目标Vit/20 + S)/100 (对照原版是 Vit/20, 不是 /10); 中毒 ×0.8; 不超过缺口
static func heal_amount(ctx, caster, target, skill: Dictionary, ai_estimate: bool = false, power_override: int = -1) -> int:
	var p = ctx.params
	var pp: int = spell_power(ctx, caster, skill, ai_estimate, power_override)
	var h: int = pp * maxi(0, 100 + target.get_stat("vit") / p.skill_heal_vit_div + spirit_mod(target, skill)) / 100
	if target.has_status(U.ST_POISON):
		h = h * p.poison_heal_num / p.poison_heal_den
	return Bits.clamp_hp_gain(h, target.hp, target.hp_max)


## 物品回 HP: base × (100 + Vit/20)/100; 中毒 ×0.8; 不超过上限
static func item_heal_hp(ctx, target, base: int) -> int:
	var p = ctx.params
	var h: int = base * (100 + target.get_stat("vit") / p.heal_vit_div) / 100   # /20: 原版 对照 (金创药 Vit 400 → ×1.2)
	if target.has_status(U.ST_POISON):
		h = h * p.poison_heal_num / p.poison_heal_den
	return Bits.clamp_hp_gain(h, target.hp, target.hp_max)


## 物品回 MP: base × (100 + Int/20)/100; 不超过上限
static func item_heal_mp(ctx, target, base: int) -> int:
	var h: int = base * (100 + target.get_stat("int") / ctx.params.item_mp_int_div) / 100
	return Bits.clamp_mp_gain(h, target.mp, target.mp_max)


## 自爆: (施术者 HPmax - HP)/2 × 目标 MAG_OPP[火]/100
static func self_destruct_damage(ctx, caster, target) -> int:
	return (caster.hp_max - caster.hp) / 2 * ctx.mag_opp_value(Stats.mag_row(ctx, target), 1) / 100


## 施加一次命中的伤害 (负数 = 回复, 不超上限)。HP 按 u16。
## 只在「命中」时调用: 受击即解冰結, 伤害为 0 或负 (属性吸收) 也解。返回是否死亡。
static func apply_damage(u, dmg: int) -> bool:
	if dmg >= 0:
		u.hp = maxi(0, u.hp - dmg)
	else:
		u.hp = mini(u.hp_max, u.hp - dmg)
	Status.on_damaged(u, dmg)
	if u.hp <= 0:
		u.alive = false
		return true
	return false


## h 已按缺口封顶 (heal_amount/item_heal_hp, 可为负); 写回是 16 位加法 (u16 回绕)
static func apply_heal(u, h: int) -> void:
	u.hp = Bits.u16(u.hp + h)


## 剧情扣血 0x46 (第 23 关): 玩家单位 hp -= 当前hp/3, 最少剩 1, 无动画
static func script_damage_46(u) -> void:
	u.hp = maxi(1, u.hp - u.hp / 3)


## 剧情扣血 0x4A (第 29 关): hp -= hp/3, mp -= mp/3, mp <= 0 时置 1
static func script_damage_4a(u) -> void:
	u.hp -= u.hp / 3
	u.mp -= u.mp / 3
	if u.mp <= 0:
		u.mp = 1

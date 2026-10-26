# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 攻击判定: 命中、会心、连击、格挡 (红闪避)、反击、射程, 以及一次普攻交换的完整流程 (§6, §3)。

const U = preload("res://engine/rules/unit_state.gd")
const Stats = preload("res://engine/rules/stats.gd")
const Damage = preload("res://engine/rules/damage.gd")
const Status = preload("res://engine/rules/status.gd")
const Exp = preload("res://engine/rules/exp.gd")

enum Result { MISS, HIT, GUARD }


## 命中
##   守方 對技全禦/幻影 → 0; 守方狂暴 → 100
##   h = 攻.武器hit + 攻.饰物hit - (守.护具miss + 守.饰物miss) + (攻Luk - 守Luk)/4, clamp 0..100
static func hit_rate(ctx, a, d) -> int:
	if d.has_status(U.ST_GUARD_SKILL) or d.has_status(U.ST_PHANTOM):
		return 0
	if d.has_status(U.ST_BERSERK):
		return 100
	var h: int = Stats.equip_sum(ctx, a, "hit", ["weapon", "accessory"]) - Stats.equip_sum(ctx, d, "miss", ["armor", "accessory"])
	h += (a.get_stat("luk") - d.get_stat("luk")) / ctx.params.hit_luk_div
	return clampi(h, 0, 100)


## 会心 = 武器 + 饰物 (护具不计, Luk 不影响); 狂暴 ×1.5; <=100
static func crit_rate(ctx, a) -> int:
	var c: int = Stats.equip_sum(ctx, a, "critical", ["weapon", "accessory"])
	if a.has_status(U.ST_BERSERK):
		c = c * ctx.params.berserk_crit_num / ctx.params.berserk_crit_den
	return mini(c, 100)


## 连击 = 武器 + 饰物, <=100
static func double_rate(ctx, a) -> int:
	return mini(Stats.equip_sum(ctx, a, "double", ["weapon", "accessory"]), 100)


## 格挡 (红闪避) = 5 + (守Luk - 攻Luk)/10, clamp 0..100
## 主攻 guard(攻, 守)、反击 guard(反击者, 原攻方): 恒为 出手方 / 挨打方
static func guard_rate(ctx, a, d) -> int:
	var p = ctx.params
	var g: int
	if p.guard_def_minus_atk:
		g = p.guard_base + (d.get_stat("luk") - a.get_stat("luk")) / p.guard_luk_div
	else:
		g = p.guard_base + 1 + (a.get_stat("luk") - d.get_stat("luk")) / p.guard_luk_div
	return clampi(g, 0, 100)


## 武器附加几率 = 武器.add_ratio + (攻Luk - 守Luk)/10, clamp 0..100; 只看武器
static func add_rate(ctx, a, d) -> int:
	var add: Dictionary = ctx.item(a.weapon).get("attack_add", {})
	if int(add.get("type", -1)) < 0:
		return 0
	return clampi(int(add.get("ratio", 0)) + (a.get_stat("luk") - d.get_stat("luk")) / ctx.params.add_luk_div, 0, 100)


## 射程格 (相对 center), 不看地形与单位
##   菱形: min+1 <= d <= max (min 是开区间下限); min=-1 → 1..max 排除自身; min=0 → 含自身;
##         结果为空且 min≠-1 → 只有自身一格
##   直线: 四方向各取 max(1,min+1)..max; 除 min=-1 外含中心
static func range_cells(center: Vector2i, rg: Dictionary) -> Array:
	var t: int = int(rg.get("type", 0))
	var mn: int = int(rg.get("min", -1))
	var mx: int = int(rg.get("max", 1))
	var out := []
	if t == 1:
		# 生成的格表按「行优先」(y 升序、同行 x 升序) 排列 (同一 range 对象的列表顺序),
		# 与后面的目标表顺序 (区域选目标 按此表顺序取) 和 AI 候选格的并列取舍有关
		if mn != -1:
			out.append(center)
		for dv in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			for dist in range(maxi(1, mn + 1), mx + 1):
				out.append(center + dv * dist)
		out.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	else:
		var lo: int = mn + 1
		for dy in range(-mx, mx + 1):
			for dx in range(-mx, mx + 1):
				var dist: int = absi(dx) + absi(dy)
				if dist == 0:
					if mn == 0:
						out.append(center)
					continue
				if dist >= lo and dist <= mx:
					out.append(center + Vector2i(dx, dy))
	if out.is_empty() and mn != -1:
		out.append(center)
	return out


static func in_range(from: Vector2i, to: Vector2i, rg: Dictionary) -> bool:
	return range_cells(from, rg).has(to)


## 能否反击: 只有普攻引发; 守方未死; 无麻痺/冰結; 爆發保留点 == 0; 攻方在守方武器射程内
static func can_counter(ctx, d, a) -> bool:
	if not a.alive:
		return false
	return can_counter_at(ctx, d, a.pos())


## can_counter 的位置参数版 (at = 攻方所在格): AI 打分时反击射程按决策前起点判定
static func can_counter_at(ctx, d, at: Vector2i) -> bool:
	if not d.alive:
		return false
	if d.has_status(U.ST_PARALYZE) or d.has_status(U.ST_FREEZE):
		return false
	if d.burst_reserve != 0:
		return false
	return in_range(d.pos(), at, Stats.weapon_range(ctx, d))


## 一次普攻判定 (主攻 / 反击 同流程) 高。只算结果, 不改状态。
##   命中 → 会心 → 连击 → 伤害 (运气随机) → 格挡 → 武器附加 (仅未格挡), 每步独立取随机数
##   estimate: AI 估价 (运气项固定)
##   counter: 反击路径 (武器附加毒/麻/封只在反击时生效)
##   ui_x: 玩家光标发起的攻击 (路径) = 目标格 x, ≥0 时作为 type 4 的未初始化倍率; -1 = AI/友军路径 (见 type4_mult)
static func strike(ctx, a, d, counter: bool = false, estimate: bool = false, ui_x: int = -1) -> Dictionary:
	var res := {"result": Result.MISS, "crit": false, "double": false, "damage": 0, "add": false, "add_type": -1,
		"counter": counter}
	if ctx.rng.mod(100) >= hit_rate(ctx, a, d):
		return res
	res.crit = ctx.rng.mod(100) < crit_rate(ctx, a)
	res["double"] = ctx.rng.mod(100) < double_rate(ctx, a)
	var raw: int = Damage.phys_damage(ctx, a, d, res.crit, estimate)
	res["raw"] = raw   # estimate (AI 估价): 运气项固定 Luk/15, 命中/会心/连击/格挡照掷 [的 flag 只传给伤害函数]
	var guard: bool = ctx.rng.mod(100) < guard_rate(ctx, a, d)
	res.damage = Damage.strike_damage(ctx, raw, res["double"], guard, d)
	if guard:
		res.result = Result.GUARD
		return res
	res.result = Result.HIT
	if ctx.rng.mod(100) < add_rate(ctx, a, d):
		res.add = true
		res.add_type = int(ctx.item(a.weapon).get("attack_add", {}).get("type", -1))
		if res.add_type == 4:
			res.damage = maxi(1, add4_damage(ctx, a, d, res.damage, type4_mult(ctx, estimate, ui_x)))   # 结果 ≤0 取 1
		elif res.add_type >= 1 and res.add_type <= 3 and ctx.params.weapon_status_mode != "custom":
			# 毒/麻/封: 结算时原版先后调 R 函数 (威力式: 取一次随机数) 与 K 函数 (祝福式扣减值),
			# 无论主攻/反击、目标是否被打死都取这两次随机数 [原版实测对照: 同种子下比旧实现多 1 次取数]。
			# 估价 (estimate) 时两者都不取随机数。R 的结果只用于主攻比较 R<K, 复刻按 恒判抵抗, 故只消耗随机数
			if not estimate:
				ctx.rng.rand()
			res["add_k"] = Status.curse_k(ctx, d, int(ctx.item(a.weapon).get("attack_add", {}).get("cost", 0)), estimate)
	return res


## 「红闪避」演出: 一次普攻结果 (strike 的返回) 是格挡时, 返回全屏闪光参数
## {color: Color, sec: float}; 否则 {}。伤害数字照常 (不变红)。纯演出, 由战场界面在命中那一刻播放
static func guard_flash(ctx, res: Dictionary) -> Dictionary:
	if int(res.get("result", Result.MISS)) != Result.GUARD or float(ctx.params.guard_flash_sec) <= 0.0:
		return {}
	var c: Array = ctx.params.guard_flash_color
	return {"color": Color8(int(c[0]), int(c[1]), int(c[2])), "sec": float(ctx.params.guard_flash_sec)}


## type 4 属性化普攻 : 替换本次伤害, 不附加状态
##   dmg × (100 - 守护具抗)(100 - 守饰物抗)/10000 × MAG_OPP[守][属性]/100; 属性 = 武器 attack_attribute (字段)
##   属性无效 (紫金劍 -1): 抗性按 0, 倍率取原版的未定义值 (约定见 type4_mult)
static func add4_damage(ctx, a, d, dmg: int, undefined_mag: int = -1) -> int:
	var attr: int = int(ctx.item(a.weapon).get("attack_attribute", -1))
	if attr < 0 or attr > 5:
		var mag: int = undefined_mag if undefined_mag >= 0 else ctx.params.weapon_add4_ai_path_mag
		return dmg * mag / 100
	var v: int = dmg * (100 - Stats.resist(ctx, d, "armor", attr)) * (100 - Stats.resist(ctx, d, "accessory", attr)) / 10000
	return v * ctx.mag_opp_value(Stats.mag_row(ctx, d), attr) / 100


## type 4 且武器属性 −1 (无效) 时的倍率是原版的未定义行为, 无法逐位复现, 复刻按下面的约定取值:
##   · 玩家光标普攻: 目标格 x (确定、可复现; 原版实测与之吻合)
##   · AI 估价: 1 (估价伤害 ×1/100 取下限 1)
##   · 敌方发起的反击: params.weapon_add4_ai_path_mag (缺省 0 → 伤害取下限 1, 不给免费击杀, 与「难度不降低」一致)
static func type4_mult(ctx, estimate: bool, ui_x: int) -> int:
	if estimate:
		return 1
	if ui_x >= 0:
		return ui_x
	return ctx.params.weapon_add4_ai_path_mag


## 把 strike 结果作用到单位上。返回 {killed, vampire, status_applied}
static func apply_strike(ctx, a, d, res: Dictionary) -> Dictionary:
	var out := {"killed": false, "vampire": 0, "status_applied": 0}
	if res.result == Result.MISS:
		return out
	var hp_before: int = d.hp
	out.killed = Damage.apply_damage(d, res.damage)
	if res.add:
		res["target_hp_before"] = hp_before
		_apply_weapon_add(ctx, a, d, res, out)
	return out


## 武器附加效果 (命中且未格挡)
static func _apply_weapon_add(ctx, a, d, res: Dictionary, out: Dictionary) -> void:
	var add: Dictionary = ctx.item(a.weapon).get("attack_add", {})
	match int(res.add_type):
		0:  # 吸血 dmg/3, 不超过上限
			# 吸血量 = min(伤害, 目标受击前剩余 HP) / 3, 再受攻方缺口限制 溢出的伤害不吸 (hp-伤害<=0 取 hp/3)
			var v: int = mini(mini(res.damage, int(res.get("target_hp_before", res.damage))) / ctx.params.vampire_div, a.hp_max - a.hp)
			a.hp += maxi(0, v)
			out.vampire = maxi(0, v)
			out["vampire_hit"] = true   # 近景表现看触发, 不看吸到多少 (满血吸 0 也放光环、弹「〇」, 实测)
		1, 2, 3:  # 毒 / 麻 / 封
			if not d.alive:
				return
			var bit: int = Status.WEAPON_ADD_BITS[int(res.add_type)]
			if ctx.params.weapon_status_mode == "custom":
				if Status.apply(d, bit, int(add.get("time", 0)), int(add.get("cost", 0))):
					out.status_applied = bit
				return
			# 原版: R 函数越界读 → R = 0; K = cost + 2×(目标Int/(5+rand%6)) (实测 106/104); R、K 的随机数在 strike 里已取
			if res.get("counter", false):
				# 反击路径 比较另一组字段, 照样施加 R=K=0 → 目标阵营下一阶段开始即解除
				Status.apply(d, bit, 0, 0)
				out.status_applied = bit
			# 主攻路径: R(0) < K → 抵抗, 不施加
		4:  # 属性化普攻: 伤害已在 strike 中替换 (add4_damage), 无其他效果
			pass


## 一次完整的普攻交换: 主攻 → (反击一次) → 经验。不处理演出、剧情变量。
## 返回 {main, main_apply, counter (或 null), counter_apply, exp_attacker, exp_defender}
## post_strike (可选): 每次 strike 之后、apply_strike 之前调用 post_strike.call(攻方, 守方, 结算结果), 可改结果 (战场的 --god 开关用); 缺省不动
static var trace := false   # 对照追踪 (--ai-trace): 打印每次普攻交换的结果


static func _tr(ctx, tag: String, a, d, r: Dictionary) -> void:
	print("  交换%s %d->%d rng=%d %s 伤%d raw%s 暴%s 连%s" % [tag, a.uid, d.uid, ctx.rng.get_state(), ["未中", "命中", "格挡"][r.result] if r.result < 3 else str(r.result), r.damage, r.get("raw", "-"), r.crit, r["double"]])


static func exchange(ctx, a, d, post_strike := Callable()) -> Dictionary:
	var rec := {"main": null, "main_apply": null, "counter": null, "counter_apply": null, "exp_attacker": 0, "exp_defender": 0}
	# 反击资格 (麻痺/冰結/保留点/射程) 在主攻结算伤害之前判定: 冰結受伤即解, 但本次交换仍不反击 ——
	# 这才符合「冰封后有一次打他不被反击的机会」 反击判定 读当时的 0x2000 位
	var counter_ok := can_counter(ctx, d, a)
	# type 4 未初始化倍率: 玩家一侧 (非友军 NPC) 经光标发起 → 目标格 x; 其余 (敌方/友军 AI 发起) 走 AI 路径 (见 type4_mult)
	var ui_x: int = d.x if (a.side == 0 and not a.npc_ally) else -1
	var r1 := strike(ctx, a, d, false, false, ui_x)
	if post_strike.is_valid():
		post_strike.call(a, d, r1)
	var ap1 := apply_strike(ctx, a, d, r1)
	rec.main = r1
	rec.main_apply = ap1
	if trace:
		_tr(ctx, "主", a, d, r1)
	# 普攻经验: 格挡算命中, 用格挡后伤害; 连击用合并伤害
	rec.exp_attacker = Exp.attack_exp(ctx, a, d, r1.result != Result.MISS, r1.damage, ap1.killed)
	if counter_ok and d.alive and a.alive:
		var r2 := strike(ctx, d, a, true, false, ui_x)
		if post_strike.is_valid():
			post_strike.call(d, a, r2)
		var ap2 := apply_strike(ctx, d, a, r2)
		rec.counter = r2
		rec.counter_apply = ap2
		if trace:
			_tr(ctx, "反", d, a, r2)
		rec.exp_defender = Exp.attack_exp(ctx, d, a, r2.result != Result.MISS, r2.damage, ap2.killed)
		if not a.alive:
			rec.exp_attacker = 0   # 攻方被反击打死: 原版结果记录经验 -1 (无经验) [实机对照]
	return rec

# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 绝技与咒术: 使用条件、命中、各类效果。
## skill = skills.json 记录。分类只看 move_attack_type (+0): ≠0 绝技, 0 咒术。

const U = preload("res://engine/rules/unit_state.gd")
const Bits = preload("res://engine/rules/bits.gd")
const Damage = preload("res://engine/rules/damage.gd")
const Status = preload("res://engine/rules/status.gd")
const Attack = preload("res://engine/rules/attack.gd")
const Movement = preload("res://engine/rules/movement.gd")
const Exp = preload("res://engine/rules/exp.gd")

const RT_DAMAGE := 0
const RT_HEAL := 1
const RT_PURIFY := 2
const RT_BLESS := 3
const RT_CURSE := 4
const RT_SPECIAL := 5
const ATTR_ICE := 2
const ATTR_FIRE := 1


static func is_physical(skill: Dictionary) -> bool:
	return int(skill.get("move_attack_type", 0)) != 0


static func is_self_destruct(skill: Dictionary) -> bool:
	return is_physical(skill) and int(skill.get("other_type", -1)) == 2 and int(skill.get("other_effect", -1)) == 9


## 召唤置位的标志变量: 取**技能记录自己的** rate10 [实机: 剑魂石‧紫 (物品 字段 = 104) 召唤后 var103=1、var104=0, 召唤物 字段=103;
## 剑雄/剑雌/灵鼩技能 95/96/97 与式鬼 40 的 rate10 都是 103 → 四种召唤共用一个标志, 同时只能有一只 (旧复刻按物品的 104~106 置位, 可同时召多种)]
static func summon_flag_var(ctx, skill: Dictionary) -> int:
	var base: Dictionary = ctx.skill(int(skill.get("id", -1)))
	return int(base.get("rate10", skill.get("rate10", 0))) if not base.is_empty() else int(skill.get("rate10", 0))


static func is_summon(skill: Dictionary) -> bool:
	return int(skill.get("result_type", -1)) == RT_SPECIAL and int(skill.get("result_effect", -1)) == 14


## 使用条件
##   封咒 → 不可 (绝技也禁); MP 不足 → 不可; 咒术: 本阶段已移动 → 不可; 绝技: 剩余移动点(含保留点) < move_cost → 不可;
##   自爆: HP > HPmax/2 → 不可; 召唤: 标志变量[rate10] ≠ 0 → 不可
## summon_flags: 剧情变量表 (103~106), 由调用方提供
static func can_use(ctx, u, skill: Dictionary, summon_flags: Dictionary = {}, mp_cost_override: int = -1) -> bool:
	if u.has_status(U.ST_SEAL):
		return false
	var cost: int = mp_cost_override if mp_cost_override >= 0 else int(skill.get("mp_cost", 0))
	if u.mp < cost:
		return false
	if not is_physical(skill):
		if u.moved:
			return false
	else:
		if u.move_left < int(skill.get("move_cost", 0)):
			return false
	# 自爆: HP <= ⌊HPmax/2⌋ (u16 无符号) HPmax 1005, HP 503 不可用、502 可用; AI 与玩家共用本函数
	if is_self_destruct(skill) and u.hp > u.hp_max / ctx.params.self_destruct_hp_div:
		return false
	if is_summon(skill) and int(summon_flags.get(int(skill.get("rate10", 0)), 0)) != 0:
		return false
	return true


## 消耗: MP -= mp_cost; 绝技另扣 move_cost (先扣保留点)
static func consume(ctx, u, skill: Dictionary, mp_cost_override: int = -1) -> void:
	var cost: int = mp_cost_override if mp_cost_override >= 0 else int(skill.get("mp_cost", 0))
	u.mp -= cost
	if is_physical(skill):
		Movement.spend(u, int(skill.get("move_cost", 0)))


## 施放距离格
static func cast_cells(skill: Dictionary, from: Vector2i) -> Array:
	return Attack.range_cells(from, skill.get("range", {}))


## 效果范围: 以落点为中心、半径 area 的菱形 (area 0 = 单格) 中高
static func area_cells(skill: Dictionary, center: Vector2i) -> Array:
	var area: int = int(skill.get("range", {}).get("area", 0))
	var out := []
	for dy in range(-area, area + 1):
		for dx in range(-area, area + 1):
			if absi(dx) + absi(dy) <= area:
				out.append(center + Vector2i(dx, dy))
	return out


## 目标过滤: target 0 我方 (含友军 NPC), 1 敌方, 2 空格
static func valid_target(caster, t, skill: Dictionary) -> bool:
	if t == null or not t.alive or t.annihilation_exempt:
		return false
	match int(skill.get("target", 1)):
		0:
			return t.side == caster.side
		1:
			return t.side != caster.side
	return false


## 直线型 (range type 1): 选定一个方向, 该方向上射程内的格全部受影响 (中) 方向 = 落点相对施术者
static func line_cells(skill: Dictionary, from: Vector2i, center: Vector2i) -> Array:
	var dv := (center - from).sign()
	if center == from or (dv.x != 0 and dv.y != 0):
		return [center]
	var out := []
	for c in cast_cells(skill, from):
		if c != from and (c - from).sign() == dv:
			out.append(c)
	return out


## 区域选目标 [AI/玩家共用的纯函数, 900 例随机局面逐项一致]
##   菱形: 以落点为中心、半径 area 的格 (行优先); 直线: 先定方向 (落点 x>施术者 x → 东, x< → 西, 同列再看 y: y> → 南, 否则 (含落点 = 施术者格) → 北),
##   再按射程格表 (行优先) 取「与施术者同列/行且在该方向」的格, area>0 时每个这样的格再展开菱形 (同一单位可重复入表, 原版如此, 数据里直线技能 area=0);
##   单位入表条件: 在场、阵营符合 (target 0 同阵营, 1 异阵营)、**字段=0** (齐祀等 untargetable 不入目标表)
static func targets_in_area(board, caster, skill: Dictionary, center: Vector2i) -> Array:
	var out := []
	var rg: Dictionary = skill.get("range", {})
	var area: int = int(rg.get("area", 0))
	var cells: Array
	if int(rg.get("type", 0)) != 0:
		var from: Vector2i = caster.pos()
		var dir: int
		if center.x > from.x:
			dir = 3
		elif center.x < from.x:
			dir = 2
		else:
			dir = 1 if center.y > from.y else 0
		cells = []
		for c in cast_cells(skill, from):
			if not board.in_bounds(c):
				continue   # 原版射程格表已按地图边界裁剪
			var hit: bool
			match dir:
				0: hit = c.x == from.x and c.y < from.y
				1: hit = c.x == from.x and c.y > from.y
				2: hit = c.x < from.x and c.y == from.y
				_: hit = c.x > from.x and c.y == from.y
			if hit:
				if area > 0:
					cells.append_array(area_cells(skill, c))
				else:
					cells.append(c)
	else:
		cells = area_cells(skill, center)
	for c in cells:
		var t = board.unit_at(c)
		if valid_target(caster, t, skill):
			out.append(t)
	return out


## 咒术/诅咒命中 高; 绝技分支查 對技全禦
##   幻影 → 0; 全禦 → 0; 狂暴 → 100; clamp(rate6 + (施Luk - 目标Luk)/4)
static func spell_hit(ctx, c, t, skill: Dictionary) -> int:
	if t.has_status(U.ST_PHANTOM):
		return 0
	var guard_bit: int = U.ST_GUARD_SKILL if is_physical(skill) else U.ST_GUARD_SPELL
	if t.has_status(guard_bit):
		return 0
	if t.has_status(U.ST_BERSERK):
		return 100
	return clampi(int(skill.get("rate6", 0)) + (c.get_stat("luk") - t.get_stat("luk")) / ctx.params.hit_luk_div, 0, 100)


## 施放并结算 (不含消耗, 消耗用 consume)。
## opts: power (物品发动时的 字段), rate10 (字段), from_item (道具发动: 不给经验)
## 返回 {targets: [每目标记录], exp, summon (bool), caster_died}
static func resolve(ctx, caster, skill: Dictionary, targets: Array, opts: Dictionary = {}) -> Dictionary:
	var out := {"targets": [], "exp": 0, "summon": false, "caster_died": false}
	var sk := skill.duplicate(true)
	if opts.has("power"):
		sk["power"] = int(opts["power"])
	if opts.has("rate10"):
		sk["rate10"] = int(opts["rate10"])
	if is_summon(sk):
		# 召唤: 目标是空格, 由调用方激活预置隐藏单位并置标志变量 (Stats.make_summon)
		# 召唤物当回合可行动, lv/HPmax = 施术者, 标志变量 103 置 1
		out.summon = true
		return out
	var exp_entries := []
	var heal_entries := []
	var kind := "none"   # damage / heal / none —— 决定给不给经验
	var physical := is_physical(sk)
	var rt: int = int(sk.get("result_type", -1))
	if not physical and rt == -1 and ctx.params.fix_mo_tian:
		physical = true   # 魔改开关: 魔天降臨等走绝技分支
	for t in targets:
		var rec := {"target": t, "hit": true, "invalid": false, "damage": 0, "killed": false, "healed": 0,
			"guard": false, "status": 0, "mp_drained": 0, "amount": 0, "code": 0}
		var hp_before: int = t.hp
		var k: String = _resolve_physical(ctx, caster, sk, t, rec, out) if physical else _resolve_spell(ctx, caster, sk, t, rec, out)
		if k != "none":
			kind = k
		rec.code = result_code(sk, physical, rec)
		# 原版每个目标都有一项 e1/e2 (默认 -1): 落空/无效的目标没走到经验段, 在汇总里记 -1 (多目标时每个扣 1)
		# 伤害类 (咒术 rt0 / 物理): 咒术 = 命中; 物理 = 非 invalid (含 0 伤害、被格挡) [w2 矩阵 639 例]
		var reached: bool = (not rec.invalid) and (rec.hit or physical or rec.damage != 0)
		exp_entries.append({"target": t, "damage": rec.damage, "killed": rec.killed, "hp_before": hp_before, "reached": reached})
		if rec.has("heal_gain"):
			heal_entries.append({"target": t, "healed": rec.heal_gain})   # 满血目标也计入 (各贡献 1)
		out.targets.append(rec)
	if is_self_destruct(sk):
		caster.hp = 0
		caster.alive = false
		out.caster_died = true
	# 只有伤害技能与治疗给经验; 道具发动的技能不给
	if not opts.get("from_item", false):
		if kind == "damage":
			out.exp = Exp.skill_exp(ctx, caster, exp_entries)
		elif kind == "heal":
			out.exp = Exp.heal_skill_exp(ctx, caster, heal_entries)
	return out


## 咒术 (+0 == 0)
static func _resolve_spell(ctx, c, sk: Dictionary, t, rec: Dictionary, out: Dictionary) -> String:
	var rt: int = int(sk.get("result_type", -1))
	var eff: int = int(sk.get("result_effect", -1))
	match rt:
		RT_DAMAGE:
			# 伤害; 冰系命中后判冰結 (先受伤解旧冰, 再挂新冰)
			rec.hit = ctx.rng.mod(100) < spell_hit(ctx, c, t, sk)
			if rec.hit:
				var d: int = Damage.spell_damage(ctx, c, t, sk)
				# 负伤害 (属性吸收) 的结果值被钳到缺口 结果 val = -min(吸收量, HPmax-HP)
				if d < 0:
					d = maxi(d, -(t.hp_max - t.hp))
				rec.damage = d
				rec.killed = Damage.apply_damage(t, d)
				if int(sk.get("attribute", -1)) == ATTR_ICE:
					# 冰結判定的随机数照取, 即使目标已被这一击打死 (原版结算先于扣血, 对照: 玄凛冰煞打死目标仍多取 1 次)
					var fr: int = clampi(int(sk.get("rate10", 0)) - ctx.params.freeze_spirit_mult * int(t.spirit[4]), 0, 100)
					if ctx.rng.mod(100) < fr:   # rate10 - 2×目标魂, R=K=1
						rec["fx_status"] = U.ST_FREEZE   # 结果码按判定算 (打死了也是冰結码, 外观上退成命中, 见 BattleActions.result_plan)
						if t.alive and Status.apply(t, U.ST_FREEZE, ctx.params.freeze_r, ctx.params.freeze_k):
							rec.status = U.ST_FREEZE
			return "damage"
		RT_HEAL:
			var h: int = Damage.heal_amount(ctx, c, t, sk)
			var hp0: int = t.hp
			Damage.apply_heal(t, h)
			rec.healed = h
			rec.amount = h
			rec["heal_gain"] = t.hp - hp0   # 实际回复量 (按缺血封顶)
			return "heal"
		RT_PURIFY:
			Status.remove(t, Status.PURIFY_MASK)
		RT_BLESS:
			_bless(ctx, c, sk, t, eff, rec)
		RT_CURSE:
			_curse(ctx, c, sk, t, Status.CURSE_BITS.get(eff, 0), rec)
		RT_SPECIAL:
			match eff:
				12:  # 無上滅法 驱散, 不判命中
					Status.remove(t, Status.DISPEL_MASK)
				13:  # 返召之咒: 只置 字段=1 (可行动), 不重置移动点
					# 已行动单位移动点已清 0 → Movement.can_start_action 为 false, 实际不能再行动
					t.extra_action = true
					t.acted = false
					if ctx.params.recall_resets_move:   # 魔改: 完整再行动
						t.move_left = t.move_cap
						t.moved = false
				14:  # 召唤: 在 resolve 开头处理
					out.summon = true
				15:  # 幽冥返召: 原版无效果, 只扣 MP 播动画
					pass
				16:  # 遁地神行: 原版无效果; 魔改开关置幻影
					if ctx.params.burrow_sets_phantom:
						Status.apply(t, U.ST_PHANTOM, ctx.params.burrow_r, ctx.params.burrow_k)
						rec.status = U.ST_PHANTOM
				7:   # 冥幻之陣: rt5 跳转表只覆盖 eff12~16 → 无效果, 扣 500 MP
					pass
		_:
			# rt == -1: 魔天降臨 —— 吸术逻辑只在绝技分支, 咒术走到这里无效果 (原版 bug)
			# 扣 25 MP、播全屏动画、行动结束; 目标不变; 不得经验
			pass
	return "none"


## 祝福: eff0~4 R = P×(100+S)/100, K = rate10 - 2×(目标Int/(5+rand%6)); eff5~7 R = power, K = rate10
static func _bless(ctx, c, sk: Dictionary, t, eff: int, rec: Dictionary) -> void:
	if eff < 0 or eff >= Status.BLESS_BITS.size():
		return
	var bit: int = Status.BLESS_BITS[eff]
	var r: int
	var k: int
	if eff <= 4:
		r = Damage.spell_power(ctx, c, sk) * maxi(0, 100 + Damage.spirit_mod(t, sk)) / 100
		k = Status.bless_k(ctx, t, int(sk.get("rate10", 0)))
	else:
		r = int(sk.get("power", 0))
		k = int(sk.get("rate10", 0))
	if Status.apply(t, bit, r, k, false):   # 祝福无 R<K 判定
		rec.status = bit


## 诅咒: 先判命中; R = 咒术伤害公式 (含抗性与 MAG_OPP[属性]); K = rate10 + 2×(目标Int/(5+rand%6))
static func _curse(ctx, c, sk: Dictionary, t, bit: int, rec: Dictionary) -> void:
	if bit == 0:
		return
	rec.hit = ctx.rng.mod(100) < spell_hit(ctx, c, t, sk)
	if not rec.hit:
		return
	var r: int = Damage.spell_damage(ctx, c, t, sk)
	var k: int = Status.curse_k(ctx, t, int(sk.get("rate10", 0)))
	if r >= k:
		rec["fx_status"] = bit   # 判定通过就是该状态的结果码, 目标已被这一击打死则状态不落 (外观退成命中)
		if t.alive:
			Status.apply(t, bit, r, k)
			rec.status = bit


## 绝技 (+0 ≠ 0),
static func _resolve_physical(ctx, c, sk: Dictionary, t, rec: Dictionary, out: Dictionary) -> String:
	var ot: int = int(sk.get("other_type", -1))
	var oe: int = int(sk.get("other_effect", -1))
	var hostile: bool = t.side != c.side
	# 不判命中; 目标有 幻影 或 對技全禦 → 无效
	# 对照原版: 伤害类 (ot0 / ot1 / ot2 oe12 幻月神劍) 不分敌我一律先判无效 (友方目标带全禦也无效);
	# 地縛 (ot2 oe8) 不做这个预判, 走诅咒流程 (命中率 0 照取 1 次命中随机数); 其余 ot2 效果实测不可见, 维持仅敌方
	var pre_check: bool = ot in [0, 1] or (ot == 2 and oe == 12) or (hostile and not (ot == 2 and oe == 8))
	if pre_check and (t.has_status(U.ST_PHANTOM) or t.has_status(U.ST_GUARD_SKILL)):
		rec.invalid = true
		rec.hit = false
		return "damage" if (ot in [0, 1] or (ot == 2 and oe in [9, 12])) else "none"
	match ot:
		0:  # ot0: 物理 + Str 浮动 × 五魂, 可格挡 d/2 (无保底)
			var d: int = Damage.skill_ot0_damage(ctx, c, t, sk)
			if ctx.rng.mod(100) < Attack.guard_rate(ctx, c, t):
				d = d / 2
				rec.guard = true
			rec.damage = d
			rec.killed = Damage.apply_damage(t, d)
			return "damage"
		1:  # ot1: 普攻伤害 (crit=0), 格挡 d/2, 再乘倍率; oe3~5 未格挡时附加状态; oe6 吸术
			var d: int = Damage.phys_damage(ctx, c, t, false)
			if ctx.rng.mod(100) < Attack.guard_rate(ctx, c, t):
				d = d / 2
				rec.guard = true
			if oe >= 0 and oe < ctx.params.skill_ot1_mult.size():
				d *= int(ctx.params.skill_ot1_mult[oe])
			rec.damage = d
			rec.killed = Damage.apply_damage(t, d)
			# 附加状态 / 吸术的随机数照取, 即使目标已被这一击打死 (对照原版: 结算先于扣血); 只有生效要求目标活着
			if oe in [3, 4, 5] and not rec.guard:
				_curse(ctx, c, sk, t, Status.OT1_BITS[oe], rec)
			elif oe == 6 and not rec.guard:   # 吸术同附加状态: 被格挡则不判 [对照: 格挡时少取 1 次随机数、不吸]
				if ctx.rng.mod(100) < spell_hit(ctx, c, t, sk):
					rec["drained"] = true
					if t.alive:
						_drain_mp(c, t, ctx.params.mp_absorb_div_ot1, rec)
			return "damage"
		2:
			match oe:
				7:  # 魔天降臨的吸术 (只有绝技分支能走到; 原版魔天降臨 +0=0 走不到)
					_drain_mp(c, t, ctx.params.mp_absorb_div_ot2, rec)
					rec["drained"] = true
				8:  # 鬼縛之陣: 地缚 (诅咒流程)
					_curse(ctx, c, sk, t, U.ST_BIND, rec)
				9:  # 自爆 高; 经验是否给: 中
					var d: int = Damage.self_destruct_damage(ctx, c, t)
					rec.damage = d
					rec.killed = Damage.apply_damage(t, d)
					return "damage"
				10, 11:  # 日輪神劍 / 七燁明華: 全禦 R=power K=rate10 (0/0 也可施加)
					var bit: int = U.ST_GUARD_SKILL if oe == 10 else U.ST_GUARD_SPELL
					if Status.apply(t, bit, int(sk.get("power", 0)), int(sk.get("rate10", 0)), false):
						rec.status = bit
				12:  # 幻月神劍: 普攻伤害 (不判格挡) + 驱散
					var d: int = Damage.phys_damage(ctx, c, t, false)
					rec.damage = d
					rec.killed = Damage.apply_damage(t, d)
					if t.alive:
						Status.remove(t, Status.DISPEL_MASK)
					return "damage"
				13:  # 天護靈燁: HP 全复 + 解麻/地缚/封/毒, 不解冰結
					rec.amount = t.hp_max - t.hp   # 地图上弹的蓝数字 = 补满的量 (满血 0, 照样弹, 码 21)
					t.hp = t.hp_max
					Status.remove(t, Status.HOLY_CLEANSE_MASK)
					# 全复是否给经验未核对 (中), 暂不给: rec.healed 保持 0, 演出只看 rec.amount
				14:  # 不動之界 / 神臨烈陣: 攻防技速 0xf, R=power K=rate10
					for bit in [U.ST_ATK_UP, U.ST_DEF_UP, U.ST_TECH_UP, U.ST_HASTE]:
						Status.apply(t, bit, int(sk.get("power", 0)), int(sk.get("rate10", 0)), false)
					rec.status = 0xf
				15:  # 天瑞仙舞: 回复术力 power, 移动点不变 MP 1000→1050, 字段 40→40
					var v: int = Bits.clamp_mp_gain(int(sk.get("power", 0)), t.mp, t.mp_max)
					t.mp = Bits.s16(t.mp + v)
					rec.amount = v   # 蓝数字 = 补的术力 (满蓝 0, 照样弹)
	return "none"


## 原版结果码 (技能解算 写进结果记录 字段; 地图结果动画 / 数字都按它分派, 实测 2026-10-18):
##   0 无 (未命中 / 无效 / 抵抗: 既没有动画也没有数字)  1 格挡  2 命中  3~7 攻击/防御/咒术/行动力提升、狂暴  8 麻痹  9 中毒  10 封咒  11 吸术
##   12 地缚  13 冰結  14 治疗  15 净化  16 咒术免疫  17 物理免疫  18 幻影  19 驱散  20 返召  21 全复  22 能力全提升  23 召唤  24 幽冥返召  25 遁地  26 术力恢复
## 在每个目标结算完 (状态已施加 / 扣血已做) 后算; rec 要有 invalid / hit / guard / status / mp 吸取标志
static func result_code(sk: Dictionary, physical: bool, rec: Dictionary) -> int:
	if rec.invalid:
		return 0
	var st: int = int(rec.get("fx_status", rec.status))
	if not physical:
		match int(sk.get("result_type", -1)):
			RT_DAMAGE:
				if not rec.hit:
					return 0
				return 13 if (st & U.ST_FREEZE) != 0 else 2
			RT_HEAL:
				return 14
			RT_PURIFY:
				return 15
			RT_BLESS:
				return _status_code(st)
			RT_CURSE:
				return _status_code(st) if st != 0 else 0
			RT_SPECIAL:
				return {12: 19, 13: 20, 14: 23, 15: 24, 16: 25}.get(int(sk.get("result_effect", -1)), 0)
		return 0
	var oe: int = int(sk.get("other_effect", -1))
	match int(sk.get("other_type", -1)):
		0:
			return 1 if rec.guard else 2
		1:
			if rec.guard:
				return 1
			if st != 0:
				return _status_code(st)
			return 11 if rec.get("drained", false) else 2
		2:
			match oe:
				7:
					return 11
				8:
					return 12 if st != 0 else 0
				9:
					return 2
				10, 11:
					return _status_code(st)
				12:
					return 19
				13:
					return 21
				14:
					return 22
				15:
					return 26
	return 0


## 状态位 -> 结果码
static func _status_code(st: int) -> int:
	for p in [[U.ST_ATK_UP, 3], [U.ST_DEF_UP, 4], [U.ST_TECH_UP, 5], [U.ST_HASTE, 6], [U.ST_BERSERK, 7], [U.ST_PARALYZE, 8], [U.ST_POISON, 9],
			[U.ST_SEAL, 10], [U.ST_BIND, 12], [U.ST_FREEZE, 13], [U.ST_GUARD_SPELL, 16], [U.ST_GUARD_SKILL, 17], [U.ST_PHANTOM, 18]]:
		if (st & int(p[0])) != 0:
			return int(p[1])
	return 0


## 这个技能的结果记录带不带「伤害数值」(原版结果记录 字段 == 1): 带才弹红数字 (咒术伤害、绝技的伤害类、自爆、幻月神劍); 纯状态 / 治疗 / 吸术 (自身类) 不弹
static func shows_damage(sk: Dictionary, physical: bool) -> bool:
	if not physical:
		return int(sk.get("result_type", -1)) == RT_DAMAGE
	var ot: int = int(sk.get("other_type", -1))
	return ot in [0, 1] or (ot == 2 and int(sk.get("other_effect", -1)) in [9, 12])


## 物理绝技近景里守方弹不弹伤害数字 (实测): 带伤害数值标志 (shows_damage) 且结果码不是 11 (吸术成功) 才弹 ——
## 回风枪 (码 2) / 化血毒沫中毒成功 (码 9) / 吸术没吸到 (码 2) 都弹, 摄魂鬼触吸术成功 (码 11) 一个数字都没有 (伤害照扣)
static func closeup_digits(sk: Dictionary, rec: Dictionary) -> bool:
	return shows_damage(sk, true) and int(rec.get("code", 0)) != 11


static func _drain_mp(c, t, div: int, rec: Dictionary) -> void:
	var v: int = mini(t.mp, t.mp_max / div)
	v = maxi(0, v)
	t.mp -= v
	c.mp = mini(c.mp_max, c.mp + v)
	rec.mp_drained = v

# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 状态异常与增益。每种状态一对「剩余值 R / 扣减值 K」。

const U = preload("res://engine/rules/unit_state.gd")

## 驱散 (無上滅法 / 幻月神劍): 清攻、防、技、速、狂暴 0x4f, 不清全禦、幻影
const DISPEL_MASK := 0x4f
## 靈淨大法: 掩码 ~0xef7f = 毒 + 麻
const PURIFY_MASK := 0x1080
## 天護靈燁: 掩码 ~0xe97f = 麻 + 地缚 + 封 + 毒, 不解冰結
const HOLY_CLEANSE_MASK := 0x1680
## 祝福 eff0~7 -> 状态位
const BLESS_BITS := [U.ST_ATK_UP, U.ST_DEF_UP, U.ST_TECH_UP, U.ST_HASTE, U.ST_BERSERK,
	U.ST_GUARD_SKILL, U.ST_GUARD_SPELL, U.ST_PHANTOM]
## 诅咒 eff8~11 -> 毒 / 麻 / 封 / 地缚
const CURSE_BITS := {8: U.ST_POISON, 9: U.ST_PARALYZE, 10: U.ST_SEAL, 11: U.ST_BIND}
## 绝技 ot1 oe3/4/5 -> 麻 / 毒 / 封
const OT1_BITS := {3: U.ST_PARALYZE, 4: U.ST_POISON, 5: U.ST_SEAL}
## 武器附加 type 1/2/3 -> 毒 / 麻 / 封
const WEAPON_ADD_BITS := {1: U.ST_POISON, 2: U.ST_PARALYZE, 3: U.ST_SEAL}


## 施加: 已有同种 = 覆盖刷新, 不叠加不拒绝 只置位、写 R/K, 不比较。
## R < K 的「抵抗」判定只在诅咒类的结算阶段 (等) 做, 对应 check = true (默认, 诅咒/冰結/武器附加);
## 祝福 (rt3)、全禦、不動之界等 (结算阶段 / 0x41a0xx 无比较) 传 check = false:
## R < K 照样置位, 下一次本阵营阶段开始 R-K <= 0 即解除 (实机对照, 对照原版)。返回是否施加。
static func apply(u, bit: int, r: int, k: int, check: bool = true) -> bool:
	if check and r < k:
		return false
	u.status |= bit
	u.status_r[bit] = r
	u.status_k[bit] = k
	return true


static func remove(u, mask: int) -> Array:
	var removed := []
	for b in U.STATUS_NAMES:
		if (u.status & mask & b) != 0:
			removed.append(b)
			u.status &= ~b
			u.status_r.erase(b)
			u.status_k.erase(b)
	return removed


## / §4 本阵营阶段开始时对单位结算: 先中毒扣 HPmax/5 (可致死, 到期那次也扣), 再所有状态 R -= K, R<=0 移除
## [中毒, 递减, 移除]
## 返回 {poison_damage, died, expired: [位...]}
static func phase_tick(ctx, u) -> Dictionary:
	var res := {"poison_damage": 0, "died": false, "expired": []}
	if not u.alive:
		return res
	if u.has_status(U.ST_POISON):
		var dmg: int = u.hp_max / ctx.params.poison_div
		if not ctx.params.poison_lethal:
			dmg = mini(dmg, u.hp - 1)
		dmg = maxi(dmg, 0)
		u.hp = maxi(0, u.hp - dmg)
		res.poison_damage = dmg
		if u.hp <= 0:
			u.alive = false
			res.died = true
	for b in U.STATUS_NAMES:
		if (u.status & b) == 0:
			continue
		var r: int = int(u.status_r.get(b, 0)) - int(u.status_k.get(b, 0))
		u.status_r[b] = r
		if r <= 0:
			remove(u, b)
			res.expired.append(b)
	return res


## 某阵营阶段开始时需要结算的单位 (按 MAN 下标顺序; 行动顺序同此)。
## phase: "ally" (友军 NPC 阶段) / "player" (我方) / "enemy"。
## 友军 NPC 在 ally 和 player 各结算一次 (一轮两次, 原版 bug 照做) NPC 一轮扣两次 HPmax/5
static func units_to_tick(ctx, units: Array, phase: String) -> Array:
	var out := []
	for u in units:
		if not u.alive:
			continue
		match phase:
			"ally":
				if u.side == 0 and u.npc_ally:
					out.append(u)
			"player":
				if u.side == 0 and (not u.npc_ally or ctx.params.ally_npc_double_tick):
					out.append(u)
			"enemy":
				if u.side == 1:
					out.append(u)
	out.sort_custom(func(a, b): return a.uid < b.uid)
	return out


## 受击即解除冰結: 条件是结果码 1/2/8~12/0x13 置的「被打」标志, 不看伤害是否 >0
## 伤害 0 的咒术命中后冰結位立即清除; 模式 1。未命中不解。
static func on_damaged(u, _dmg: int = 0) -> void:
	if u.has_status(U.ST_FREEZE):
		remove(u, U.ST_FREEZE)
		u.released |= U.ST_FREEZE   # 演出 (动画 + 「冰結的状态解除了.」框) 由战场层读这一位


## 可操作 / 能行动: 无麻痺、无冰結
static func can_act(u) -> bool:
	return u.alive and not u.has_status(U.ST_PARALYZE) and not u.has_status(U.ST_FREEZE)


## 祝福扣减值 K = rate10 - 2 × (Int / (5 + rand()%6)); AI 估算 2 × (Int/7)
## 高; Int 取目标 目标 Int 80 → K = 100-2×(80/5) = 68 等
static func bless_k(ctx, target, rate10: int, ai_estimate: bool = false) -> int:
	var iv: int = target.get_stat("int")
	if ai_estimate:
		return rate10 - 2 * (iv / ctx.params.ai_status_int_div)
	var div: int = ctx.params.bless_int_div_min + ctx.rng.mod(ctx.params.bless_int_div_span)
	return rate10 - 2 * (iv / div)


## 诅咒扣减值 K = rate10 + 2 × (Int / (5 + rand()%6)); AI 估算 2 × (Int/7)
## [与 同构只是加号] 高; Int 取目标 (同)
static func curse_k(ctx, target, rate10: int, ai_estimate: bool = false) -> int:
	var iv: int = target.get_stat("int")
	if ai_estimate:
		return rate10 + 2 * (iv / ctx.params.ai_status_int_div)
	var div: int = ctx.params.bless_int_div_min + ctx.rng.mod(ctx.params.bless_int_div_span)
	return rate10 + 2 * (iv / div)


## 实际持续 = ⌈R/K⌉ 次结算; K<=0 时返回 1 (R=K=0 只撑到本阵营下一阶段开始)
static func duration_ticks(r: int, k: int) -> int:
	if k <= 0:
		return 1
	return (r + k - 1) / k

# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 战斗中使用道具 (规格 §3,)。物品记录 = items.json, 使用字段在 rec.use。
## 按 use.effect 分派 (items.json 的 use_type 名称与 表的编号不一致, effect 才是决定因素):
##   0 回 HP / 1 回 MP / 2 解毒 / 3 解麻 / 4 解封 / 5~11 上限提升 / use_type 3 发动技能 (skill_id)

const U = preload("res://engine/rules/unit_state.gd")
const Bits = preload("res://engine/rules/bits.gd")
const Damage = preload("res://engine/rules/damage.gd")
const Status = preload("res://engine/rules/status.gd")
const Attack = preload("res://engine/rules/attack.gd")
const Growth = preload("res://engine/rules/growth.gd")
const Movement = preload("res://engine/rules/movement.gd")
const Inventory = preload("res://engine/rules/inventory.gd")

const USE_SKILL := 3
const CURE_BITS := {2: U.ST_POISON, 3: U.ST_PARALYZE, 4: U.ST_SEAL}
## 上限提升 effect 5..11 -> 字段
const LIMIT_KEYS := {5: "hp_max", 6: "mp_max", 7: "str", 8: "int", 9: "avg", 10: "vit", 11: "luk"}


## 主角 10 格的统一数据规则 (囊內乾坤 / 商店人物栏 / 諸物煉化 / 体态观览 / 战斗写回共用):
## 原版装备 (字段/字段/字段) 指向格子 (字段) 里的物品, 所以已装备的物品一定在格子里。
## 存档的 items 可能落后于 gear (战斗中剧情 0x40/0x49 换装、0x53 收走; 旧存档只有 gear),
## 这里以 gear 为准补齐: 去掉 removed 里的物品, 缺的装备按 武器/护具/饰物 顺序追加。返回新数组, 不改参数。
const GEAR_KEYS := ["weapon", "armor", "accessory"]

static func unit_slots(items: Array, gear: Dictionary, removed: Array = []) -> Array:
	var out: Array = []
	var drop: Array = removed.map(func(x): return int(x))
	for x in items:
		if x == null or int(x) < 0:
			continue
		var id := int(x)
		if id in drop:
			drop.erase(id)
			continue
		out.append(id)
	for k in GEAR_KEYS:
		var v = gear.get(k)
		if v != null and int(v) >= 0 and not int(v) in out:
			out.append(int(v))
	return out


## 战斗中「装备」「丢弃」之后: 原版不消耗行动, 也不消耗移动点, 可连续多次,
## 之后仍可移动、出手 (字段 仍为 1, 字段 不变)。params.equip_costs_action = true (魔改) 时结束行动。
## 返回: 行动是否因此结束
static func after_equip_or_discard(ctx, u) -> bool:
	if not ctx.params.equip_costs_action:
		return false
	Movement.end_action(u)
	return true


## 战斗中「交給」之后: give_costs_action (默认真) 时结束行动。返回: 行动是否因此结束
static func after_give(ctx, u) -> bool:
	if not ctx.params.give_costs_action:
		return false
	Movement.end_action(u)
	return true


static func use_rec(ctx, item_id: int) -> Dictionary:
	return ctx.item(item_id).get("use", {})


## 战斗中「使用」条件:
##   物品有使用目标 (target ≠ -1) 且 MP 够, 且 (是已装备的那件 或 道具类型 0)
##   使用道具可以在移动后 敌人移动到相邻格后对友军用药
static func can_use(ctx, u, item_id: int) -> bool:
	if not u.items.has(item_id):
		return false
	var rec: Dictionary = ctx.item(item_id)
	var use: Dictionary = rec.get("use", {})
	if int(use.get("target", -1)) == -1:
		return false
	if u.mp < int(use.get("mp_cost", 0)):
		return false
	if int(rec.get("type", 0)) == 0:
		return true
	return item_id == u.weapon or item_id == u.armor or item_id == u.accessory


## 使用距离
static func use_range(ctx, item_id: int) -> Dictionary:
	var use: Dictionary = use_rec(ctx, item_id)
	return {"type": int(use.get("range_type", 0)), "area": int(use.get("range_area", 0)),
		"min": int(use.get("range_min", 0)), "max": int(use.get("range_max", 0))}


static func use_cells(ctx, item_id: int, from: Vector2i) -> Array:
	return Attack.range_cells(from, use_range(ctx, item_id))


## target 0 我方 (含友军 NPC), 1 敌方
static func valid_target(ctx, user, t, item_id: int) -> bool:
	if t == null or not t.alive or t.annihilation_exempt:   # 原版选目标 对技能和道具一视同仁地排除 字段≠0 的单位 (齐祀等), 同 Skills.valid_target
		return false
	match int(use_rec(ctx, item_id).get("target", -1)):
		0:
			return t.side == user.side
		1:
			return t.side != user.side
	return false


static func targets_in_area(ctx, board, user, item_id: int, center: Vector2i) -> Array:
	var out := []
	var area: int = int(use_rec(ctx, item_id).get("range_area", 0))
	for dy in range(-area, area + 1):
		for dx in range(-area, area + 1):
			if absi(dx) + absi(dy) > area:
				continue
			var t = board.unit_at(center + Vector2i(dx, dy))
			if valid_target(ctx, user, t, item_id):
				out.append(t)
	return out


## 对一个目标结算道具效果 (不含消耗与技能发动)。返回 {healed, mp, cured, raised}
## 高; 道具不给经验
static func apply_effect(ctx, t, item_id: int) -> Dictionary:
	var use: Dictionary = use_rec(ctx, item_id)
	var eff: int = int(use.get("effect", -1))
	var base: int = int(use.get("base_power", 0))
	var out := {"healed": 0, "mp": 0, "cured": 0, "raised": 0}
	match eff:
		0:
			var h: int = Damage.item_heal_hp(ctx, t, base)
			t.hp = Bits.u16(t.hp + h)
			out.healed = h
		1:
			var m: int = Damage.item_heal_mp(ctx, t, base)
			t.mp = Bits.s16(t.mp + m)
			out.mp = m
		2, 3, 4:
			var bit: int = CURE_BITS[eff]
			if t.has_status(bit):
				Status.remove(t, bit)
				out.cured = bit
		5, 6:
			# HPmax/MPmax 16 位加, 无上限
			var key: String = LIMIT_KEYS[eff]
			t.set(key, Growth.add_u16(ctx, int(t.get(key)), base))
			out.raised = base
		7, 8, 9, 10, 11:
			var k: String = LIMIT_KEYS[eff]
			# 属性按 s16 读; 超 500 则 val = 500 - 当前 (当前 > 500 时为负, 拉回 500) [实机对照]
			var before: int = Bits.s16(t.get_stat(k))
			var val: int = ctx.params.stat_cap - before if before + base > ctx.params.stat_cap else base
			t.set_stat(k, Bits.s16(before + val))
			out.raised = val
	return out


## 从使用者物品栏扣掉一件 (消耗品) 并扣 MP 对友军用药, 药从使用者物品栏消失
static func consume(ctx, user, item_id: int) -> void:
	var use: Dictionary = use_rec(ctx, item_id)
	user.mp -= int(use.get("mp_cost", 0))
	if bool(use.get("consumable", false)):
		Inventory.remove_one(user, item_id)


## 召唤石「可使用」检查读的标志变量: 取【技能记录】自己的 rate10 (剑魂石/兽魂石三件都是 103, 与式鬼共用), 不是物品的 字段 (104~106)
## 返回变量号, 不是召唤类返回 -1
static func summon_check_var(ctx, item_id: int) -> int:
	var use: Dictionary = use_rec(ctx, item_id)
	if int(use.get("use_type", -1)) != USE_SKILL or use.get("skill_id") == null:
		return -1
	var sk: Dictionary = ctx.skill(int(use["skill_id"]))
	if int(sk.get("result_type", -1)) != 5 or int(sk.get("result_effect", -1)) != 14:
		return -1
	return int(sk.get("rate10", -1))


## 道具发动技能时的技能记录 (power / rate10 换成物品 字段 / 字段, MP 用物品的) —— 由 Skills.resolve(opts) 结算
static func skill_of(ctx, item_id: int) -> Dictionary:
	var use: Dictionary = use_rec(ctx, item_id)
	if int(use.get("use_type", -1)) != USE_SKILL or use.get("skill_id") == null:
		return {}
	var sk: Dictionary = ctx.skill(int(use["skill_id"])).duplicate(true)
	if sk.is_empty():
		return sk
	sk["power"] = int(use.get("base_power", sk.get("power", 0)))
	sk["rate10"] = int(use.get("time_cost", sk.get("rate10", 0)))   # 字段 (召唤石 = 标志变量 104~106)
	sk["mp_cost"] = int(use.get("mp_cost", 0))
	sk["range"] = {"type": int(use.get("range_type", 0)), "area": int(use.get("range_area", 0)), "min": int(use.get("range_min", 0)), "max": int(use.get("range_max", 0))}
	return sk

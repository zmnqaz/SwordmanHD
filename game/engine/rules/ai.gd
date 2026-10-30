# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 敌方 / 友军 AI: 统一打分决策 + 各类型的移动逻辑。
## 只产生「计划」{move_to, action}; execute() 用规则模块执行, 不涉及演出。

const U = preload("res://engine/rules/unit_state.gd")
const Stats = preload("res://engine/rules/stats.gd")
const Damage = preload("res://engine/rules/damage.gd")
const Status = preload("res://engine/rules/status.gd")
const Attack = preload("res://engine/rules/attack.gd")
const Movement = preload("res://engine/rules/movement.gd")
const Skills = preload("res://engine/rules/skills.gd")
const Board = preload("res://engine/rules/board.gd")
const Items = preload("res://engine/rules/items.gd")
static var trace_cands := false   # 对照: 打印每个候选与估价前后的 rng (战场层按 --ai-cands 注入; 规则层不读命令行)


## 统一决策
##   候选格 = 所有可停留格 (含原地, 按搜索顺序); 地缚或本阶段已移动 → 只有原地
##   每格依次试 普攻 → 道具 → 技能, (主分, 副分) 严格大于才替换 (同分保留先找到的)
##   主分 < 100 → 不行动 (返回 {})
##   普攻副分里的反击射程按起点 (决策前位置) 判定, 见 _score_attacks (实测)
##   only_here: 只从当前格出手 (类型 3/4 的「先移动再出手」)
static func decide(ctx, board, u, only_here: bool = false) -> Dictionary:
	var start: Vector2i = u.pos()
	var cells := []
	var costs := {}
	if only_here or u.has_status(U.ST_BIND) or u.moved:
		cells = [start]
		costs[start] = 0
	else:
		var s := Movement.search(ctx, board, u)
		for c in s.stop:
			cells.append(c)
			costs[c] = s.cost[c]
		cells.sort_custom(_row_major)   # 原版候选表 = 的输出, 按行优先
	var best := {}
	var foes_sorted: Array = _sorted_hostiles(board, u)
	for cell in cells:
		u.set_pos(cell)
		var moved_here: bool = cell != start
		var r0: int = ctx.rng.get_state()
		for cand in _score_attacks(ctx, board, u, start, foes_sorted):
			best = _pick(best, cand, cell)
		if trace_cands:
			print("  估价 格", cell, " 普攻后 rng ", r0, "->", ctx.rng.get_state())
		# 道具: 可移动后使用, 从使用者物品栏扣
		if ctx.params.ai_use_items:
			for cand in _score_items(ctx, board, u):
				best = _pick(best, cand, cell)
		var r1: int = ctx.rng.get_state()
		for cand in _score_skills(ctx, board, u, moved_here, int(costs[cell])):
			best = _pick(best, cand, cell)
		if trace_cands:
			print("  估价 格", cell, " 技能后 rng ", r1, "->", ctx.rng.get_state())
	u.set_pos(start)
	if best.is_empty() or int(best.main) < ctx.params.ai_score_threshold:
		return {}
	return best


static func _row_major(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _pick(best: Dictionary, cand: Dictionary, cell: Vector2i) -> Dictionary:
	cand["cell"] = cell
	if trace_cands:
		print("  候选 ", cell, " ", cand.kind, " 主", cand.main, " 副", cand.sub, " ", cand.get("item", cand.get("skill", "")))
	if best.is_empty():
		return cand
	if cand.main > best.main or (cand.main == best.main and cand.sub > best.sub):
		return cand
	return best


## 普攻: 主分 100, 能击杀 +50; 副分 = 预计伤害 - 预计反击伤害。
##   「预计」不是固定估算而是【真的掷一遍】: 对每个 (候选格, 目标) 调用和实战同一个判定函数 (命中 / 会心 / 连击 / 格挡 / 伤害运气项都取随机数),
##   再取 副分 = 结果.伤害 - 结果.反击伤害, 击杀才 +50。所以同分格 / 目标的取舍随随机数波动 (固定随机数种子时结果可复现)。
##   反击射程按【决策前起点】判定, 不随候选格变化: 即对「移动后落在敌人枪口下」估价不足, 这是有意保留的原版行为。
## 敌对单位按 (y, x) 行优先排序; 决策里候选格逐格估价时, 敌对单位位置不变, 只排一次
static func _sorted_hostiles(board, u) -> Array:
	var tl: Array = board.hostiles_of(u)
	tl.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return tl


static func _score_attacks(ctx, board, u, start: Vector2i, sorted_foes = null) -> Array:
	var out := []
	var rg: Dictionary = Stats.weapon_range(ctx, u)
	# 目标顺序 = 射程格掩码的行优先顺序 (y 小优先, 再 x 小): 对 生成的射程格逐格取单位, 不是按单位表顺序;
	# 每个目标各掷一轮骰, 顺序不同则骰子落到不同目标上 [对照 第 1 关第 2 阶段 同种子同随机数消耗却打了不同的我方]
	var tl: Array = sorted_foes if sorted_foes != null else _sorted_hostiles(board, u)
	for t in tl:
		if not Attack.in_range(u.pos(), t.pos(), rg):
			continue
		var r1: Dictionary = Attack.strike(ctx, u, t, false, true)
		var dmg: int = 0 if r1.result == Attack.Result.MISS else int(r1.damage)
		var kill: bool = dmg >= t.hp
		var counter := 0
		if not kill and Attack.can_counter_at(ctx, t, start):
			var r2: Dictionary = Attack.strike(ctx, t, u, true, true)
			counter = 0 if r2.result == Attack.Result.MISS else int(r2.damage)
		var main: int = ctx.params.ai_attack_base + (ctx.params.ai_kill_bonus if kill else 0)
		out.append({"kind": "attack", "target": t, "main": main, "sub": dmg - counter})
	return out


## 技能打分的落点候选: 菱形射程 (type 0) 取射程格表的每一格;
## 直线射程 (type != 0, 刚烈破/分天斩/双环映月) 的落点只是本格的四邻 (北、东、南、西, 按这个顺序), 起方向选择器的作用,
## 不是射程内每一格。复刻原先把整条直线都当落点, 每个方向重复估价 3 次, 随机数多取 (实测, 见 §8)
static func _skill_centers(sk: Dictionary, from: Vector2i) -> Array:
	if int(sk.get("range", {}).get("type", 0)) == 0:
		return Skills.cast_cells(sk, from)
	return [from + Vector2i(0, -1), from + Vector2i(1, 0), from + Vector2i(0, 1), from + Vector2i(-1, 0)]


## 技能打分 (权重)
static func _score_skills(ctx, board, u, moved_here: bool, move_spent: int) -> Array:
	var out := []
	for sid in u.skills:
		var sk: Dictionary = ctx.skill(int(sid))
		if sk.is_empty():
			continue
		# 移动到该格之后的可用性: 咒术不能移动后用; 绝技看剩余移动点
		var saved_moved: bool = u.moved
		var saved_left: int = u.move_left
		u.moved = u.moved or moved_here
		u.move_left = u.move_left - move_spent
		var usable: bool = Skills.can_use(ctx, u, sk)
		u.moved = saved_moved
		u.move_left = saved_left
		if not usable:
			continue
		for center in _skill_centers(sk, u.pos()):
			if not board.in_bounds(center):
				continue
			var targets: Array = Skills.targets_in_area(board, u, sk, center)
			if targets.is_empty():
				continue
			var sc := _score_skill_targets(ctx, board, u, sk, targets)
			if sc.is_empty():
				continue
			sc["kind"] = "skill"
			sc["skill"] = int(sid)
			sc["center"] = center
			out.append(sc)
	return out


## 技能/物品效果打分 [权重; 对照原版逐条核对 2026-10-05]
##   对每个目标条目依次处理 (条目 = 范围内目标, 面积格行优先): 伤害类的主分是【赋值】不是累加,
##   所以只看最后一个条目 (它被击杀才 +50), 副分 (伤害) 才是各条目累加;
##   增益/诅咒/治疗的主分按条目累加。AI 不会考虑的效果 (对技/对术全禦、不動之界、天瑞仙舞、遁地神行、驱散、全复…) 返回空
static func _score_skill_targets(ctx, board, u, sk: Dictionary, targets: Array) -> Dictionary:
	var p = ctx.params
	var physical := Skills.is_physical(sk)
	var rt: int = int(sk.get("result_type", -1))
	var eff: int = int(sk.get("result_effect", -1))
	var ot: int = int(sk.get("other_type", -1))
	var oe: int = int(sk.get("other_effect", -1))
	# 伤害技能: 类型 2 (咒术伤害 / ot0 / ot1 oe0~2 / 自爆) 主分 100 (+50); 绝技附带 麻/毒/封/吸术 (ot1 oe3~6) 与 驱散 (ot2 oe12) 主分 110 (+30)
	var is_damage: bool = (not physical and rt == Skills.RT_DAMAGE) or (physical and (ot == 0 or ot == 1 or (ot == 2 and oe in [9, 12])))
	if is_damage:
		var total := 0
		var last_kill := false
		for t in targets:
			var d: int = estimate_target(ctx, u, t, sk)
			total += d
			last_kill = d >= t.hp
		var extra: bool = physical and ((ot == 1 and oe >= 3 and oe <= 6) or (ot == 2 and oe == 12))
		var base: int = p.ai_status_dmg_base if extra else p.ai_attack_base
		var bonus: int = p.ai_status_dmg_kill if extra else p.ai_kill_bonus
		return {"main": base + (bonus if last_kill else 0), "sub": total}
	# 治疗: 每个目标按 HP 比例累加, 副分 = 回复量总
	if not physical and rt == Skills.RT_HEAL:
		var healed := 0
		for t in targets:
			healed += maxi(0, Damage.heal_amount(ctx, u, t, sk, true))
		return {"main": heal_score(ctx, targets), "sub": healed}
	# 返召之咒 (rt5 eff13, 结果码 0x14): 范围内每个本阶段已行动 (字段 == 0) 的友军 +40, 累加不封顶 → 3 个就够 120 ≥ 100
	if not physical and rt == Skills.RT_SPECIAL and eff == 13:
		var rs := 0
		for t in targets:
			if t.acted or (p.ai_recall_count_idle and t.ai_passed):
				rs += p.ai_recall_each
		return {"main": rs, "sub": 0}
	# 增益 / 诅咒: 目标没有该状态时每人 +50, 上限 150
	#   攻/防/技/速/狂暴 都要求目标 12 格内有敌人, 技法提昇另要求目标会施法 (有 MP 够用的技能)
	var bit := 0
	var need_enemy := false
	var need_caster := false
	if not physical and rt == Skills.RT_BLESS and eff >= 0 and eff < Status.BLESS_BITS.size():
		if eff == 7:
			# 幻影 (无方变幻): 目标没有幻影 → 固定 110 (赋值, 不累加)
			for t in targets:
				if not t.has_status(U.ST_PHANTOM):
					return {"main": p.ai_phantom_score, "sub": 0}
			return {}
		if eff >= 5:
			return {}   # 對技/對術全禦 (类型 16/17) 不在打分表里: AI 不会用
		bit = Status.BLESS_BITS[eff]
		need_enemy = true
		need_caster = eff == 2
	elif not physical and rt == Skills.RT_CURSE:
		bit = int(Status.CURSE_BITS.get(eff, 0))
	elif physical and ot == 2 and oe == 8:
		bit = U.ST_BIND
	if bit != 0:
		var s := 0
		for t in targets:
			# 诅咒估价对每个目标掷一次命中 (case 0xb: 命中率 +) [对照 第 1 关: 随机数消耗];
			# 地缚 (绝技 ot2 oe8) 同样每个目标掷一次命中 (est 录制 2120 例: 1 目标 1 次, 无幻影/全禦预判)。
			# 但原版【不看命中结果】: 掷了骰照样每个缺该状态的目标 +50 (幻影/全禦目标也算), 与命中率无关
			# [原版 直接调 逐例对照: 封魔神道/夺魄鬼咒/鬼缚之阵 1026 例 (含目标带幻影/全禦/同状态) 位置、落点、随机数全等,]
			if (not physical and rt == Skills.RT_CURSE) or (physical and ot == 2 and oe == 8):
				var roll: int = ctx.rng.mod(100)
				if p.ai_curse_needs_hit and roll >= Skills.spell_hit(ctx, u, t, sk):
					continue
			if t.has_status(bit):
				continue
			if need_enemy and not _enemy_within(board, t, p.ai_buff_enemy_radius):
				continue
			if need_caster and not _can_cast_any(ctx, t):
				continue
			s = mini(s + p.ai_status_each, p.ai_status_cap)
		return {"main": s, "sub": 0}
	return {}


## 单个目标的技能估价: 估价伤害 + 随机数消耗, 与 flag=1 逐位一致
##   咒术伤害: 命中 1 次 (未中 0 伤害), 冰系命中后再 1 次冰結; 威力随机项取固定值
##   物理绝技: 幻影/對技全禦目标先判无效, 不取随机数、伤害 0;
##     ot0: 运气项真掷 1 次 (Str 除数固定 14) + 格挡 1 次 (格挡则 d/2, 无保底);
##     ot1: 运气项固定 Luk/15, 格挡 1 次 (格挡则 d/2 再乘倍率); oe3~6 (麻/毒/封/吸术) 未格挡再掷 1 次命中;
##     ot2 自爆/幻月: 0 次
static func estimate_target(ctx, u, t, sk: Dictionary) -> int:
	var physical := Skills.is_physical(sk)
	var ot: int = int(sk.get("other_type", -1))
	var oe: int = int(sk.get("other_effect", -1))
	if not physical:
		# 咒术估价也先掷命中 (与实战同); 未命中伤害 0。威力的随机项取固定 Int/20/2 (flag=1)
		# 敌方 离火神诀 决策消耗十余次 rand; 威力函数 估价分支不取 rand
		if ctx.rng.mod(100) >= Skills.spell_hit(ctx, u, t, sk):
			return 0
		var d: int = Damage.spell_damage(ctx, u, t, sk, true)
		d = _clamp_gap(t, d)
		if int(sk.get("attribute", -1)) == Skills.ATTR_ICE:
			ctx.rng.mod(100)   # 冰系命中后再掷一次冰結, 估价也消耗
		return d
	if t.has_status(U.ST_PHANTOM) or t.has_status(U.ST_GUARD_SKILL):
		return 0
	if ot == 2 and oe == 9:
		return _clamp_gap(t, Damage.self_destruct_damage(ctx, u, t))   # 对吸火目标的负值同样封顶到缺口 (est 录制 3 例)
	if ot == 0:
		var d0: int = Damage.skill_ot0_damage(ctx, u, t, sk, true)
		if ctx.rng.mod(100) < Attack.guard_rate(ctx, u, t):
			d0 = d0 / 2
		return d0
	var d1: int = Damage.phys_damage(ctx, u, t, false, true)
	if ot != 1:
		return d1
	var guarded: bool = ctx.rng.mod(100) < Attack.guard_rate(ctx, u, t)
	if guarded:
		d1 = d1 / 2
	if oe >= 0 and oe < ctx.params.skill_ot1_mult.size():
		d1 *= int(ctx.params.skill_ot1_mult[oe])
	if oe >= 3 and oe <= 6 and not guarded:
		ctx.rng.mod(100)   # 附加状态/吸术的命中判定 (估价也取随机数, 结果不影响估价)
	return d1


## 属性吸收的负伤害 (回血) 估价封顶到目标缺口 (est 录制: 满血目标估价为 0, 同 的结算钳制)
static func _clamp_gap(t, d: int) -> int:
	return maxi(d, -(t.hp_max - t.hp)) if d < 0 else d


## 目标是否带有一个 MP 够用的技能 (10 格技能栏, 技能 字段 = mp_cost <= 当前 MP)
static func _can_cast_any(ctx, t) -> bool:
	for sid in t.skills:
		var sk: Dictionary = ctx.skill(int(sid))
		if not sk.is_empty() and int(sk.get("mp_cost", 0)) <= t.mp:
			return true
	return false


## 治疗打分 (技能与道具相同): 每个目标 HP ≤40% +100, ≤60% +50, ≤80% +10, 累加。
## 档位阈值 = _ftol(float32(HPmax × 0.01f) × 档位%) (截断), HP ≤ 阈值才算该档
## (精确比例只在个别 HPmax 上与此差 1) 215/525=40.95% 不用药, 166/426=39% 用
static func heal_score(ctx, targets: Array) -> int:
	var s := 0
	for t in targets:
		var unit := _f32(float(t.hp_max) * 0.009999999776482582)   # = 0.01f
		for tier in ctx.params.ai_heal_tiers:
			if t.hp <= int(unit * float(int(tier[0]))):
				s += int(tier[1])
				break
	return s


static func _f32(x: float) -> float:
	var a := PackedFloat32Array([x])
	return a[0]


## 道具打分: 回 HP 同治疗; 回 MP: 有目标 MP <= 一半 → 130; 解毒/麻/封: 有该状态的目标每人 50;
## 发动技能的道具按技能打分; 上限提升道具 AI 不用
static func _score_items(ctx, board, u) -> Array:
	var out := []
	var seen := {}
	if trace_cands:
		print("  道具栏 ", u.name if "name" in u else "", u.items, " mp", u.mp)
	for iid in u.items:
		var item_id: int = int(iid)
		if seen.has(item_id) or not Items.can_use(ctx, u, item_id):
			continue
		seen[item_id] = true
		var use: Dictionary = Items.use_rec(ctx, item_id)
		var eff: int = int(use.get("effect", -1))
		var sk: Dictionary = Items.skill_of(ctx, item_id)
		for center in Items.use_cells(ctx, item_id, u.pos()):
			if not board.in_bounds(center):
				continue
			var sc := {}
			if not sk.is_empty():
				var ts: Array = Skills.targets_in_area(board, u, sk, center)
				if ts.is_empty():
					continue
				sc = _score_skill_targets(ctx, board, u, sk, ts)
			else:
				var ts: Array = Items.targets_in_area(ctx, board, u, item_id, center)
				if ts.is_empty():
					continue
				match eff:
					0:
						var healed := 0
						var base: int = int(use.get("base_power", 0))
						for t in ts:
							healed += maxi(0, Damage.item_heal_hp(ctx, t, base))
						sc = {"main": heal_score(ctx, ts), "sub": healed}
					# 1 (回 MP) 不在 的打分表里: AI 不会用术力药
					2, 3, 4:
						var n := 0
						for t in ts:
							if t.has_status(Items.CURE_BITS[eff]):
								n += 1
						sc = {"main": n * ctx.params.ai_cure_each, "sub": 0}
			if sc.is_empty():
				continue
			sc["kind"] = "item"
			sc["item"] = item_id
			sc["center"] = center
			out.append(sc)
	return out


static func _enemy_within(board, t, radius: int) -> bool:
	for o in board.hostiles_of(t):
		if Board.manhattan(o.pos(), t.pos()) <= radius:
			return true
	return false


## 走向敌群 中高: 每个格累加 4 格内敌人的距离权重, 取最大 (行优先, 严格大于)
static func crowd_target(ctx, board, u) -> Variant:
	var w := {}
	var r: int = ctx.params.ai_crowd_radius
	for e in board.hostiles_of(u):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var dist: int = absi(dx) + absi(dy)
				if dist > r:
					continue
				var c: Vector2i = e.pos() + Vector2i(dx, dy)
				if not board.in_bounds(c):
					continue
				w[c] = int(w.get(c, 0)) + int(ctx.params.ai_crowd_weights[dist])
	var best = null
	var bw := 0
	for y in board.height:
		for x in board.width:
			var c := Vector2i(x, y)
			if int(w.get(c, 0)) > bw:
				bw = w[c]
				best = c
	return best


## 曼哈顿距离最近的敌人 (同距离取先出现的) 类型 1
static func nearest_hostile(board, u):
	var best = null
	var bd := 1 << 30
	for o in board.hostiles_of(u):
		var d: int = Board.manhattan(o.pos(), u.pos())
		if d < bd:
			bd = d
			best = o
	return best


## 接近 高 (逐条照对照原版移植, B4)
##   1. 忽略单位的代价格上, 以 16×移动点求起点 → goal 的路径 (回溯同值邻格用 rand 取舍 → 消耗随机数)
##   2. 忽略单位、本阶段移动点内可达的格 (行优先) 中, 在路径上且离起点曼哈顿距离最远的为路点 p
##      (严格大于, 同距离取行优先靠前的); 没找到路径 (路径只有 goal) → 取离 goal 最近的可达格为 p
##   3. 计入单位 (敌格不可入、敌四邻 ZOC) 求可达格, 在空格 (自己所在格算空) 中取离 p 曼哈顿最近的 (严格小于, 行优先)
##   找不到 → 原地
static func approach(ctx, board, u, goal: Vector2i) -> Vector2i:
	var start: Vector2i = u.pos()
	var pts: int = u.move_left
	var free_c := cost_grid(ctx, board, u, false)
	var path := path_cells(ctx, board, free_c, start, goal, pts * 16)
	var reach0 := flood(board, free_c, start, pts)
	var wp = null
	if path.size() > 1:
		var on_path := {}
		for c in path:
			on_path[c] = true
		var best := -1
		for c in reach0:
			if on_path.has(c):
				var d: int = Board.manhattan(c, start)
				if d > best:
					best = d
					wp = c
	else:
		var best := 0xFFFF
		for c in reach0:
			var d: int = Board.manhattan(c, goal)
			if d < best:
				best = d
				wp = c
	if wp == null:
		return start
	var reach := flood(board, cost_grid(ctx, board, u, true), start, pts)
	var dest: Vector2i = start
	var bd := 0xFFFF
	for c in reach:
		var o = board.unit_at(c)
		if o != null and o != u:
			continue
		var d: int = Board.manhattan(c, wp)
		if d < bd:
			bd = d
			dest = c
	return dest


const ZOC_BIT := 0x8000

## 原版代价格: 每格 = TER_EFF[移动类型][地形];
## with_units: 敌对单位格 = 0x7FFF (幻影除外), 敌对单位四邻 |= 0x8000 (ZOC, 进入后不再扩展)
static func cost_grid(ctx, board, u, with_units: bool) -> PackedInt32Array:
	var g := PackedInt32Array()
	g.resize(board.width * board.height)
	for y in board.height:
		for x in board.width:
			g[y * board.width + x] = Movement.cell_cost(ctx, board, u, Vector2i(x, y))
	if with_units:
		var phantom: bool = u.has_status(U.ST_PHANTOM)
		for o in board.units:
			if not o.alive or o.side == u.side:
				continue
			if not phantom and board.in_bounds(o.pos()):  # 图外的单位 (如第 10 关我方从图外走入) 不占格, 也不能按 y*w+x 写到下一行
				g[o.y * board.width + o.x] = 0x7FFF
			for dv in Movement.DIRS:
				var n: Vector2i = o.pos() + dv
				if board.in_bounds(n):
					g[n.y * board.width + n.x] |= ZOC_BIT
	return g


## 洪泛可达: 返回 A≠0 的格 (行优先)。A[格] = 进入该格时上一格的剩余点; 起点 A = pts。
## ZOC 格记入但不再扩展; 进入后剩余 < 0 的格不可达。
static func flood(board, g: PackedInt32Array, start: Vector2i, pts: int, rem_out: Dictionary = {}) -> Array:
	var w: int = board.width
	var h: int = board.height
	var a := PackedInt32Array()
	a.resize(w * h)
	a.fill(0)
	if not board.in_bounds(start):  # 起点在图外: 没有可达格
		return []
	a[start.y * w + start.x] = pts
	var front := [[start.x, start.y, pts]]
	while not front.is_empty():
		var nxt := []
		for e in front:
			var x: int = e[0]
			var y: int = e[1]
			var rem: int = e[2]
			for dv in Movement.DIRS:
				var nx: int = x + dv.x
				var ny: int = y + dv.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var i: int = ny * w + nx
				if rem <= a[i]:
					continue
				var nr: int = rem - (g[i] & 0x7FFF)
				if nr < 0:
					continue
				a[i] = rem
				if g[i] & ZOC_BIT == 0:
					nxt.append([nx, ny, nr])
		front = nxt
	var out := []
	for i in w * h:
		if a[i] != 0:
			var c := Vector2i(i % w, i / w)
			out.append(c)
			# 输出表 +8 字段: 进入该格后的剩余点 (起点不扣)
			rem_out[c] = a[i] if c == start else a[i] - (g[i] & 0x7FFF)
	return out


## 寻路: 洪泛 (记方向与转弯数) 后从 goal 回溯到起点, 返回 [goal, ..., 起点];
## 找不到 → [goal]。回溯每步看上、下、左、右四邻的 A 值取最大; 同值时 rand()%100 < 50 换成后看的格,
## 否则转弯数更大才换 (右邻比较的是左邻的转弯数且不更新, 原版如此); 上邻 A = 0 也要掷一次。
static func path_cells(ctx, board, g: PackedInt32Array, start: Vector2i, goal: Vector2i, pts: int) -> Array:
	var w: int = board.width
	var h: int = board.height
	var a := PackedInt32Array()
	a.resize(w * h)
	a.fill(0)
	var t := PackedInt32Array()
	t.resize(w * h)
	t.fill(0)
	if not board.in_bounds(start):  # 起点在图外: 无路径 (同 flood)
		return [goal]
	a[start.y * w + start.x] = pts
	var front := [[-1, 0, pts, start.x, start.y]]   # 方向, 转弯数, 剩余, x, y
	while not front.is_empty():
		var nxt := []
		for e in front:
			var dir: int = e[0]
			var turns: int = e[1]   # 原版在同一格的四个方向间累加 (不复位)
			var rem: int = e[2]
			var x: int = e[3]
			var y: int = e[4]
			for d in 4:
				var dv: Vector2i = Movement.DIRS[d]
				var nx: int = x + dv.x
				var ny: int = y + dv.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var i: int = ny * w + nx
				if rem <= a[i]:
					continue
				var nr: int = rem - (g[i] & 0x7FFF)
				if nr < 0:
					continue
				if dir != -1 and dir != d:
					turns += 1
				t[i] = turns
				if g[i] & ZOC_BIT:
					a[i] = 0
				else:
					a[i] = rem
					nxt.append([d, turns, nr, nx, ny])
		front = nxt
	var path := [goal]
	var cur := goal
	var t18 := 0
	while cur != start:
		var best := 0
		var bt := -1
		var pick := cur
		if cur.y - 1 >= 0:
			var i: int = (cur.y - 1) * w + cur.x
			t18 = t[i]
			if a[i] > 0:
				pick = Vector2i(cur.x, cur.y - 1); bt = t[i]; best = a[i]
			elif a[i] == 0:
				ctx.rng.rand()   # 结果不影响: 两支都选上邻 (best 仍 0)
				pick = Vector2i(cur.x, cur.y - 1); bt = t[i]
		for d in [1, 2, 3]:
			var n: Vector2i = cur + Movement.DIRS[d]
			if not board.in_bounds(n):
				continue
			var i: int = n.y * w + n.x
			var v: int = a[i]
			if d != 3:
				t18 = t[i]
			var take := false
			if best < v:
				take = true
			elif best == v:
				take = ctx.rng.rand() % 100 < 50 or bt < t18
			if take:
				pick = n
				best = v
				if d != 3:
					bt = t18
		if best == 0:
			break
		path.append(pick)
		cur = pick
	return path


## 一个 AI 单位本阶段的计划。返回 {move_to: Vector2i, action: Dictionary(可空)}
static func plan(ctx, board, u) -> Dictionary:
	var stay := {"move_to": u.pos(), "action": {}}
	if not Status.can_act(u):
		return stay   # 麻痺、冰結按类型 0 处理
	if u.side == 0 and not u.npc_ally:
		return _plan_active(ctx, board, u, stay)   # 玩家单位 (仅测试代打): 原版 AI 分发只对敌方与友军 NPC (字段≠0) 调用, 保留的 AI 类型不参与
	var t: int = u.ai
	var alias: Dictionary = ctx.params.ai_type_alias
	if not alias.is_empty():
		t = int(alias.get(str(t), t))   # 数据新增的类型 = 已有类型的别名 (rules.json ai_type_alias)
	return behavior_for(t).call(ctx, board, u, stay)


## ---- AI 行为注册表: 类型号 -> Callable(ctx, board, u, stay) -> {move_to, action} ----
## 默认注册原版 5 种 (0 待机 / 1 主动 / 2 消极 / 3 跟随 / 4 定点); 未注册的类型号走「主动」(原版 default 分支)。
## mod 的 GDScript 用 register_behavior(5, 自己的 Callable) 新增第 6 种; 只改数据的 mod 用 rules.json 的
## ai_type_alias {"5": 1} 把新类型号映射到已有行为。测试用 reset_behaviors() 还原。见 docs/AI行为注册表.md
static var _behaviors: Dictionary = {}


static func _ensure_defaults() -> void:
	if not _behaviors.is_empty():
		return
	_behaviors[U.AI_IDLE] = func(_ctx, _board, _u, stay): return stay
	_behaviors[U.AI_ACTIVE] = func(ctx, board, u, stay): return _plan_active(ctx, board, u, stay)
	_behaviors[U.AI_PASSIVE] = func(ctx, board, u, stay): return _from_decision(decide(ctx, board, u), stay)
	_behaviors[U.AI_FOLLOW] = func(ctx, board, u, stay): return _plan_follow(ctx, board, u, stay)
	_behaviors[U.AI_GOTO] = func(ctx, board, u, _stay):
		return _plan_move_then_act(ctx, board, u, Vector2i(u.ai_target[0], u.ai_target[1]))


## 注册 / 覆盖一个 AI 类型的行为; fn(ctx, board, u, stay: Dictionary) -> {move_to: Vector2i, action: Dictionary}
static func register_behavior(type: int, fn: Callable) -> void:
	_ensure_defaults()
	_behaviors[type] = fn


static func has_behavior(type: int) -> bool:
	_ensure_defaults()
	return _behaviors.has(type)


## 类型号对应的行为; 未注册 = 「主动」
static func behavior_for(type: int) -> Callable:
	_ensure_defaults()
	return _behaviors.get(type, _behaviors[U.AI_ACTIVE])


## 清掉所有注册, 下次使用时重新注册原版 5 种 (测试 / 换内容包)
static func reset_behaviors() -> void:
	_behaviors = {}


static func _from_decision(d: Dictionary, stay: Dictionary) -> Dictionary:
	if d.is_empty():
		return stay
	return {"move_to": d.cell, "action": d}


## 类型 1 主动 中高
static func _plan_active(ctx, board, u, stay: Dictionary) -> Dictionary:
	var d := decide(ctx, board, u)
	if not d.is_empty():
		return {"move_to": d.cell, "action": d}
	if u.has_status(U.ST_BIND) or u.moved:
		return stay
	var goal = null
	if int(u.ai_target[0]) == 0:
		var e = nearest_hostile(board, u)
		if e != null:
			goal = e.pos()
	else:
		goal = crowd_target(ctx, board, u)
	if goal == null:
		return stay
	return {"move_to": approach(ctx, board, u, goal), "action": {}}


## 先朝 goal 前进, 再只从到达格出手 (类型 4; 类型 3 且 字段≠0)
static func _plan_move_then_act(ctx, board, u, goal: Vector2i) -> Dictionary:
	var dest: Vector2i = u.pos()
	if not u.has_status(U.ST_BIND):
		dest = approach(ctx, board, u, goal)
	var start: Vector2i = u.pos()
	var saved_moved: bool = u.moved
	var saved_left: int = u.move_left
	var spent: int = int(Movement.reachable(ctx, board, u).get(dest, 0))
	u.set_pos(dest)
	u.moved = u.moved or dest != start
	u.move_left -= spent
	var d := decide(ctx, board, u, true)
	u.set_pos(start)
	u.moved = saved_moved
	u.move_left = saved_left
	return {"move_to": dest, "action": d}


## 跟随目标附近的落脚格: 带单位阻挡 / ZOC 的可达格里取【空格】(单位格网 不登记自己, 自己所在格算空),
## 离 leader 曼哈顿最近 (严格小于; 同距离取剩余移动点更大的, 严格大于; 再同则取行优先靠前),
## 最近距离 > 2 视为没有 (返回 null)。
static func near_leader_cell(ctx, board, u, leader) -> Variant:
	var rem := {}
	# 洪泛点数 = (移动点+保留点) x 16, 传的是 shl 4 之后的值, 等于不受本阶段移动力限制 [第 1 关对照: 领队在 7 格外时仍朝领队走]
	var reach := flood(board, cost_grid(ctx, board, u, true), u.pos(), u.move_left * 16, rem)
	var best = null
	var bd := 0xFFFF
	var br := -1
	for c in reach:
		var occ = board.unit_at(c)
		if occ != null and occ != u:
			continue
		var d: int = Board.manhattan(c, leader.pos())
		var r: int = int(rem[c])
		if d < bd or (d == bd and r > br):
			bd = d
			br = r
			best = c
	if best == null or bd > 2:
		return null
	return best


## 类型 3 跟随单位 (目标 = 字段) 对照原版核过
##   字段 == 0: 先决策; 打不到: 地缚 → 不动; 否则 目标 = near_leader_cell (2 格内空格) 找不到 → 走向敌群 → approach
##   字段 != 0: 地缚 → 原地; 否则 目标 = near_leader_cell, 找不到 → 目标单位所在格; approach 后只从到达格出手
static func _plan_follow(ctx, board, u, stay: Dictionary) -> Dictionary:
	var leader = null
	for o in board.units:
		if o.alive and o.uid == int(u.ai_target[1]):
			leader = o
	if leader == null:
		return _plan_active(ctx, board, u, stay)
	if int(u.ai_target[0]) != 0:
		var goal: Vector2i = leader.pos()
		if not u.has_status(U.ST_BIND):
			var near = near_leader_cell(ctx, board, u, leader)
			if near != null:
				goal = near
		return _plan_move_then_act(ctx, board, u, goal)
	var d := decide(ctx, board, u)
	if not d.is_empty():
		return {"move_to": d.cell, "action": d}
	if u.has_status(U.ST_BIND):
		return stay
	var g = near_leader_cell(ctx, board, u, leader)
	if g == null:
		g = crowd_target(ctx, board, u)
	if g == null:
		return stay
	return {"move_to": approach(ctx, board, u, g), "action": {}}


## 执行计划 (移动 + 普攻交换 / 技能), 返回结算记录。AI 行动开始写变量 102 等剧情副作用由调用方处理。
static func execute(ctx, board, u, pl: Dictionary) -> Dictionary:
	var rec := {"moved_to": pl.move_to, "result": null}
	Movement.move_to(ctx, board, u, pl.move_to)
	var act: Dictionary = pl.get("action", {})
	if act.is_empty():
		Movement.end_action(u)
		return rec
	if act.kind == "attack":
		rec.result = Attack.exchange(ctx, u, act.target)
	elif act.kind == "skill":
		var sk: Dictionary = ctx.skill(int(act.skill))
		Skills.consume(ctx, u, sk)
		rec.result = Skills.resolve(ctx, u, sk, Skills.targets_in_area(board, u, sk, act.center))
	elif act.kind == "item":
		rec.result = use_item(ctx, board, u, int(act.item), act.center)
	Movement.end_action(u)
	return rec


## 使用道具: 先扣使用者物品与 MP, 再对范围内目标结算; 发动技能的道具走技能流程 (from_item, 不给经验)
static func use_item(ctx, board, u, item_id: int, center: Vector2i) -> Dictionary:
	var sk: Dictionary = Items.skill_of(ctx, item_id)
	Items.consume(ctx, u, item_id)
	if not sk.is_empty():
		return Skills.resolve(ctx, u, sk, Skills.targets_in_area(board, u, sk, center), {"from_item": true})
	var res := {"targets": []}
	for t in Items.targets_in_area(ctx, board, u, item_id, center):
		var r := Items.apply_effect(ctx, t, item_id)
		r["target"] = t
		res.targets.append(r)
	return res

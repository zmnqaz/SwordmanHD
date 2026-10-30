# SPDX-License-Identifier: GPL-3.0-only
class_name BattleRules
extends RefCounted
## 战斗规则适配层: 把战场 (BattleScene / BattleUnit) 接到规则引擎 engine/rules。
## 这里不写规则公式 —— 移动、命中、伤害、状态、技能、道具、经验、AI、胜负全在 engine/rules (依据)。
## 本文件只负责: 建上下文与棋盘、BattleUnit <-> UnitState 对照、--god 测试开关、--autoplay 代打的少量策略。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

const Params = preload("res://engine/rules/params.gd")
const Context = preload("res://engine/rules/context.gd")
const Rng = preload("res://engine/rules/rng.gd")
const Board = preload("res://engine/rules/board.gd")
const U = preload("res://engine/rules/unit_state.gd")
const Stats = preload("res://engine/rules/stats.gd")
const Movement = preload("res://engine/rules/movement.gd")
const Attack = preload("res://engine/rules/attack.gd")
const Damage = preload("res://engine/rules/damage.gd")
const Status = preload("res://engine/rules/status.gd")
const Skills = preload("res://engine/rules/skills.gd")
const Items = preload("res://engine/rules/items.gd")
const Inventory = preload("res://engine/rules/inventory.gd")
const Exp = preload("res://engine/rules/exp.gd")
const Growth = preload("res://engine/rules/growth.gd")
const AI = preload("res://engine/rules/ai.gd")
const Flow = preload("res://engine/rules/flow.gd")

var bs  # battle_scene
var ctx
var board


func _init(scene) -> void:
	bs = scene
	ctx = Context.new(Content.params(), Rng.new(battle_seed()))
	AI.trace_cands = gc.debug.ai_cands   # 规则层不读命令行: 对照开关由这里注入
	# 通关录像: 读战阵存录会换种子, 回放时到那个点调这个。用方法 Callable 不用 lambda: 静态变量里的 lambda
	# 在退出时晚于脚本释放, 会把堆写坏 (glibc "corrupted size vs. prev_size", 测试进程退出码 134)
	PlayLog.reseed_hook = ctx.rng.set_seed
	ctx.load_records(Content.items(), Content.skills(), Content.table("attribute_defense"), Content.table("levelup"), Content.units())
	if gc.god:  # 测试 --god: 我方移动点 +12 (见 Params.test_move_bonus), 与免伤、打敌每击至少 1/3 体力同属「保证代打能推进」的测试开关, 不是原版规则
		ctx.params.test_move_bonus = 12
	board = Board.new(bs.st.width, bs.st.height)
	for y in bs.st.height:
		for x in bs.st.width:
			board.set_terrain(Vector2i(x, y), int(bs.st.cell(x, y)["move"]))


## 每关的随机数种子: 显式 --seed=N 时固定 (确定性回归用);
## 没传则随机 (原版行为: 战阵重现再进来闪避/命中的 rolls 不同, 会话用户实测报告)

static func battle_seed() -> int:
	var s = GameContext.current().debug.rng_seed
	if s != null:
		return PlayLog.seed_for_battle(int(s))   # 通关录像: 录制时记下种子, 回放时取回当时的
	return PlayLog.seed_for_battle(int(Time.get_unix_time_from_system() * 1000) & 0x7FFFFFFF)


## 棋盘上的单位 = 在场 (存活且已现身) 的单位
func sync() -> void:
	board.units = units_alive().map(func(u): return u.st)


func units_alive() -> Array:
	return bs.units.filter(func(u): return u.alive and u.shown)


func unit_of(s) -> BattleUnit:
	return null if s == null else bs.unit(s.uid)


func unit_at(c: Vector2i, except: BattleUnit = null) -> BattleUnit:
	for u in units_alive():
		if u != except and u.cx == c.x and u.cy == c.y:
			return u
	return null


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return Board.manhattan(a, b)


# ================= 移动 (02) =================

## 本阵营阶段开始: 移动点 = 上限 (含爆發保留点), 清行动标志
func begin_phase(u: BattleUnit) -> void:
	Movement.begin_phase(ctx, u.st)


## 可停留格 -> 已用移动点 (含原地)
func move_range(u: BattleUnit) -> Dictionary:
	sync()
	return Movement.reachable(ctx, board, u.st)


## 用最大移动力算的可停留格 (查看已行动/友军/敌方单位的范围, 2.1); 不改单位状态
func move_range_full(u: BattleUnit) -> Dictionary:
	sync()
	return Movement.reachable(ctx, board, u.st, Movement.move_cap(ctx, u.st))


## 到 to 的路径 (不含起点); 不可达为空
func path_in_range(u: BattleUnit, to: Vector2i) -> Array:
	sync()
	var p := Movement.path_to(Movement.search(ctx, board, u.st), to)
	return p.slice(1)


## 走到 to (扣移动点, 置已移动)。返回路径 (不含起点)
func commit_move(u: BattleUnit, to: Vector2i) -> Array:
	var path := path_in_range(u, to)
	Movement.move_to(ctx, board, u.st, to)
	return path


## 移动前的状态, 取消行动菜单时恢复 (撤销移动)
func move_snapshot(u: BattleUnit) -> Dictionary:
	return {"pos": u.st.pos(), "left": u.st.move_left, "reserve": u.st.burst_reserve, "moved": u.st.moved}


func move_restore(u: BattleUnit, s: Dictionary) -> void:
	u.st.move_left = s["left"]
	u.st.burst_reserve = s["reserve"]
	u.st.moved = s["moved"]
	u.set_cell(s["pos"].x, s["pos"].y)


func can_start_action(u: BattleUnit) -> bool:
	return Movement.can_start_action(u.st)


## 系统菜单「存讀 → 存档」是否可选: 我方阶段开始、我方尚无人行动 (友军 NPC 不算)
func can_save_battle() -> bool:
	if ctx.params.battle_save_after_action:
		return true
	return Flow.can_save_battle(bs.units.map(func(u): return u.st), true)


func can_burst(u: BattleUnit) -> bool:
	return Movement.can_burst(ctx, u.st)


func burst(u: BattleUnit) -> void:
	Movement.burst(ctx, u.st)


func end_action(u: BattleUnit) -> void:
	Movement.end_action(u.st)
	u.acted_fx = true


# ================= 普攻 (03, §2 §6) =================

func weapon_cells(u: BattleUnit, from: Vector2i) -> Array:
	return Attack.range_cells(from, Stats.weapon_range(ctx, u.st))


func targets_from(u: BattleUnit, from: Vector2i) -> Array:
	var cells := weapon_cells(u, from)
	return units_alive().filter(func(t): return t.hostile(u) and Vector2i(t.cx, t.cy) in cells)


## 一次普攻交换 (主攻 + 反击一次), 已作用到单位上: 就是 Attack.exchange (唯一实现), 仅挂上 --god 钩子。
## 返回 {main, counter (可空), exp_attacker, exp_defender, main_apply, counter_apply}
func exchange(a: BattleUnit, d: BattleUnit) -> Dictionary:
	sync()
	return Attack.exchange(ctx, a.st, d.st, _god_strike)


## 近景演出用: strike 结果 -> [{kind, damage}] (连击 = 一次结算 x2, 演出分两段)
static func strike_kinds(r: Dictionary) -> Array:
	match int(r.result):
		Attack.Result.MISS:
			return [{"kind": "miss", "damage": 0}]
		Attack.Result.GUARD:
			if r["double"]:
				return [{"kind": "guard", "damage": r.damage / 2}, {"kind": "guard", "damage": r.damage - r.damage / 2}]
			return [{"kind": "guard", "damage": r.damage}]
	var kind := "critical" if r.crit else ("double" if r["double"] else "hit")
	if r["double"]:
		return [{"kind": kind, "damage": r.damage / 2}, {"kind": kind, "damage": r.damage - r.damage / 2}]
	return [{"kind": kind, "damage": r.damage}]


## 格挡 (红闪避) 的全屏闪色: {color, sec} 或 {} (非格挡)
func guard_flash(r: Dictionary) -> Dictionary:
	return Attack.guard_flash(ctx, r)


## 战斗中装备/丢弃之后: 原版不消耗行动 (返回 false); 魔改开关 equip_costs_action 为真时结束行动 (返回 true)
func after_equip_or_discard(u: BattleUnit) -> bool:
	return Items.after_equip_or_discard(ctx, u.st)


## 测试 --god: 我方不受伤害; 我方打敌人每击至少体力上限 1/3 (保证自动通关能推进)
func _god_strike(a, d, r: Dictionary) -> void:  # a/d: UnitState (Attack.exchange 的 post_strike 钩子)
	if not gc.god:
		return
	if d.side == 0:
		r.result = Attack.Result.MISS
		r.damage = 0
		r.add = false
	elif a.side == 0:
		if r.result == Attack.Result.MISS:
			r.result = Attack.Result.HIT
		r.damage = maxi(r.damage, (d.hp_max + 2) / 3)


# ================= 技能 (07) =================

func skill(id: int) -> Dictionary:
	return ctx.skill(id)


func summon_flags() -> Dictionary:
	var f := {}
	for v in ctx.params.summon_flag_vars:
		f[v] = gc.state.get_data(v)
	return f


## 使用条件 (封咒、MP、咒术未移动、绝技移动点、自爆 HP、召唤标志)
func can_cast(u: BattleUnit, id: int) -> bool:
	var sk := skill(id)
	return not sk.is_empty() and Skills.can_use(ctx, u.st, sk, summon_flags())


## 召唤的预置隐藏单位 (unit_id = power, 当前不在场)
func summon_candidate(sk: Dictionary) -> BattleUnit:
	for o in bs.units:
		if int(o.man["unit_id"]) == int(sk["power"]) and not (o.alive and o.shown):
			return o
	return null


## 施放范围 (地图内; 显示用)
func cast_range(u: BattleUnit, sk: Dictionary) -> Array:
	sync()
	return Skills.cast_cells(sk, u.st.pos()).filter(func(c): return board.in_bounds(c))


## 道具使用范围 (地图内; 显示用)
func item_range(u: BattleUnit, item_id: int) -> Array:
	sync()
	return Items.use_cells(ctx, item_id, u.st.pos()).filter(func(c): return board.in_bounds(c))


## 选落点时光标的形状 = 效果范围 (法术 / 道具; 其他 0)
func cast_area(sk: Dictionary) -> int:
	return int(sk.get("range", {}).get("area", 0))


func item_area(item_id: int) -> int:
	sync()
	return int(Items.use_range(ctx, item_id).get("area", 0))


## 召唤落点是否有效 (技能与道具共用): 有预置的隐藏召唤物, 且是空格。不看地形:
## 原版实测 (原版, 存档大礼包 happy ending 第 34 关, 真胤式鬼召唤): 式鬼 (步行 2, 地形 8 不可通行) 照样召到 (5,35) (地形 8) 上,
## 召唤放置 / 选格都没有通行判定 (道具召唤同样没有)
func summon_cell_ok(sk: Dictionary, c: Vector2i) -> bool:
	return summon_candidate(sk) != null and board.unit_at(c) == null


## 有效落点: 召唤 = 射程内的空地; 其他 = 至少影响到一个合法目标的格
func cast_cells(u: BattleUnit, sk: Dictionary) -> Array:
	sync()
	var out: Array = []
	for c in Skills.cast_cells(sk, u.st.pos()):
		if not board.in_bounds(c):
			continue
		if Skills.is_summon(sk):
			if summon_cell_ok(sk, c):
				out.append(c)
		elif not Skills.targets_in_area(board, u.st, sk, c).is_empty():
			out.append(c)
	return out


func affected(u: BattleUnit, sk: Dictionary, c: Vector2i) -> Array:
	sync()
	return Skills.targets_in_area(board, u.st, sk, c).map(unit_of)


## 施放: 扣消耗 (道具发动另算) 并结算。返回 Skills.resolve 的结果, targets 每项另加 unit
func cast(u: BattleUnit, sk: Dictionary, c: Vector2i, opts: Dictionary = {}) -> Dictionary:
	sync()
	if not opts.get("from_item", false):
		Skills.consume(ctx, u.st, sk)
	var targets := Skills.targets_in_area(board, u.st, sk, c)
	var saved := {}
	if gc.god:  # 测试 --god: 我方不受技能伤害与负面状态
		for t in targets:
			if t.side == 0 and t != u.st and int(sk.get("target", 1)) == 1:
				saved[t] = t.to_dict()
	var res := Skills.resolve(ctx, u.st, sk, targets, opts)
	for t in saved:
		t.from_dict(saved[t])
	for r in res.targets:
		r["unit"] = unit_of(r.target)
		if saved.has(r.target):
			r.damage = 0
			r.killed = false
			r.hit = false
	return res


# ================= 道具 =================

## 战斗中可「使用」的物品: 只看本人 10 格; 条件见 Items.can_use (有使用目标、MP 够、道具或已装备的那件)
func usable_items(u: BattleUnit) -> Array:
	sync()
	var out: Array = []
	for id in u.st.items:
		id = int(id)
		if out.has(id) or not Items.can_use(ctx, u.st, id):
			continue
		var flag_var := Items.summon_check_var(ctx, id)
		if flag_var >= 0 and gc.state.get_data(flag_var) != 0:
			continue  # 召唤石: 检查的是技能记录的标志变量 (三件都是 103), 不是物品自己的 104~106
		out.append(id)
	return out


# ---- 物品栏操作 (规则在 engine/rules/inventory.gd; 这里只接 BattleUnit) ----

func inv_equipped(u: BattleUnit) -> Dictionary:
	return Inventory.equipped_map(u.st)


func inv_can_give(u: BattleUnit, i: int) -> bool:
	return Inventory.can_give(u.st, i)


func inv_can_equip(u: BattleUnit, i: int) -> bool:
	return Inventory.can_equip(ctx, u.st, i)


func inv_equip(u: BattleUnit, i: int) -> void:
	Inventory.equip(ctx, u.st, i)


func inv_discard(u: BattleUnit, i: int) -> int:
	return Inventory.discard(u.st, i)


func inv_full(u: BattleUnit) -> bool:
	return Inventory.is_full(ctx, u.st)


## 放进本人 10 格 (宝箱/掉落): 满了返回 false (调用方询问丢弃)
func inv_pickup(u: BattleUnit, id: int) -> bool:
	return Inventory.pickup(ctx, u.st, id)


## 相邻 (曼哈顿 1) 可接收物品的我方单位 (不含自己), 含友军 NPC 与召唤物。
## 友军 NPC 可作目标 [原版实测: 第 0 幕档里把应奉仁挪到殷剑平邻格, 交給的目标光标能选中他, 提示「身上物品太多了」「取得燧石.」都正常出现];
## 召唤物也可 [交給流程对「目标是召唤物 (字段>0)」单独处理头像]; 敌人不是目标 (side 不同)
func give_targets(u: BattleUnit) -> Array:
	var out: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: BattleUnit = unit_at(Vector2i(u.cx, u.cy) + d)
		if t != null and t != u and t.alive and t.st.side == u.st.side:
			out.append(t)
	return out


## 给予: 对方未满追加; 满了返回 false (调用方走 inv_exchange)。成功后按 give_costs_action 结束行动, 返回是否结束
func inv_give(u: BattleUnit, i: int, t: BattleUnit) -> bool:
	return Inventory.give(ctx, u.st, i, t.st)


func inv_exchange(u: BattleUnit, i: int, t: BattleUnit, j: int) -> Dictionary:
	return Inventory.exchange(u.st, i, t.st, j)


func after_give(u: BattleUnit) -> bool:
	return Items.after_give(ctx, u.st)


func item_cells(u: BattleUnit, item_id: int) -> Array:
	sync()
	var sk := Items.skill_of(ctx, item_id)
	var out: Array = []
	for c in Items.use_cells(ctx, item_id, u.st.pos()):
		if not board.in_bounds(c):
			continue
		if not sk.is_empty():
			if Skills.is_summon(sk):
				if summon_cell_ok(sk, c):
					out.append(c)
			elif not Skills.targets_in_area(board, u.st, sk, c).is_empty():
				out.append(c)
		elif not Items.targets_in_area(ctx, board, u.st, item_id, c).is_empty():
			out.append(c)
	return out


## 使用道具: 先扣 (消耗品从行囊或个人物品栏、MP), 再结算。发动技能的道具走技能结算 (不给经验)。
## 返回 {skill (可空), res}: 技能道具 res = Skills.resolve 结果; 否则 res.targets = [{unit, healed, mp, cured, raised}]
func use_item(u: BattleUnit, item_id: int, c: Vector2i) -> Dictionary:
	sync()
	var use: Dictionary = Items.use_rec(ctx, item_id)
	u.mp -= int(use.get("mp_cost", 0))
	if bool(use.get("consumable", false)):
		Inventory.remove_one(u.st, item_id)  # 药从使用者本人的物品栏扣
	var sk := Items.skill_of(ctx, item_id)
	if not sk.is_empty():
		return {"skill": sk, "res": cast(u, sk, c, {"from_item": true})}
	var out := {"skill": {}, "res": {"targets": []}}
	for t in Items.targets_in_area(ctx, board, u.st, item_id, c):
		var r := Items.apply_effect(ctx, t, item_id)
		r["unit"] = unit_of(t)
		out.res.targets.append(r)
	return out


# ================= 状态 (05) / 经验 (08) / 升级 =================

## 阶段开始结算一个单位 (中毒、R-=K)。返回 Status.phase_tick 结果
func tick(u: BattleUnit) -> Dictionary:
	if gc.god and u.st.side == 0:  # 测试 --god: 我方不受中毒伤害
		var hp0: int = u.hp
		var r := Status.phase_tick(ctx, u.st)
		u.hp = hp0
		u.alive = true
		r.poison_damage = 0
		r.died = false
		return r
	return Status.phase_tick(ctx, u.st)


## 阶段要结算的单位 (含友军 NPC 一轮两次)
func units_to_tick(phase: String) -> Array:
	sync()
	return Status.units_to_tick(ctx, board.units, phase).map(unit_of)


## 获得经验 (500 升一级, 99 级封顶), 返回每次升级的结果 [{gains, learned}]
func gain_exp(u: BattleUnit, amount: int) -> Array:
	return Growth.gain_exp(ctx, u.st, amount, ctx.levelup.get(u.st.unit_id, {}))


# ================= AI (09) =================

## AI 计划: {move_to, action: {kind: attack/skill/item, target/skill/item, center}}; action 为空 = 只移动
func ai_plan(u: BattleUnit) -> Dictionary:
	sync()
	var plan: Dictionary = AI.plan(ctx, board, u.st)
	if gc.autoplay and u.controllable:
		plan = _autoplay_adjust(u, plan)
	Attack.trace = gc.debug.ai_trace
	if gc.debug.ai_trace:  # 对照: 每个 AI 单位本阶段的决定
		var a: Dictionary = plan.action
		print("AI回合%d %s#%d ai%d (%d,%d)->(%d,%d) hp%d/%d mp%d rng=%d %s" % [bs.turn, u.name_text, u.index, u.st.ai, u.cx, u.cy, plan.move_to.x, plan.move_to.y, u.hp, u.hp_max, u.mp, ctx.rng.get_state(),
			"待命" if a.is_empty() else ("%s %s 分 %s/%s" % [a.get("kind", "?"), str(a.get("target", a.get("center", ""))), str(a.get("main")), str(a.get("sub"))]) + " sk=" + str(a.get("skill", a.get("item", "")))])
	return plan


func board_unit(uid: int):
	for s in board.units:
		if s.uid == uid:
			return s
	return null


## 代打 (--autoplay) 的我方策略补充, 不是原版规则:
##   无事可做时走向「能打到」的最近敌人 (按地形路程, 避免卡在够不着的敌人旁边, 如第 23 关);
##   场上没有敌人时 (如第 24 关「全员从右下角脱离」) 走向最近的玩家可触发的地图事件格;
##   格数少于人数的事件格只留给主角 (MAN 下标最小的玩家单位; 第 28 关要殷剑平本人踩 (12,33));
##   不占剧情接管的友军 (AI 4) 要去的格子 (如第 31 关封寒月走向封印格)
const AUTOPLAY_CLAIM_CAP := 3         # 一个敌人最多被几个代打单位同回合认领后开始分摊
const AUTOPLAY_CLAIM_PENALTY := 40    # 超额认领的敌人路程加的惩罚 (格路程单位)
var _claims := {}                     # 本回合 敌人格 -> 已认领的代打单位数
var _claims_turn := -1


var _loot_seen := {}
var _autoplay_loot: bool = gc.debug.autoplay_loot   # 测试: 代打无事可做时先去拿还在场上的宝物 (道具获取核对)


## 还没被拿走的宝物所在格 (物品/金钱宝箱, 含隐藏)
func _treasure_cells() -> Array:
	var cells: Array = []
	for y in bs.st.height:
		for x in bs.st.width:
			var m: Dictionary = bs.ctl.map_events.get(int(bs.st.cell(x, y)["event"]), {})
			if not m.is_empty() and int(m["type"]) == 1 and int(m["item_type"]) in [1, 2] and not _loot_seen.has(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	return cells


func _autoplay_adjust(u: BattleUnit, plan: Dictionary) -> Dictionary:
	var reserved: Array = []
	for o in units_alive():
		if o != u and o.camp != 1 and o.ai == U.AI_GOTO:
			reserved.append(Vector2i(o.st.ai_target[0], o.st.ai_target[1]))
	var players := units_alive().filter(func(o): return o.controllable)
	var leader: bool = players.all(func(o): return o.index >= u.index)
	var goals: Array = []
	var by_event := {}
	for y in bs.st.height:
		for x in bs.st.width:
			var e := int(bs.st.cell(x, y)["event"])
			var m: Dictionary = bs.ctl.map_events.get(e, {})
			if not m.is_empty() and int(m["type"]) == 0 and int(m["parm1"]) in [0, 2, 4, 6]:
				by_event.get_or_add(e, []).append(Vector2i(x, y))
	for e in by_event:
		if by_event[e].size() < players.size() and not leader:
			reserved.append_array(by_event[e])
		else:
			goals.append_array(by_event[e])
	if plan.action.is_empty():
		var goal := Vector2i(-1, -1)
		if _autoplay_loot:
			goal = _nearest_free(u, _treasure_cells())
			if goal == Vector2i(u.cx, u.cy):   # 已站在宝物格上还在 (拒开/满格放弃): 不再回头
				_loot_seen[goal] = true
				goal = Vector2i(-1, -1)
		if goal.x >= 0:
			pass
		elif board.hostiles_of(u.st).is_empty():
			goal = _nearest_free(u, goals)
		else:
			goal = _attackable_goal(u)
		if goal.x >= 0:
			plan = {"move_to": _autoplay_step(u, goal), "action": {}}
	if plan.move_to in reserved:
		var reach := Movement.reachable(ctx, board, u.st)
		var best := Vector2i(-1, -1)
		for c in reach:
			if not c in reserved and (best.x < 0 or manhattan(c, plan.move_to) < manhattan(best, plan.move_to)):
				best = c
		if best.x >= 0:
			var start: Vector2i = u.st.pos()
			u.st.set_pos(best)
			var d := AI.decide(ctx, board, u.st, true)
			u.st.set_pos(start)
			plan = {"move_to": best, "action": d}
	return plan


## 朝 goal 走一步: 在本回合可停的空格里取「离 goal 地形路程最小」者 (原版 AI.approach 用曼哈顿取路点, 绕墙时会来回摆动,
## 第 23 关代打因此拖过第 34 回合时限; 代打自己的移动不必照搬, 按路程取最近才通用)
func _autoplay_step(u: BattleUnit, goal: Vector2i) -> Vector2i:
	var start: Vector2i = u.st.pos()
	var reach := Movement.reachable(ctx, board, u.st)
	u.st.set_pos(goal)
	var from_goal: Dictionary = Movement.search(ctx, board, u.st, 1 << 20, true).cost
	u.st.set_pos(start)
	var best := start
	var bc: int = int(from_goal.get(start, 1 << 30))
	for c in reach:
		var d: int = int(from_goal.get(c, 1 << 30))
		if d < bc:
			bc = d
			best = c
	return best


func _nearest_free(u: BattleUnit, cells: Array) -> Vector2i:
	var here := Vector2i(u.cx, u.cy)
	var best := Vector2i(-1, -1)
	# 地形上走不到的格 (事件格里夹着不可通行地形, 如第 24 关 (21,66)) 不当目标, 否则代打会原地不动、拖到 100 回合
	var walk: Dictionary = Movement.search(ctx, board, u.st, 1 << 20, true).cost
	for c in cells:
		var o = board.unit_at(c)
		if not walk.has(c):
			continue
		if (o == null or o == u.st) and (best.x < 0 or manhattan(here, c) < manhattan(here, best)):
			best = c
	return best


## 按地形路程 (忽略单位) 最近的、能用武器打到某个敌人的空格
func _attackable_goal(u: BattleUnit) -> Vector2i:
	var full := Movement.search(ctx, board, u.st, 1 << 20, true)
	var rg: Dictionary = Stats.weapon_range(ctx, u.st)
	if _claims_turn != bs.turn:  # 新回合: 目标认领清零
		_claims_turn = bs.turn
		_claims.clear()
	var best := Vector2i(-1, -1)
	var best_e := Vector2i(-1, -1)
	var bc := 1 << 30
	for e in board.hostiles_of(u.st):
		var ep: Vector2i = e.pos()
		# 已被本回合其他代打单位认领 AUTOPLAY_CLAIM_CAP 个以上的敌人, 路程按 +AUTOPLAY_CLAIM_PENALTY 计: 人多时分摊到别的敌人,
		# 不让全队扎堆打同一批而放着远处待命的敌人不管 (第 23 关 34 回合限时, 两只待命赤壳蜈蚣没人去追)
		var pen: int = AUTOPLAY_CLAIM_PENALTY if int(_claims.get(ep, 0)) >= AUTOPLAY_CLAIM_CAP else 0
		for c in Attack.range_cells(ep, rg):
			var o = board.unit_at(c)
			if full.cost.has(c) and (o == null or o == u.st) and int(full.cost[c]) + pen < bc:
				bc = int(full.cost[c]) + pen
				best = c
				best_e = ep
	if best_e.x >= 0:
		_claims[best_e] = int(_claims.get(best_e, 0)) + 1
	return best


# ================= 流程 (10) =================

## 胜负判定: 先胜后负。全灭只数在场单位; 指定单位离场看存活标志 (未现身的预置单位不算离场)
func judge() -> Dictionary:
	var present: Array = units_alive().map(func(u): return u.st)
	var all: Array = bs.units.map(func(u): return u.st)
	var r := Flow.judge(present, bs.st.judge["win"], bs.st.judge["lose"], all)
	return {"result": r.result, "event": int(r.event)}


## 行动后命中的剧情地图事件; path 含起点。无则 {}
func map_event_hit(u: BattleUnit, path: Array, map_events: Dictionary) -> Dictionary:
	var at := func(c: Vector2i) -> Dictionary:
		return map_events.get(int(bs.st.cell(c.x, c.y).get("event", -1)), {})
	return Flow.map_event_hit(at, path, u.st, not u.controllable)


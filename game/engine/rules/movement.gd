# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 移动点、地形消耗、可达范围、ZOC、爆發。

const U = preload("res://engine/rules/unit_state.gd")
const Stats = preload("res://engine/rules/stats.gd")

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


## 本阶段移动上限
##   m = move + Avg/25; 速敏 ×1.5 (_ftol); 地縛 m = 1; cap = m + 爆發保留点
##   速敏先乘后加, 保留点不乘
static func move_cap(ctx, u) -> int:
	var p = ctx.params
	var m: int = Stats.mov_base(ctx, u)
	var r: int = u.burst_reserve
	if u.has_status(U.ST_HASTE):
		if p.haste_before_reserve:
			m = m * p.haste_move_num / p.haste_move_den
		else:
			m = (m + r) * p.haste_move_num / p.haste_move_den
			r = 0
	if u.has_status(U.ST_BIND):
		m = p.bind_move
	if p.test_move_bonus > 0 and u.side == 0:  # 仅测试 --god (缺省 0): 代打机器人只会走向最近的敌人, 限时关里常差一两个回合赶不到
		m += p.test_move_bonus
	return m + r


## 本阵营阶段开始: 当前移动点 = 上限, 清行动标志
static func begin_phase(ctx, u) -> void:
	u.move_cap = move_cap(ctx, u)
	u.move_left = u.move_cap
	u.moved = false
	u.acted = false
	u.ai_passed = false
	u.burst_fresh = false


## 地形单格消耗 TER_EFF[move_type][class]
static func cell_cost(ctx, board, u, c: Vector2i) -> int:
	return ctx.params.terrain_move_cost(u.move_type, board.terrain_class(c))


## ZOC 格 = 敌对单位上下左右 4 格 高; 飞行无例外, 不加消耗
static func in_zoc(board, u, c: Vector2i) -> bool:
	for o in board.units:
		if o.alive and o.side != u.side and absi(o.x - c.x) + absi(o.y - c.y) == 1:
			return true
	return false


## 可达搜索 (Dijkstra)。返回 {cost: {cell: 累计消耗}, prev: {cell: 上一格}, stop: [可停留格, 按确定顺序]}
##   进入格代价 = TER_EFF; 累计 <= 移动点即可到达
##   敌对单位格: 不可进入/穿过; 同阵营单位格: 可穿过、不可停留 (穿过 高, 不可停 中)
##   进入 ZOC 格后不再向外扩展 高; 起点在 ZOC 内可离开
##   幻影 (0x800): 无视单位阻挡与 ZOC
static func search(ctx, board, u, points: int = -1, ignore_units: bool = false) -> Dictionary:
	var p = ctx.params
	if points < 0:
		points = u.move_left
	var start: Vector2i = u.pos()
	var phantom: bool = u.has_status(U.ST_PHANTOM) or ignore_units
	var cost := {start: 0}
	var prev := {}
	var done := {}
	var order := []
	var open := [start]
	# 本次搜索内单位不动: 一次性建占位表和敌方 ZOC 格集合 (原先每格都线性扫全部单位)
	var occ := {}
	var zoc := {}
	for o in board.units:
		if not o.alive:
			continue
		var oc := Vector2i(o.x, o.y)
		if not occ.has(oc):
			occ[oc] = o
		if o.side != u.side:
			for dv in DIRS:
				zoc[oc + dv] = true
	while not open.is_empty():
		# 取累计消耗最小者 (同值取先入队的, 保证确定性)
		var bi := 0
		for i in range(1, open.size()):
			if cost[open[i]] < cost[open[bi]]:
				bi = i
		var c: Vector2i = open[bi]
		open.remove_at(bi)
		if done.has(c):
			continue
		done[c] = true
		order.append(c)
		# ZOC: 进入后停止 (起点按 zoc_start_free)
		if p.zoc_enabled and not phantom and zoc.has(c):
			if c != start or not p.zoc_start_free:
				continue
		for dv in DIRS:
			var n: Vector2i = c + dv
			if not board.in_bounds(n) or done.has(n):
				continue
			var step: int = cell_cost(ctx, board, u, n)
			if step >= p.impassable_cost:
				continue
			if not phantom:
				var o = occ.get(n)
				if o != null and o != u and o.side != u.side:
					continue
			var nc: int = cost[c] + step
			if nc > points:
				continue
			if not cost.has(n) or nc < cost[n]:
				cost[n] = nc
				prev[n] = c
				open.append(n)
	var stop := []
	for c in order:
		var o = occ.get(c)
		if o == null or o == u or ignore_units:
			stop.append(c)
	return {"cost": cost, "prev": prev, "stop": stop}


## 可停留格 -> 累计消耗 (含原地)
static func reachable(ctx, board, u, points: int = -1) -> Dictionary:
	var s := search(ctx, board, u, points)
	var out := {}
	for c in s.stop:
		out[c] = s.cost[c]
	return out


static func path_to(search_result: Dictionary, goal: Vector2i) -> Array:
	var path := []
	if not search_result.cost.has(goal):
		return path
	var c := goal
	path.append(c)
	while search_result.prev.has(c):
		c = search_result.prev[c]
		path.push_front(c)
	return path


## 原版字段换算: 字段 (当前移动点, 不含保留点) = move_left - burst_reserve; 字段 = move_cap
static func cur_points(u) -> int:
	return u.move_left - u.burst_reserve


## 消耗移动点: 先扣爆發保留点, 不够再扣 字段
static func spend(u, amount: int) -> void:
	var from_reserve: int = mini(u.burst_reserve, amount)
	u.burst_reserve -= from_reserve
	u.move_left = maxi(0, u.move_left - amount)


## 移动到 cell (消耗 = 搜索得到的累计值)
static func move_to(ctx, board, u, cell: Vector2i) -> bool:
	var r := reachable(ctx, board, u)
	if not r.has(cell):
		return false
	if cell != u.pos():
		spend(u, r[cell])
		u.set_pos(cell)
		u.moved = true
	return true


## 爆發可用: 菜单条件 字段 + 字段 == 字段, 即本阶段一格都没移动过;
## 带保留点、未移动时同样可选
static func can_burst(ctx, u) -> bool:
	if u.acted or u.moved:
		return false
	return u.move_left == u.move_cap


## 爆發: 字段 = 字段; 字段 = 0; 行动立即结束。
## 新保留点 = 当前移动点 (不含旧保留点), 旧保留点丢弃 —— 连续爆發不累积 23/23/46 → 再爆發仍 23
static func burst(ctx, u) -> bool:
	if not can_burst(ctx, u):
		return false
	if ctx.params.burst_accumulate:
		u.burst_reserve = u.move_left          # 魔改: 累积
	else:
		u.burst_reserve = cur_points(u)
	u.move_left = u.burst_reserve
	u.burst_fresh = true
	u.acted = true
	return true


## 行动结束 (攻击、施法、道具、待機都算): 字段 清 0, 字段 清 0;
## 非本阶段爆發的保留点清 0
static func end_action(u) -> void:
	u.acted = true
	u.extra_action = false
	if not u.burst_fresh:
		u.burst_reserve = 0
	u.move_left = u.burst_reserve


## 能否开始一次行动 (被选中后确认移动格、打开行动菜单): 未行动、能动 (无麻痺/冰結)、
## 当前移动点 > 0 —— 移动点为 0 时连原地格都不能确认 返召之咒后移动点 0 无法再行动
static func can_start_action(u) -> bool:
	if u.acted or not u.alive:
		return false
	if u.has_status(U.ST_PARALYZE) or u.has_status(U.ST_FREEZE):
		return false
	return u.move_left > 0

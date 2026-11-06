# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 测试: 全技能大乱斗 (--brawl)。测试回合我方阶段开始时: 敌我体力/术力拉满、敌人集中到我方周围, 然后按清单逐个技能走真实施放流程 (BattleActions.cast,
## 演出/近景/结算/经验/升级都照常), 施放者借用「使用该技能的精灵」的演出; 落点自动挑: 敌方技能 = 射程内覆盖敌人最多的格, 我方技能 = 覆盖队友最多的格,
## 召唤 = 射程内可召唤的空格; 射程内没有目标就把施放者挪到目标旁边再挑。每招前后打一行 BRAWL 日志 (帧号 / 施放者 / 落点 / 每个受影响单位体力术力状态 R,K 的变化),
## 录像后期按帧号叠字幕 (仓库外的开发脚本)。放完交回正常流程 (配 --autoplay 让双方 AI 接着打)。
## 参数 (从 DebugArgs.current().raw 取原样参数自己解析):
##   --brawl                       开启
##   --brawl-skills=a-b|a,b,...    只放这些技能号 (缺省全部)
##   --brawl-owners=技能:精灵,...  施放者借用的精灵 (缺省用施放者自己的)
##   --brawl-hp=N                  敌我体力上限与当前值 (缺省 30000, 免得中途打死; 0 = 不改)
##   --brawl-cell=技能:x;y,...      指定这些技能的落点 (与原版录像对照时用同一落点)
##   --brawl-no-gather             不把敌人集中过来 (保持关卡原始站位, 对照用)
##   --brawl-tail=N                放完后再让双方照常打 N 帧 (配 --autoplay), 然后退出 (录像用; 缺省不退出)

const SkillsR = preload("res://engine/rules/skills.gd")


static func args() -> Dictionary:
	return parse(DebugArgs.current().raw)


static func parse(argv) -> Dictionary:
	var out := {}
	for a in argv:
		if a == "--brawl":
			out["on"] = true
		elif a.begins_with("--brawl-skills="):
			var ids: Array = []
			for part in a.substr(15).split(","):
				if "-" in part:
					for i in range(int(part.get_slice("-", 0)), int(part.get_slice("-", 1)) + 1):
						ids.append(i)
				elif part != "":
					ids.append(int(part))
			out["skills"] = ids
		elif a.begins_with("--brawl-owners="):
			var m := {}
			for kv in a.substr(15).split(","):
				if ":" in kv:
					m[int(kv.get_slice(":", 0))] = int(kv.get_slice(":", 1))
			out["owners"] = m
		elif a.begins_with("--brawl-hp="):
			out["hp"] = int(a.substr(11))
		elif a.begins_with("--brawl-cell="):
			var cm := {}
			for kv in a.substr(13).split(","):
				if ":" in kv and ";" in kv:
					var xy: PackedStringArray = kv.get_slice(":", 1).split(";")
					cm[int(kv.get_slice(":", 0))] = Vector2i(int(xy[0]), int(xy[1]))
			out["cells"] = cm
		elif a == "--brawl-no-gather":
			out["no_gather"] = true
		elif a.begins_with("--brawl-tail="):
			out["tail"] = int(a.substr(13))
	return out


## 测试回合我方阶段: 开启了就跑完整场大乱斗, 返回 true 表示已处理 (之后照常进入我方操作 / --autoplay)
static func run(flow, mine: Array) -> bool:
	var a := args()
	if not a.get("on", false) or flow.bs.turn != flow.test_turn or mine.is_empty():
		return false
	var hp := int(a.get("hp", 30000))
	var everyone: Array = flow.rules.units_alive()
	for u in everyone:
		if hp > 0:
			u.hp_max = hp
			u.hp = hp
		u.mp_max = maxi(u.mp_max, 999)
		u.mp = u.mp_max
	if not a.get("no_gather", false):
		_gather(flow, mine)
	var ids: Array = Array(a.get("skills", range(256))).filter(func(i): return not flow.rules.skill(int(i)).is_empty())   # 缺省: 全部
	var owners: Dictionary = a.get("owners", {})
	print("BRAWL 开始 帧%d 我方 %d 人 敌方 %d 人 技能 %d 个" % [RegressLog.log_frame, mine.size(), everyone.size() - mine.size(), ids.size()])
	var n := 0
	for sid in ids:
		n += 1
		await _one(flow, mine, int(sid), owners, n, ids.size(), a.get("cells", {}))
	print("BRAWL 结束 帧%d" % RegressLog.log_frame)
	if a.has("tail"):
		var tree: SceneTree = flow.bs.get_tree()
		tree.create_timer(int(a["tail"]) * BattleUnit.TICK).timeout.connect(func():
			print("BRAWL 收尾退出 帧%d" % RegressLog.log_frame)
			tree.quit())
	return false


## 敌人集中到我方队长周围 (由近到远找空格; 只挪位置, 不看地形, 只为同框)
static func _gather(flow, mine: Array) -> void:
	var c0 := Vector2i(mine[0].cx, mine[0].cy)
	var board = flow.rules.board
	var ring: Array = []
	for r in range(2, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r:
					ring.append(c0 + Vector2i(dx, dy))
	for u in flow.rules.units_alive():
		if u.controllable or not u.shown:
			continue
		for c in ring:
			if board.in_bounds(c) and flow.rules.unit_at(c) == null:
				u.set_cell(c.x, c.y)
				ring.erase(c)
				break
	flow.rules.sync()


static func _side_ok(sk: Dictionary, caster, t) -> bool:
	return (t.st.side != caster.st.side) if int(sk.get("target", 1)) == 1 else (t.st.side == caster.st.side)


## 射程内最好的落点 (影响目标最多; 召唤 = 第一个可召唤空格); 没有返回 null
static func _best_cell(flow, u, sk: Dictionary):
	var cells: Array = flow.rules.cast_cells(u, sk)
	if cells.is_empty():
		return null
	if SkillsR.is_summon(sk):
		return cells[0]
	var best = null
	var best_n := -1
	for c in cells:
		var n: int = flow.rules.affected(u, sk, c).filter(func(t): return _side_ok(sk, u, t)).size()
		if n > best_n:
			best_n = n
			best = c
	return best


## 射程内没有目标: 把施放者挪到最近的合法目标旁边 (距离取射程下限, 至少 1; 自身技能就站原地)
static func _move_into_range(flow, u, sk: Dictionary) -> void:
	var rmin := maxi(1, int(sk.get("range", {}).get("min", 0)))
	var rmax := maxi(rmin, int(sk.get("range", {}).get("max", 0)))
	var targets: Array = flow.rules.units_alive().filter(func(t): return t != u and _side_ok(sk, u, t))
	targets.sort_custom(func(p, q): return absi(p.cx - u.cx) + absi(p.cy - u.cy) < absi(q.cx - u.cx) + absi(q.cy - u.cy))
	var home := Vector2i(u.cx, u.cy)
	for t in targets:
		for r in range(rmin, rmax + 1):   # 距目标 r 的整个菱形圈都试 (固定射程 3/4 的弹类, 正上下左右常被围住)
			for dx in range(-r, r + 1):
				for sy in [-1, 1]:
					var c: Vector2i = Vector2i(t.cx, t.cy) + Vector2i(dx, sy * (r - absi(dx)))
					if flow.rules.board.in_bounds(c) and flow.rules.unit_at(c, u) == null:
						u.set_cell(c.x, c.y)
						flow.rules.sync()
						if _best_cell(flow, u, sk) != null:
							return
	u.set_cell(home.x, home.y)
	flow.rules.sync()


## 施放者: 我方有人会这招 / 精灵就是我方某人 → 那个队员; 否则 (妖怪专属技能) 由一个敌人借精灵来放、打向我方 ——
## 自爆这类施放者自己会死的技能也就不会让主角阵亡判负
static func _caster(flow, mine: Array, sid: int, spr: int):
	for m in mine:
		if m.alive and sid in m.st.skills:
			return m
	for m in mine:
		if m.alive and spr >= 0 and int(m.info.get("sprite", -1)) == spr:
			return m
	if spr < 0:
		return mine[0] if mine[0].alive else null
	for o in flow.rules.units_alive():
		if not o.controllable and o.shown and not o.summoned:
			return o
	return null


static func _snap(flow) -> Dictionary:
	var d := {}
	for o in flow.bs.units:
		if o.shown or o.alive:
			d[o] = [o.alive, o.hp, o.mp, o.st.status, o.st.status_r.duplicate(), o.st.status_k.duplicate(), o.st.lv, o.st.xp]
	return d


static func _one(flow, mine: Array, sid: int, owners: Dictionary, n: int, total: int, forced: Dictionary = {}) -> void:
	var sk: Dictionary = flow.rules.skill(sid)
	if sk.is_empty():
		return
	var spr := int(owners.get(sid, -1))
	var u = _caster(flow, mine, sid, spr)
	if u == null:
		return
	var keep_sprite := int(u.info.get("sprite", 0))
	if spr >= 0 and spr != keep_sprite:
		u.override_sprite(spr)
	u.mp = u.mp_max + int(sk.get("mp_cost", 0))
	u.st.moved = false
	u.st.acted = false
	u.st.move_left = maxi(u.st.move_left, int(sk.get("move_cost", 0)))
	var c = forced.get(sid, _best_cell(flow, u, sk))
	if c == null and int(sk.get("range", {}).get("max", 0)) == 0 and not SkillsR.is_summon(sk):
		c = Vector2i(u.cx, u.cy)   # 射程 0 = 对自己脚下放 (天魔护铠: 目标类型写敌方, 正常规则找不到合法目标, 原版也只是无演出结束)
	if c == null and not SkillsR.is_summon(sk):
		_move_into_range(flow, u, sk)
		c = _best_cell(flow, u, sk)
	if c == null:
		var why := "没有可用落点"
		var rg: Dictionary = sk.get("range", {})
		if SkillsR.is_summon(sk):
			why += ", 本关没有预置召唤物"
		elif int(rg.get("min", 0)) == int(rg.get("max", 0)) and int(rg.get("max", 0)) > 0:
			why += ", 射程下限 = 上限, 原版射程格集合也为空, 原版从不施放 (09 §AI / H23)"
		print("BRAWL 跳过 %d %s (%s)" % [sid, sk["name"], why])
		if spr >= 0 and spr != keep_sprite:
			u.override_sprite(keep_sprite)
		return
	var affected: Array = flow.rules.affected(u, sk, c)
	if int(sk.get("result_type", -1)) == SkillsR.RT_HEAL:   # 治疗: 先把目标体力降到 6 成, 才看得出回了多少
		for t in affected:
			t.hp = t.hp_max * 6 / 10
	var tgt_names: Array = affected.map(func(t): return t.name_text)
	print("BRAWL 施放 帧%d [%d/%d] #%d %s | 施放者 %s(精灵%d) 智%d 运%d | 落点 (%d,%d) | 目标 %s" % [RegressLog.log_frame, n, total, sid, sk["name"], u.name_text, int(u.info.get("sprite", 0)),
		u.st.get_stat("int"), u.st.get_stat("luk"), c.x, c.y, "、".join(tgt_names) if not tgt_names.is_empty() else "-"])
	var before := _snap(flow)
	var rng0: int = flow.rules.ctx.rng.get_state()
	await flow.actions.cast(u, sk, c)
	for o in before:
		var b: Array = before[o]
		var now := [o.alive, o.hp, o.mp, o.st.status, o.st.status_r, o.st.status_k, o.st.lv, o.st.xp]
		if str(b) != str(now):
			print("BRAWL   %s 体力 %d->%d 术力 %d->%d 状态 0x%x->0x%x R%s K%s 等级 %d->%d 经验 %d->%d%s" % [o.name_text, b[1], o.hp, b[2], o.mp, b[3], o.st.status,
				str(o.st.status_r), str(o.st.status_k), b[6], o.st.lv, b[7], o.st.xp, "" if o.alive else " 阵亡"])
	print("BRAWL   随机数 %d -> %d" % [rng0, flow.rules.ctx.rng.get_state()])
	if spr >= 0 and spr != keep_sprite and is_instance_valid(u):
		u.override_sprite(keep_sprite)
	for o in flow.rules.units_alive():   # 别让有人死掉退场 (下一招还要目标): 体力补回
		o.hp = maxi(o.hp, o.hp_max / 2)

# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 回合流程与胜负判定。只给规则判断, 不驱动演出与剧情 VM。

const U = preload("res://engine/rules/unit_state.gd")

## 一个回合的步骤 (高)。tick = 结算状态 (Status.units_to_tick 的 phase), tevt = TEVT type, act = 行动阵营
const ROUND_STEPS := [
	{"step": "banner", "side": 0},          # 1 我方横幅「陽之陣」
	{"step": "tick", "phase": "ally"},      # 2 结算友军 NPC
	{"step": "tevt", "type": 0},            # 3
	{"step": "act", "who": "ally_npc"},     # 4 友军 NPC 行动 (AI)
	{"step": "tick", "phase": "player"},    # 5 结算全部阵营 0 (含友军 NPC → 一轮两次)
	{"step": "tevt", "type": 1},            # 6
	{"step": "act", "who": "player"},       # 7 玩家操作
	{"step": "banner", "side": 1},          # 8 敌方横幅「陰之陣」
	{"step": "tick", "phase": "enemy"},     # 9
	{"step": "tevt", "type": 2},            # 10
	{"step": "act", "who": "enemy"},        # 11 敌方行动 (MAN 下标顺序)
	{"step": "turn_end"},                   # 12 turn += 1; turn >= 100 → GAME OVER
]

## 胜负判定的触发点
const TRIGGER_ACTION := "action"          # 攻击/法术 (含治疗术) 结算后的死亡处理 —— 总是判定
const TRIGGER_STATUS_DEATH := "status_death"  # 中毒等致死
const TRIGGER_TEVT := "tevt"              # TEVT 之后: 不判
const TRIGGER_MAP_EVENT := "map_event"    # 地图事件之后: 不判
const TRIGGER_OTHER := "other"            # 装备/丢弃/待機/回合推进: 不判


## TEVT: 按文件顺序只执行第一条匹配 (type 相同且 turn == -1 或 == 当前回合); 第 1 回合同样检查
## records: [{turn, type, event}]; 返回匹配记录的下标, 无则 -1
static func tevt_match(records: Array, type: int, turn: int) -> int:
	for i in records.size():
		var r: Dictionary = records[i]
		if int(r.get("type", -1)) == type and (int(r.get("turn", 0)) == -1 or int(r.get("turn", 0)) == turn):
			return i
	return -1


## 回合推进: 返回 {turn, game_over}
static func end_turn(ctx, turn: int) -> Dictionary:
	var t := turn + 1
	return {"turn": t, "game_over": t >= ctx.params.turn_limit}


## 本次是否要调用 JUDGE
##   action: 总判定 (任何行动结算都会, 连治疗术也算)
##   status_death: 仅当本批死者里有 kill_event ≠ -1
##   tevt / map_event / other: 不判
static func should_judge(ctx, trigger: String, dead: Array = []) -> bool:
	match trigger:
		TRIGGER_ACTION:
			return true
		TRIGGER_STATUS_DEATH:
			if not ctx.params.status_death_judge_needs_event:
				return true
			for u in dead:
				if int(u.kill_event) != -1:
					return true
			return false
	return false


## 单个条件
##   type 1 全灭: 在场 且 阵营 1 且 字段 == 0 的单位 (跳过下标 == id 的那个) 数量为 0
##   type 2 指定单位离场: 下标 id 的单位不在场
static func cond_met(units: Array, cond: Dictionary) -> bool:
	var id: int = int(cond.get("id", -1))
	match int(cond.get("type", 0)):
		1:
			for u in units:
				if u.alive and u.side == 1 and not u.annihilation_exempt and u.uid != id:
					return false
			return true
		2:
			for u in units:
				if u.uid == id:
					return not u.alive
			return true
	return false


## JUDGE: 先遍历胜利表, 第一个成立 → 胜; 否则遍历失败表 (先胜后负)
## win / lose: [{type, id, event}], type 0 = 表结束。返回 {result: "win"/"lose"/"", index, event}
##   units = 「在场」单位 (type 1 全灭用); all = 全部单位 (type 2 指定单位离场用, 不看是否现身), 缺省同 units
static func judge(units: Array, win: Array, lose: Array, all: Variant = null) -> Dictionary:
	var every: Array = units if all == null else all
	for side in [["win", win], ["lose", lose]]:
		var list: Array = side[1]
		for i in list.size():
			var c: Dictionary = list[i]
			if int(c.get("type", 0)) == 0:  # 表结束: 遇类型 0 就返回「不成立」, 后面还有条目也不再看
				break
			if cond_met(units if int(c.get("type", 0)) == 1 else every, c):
				return {"result": side[0], "index": i, "event": c.get("event", -1)}
	return {"result": "", "index": -1, "event": -1}


## 同一批死者的 kill_event 去重 (同号只执行一次, 保持首次出现顺序)
static func kill_events(dead: Array) -> Array:
	var out := []
	for u in dead:
		var e: int = int(u.kill_event)
		if e != -1 and not out.has(e):
			out.append(e)
	return out


## 战阵存档: 只能在我方阶段开始、我方尚无人行动时存
static func can_save_battle(units: Array, in_player_phase: bool) -> bool:
	if not in_player_phase:
		return false
	for u in units:
		if u.alive and u.side == 0 and not u.npc_ally and u.acted:
			return false
	return true


## 剧情脚本结束 (END) 后的去向
##   exit_issued: 本次脚本发出过出口指令 (0x03 GAME_OVER / 0x54 回标题 / STAGE_OVER 等) → 照指令走, 这里不管
##   ending_movie_played: 本次脚本播过结局过场 (内容包 manifest.ending_movies; 原版 Movie_13 制作人员名单)
## 原版: 第 31 关悲剧分支播完 Movie 6/9/10/13 + DELAY 1500 后直接 END, 停在黑屏, 战斗在后台空转 (回合照常推进),
## 按键无反应 —— 脚本缺陷。params.fix_ending_return_title (默认 true, 复刻修补) → 返回 "title";
## false = 原版, 返回 "" (什么都不做, 战斗继续)。
static func script_end_exit(ctx, ending_movie_played: bool, exit_issued: bool) -> String:
	if exit_issued or not ending_movie_played:
		return ""
	return "title" if ctx.params.fix_ending_return_title else ""


## 地图事件触发者过滤: parm1 0 任何 / 1 友军 NPC / 2 玩家单位 / 3 敌人; 4~7 同上但只算停留
static func map_event_filter(parm1: int, u) -> bool:
	if parm1 < 0 or parm1 > 7:
		return false
	var who := 3 if u.side == 1 else (1 if u.npc_ally else 2)
	var k := parm1 % 4
	return k == 0 or k == who


## §2.2 行动后检查剧情地图事件, 返回命中的 MEVT 记录 (无则 {})。
##   event_at: Callable(Vector2i) -> Dictionary, 该格的 MEVT 记录 ({type, parm1, parm2, ...}, 无事件 {})
##   path: 本次移动路径, 起点在前、终点在后 (含起点; 未移动 = [起点] 或 [])
##   is_ai: AI 控制 (敌人、友军 NPC)
## 从终点往起点查, 起点不查; 终点 parm1 0~7 都可命中, 途经格只有 0~3; 只返回第一个 (离终点最近)。
## 玩家单位没移动: 只查脚下格, 按停留处理。
## AI 单位没移动: 【不检查】: 封寒月转 NPC 时已站在石座 (12,6), AI 4 不移动 →
##   mevt1 永不触发, 第 20 关剧情卡在 var9 = 1, 她一直是 NPC。不是脚本特判, 照这条通用规则自然重现
static func map_event_hit(event_at: Callable, path: Array, u, is_ai: bool) -> Dictionary:
	var cells: Array = path.duplicate()
	cells.reverse()                       # [终点, ..., 起点]
	if cells.size() <= 1:
		if is_ai:
			return {}
		cells = [cells[0] if cells.size() == 1 else u.pos(), null]   # 原地: 脚下格按终点 (停留)
	for i in cells.size() - 1:            # 起点不查
		var m: Dictionary = event_at.call(cells[i])
		if m.is_empty() or int(m.get("type", -1)) != 0:
			continue
		var p1: int = int(m.get("parm1", -1))
		if map_event_filter(p1, u) and (i == 0 or p1 <= 3):
			return m
	return {}


## 事件来源: 引擎只经 TEVT、JUDGE (胜/负表)、
## kill_event、MEVT (type 0 的 parm2) 四处执行事件; 脚本没有调用其他事件的指令。事件 0 = 开场前置 (引擎直接执行)。
## 不在返回集合里的事件是死代码 —— 例: 第 3 关 e5 (第二波 u14~16、u21~24) 永不出现
## stage: stage.json ({turn_events, judge:{win,lose}, map_events}); units: units.json ({kill_event})
static func event_sources(stage: Dictionary, units: Array) -> Array:
	var out := []
	var add := func(e):
		var v := int(e)
		if v >= 0 and not out.has(v):
			out.append(v)
	for t in stage.get("turn_events", []):
		add.call(t.get("event", -1))
	var j: Dictionary = stage.get("judge", {})
	for k in ["win", "lose"]:
		for r in j.get(k, []):
			add.call(r.get("event", -1))
	for u in units:
		add.call(u.get("kill_event", -1))
	for m in stage.get("map_events", []):
		if int(m.get("type", -1)) == 0:
			add.call(m.get("event", -1))
	out.sort()
	return out

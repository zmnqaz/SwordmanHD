# SPDX-License-Identifier: GPL-3.0-only
class_name BattleFlow
extends Node
## 回合流程 (机制): 阶段结算、回合事件、AI 行动、我方操作阶段、地图事件与宝物、死亡处理与胜负判定。
## 回合: [陽之陣横幅] -> 结算友军 NPC -> TEVT 0 -> 友军 NPC 行动 -> 结算阵营 0 -> TEVT 1 -> 我方操作
##            -> 陰之陣横幅 -> 结算敌方 -> TEVT 2 -> 敌方行动 -> 回合数+1 (满 100 回合 GAME OVER)。
##   第 1 回合不出陽之陣横幅 (原版逐帧截图: 过场 -> 对白 -> 标题卡 -> 夜魑入场 -> 开战); 敌方横幅从第 1 回合起照常。
## 我方操作阶段交给 BattleInput (玩家操作状态机); 代打 (--autoplay) 时由 AI 行动。
## 攻击/法术结算后: 死亡处理 (掉落 -> kill_event 去重 -> 胜负判定)。TEVT 与地图事件之后不判胜负。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

const Flow = preload("res://engine/rules/flow.gd")
const UnitState = preload("res://engine/rules/unit_state.gd")

var bs
var rules: BattleRules
var view: BattleView
var actions: BattleActions
var input  # BattleInput
var over := false
var stats := BattleStats.new()   # 每关统计 (测试用, 默认关)
var map_events := {}      # 事件编号 -> MEVT (类型 0 剧情事件 / 1 宝物)
var _treasures := {}      # 事件编号 -> [宝箱动画] (共用一条 MEVT 的每个格子各一个)
var _hidden_icons := {}   # 事件编号 -> [隐藏宝箱的半透明图标]: 只在设定「隐藏宝箱」开着时有, 与正常宝物分开管 (开关即时增删)
var _hidden_shown := false
var _killers := {}        # 本批死亡: 死者 -> 击杀者 (中毒等无击杀者)
var _judge_event := -1
var test_turn := 1        # 测试钩子 (--unit/--hp/--cast…) 生效的回合; --gcf 读入存档时 = 存档回合


func _init(scene, battle_rules: BattleRules, battle_view: BattleView, battle_actions: BattleActions) -> void:
	bs = scene
	rules = battle_rules
	view = battle_view
	actions = battle_actions


# ================= 回合流程 =================

## resume: 戰陣重現时的控制器快照 (见 snapshot), 直接从我方操作阶段继续
## 战阵存录里只记「还没触发」的地图事件; 读档时现有事件里不在其中的就是存档前已触发的。
## 存录是 JSON, 数字读回是 float (str(1.0) != "1"), 必须按整数比 (以前按字符串比, 读档后所有宝箱/地图事件都被当作已触发而消失)
static func events_taken_since(current: Array, saved_remaining: Array) -> Array:
	var left := saved_remaining.map(func(x): return int(x))
	return current.filter(func(e): return not int(e) in left)


func run(resume := {}) -> void:
	init_map_events()
	stats.begin(bs, rules)
	if not resume.is_empty():
		for e in events_taken_since(map_events.keys(), resume["map_events"]):
			take_map_event(e)
		for u in bs.units:
			u.acted_fx = u.controllable and u.acted  # 从我方操作阶段继续: 只有我方已行动的显示灰
			shade(u)
	else:
		for v in rules.ctx.params.summon_flag_vars:  # 每关开始召唤标志清 0
			gc.state.set_data(v, 0)
	while not over:
		if resume.is_empty():
			if bs.turn > 1:  # 第 1 回合不出我方横幅
				await view.banner(0, bs.turn)
			await _tick_phase("ally")
			if over:
				break
			await _turn_event(0)
			if over:
				break
			await _ai_phase(func(u): return u.st.side == 0 and u.st.npc_ally)
			_end_phase(func(u): return u.st.side == 0 and u.st.npc_ally)
			if over:
				break
			await _tick_phase("player")
			if over:
				break
			await _turn_event(1)
			if over:
				break
		resume = {}
		await _player_phase()
		_end_phase(func(u): return u.st.side == 0 and not u.st.npc_ally)
		if over:
			break
		await view.banner(1, bs.turn)
		await _tick_phase("enemy")
		if over:
			break
		await _turn_event(2)
		if over:
			break
		await _ai_phase(func(u): return u.st.side == 1)
		_end_phase(func(u): return u.st.side == 1)
		if over:
			break
		var te := Flow.end_turn(rules.ctx, bs.turn)
		RegressLog.checkpoint("turn", {"stage": bs.st.n, "turn": bs.turn})
		var hp_sum := 0
		for u in rules.units_alive():
			hp_sum += u.hp
		PlayLog.checkpoint("turn%d" % bs.turn, int(bs.st.n) * 100000 + hp_sum)   # 通关录像检查点 (关号 + 全场血量合计), 回放对不上时报警
		bs.turn = te.turn
		var foes := rules.units_alive().filter(func(u): return u.camp == 1)
		print("第 %d 关 第 %d 回合 敌方存活 %d %s" % [bs.st.n, bs.turn, foes.size(),
			foes.slice(0, 4).map(func(u): return "%s(%d,%d)ai%d" % [u.name_text, u.cx, u.cy, u.ai])])
		if bs.turn % 10 == 0:  # 长时间没结束: 打出我方位置帮助排查
			print("  我方: ", rules.units_alive().filter(func(u): return u.camp != 1).map(func(u): return "%s(%d,%d)ai%d" % [u.name_text, u.cx, u.cy, u.ai]))
		if te.game_over:  # 第 100 回合 GAME OVER (消息 0x516)
			print("回合数达到上限 %d, 游戏结束" % bs.turn)
			over = true
			bs.vm.ended = true
			gc.flow.game_over.call_deferred()
	RegressLog.checkpoint("battle_end", {"stage": bs.st.n, "turn": bs.turn})
	stats.report()
	PlayLog.stage_end(int(bs.st.n), stats.result != "lose")   # 通关录像: 胜利则导出这一幕的单幕战斗录像 (读档放弃的段已剪掉)
	print("战斗结束")


## 阶段结束: 本阵营存活单位一律置已行动 (字段=0, 没动过的 AI 也算),
## 并关掉灰色外观 —— 原版友军在我方阶段、我方在敌方阶段都不显示灰 (差异)
func _end_phase(filter: Callable) -> void:
	for u in rules.units_alive().filter(filter):
		u.st.acted = true
		u.acted_fx = false
		shade(u)


## 阶段开始: 结算状态 (中毒、R-=K), 再给本阶段行动的单位重置移动点。
## phase: ally 友军 NPC / player 阵营 0 (友军 NPC 再结算一次) / enemy
func _tick_phase(phase: String) -> void:
	for u in rules.units_to_tick(phase):
		var r := rules.tick(u)
		if int(r.poison_damage) > 0 and u.shown:
			await _poison_fx(u, int(r.poison_damage))
		if r.died:   # 被毒死: 数字弹完就死 (淡出、掉物、kill_event、胜负), 中毒位保留、不演状态到期 (实测)
			await resolve_deaths(Flow.TRIGGER_STATUS_DEATH)
			if over:
				return
		elif not r.expired.is_empty() and u.shown:
			var mask := 0
			for b in r.expired:
				mask |= int(b)
			await release_fx(u, mask)   # 状态到期: 镜头跟到单位, 身上放一段结果动画, 播完状态外观才消失, 弹框说明
		u._tint()
	for u in bs.units:
		if not u.alive:
			continue
		var mine: bool = u.st.side == 1 if phase == "enemy" else (u.st.side == 0 and u.st.npc_ally == (phase == "ally"))
		if mine:
			rules.begin_phase(u)
			shade(u)


## 中毒扣血的演出 (原版阶段开始状态结算 状态 4→5→6, 实测): 镜头跟随单位 -> MAN_RES 帧 2~9 命中动画 ->
## 动画一结束红色数字弹出 (= HPmax/5, 与伤害同一套), 等数字弹完 (约 1.2 秒) 才轮到下一步
func _poison_fx(u: BattleUnit, dmg: int) -> void:
	var seg := UnitStatusFx.poison_range()
	await bs.follow_cell(u.cx, u.cy)
	await view.res_anim(u, ThemeAssets.p("battle.result_fx"), seg[0], seg[1])
	view.digits(u, dmg, false)
	await SceneGuard.wait(self, DamageDigits.seconds())


## 状态解除的演出 (原版阶段开始状态结算 状态 4→9→10→11, 实测 2026-10-17 差异):
## 镜头跟到单位 -> 单位身上放 MAN_RES 一段 (每帧固定 0.12 秒; 正面 60~80 / 负面 81~98 / 冰結被打碎 32~45) -> 播完状态外观才消失,
## 同一刻弹出对话框「XX的状态解除了.」(一行一个状态, 同一单位同时解除的合进一个框, 末页自动停 2 秒)。
## 调用时数据里的状态位已清, 单位的外观 (Man_eff 叠层/着色) 还没刷新, 所以动画期间状态外观照旧。区间选法见 UnitStatusFx.release_range
func release_fx(u: BattleUnit, mask: int, frames := []) -> void:
	var seg: Array = frames if not frames.is_empty() else UnitStatusFx.release_range(mask)
	await bs.follow_cell(u.cx, u.cy)
	var tick := int(UiLayout.val("map.unit.expire_fx", "tick", 0))
	await view.res_anim(u, ThemeAssets.p("battle.result_fx"), seg[0], seg[1], true, tick)
	u._tint()
	var lines: Array = []
	for b in UnitState.STATUS_NAMES:   # 位从小到大
		if (mask & int(b)) != 0:
			lines.append(UiStrings.t("battle.release.%d" % int(b)))
	await bs.msgbox.show_text(-1, 0, -1, "\n".join(lines), UiLayout.el("dialog.release"))


## 本次行动里被打破的状态 (冰結受击解除, 单位的 released 位) 逐个演出; 已死的单位不演 (原版只在近景回到地图后演, 之后才判死亡)
func flush_releases() -> void:
	for u in bs.units:
		var m: int = u.st.released
		if m == 0:
			continue
		u.st.released = 0
		if u.alive and u.shown:
			await release_fx(u, m, UnitStatusFx.freeze_break_range())


## 回合事件 (TEVT): 只执行第一条匹配 (type 相同, turn 为当前回合或 -1); 第 1 回合同样检查; 之后不判胜负
func _turn_event(type: int) -> void:
	var i := Flow.tevt_match(bs.st.tevt, type, bs.turn)
	if i < 0:
		return
	await bs.vm.run(int(bs.st.tevt[i]["event"]))
	if bs.vm.ended:
		over = true


## 对照: 我方操作阶段开始时 (本回合 TEVT 0/1、友军阶段之后) 的全体单位状态, 与原版「我方阶段待命时」的单位表采样逐项比 (battlework/ai2)
func _trace_state() -> void:
	if gc.debug.ai_trace and bs.turn > test_turn:
		print("AI阶段末 回合%d rng=%d: %s" % [bs.turn, rules.ctx.rng.get_state(), " ".join(bs.units.map(func(o): return "%d:%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [o.index, o.cx, o.cy, o.hp, 1 if o.alive else 0, o.mp, o.st.status, o.st.ai, o.st.ai_target[0], o.st.ai_target[1], 1 if o.st.npc_ally else 0]))])


func _player_phase() -> void:
	_trace_state()
	var mine: Array = rules.units_alive().filter(func(u): return u.controllable)
	if mine.is_empty():
		return
	if await BattleTestHooks.player_phase(self, mine):   # 测试开关 (--cast/--warp/--hp-unit/--idle-player…, engine/test/battle_test_hooks.gd)
		return
	if gc.autoplay:
		await _ai_phase(func(u): return u.controllable)
		return
	if ready_units().is_empty():
		return
	print("我方回合 第%d回合 帧%d" % [bs.turn, RegressLog.log_frame])
	await input.player_phase()


## 还能行动的玩家单位 (未行动、无麻痺/冰結、移动点 > 0), 按单位编号
func ready_units() -> Array:
	return rules.units_alive().filter(func(u): return u.controllable and rules.can_start_action(u))


## AI 行动 (09): 按 MAN 下标升序; 计划 -> (有行动才) 写变量 102 -> 移动 -> 出手 -> 地图事件 -> 行动结束
func _ai_phase(filter: Callable) -> void:
	var any_acted := false
	for u in rules.units_alive().filter(filter):
		if over:
			return
		if not u.alive or not u.shown or u.acted:
			continue
		var plan := rules.ai_plan(u)
		# 不移动也不出手 = 分发 返回假: 不写变量 102, 不算已行动 (原版第 0 幕友军第 1 回合仍是未行动, 差异)
		if plan.move_to == Vector2i(u.cx, u.cy) and plan.action.is_empty():
			u.st.ai_passed = true   # 轮到过 (对每个轮到的单位清 字段), 返召之咒估价要看
			continue
		any_acted = true
		gc.state.set_data(rules.ctx.params.var_actor, u.index)  # 剧情变量 102 = 当前行动单位, AI 决定行动后写
		bs.show_cursor(u.cx, u.cy)
		await bs.follow_cell(u.cx, u.cy)
		var path: Array = []
		var start := Vector2i(u.cx, u.cy)
		var m: Vector2i = plan.move_to
		if m != Vector2i(u.cx, u.cy):
			path = rules.commit_move(u, m)
			if not path.is_empty():
				u.walk(path, BattleStage.WALK_SPEED)
				await u.move_finished
				bs.show_cursor(u.cx, u.cy)   # 原版光标框随单位到落点 (B4 实录)
		var act: Dictionary = plan.action
		if not act.is_empty() and u.alive:
			match String(act.kind):
				"attack":
					var t: BattleUnit = rules.unit_of(act.target)
					if t and t.alive:
						await actions.attack(u, t)
				"skill":
					await actions.cast(u, rules.skill(int(act.skill)), act.center)
				"item":
					await actions.use_item(u, int(act.item), act.center)
				"burst":   # 聚力: 与玩家菜单「爆發」同一个规则调用
					rules.burst(u)
		rules.end_action(u)
		shade(u)
		if u.alive and not over:
			await after_action(u, path, start)
		RegressLog.checkpoint("act", {"stage": bs.st.n, "turn": bs.turn, "unit": u.index})
		if gc.debug.ai_trace:
			print("AI单位完 #%d rng=%d at=%d,%d hp: %s" % [u.index, rules.ctx.rng.get_state(), u.cx, u.cy, " ".join(bs.units.filter(func(o): return o.alive).map(func(o): return "%d:%d" % [o.index, o.hp]))])
		await SceneGuard.wait(self, 0.15)
	# 光标框留在最后行动的单位上 (原版回合横幅期间仍显示)


## 已行动 / 不能行动的单位画成灰色
func shade(u: BattleUnit) -> void:
	view.shade(u, rules.can_start_action(u))


## 玩家单位行动结束: 移动点清零 (保留点按爆發规则) -> 宝箱与地图事件
func finish_unit_action(u: BattleUnit, path: Array, start := Vector2i(-1, -1)) -> void:
	rules.end_action(u)
	shade(u)
	if u.alive and not over:
		await after_action(u, path, start)
	RegressLog.checkpoint("act", {"stage": bs.st.n, "turn": bs.turn, "unit": u.index})


# ================= 地图事件与宝箱 (MEVT, 12) =================



## 隐藏宝箱: 宝物 (type > 0) 且 show == -1 (原版不画)
static func is_hidden_chest(m: Dictionary) -> bool:
	return int(m["type"]) > 0 and int(m["show"]) == -1


## 宝箱图标: 隐藏宝物 (show == -1) 原版不画; 设定「隐藏宝箱」开着时另画成半透明图标 (refresh_hidden_treasures)
func init_map_events() -> void:
	for i in bs.st.mevt.size():
		if int(bs.st.mevt[i]["type"]) != -1:
			map_events[i] = bs.st.mevt[i]
	for y in bs.st.height:
		for x in bs.st.width:
			var e := int(bs.st.cell(x, y)["event"])
			if map_events.has(e) and int(map_events[e]["type"]) > 0 and int(map_events[e]["show"]) != -1:
				var a := _make_chest_icon(Vector2i(x, y))
				if not _treasures.has(e):
					_treasures[e] = []
				_treasures[e].append(a)
	if not gc.settings_applied.is_connected(refresh_hidden_treasures):
		gc.settings_applied.connect(refresh_hidden_treasures)
	refresh_hidden_treasures()


## 一个宝箱图标 (宝箱 = 地图物件约定)
## red = true: 隐藏宝箱的红色版闪光 (原版宝箱是蓝白闪光, 动画相同只是换红色, 一眼分得出)
func _make_chest_icon(c: Vector2i, red := false) -> Node2D:
	var a := AnimPlayer.new()
	a.recolor_red = red
	a.play_sound = false
	a.position = FxPlace.at_cell(c, "object")
	a.z_index = -1
	bs.units_node.add_child(a)
	a.play(ThemeAssets.p("battle.treasure"))
	return a


## 按设定「隐藏宝箱」增删隐藏宝物的图标 (只影响显示, 不改规则/存档; 设定改动与进战场时调)
func refresh_hidden_treasures() -> void:
	var want := int(gc.settings.get("show_hidden", 0)) == 1
	if want == _hidden_shown:
		return
	_hidden_shown = want
	for e in _hidden_icons:
		for a in _hidden_icons[e]:
			if is_instance_valid(a):
				a.queue_free()
	_hidden_icons.clear()
	if not want:
		return
	var n := 0
	for y in bs.st.height:
		for x in bs.st.width:
			var e := int(bs.st.cell(x, y)["event"])
			if map_events.has(e) and is_hidden_chest(map_events[e]):
				var a := _make_chest_icon(Vector2i(x, y), true)
				if not _hidden_icons.has(e):
					_hidden_icons[e] = []
				_hidden_icons[e].append(a)
				n += 1
	print("隐藏宝箱显示: %d 个图标" % n)


## 行动结束后的宝物与地图事件: path = 本次移动路径 (不含起点), start = 起点。
##   玩家单位: 先拿脚下宝物 (只算停留), 再按路径查剧情事件; 没移动只查脚下 (按停留)
##   AI 单位: 没移动不查; 不拿宝物。路径判定在规则引擎 Flow.map_event_hit
func after_action(u: BattleUnit, path: Array, start := Vector2i(-1, -1)) -> void:
	if u.controllable:
		await _take_treasure(u)
		if over or not u.alive:
			return
	var full: Array = path.duplicate()
	if not full.is_empty():
		full.push_front(start if start.x >= 0 else full[0])
	var m := rules.map_event_hit(u, full, map_events)
	if m.is_empty():
		return
	gc.state.set_data(rules.ctx.params.var_actor, u.index)  # 执行时变量 102 = 触发者
	await bs.vm.run(int(m["parm2"]))
	if bs.vm.ended:
		over = true


## 宝物: 只有玩家单位行动结束时停在格上才拿; 先问「發現了寶箱,是否要開啟它呢?」(带开箱者头像, 默认是),
## 否则宝物保留; 拿到后「得到X.」/「得到金錢N兩.」头像对话 (原版截图), 共用这条 MEVT 的格子一起消失。
## 文本: 内容包 system_text treasure (TREPRO.MSG)
func _take_treasure(u: BattleUnit) -> void:
	var e := int(bs.st.cell(u.cx, u.cy).get("event", -1))
	var m: Dictionary = map_events.get(e, {})
	if m.is_empty() or int(m["type"]) == 0:
		return
	var t := _text("treasure", [["发现了宝箱,是否要开启它呢?", "是,开启发现的宝箱.", "否,不开启这个宝箱."], ["得到{0}.", "得到金钱{0}两."],
		["是否丢弃物品,来存放宝箱的物品?", "是,丢弃物品来存放它.", "否,不开启这个宝箱."]])
	var face := BattleActions.face_of(u)
	if not await view.ui.choice.ask(t[0][0], t[0][1], t[0][2], true, face):
		return
	var msg := ""
	if int(m["item_type"]) == 1:
		# 进开箱者本人 10 格; 满了问是否丢一件来存放, 否 = 不开箱、宝箱留着 (TREPRO.MSG)
		if not await receive_item(u, int(m["item1"]), t[2]):
			return
		msg = String(t[1][0]).replace("{0}", item_name(int(m["item1"])))
	elif int(m["item_type"]) == 2:
		gc.state.gold += int(m["item1"])
		msg = String(t[1][1]).replace("{0}", str(int(m["item1"])))
	stats.treasure(u, e, ("金钱%d两" % int(m["item1"])) if int(m["item_type"]) == 2 else item_name(int(m["item1"])))
	take_map_event(e)
	if msg != "":
		print("宝物: %s %s" % [u.name_text, msg])
		await bs.msgbox.show_text(face, 0, 0, msg)
	if int(m["item_type"]) == 0:
		# 事件宝物 (2026-10-05 原版 造 MEVT 实测: 问「发现了宝箱」→ 是 → 执行 parm2 事件; 宝物同时被消掉, 无得到物品提示)
		gc.state.set_data(rules.ctx.params.var_actor, u.index)
		await bs.vm.run(int(m["parm2"]))
		if bs.vm.ended:
			over = true


## 拿到物品: 放进 u 的 10 格; 满了按 ask = [问句 ({0} = 物品名), 是, 否] 问是否丢一件来存放 (默认否), 是 -> 选一件未装备的丢掉。返回是否放进
func receive_item(u: BattleUnit, id: int, ask: Array) -> bool:
	return await take_item(rules, view.ui, u, id, ask)


## 选 u 的一格 (模态列表): can(i) 决定哪格可选, 取消返回 -1
func pick_slot(u: BattleUnit, can: Callable) -> int:
	return await pick_unit_slot(rules, view.ui, u, can)


## 以上两个的实现 (rules/ui 由参数传入, 不依赖场景, 测试可换替身)
## 物品名 (编号无效时为空串, 不崩; 见 ContentDB.item_at)
static func item_name(id: int) -> String:
	return String(Content.item_at(id)["name"])


static func take_item(rules_, ui, u, id: int, ask: Array) -> bool:
	if rules_.inv_pickup(u, id):
		return true
	var q := String(ask[0]).replace("{0}", item_name(id))
	if not await ui.choice.ask(q, String(ask[1]), String(ask[2]), false, BattleActions.face_of(u)):
		return false
	var k: int = await pick_unit_slot(rules_, ui, u, func(i): return rules_.inv_can_give(u, i))
	if k < 0:
		return false
	rules_.inv_discard(u, k)
	return rules_.inv_pickup(u, id)


static func pick_unit_slot(rules_, ui, u, can: Callable) -> int:
	var ids: Array = u.st.items.duplicate()
	var enabled: Array = []
	for i in ids.size():
		enabled.append(bool(can.call(i)))
	return await ItemPicker.new().run(ui, ids, rules_.inv_equipped(u), enabled)


## 系统文本表 (内容包 text/system.json), 缺了用 fallback
static func _text(table: String, fallback: Array) -> Array:
	var t: Array = Content.system_text(table)
	return t if t.size() >= fallback.size() else fallback


func take_map_event(e) -> void:
	map_events.erase(e)
	if _treasures.has(e):
		for a in _treasures[e]:
			a.queue_free()
		_treasures.erase(e)
	if _hidden_icons.has(e):   # 隐藏宝箱的图标 (设定开着时才有) 随宝物一起消失
		for a in _hidden_icons[e]:
			a.queue_free()
		_hidden_icons.erase(e)


## 剧情扣血: uid < 0 为 0x46 (玩家单位 hp -= hp/3, 最少剩 1); 否则 0x4A (unit_id 相同的我方单位 hp/mp 各 -1/3)
func event_damage(uid: int) -> void:
	var hit := rules.units_alive().filter(func(u): return u.controllable if uid < 0 else (u.camp == 0 and int(u.man["unit_id"]) == uid))
	if hit.is_empty():
		return
	if uid >= 0:
		await bs.follow_cell(hit[0].cx, hit[0].cy)
	for i in hit.size():
		view.res_anim(hit[i], ThemeAssets.p("battle.result_fx"), 2, 10, false)
	await SceneGuard.wait(self, 0.5)
	for u in hit:
		var hp0: int = u.hp
		if not gc.god:
			if uid < 0:
				BattleRules.Damage.script_damage_46(u.st)
			else:
				BattleRules.Damage.script_damage_4a(u.st)
		view.digits(u, hp0 - u.hp, false)
	await SceneGuard.wait(self, 0.6)


# ================= 死亡与胜负 =================

func note_killer(dead: BattleUnit, killer: BattleUnit) -> void:
	_killers[dead] = killer


## 死亡处理: 掉落 -> kill_event (同一批去重) -> 胜负判定 (状态致死时仅当死者有 kill_event)
func resolve_deaths(trigger := Flow.TRIGGER_ACTION) -> void:
	var dead: Array = bs.units.filter(func(u): return u.shown and (not u.alive or u.hp <= 0))
	var killers := _killers
	_killers = {}
	for u in dead:
		if u.controllable and u.shown and gc.content.is_hero(int(u.man["unit_id"])):   # 主角阵亡: 统计开着时记一笔
			var kb: BattleUnit = killers.get(u)
			if stats.enabled:
				stats.death(bs.turn, u.name_text, kb.name_text if kb != null else "")
		u.alive = false
		await u.fade_out()
		u.dump_items_to_bag()
		if u.summon_flag >= 0:  # 召唤物死亡: 标志清 0, 本关可再召唤
			gc.state.set_data(u.summon_flag, 0)
			u.summon_flag = -1
	await _kill_get(dead, killers)
	var dead_st: Array = dead.map(func(u): return u.st)
	for ke in Flow.kill_events(dead_st):
		await bs.vm.run(ke)
		if bs.vm.ended:
			over = true
			return
	if Flow.should_judge(rules.ctx, trigger, dead_st):
		_check_judge()
		if over:
			await bs.vm.run(_judge_event)


## 杀敌掉落 kill_get: 只有玩家单位 (阵营 0 且非 AI) 击杀阵营 1 才给; 友军 NPC 击杀、中毒死亡不给。
## 金钱 (type 0) 合并后加入全局金钱; 物品 (type 1) 原版进击杀者个人物品栏 (满了询问丢弃), 复刻只有公共行囊, 直接放进行囊。
## 提示: 击杀者头像对话「得到金錢N兩.」/「得到X.」(Respro.msg = system_text battle_result; 原版获得物品同为头像对话框)
func _kill_get(dead: Array, killers: Dictionary) -> void:
	var items: Array = Content.items()
	var t := _text("battle_result", [["得到金钱{0}两.", "得到{0}."], ["是否丢弃其它物品,来存放{0}.", "是,丢弃身上的其它物品.", "否,放弃该物品."]])
	var gold := 0
	var gold_to: BattleUnit = null
	var msgs: Array = []   # [单位, 文字]
	for u in dead:
		var k: BattleUnit = killers.get(u)
		if k == null or u.camp != 1 or not k.controllable:
			continue
		var parm := int(u.man.get("kill_get_parm", 0))
		match int(u.man.get("kill_get_type", -1)):
			0:
				gold += parm
				gold_to = k
				stats.drop(k, u.index, "金钱%d两" % parm)
			1:
				if parm >= 0 and parm < items.size():
					# 进击杀者本人 10 格; 满了问是否丢弃其它物品来存放, 否 = 该物品丢失 (Respro.msg)
					if await receive_item(k, parm, t[1]):
						print("掉落: %s 得到 %s" % [k.name_text, item_name(parm)])
						stats.drop(k, u.index, item_name(parm))
						msgs.append([k, String(t[0][1]).replace("{0}", item_name(parm))])
					else:
						print("掉落: %s 放弃 %s" % [k.name_text, item_name(parm)])
	if gold > 0:
		gc.state.gold += gold
		print("掉落: 金钱 %d" % gold)
		msgs.push_front([gold_to, String(t[0][0]).replace("{0}", str(gold))])
	for mm in msgs:
		await bs.msgbox.show_text(BattleActions.face_of(mm[0]), 0, 0, mm[1])


## 胜负判定 (JUDGE): 先胜后负 (engine/rules/flow.gd)
func _check_judge() -> void:
	if bs.vm.ended:
		over = true
		return
	var j := rules.judge()
	if j.result != "":
		over = true
		_judge_event = int(j.event)
		print("判定: %s, 事件 %d" % [j.result, _judge_event])
		stats.result = String(j.result)

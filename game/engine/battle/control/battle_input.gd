# SPDX-License-Identifier: GPL-3.0-only
class_name BattleInput
extends Node
## 战场玩家操作 (原版 GameBattleInput, 规格 第 2 节): 状态栈 + 统一输入层的动作。
## 只在我方操作阶段 (player_phase) 接收动作; 执行行动 / 移动 / 确认框期间 busy, 不接收。
## 光标类状态 (BattleState.cursor_mode) 的通用操作在这里处理:
##   方向 (按住 0.5 秒后连移)、触摸拖动 = 卷动地图、查看 (F/F1/中键/长按) = 光标下单位的详情;
##   指针由统一输入层按地图格子的命中区处理 (ui_hits): 悬停 = 光标跟随, 点按 = 光标移到该格再确认, 中键 = 先移再查看。
## 我方回合开始: 光标移到第一个未行动的我方单位 (不自动选中, 确认后才选中 改判)。
## 行动结束: 光标留在当时所在的格 (攻击后在目标格, §5-19); 我方全员行动完自动结束回合; 手动结束只经系统菜单并确认。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal phase_done

## 依赖 (不标类型, 测试可换成替身, 见 tests/test_battle_input.gd):
var bc       # BattleController
var bs       # BattleScene: st (地图), cam, follow_cell(), scroll_camera(), snapshot()
var rules    # BattleRules
var view     # BattleView
var ui       # BattleUi
var flow     # BattleFlow: ready_units(), finish_unit_action(), over
var actions  # BattleActions: attack(), cast(), use_item()

var stack: Array = []        # BattleState, 末尾为栈顶
var active := false          # 我方操作阶段中
var busy := false
var cur := Vector2i.ZERO     # 光标格
var sel: BattleUnit          # 选中的单位
var reach := {}              # 选中单位可到的格
var last_unit: BattleUnit    # 上次行动 / 巡视到的单位 (取消键从它往后找, 原版 lastUnitID)
var _snap := {}              # 移动前的状态 (撤销移动)
var _path: Array = []        # 本次行动的移动路径 (不含起点), 行动结束查地图事件用


func _init(controller = null) -> void:
	if controller == null:
		return
	bc = controller
	bs = controller.bs
	rules = controller.rules
	view = controller.view
	ui = controller.ui
	flow = controller.flow
	actions = controller.actions


# ================= 阶段 =================

func player_phase() -> void:
	var rs: Array = flow.ready_units()
	if rs.is_empty():
		return
	active = true
	busy = false
	_clear_stack()
	var first: BattleUnit = rs[0]
	last_unit = first
	set_cursor(Vector2i(first.cx, first.cy))
	push(CursorState.new())  # 只移光标不选中: 信息条随光标显示, 玩家确认后才选中 (改判, 2026-10-06 用户原版实测)
	print("操作: 光标至 %s (%d,%d) 镜头 %s 帧%d" % [first.name_text, first.cx, first.cy, bs.cam, RegressLog.log_frame])
	await phase_done
	active = false
	_clear_stack()
	sel = null
	view.clear_range()
	view.show_cursor(cur)   # 原版: 结束回合后光标框留在原格, 敌方横幅期间照常显示
	view.hide_info()


func end_phase() -> void:
	if active:
		active = false
		phase_done.emit()


# ================= 状态栈 =================

func top() -> BattleState:
	return stack[-1] if not stack.is_empty() else null


func push(s: BattleState) -> void:
	s.c = self
	stack.append(s)
	s.enter()


func pop() -> void:
	if stack.size() <= 1:
		return
	var s: BattleState = stack.pop_back()
	s.exit()
	top().resume()


## 换掉栈顶 (下层不 resume)
func replace(s: BattleState) -> void:
	if not stack.is_empty():
		stack.pop_back().exit()
	push(s)


## 一直出栈到某类状态 (它 resume)
func pop_to(cls) -> void:
	while stack.size() > 1 and not is_instance_of(top(), cls):
		stack.pop_back().exit()
	top().resume()


## 回到光标状态 (清掉其上的全部状态)
func reset_to_cursor() -> void:
	while stack.size() > 1:
		stack.pop_back().exit()
	if stack.is_empty():
		push(CursorState.new())
	else:
		top().resume()


func _clear_stack() -> void:
	while not stack.is_empty():
		stack.pop_back().exit()


# ================= 输入 =================

## 统一输入层 (战场在界面栈底; 对话框、确认框打开时在它上面)。指针不在这里处理 (见 ui_pointer_target)
func ui_action(a: UiAction) -> bool:
	if not active or busy or stack.is_empty():
		return true
	var s := top()
	if not s.cursor_mode:
		s.on_action(a)
		return true
	match a.kind:
		UiAction.UP, UiAction.DOWN, UiAction.LEFT, UiAction.RIGHT:
			set_cursor(cur + a.dir())
		UiAction.DRAG:
			bs.scroll_camera(-a.delta / Assets.SCALE)
		UiAction.INFO:
			var u: BattleUnit = rules.unit_at(cur)
			if u:
				open_detail(u)
			elif a.source == "touch":
				s.on_menu()   # 触屏长按空地 = 系统菜单 (点按空地只移动选择格, 见下)
		UiAction.CONFIRM, UiAction.SELECT:
			if not a.echo:
				if a.source == "touch" and s is CursorState and rules.unit_at(cur) == null:
					return true   # 触屏点按空地: 光标 (选择格) 已由指针层移过去了, 不弹菜单 (手指点偏了就开菜单太容易误触); 键盘/鼠标/屏幕确认键仍是原版的「空地确认 = 系统菜单」
				s.confirm()
		UiAction.CANCEL:
			if not a.echo:
				s.cancel()
		UiAction.MENU:
			s.on_menu()
	return true


## F2 (统一输入层先问栈顶): 原版战场空闲光标态 (状态 0) F2 = 战场地图; 其他状态不处理
func ui_f2() -> bool:
	if not active or busy or stack.is_empty():
		return false
	return top().on_f2()


## 指针 (engine/ui/ui_hit.gd): 光标类状态时地图格子是命中区 (本节点 ui_hits), 界面类状态交给它的菜单/列表 (BattleState.pointer_target)
func ui_pointer_target() -> Object:
	if not active or busy or stack.is_empty():
		return null
	var s := top()
	return self if s.cursor_mode else s.pointer_target()


## 整张地图按格 (30x24) 切分, index = 格坐标; 地图在 bs 坐标系里随镜头平移 −cam
func ui_hits() -> Array:
	var cell := Vector2(BattleStage.CELL_W, BattleStage.CELL_H)
	return [UiHit.area(Rect2(-bs.cam, cell * Vector2(bs.st.width, bs.st.height)), Vector2i.ZERO, bs, UiAction.CONFIRM, cell)]


## 光标移到格 c (悬停 = 光标跟随, 点按 = 移到该格再确认)
func ui_select(c) -> void:
	if c != cur and in_map(c):
		set_cursor(c, true)


func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < bs.st.width and c.y < bs.st.height


# ================= 光标 =================

## 光标移到格 c (夹在地图内), 镜头跟随, 信息条显示格上的单位
## pointer: 指针悬停 / 点按选的格 (一定在屏幕上), 镜头只推一小步 (BattleScene.follow_cell minimal); 键盘 / 手柄相邻移光标同样只推一小步, 跳得远才重新居中
## 键盘 / 手柄一格一格移 (离上一格 <= NEAR_STEP) 也只推一小步, 跳得远 (切到下一个单位 / 目标) 才重新居中
const NEAR_STEP := 2

func set_cursor(c: Vector2i, pointer := false) -> void:
	var prev := cur
	cur = c.clamp(Vector2i.ZERO, Vector2i(bs.st.width - 1, bs.st.height - 1))
	var near := absi(cur.x - prev.x) + absi(cur.y - prev.y) <= NEAR_STEP
	bs.follow_cell(cur.x, cur.y, pointer or near)
	show_cursor()


func show_cursor(with_info := true) -> void:
	view.show_cursor(cur)
	if with_info:
		view.show_info(rules.unit_at(cur), cur)


## 取消键: 光标跳到下一个未行动的我方单位 (从 last_unit 往后找, 到尾回到头; 原版 nextUser/firstUser)
func cycle_next_unit() -> void:
	var rs: Array = flow.ready_units()
	if rs.is_empty():
		return
	var i: int = rs.find(last_unit)
	var nxt: BattleUnit = rs[0]
	if last_unit != null and i < 0:  # last_unit 已行动: 按单位编号往后找
		for u in rs:
			if u.index > last_unit.index:
				nxt = u
				break
	elif i >= 0:
		nxt = rs[(i + 1) % rs.size()]
	last_unit = nxt
	set_cursor(Vector2i(nxt.cx, nxt.cy))


# ================= 选中与移动 =================

## 选中格上的单位: 我方未行动 -> 移动范围 (剩余移动力); 其他 -> 该单位的移动范围 (最大移动力, 敌方红色)
func select_unit(u: BattleUnit) -> void:
	sel = u
	var own: bool = u.controllable and rules.can_start_action(u)
	if own:
		gc.state.set_data(rules.ctx.params.var_actor, u.index)  # 剧情变量 102 = 当前行动单位, 玩家选中时写
		_snap = rules.move_snapshot(u)
		_path = []
		reach = rules.move_range(u)
		view.show_range(reach.keys(), BattleView.RANGE_MOVE)
	else:
		reach = rules.move_range_full(u)
		view.show_range(reach.keys(), BattleView.RANGE_ENEMY if u.st.side == 1 else BattleView.RANGE_MOVE)
	push(UnitSelectState.new(own))
	show_cursor()


## 沿路径走到 to, 然后打开行动菜单 (移动过: 不能爆發)
func move_selected(to: Vector2i) -> void:
	busy = true
	view.clear_range()
	view.hide_info()
	_path = rules.commit_move(sel, to)
	if not _path.is_empty():
		sel.walk(_path, BattleStage.WALK_SPEED)
		await sel.move_finished
	busy = false
	push(ActionMenuState.new())


## 行动菜单取消: 撤销移动 (返还移动点), 光标留在移动后的位置, 回到光标状态
func undo_move() -> void:
	rules.move_restore(sel, _snap)
	_path = []
	sel.play_act(BattleUnit.Act.STAND, sel.dir)
	view.clear_range()
	sel = null
	reset_to_cursor()


## 装备/丢弃之后: 原版不消耗行动, 回到选中状态重新显示 (剩余移动力的) 移动范围, 之后仍可移动、出手;
## 魔改开关 equip_costs_action 时结束行动。stay_in_list: 物品列表里装备/丢弃 (不耗行动时) 留在列表, 由调用方刷新, 这里什么都不动
func after_equip_or_discard(stay_in_list := false) -> void:
	var u := sel
	if rules.after_equip_or_discard(u):
		await _finish()
		return
	if stay_in_list:
		return
	_close_menus()
	set_cursor(Vector2i(u.cx, u.cy))
	select_unit(u)


# ================= 执行行动 =================

func do_burst() -> void:
	rules.burst(sel)
	await _finish()


func do_wait() -> void:
	await _finish()


func do_attack(t: BattleUnit) -> void:
	await _act(func(): await actions.attack(sel, t))


func do_cast(sk: Dictionary, c: Vector2i) -> void:
	await _act(func(): await actions.cast(sel, sk, c))


func do_item(id: int, c: Vector2i) -> void:
	await _act(func(): await actions.use_item(sel, id, c))


## 交給 (原版实测 + GITEPRO.MSG): 范围 = 相邻一格; 对方物品栏未满 -> 追加到对方末尾, 提示「取得X.」(X = 给出的物品);
## 满了 -> 「身上物品太多了,请选择欲交换的物品.」从对方物品栏选一件 (已装备的灰) 互换位置, 提示「取得X.」(X 仍是给出的物品, 给出者换回的不提示);
## 三种提示的头像见 BattleActions.give_face;
## 取消 -> 「放弃给予物品.」不消耗行动, 回到选目标。成功后消耗行动 (params.give_costs_action)
func do_give(slot: int, t: BattleUnit) -> void:
	var u := sel
	if t == null or not rules.inv_can_give(u, slot):
		return
	busy = true
	var tx: Array = BattleFlow._text("give_item", [["身上物品太多了,请选择欲交换的物品.", "放弃给予物品.", "取得{0}."]])
	var given: int = int(u.st.items[slot])
	var got_text := String(tx[0][2]).replace("{0}", BattleFlow.item_name(given))  # 「取得X.」X = 给出的物品 (满格互换时也是它)
	var gf := BattleActions.face_of(u)
	var tf := BattleActions.face_of(t)
	if rules.inv_give(u, slot, t):
		await bs.msgbox.show_text(BattleActions.give_face("got", gf, tf), 0, 0, got_text)
	else:
		await bs.msgbox.show_text(BattleActions.give_face("full", gf, tf), 0, 0, String(tx[0][0]))
		var j: int = await flow.pick_slot(t, func(i): return rules.inv_can_give(t, i))
		if j < 0:
			await bs.msgbox.show_text(BattleActions.give_face("cancel", gf, tf), 0, 0, String(tx[0][1]))
			busy = false
			return
		rules.inv_exchange(u, slot, t, j)
		await bs.msgbox.show_text(BattleActions.give_face("got", gf, tf), 0, 0, got_text)
	if rules.after_give(u):
		await _finish()
		return
	busy = false
	after_equip_or_discard()  # 行动未结束 (魔改): 回到选中状态


func _act(f: Callable) -> void:
	busy = true
	_close_menus()
	view.clear_range()
	await f.call()
	await _finish()


func _close_menus() -> void:
	while stack.size() > 1:
		stack.pop_back().exit()


## 行动结束: 移动点清零 -> 宝箱与地图事件; 全员行动完 (或战斗结束) 自动结束回合, 否则回到光标 (光标留在原处)
func _finish() -> void:
	busy = true
	_close_menus()
	view.clear_range()
	var u := sel
	await flow.finish_unit_action(u, _path, _snap.get("pos", Vector2i(-1, -1)))
	_path = []
	sel = null
	last_unit = u
	if flow.over or flow.ready_units().is_empty():
		end_phase()
		return
	reset_to_cursor()
	busy = false


# ================= 系统菜单的命令 =================

## 結束回合: 关闭系统菜单, 隐藏光标, 确认框 (第 9~11 句, 默认「是」); 否或取消恢复光标
func ask_end_turn() -> void:
	reset_to_cursor()
	view.hide_cursor()
	if await confirm_box(9):
		end_phase()
	else:
		show_cursor()


## 存讀子菜单: 0 存档 / 1 读档 / 2 情報 / 3 结束游戏
func system_command(k: int) -> void:
	reset_to_cursor()
	match k:
		0:
			if await confirm_box(0):
				gc.flow.save_battle(bs.snapshot())  # 原版存完无提示 (用户实测), 只在日志留路径
		1:
			if await confirm_box(3):
				busy = true
				if not await gc.flow.load_battle():  # 没有存录 / 读不了 (损坏、内容包不兼容, Game 已弹提示): 回到可操作, 否则战场永久无响应
					busy = false
		2:
			push(WindowState.new(WindowState.BRIEF))
		3:
			if await confirm_box(6):
				busy = true
				gc.flow.return_to_title()  # 不 await: 本场景随即被释放


## 系统确认框 (原版 GameMsgBoxChooseUI, 默认「是」; 取消 = 否)
func confirm_box(first: int) -> bool:
	busy = true
	view.hide_cursor()
	var yes: bool = await ui.confirm_text(first, true)
	busy = false
	show_cursor()
	return yes


func open_detail(u: BattleUnit) -> void:
	push(WindowState.new(WindowState.DETAIL, u))


## 战场情报的人数: [敌, 我, 友军, 回合]
func brief_counts() -> Array:
	var alive: Array = rules.units_alive()
	return [alive.filter(func(u): return u.st.side == 1).size(), alive.filter(func(u): return u.controllable).size(),
		alive.filter(func(u): return u.st.side == 0 and u.st.npc_ally).size(), bs.turn]


## 小地图上的单位点: [[格, 0 我 / 1 敌 / 2 友军], ...]
func map_dots() -> Array:
	return rules.units_alive().map(func(u): return [Vector2i(u.cx, u.cy), 1 if u.st.side == 1 else (2 if u.st.npc_ally else 0)])

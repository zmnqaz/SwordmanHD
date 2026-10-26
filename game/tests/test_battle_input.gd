# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战场玩家操作状态机 (engine/battle/control/): 用替身 (地图/规则/表现/界面/流程) 驱动 BattleInput, 检查状态栈与原版操作逻辑
## 图标菜单与列表用真组件 (需要 Assets/Content)。
const REQUIRES_TEST := {
	"test_icon_menu_wraps_and_skips_disabled": ["original"],
	"test_info_opens_detail_and_echo_moves_cursor_only": ["content"]
}  # 个别方法的依赖 (同上)

const US = preload("res://engine/rules/unit_state.gd")
const Inv = preload("res://engine/rules/inventory.gd")
const ItemRules = preload("res://engine/rules/items.gd")


class FakeStage:
	extends RefCounted
	var width := 12
	var height := 10
	var n := 0


class FakeMsg:
	extends RefCounted
	var shown: Array = []
	func show_text(_face, _a, _b, t: String) -> void:
		shown.append(t)


class FakeScene:
	extends Node2D
	var msgbox := FakeMsg.new()
	var st := FakeStage.new()
	var cam := Vector2.ZERO
	var turn := 1
	var cursor_cell := Vector2i(-1, -1)
	var units_node := Node2D.new()
	func _init() -> void:
		scale = Vector2.ONE * Assets.SCALE  # 同 BattleScene: 子节点用原版坐标 (指针换算按全局变换)
	func follow_cell(_x, _y) -> void:
		pass
	func scroll_camera(d: Vector2) -> void:
		cam += d
	func show_cursor(x: int, y: int) -> void:
		cursor_cell = Vector2i(x, y)
	func hide_cursor() -> void:
		cursor_cell = Vector2i(-1, -1)
	func snapshot() -> Dictionary:
		return {}


class FakeRules:
	extends RefCounted
	var units: Array = []
	var log: Array = []
	func unit_at(c: Vector2i, _except = null):
		for u in units:
			if u.alive and u.cx == c.x and u.cy == c.y:
				return u
		return null
	func can_start_action(u) -> bool:
		return not u.acted
	func can_burst(u) -> bool:
		return not u.st.moved
	func can_cast(_u, _id) -> bool:
		return true
	var save_ok := true
	func can_save_battle() -> bool:
		return save_ok
	func move_range(u) -> Dictionary:
		var out := {}
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if absi(dx) + absi(dy) <= 2:
					out[Vector2i(u.cx + dx, u.cy + dy)] = 0
		return out
	func move_range_full(u) -> Dictionary:
		return move_range(u)
	func move_snapshot(u) -> Dictionary:
		return {"pos": Vector2i(u.cx, u.cy), "moved": u.st.moved}
	func move_restore(u, s: Dictionary) -> void:
		u.cx = s["pos"].x
		u.cy = s["pos"].y
		u.st.moved = s["moved"]
	func commit_move(u, to: Vector2i) -> Array:
		u.cx = to.x
		u.cy = to.y
		u.st.moved = true
		return []
	func weapon_cells(_u, here: Vector2i) -> Array:
		return [here + Vector2i(1, 0), here + Vector2i(-1, 0), here + Vector2i(0, 1), here + Vector2i(0, -1)]
	func targets_from(u, here: Vector2i) -> Array:
		return units.filter(func(t): return t.alive and t.st.side != u.st.side and Vector2i(t.cx, t.cy) in weapon_cells(u, here))
	func cast_range(_u, _sk) -> Array:
		return []
	func cast_cells(_u, _sk) -> Array:
		return [Vector2i(3, 3)]
	func cast_area(sk) -> int:
		return int(sk.get("range", {}).get("area", 0))
	func item_range(_u, _id) -> Array:
		return []
	func item_cells(_u, _id) -> Array:
		return [Vector2i(3, 3)]
	func item_area(_id) -> int:
		return 1
	func after_equip_or_discard(u) -> bool:
		return ItemRules.after_equip_or_discard(ctx, u.st)
	func burst(u) -> void:
		log.append("burst %s" % u.name_text)
	func skill(_id) -> Dictionary:
		return {}
	func usable_items(_u) -> Array:
		return []
	# 物品栏 (engine/rules/inventory.gd), 同 BattleRules 的薄封装
	var ctx
	func inv_equipped(u) -> Dictionary:
		return Inv.equipped_map(u.st)
	func inv_can_give(u, i: int) -> bool:
		return Inv.can_give(u.st, i)
	func inv_can_equip(u, i: int) -> bool:
		return Inv.can_equip(ctx, u.st, i)
	func inv_equip(u, i: int) -> void:
		Inv.equip(ctx, u.st, i)
	func inv_discard(u, i: int) -> int:
		return Inv.discard(u.st, i)
	func give_targets(u) -> Array:
		return units.filter(func(t): return t != u and t.alive and t.st.side == u.st.side and absi(t.cx - u.cx) + absi(t.cy - u.cy) == 1)
	func inv_give(u, i: int, t) -> bool:
		return Inv.give(ctx, u.st, i, t.st)
	func after_give(u) -> bool:
		return ItemRules.after_give(ctx, u.st)


class FakeView:
	extends RefCounted
	var bs
	var range_cells: Array = []
	var info = null
	func show_range(cells: Array, _c) -> void:
		range_cells = cells
	func clear_range() -> void:
		range_cells = []
	var cursor_area := 0
	func set_cursor_area(a: int) -> void:
		cursor_area = a
	func show_cursor(c: Vector2i) -> void:
		bs.show_cursor(c.x, c.y)
	func hide_cursor() -> void:
		bs.hide_cursor()
	func show_info(u, _at) -> void:
		info = u
	func hide_info() -> void:
		info = null
	func digits(_u, _v: int, _heal: bool):
		return null


class FakeChoice:
	extends RefCounted
	var answer := true
	var asked: Array = []
	func ask(q: String, _y, _n, _d := true) -> bool:
		asked.append(q)
		return answer


class FakeUi:
	extends RefCounted
	var bs
	var choice := FakeChoice.new()
	var menus: Array = []
	func icon_menu(id: String, enabled: Array, sel: int, cell: Vector2i) -> UiIconMenu:
		var m := UiIconMenu.new()
		m.setup_id(id, enabled, sel)
		m.position = Vector2(cell.x * 30, cell.y * 24 + 7)
		m.set_meta("cell", cell)
		menus.append(m)
		return m
	func sub_menu(parent: UiIconMenu, id: String, enabled: Array, sel: int, frames: Array = []) -> UiIconMenu:
		var m := UiIconMenu.new()
		m.setup_id(id, enabled, sel, frames)
		m.position = parent.position + Vector2(0, -8)
		menus.append(m)
		return m
	func list_menu(lay: Dictionary, rows: Array, sel := -1) -> UiListMenu:
		var l := UiListMenu.new()
		l.setup(lay, rows, sel)
		return l
	func add_center(n: Node) -> Node:
		bs.add_child(n)
		return n
	func confirm_text(_first: int, _d := true) -> bool:
		return await choice.ask("?", "", "", true)


class FakeFlow:
	extends RefCounted
	var rules
	var over := false
	var finished: Array = []
	func ready_units() -> Array:
		return rules.units.filter(func(u): return u.alive and u.controllable and not u.acted)
	func finish_unit_action(u, _path, _start = null) -> void:
		u.acted = true
		finished.append(u.name_text)


class FakeActions:
	extends RefCounted
	var log: Array = []
	func attack(a, t) -> void:
		log.append("attack %s -> %s" % [a.name_text, t.name_text])


var _bs: FakeScene
var _rules: FakeRules
var _ui: FakeUi
var _flow: FakeFlow
var _actions: FakeActions
var _done := 0
var _ctx


func _assets_ready() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var A = tree.root.get_node_or_null("Assets")
	var C = tree.root.get_node_or_null("Content")
	if A == null or C == null:
		return false
	if A._index.is_empty():
		A._ready()
	if C.packs.is_empty():
		C.load_packs([ContentDB.default_main()])
	return not A._index.is_empty()


func _unit(name: String, side: int, c: Vector2i) -> BattleUnit:
	var u := BattleUnit.new()
	u.info = {"name": name, "camp": side, "sprite": 1}
	u._anim_dir = "Sprite/man001/001man"
	u.anim = AnimPlayer.new()
	u.add_child(u.anim)
	u.man = {"unit_id": 90}
	u.ctx = _ctx
	u.st = US.new()
	u.st.skills = [1]
	u.st.side = side
	u.st.alive = true
	u.st.hp = 10
	u.st.hp_max = 10
	u.shown = true
	u.set_cell(c.x, c.y)
	return u


## 我方 甲 (2,2)、乙 (6,6); 敌方 丙 (4,2)
func _setup() -> BattleInput:
	_ctx = ctx_data()
	_bs = FakeScene.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_bs)
	_rules = FakeRules.new()
	_rules.ctx = _ctx
	_rules.units = [_unit("甲", 0, Vector2i(2, 2)), _unit("乙", 0, Vector2i(6, 6)), _unit("丙", 1, Vector2i(4, 2))]
	var view := FakeView.new()
	view.bs = _bs
	_ui = FakeUi.new()
	_ui.bs = _bs
	_flow = FakeFlow.new()
	_flow.rules = _rules
	_actions = FakeActions.new()
	var c := BattleInput.new()
	_bs.add_child(c)
	c.bs = _bs
	c.rules = _rules
	c.view = view
	c.ui = _ui
	c.flow = _flow
	c.actions = _actions
	c.phase_done.connect(func(): _done += 1)
	_done = 0
	c.player_phase()
	return c


func _names(c: BattleInput) -> Array:
	return c.stack.map(func(s): return String(s.get_script().get_global_name()))


## 带坐标的动作经统一输入层 (InputRouter 实例) 走指针命中: 先移到该点 (悬停) 再发动作
func _act(c: BattleInput, kind: int, pos := Vector2.INF) -> void:
	if pos == Vector2.INF:
		c.ui_action(UiAction.new(kind, "test", pos))
		return
	var r = load("res://engine/input/input_router.gd").new()
	r.push(c)
	r.dispatch(UiAction.new(UiAction.POINT, "mouse", pos))
	r.dispatch(UiAction.new(kind, "mouse", pos))
	r.free()


func _cleanup() -> void:
	for u in _rules.units:
		u.free()
	_bs.units_node.free()
	_bs.get_parent().remove_child(_bs)
	_bs.free()


func test_phase_start_only_moves_cursor():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	eq(_names(c), ["CursorState"], "回合开始只移光标, 不自动选中 (改判, 2026-10-06 用户原版实测)")
	eq(c.sel, null, "没有选中单位")
	eq(c.cur, Vector2i(2, 2), "光标在第一个未行动单位上")
	check(c.view.range_cells.is_empty(), "不显示移动范围")
	_act(c, UiAction.CONFIRM)
	eq(_names(c), ["CursorState", "UnitSelectState"], "确认后才选中")
	eq(c.sel.name_text, "甲")
	check(not c.view.range_cells.is_empty(), "选中后显示移动范围")
	_act(c, UiAction.CANCEL)
	eq(_names(c), ["CursorState"], "取消: 收起范围回到光标")
	eq(c.cur, Vector2i(2, 2), "光标留在原处")
	_act(c, UiAction.CANCEL)
	eq(c.cur, Vector2i(6, 6), "光标状态取消: 跳到下一个未行动单位 (§5-1)")
	_act(c, UiAction.CANCEL)
	eq(c.cur, Vector2i(2, 2), "循环巡视")
	eq(_done, 0, "取消键从不结束回合")
	_cleanup()


func test_move_menu_cancel_undoes_move():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	_act(c, UiAction.CONFIRM)  # 回合开始只移光标 (改判), 先确认选中
	_act(c, UiAction.DOWN)
	eq(c.cur, Vector2i(2, 3), "选中后光标仍可移动")
	_act(c, UiAction.CONFIRM)
	eq(_names(c)[-1], "ActionMenuState", "范围内确认: 移动后打开行动菜单")
	var m: UiIconMenu = _ui.menus[-1]
	eq(m.selected, 2, "初始选中攻擊")
	check(not m.enabled[0], "移动过不能爆發")
	eq(m.get_meta("cell"), Vector2i(2, 3), "菜单跟在单位 (移动后) 处")
	_act(c, UiAction.UP)
	eq(m.selected, 3, "Up +1")
	_act(c, UiAction.RIGHT)
	eq(m.selected, 4, "Right +1 到最右")
	_act(c, UiAction.RIGHT)
	eq(m.selected, 1, "最右再按右: 循环回最左的可用项 (爆發禁用, 跳过; 原版夹紧不循环, 差异)")
	_act(c, UiAction.LEFT)
	eq(m.selected, 4, "最左的可用项再按左: 循环到最右 (用户要求, 跳过禁用的爆發)")
	_act(c, UiAction.DOWN)
	_act(c, UiAction.DOWN)
	_act(c, UiAction.DOWN)
	eq(m.selected, 1, "Down −1 逐项往左")
	_act(c, UiAction.CANCEL)
	eq(_names(c), ["CursorState"], "行动菜单取消: 回到光标")
	eq(Vector2i(c.rules.units[0].cx, c.rules.units[0].cy), Vector2i(2, 2), "撤销移动: 单位回原位")
	eq(c.cur, Vector2i(2, 3), "光标留在移动后的位置 (§5-18)")
	_cleanup()


func test_attack_target_is_free_cursor():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	_act(c, UiAction.CONFIRM)          # 回合开始只移光标 (改判), 先确认选中甲
	_act(c, UiAction.RIGHT)
	_act(c, UiAction.CONFIRM)          # 走到 (3,2), 敌人在 (4,2)
	_act(c, UiAction.CONFIRM)          # 攻擊
	eq(_names(c)[-1], "TargetState", "攻擊 -> 选目标")
	eq(c.cur, Vector2i(4, 2), "光标初始在第一个目标上")
	_act(c, UiAction.DOWN)
	eq(c.cur, Vector2i(4, 3), "光标自由移动, 不是在目标间循环 (§5-3)")
	_act(c, UiAction.CONFIRM)
	eq(_actions.log, [], "空格确认无反应")
	_act(c, UiAction.CANCEL)
	eq(_names(c)[-1], "ActionMenuState", "取消回到行动菜单, 不撤销移动")
	eq(Vector2i(c.sel.cx, c.sel.cy), Vector2i(3, 2))
	_act(c, UiAction.CONFIRM)
	_act(c, UiAction.CONFIRM, Vector2(4 * 30 + 15, 2 * 24 + 12) * Assets.SCALE)  # 点按敌人: 点哪选哪
	eq(_actions.log, ["attack 甲 -> 丙"], "点按目标格发动攻击")
	eq(_flow.finished, ["甲"], "行动结束")
	eq(_names(c), ["CursorState"], "回到光标")
	eq(c.cur, Vector2i(4, 2), "光标留在目标格 (§5-19)")
	eq(_done, 0, "还有人没行动, 不结束回合")
	# 乙 待機 -> 全员行动完自动结束回合
	_act(c, UiAction.CANCEL)
	eq(c.cur, Vector2i(6, 6), "取消跳到剩下的乙")
	_act(c, UiAction.CONFIRM)
	_act(c, UiAction.CONFIRM)
	var m: UiIconMenu = _ui.menus[-1]
	m.select(4)
	_act(c, UiAction.CONFIRM)
	eq(_done, 1, "全员行动完自动结束回合")
	_cleanup()


func test_system_menu_end_turn_needs_confirm():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	_act(c, UiAction.UP)  # 回合开始就在光标态, 光标 (2,2) 上移一格到空地
	_act(c, UiAction.CONFIRM)  # 空地
	eq(_names(c)[-1], "SystemMenuState", "空地确认 -> 系统菜单")
	var m: UiIconMenu = _ui.menus[-1]
	eq(m.frames, [0, 4, 8, 12], "Sys_int 四个图标")
	eq(m.selected, 0, "默认「存讀」(§5-2)")
	_act(c, UiAction.CONFIRM)
	eq(_names(c)[-1], "SystemSubState", "存讀 -> 子菜单")
	_act(c, UiAction.CANCEL)
	eq(_names(c)[-1], "SystemMenuState", "取消回系统菜单")
	for i in 3:
		_act(c, UiAction.RIGHT)
	_ui.choice.answer = false
	_act(c, UiAction.CONFIRM)
	eq(_ui.choice.asked.size(), 1, "結束回合先弹确认框")
	eq(_done, 0, "选否不结束")
	eq(_names(c), ["CursorState"], "回到光标")
	_act(c, UiAction.MENU)
	eq(_names(c)[-1], "SystemMenuState", "菜单键 (屏幕按钮) 打开系统菜单")
	for i in 3:
		_act(c, UiAction.RIGHT)
	_ui.choice.answer = true
	_act(c, UiAction.CONFIRM)
	eq(_done, 1, "选是结束回合")
	_cleanup()


func test_info_opens_detail_and_echo_moves_cursor_only():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	var e := UiAction.new(UiAction.RIGHT, "key", Vector2.INF, true)
	c.ui_action(e)
	eq(c.cur, Vector2i(3, 2), "光标状态接受按住连发")
	_act(c, UiAction.RIGHT)
	_act(c, UiAction.INFO)
	eq(_names(c)[-1], "WindowState", "查看: 光标下单位的详情")
	_act(c, UiAction.CANCEL)
	eq(_names(c), ["CursorState"], "取消关闭详情")
	_act(c, UiAction.CONFIRM)
	eq(_names(c)[-1], "UnitSelectState", "敌方单位: 显示其范围")
	_act(c, UiAction.CONFIRM)
	eq(_names(c)[-1], "WindowState", "再确认打开详情")
	c.ui_action(UiAction.new(UiAction.CONFIRM, "key", Vector2.INF, true))
	check(true)
	_cleanup()


## 触屏: 点按空地只移动选择格 (不弹菜单), 长按空地才是系统菜单; 点单位照常选中; 键盘/鼠标/屏幕确认键仍是「空地确认 = 系统菜单」
func test_touch_tap_empty_moves_cursor_long_press_opens_menu():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	_act(c, UiAction.UP)   # (2,1): 空地
	c.ui_action(UiAction.new(UiAction.CONFIRM, "touch"))
	eq(_names(c), ["CursorState"], "触屏点按空地: 不弹系统菜单")
	c.ui_action(UiAction.new(UiAction.INFO, "touch"))
	eq(_names(c)[-1], "SystemMenuState", "触屏长按空地: 系统菜单")
	c.ui_action(UiAction.new(UiAction.CANCEL, "touch"))
	_act(c, UiAction.DOWN)   # 回 (2,2): 有我方单位
	c.ui_action(UiAction.new(UiAction.CONFIRM, "touch"))
	eq(_names(c)[-1], "UnitSelectState", "触屏点单位: 照常选中")
	c.ui_action(UiAction.new(UiAction.CANCEL, "touch"))
	_act(c, UiAction.UP)
	c.ui_action(UiAction.new(UiAction.CONFIRM, "button"))
	eq(_names(c)[-1], "SystemMenuState", "屏幕确认键 (非手势) 仍是空地确认 = 系统菜单")
	_cleanup()


## 物品栏 M5: 战斗「交給」流程 (物品列表 GIVE 模式 -> 选相邻队友 -> 追加到对方物品栏, 消耗行动); 已装备的灰
func test_give_item_flow():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	var a: BattleUnit = _rules.units[0]
	var b: BattleUnit = _rules.units[1]
	b.set_cell(2, 3)
	a.st.items = [0, 220]
	a.st.weapon = 0
	_act(c, UiAction.CONFIRM)                 # 回合开始只移光标 (改判): 先确认选中
	_act(c, UiAction.CONFIRM)                 # 原地确认: 行动菜单
	var m: UiIconMenu = _ui.menus[-1]
	m.select(3)
	_act(c, UiAction.CONFIRM)                 # 物品子菜单
	c.stack[-1].menu.select(1)
	_act(c, UiAction.CONFIRM)                 # 交給 -> 列表
	eq(_names(c)[-1], "ItemListState")
	var lst: UiListMenu = c.stack[-1].list
	eq(lst.rows.size(), 2, "列表 = 本人 10 格 (不是公共行囊)")
	check(not lst.rows[0]["enabled"], "已装备的武器不能交给别人")
	check(lst.rows[1]["enabled"], "药品可交")
	eq(lst.selected, 1, "初始选第一个可用项")
	_act(c, UiAction.CONFIRM)
	eq(_names(c)[-1], "TargetState", "选目标")
	eq(c.cur, Vector2i(2, 3), "光标在相邻队友上")
	eq(c.view.range_cells.size(), 4, "范围 = 相邻 4 格")
	_act(c, UiAction.CONFIRM)
	eq(a.st.items, [0], "给出的从自己的格子里去掉")
	eq(b.st.items, [220], "追加到对方物品栏")
	eq(_flow.finished, ["甲"], "交給消耗行动")
	check(_bs.msgbox.shown.size() == 1 and "取得" in String(_bs.msgbox.shown[0]), "原版实测: 给出后提示「取得X.」: %s" % [_bs.msgbox.shown])
	_cleanup()


## 战场装备 (2026-10-11 用户要求): 装备 / 卸下留在物品列表里, 列表原地刷新, 不耗行动; 取消回物品子菜单
func test_equip_stays_in_item_list():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	var a: BattleUnit = _rules.units[0]
	a.st.unit_id = 0   # 殷剑平: 两把剑都能装
	a.st.items = [0, 1]
	a.st.weapon = 0
	_act(c, UiAction.CONFIRM)                 # 选中
	_act(c, UiAction.CONFIRM)                 # 行动菜单
	_ui.menus[-1].select(3)
	_act(c, UiAction.CONFIRM)                 # 物品子菜单
	c.stack[-1].menu.select(2)
	_act(c, UiAction.CONFIRM)                 # 裝備 -> 列表
	eq(_names(c)[-1], "ItemListState")
	var lst: UiListMenu = c.stack[-1].list
	check(not lst.rows[0]["enabled"] and lst.rows[1]["enabled"], "当前武器不可选, 另一把可装")
	lst.select(1)
	_act(c, UiAction.CONFIRM)
	eq(a.st.weapon, 1, "换上了第二把")
	eq(_names(c)[-1], "ItemListState", "装备后留在列表里")
	check(_flow.finished.is_empty(), "不耗行动")
	var lst2: UiListMenu = c.stack[-1].list
	check(lst2.rows[0]["enabled"] and not lst2.rows[1]["enabled"], "列表已刷新: 现在第一把可再换回")
	lst2.select(0)
	_act(c, UiAction.CONFIRM)
	eq(a.st.weapon, 0, "不退出菜单, 接着换回")
	_act(c, UiAction.CANCEL)
	eq(_names(c)[-1], "ItemMenuState", "取消回物品子菜单")
	_cleanup()


## 战场装备预览 (按住空格): 数值取单位当前装备, 变好的显示绿色 (字模第 2 帧)。用户 2026-10-17 「卸下饰品后按空格看不到绿色变化」
func test_equip_preview_shows_green_after_unequip():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	var a: BattleUnit = _rules.units[0]
	a.st.unit_id = 0
	a.man = {"unit_id": 0}   # 预览按 man.unit_id 取营地存档
	a.st.items = [156, 157]   # 黑玉蛇戒 防+8 / 密法护印 防+20
	a.st.accessory = 156
	var gs: GameState = GameContext.current().state
	var saved_party = gs.party.duplicate(true)
	gs.party = {0: {"stats": {"str": 30, "vit": 30, "avg": 30}, "gear": {"weapon": null, "armor": null, "accessory": 157}}}   # 营地存档里戴的是密法护印 (战场里已换成蛇戒)
	_act(c, UiAction.CONFIRM)
	_act(c, UiAction.CONFIRM)
	_ui.menus[-1].select(3)
	_act(c, UiAction.CONFIRM)
	c.stack[-1].menu.select(2)
	_act(c, UiAction.CONFIRM)
	eq(_names(c)[-1], "ItemListState")
	var lst: UiListMenu = c.stack[-1].list
	lst.select(1)
	_act(c, UiAction.INFO)   # 戴着蛇戒看密法护印: 防 8 -> 20 变好
	eq(_def_frame(c.stack[-1]), 2, "换更好的饰品 (防 8 -> 20): 防显示绿色")
	_act(c, UiAction.INFO_UP)
	lst.select(0)
	_act(c, UiAction.CONFIRM)   # 再选一次 = 卸下蛇戒
	eq(a.st.accessory, -1, "卸下了")
	c.stack[-1].list.select(0)
	_act(c, UiAction.INFO)   # 没戴饰品看蛇戒: 防 0 -> 8 变好
	eq(_def_frame(c.stack[-1]), 2, "卸下后看原来那件 (防 0 -> 8): 防显示绿色")
	_act(c, UiAction.INFO_UP)
	gs.party = saved_party
	_cleanup()


## 预览里「防」行新值 (左列 x=54, y=20) 的字模帧: 1 不变 / 2 变好 (绿) / 3 变差 (红); 没开预览 -1
func _def_frame(state) -> int:
	if state._preview == null:
		return -1
	for ch in state._preview.get_children():
		if ch is UiNumber and ch.position.is_equal_approx(Vector2(54, 20)):
			return ch.frame
	return -2


## 选法术 / 道具落点: 光标形状 = 效果范围 (Misc/Cursor 的 3x3 / 5x5 / 7x7 菱形), 退出选目标后恢复单格
func test_target_cursor_shape_follows_area():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	_act(c, UiAction.CONFIRM)
	_act(c, UiAction.CONFIRM)
	c.push(TargetState.new(TargetState.SPELL, {"range": {"area": 2}}))
	eq(c.view.cursor_area, 2, "法术效果范围 2 -> 5x5 菱形光标")
	c.pop()
	eq(c.view.cursor_area, 0, "退出选目标 -> 单格")
	c.push(TargetState.new(TargetState.ITEM, 220))
	eq(c.view.cursor_area, 1, "道具按道具自己的效果范围")
	c.pop()
	c.push(TargetState.new(TargetState.ATTACK))
	eq(c.view.cursor_area, 0, "普攻单格")
	_cleanup()


## 模态选格器 (ItemPicker): 方向/确认/取消走统一输入层; 不可选的格确认无反应, 取消返回 -1
func test_item_picker_modal():
	if not _assets_ready():
		check(true)
		return
	_bs = FakeScene.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_bs)
	_ui = FakeUi.new()
	_ui.bs = _bs
	var got := []
	var p := ItemPicker.new()
	p.picked.connect(func(k): got.append(k))
	p.run(_ui, [220, 0, 99], {1: 0, 2: 1}, [true, false, false])
	check(p.list != null, "打开了列表")
	eq(p.list.selected, 0, "初始选第一个可选")
	p.ui_action(UiAction.new(UiAction.DOWN, "test"))
	eq(p.list.selected, 1)
	p.ui_action(UiAction.new(UiAction.CONFIRM, "test"))
	eq(got, [], "已装备 (不可选) 的格确认无反应")
	p.ui_action(UiAction.new(UiAction.UP, "test"))
	p.ui_action(UiAction.new(UiAction.CONFIRM, "test"))
	eq(got, [0], "可选的格返回格号")
	var q := ItemPicker.new()
	var got2 := []
	q.picked.connect(func(k): got2.append(k))
	q.run(_ui, [220], {}, [true])
	q.ui_action(UiAction.new(UiAction.CANCEL, "test"))
	eq(got2, [-1], "取消返回 -1")
	for pk in [p, q]:
		if pk.list != null and is_instance_valid(pk.list) and pk.list.get_parent() == null:
			pk.list.free()
	_bs.get_parent().remove_child(_bs)
	_bs.free()


## 回归: 系统菜单「读档」选是但读不了 (没有存录/存录损坏/内容包不兼容) 时, 战场必须恢复可操作 (以前 busy 永远为真, 战场永久无响应)
func test_system_load_failure_does_not_lock_battle():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	_ui.choice.answer = true
	c.gc = GameContext.new()  # 缺省流转实现: load_battle 返回 false (同 Game 读档失败)
	await c.system_command(1)
	check(not c.busy, "读档失败后战场恢复可操作")
	_cleanup()


## T36 (原版实测): 我方有人行动后, 系统菜单「存讀」里的「存档」变灰且确认无反应; 回合开始可存
func test_system_save_item_disabled_after_action():
	if not _assets_ready():
		check(true)
		return
	var c := _setup()
	for ok in [true, false]:
		c.rules.save_ok = ok
		_act(c, UiAction.CANCEL)
		_act(c, UiAction.UP)
		_act(c, UiAction.CONFIRM)  # 空地 -> 系统菜单
		_act(c, UiAction.CONFIRM)  # 存讀
		var m: UiIconMenu = _ui.menus[-1]
		eq(m.enabled[0], ok, "存档项可用 = %s" % ok)
		if not ok:
			check(m.selected != 0, "选中项夹到可用项, 不会落在灰显的存档上")
		_act(c, UiAction.CANCEL)
		_act(c, UiAction.CANCEL)
	_cleanup()


## 图标菜单 (行动菜单/物品子菜单/系统菜单) 方向键到头循环, 跳过禁用项 (UiIconMenu.move, 差异)
func test_icon_menu_wraps_and_skips_disabled():
	var m := UiIconMenu.new()
	m.setup([0, 4, 8, 12, 16], [false, true, true, true, true], {}, 2)
	eq(m.selected, 2)
	check(m.move(1), "右移")
	eq(m.selected, 3)
	m.move(1)
	eq(m.selected, 4)
	check(m.move(1), "最右再按右: 循环")
	eq(m.selected, 1, "回到最左的可用项, 跳过禁用的第 0 项")
	check(m.move(-1), "最左可用项再按左: 循环")
	eq(m.selected, 4, "到最右")
	var one := UiIconMenu.new()
	one.setup([0, 4, 8], [false, true, false], {}, 1)
	check(not one.move(1) and not one.move(-1), "只有一个可用项: 不动")
	eq(one.selected, 1)
	var none := UiIconMenu.new()
	none.setup([], [], {}, -1)
	check(not none.move(1), "空菜单不崩")
	m.free()
	one.free()
	none.free()

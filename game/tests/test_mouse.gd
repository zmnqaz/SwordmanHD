# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 指针命中框架 (engine/ui/ui_hit.gd + InputRouter._pointer): 用真组件, 把 InputEventMouseMotion / InputEventMouseButton
## 喂给输入层, 检查悬停 = 选中项跟随、左键 = 选中并确认、点空处、右键取消、滚轮、防误触、宽屏锚点换算。
const REQUIRES_TEST := {
	"test_icon_menu_and_list_menu_components": ["content"],
	"test_item_window_columns_menu_and_discard_ask": ["content"],
	"test_spirit_arrows_and_alloc": ["content"]
}  # 个别方法的依赖 (同上)

const Router = preload("res://engine/input/input_router.gd")


## 界面栈上的接收方: 指针交给组件 comp; 动作按营地按键名转给 comp.key (同 camp_scene), 并记录
class Screen:
	extends RefCounted
	var comp: Object
	var log: Array = []
	func _init(c: Object) -> void:
		comp = c
	func ui_pointer_target() -> Object:
		return comp
	func ui_action(a: UiAction) -> bool:
		log.append(a.name())
		var k := a.camp_key()
		if k != "" and comp.has_method("key"):
			comp.key(k)
		return true


var _nodes: Array = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _assets_ready() -> bool:
	var A = _tree().root.get_node_or_null("Assets")
	var C = _tree().root.get_node_or_null("Content")
	if A == null or C == null:
		return false
	if A._index.is_empty():
		A._ready()
	if C.packs.is_empty():
		C.load_packs([ContentDB.default_main()])
	return not A._index.is_empty()


func _layer() -> UiLayer:
	var l := UiLayer.new()
	_tree().root.add_child(l)
	_nodes.append(l)
	return l


func _cleanup() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()


func _router(receiver: Object):
	var r = Router.new()
	r.push(receiver)
	return r


## 组件局部坐标 (原版像素) → 屏幕坐标
func _scr(node: CanvasItem, local: Vector2) -> Vector2:
	return node.get_global_transform_with_canvas() * local


func _move(r, p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	r._handle(m)


func _button(r, p: Vector2, b: int) -> void:
	for pressed in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = b
		m.pressed = pressed
		m.position = p
		r._handle(m)


## 移过去再左键 (真实鼠标总是先移动)
func _click(r, p: Vector2) -> void:
	_move(r, p)
	_button(r, p, MOUSE_BUTTON_LEFT)


func test_camp_menu_hover_click_cancel_wheel():
	if not _assets_ready():
		check(true)
		return
	var l := _layer()
	var m := CampMenu.new()
	l.add(m)
	var s := Screen.new(m)
	var r = _router(s)
	var chosen := []
	m.chosen.connect(func(i): chosen.append(i))
	var cancelled := []
	m.cancelled.connect(func(): cancelled.append(true))
	# 16:10 下主菜单贴左上, 原版 (24,20) + 第 i 项 (15, 10+12i), ×4 = 屏幕坐标 (直接按原版坐标算, 验证换算)
	_move(r, Vector2(24 + 20, 20 + 10 + 12 * 3 + 6) * Assets.SCALE)
	eq(m.selected, 3, "悬停 = 箭头跟随到第 3 项")
	eq(s.log, [], "悬停不确认")
	_move(r, Vector2(300, 190) * Assets.SCALE)
	eq(m.selected, 3, "移到空处不改选中项")
	_click(r, _scr(m, Vector2(30, 10 + 12 * 5 + 5)))
	eq(m.selected, 5, "点别的项: 先切过去")
	eq(chosen, [5], "再确认")
	_button(r, Vector2(10, 10), MOUSE_BUTTON_RIGHT)
	eq(cancelled.size(), 1, "右键 = 取消")
	_button(r, Vector2(10, 10), MOUSE_BUTTON_WHEEL_DOWN)
	eq(m.selected, 6, "滚轮下 = ↓")
	_click(r, Vector2(1200, 700))
	eq(chosen, [5], "点空处不确认")
	r.free()
	_cleanup()


## 用户反馈: 营地「是否出发」的 ○/✗ 框鼠标点不中 ○ (原来点哪都等于确认当前的✗)
func test_camp_yes_no_click_o():
	if not _assets_ready():
		check(true)
		return
	var l := _layer()
	var q := CampAsk.Question.new("确定要准备出发了吗？")
	l.add(q)
	var s := Screen.new(q)
	var r = _router(s)
	var got := []
	q.done.connect(func(y): got.append(y))
	eq(q.yes_no.sel, 1, "默认✗")
	var rect := UiPanel.frame_rect(CampAsk.YesNo.DIR, 0)
	var o := _scr(q.yes_no, rect.position + Vector2(rect.size.x * 0.25, rect.size.y * 0.5))
	var x := _scr(q.yes_no, rect.position + Vector2(rect.size.x * 0.75, rect.size.y * 0.5))
	_move(r, o)
	eq(q.yes_no.sel, 0, "悬停在左半 = ○")
	_move(r, x)
	eq(q.yes_no.sel, 1, "悬停在右半 = ✗")
	_click(r, o)
	eq(got, [true], "点 ○ = 是")
	r.free()
	_cleanup()


func test_pointer_guard_after_popup():
	if not _assets_ready():
		check(true)
		return
	var l := _layer()
	var y := CampAsk.YesNo.new(Vector2(100, 100))
	l.add(y)
	var r = _router(Screen.new(y))
	var got := []
	y.done.connect(func(v): got.append(v))
	var rect := UiPanel.frame_rect(CampAsk.YesNo.DIR, 0)
	var o := _scr(y, rect.position + rect.size * Vector2(0.25, 0.5))
	_button(r, o, MOUSE_BUTTON_LEFT)
	eq(got, [], "刚弹出、指针没在上面移动过: 点按不算 (双击防误触)")
	r._process(UiHit.GUARD + 0.1)
	_button(r, o, MOUSE_BUTTON_LEFT)
	eq(got, [true], "过了防误触时间, 不移动也能点")
	r.free()
	_cleanup()


func test_item_window_columns_menu_and_discard_ask():
	if not _assets_ready():
		check(true)
		return
	var bag0: Array = Game.state.bag.duplicate()
	var party0: Dictionary = Game.state.party.duplicate(true)
	Game.state.bag = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
	Game.state.party = {0: {"lv": 1, "items": [13, 14], "gear": {}, "skills": [], "spirit": {}, "stats": {}}}
	var l := _layer()
	var w := CampItemWindow.new(CampInventory.new())
	l.add(w)
	var s := Screen.new(w)
	var r = _router(s)
	var row := func(side: int, k: int) -> Vector2:
		return _scr(w._panels[side], UiLayout.at("camp.item.row", k) + Vector2(35, 5))
	_move(r, row.call(1, 1))
	eq([w.focus, w.sel[1]], [1, 1], "悬停右栏第 1 行: 焦点移到右栏并选中")
	_move(r, row.call(0, 2))
	eq([w.focus, w.sel[0]], [0, 2], "悬停左栏第 2 行")
	_button(r, _scr(w._panels[0], Vector2(64, 140)), MOUSE_BUTTON_LEFT)
	eq([w.top[0], w.sel[0]], [2, 9], "点下翻页箭头 = Q/E 下翻: 选中跳 7 格, 顶行跟随")
	_click(r, row.call(0, 0))
	check(w._menu != null, "点行 = 选中并确认: 打开三选项菜单")
	var menu_row := func(k: int) -> Vector2:
		return _scr(w._menu, Vector2(20, 9 + 13 * k + 4))
	_move(r, menu_row.call(2))
	eq(w._menu_sel, 2, "菜单: 悬停 = 箭头跟随")
	_click(r, Vector2(1270, 790))
	check(w._menu == null, "点菜单外 = 关菜单")
	_click(r, row.call(0, 0))
	_click(r, menu_row.call(2))
	check(w._ask != null, "点「丢弃」= 弹出是/否框")
	var n: int = w.inv.col(0)["items"].size()
	var rect := UiPanel.frame_rect(CampAsk.YesNo.DIR, 0)
	_click(r, _scr(w._ask, rect.position + rect.size * Vector2(0.25, 0.5)))
	eq(w.inv.col(0)["items"].size(), n - 1, "点 ○ = 确认丢弃")
	r.free()
	_cleanup()
	Game.state.bag = bag0
	Game.state.party = party0


func test_icon_menu_and_list_menu_components():
	if not _assets_ready():
		check(true)
		return
	var l := _layer()
	var m := UiIconMenu.new()
	l.add(m)
	m.position = Vector2(100, 80)
	m.setup(UiIconMenu.ACTION_FRAMES, [false, true, true, true, true], UiIconMenu.ACTION_DISABLED, 2)
	var s := Screen.new(m)
	var r = _router(s)
	_move(r, _scr(m, Vector2(m.step * 4 + 10, 10)))
	eq(m.selected, 4, "图标菜单: 悬停跟随")
	_move(r, _scr(m, Vector2(10, 10)))
	eq(m.selected, 4, "禁用项悬停不选中")
	_click(r, _scr(m, Vector2(m.step * 1 + 10, 10)))
	eq([m.selected, s.log], [1, ["confirm"]], "点图标 = 选中并确认 (确认作为普通动作交给界面)")
	r.free()
	var lst := UiListMenu.new()
	l.add(lst)
	lst.setup(UiListMenu.SPELL, UiListMenu.spell_rows([1, 2, 3, 4, 5, 6]), 0)
	lst.visible = true
	var s2 := Screen.new(lst)
	var r2 = _router(s2)
	var p := _scr(lst, UiListMenu.panel_pos(lst.layout) + lst.slot_pos(5) + Vector2(4, 4))
	_move(r2, p)
	eq(lst.selected, 5, "列表: 悬停跟随 (第二列)")
	r2.free()
	_cleanup()


## 格子型命中区的假组件 (战场地图那类): 拖动要留给界面卷镜头, 不能被当列表滚动
class GridComp:
	extends Node2D
	func ui_hits() -> Array:
		return [UiHit.area(Rect2(0, 0, 100, 100), Vector2i.ZERO, null, UiAction.CONFIRM, Vector2(10, 10))]


## 真实的触摸事件 (InputEventScreenTouch / InputEventScreenDrag) 走完整的 _handle 路径 (Windows/Linux 触摸屏、手机都是这套事件)
func _finger(r, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = pressed
	r._handle(e)


func _finger_drag(r, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = rel
	r._handle(e)


func _touch_drag(r, from: Vector2, to: Vector2, steps := 6) -> void:
	_finger(r, from, true)
	var prev := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		_finger_drag(r, p, p - prev)
		prev = p
	_finger(r, to, false)


## 触摸在竖排列表上拖动 = 滚动: 每拖过一行一步 ↑/↓ (手指向下 = 选中项上移), 抬手不再确认; 横向拖不当列表滚动; 格子型 (战场地图) 不抢
func test_touch_drag_scrolls_lists():
	if not _assets_ready():
		check(true)
		return
	var l := _layer()
	var lst := UiListMenu.new()
	l.add(lst)
	lst.setup(UiListMenu.SPELL, UiListMenu.spell_rows([1, 2, 3, 4, 5, 6]), 0)
	lst.visible = true
	var s := Screen.new(lst)
	var r = _router(s)
	_tree().root.add_child(r)   # 触摸模式要建虚拟键层, 需要在树里
	r.set_touch_mode(true)
	var p0 := _scr(lst, UiListMenu.panel_pos(lst.layout) + lst.slot_pos(0) + Vector2(4, 4))
	var pitch := _scr(lst, UiListMenu.panel_pos(lst.layout) + lst.slot_pos(1) + Vector2(4, 4)).y - p0.y
	check(pitch > 8.0, "行距换算成视口像素 > 0")
	_move(r, p0)   # 先悬停 (防误触: 组件刚出现 0.4 秒内未悬停过的点按不算)
	s.log.clear()
	_touch_drag(r, p0, p0 + Vector2(0, pitch * 2.5))
	eq([s.log.count("up"), s.log.count("down"), s.log.has("confirm")], [2, 0, false], "手指向下拖 2.5 行 = 2 步「上」(选中项上移), 抬手不确认")
	s.log.clear()
	_touch_drag(r, p0 + Vector2(0, pitch * 2), p0)   # 反方向拖回去
	eq([s.log.count("down"), s.log.count("up"), s.log.has("confirm")], [2, 0, false], "反方向拖回去 = 2 步「下」, 同样按行距步进")
	s.log.clear()
	_touch_drag(r, p0, p0 + Vector2(pitch * 3, 4))   # 横向
	check(s.log.count("up") + s.log.count("down") == 0, "横向拖动不当列表滚动 (留给左右快滑翻页)")
	r.free()
	# 格子型: 不当列表
	var g := GridComp.new()
	_tree().root.add_child(g)
	_nodes.append(g)
	var r2 = _router(Screen.new(g))
	eq(r2._list_pitch(Vector2(5, 5), Vector2(0, 30)), 0.0, "格子型命中区 (战场地图) 不当列表滚动")
	r2.free()
	_cleanup()


## --aspect 宽屏: 整页居中的界面平移 (逻辑画面 356x200 时安全区右移 18), 指针换算跟着锚点走
func test_widescreen_anchor_offset():
	if not _assets_ready():
		check(true)
		return
	var sl = _tree().root.get_node("ScreenLayout")
	var size0: Vector2 = sl.size
	sl.size = Vector2(356, 200)
	sl.changed.emit()
	var l := _layer()
	var sw := CampSaveWindow.new(true)
	l.add(sw)
	var r = _router(Screen.new(sw))
	var off: Vector2 = sl.offset(ScreenLayout.SAFE)
	eq(off, Vector2(18, 0), "安全区居中偏移")
	_move(r, (off + Vector2(3 + 60, 30 + 33 * 3 + 10)) * Assets.SCALE)
	eq(sw.sel, 3, "按锚点偏移后的坐标命中第 3 档")
	_move(r, (Vector2(3 + 5, 30 + 33 * 1 + 10)) * Assets.SCALE)
	eq(sw.sel, 3, "不加偏移的坐标落在界面外 (不命中)")
	r.free()
	_cleanup()
	sl.size = size0
	sl.changed.emit()


func test_choice_box_hover_click():
	if not _assets_ready():
		check(true)
		return
	var cb := ChoiceBox.new()
	_tree().root.add_child(cb)
	_nodes.append(cb)
	var got := []
	cb.chosen.connect(func(v): got.append(v))
	cb.ask("是否要丢弃?", "是", "否", false)  # 不 await: 打开后等 chosen
	var r = _router(cb)
	eq(cb._sel, 1, "默认否")
	var yes: UiText = cb._opts[0]  # 原版坐标的文字节点
	_move(r, _scr(yes, Vector2(2, 2)))
	eq(cb._sel, 0, "悬停「是」")
	_click(r, _scr(yes, Vector2(-6, 5)))
	eq(got, [true], "点「是」的图标/文字 = 是")
	r.free()
	InputRouter.pop(cb)
	_cleanup()


func test_spirit_arrows_and_alloc():
	if not _assets_ready():
		check(true)
		return
	var party0: Dictionary = Game.state.party.duplicate(true)
	Game.state.party = {}
	for uid in [0, 1]:
		Game.state.party[uid] = {"lv": 1, "items": [], "gear": {}, "skills": [], "spirit_points": 5,
			"spirit": {"迅": 1, "烈": 1, "神": 1, "魔": 1, "魂": 1}, "stats": {}}
	var l := _layer()
	var sp := CampSpirit.new([0, 1])
	l.add(sp)
	var r = _router(Screen.new(sp))
	var ar := UiPanel.frame_rect("Misc/SP_REV", 18)
	_click(r, _scr(sp._ar, ar.get_center()))
	eq(sp.who, 1, "点右箭头 = 换下一人")
	_click(r, _scr(sp._panel, Vector2(30, 20)))
	check(sp.allocating, "点面板 = 进入分配")
	_move(r, _scr(sp._panel, Vector2(11 + 28 * 2 + 10, 60)))
	eq(sp.msel, 2, "悬停第 2 魂的柱 = 选中")
	var ur := UiPanel.frame_rect("Misc/SP_REV", 22)
	_click(r, _scr(sp._panel, ur.get_center() + Vector2(11 + 28 * 3, 36)))
	eq([sp.msel, sp.added[1][3]], [3, 1], "点第 3 魂的上箭头 = 选中并加一点")
	_click(r, Vector2(5, 5))
	check(not sp.allocating, "点面板外 = 分配结束")
	var asked := []
	sp.guide_requested.connect(func(uid): asked.append(uid))
	sp.key("space")
	sp.key("right")
	sp.key("space")
	eq(asked, [1, 0], "查看键 / 空格 = 请求当前这个人的五魂攻略页 (换人后换页)")
	r.free()
	_cleanup()
	Game.state.party = party0


## 触摸虚拟键 (--touch / 手机, 手游式): 圆形摇杆 (STICK) + 确认/取消 (两个一样大) + 显示开关 + 设置钮 (没有菜单键和查看键: 2026-10-25 去掉, 查看靠长按); 每个键的中心点命中它自己
func test_touch_pad_keys_and_hits():
	var pad = load("res://engine/input/touch_pad.gd").new()
	_tree().root.add_child(pad)
	_nodes.append(pad)
	check(not pad.shown, "缺省隐藏整套键 (只剩显/设置钮)")
	pad.toggle()
	var kinds := []
	for k in pad.keys():
		eq(pad.hit(k["c"]), int(k["kind"]), "键 %d 的中心命中它自己" % int(k["kind"]))
		kinds.append(int(k["kind"]))
	kinds.sort()
	var want := [UiAction.CONFIRM, UiAction.CANCEL, pad.TOGGLE, pad.SETTINGS]
	want.sort()
	eq(kinds, want, "虚拟键集合 (方向由摇杆给; 翻页没有键, 靠左右快滑; 没有菜单键和查看键)")
	var rs := []
	for k in pad.keys():
		if int(k["kind"]) in [UiAction.CONFIRM, UiAction.CANCEL]:
			rs.append(float(k["r"]))
	check(rs.size() == 2 and is_equal_approx(rs[0], rs[1]), "确认 / 取消两个键一样大")
	eq(pad.hit(pad._stick_c), pad.STICK, "摇杆底盘中心命中摇杆")
	eq(pad.hit(Vector2(-5000, -5000)), UiAction.NONE, "空处不命中")
	# 键不重叠: 任意两个键的中心距 >= 半径之和 (拇指不会误触邻键)
	var ks: Array = pad.keys()
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			check((ks[i]["c"] as Vector2).distance_to(ks[j]["c"]) >= float(ks[i]["r"]) + float(ks[j]["r"]) - 0.5, "键 %d 与 %d 不重叠" % [ks[i]["kind"], ks[j]["kind"]])
	pad.shown = false
	var any_hit := false
	for k in pad.keys():
		if int(k["kind"]) != pad.TOGGLE and int(k["kind"]) != pad.SETTINGS and pad.hit(k["c"]) != UiAction.NONE:
			any_hit = true
	check(not any_hit and pad.hit(pad._stick_c) == UiAction.NONE, "整套键隐藏后只有开关钮和设置钮有效 (摇杆也不响应)")


## 摇杆: 取主方向 (四向), 死区内无方向, 斜推粘滞, 圆钮限幅, 松手回中
func test_touch_stick_directions():
	var pad = load("res://engine/input/touch_pad.gd").new()
	_tree().root.add_child(pad)
	_nodes.append(pad)
	var c: Vector2 = pad._stick_c
	var r: float = pad._stick_r
	eq(pad.stick_dir(c + Vector2(r * 0.1, 0)), UiAction.NONE, "死区内没有方向")
	eq(pad.stick_dir(c + Vector2(r * 0.6, 0)), UiAction.RIGHT, "右")
	eq(pad.stick_dir(c + Vector2(-r * 0.6, 0)), UiAction.LEFT, "左")
	eq(pad.stick_dir(c + Vector2(0, -r * 0.6)), UiAction.UP, "上 (屏幕 y 向下为正)")
	eq(pad.stick_dir(c + Vector2(0, r * 0.6)), UiAction.DOWN, "下")
	pad.stick_dir(c + Vector2(r * 0.6, 0))
	eq(pad.stick_dir(c + Vector2(r * 0.6, r * 0.65)), UiAction.RIGHT, "斜推: 当前方向 (右) 粘滞, 另一轴没超过 1.25 倍不换")
	eq(pad.stick_dir(c + Vector2(r * 0.5, r * 0.8)), UiAction.DOWN, "另一轴超过 1.25 倍才换方向")
	pad.stick_dir(c + Vector2(r * 3, 0))
	check(pad._knob.length() <= r * pad.KNOB_TRAVEL + 0.01, "圆钮偏移限幅在底盘内")
	pad.stick_release()
	eq(pad._knob, Vector2.ZERO, "松手回中")
	eq(pad._stick_dir, UiAction.NONE)

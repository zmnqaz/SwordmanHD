# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 统一输入层 (engine/input/): 按住连发、触摸手势、按键翻译、界面栈分发

const Router = preload("res://engine/input/input_router.gd")


class Rec:
	extends RefCounted
	var log: Array = []
	var consume := true
	func ui_action(a: UiAction) -> bool:
		log.append(a.name() + ("*" if a.echo else ""))
		return consume


func _router():
	var r = Router.new()
	return r


func _key(code: int, pressed := true, echo := false, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	e.shift_pressed = shift
	return e


class F2Map:
	extends RefCounted
	var opened := 0
	func ui_f2() -> bool:
		opened += 1
		return true


class SigRec:
	extends RefCounted
	var settings := 0
	var skip := 0
	var guide := 0
	func on_guide() -> void:
		guide += 1
	func on_settings() -> void:
		settings += 1
	func on_skip() -> void:
		skip += 1


## 战场地图默认键 M (可改键; 原版是 F2, 现在 F2 是攻略); 设定 = F1 (F10 一直同效)。栈顶不处理地图键时不开设定面板, 也不吞键
func test_map_key_is_battle_map_only_and_f1_f10_open_settings():
	var r = _router()
	var sig := SigRec.new()
	r.settings_requested.connect(sig.on_settings)
	r.guide_requested.connect(sig.on_guide)
	eq(r._handle(_key(KEY_M)), false, "没有接收方处理地图键: 不吞键")
	eq(sig.settings, 0, "M 不打开设定面板")
	var m := F2Map.new()
	r.push(m)
	eq(r._handle(_key(KEY_M)), true, "战场空闲态 M 归地图")
	eq(m.opened, 1, "栈顶 ui_f2 被调用")
	eq(sig.settings, 0, "M 开地图时也不开设定")
	eq(r._handle(_key(KEY_F10)), true, "F10 吞键")
	eq(sig.settings, 1, "F10 打开设定面板")
	eq(r._handle(_key(KEY_F1)), true, "F1 吞键")
	eq(sig.settings, 2, "F1 打开设定面板")
	r._handle(_key(KEY_F2))
	r._handle(_key(KEY_F4))
	eq(sig.guide, 2, "F2 / F4 开关攻略")
	r.free()


func test_key_repeat_hold_half_second():
	# 原版 实测: 第一格立即, 之后每 0.2 秒一格, 没有 0.5 秒初始延迟
	var k := KeyRepeat.new()
	eq(k.press(UiAction.RIGHT), [UiAction.RIGHT], "首次按下立即走一格")
	eq(k.tick(0.15), [], "0.2 秒内不连发")
	eq(k.tick(0.05), [UiAction.RIGHT], "满 0.2 秒走第二格")
	eq(k.tick(0.45).size(), 2, "之后每 0.2 秒一格")
	eq(k.press(UiAction.RIGHT), [], "已按住的不重复")
	k.press(UiAction.UP)
	eq(k.current(), UiAction.UP, "后按的方向优先")
	eq(k.tick(0.15), [], "换方向重新计时")
	k.release(UiAction.UP)
	eq(k.current(), UiAction.RIGHT, "松开后回到仍按住的方向")
	k.release(UiAction.RIGHT)
	eq(k.tick(1.0), [], "全部松开后不再连发")


func test_key_repeat_per_screen_interval():
	# w5 项 6 (原版 轮询日志): 换栏/换人动画做完才再读键, 连发间隔按界面给 (物品窗 ←/→ 21 帧, 体态观览/五魂换人 15 帧)
	var k := KeyRepeat.new()
	k.press(UiAction.RIGHT)
	eq(k.tick(0.5, 0.6), [], "0.6 秒间隔: 0.5 秒内不连发")
	eq(k.tick(0.1, 0.6), [UiAction.RIGHT], "满 0.6 秒一次")
	eq(k.tick(0.5, 0.6), [], "下一次要再等 0.6 秒")
	eq(k.tick(0.1, 0.6), [UiAction.RIGHT])
	check(CampItemWindow.CYCLE_REPEAT > 0.8 and CampItemWindow.CYCLE_REPEAT < 0.9, "物品窗 ←/→ 换栏 21 帧")
	check(UiProfile.SWITCH_REPEAT == 0.6 and CampSpirit.SWITCH_REPEAT == 0.6, "换人 15 帧")


func test_key_repeat_stall_does_not_burst():
	var k := KeyRepeat.new()
	k.press(UiAction.DOWN)
	check(k.tick(5.0).size() <= KeyRepeat.MAX_PER_TICK, "卡顿 5 秒后一帧只补发有限几次")
	eq(k.tick(0.05), [], "余量被丢弃, 不会下一帧接着补")
	eq(k.tick(0.2).size(), 1, "之后恢复每 0.2 秒一格")


func test_touch_tap_long_press_drag_swipe_two_finger():
	var g := TouchGestures.new()
	g.touch_down(0, Vector2(100, 100), 0.0)
	var out: Array = g.touch_up(0, Vector2(104, 102), 0.2)
	eq(out.size(), 1, "点按一个动作")
	eq(out[0].kind, UiAction.CONFIRM, "点按 = 确认")
	eq(out[0].pos, Vector2(104, 102), "点哪选哪: 带坐标")
	# 长按
	g.touch_down(0, Vector2(50, 50), 1.0)
	eq(g.tick(1.3), [], "未到 0.5 秒")
	out = g.tick(1.5)
	eq(out.size() == 1 and out[0].kind == UiAction.INFO, true, "长按 0.5 秒 = 查看")
	out = g.touch_up(0, Vector2(50, 50), 2.0)
	eq(out[0].kind, UiAction.INFO_UP, "长按松开")
	# 拖动
	g.touch_down(0, Vector2(200, 200), 3.0)
	eq(g.touch_move(0, Vector2(210, 200), 3.1), [], "阈值内不算拖动")
	out = g.touch_move(0, Vector2(260, 230), 3.2)
	eq(out[0].kind, UiAction.DRAG, "超过阈值 = 拖动")
	eq(out[0].delta, Vector2(60, 30), "首次拖动的位移从按下点算")
	out = g.touch_move(0, Vector2(270, 240), 3.3)
	eq(out[0].delta, Vector2(10, 10), "之后按每次移动")
	eq(g.tick(4.0), [], "拖动中不触发长按")
	out = g.touch_up(0, Vector2(270, 240), 4.5)
	eq(out, [], "慢拖松开不出动作")
	# 左滑翻页
	g.touch_down(0, Vector2(600, 300), 5.0)
	g.touch_move(0, Vector2(500, 305), 5.1)
	out = g.touch_up(0, Vector2(400, 310), 5.2)
	eq(out.size() == 1 and out[0].kind == UiAction.PAGE_DOWN, true, "快速左滑 = 下一页")
	g.touch_down(0, Vector2(400, 300), 6.0)
	g.touch_move(0, Vector2(560, 300), 6.1)
	out = g.touch_up(0, Vector2(560, 300), 6.15)
	eq(out[0].kind, UiAction.PAGE_UP, "快速右滑 = 上一页")
	# 双指点按
	g.touch_down(0, Vector2(300, 300), 7.0)
	g.touch_down(1, Vector2(500, 300), 7.05)
	eq(g.touch_up(0, Vector2(300, 300), 7.1), [], "第一指松开时还不出")
	out = g.touch_up(1, Vector2(500, 300), 7.12)
	eq(out.size() == 1 and out[0].kind == UiAction.CANCEL, true, "双指点按 = 取消")
	eq(g.tick(9.0), [], "手势结束后无残留")


func test_router_stack_and_passthrough():
	var r = _router()
	var a := Rec.new()
	var b := Rec.new()
	r.push(a)
	r.push(b)
	r.dispatch(UiAction.of(UiAction.CONFIRM))
	eq(b.log, ["confirm"], "栈顶收到")
	eq(a.log, [], "下层收不到")
	b.consume = false
	r.dispatch(UiAction.of(UiAction.CANCEL))
	eq(a.log, ["cancel"], "栈顶不处理时交给下一层")
	r.pop(b)
	r.dispatch(UiAction.of(UiAction.INFO))
	eq(a.log, ["cancel", "info"], "出栈后下层成为栈顶")
	r.push(a)
	eq(r._stack.size(), 1, "重复入栈不重复")
	r.free()


func test_router_overlay_stays_on_top():
	# 模态浮层 (F2 设定面板) 打开后, 下层 (对白框等) 再入栈不能把输入抢走; 浮层关闭后下层照常可用
	var r = _router()
	var scene := Rec.new()
	var dlg := Rec.new()
	var panel := Rec.new()
	r.push(scene)
	r.push(dlg)
	r.push(panel, true)
	eq(r.top(), panel, "浮层在栈顶")
	r.dispatch(UiAction.of(UiAction.CONFIRM))
	eq(panel.log, ["confirm"], "浮层收到输入")
	eq(dlg.log, [], "对白框收不到")
	var dlg2 := Rec.new()
	r.push(dlg2)  # 浮层打开期间对白推进到下一句
	eq(r.top(), panel, "后入栈的对白框不压过浮层")
	r.push(dlg)   # 重复入栈 (对白框再次 show_text)
	eq(r.top(), panel, "重复入栈也不压过浮层")
	check(r.overlay_open(), "有浮层打开")
	r.dispatch(UiAction.of(UiAction.CANCEL))
	eq(dlg.log, [], "对白框仍收不到")
	r.pop(panel)
	check(not r.overlay_open(), "浮层关闭")
	eq(r.top(), dlg, "关闭后对白框是栈顶 (最后入栈的普通接收方)")
	r.dispatch(UiAction.of(UiAction.CONFIRM))
	eq(dlg.log, ["confirm"], "关闭浮层后对白继续可用")
	r.pop(dlg)
	r.pop(dlg2)
	eq(r.top(), scene, "栈顺序保持")
	r.free()


func test_router_pointer_not_leaking_below_overlay():
	# 鼠标: 浮层之外的点击/悬停归浮层 (模态), 不穿到下层
	var r = _router()
	var below := Rec.new()
	var panel := Rec.new()
	r.push(below)
	r.push(panel, true)
	r.dispatch(UiAction.new(UiAction.CONFIRM, "mouse", Vector2(10, 10)))
	eq(panel.log, ["confirm"], "点击归浮层")
	eq(below.log, [], "下层没有收到点击")
	r.free()


func test_router_keyboard_mapping():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	for code in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_C, KEY_F, KEY_Q, KEY_E, KEY_TAB]:
		r._handle(_key(code))
		r._handle(_key(code, false))
	eq(a.log, ["confirm", "confirm", "cancel", "cancel", "info", "info_up",
		"page_up", "page_down", "switch"], "原版键位 + 扩展")
	a.log.clear()
	r._handle(_key(KEY_SPACE))
	r._handle(_key(KEY_SPACE, false))
	eq(a.log, ["select", "select_up"], "空格: 按下/松开 (营地按住预览)")
	a.log.clear()
	r._handle(_key(KEY_W))
	r._handle(_key(KEY_W, true, true))
	eq(a.log, ["up"], "WASD 方向; 系统自动重复忽略")
	r._process(0.2)
	eq(a.log, ["up", "up*"], "按住 0.2 秒连发 (echo)")
	eq(r.held_dir(), Vector2i(0, -1), "按住的方向 (城镇行走)")
	r._handle(_key(KEY_W, false))
	eq(r.held_dir(), Vector2i.ZERO, "松开")
	# 城镇行走: 同时按住多个方向, 固定优先级 上>下>左>右, 与按下先后无关
	r._handle(_key(KEY_RIGHT))
	r._handle(_key(KEY_LEFT))
	eq(r.held_dir_by_priority(RpgStage.KEY_PRIORITY), Vector2i(-1, 0), "右后左: 左优先于右")
	r._handle(_key(KEY_DOWN))
	eq(r.held_dir_by_priority(RpgStage.KEY_PRIORITY), Vector2i(0, 1), "下优先于左右")
	r._handle(_key(KEY_UP))
	eq(r.held_dir_by_priority(RpgStage.KEY_PRIORITY), Vector2i(0, -1), "上最优先")
	r._handle(_key(KEY_UP, false))
	eq(r.held_dir_by_priority(RpgStage.KEY_PRIORITY), Vector2i(0, 1), "松开上回到下")
	for k in [KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		r._handle(_key(k, false))
	eq(r.held_dir_by_priority(RpgStage.KEY_PRIORITY), Vector2i.ZERO, "全松开")
	check(not r._handle(_key(KEY_X)), "未映射的键不吃掉")
	r.free()


func test_router_action_events_and_mouse():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	for name in ["ui_accept", "ui_cancel", "info", "menu", "ui_down"]:
		var e := InputEventAction.new()
		e.action = name
		e.pressed = true
		r._handle(e)
	eq(a.log, ["confirm", "cancel", "info", "menu", "down"], "自动测试注入的动作")
	var up := InputEventAction.new()
	up.action = "ui_down"
	up.pressed = false
	r._handle(up)
	a.log.clear()
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_RIGHT
	m.pressed = true
	r._handle(m)
	m = InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	m.position = Vector2(320, 240)
	r._handle(m)
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(400, 300)
	r._handle(mm)
	eq(a.log, ["cancel", "confirm", "point"], "右键取消, 左键确认, 移动 = 指向")
	# --touch: 鼠标按触摸处理, 点按在松开时确认
	r.emulate_touch = true
	a.log.clear()
	m = InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	m.position = Vector2(100, 100)
	r._handle(m)
	eq(a.log, [], "按下时不出动作")
	m = m.duplicate()
	m.pressed = false
	r._handle(m)
	eq(a.log, ["confirm"], "松开 = 点按确认")
	m = m.duplicate()
	m.pressed = true
	r._handle(m)
	r._process(0.6)
	eq(a.log, ["confirm", "info"], "按住 0.5 秒 = 长按查看")
	r.free()


func test_camp_key_names():
	eq(UiAction.of(UiAction.CONFIRM).camp_key(), "accept")
	eq(UiAction.of(UiAction.SWITCH).camp_key(), "tab")
	eq(UiAction.of(UiAction.SELECT).camp_key(), "space")
	eq(UiAction.of(UiAction.INFO_UP).camp_key(), "space_up", "触摸长按松开 = 关预览")
	eq(UiAction.of(UiAction.POINT).camp_key(), "")
	check(UiAction.of(UiAction.SELECT).is_confirm(), "空格在一般画面等同确认")


func _joy(btn: int, pressed := true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = pressed
	return e


func _stick(axis: int, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return e


func _axis(axis: int, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return e


func test_pad_swap_preset_and_overrides():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	r.set_pad("swap", {})
	r._handle(_joy(JOY_BUTTON_A))
	r._handle(_joy(JOY_BUTTON_B))
	eq(a.log, ["cancel", "confirm"], "交换预设: A 取消, B 确认")
	a.log.clear()
	r.set_pad("std", {"menu": JOY_BUTTON_A})
	r._handle(_joy(JOY_BUTTON_A))
	eq(a.log, ["confirm", "menu"], "覆盖: A 同时是确认和菜单 (按 ACTIONS 顺序派发)")
	a.log.clear()
	r._handle(_joy(JOY_BUTTON_Y))
	eq(a.log, [], "Y 被改走后不再是菜单")
	r.free()


func test_pad_triggers_are_virtual_buttons():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	r._handle(_axis(JOY_AXIS_TRIGGER_LEFT, 0.9))
	eq(a.log, ["switch"], "LT = 营地切栏")
	r._handle(_axis(JOY_AXIS_TRIGGER_LEFT, 0.9))
	r._handle(_axis(JOY_AXIS_TRIGGER_LEFT, 0.4))
	eq(a.log.size(), 1, "按住不重复触发, 0.3~0.5 之间保持按下")
	r._handle(_axis(JOY_AXIS_TRIGGER_LEFT, 0.0))
	r._handle(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.8))
	eq(a.log, ["switch"], "RT 没有绑定动作; 松开 LT 不派发动作")
	r.free()


func test_pad_settings_map_and_skip_buttons():
	var r = _router()
	var sig := SigRec.new()
	r.settings_requested.connect(sig.on_settings)
	r.skip_dialog_toggled.connect(sig.on_skip)
	r._handle(_joy(JOY_BUTTON_START))
	eq(sig.settings, 1, "Start 打开设定面板")
	r._handle(_joy(JOY_BUTTON_START, false))
	eq(sig.settings, 1, "松开不触发")
	r._handle(_joy(JOY_BUTTON_LEFT_STICK))
	eq(sig.skip, 1, "L3 切换跳过对白")
	var m := F2Map.new()
	r.push(m)
	r._handle(_joy(JOY_BUTTON_BACK))
	eq(m.opened, 1, "Back = F2 战场地图 (问栈顶 ui_f2)")
	r.free()


func test_pad_capture_swallows_next_button():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	var got := []
	r.pad_capture = func(b: int): got.append(b)
	r._handle(_joy(JOY_BUTTON_A))
	r._handle(_joy(JOY_BUTTON_A, false))
	r._handle(_joy(JOY_BUTTON_DPAD_UP))
	r._handle(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.9))
	eq(got, [JOY_BUTTON_A, PadMap.TRIGGER_R], "捕获期间只回报可绑定键 (A 与 RT), 十字键不可绑")
	eq(a.log, [], "捕获期间手柄键不当游戏动作派发")
	r.pad_capture = Callable()
	r._handle(_joy(JOY_BUTTON_A))
	eq(a.log, ["confirm"], "捕获结束恢复")
	r.free()


## 手柄映射 (标准预设, docs/设计_输入映射与战场辅助.md §2): A 确认, B 取消, X 查看, Y 菜单, LB/RB 翻页; Start = 设定, Back = 战场地图 (不再是菜单/取消)
func test_gamepad_mapping():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		r._handle(_joy(b))
		r._handle(_joy(b, false))
	eq(a.log, ["confirm", "cancel", "info", "info_up", "menu", "page_up", "page_down"], "手柄按钮布局 (X 有松开动作)")
	r._handle(_joy(JOY_BUTTON_START))
	r._handle(_joy(JOY_BUTTON_BACK))
	eq(a.log.size(), 7, "Start / Back 不再派发菜单/取消动作")
	a.log.clear()
	for b in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		r._handle(_joy(b))
		r._handle(_joy(b, false))
	eq(a.log, ["up", "down", "left", "right"], "手柄十字键")
	a.log.clear()
	r._handle(_stick(JOY_AXIS_LEFT_X, 0.9))
	r._handle(_stick(JOY_AXIS_LEFT_X, 0.0))
	r._handle(_stick(JOY_AXIS_LEFT_Y, -0.9))
	r._handle(_stick(JOY_AXIS_LEFT_Y, 0.0))
	r._handle(_stick(JOY_AXIS_LEFT_X, 0.3))
	eq(a.log, ["right", "up"], "左摇杆过死区取主方向, 死区内无动作")
	r._handle(_stick(JOY_AXIS_LEFT_X, 0.8))
	r._handle(_stick(JOY_AXIS_LEFT_Y, 0.6))
	eq(r.held_dir(), Vector2i(1, 0), "摇杆斜推取主方向 (四向)")
	r.free()


## 键盘全键 (原版按键: Enter Esc/Delete Space PgUp PgDn 方向 Tab F1 小键盘+/−)
func test_keyboard_full_set():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	var want := {KEY_UP: "up", KEY_W: "up", KEY_DOWN: "down", KEY_S: "down", KEY_LEFT: "left", KEY_A: "left", KEY_RIGHT: "right", KEY_D: "right",
		KEY_ENTER: "confirm", KEY_KP_ENTER: "confirm", KEY_ESCAPE: "cancel", KEY_C: "cancel", KEY_DELETE: "cancel", KEY_BACK: "cancel",
		KEY_F: "info", KEY_Q: "page_up", KEY_PAGEUP: "page_up", KEY_E: "page_down", KEY_PAGEDOWN: "page_down",
		KEY_TAB: "switch"}
	for code in want:
		a.log.clear()
		r._handle(_key(code))
		eq(a.log[0] if a.log.size() >= 1 else "", want[code], "键 %s" % OS.get_keycode_string(code))
		r._handle(_key(code, false))
		r.repeat.clear()
	for code in [KEY_X, KEY_Z, KEY_F5, KEY_F6, KEY_G, KEY_H]:
		check(not r._handle(_key(code)), "未映射的键 %s 不吃掉" % OS.get_keycode_string(code))
	r.free()


## 触屏设置钮: 点一下发 settings_requested (桌面是 F10, 触屏没有键盘); 操作盘隐藏时也能点; 不发按键动作
func test_touch_settings_button_opens_settings():
	var r = _router()
	(Engine.get_main_loop() as SceneTree).root.add_child(r)
	r.set_touch_mode(true)
	var sig := SigRec.new()
	r.settings_requested.connect(sig.on_settings)
	var rec := Rec.new()
	r.push(rec)
	var c := Vector2.ZERO
	for k in r._buttons.keys():
		if int(k["kind"]) == r._buttons.SETTINGS:
			c = k["c"]
	check(c != Vector2.ZERO, "操作盘上有设置钮")
	eq(r._hit_button(c), r._buttons.SETTINGS, "点中设置钮")
	eq(sig.settings, 1, "点设置钮 = 打开设定面板")
	eq(rec.log.size(), 0, "设置钮不产生按键动作")
	r._release_button(r._buttons.SETTINGS)
	r._buttons.shown = false
	r._hit_button(c)
	eq(sig.settings, 2, "操作盘隐藏后设置钮仍可点")
	r.free()


# ---------------------------------------------------------------- 回放期间屏蔽真实输入 (回放锁)
## 回放时真实键盘/鼠标/手柄/触摸不能混进回放的指令流 (用户: 回放时动鼠标会把指令打乱); 只放行打开设定面板 (暂停/调速/结束回放)

func _mouse_move(pos: Vector2) -> InputEventMouseMotion:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	return mm


func test_replay_lock_swallows_live_input():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	r.replay_lock = true
	eq(r._handle(_key(KEY_DOWN)), true, "方向键被吞")
	eq(r._handle(_key(KEY_ENTER)), true, "回车被吞")
	eq(r._handle(_mouse_move(Vector2(300, 200))), true, "鼠标移动被吞")
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = true
	m.position = Vector2(300, 200)
	eq(r._handle(m), true, "鼠标点击被吞")
	eq(r._handle(_joy(JOY_BUTTON_A)), true, "手柄键被吞")
	eq(a.log, [], "界面一个真实输入都没收到")
	r.replay_lock = false
	r._handle(_mouse_move(Vector2(310, 210)))
	r._handle(_key(KEY_DOWN))
	check(a.log.size() >= 1, "关锁后恢复正常: %s" % str(a.log))
	r.free()


func test_replay_lock_lets_settings_through():
	var r = _router()
	var sig := SigRec.new()
	r.settings_requested.connect(sig.on_settings)
	r.skip_dialog_toggled.connect(sig.on_skip)
	r.replay_lock = true
	r._handle(_key(KEY_F10))
	eq(sig.settings, 1, "F10 照常打开设定面板")
	r._handle(_joy(JOY_BUTTON_START))
	eq(sig.settings, 2, "手柄 Start 照常")
	r._handle(_key(KEY_F3))
	eq(sig.skip, 0, "F3 跳过对白会改游戏进程: 回放时不行")
	var m := F2Map.new()
	r.push(m)
	r._handle(_key(KEY_M))
	eq(m.opened, 0, "战场地图键也不行")
	r.free()


func test_replay_lock_off_while_overlay_open():
	var r = _router()
	var base := Rec.new()
	var panel := Rec.new()
	r.push(base)
	r.push(panel, true)
	r.replay_lock = true
	r._handle(_key(KEY_DOWN))
	eq(panel.log, ["down"], "设定面板开着: 键盘照常用它 (回放此时是冻结的)")
	eq(base.log, [], "不会漏到游戏")
	r.free()


func test_replay_lock_drops_held_repeat():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	r._handle(_key(KEY_DOWN))          # 回放开始前按着方向键
	a.log.clear()
	r.replay_lock = true
	r._process(1.0)
	eq(a.log, [], "开锁前按着的键不会在回放里连发")
	r.free()


## 没有「选目标跳转」: Tab 只是切栏; 小键盘 + / − 不再有动作 (2026-10-25 删除); 没绑 Shift+X 的键带着 Shift 仍按 X 处理
func test_tab_is_only_switch_and_numpad_plus_minus_do_nothing():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	r._handle(_key(KEY_TAB))
	eq(a.log, ["switch"], "Tab: 只是切栏")
	a.log.clear()
	r._handle(_key(KEY_TAB, true, false, true))
	eq(a.log, ["switch"], "Shift+Tab 没绑: 按 Tab 处理")
	a.log.clear()
	check(not r._handle(_key(KEY_KP_ADD)) and not r._handle(_key(KEY_KP_SUBTRACT)), "小键盘 + / − 不吃键")
	eq(a.log, [], "小键盘 + / − 没有动作")
	r._handle(_key(KEY_ENTER, true, false, true))
	eq(a.log, ["confirm"], "没绑 Shift+X 的键带着 Shift 仍按 X 处理")
	r.free()


## 键盘改键: 只换主键, 别名保留; 改完旧主键不再触发
func test_key_remap_replaces_primary_keeps_aliases():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	r.set_keys({"page_up": KEY_N, "info": KEY_G})
	r._handle(_key(KEY_N))
	eq(a.log, ["page_up"], "新主键生效")
	a.log.clear()
	check(not r._handle(_key(KEY_Q)), "旧主键不再是上一页")
	eq(a.log, [], "旧主键没有动作")
	r._handle(_key(KEY_PAGEUP))
	eq(a.log, ["page_up"], "别名 (PageUp) 保留")
	a.log.clear()
	r._handle(_key(KEY_G))
	eq(a.log, ["info"], "info 改绑到 G")
	r.set_keys({})
	a.log.clear()
	r._handle(_key(KEY_Q))
	eq(a.log, ["page_up"], "清掉覆盖项回到默认")
	r.free()


## 改键捕获: 开着时按键 (除 Esc) 只回报键值, 不当游戏动作; Shift 带进键值; 方向键与修饰键本身也回报/忽略
func test_key_capture_reports_keys_and_swallows_them():
	var r = _router()
	var a := Rec.new()
	r.push(a)
	var got := []
	r.key_capture = func(k: int): got.append(k)
	check(r._handle(_key(KEY_Z)), "捕获中: 键被吞")
	r._handle(_key(KEY_Z, false))
	r._handle(_key(KEY_TAB, true, false, true))
	r._handle(_key(KEY_SHIFT))
	eq(got, [KEY_Z, KEY_TAB | KeyMap.SHIFT], "回报键值 (Shift 并入, 修饰键本身不报)")
	eq(a.log, [], "捕获中不触发动作")
	r._handle(_key(KEY_ESCAPE))
	eq(a.log, ["cancel"], "Esc 不被捕获: 仍是取消 (用来放弃改键)")
	r.key_capture = Callable()
	r.free()

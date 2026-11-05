# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 虚拟键位置编辑 (设定「触屏键位置」touch_edit → TouchPad 编辑模式, 布局存 touch_layout; 2026-11-04 用户要求):
## 每个键单独拖动、位置按可用区域比例存; 透明度 / 大小滑条; 复位; 完成发出布局; 布局校验。

func _pad():
	var pad = load("res://engine/input/touch_pad.gd").new()
	(Engine.get_main_loop() as SceneTree).root.add_child(pad)
	return pad


func _key(pad, kind: int) -> Dictionary:
	for k in pad.keys():
		if int(k["kind"]) == kind:
			return k
	return {}


func _bar_item(pad, id: String) -> Dictionary:
	for it in pad._bar_items:
		if it["id"] == id:
			return it
	return {}


func test_sanitize():
	eq(TouchLayout.sanitize(null), TouchLayout.defaults(), "非法值取缺省")
	var v := TouchLayout.sanitize({"alpha": 5.0, "size": 999, "pos": {"stick": [0.5, 2.0], "bogus": [0.1, 0.1], "confirm": "x"}})
	eq(v["alpha"], TouchLayout.ALPHA_MIN, "透明度夹到下限 (JSON 的浮点也认)")
	eq(v["size"], TouchLayout.SIZE_MAX, "大小夹到上限")
	eq(v["pos"], {"stick": [0.5, 1.0]}, "位置夹到 0~1, 未知键和坏值丢掉")
	eq(SettingsSchema.clean_value("touch_layout", {"alpha": 50})["alpha"], 50, "设定校验走 TouchLayout")
	eq(SettingsSchema.defaults()["touch_layout"], TouchLayout.defaults(), "缺省布局")


func test_drag_key_moves_only_that_key():
	var pad = _pad()
	pad.begin_edit()
	check(pad.editing, "进入编辑")
	var cancel_c: Vector2 = _key(pad, UiAction.CANCEL)["c"]
	var confirm_c: Vector2 = _key(pad, UiAction.CONFIRM)["c"]
	var to: Vector2 = pad._area.get_center()
	pad.edit_touch(0, confirm_c, true, false)
	pad.edit_touch(0, to, true, true)
	pad.edit_touch(0, to, false, false)
	check((_key(pad, UiAction.CONFIRM)["c"] as Vector2).distance_to(to) < 1.0, "确认键跟着手指走")
	eq(_key(pad, UiAction.CANCEL)["c"], cancel_c, "别的键不动")
	var p: Array = pad.layout_config()["pos"]["confirm"]
	check(absf(p[0] - 0.5) < 0.01 and absf(p[1] - 0.5) < 0.01, "位置按可用区域比例存")
	# 拖出屏幕外: 整个键夹在区域里
	pad.edit_touch(1, pad._stick_c, true, false)
	pad.edit_touch(1, Vector2(-5000, 5000), true, true)
	pad.edit_touch(1, Vector2(-5000, 5000), false, false)
	var area: Rect2 = pad._area
	check(pad._stick_c.x >= area.position.x + pad._stick_r - 0.5 and pad._stick_c.y <= area.end.y - pad._stick_r + 0.5, "摇杆拖出界被夹回")
	pad.free()


func test_small_buttons_draggable_and_shown_in_edit():
	var pad = _pad()
	pad.shown = false
	pad.begin_edit()
	var c: Vector2 = _key(pad, pad.SETTINGS)["c"]
	eq(pad.edit_hit(c)["what"], "key", "右上角小钮也能拖")
	eq(pad.edit_hit(pad._stick_c)["what"], "key", "整套键隐藏时编辑中摇杆也在")
	pad.end_edit()
	check(pad.shown, "摆完整套键显示出来")
	pad.free()


func test_sliders_and_reset():
	var pad = _pad()
	pad.begin_edit()
	var r0: float = _key(pad, UiAction.CONFIRM)["r"]
	var size: Rect2 = _bar_item(pad, "size")["rect"]
	pad.edit_touch(0, Vector2(size.end.x + 2.0, size.get_center().y), true, false)
	pad.edit_touch(0, Vector2(size.end.x + 2.0, size.get_center().y), false, false)
	eq(pad.layout_config()["size"], TouchLayout.SIZE_MAX, "大小滑条拉到最右")
	check(float(_key(pad, UiAction.CONFIRM)["r"]) > r0 * 1.5, "键跟着变大")
	var alpha: Rect2 = _bar_item(pad, "alpha")["rect"]
	pad.edit_touch(0, Vector2(alpha.position.x, alpha.get_center().y), true, false)
	pad.edit_touch(0, Vector2(alpha.position.x - 30.0, alpha.get_center().y), true, true)
	pad.edit_touch(0, Vector2(alpha.position.x - 30.0, alpha.get_center().y), false, false)
	eq(pad.layout_config()["alpha"], TouchLayout.ALPHA_MIN, "透明度滑条拉到最左")
	check(absf(pad._pad.modulate.a - TouchLayout.ALPHA_MIN / 100.0) < 0.01, "立即按新透明度显示")
	var reset: Rect2 = _bar_item(pad, "reset")["rect"]
	pad.edit_touch(0, reset.get_center(), true, false)
	pad.edit_touch(0, reset.get_center(), false, false)
	eq(pad.layout_config(), TouchLayout.defaults(), "复位: 全回缺省")
	check(pad.editing, "复位后还在编辑")
	pad.free()


func test_done_emits_layout_and_bar_draggable():
	var pad = _pad()
	pad.begin_edit()
	var bar: Rect2 = pad._bar
	var grab := Vector2(bar.position.x + 2.0, bar.position.y + 2.0)
	eq(pad.edit_hit(grab)["what"], "bar", "工具条空白处可以拖")
	pad.edit_touch(0, grab, true, false)
	pad.edit_touch(0, grab + Vector2(0, 40), true, true)
	pad.edit_touch(0, grab + Vector2(0, 40), false, false)
	check(absf(pad._bar.position.y - bar.position.y - 40.0) < 0.5, "工具条跟着拖")
	var got := []
	pad.edit_finished.connect(func(cfg): got.append(cfg))
	var done: Rect2 = _bar_item(pad, "done")["rect"]
	pad.edit_touch(0, done.get_center(), true, false)
	check(pad.editing, "按下还没生效")
	pad.edit_touch(0, done.get_center(), false, false)
	check(not pad.editing, "松开在完成上: 退出编辑")
	eq(got.size(), 1, "发出布局")
	pad.free()


func test_saved_layout_applies():
	var pad = _pad()
	pad.set_layout({"alpha": 60, "size": 100, "pos": {"cancel": [0.5, 0.5]}})
	check((_key(pad, UiAction.CANCEL)["c"] as Vector2).distance_to(pad._area.get_center()) < 1.0, "存的位置生效")
	pad.set_layout(null)
	pad.free()


func test_setting_row_only_with_touch():
	var args = DebugArgs.current()
	var old: bool = args.touch
	args.touch = true
	var keys := SettingsSchema.shown_rows("controls").map(func(r): return r["key"])
	check(keys.has("touch_edit"), "有虚拟键时在控制器设置里列")
	args.touch = old

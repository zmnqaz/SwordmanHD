# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 版权声明页 (scripts/notice_scene.gd): 每次启动都显示 (跳过片头 / 回放除外), 不记住同意;
## 键盘切按钮 / 确认; 同意走 on_agree, 不同意走 on_decline; 取消键关不掉; 选过一次再按无效。

const NoticeScene = preload("res://scripts/notice_scene.gd")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_needed_every_time():
	check(NoticeScene.needed(false), "正常启动: 显示")
	check(not NoticeScene.needed(true), "跳过片头 / 回放: 不拦")


func test_keyboard_agree_and_decline():
	var got := []
	var s := NoticeScene.create(func(): got.append("agree"), func(): got.append("decline"))
	_tree().root.add_child(s)
	eq(s._buttons.size(), 2, "同意 / 不同意 两个按钮")
	eq(s._sel, 0, "默认选中「同意」")
	s.ui_action(UiAction.new(UiAction.CANCEL, "key"))
	eq(got, [], "取消键关不掉")
	s.ui_action(UiAction.new(UiAction.RIGHT, "key"))
	eq(s._sel, 1, "→ 选中「不同意」")
	s.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
	eq(got, ["decline"], "确认 = 不同意")
	s.ui_action(UiAction.new(UiAction.LEFT, "key"))
	s.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
	eq(got, ["decline"], "已经选过, 再按无效")
	s.queue_free()
	await _tree().process_frame
	var t := NoticeScene.create(func(): got.append("agree"), func(): got.append("decline"))
	_tree().root.add_child(t)
	t.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
	eq(got, ["decline", "agree"], "确认 = 同意")
	check(not FileAccess.file_exists("user://notice.json"), "同意后不落盘")
	t.queue_free()
	await _tree().process_frame


## 鼠标: 输入层把左键吃掉转成带坐标的确认, 页面靠 ui_hits 命中区认按钮。回归: 点哪都等于「同意」、点「不同意」也进游戏 (2026-10-29)
func _click_center(b: Button) -> Vector2:
	return b.get_global_transform_with_canvas() * (b.size * 0.5)


func test_mouse_click_hits_buttons_only():
	var got := []
	var s := NoticeScene.create(func(): got.append("agree"), func(): got.append("decline"))
	_tree().root.add_child(s)
	await _tree().process_frame
	await _tree().process_frame
	var agree: Button = s._buttons[0]
	var decline: Button = s._buttons[1]
	check(agree.size.x > 0 and decline.size.x > 0, "按钮已布局")
	InputRouter.dispatch(UiAction.new(UiAction.CONFIRM, "mouse", Vector2(1, 1)))
	eq(got, [], "点空处 (窗口角落) 不算同意")
	InputRouter.dispatch(UiAction.new(UiAction.CONFIRM, "mouse", _click_center(decline)))
	eq(got, [], "没悬停过的第一下点按被防误触挡掉, 更不是同意")
	InputRouter.dispatch(UiAction.new(UiAction.POINT, "mouse", _click_center(decline)))
	eq(s._sel, 1, "悬停「不同意」= 选中它")
	InputRouter.dispatch(UiAction.new(UiAction.CONFIRM, "mouse", _click_center(decline)))
	eq(got, ["decline"], "点「不同意」= 不同意 (不是同意)")
	s.queue_free()
	await _tree().process_frame
	var t := NoticeScene.create(func(): got.append("agree"), func(): got.append("decline"))
	_tree().root.add_child(t)
	await _tree().process_frame
	await _tree().process_frame
	InputRouter.dispatch(UiAction.new(UiAction.POINT, "mouse", _click_center(t._buttons[0])))
	InputRouter.dispatch(UiAction.new(UiAction.CONFIRM, "mouse", _click_center(t._buttons[0])))
	eq(got, ["decline", "agree"], "点「同意」= 同意")
	t.queue_free()
	await _tree().process_frame

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

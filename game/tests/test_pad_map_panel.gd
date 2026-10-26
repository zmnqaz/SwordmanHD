# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 手柄按键设置子面板 (engine/ui/pad_map_panel.gd): 绑定存稀疏覆盖项、捕获流程、恢复预设、取消还原

const Router = preload("res://engine/input/input_router.gd")


class Flow:
	extends SceneFlow
	var applied := 0
	func apply_settings() -> void:
		applied += 1


func _panel() -> PadMapPanel:
	var p := PadMapPanel.new()
	p.gc = GameContext.new()
	p.gc.flow = Flow.new()
	p.router = Router.new()
	return p


func _joy(btn: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = true
	return e


func _free(p: PadMapPanel) -> void:
	p.router.free()
	p.free()


func test_entries_and_value_text_follow_preset():
	var p := _panel()
	eq(p.total(), PadMap.ACTIONS.size() + 2, "每个动作一行 + 恢复预设 + 完成")
	eq(p.value_text(0), "A", "标准: 确认 = A")
	p.gc.settings["pad_preset"] = "swap"
	eq(p.value_text(0), "B", "交换预设: 确认 = B")
	p.gc.settings["pad_map"] = {"confirm": JOY_BUTTON_Y}
	eq(p.value_text(0), "Y *", "改过的键带 * 标记")
	_free(p)


func test_bind_stores_sparse_override_and_applies():
	var p := _panel()
	var f: Flow = p.gc.flow
	p.bind("info", JOY_BUTTON_RIGHT_STICK)
	eq(p.gc.settings["pad_map"], {"info": JOY_BUTTON_RIGHT_STICK}, "只存与预设不同的项")
	eq(f.applied, 1, "绑定后即时生效")
	p.bind("info", JOY_BUTTON_X)
	eq(p.gc.settings["pad_map"], {}, "改回预设默认键: 覆盖项删除")
	_free(p)


func test_capture_binds_next_button():
	var p := _panel()
	p.start_capture("menu")
	check(p.router.pad_capture.is_valid(), "捕获开始: 路由器进入捕获状态")
	p.router._handle(_joy(JOY_BUTTON_LEFT_STICK))
	eq(p.gc.settings["pad_map"], {"menu": JOY_BUTTON_LEFT_STICK}, "下一个键绑定到该动作")
	check(not p.router.pad_capture.is_valid(), "绑定后结束捕获")
	eq(p.capturing(), "", "捕获状态清除")
	_free(p)


func test_capture_cancel_and_timeout_leave_binding_alone():
	var p := _panel()
	p.start_capture("menu")
	check(p.ui_action(UiAction.of(UiAction.CANCEL)), "捕获中取消键被面板吃掉 (不关面板)")
	eq(p.gc.settings["pad_map"], {}, "取消捕获: 不改绑定")
	check(not p.router.pad_capture.is_valid(), "取消后结束捕获")
	p.start_capture("menu")
	p.tick_capture(PadMapPanel.CAPTURE_TIMEOUT + 0.1)
	eq(p.capturing(), "", "超时自动放弃")
	eq(p.gc.settings["pad_map"], {})
	_free(p)


func test_reset_and_cancel_restore():
	var p := _panel()
	p.gc.settings["pad_map"] = {"info": JOY_BUTTON_BACK}
	p.begin()
	p.bind("menu", JOY_BUTTON_START)
	p.reset_all()
	eq(p.gc.settings["pad_map"], {}, "恢复预设: 清空全部覆盖项")
	p.cancel_changes()
	eq(p.gc.settings["pad_map"], {"info": JOY_BUTTON_BACK}, "取消: 还原进入面板时的覆盖项")
	_free(p)

# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 键盘按键设置子面板 (engine/ui/key_map_panel.gd): 绑定存稀疏覆盖项、捕获流程、恢复默认、取消还原

const Router = preload("res://engine/input/input_router.gd")


class Flow:
	extends SceneFlow
	var applied := 0
	func apply_settings() -> void:
		applied += 1


func _panel() -> KeyMapPanel:
	var p := KeyMapPanel.new()
	p.gc = GameContext.new()
	p.gc.flow = Flow.new()
	p.router = Router.new()
	return p


func _free(p: KeyMapPanel) -> void:
	p.router.free()
	p.free()


func _idx(a: String) -> int:
	return KeyMap.ACTIONS.find(a)


func test_entries_and_value_text():
	var p := _panel()
	eq(p.total(), KeyMap.ACTIONS.size() + 2, "每个动作一行 + 恢复默认 + 完成")
	eq(p.value_text(_idx("map")), "M", "战场地图 = M")
	eq(p.value_text(_idx("settings")), "F1", "设定 = F1")
	eq(p.value_text(_idx("guide")), "F2", "攻略 = F2")
	p.gc.settings["key_map"] = {"map": KEY_N}
	eq(p.value_text(_idx("map")), "N *", "改过的键带 * 标记")
	p.gc.settings["key_map"] = {"map": KEY_F2}
	eq(p.value_text(_idx("map")), "F2 * !", "与别的动作共用同一个键: 带 !")
	eq(p.value_text(_idx("guide")), "F2 !", "对方也带 !")
	p.gc.settings["key_map"] = {}
	eq(p.value_text(_idx("switch")), "Tab", "Tab = 切栏")
	_free(p)


func test_bind_stores_sparse_override_and_applies():
	var p := _panel()
	var f: Flow = p.gc.flow
	p.bind("map", KEY_N)
	eq(p.gc.settings["key_map"], {"map": KEY_N}, "只存与默认不同的项")
	eq(f.applied, 1, "绑定后即时生效")
	p.bind("map", KEY_M)
	eq(p.gc.settings["key_map"], {}, "改回默认主键: 覆盖项删除")
	_free(p)


func test_capture_binds_next_key_and_ignores_unbindable():
	var p := _panel()
	p.start_capture("map")
	check(p.router.key_capture.is_valid(), "捕获开始: 路由器进入捕获状态")
	p._on_captured(KEY_W)
	eq(p.capturing(), "map", "方向键不能绑: 继续等")
	p._on_captured(KEY_Z | KEY_MASK_CTRL)
	eq(p.capturing(), "map", "带 Ctrl 的组合不能绑: 继续等")
	p._on_captured(KEY_TAB | KeyMap.SHIFT)
	eq(p.capturing(), "", "绑定后结束捕获")
	eq(p.gc.settings["key_map"], {"map": KEY_TAB | KeyMap.SHIFT}, "Shift 组合可以绑")
	check(not p.router.key_capture.is_valid(), "捕获结束: 路由器退出捕获状态")
	_free(p)


func test_capture_timeout_and_cancel_leave_binding_alone():
	var p := _panel()
	p.start_capture("map")
	p.tick_capture(KeyMapPanel.CAPTURE_TIMEOUT + 0.1)
	eq(p.capturing(), "", "超时放弃")
	eq(p.gc.settings["key_map"], {}, "没改")
	p.start_capture("map")
	var a := UiAction.new(UiAction.CANCEL, "key")
	check(p.ui_action(a), "捕获中取消键被面板吞掉")
	eq(p.capturing(), "", "取消键放弃改键")
	_free(p)


func test_reset_and_cancel_restore():
	var p := _panel()
	p.gc.settings["key_map"] = {"info": KEY_G}
	p.begin()
	p.bind("map", KEY_N)
	p.reset_all()
	eq(p.gc.settings["key_map"], {}, "恢复默认清掉全部覆盖项")
	p.cancel_changes()
	eq(p.gc.settings["key_map"], {"info": KEY_G}, "取消: 还原进入前的覆盖项")
	_free(p)

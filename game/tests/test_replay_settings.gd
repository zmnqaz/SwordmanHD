# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 设定面板的回放行 (SettingsSchema): replay 平时列、replay_stop/replay_speed 回放中列, live kind 不进设定文件


func _keys() -> Array:
	return SettingsSchema.all_shown_rows().map(func(r): return r["key"])   # 主菜单 + 各二级菜单


func _start_replay() -> String:
	var p := "user://test_rs_%d.json" % Time.get_ticks_usec()
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": PlayLog.VERSION, "kind": "play", "meta": {}, "duration": 1.0, "seeds": [], "checkpoints": [], "events": [{"t": 100.0, "k": UiAction.UP}]}))
	f.close()
	var l := PlayLog.open_replay(p, 1.0)
	l._ready()
	return p


func test_rows_when_idle() -> void:
	var k := _keys()
	check("replay" in k, "平时有「录像回放」行")
	check(not ("replay" in SettingsSchema.shown_rows().map(func(r): return r["key"])), "主菜单不直接列, 收在「特色功能」里 (2026-11-03)")
	check("replay" in SettingsSchema.shown_rows("feature").map(func(r): return r["key"]), "「特色功能」二级菜单里有")
	check(not ("replay_stop" in k), "平时没有「结束回放」")
	check(not ("replay_speed" in k), "平时没有「回放速度」")


func test_rows_while_replaying() -> void:
	var p := _start_replay()
	var k := _keys()
	check(not ("replay" in k), "回放中不列「录像回放」")
	check("replay_stop" in k, "回放中有「结束回放」")
	check("replay_speed" in k, "回放中有「回放速度」")
	var main := SettingsSchema.shown_rows().map(func(r): return r["key"])
	check("replay_stop" in main and "replay_speed" in main, "回放中的两行仍在主菜单 (随时能停 / 调速)")
	PlayLog.stop_current()
	DirAccess.remove_absolute(p)


func test_live_and_action_rows_not_persisted() -> void:
	var d := SettingsSchema.defaults()
	for k in ["replay", "replay_stop", "replay_speed"]:
		check(not d.has(k), k + " 不进缺省设定")
		eq(SettingsSchema.clean_value(k, 1), null, k + " 不接受写入")
	check(not SettingsSchema.sanitize({"replay_speed": 4}).has("replay_speed"), "设定文件里的 replay_speed 被丢掉")


func test_live_step_text_and_set() -> void:
	eq(SettingsSchema.step("replay_speed", 1.0, 1), 2.0)
	eq(SettingsSchema.step("replay_speed", 16.0, 1), 16.0, "到头停住")
	eq(SettingsSchema.text_of("replay_speed", 2.0), "×2")
	eq(SettingsSchema.live_value("replay_speed"), 1.0, "没回放时读 1.0")
	var p := _start_replay()
	SettingsSchema.set_live("replay_speed", 8.0)
	eq(Engine.time_scale, 8.0)
	eq(SettingsSchema.live_value("replay_speed"), 8.0)
	PlayLog.stop_current()
	DirAccess.remove_absolute(p)


func test_panel_adjusts_live_speed_row_without_touching_settings() -> void:
	var p := _start_replay()
	var panel := SettingsPanel.new()
	panel.gc = GameContext.new()
	var idx := _keys().find("replay_speed")
	check(idx >= 0)
	panel._sel = idx
	var before := panel.gc.settings.duplicate(true)
	panel._change(1)
	eq(Engine.time_scale, 2.0, "右键: 1x -> 2x, 立即生效")
	panel._change(-1)
	panel._change(-1)
	eq(Engine.time_scale, 0.5)
	eq(panel.gc.settings, before, "live 行不写设定")
	panel.free()
	PlayLog.stop_current()
	DirAccess.remove_absolute(p)


## 开始回放后整个设定菜单都要退出: 「录像回放」现在在二级菜单「特色功能」里, 二级菜单关闭时必须连主面板一起关 (否则切到回放后主面板还留在屏幕上)
func test_starting_a_replay_from_submenu_closes_the_whole_menu() -> void:
	var main := SettingsPanel.new()
	var sub_panel := SettingsPanel.new()
	sub_panel._chain_close = true
	check(main._closes_all("feature", sub_panel, true), "二级菜单里开始了回放: 主面板跟着关")
	var other := SettingsPanel.new()
	check(not main._closes_all("feature", other, true), "二级菜单只是正常关闭: 主面板留着")
	var rp := ReplayPanel.new()
	rp.chosen_path = ""
	check(main._closes_all("replay", rp, true), "主面板直接选了录像: 照旧关")
	check(not main._closes_all("replay", rp, false), "取消选择: 不关")
	main.free()
	sub_panel.free()
	other.free()
	rp.free()



func test_record_setting_defaults_off_and_gates_recording() -> void:
	eq(SettingsSchema.defaults().get("record"), 0, "战场录像缺省关")
	check("record" in SettingsSchema.shown_rows("feature").map(func(r): return r["key"]), "在「特色功能」里")
	var gc := GameContext.current()
	var had = gc.settings.get("record", 0)
	gc.settings["record"] = 0
	if DebugArgs.current().record_play == "":
		check(not PlayLog.recording_wanted(), "关着: 不录")
	gc.settings["record"] = had

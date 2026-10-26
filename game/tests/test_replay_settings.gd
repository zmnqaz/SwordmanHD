# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 设定面板的回放行 (SettingsSchema): replay 平时列、replay_stop/replay_speed 回放中列, live kind 不进设定文件


func _keys() -> Array:
	return SettingsSchema.shown_rows().map(func(r): return r["key"])


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
	check(not ("replay_stop" in k), "平时没有「结束回放」")
	check(not ("replay_speed" in k), "平时没有「回放速度」")


func test_rows_while_replaying() -> void:
	var p := _start_replay()
	var k := _keys()
	check(not ("replay" in k), "回放中不列「录像回放」")
	check("replay_stop" in k, "回放中有「结束回放」")
	check("replay_speed" in k, "回放中有「回放速度」")
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

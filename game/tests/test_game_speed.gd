# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 游戏速度 (设定 game_speed, engine/core/game_speed.gd): 1.0~5.0 倍, 设定里存 10~50 的整数, 即时生效, 缺省 1.0 = 与原版一致

func after_each() -> void:
	GameSpeed.set_tenths(10)
	Engine.time_scale = 1.0


func test_setting_row_defaults_and_options():
	var r := SettingsSchema.row("game_speed")
	check(not r.is_empty(), "有游戏速度项")
	eq(SettingsSchema.defaults()["game_speed"], 10, "缺省原速")
	var opts := SettingsSchema.options_of(r)
	eq(opts.size(), 17, "1.0 ~ 2.0 每 0.1 一档 (11 档), 2.0 以上每 0.5 一档到 5.0 (6 档)")
	eq(opts[0]["t"], "×1.0")
	eq(opts[5]["t"], "×1.5")
	eq(opts[10]["t"], "×2.0")
	eq(opts[11]["t"], "×2.5")
	eq(opts[16]["t"], "×5.0")
	check(SettingsSchema.shown_rows().any(func(x): return x["key"] == "game_speed"), "主菜单里列出")


func test_setting_validation():
	eq(SettingsSchema.sanitize({"game_speed": 15})["game_speed"], 15, "合法档位保留")
	eq(SettingsSchema.sanitize({"game_speed": 40})["game_speed"], 40, "2.0 以上的档位 (×4.0) 保留")
	for bad in [9, 21, 26, 51, 0, 1.55, "fast", null]:
		eq(SettingsSchema.sanitize({"game_speed": bad})["game_speed"], 10, "非法值 (不在档位上) 回退原速: %s" % str(bad))
	eq(SettingsSchema.step("game_speed", 10, 1), 11, "右键加一档")
	eq(SettingsSchema.step("game_speed", 20, 1), 25, "2.0 之后每档 0.5")
	eq(SettingsSchema.step("game_speed", 50, 1), 10, "到头循环回原速")


func test_set_tenths_drives_time_scale_and_clamps():
	GameSpeed.set_tenths(15)
	eq(GameSpeed.factor, 1.5)
	eq(Engine.time_scale, 1.5, "即时生效")
	GameSpeed.set_tenths(40)
	eq(Engine.time_scale, 4.0, "×4.0")
	GameSpeed.set_tenths(99)
	eq(Engine.time_scale, 5.0, "夹在 5.0")
	GameSpeed.set_tenths(0)
	eq(Engine.time_scale, 1.0, "夹在 1.0, 不会比原速慢")

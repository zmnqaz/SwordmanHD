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


## 人手节拍用的真实时间: delta 已被 time_scale 放大, real_delta 还原; 回放暂停 (time_scale 0) 时为 0
func test_real_delta_undoes_time_scale():
	Engine.time_scale = 1.0
	eq(GameSpeed.real_delta(0.04), 0.04, "原速不变")
	Engine.time_scale = 3.0
	check(absf(GameSpeed.real_delta(0.12) - 0.04) < 1e-9, "3 倍速: 游戏 0.12 秒 = 真实 0.04 秒")
	Engine.time_scale = 0.5
	check(absf(GameSpeed.real_delta(0.02) - 0.04) < 1e-9, "回放慢放 0.5 倍也还原")
	Engine.time_scale = 0.0
	eq(GameSpeed.real_delta(0.0), 0.0, "暂停: 0, 不除零")
	Engine.time_scale = 1.0   # 跑测试的循环不调 after_each: 自己还原, 否则后面靠 SceneTreeTimer 的测试永远等不到


## 整屏过场动画播放期间按原速, 播完 / 节点离开场景树后回到设定倍速; 期间改设定也不加速
func test_cutscene_hold_plays_at_normal_speed():
	var root := (Engine.get_main_loop() as SceneTree).root
	GameSpeed.set_tenths(30)
	eq(Engine.time_scale, 3.0, "设定 3 倍")
	var a := Node.new()
	root.add_child(a)
	GameSpeed.hold_normal(a)
	eq(Engine.time_scale, 1.0, "过场动画期间原速")
	GameSpeed.set_tenths(20)
	eq(Engine.time_scale, 1.0, "期间改设定仍原速")
	GameSpeed.release(a)
	eq(Engine.time_scale, 2.0, "播完回到设定倍速")
	GameSpeed.hold_normal(a)
	root.remove_child(a)   # 中途离开场景树 (换场景 / 跳过) 也放开
	eq(Engine.time_scale, 2.0, "节点离开场景树自动放开")
	a.free()



## 过场动画被隐藏 (剧情清掉 / 跳过, 没发 finished) 也放开, 速度不卡在 1 倍
func test_cutscene_hidden_releases_hold():
	var root := (Engine.get_main_loop() as SceneTree).root
	GameSpeed.set_tenths(30)
	var a := Node2D.new()
	root.add_child(a)
	GameSpeed.hold_normal(a)
	eq(Engine.time_scale, 1.0, "过场动画期间原速")
	a.visible = false
	eq(Engine.time_scale, 3.0, "隐藏后回到设定倍速")
	a.visible = true
	eq(Engine.time_scale, 3.0, "再显示不会自己重新按住")
	GameSpeed.release(a)   # 播完照常调用, 已放开时什么都不做
	eq(Engine.time_scale, 3.0)
	GameSpeed.hold_normal(a)   # 同一个动画节点再播一次 (剧情里事件动画会重复播)
	eq(Engine.time_scale, 1.0, "再次按住")
	GameSpeed.release(a)
	eq(Engine.time_scale, 3.0, "再次放开")
	a.free()

# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战场镜头取整 (BattleScene._snap_px): 取到「画面像素」(1/SCALE 原版像素), 不是整个原版像素。
## 回归 (2026-10-29): 取整到 1 原版像素时, 1920 窗口里每帧镜头位移的取整误差最大 3 个屏幕像素, 平移 (战斗走路镜头跟随) 看起来不流畅。

const BattleSceneScript = preload("res://engine/battle/battle_scene.gd")


func test_snap_to_screen_pixel_not_original_pixel() -> void:
	var s := float(Assets.SCALE)
	eq(BattleSceneScript._snap_px(Vector2(10.0, 20.0)), Vector2(10.0, 20.0), "整数原版像素不变")
	eq(BattleSceneScript._snap_px(Vector2(10.3, 20.6)), Vector2(roundf(10.3 * s) / s, roundf(20.6 * s) / s), "小数位保留到 1/SCALE")
	check(BattleSceneScript._snap_px(Vector2(10.3, 0.0)).x != 10.0, "不再取整成整个原版像素")
	for i in 40:   # 取整后任何位置与原位置相差不超过半个画面像素
		var v := Vector2(i * 0.173, i * 0.311)
		var d := (BattleSceneScript._snap_px(v) - v).abs()
		check(d.x <= 0.5 / s + 0.0001 and d.y <= 0.5 / s + 0.0001, "误差 <= 半个画面像素: %s" % str(d))
	var step := BattleSceneScript._snap_px(Vector2(100.0 * 5.0 / 3.0, 0.0)) - BattleSceneScript._snap_px(Vector2.ZERO)
	check(absf(step.x * s - roundf(step.x * s)) < 0.0001, "位置总是画面像素的整数倍 (与格子 / 贴图对齐)")

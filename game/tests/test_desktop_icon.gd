# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 桌面窗口 / 任务栏图标 (ScreenLayout.desktop_icon_image): 用自制的 icon_pc.png, 不跟手游的美术图标 (project.godot config/icon = app_icon.png) 走。
## 2026-10-31 玩家: PC 版图标不该跟着手游图标变。


func test_desktop_icon_loads_and_is_not_the_mobile_icon() -> void:
	var pc := ScreenLayout.desktop_icon_image()
	check(pc != null, "icon_pc.png 能读到")
	eq(pc.get_size(), Vector2i(1024, 1024), "1024x1024")
	check(not pc.is_compressed(), "解压过 (DisplayServer.set_icon 要原始像素)")
	var mobile := (load("res://assets/app_icon.png") as Texture2D).get_image()
	var diff := 0
	for p in [Vector2i(100, 100), Vector2i(512, 512), Vector2i(900, 300), Vector2i(300, 900), Vector2i(512, 200)]:
		if pc.get_pixelv(p).is_equal_approx(mobile.get_pixelv(p)):
			continue
		diff += 1
	check(diff >= 3, "桌面图标与手游图标是两张不同的图 (抽样 5 点, %d 点不同)" % diff)


func test_project_icon_stays_the_mobile_art() -> void:
	eq(String(ProjectSettings.get_setting("application/config/icon")), "res://assets/app_icon.png", "project.godot 的 config/icon 是手游美术图标 (Android / iOS 取它)")

# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 城镇整屏事件动画 (如第 7 镇客栈房间 EANM_04) 的宽屏留边: 动画只摆在原版 320x200 镜头位置, 宽屏下视口比它宽, 两侧会露出下面的城镇地图。
## AnimPlayer.data_covers_window / covers_window 判断动画是不是整屏画面, RpgScreenMask 在它四周铺黑 (原版画面之外没有别的东西)。


func _anim(x: float, y: float, w: float, h: float) -> Dictionary:
	return {"frames": [{"parts": [{"tex": 0, "x": x, "y": y}]}], "textures": [{"w": w, "h": h}]}


func test_covers_window_only_for_full_screen_pictures() -> void:
	var s := Vector2(320, 200)
	check(AnimPlayer.data_covers_window(_anim(-8, 0, 364, 223), s), "客栈房间 EANM_04 (第 7 镇, 比屏幕还大)")
	check(AnimPlayer.data_covers_window(_anim(0, 0, 330, 216), s), "Meet-1 (第 7 镇)")
	check(AnimPlayer.data_covers_window(_anim(0, 0, 320, 200), s), "刚好整屏")
	check(not AnimPlayer.data_covers_window(_anim(179, 89, 169, 129), s), "MEET-2: 叠在别的画面上的局部动画")
	check(not AnimPlayer.data_covers_window(_anim(2, 2, 271, 192), s), "大个子 NPC 动画不是整屏")
	check(not AnimPlayer.data_covers_window({"frames": [{"parts": []}], "textures": []}, s), "空动画")


func test_bounds_cover_all_frames_and_parts() -> void:
	var d := {"frames": [{"parts": [{"tex": 0, "x": 0, "y": 0}]}, {"parts": [{"tex": 1, "x": 200, "y": 150}]}],
		"textures": [{"w": 120, "h": 100}, {"w": 120, "h": 50}]}
	eq(AnimPlayer.bounds_of(d), Rect2(0, 0, 320, 200), "各帧各部件的包围盒")


func test_mask_rects_surround_window_without_overlap() -> void:
	var w := Rect2(10, 20, 320, 200)
	var rs := RpgScreenMask.rects(w, 100.0)
	eq(rs.size(), 4)
	var area := 0.0
	for r in rs:
		area += r.get_area()
		check(not r.intersects(w), "不盖住窗口")
	eq(area, 520.0 * 400.0 - 320.0 * 200.0, "四块正好是窗口外的一圈")
	for i in rs.size():
		for j in range(i + 1, rs.size()):
			check(not rs[i].intersects(rs[j]), "互不重叠")

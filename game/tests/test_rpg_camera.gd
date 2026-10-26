# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 城镇镜头取整 (RpgStage.snap_camera): 横向 75 像素/秒在 60Hz 下每帧 1.25 个原版像素, 取整到原版像素会 1、1、1、2 抖动, 取整到物理像素就均匀。


func _steps(mult: float, per_frame: float, frames: int) -> Array:
	var out: Array = []
	var prev := RpgStage.snap_camera(Vector2(100, 0), mult).x
	for i in range(1, frames + 1):
		var cur := RpgStage.snap_camera(Vector2(100 + per_frame * i, 0), mult).x
		out.append(snappedf((cur - prev) * maxf(mult, 1.0), 0.001))   # 以物理像素计的这一帧位移 (mult < 1 时就是原版像素)
		prev = cur
	return out


func test_old_integer_rounding_judders_horizontally_but_not_vertically() -> void:
	var h := _steps(0.0, 1.25, 40)   # mult < 1: 原来的取整到原版像素
	check(h.min() == 1.0 and h.max() == 2.0, "横向 1.25 像素/帧取整后在 1 和 2 之间跳: %s..%s" % [h.min(), h.max()])
	var v := _steps(0.0, 1.0, 40)
	check(v.min() == 1.0 and v.max() == 1.0, "纵向每帧正好 1 个像素: 均匀")


func test_physical_pixel_snapping_is_even() -> void:
	var m4 := _steps(4.0, 1.25, 60)   # 1280x800 窗口
	check(m4.min() == 5.0 and m4.max() == 5.0, "4 倍窗口横向每帧正好 5 个物理像素: %s..%s" % [m4.min(), m4.max()])
	var m6 := _steps(6.0, 1.25, 60)   # 1920x1200 窗口: 7.5 个物理像素, 7 和 8 交替
	check(m6.min() == 7.0 and m6.max() == 8.0, "6 倍窗口横向 7、8 交替 (相差 1 个物理像素): %s..%s" % [m6.min(), m6.max()])
	var m6v := _steps(6.0, 1.0, 60)
	check(m6v.min() == 6.0 and m6v.max() == 6.0, "纵向仍然均匀")


func test_snap_lands_on_physical_pixels_and_never_drifts_far() -> void:
	for m in [1.0, 2.5, 4.0, 6.0]:
		var p := Vector2(123.456, 78.9)
		var s := RpgStage.snap_camera(p, m)
		check(absf(s.x * m - roundf(s.x * m)) < 1e-4 and absf(s.y * m - roundf(s.y * m)) < 1e-4, "m=%s 落在物理像素上" % m)
		check(absf(s.x - p.x) <= 0.5 / m + 1e-6 and absf(s.y - p.y) <= 0.5 / m + 1e-6, "m=%s 误差不超过半个物理像素" % m)

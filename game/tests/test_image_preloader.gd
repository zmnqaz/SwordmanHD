# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## ImagePreloader (engine/render/image_preloader.gd): 切场景淡出期间后台解码大图, 新场景直接取; 没预读的返回 null 由调用方现读


func _png(w: int, h: int) -> String:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color8(x * 4 % 256, y * 7 % 256, 90, 255))
	var path := "user://preload_test_%d_%d.png" % [Time.get_ticks_usec(), w]
	img.save_png(path)
	return path


func test_take_returns_the_decoded_image_once() -> void:
	var f := _png(64, 32)
	var p := ImagePreloader.new()
	p.start(f)
	p.start(f)   # 重复 start 不重复解码
	eq(p.pending(), 1, "同一张只排一次")
	var img := p.take(f)
	var direct := Image.load_from_file(f)
	check(img != null and img.get_size() == Vector2i(64, 32) and img.get_data() == direct.get_data(), "取到的和直接读的像素一致")
	check(p.take(f) == null, "取走后没有了 (调用方自己读)")
	check(p.take("user://no_such_image.png") == null, "没 start 过返回 null")
	DirAccess.remove_absolute(f)


func test_next_scene_keeps_this_round_and_drops_stale() -> void:
	var a := _png(8, 8)
	var b := _png(16, 8)
	var p := ImagePreloader.new()
	p.start(a)
	p.next_scene()   # 淡出前 start 的, 切场景时调一次: 留给新场景取
	check(p.pending() == 1, "切换时刚 start 的留着")
	p.start(b)
	p.next_scene()   # 下一次换场景: a 没人取, 丢掉; b 是这一轮的, 留着
	eq(p.pending(), 1, "上一轮没人取的丢掉")
	check(p.take(a) == null and p.take(b) != null, "a 丢了, b 还在")
	p.wait_all()
	DirAccess.remove_absolute(a)
	DirAccess.remove_absolute(b)

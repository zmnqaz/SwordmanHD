# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 过场视频 (scripts/movie_scene.gd): 全屏宽屏时视频两侧不能露出下面的场景 —— 视频放在最高层画布里, 先铺一块盖满整个窗口的黑底


func test_video_sits_on_a_top_layer_over_a_full_screen_black_backdrop():
	var m: Control = MovieScene.create(["Movie/__no_such_movie__"], func(): pass)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(m)
	var layer: CanvasLayer = null
	for c in m.get_children():
		if c is CanvasLayer:
			layer = c
	check(layer != null, "视频在自己的画布层里")
	if layer == null:
		m.queue_free()
		return
	check(layer.layer > 55, "层号高于设定面板 (54/55) 与战场界面层 (30/31/40): %d" % layer.layer)
	var first := layer.get_child(0)
	check(first is ColorRect, "第一个子节点是黑底 (画在视频后面)")
	if first is ColorRect:
		eq((first as ColorRect).color, Color.BLACK, "纯黑")
		eq((first as ColorRect).mouse_filter, Control.MOUSE_FILTER_STOP, "点击不穿透到下面的界面")
	var has_player := false
	for c in layer.get_children():
		if c is VideoStreamPlayer:
			has_player = true
	check(has_player, "视频播放器在同一层里 (黑底之后)")
	eq(m.mouse_filter, Control.MOUSE_FILTER_IGNORE, "播放队列的壳不挡鼠标")
	m.queue_free()

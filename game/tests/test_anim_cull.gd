# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## AnimPlayer 屏外裁剪 (cull_offscreen): 屏外不换帧 (不取贴图), 回屏内补帧。


func test_near_screen_uses_anim_bounds() -> void:
	var a := AnimPlayer.new()
	a.data = {"frames": [{"parts": [{"tex": 0, "x": 5, "y": 5}, {"tex": null, "x": 0, "y": 0}]}], "textures": [{"w": 10, "h": 20}]}
	(Engine.get_main_loop() as SceneTree).root.add_child(a)
	var b := a._anim_bounds()
	check(b == Rect2(5, 5, 10, 20), "包围盒取全部帧部件 (跳过无贴图): %s" % b)
	a.position = Vector2(20, 20)
	check(a._near_screen(), "屏内")
	a.position = Vector2(1e6, 20)
	check(not a._near_screen(), "远在屏外")
	a.position = Vector2(-10000, -10000)
	check(not a._near_screen(), "左上屏外")
	a.free()


## 第 19 幕云海背板 (Eanm_09): 贴图 330x216 但内容只有 320x200, 右/下是透明留白。clip_to 让每个部件只取内容区并夹边,
## 两份循环首尾相接处才不会混进透明露一条黑线; 不设 clip_to 的动画不受影响
const REQUIRES_TEST := {"test_clip_to_crops_to_content": ["original"]}


func test_clip_to_crops_to_content() -> void:
	var a := AnimPlayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(a)
	a.play("Stage/Stage19/Eanm_09")
	var s: Sprite2D = a._sprites[0]
	check(not s.region_enabled, "默认不裁")
	a.clip_to = Vector2(320, 200)
	a.frame = -1
	a._show(1)
	s = a._sprites[0]
	check(s.region_enabled and s.region_filter_clip_enabled, "设了 clip_to 就按区域夹边")
	eq(s.region_rect.size * s.scale, Vector2(320, 200), "区域 = 320x200 原版像素 (与贴图倍率无关)")
	a.clip_to = Vector2.ZERO
	a.frame = -1
	a._show(1)
	check(not a._sprites[0].region_enabled, "清掉 clip_to 恢复整张贴图")
	a.free()

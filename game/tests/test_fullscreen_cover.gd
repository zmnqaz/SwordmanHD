# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 满屏演出动画在宽屏/全屏下的黑边 (engine/fx/fullscreen_cover.gd): 用户 2026-10-11 「全屏时第几幕图片、剧情全屏红色大招比全屏小」。
const REQUIRES := ["original"]


func _anim(dir: String) -> AnimPlayer:
	var a := AnimPlayer.new()
	a.play_sound = false
	a.show_frame(dir, 0)
	return a


func test_fullscreen_cutscene_gets_black_frame_once():
	var a := _anim("Stage/Stage07/Eanm_10")   # 第 7 幕满屏剧情画面 (320x200 一帧)
	check(FullscreenCover.is_fullscreen(a), "满屏动画识别")
	check(FullscreenCover.attach(a), "加了黑边")
	var n := a.get_child_count()
	check(not FullscreenCover.attach(a), "每个节点只加一次")
	eq(a.get_child_count(), n, "不重复加")
	var blacks := a.get_children().filter(func(c): return c is ColorRect)
	eq(blacks.size(), 4, "屏幕框外四块")
	for c in blacks:
		check(not Rect2(c.position, c.size).intersects(Rect2(1, 1, 318, 198)), "不压到 320x200 框里面")
	a.free()


func test_fullscreen_spell_animation():
	var a := _anim("Magic/magic075/M75")   # 满屏法术动画 (只有中间几帧满屏, 要扫全部帧才识别得出)
	check(FullscreenCover.is_fullscreen(a), "满屏法术动画识别")
	a.free()


func test_small_animation_untouched():
	var a := _anim("Misc/Cursor")
	check(not FullscreenCover.is_fullscreen(a), "光标不是满屏动画")
	check(not FullscreenCover.attach(a), "小动画不加黑边")
	eq(a.get_children().filter(func(c): return c is ColorRect).size(), 0)
	a.free()


## 纯色遮罩 (黑白场、剧情红屏、压暗) 用 margin 四边多铺: 窗口 / 全屏 / 宽屏切换时没重算也不露边
func test_cover_margin_extends_beyond_viewport():
	var tree := Engine.get_main_loop() as SceneTree
	var SL = tree.root.get_node_or_null("ScreenLayout")
	if SL == null:
		skip("没有 ScreenLayout autoload")
		return
	var layer := CanvasLayer.new()
	tree.root.add_child(layer)
	var plain := ColorRect.new()
	var wide := ColorRect.new()
	layer.add_child(plain)
	layer.add_child(wide)
	SL.cover(plain)
	SL.cover(wide, 500.0)
	var vis := tree.root.get_visible_rect()
	eq(plain.size, vis.size, "margin 0: 正好铺满视口")
	eq(wide.size, vis.size + Vector2(1000, 1000), "margin 500: 四边各多 500")
	eq(wide.position, vis.position - Vector2(500, 500), "起点往左上多出 500")
	layer.queue_free()

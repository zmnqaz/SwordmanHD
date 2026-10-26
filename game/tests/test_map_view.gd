# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战场「地圖」全图 (engine/battle/ui/battle_map_view.gd, 原版)
const REQUIRES_TEST := {
	"test_pulse_and_close_animation": ["original"],
	"test_small_map_centered_no_arrows": ["original"],
	"test_tall_map_scroll_and_arrows": ["original"]
}  # 个别方法的依赖 (同上)


func test_layout_from_table():
	var c := BattleMapView.load_cfg()
	eq(c["pos"], Vector2(78, 42), "面板固定在 (78,42), 不居中")
	eq(c["view_pos"], Vector2(3, 8), "可视区左上")
	eq(c["view_size"], Vector2(162, 111), "可视区 162x111")
	eq(c["cell"], 3, "每格 3 像素")
	eq(c["arrow_pos"][1], Vector2(80, 128), "下箭头在面板下沿外")
	eq(c["scroll_step"], 3, "每帧卷 3 像素")


func test_small_map_centered_no_arrows():
	var v := BattleMapView.new(0, Vector2i(24, 16), [[Vector2i(23, 9), 0], [Vector2i(23, 8), 1], [Vector2i(21, 9), 2]])
	eq(v.thumb_size, Vector2(72, 48), "第 0 幕缩略图 72x48")
	eq(v._map.position, Vector2(45, 31), "窄矮的缩略图居中 ((162-72)/2, (111-48)/2)")
	eq(v._dots[0].position, Vector2(69, 27), "单位标记 = 格 x3")
	eq(v._dots.size(), 3, "三个标记")
	check(not v._arrows.any(func(a): return a.visible), "放得下时不显示箭头")
	v.scroll(Vector2i(0, 1))
	eq(v.scroll_pos, Vector2.ZERO, "放得下时不卷动")
	v.free()


func test_tall_map_scroll_and_arrows():
	var v := BattleMapView.new(17, Vector2i(22, 93), [])
	eq(v.thumb_size.y, 279.0, "第 17 幕缩略图高 279")
	eq(v.scroll_pos, Vector2.ZERO, "从左上角开始, 不对准光标")
	check(v._arrows[1].visible and not v._arrows[0].visible, "开始只有下箭头")
	v.scroll(Vector2i(0, 1))
	eq(v.scroll_pos.y, 3.0, "一帧卷 3 像素")
	eq(v._map.position.y, -3.0, "缩略图上移")
	for i in 100:
		v.scroll(Vector2i(0, 1))
	eq(v.scroll_pos.y, 279.0 - 111.0, "到底夹紧")
	check(v._arrows[0].visible and not v._arrows[1].visible, "到底只有上箭头")
	v.free()


func test_pulse_and_close_animation():
	var v := BattleMapView.new(0, Vector2i(24, 16), [[Vector2i(1, 1), 0]])
	var seen := []
	for i in 40:
		v._tick()
		seen.append(v.pulse)
	eq(seen.max(), 16, "呼吸最亮 16/16")
	eq(seen.min(), 4, "最暗 4/16")
	v.open()
	eq(v.position, Vector2(62, 42), "打开第一帧在左 16 像素")
	for i in 5:
		v._tick()
	eq(v.position, Vector2(78, 42), "5 帧后到位")
	eq(v.modulate.a, 1.0, "完全不透明")
	v.dismiss()
	eq(v.position, Vector2(78, 42), "关闭第一帧在原位")
	for i in 4:
		v._tick()
	eq(v.position, Vector2(62, 42), "滑到左 16 像素")
	v._tick()
	check(v.is_queued_for_deletion(), "播完自行释放")
	v.free()

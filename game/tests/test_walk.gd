# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战场单位逐格行走 (BattleUnit.walk / _process): 任意帧长都要走到终点并发 move_finished。
## 回归: 原先 |差| <= 0.01 像素就不再移动、又要 is_equal_approx 才算到格, 帧长不整除格宽时
## (60/144Hz 实机, 无 --fixed-fps) 停在差 0.00x 像素处, 剧情行走与 AI 移动永远等不到 move_finished。


func _assets_ready() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var A = tree.root.get_node_or_null("Assets")
	var C = tree.root.get_node_or_null("Content")
	if A == null or C == null:
		return false
	if A._index.is_empty():
		A._ready()
	if C.packs.is_empty():
		C.load_packs([ContentDB.default_main()])
	return not A._index.is_empty()


func _unit(c: Vector2i) -> BattleUnit:
	var u := BattleUnit.new()
	u.info = {"name": "甲", "camp": 0, "sprite": 1}
	u._anim_dir = "Sprite/man001/001man"
	u.anim = AnimPlayer.new()
	u.anim.play_sound = false
	u.add_child(u.anim)
	u.set_cell(c.x, c.y)
	return u


## 各种帧长 (含实测卡住的 0.006896 秒 = 145 帧/秒) 下都能走完, 用时与帧率无关
func test_walk_finishes_at_any_frame_rate():
	if not _assets_ready():
		check(true, "无资源, 跳过")
		return
	var path := [Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7), Vector2i(9, 8), Vector2i(9, 9)]
	var dist := 3.0 * BattleStage.CELL_W + 2.0 * BattleStage.CELL_H
	for dt in [1.0 / 25, 1.0 / 30, 1.0 / 60, 1.0 / 144, 0.006896, 0.00694444444444, 0.0173, 0.1]:
		for speed in [150.0, 125.0, 75.0, 35.0]:
			var u := _unit(Vector2i(6, 7))
			var done := [false]
			u.move_finished.connect(func(): done[0] = true)
			u.walk(path, speed)
			var frames := 0
			while not done[0] and frames < 100000:
				u._process(dt)
				frames += 1
			check(done[0], "帧长 %.6f 速度 %d 走完" % [dt, speed])
			eq(Vector2i(u.cx, u.cy), Vector2i(9, 9), "帧长 %.6f 速度 %d 终点格" % [dt, speed])
			eq(u.position, Vector2(9 * BattleStage.CELL_W, 9 * BattleStage.CELL_H), "终点像素")
			check(absf(frames * dt - dist / speed) <= dt + 1e-6, "帧长 %.6f 速度 %d 用时 %.3f 应约 %.3f 秒" % [dt, speed, frames * dt, dist / speed])
			u.free()


## 走路指令只改坐标, 不让单位出场 (在场标志只由出场指令置位)。
## 原版第 16~31 关开场脚本对没入队的夏侯仪无条件下达走路指令 (show_group 才受 var14 保护);
## 以前 walk() 顺手置 shown, 没入队的夏侯仪凭空出现并被当玩家单位行动。
func test_d70_walk_does_not_show_hidden_unit():
	if not _assets_ready():
		check(true, "无资源, 跳过")
		return
	var hidden := _unit(Vector2i(6, 7))
	hidden.shown = false
	hidden.visible = false
	hidden.walk([Vector2i(7, 7)], 150.0)
	check(not hidden.shown, "没出场的单位走路后仍不在场")
	check(not hidden.visible, "也不显示")
	hidden.free()
	var on := _unit(Vector2i(6, 7))
	on.shown = true
	on.visible = false
	on.walk([Vector2i(7, 7)], 150.0)
	check(on.shown and on.visible, "在场的单位走路时显示")
	on.free()

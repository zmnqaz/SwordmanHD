# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 施放 / 普攻的转向 (差异, 用户 2026-11-06「分天斩大地图的朝向似乎不对, 一些 AOE 也不对」):
## 原版转向函数 —— 同一格不转; |dy| > |dx| 竖向, 否则横向 (含 |dx| = |dy|); 方向编号 0 南 1 西 2 北 3 东 (= BattleUnit.Dir)。
## 普攻双方互转, 法术 / 绝技 / 道具施放者转向落点, 放完不转回。

const D = BattleUnit.Dir


func test_face_dir_matches_() -> void:
	var o := Vector2i(5, 5)
	eq(BattleView.face_dir(o, o), null, "落点是自己的格: 不转")
	eq(BattleView.face_dir(o, Vector2i(5, 8)), D.SOUTH, "正下")
	eq(BattleView.face_dir(o, Vector2i(5, 2)), D.NORTH, "正上")
	eq(BattleView.face_dir(o, Vector2i(9, 5)), D.EAST, "正右")
	eq(BattleView.face_dir(o, Vector2i(1, 5)), D.WEST, "正左")
	eq(BattleView.face_dir(o, Vector2i(6, 8)), D.SOUTH, "|dy| > |dx| 竖向")
	eq(BattleView.face_dir(o, Vector2i(4, 1)), D.NORTH)
	eq(BattleView.face_dir(o, Vector2i(8, 6)), D.EAST, "|dx| > |dy| 横向")
	eq(BattleView.face_dir(o, Vector2i(7, 7)), D.EAST, "|dx| = |dy| 按横向 (je)")
	eq(BattleView.face_dir(o, Vector2i(3, 3)), D.WEST)
	eq(BattleView.face_dir(o, Vector2i(3, 7)), D.WEST)


func test_face_cell_turns_and_keeps_on_self() -> void:
	var u := BattleUnit.new()
	u.anim = AnimPlayer.new()
	u.add_child(u.anim)
	u.cx = 5
	u.cy = 5
	u.dir = D.NORTH
	var view := BattleView.new(null, null)
	view.face_cell(u, Vector2i(5, 5))
	eq(u.dir, D.NORTH, "对自己 (治疗 / 祝福落在自己格): 朝向不变 (原版直接返回; 复刻以前会转向西)")
	view.face_cell(u, Vector2i(9, 6))
	eq(u.dir, D.EAST, "转向落点")
	view.free()
	u.free()

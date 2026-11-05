# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 选目标进入时光标落点 (TargetState.default_cell, / 比较器, 差异):
## 先看格上站着合法目标的格, 没有才看效果范围有目标的格; 取离行动者最近的, 同距离先 y 小再 x 小


func test_nearest_direct_target_wins() -> void:
	var here := Vector2i(5, 5)
	var cells: Array = [Vector2i(5, 2), Vector2i(7, 5), Vector2i(4, 5)]
	eq(TargetState.default_cell(here, cells, func(_c): return true), Vector2i(4, 5), "最近的 (距离 1)")


func test_tie_breaks_by_y_then_x() -> void:
	var here := Vector2i(5, 5)
	var cells: Array = [Vector2i(6, 5), Vector2i(5, 6), Vector2i(4, 5), Vector2i(5, 4)]
	eq(TargetState.default_cell(here, cells, func(_c): return true), Vector2i(5, 4), "同距离 y 小的先")
	cells = [Vector2i(6, 5), Vector2i(4, 5)]
	eq(TargetState.default_cell(here, cells, func(_c): return true), Vector2i(4, 5), "同 y 时 x 小的先")


func test_heal_defaults_to_caster() -> void:
	var here := Vector2i(5, 5)
	var cells: Array = [Vector2i(5, 4), Vector2i(5, 5), Vector2i(3, 5)]   # 射程含自己 (气愈之术 min 0)
	var occupied := [Vector2i(5, 5), Vector2i(3, 5)]
	eq(TargetState.default_cell(here, cells, func(c): return c in occupied), Vector2i(5, 5), "距离 0 = 施法者自己")


func test_area_cells_only_when_no_direct_target() -> void:
	var here := Vector2i(5, 5)
	var cells: Array = [Vector2i(5, 4), Vector2i(5, 1)]   # (5,4) 只是范围沾到目标, (5,1) 上站着目标
	eq(TargetState.default_cell(here, cells, func(c): return c == Vector2i(5, 1)), Vector2i(5, 1), "有站着目标的格: 不管更近的空落点")
	eq(TargetState.default_cell(here, cells, func(_c): return false), Vector2i(5, 4), "没有: 退到范围落点里最近的")

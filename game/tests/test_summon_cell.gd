# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 召唤落点判定: 技能召唤与道具召唤共用 BattleRules.summon_cell_ok, 不看地形。
## 原版实测: 式鬼 (步行 2) 能召到地形 8 (步行不可通行) 的格子上; 复刻旧版技能路径拦掉、道具路径不拦, 两处不一致。

class FakeSt:
	extends RefCounted
	var width := 4
	var height := 3
	func cell(_x: int, _y: int) -> Dictionary:
		return {"move": 8}   # 全图地形类别 8: 步行类单位不可通行


class FakeScene:
	extends RefCounted
	var st := FakeSt.new()
	var units: Array = []


func test_summon_cell_ignores_terrain() -> void:
	var sc := FakeScene.new()
	var hidden := BattleUnit.new()   # 预置的隐藏召唤物: 未现身
	hidden.man = {"unit_id": 10}
	hidden.alive = false
	hidden.shown = false
	sc.units = [hidden]
	var r := BattleRules.new(sc)
	var sk := {"power": 10}
	check(r.summon_cell_ok(sk, Vector2i(1, 1)), "步行单位召到不可通行地形也允许 (原版实测)")
	check(not r.summon_cell_ok({"power": 11}, Vector2i(1, 1)), "没有预置的隐藏召唤物不能召")
	sc.units.clear()
	hidden.free()

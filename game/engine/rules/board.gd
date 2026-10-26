# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 战场棋盘: 地形类别网格 + 单位列表。纯数据, 供移动、射程、AI 使用。
## 地形类别 = mapNN.dtl 每格第 1 字节。

var width: int = 0
var height: int = 0
var terrain := PackedInt32Array()
var units: Array = []       # UnitState


func _init(w: int = 0, h: int = 0, fill_class: int = 0) -> void:
	width = w
	height = h
	terrain.resize(w * h)
	terrain.fill(fill_class)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func terrain_class(c: Vector2i) -> int:
	return terrain[c.y * width + c.x]


func set_terrain(c: Vector2i, cls: int) -> void:
	terrain[c.y * width + c.x] = cls


## 从字符串行设置地形 (测试便利): 每个字符是一位十六进制类别, '.' = 0。
func set_rows(rows: Array) -> void:
	for yy in rows.size():
		var row: String = rows[yy]
		for xx in row.length():
			var ch := row[xx]
			set_terrain(Vector2i(xx, yy), 0 if ch == "." else ch.hex_to_int())


func add_unit(u) -> void:
	units.append(u)


func unit_at(c: Vector2i):
	for u in units:
		if u.alive and u.x == c.x and u.y == c.y:
			return u
	return null


func living() -> Array:
	return units.filter(func(u): return u.alive)


func hostiles_of(u) -> Array:
	return units.filter(func(o): return o.alive and o.side != u.side)


func allies_of(u) -> Array:
	return units.filter(func(o): return o.alive and o.side == u.side)


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

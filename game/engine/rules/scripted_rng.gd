# SPDX-License-Identifier: GPL-3.0-only
extends "res://engine/rules/rng.gd"
## 测试用随机数: 依次返回给定的 rand() 值; 用完后返回 fallback (默认 0: 几率判定必成功、随机项取最小)。
## 想让 rand()%100 得到 v, 直接放 v (v < 100)。

var queue: Array = []
var fallback: int = 0
var used: int = 0


func _init(values: Array = [], fallback_value: int = 0) -> void:
	queue = values.duplicate()
	fallback = fallback_value


func push(values: Array) -> void:
	queue.append_array(values)


func rand() -> int:
	used += 1
	if queue.is_empty():
		return fallback
	return int(queue.pop_front())


func remaining() -> int:
	return queue.size()

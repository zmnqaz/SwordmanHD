# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 胜负判定表以类型 0 结束: 原版 JUDGE 循环读到类型 0 立即返回, 其后的条目不再判定。
## BattleRules.judge (战场用) 与 Flow.judge (纯规则) 要一致。

const Flow = preload("res://engine/rules/flow.gd")


class FakeSt:
	extends RefCounted
	var width := 2
	var height := 2
	var judge := {"win": [], "lose": []}
	func cell(_x: int, _y: int) -> Dictionary:
		return {"move": 0}


class FakeScene:
	extends RefCounted
	var st := FakeSt.new()
	var units: Array = []


func test_type0_ends_list() -> void:
	var sc := FakeScene.new()
	var r := BattleRules.new(sc)
	# 场上没有敌人: 全灭条件 (type 1) 成立。type 0 在它前面时不应判定
	sc.st.judge = {"win": [{"type": 0, "id": 0, "event": 5}, {"type": 1, "id": 0, "event": 7}], "lose": []}
	eq(r.judge().result, "", "type 0 之后的条目不判定")
	sc.st.judge = {"win": [{"type": 1, "id": 0, "event": 7}, {"type": 0, "id": 0, "event": 0}], "lose": []}
	var j := r.judge()
	eq(j.result, "win", "type 0 之前的条目照常判定")
	eq(j.event, 7)
	eq(Flow.judge([], [{"type": 0, "event": 5}, {"type": 1, "id": 0, "event": 7}], []).result, "", "Flow.judge 同样")

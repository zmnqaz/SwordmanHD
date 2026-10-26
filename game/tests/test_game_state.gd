# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## GameState: 进度数据、存档字典往返 (经 JSON 后数字变 float, 要能还原)


func _sample() -> GameState:
	var s := GameState.new()
	s.stage = 3
	s.next_stage = 4
	s.camp_no = 3
	s.gold = 120
	s.bag = [5, 7, 7]
	s.set_data(10, 2)
	s.set_data(101, -1)
	s.seeded[0] = true
	s.party[1] = {"lv": 4, "gear": {"weapon": 29}}
	return s


func test_dict_roundtrip_through_json():
	var a := _sample()
	var b := GameState.new()
	b.apply_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	eq(b.stage, 3)
	eq(b.next_stage, 4)
	eq(b.camp_no, 3)
	eq(b.gold, 120)
	eq(b.bag, [5, 7, 7])
	eq(b.get_data(10), 2)
	eq(b.get_data(101), -1)
	eq(b.get_data(999), 0, "未设置的变量为 0")
	check(b.seeded.has(0), "seeded")
	eq(int(b.party[1]["lv"]), 4)


func test_reset_and_items():
	var s := _sample()
	check(s.has_item(7), "有 7")
	s.add_item(9)
	check(s.has_item(9), "加入 9")
	eq(s.party_of(1).get("lv"), 4)
	eq(s.party_of(2), {}, "无此人返回空")
	s.reset()
	eq(s.bag, [])
	eq(s.gold, 0)
	s.reset(5)
	eq(s.gold, 5, "新游戏初始金钱来自 params.initial_gold ")
	eq(s.stage, 0)
	eq(s.game_data.size(), 0)
	eq(s.party.size(), 0)

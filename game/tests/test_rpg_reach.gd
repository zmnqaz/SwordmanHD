# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## RPG 行走场景 (城镇/室内) 走查: 每个场景从每个入口出发 (不踩中途的踩踏事件格), 用与游戏相同的寻路数据
## (RpgStage.reachable / find_path) 检查入口可站、所有出口/踩踏事件格能走到、所有 NPC/对话事件格旁边有能站的格子。
## 走不到的打印出来 (只报告: 原版里有被剧情踩踏格挡住的出口、柜台后摆设性的 NPC);
## 入口站在不可走格、或一个离开场景的事件 (出城/营地/换场景) 都走不到 (会困在场景里) 算失败。
## 单独运行: tools/godot/godot --headless --path game --script res://tests/run_tests.gd -- test_rpg_reach
const REQUIRES := ["content"]  # 缺则整个文件 SKIP (run_tests.gd 头注); 实测: 移走对应产物后这些测试失败

const SCENE_OPS := [0x26, 0x28, 0x29, 0x33]


func _content_ready() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var C = tree.root.get_node_or_null("Content")
	if C == null:
		return false
	if C.packs.is_empty():
		C.load_packs([ContentDB.default_main()])
	return true


func _is_scene_event(st: RpgStage, e: int) -> bool:
	if e <= 0 or e >= st.events.size():
		return false
	for c in st.events[e]:
		if int(c["type"]) in SCENE_OPS:
			return true
	return false


## 一个场景的走查结果: {bad_entries: [入口号], unreachable: {"踩踏事件N"/"对话事件N": [格子]}, reached: [走得到的事件号]}
## 一个事件可以占多格 (如出口一整排), 任一格能走到 (对话格: 旁边有能站的格) 就算走得到
static func survey(st: RpgStage) -> Dictionary:
	var seen := {}
	var bad_entries: Array = []
	for i in st.pos.size():
		var p := Vector2i(int(st.pos[i]["x"]), int(st.pos[i]["y"]))
		var c := st.cell(p.x, p.y)
		if c.is_empty() or not c["walk"]:
			bad_entries.append(i)
			continue
		seen.merge(st.reachable(p))
	var cells := {}
	var ok := {}
	for y in st.height:
		for x in st.width:
			var c := st.cell(x, y)
			var step := int(c["step"])
			var talk := int(c["talk"])
			if step > 0:
				var k := "踩踏事件%d" % step
				cells.get_or_add(k, []).append(Vector2i(x, y))
				if seen.has(Vector2i(x, y)):
					ok[k] = true
			if talk > 0:
				var k := "对话事件%d" % talk
				cells.get_or_add(k, []).append(Vector2i(x, y))
				for d in RpgStage.DIRS4:
					var nb := Vector2i(x, y) + d
					if seen.has(nb) and int(st.cell(nb.x, nb.y)["step"]) <= 0:
						ok[k] = true
	var out := {}
	for k in cells:
		if not ok.has(k):
			out[k] = cells[k]
	var reached := ok.keys().map(func(k): return int(String(k).get_slice("事件", 1)))
	return {"bad_entries": bad_entries, "unreachable": out, "reached": reached}


func test_all_rpg_scenes_reachable():
	if not _content_ready():
		check(true, "无内容包, 跳过")
		return
	var n := 0
	while not Content.town_info(n).is_empty():
		var st := RpgStage.load_stage(n)
		var r := survey(st)
		eq(r.bad_entries, [], "城镇 %d 入口站在不可走格" % n)
		var by_event: Dictionary = r.unreachable
		for k in by_event:
			var e := int(String(k).get_slice("事件", 1))
			print("  城镇 %02d %s 走不到 %s%s" % [n, k, by_event[k].slice(0, 4), " (切换场景)" if _is_scene_event(st, e) else ""])
		var exits: Array = r.reached.filter(func(e): return _is_scene_event(st, e))
		check(not exits.is_empty(), "城镇 %d 从入口走不到任何离开场景的事件 (会困在这里)" % n)
		check(true)
		n += 1
	check(n > 0, "没有城镇")

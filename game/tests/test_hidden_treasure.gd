# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 隐藏宝箱显示开关 (BattleFlow.refresh_hidden_treasures): 默认不画 (原版), 开了画成半透明图标, 即时刷新, 拿走后释放


class FakeScene:
	extends Node
	var st: BattleStage
	var units_node := Node2D.new()
	func _init(s: BattleStage) -> void:
		st = s
		add_child(units_node)


## 图标换成普通节点 (不依赖原版资源与动画)
class TestFlow:
	extends BattleFlow
	func _init(s) -> void:
		super._init(s, null, null, null)
	var red_flags := []   # 每次建图标时 red 参数 (隐藏宝箱应为 true)
	func _make_chest_icon(c: Vector2i, red := false) -> Node2D:
		red_flags.append(red)
		var n := Node2D.new()
		n.position = Vector2(c)
		bs.units_node.add_child(n)
		return n


func _flow(show_hidden: int) -> TestFlow:
	var st := BattleStage.new()
	st.width = 4
	st.height = 1
	st.mevt = [
		{"type": 0, "parm1": 0, "parm2": 0, "item_type": 0, "item1": 0, "item2": 0, "show": 0},    # 0 剧情事件: 永不画宝箱
		{"type": 1, "parm1": 0, "parm2": 0, "item_type": 1, "item1": 5, "item2": 0, "show": -1},   # 1 隐藏宝物
		{"type": 1, "parm1": 0, "parm2": 0, "item_type": 2, "item1": 100, "item2": 0, "show": 0},  # 2 普通宝物
	]
	for x in 4:
		st.cells.append({"move": 0, "floor": 0, "event": [-1, 0, 1, 2][x]})
	var f := TestFlow.new(FakeScene.new(st))
	f.gc = GameContext.new()
	f.gc.settings["show_hidden"] = show_hidden
	f.init_map_events()
	return f


func _free(f: TestFlow) -> void:
	f.bs.free()
	f.free()


func test_is_hidden_chest_rules():
	check(BattleFlow.is_hidden_chest({"type": 1, "show": -1}), "type>0 且 show==-1 才是隐藏宝箱")
	check(not BattleFlow.is_hidden_chest({"type": 0, "show": -1}), "剧情事件不算")
	check(not BattleFlow.is_hidden_chest({"type": 1, "show": 0}), "普通宝物不算")


func test_default_off_draws_only_visible_chest():
	var f := _flow(0)
	eq(f._treasures.size(), 1, "只有普通宝物有图标 (事件 2)")
	check(f._treasures.has(2) and not f._treasures.has(1), "隐藏宝物和剧情事件不画")
	eq(f._hidden_icons.size(), 0, "开关关: 没有隐藏宝箱图标 (与原版一致)")
	_free(f)


func test_on_draws_translucent_hidden_chests_and_toggles_live():
	var f := _flow(1)
	eq(f._hidden_icons.keys(), [1], "开关开: 隐藏宝物 (事件 1) 有图标")
	var icon: Node2D = f._hidden_icons[1][0]
	eq(f._hidden_icons[1].size(), 1, "隐藏宝箱只有一个闪光图标 (红色版), 没有别的标记")
	eq(f.red_flags, [false, true], "正常宝箱是原版蓝白闪光, 隐藏宝箱是红色版")
	eq(f._treasures.size(), 1, "正常宝物图标不受影响")
	f.gc.settings["show_hidden"] = 0
	f.gc.settings_applied.emit()
	eq(f._hidden_icons.size(), 0, "设定改回关: 即时去掉")
	check(icon.is_queued_for_deletion(), "图标被释放")
	f.gc.settings["show_hidden"] = 1
	f.gc.settings_applied.emit()
	eq(f._hidden_icons.keys(), [1], "再开: 重新出现")
	_free(f)


func test_taking_the_chest_removes_its_hidden_icon():
	var f := _flow(1)
	var icon: Node2D = f._hidden_icons[1][0]
	f.take_map_event(1)
	check(not f.map_events.has(1), "事件已消耗")
	eq(f._hidden_icons.size(), 0, "隐藏图标随宝物一起消失")
	check(icon.is_queued_for_deletion())
	f.gc.settings_applied.emit()
	eq(f._hidden_icons.size(), 0, "刷新不会把已拿走的宝箱画回来")
	_free(f)

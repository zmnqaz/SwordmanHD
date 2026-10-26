# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 隐藏宝箱提示 (engine/battle/ui/battle_hidden_tip.gd): 设定开/关、光标在/不在隐藏宝箱格、拿走后消失、非玩家阶段不显示、文字与位置

const STRINGS := {"battle.hidden_tip": "隐藏: %s", "battle.chest_tip": "宝物: %s", "battle.hidden_tip.gold": "金钱%d两", "battle.hidden_tip.event": "事件"}


class FakeFlow:
	extends RefCounted
	var map_events := {}


class FakeCtl:
	extends RefCounted
	var flow := FakeFlow.new()


## 只给提示组件用到的场景接口
class FakeScene:
	extends RefCounted
	var st: BattleStage
	var ctl := FakeCtl.new()
	var cam := Vector2.ZERO
	var cur := Vector2i(-1, -1)
	var player_phase := true
	func view() -> Vector2:
		return Vector2(320, 200)
	func cursor_cell() -> Vector2i:
		return cur
	func in_player_phase() -> bool:
		return player_phase


## 一行 4 格: 0 无事件, 1 剧情事件, 2 隐藏物品宝箱 (物品 5), 3 普通宝箱; 外加隐藏金钱宝箱放在第 2 行 0 格
func _scene() -> FakeScene:
	var st := BattleStage.new()
	st.width = 4
	st.height = 2
	for e in [-1, 0, 1, 2, 3, -1, -1, -1]:
		st.cells.append({"move": 0, "floor": 0, "event": e})
	var s := FakeScene.new()
	s.st = st
	s.ctl.flow.map_events = {
		0: {"type": 0, "item_type": 0, "item1": 0, "show": -1},    # 剧情事件 (show -1 也不算宝箱)
		1: {"type": 1, "item_type": 1, "item1": 5, "show": -1},    # 隐藏物品
		2: {"type": 1, "item_type": 2, "item1": 100, "show": 0},   # 普通金钱宝箱 (看得见, 提示「宝物: ...」)
		3: {"type": 1, "item_type": 2, "item1": 300, "show": -1},  # 隐藏金钱
	}
	return s


func _tip(s: FakeScene, show_hidden: int) -> BattleHiddenTip:
	var t := BattleHiddenTip.new()
	t.gc = GameContext.new()
	t.gc.settings["show_hidden"] = show_hidden
	t.bs = s
	return t


func test_text_item_gold_event():
	UiStrings.use(STRINGS)
	eq(BattleHiddenTip.tip_text({"type": 1, "item_type": 1, "item1": 5, "show": -1}), "隐藏: " + BattleFlow.item_name(5), "物品: 走 Content 物品表")
	eq(BattleHiddenTip.tip_text({"type": 1, "item_type": 2, "item1": 300, "show": -1}), "隐藏: 金钱300两", "金钱: 显示金额")
	eq(BattleHiddenTip.tip_text({"type": 1, "item_type": 0, "item1": 0, "show": -1}), "隐藏: 事件", "事件宝物")
	eq(BattleHiddenTip.tip_text({"type": 1, "item_type": 1, "item1": 5, "show": 0}), "宝物: " + BattleFlow.item_name(5), "看得见的普通宝箱: 前缀「宝物」")
	eq(BattleHiddenTip.tip_text({}), "", "没有宝箱: 空")
	UiStrings.use(null)


func test_setting_off_shows_nothing():
	UiStrings.use(STRINGS)
	var s := _scene()
	var t := _tip(s, 0)
	s.cur = Vector2i(2, 0)
	eq(t.current_text(), "", "设定关: 光标在隐藏宝箱格上也不显示 (原版行为)")
	t.gc.settings["show_hidden"] = 1.0
	eq(t.current_text(), "隐藏: " + BattleFlow.item_name(5), "设定开 (JSON 读回 1.0): 显示")
	t.free()
	UiStrings.use(null)


func test_only_on_chest_cell():
	UiStrings.use(STRINGS)
	var s := _scene()
	var t := _tip(s, 1)
	s.cur = Vector2i(2, 0)
	eq(t.current_text(), "隐藏: " + BattleFlow.item_name(5), "隐藏物品宝箱格")
	s.cur = Vector2i(0, 1)
	eq(t.current_text(), "隐藏: 金钱300两", "隐藏金钱宝箱格")
	s.cur = Vector2i(3, 0)
	eq(t.current_text(), "宝物: 金钱100两", "普通宝箱格 (看得见的)")
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(-1, -1)]:
		s.cur = c
		eq(t.current_text(), "", "空格 / 剧情事件 / 光标不可见: 不显示 %s" % c)
	t.free()
	UiStrings.use(null)


func test_gone_after_taken():
	UiStrings.use(STRINGS)
	var s := _scene()
	var t := _tip(s, 1)
	s.cur = Vector2i(2, 0)
	check(t.current_text() != "")
	s.ctl.flow.map_events.erase(1)   # BattleFlow.take_map_event 拿走宝物时删掉该事件
	eq(t.current_text(), "", "拿走后提示消失")
	t.free()
	UiStrings.use(null)


func test_not_outside_player_phase():
	UiStrings.use(STRINGS)
	var s := _scene()
	var t := _tip(s, 1)
	s.cur = Vector2i(2, 0)
	s.player_phase = false
	eq(t.current_text(), "", "剧情/对白/敌方回合等非操作阶段: 不显示")
	t.bs = null
	eq(t.current_text(), "", "不在战场: 不显示")
	t.free()
	UiStrings.use(null)


func test_pos_alone_matches_coord_rule():
	var v := Vector2(320, 200)
	eq(BattleHiddenTip.tip_pos(Vector2i(3, 5), Vector2.ZERO, v, 40.0, false), BattleCoord.tag_pos(Vector2i(3, 5), Vector2.ZERO, v, 40.0), "不开坐标: 与坐标标签同位置 (格上方)")
	eq(BattleHiddenTip.tip_pos(Vector2i(3, 0), Vector2.ZERO, v, 40.0, false).y, 25.0, "第一行: 放格下方")


func test_pos_stacks_beside_coord_tag():
	var v := Vector2(320, 200)
	var row := BattleCoord.LABEL_SIZE + 3.0
	var coord := BattleCoord.tag_pos(Vector2i(3, 5), Vector2.ZERO, v, 8.0)
	eq(BattleHiddenTip.tip_pos(Vector2i(3, 5), Vector2.ZERO, v, 40.0, true).y, coord.y - row, "坐标在格上方: 提示再往上一行")
	eq(BattleHiddenTip.tip_pos(Vector2i(3, 0), Vector2.ZERO, v, 40.0, true).y, 25.0 + row, "坐标翻到格下方: 提示再往下一行")
	eq(BattleCoord.tag_pos(Vector2i(3, 1), Vector2(0, 2), v, 8.0).y, 11.0, "(前提) 坐标标签刚好还在格上方")
	eq(BattleHiddenTip.tip_pos(Vector2i(3, 1), Vector2(0, 2), v, 40.0, true).y, 47.0, "坐标在上但再上一行出画面: 提示放格下方 (2*24-2+1)")
	check(BattleHiddenTip.tip_pos(Vector2i(10, 5), Vector2.ZERO, v, 40.0, true).x + 40.0 <= 320.0, "横向夹在画面内")

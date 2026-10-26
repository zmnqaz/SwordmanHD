# SPDX-License-Identifier: GPL-3.0-only
class_name BattleHiddenTip
extends Node2D
## 宝箱提示 (设定「宝箱显示」开着时; 原版没有, 只画不改规则): 光标停在还没拿走的宝箱格上时, 在格旁显示里面是什么:
##   隐藏宝箱 (BattleFlow.is_hidden_chest) 「隐藏: <物品名>」, 看得见的普通宝箱「宝物: <物品名>」
##   (物品名走 Content 物品表, 随当前语言; 金钱类显示金额; 事件宝物显示「事件」)。2026-10-11 用户: 普通宝箱也要能看内容。
## 设定关时完全不显示 (原版行为); 宝物拿走后 (BattleFlow.take_map_event 删掉该事件) 提示随之消失。
## 显示时机同格子坐标 (BattleCoord): 只在玩家操作阶段; 触屏点格子同样触发 (只看光标所在格)。
## 样式与位置规则沿用 BattleCoord (字号/颜色/描边/半透明底); 与格子坐标同开时叠在坐标标签外侧, 不互相遮挡。
## 数据只读: 关卡格子的事件号 (bs.st) + 当前还在的地图事件 (bs.ctl.flow.map_events, 已拿走的已删)。

var gc: GameContext = GameContext.current()
var bs                        # 战场场景 (BattleScene): st / ctl.flow / cam / view() / cursor_cell() / in_player_phase()

var _tag: UiText
var _key := ""
var _tag_pos := Vector2.ZERO
var _tag_text := ""


## 设定值是否为「开」(JSON 读回的 1.0 也算)
static func _on(setting) -> bool:
	return (setting is int or setting is float) and int(setting) == 1


## 光标格上还没拿走的宝箱 (MEVT 宝物类 type > 0, 隐藏的或看得见的); 没有返回 {} (剧情事件 type 0 不算)
static func chest_at(st, events: Dictionary, c: Vector2i) -> Dictionary:
	if st == null or c.x < 0 or c.y < 0:
		return {}
	var e := int(st.cell(c.x, c.y).get("event", -1))
	var m: Dictionary = events.get(e, {})
	return m if not m.is_empty() and int(m.get("type", 0)) > 0 else {}


## 提示文字: 物品 (item_type 1) = 物品名, 金钱 (2) = 金额, 事件宝物 (0) = 「事件」
static func tip_text(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	var what := ""
	match int(m.get("item_type", 0)):
		1:
			what = BattleFlow.item_name(int(m["item1"]))
		2:
			what = UiStrings.t("battle.hidden_tip.gold", [int(m["item1"])])
		_:
			what = UiStrings.t("battle.hidden_tip.event")
	return UiStrings.t("battle.hidden_tip" if BattleFlow.is_hidden_chest(m) else "battle.chest_tip", [what])


## 标签左上角: 不开格子坐标时与坐标标签同规则 (格上方, 靠顶放下方, BattleCoord.tag_pos);
## 开着格子坐标时叠在坐标标签外侧 (坐标在上 → 再往上一行, 放不下就放格下方; 坐标在下 → 再往下一行)
static func tip_pos(c: Vector2i, cam: Vector2, view: Vector2, text_w: float, coord_on: bool, cell := FxPlace.CELL) -> Vector2:
	var p := BattleCoord.tag_pos(c, cam, view, text_w, cell)
	if not coord_on:
		return p
	var row := BattleCoord.LABEL_SIZE + 3.0
	var above := c.y * cell.y - cam.y - row
	var below := (c.y + 1) * cell.y - cam.y + 1.0
	var coord_y := BattleCoord.tag_pos(c, cam, view, 0.0, cell).y
	if coord_y < (above + below) / 2.0:     # 坐标标签在格上方
		p.y = above - row if above - row >= 1.0 else below
	else:
		p.y = below + row
	p.y = clampf(p.y, 1.0, maxf(1.0, view.y - BattleCoord.LABEL_SIZE - 3.0))
	return p


func _ready() -> void:
	z_index = 30
	_tag = UiText.new("", BattleCoord.LABEL_SIZE, BattleCoord.LABEL_COLOR)
	_tag.flags = "edge5"
	_tag.edge_color = BattleCoord.EDGE_COLOR
	add_child(_tag)
	visible = false


## 当前该显示的文字 (不显示时为空); 设定关时不去问场景
func current_text() -> String:
	if bs == null or not _on(gc.settings.get("show_hidden", 0)) or not bs.in_player_phase():
		return ""
	var flow = bs.ctl.flow if bs.ctl != null else null
	if flow == null:
		return ""
	return tip_text(chest_at(bs.st, flow.map_events, bs.cursor_cell()))


func _process(_delta: float) -> void:
	var text := current_text()
	visible = text != ""
	if text == "":
		_key = ""
		return
	var view: Vector2 = bs.view()
	var cur: Vector2i = bs.cursor_cell()
	var coord_on := _on(gc.settings.get("coord", 0))
	var key := "%s|%s|%s|%s|%s" % [bs.cam.round(), view, cur, text, coord_on]
	if key == _key:
		return
	_key = key
	_tag_text = text
	_tag.text = text
	_tag_pos = tip_pos(cur, bs.cam.round(), view, UiText.measure(text, BattleCoord.LABEL_SIZE), coord_on)
	_tag.position = _tag_pos
	queue_redraw()


func _draw() -> void:
	if _tag_text != "":
		var w := UiText.measure(_tag_text, BattleCoord.LABEL_SIZE) + 2.0
		draw_rect(Rect2(_tag_pos - Vector2(1, 1), Vector2(w, BattleCoord.LABEL_SIZE + 2.0)), BattleCoord.PLATE)

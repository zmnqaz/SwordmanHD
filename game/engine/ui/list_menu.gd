# SPDX-License-Identifier: GPL-3.0-only
class_name UiListMenu
extends Node2D
## 法术列表 / 物品列表 (素材 Misc/Man_int)。两种布局见 SPELL / ITEM, 坐标为原版像素。
##   面板: 法术第 44 帧 (246x94), 物品第 45 帧 (202x83); 居中 x=(320-宽)/2, y=(199-面板高-33)/2 (原式含地图缓冲区边框 +30/+24)。
##   说明栏: 第 46 帧 (202x33), x=(319-202)/2, y=面板y+面板高+1; 文字第一行 (12,4)、第二行 (12,17), 每行最多 15 个汉字。
##   行: 10 格分左右两列各 5 行, 不翻页; 槽 0~4 左列、5~9 右列。
##   选中行: 1 像素空心框, 颜色 RGB555 0x64a5; 不可用项约 25% 不透明 (选得中, 确认无反应)。
##   打开: 列表从左、说明栏从右滑入, 偏移 8→4→2→0 并淡入 (UiSlide)。
## 方向: 上下 ±1 (槽 4 往下到槽 5), 左右 ±5 换列; 目标是空槽就不动。
## 按键由调用方传入: move(Vector2i) / confirm() / cancel()。
## 坐标/帧号取自布局表 listmenu.<spell|item|desc>.* (resolve(), 缺省为下面 SPELL / ITEM 的原版值); 面板宽高按素材帧原版 1 倍外框。
##
## 行数据 (Array of Dictionary):
##   法术: {"name", "desc", "mp", "move", "enabled"}       (mp/move 为术力、移动消耗)
##   物品: {"name", "desc", "type" (0 道具 1 武器 2 护具 3 饰物), "equip" (-1 / 0 当前武器 / 1 防具 / 2 饰物), "enabled"}

signal confirmed(index: int)
signal cancelled
signal selection_changed(index: int)

const SLOTS := 10
const HALF := 5
## 两种列表: 布局全部在 listmenu.<kind>.* (面板帧、行点表、名字/图标/数字位置), 这里只是种类
const SPELL := {"kind": "spell"}
const ITEM := {"kind": "item"}

var layout: Dictionary = SPELL
var rows: Array = []
var selected := 0
var anim_dir := ThemeAssets.p("ui.menu_icons")
var is_open := false

var _list: Node2D          # 面板 + 行 + 选中框 (整体滑动)
var _desc: Node2D          # 说明栏
var _panel: UiPanel
var _desc_panel: UiPanel
var _rows_node: Node2D
var _box: _Box
var _desc_text: Array[UiText] = []
var _list_pos := Vector2.ZERO
var _desc_pos := Vector2.ZERO


class _Box:
	extends Node2D
	var size := Vector2.ZERO
	var color := Color.RED

	func _draw() -> void:
		# 原版画 (x,y)~(x+w,y+h) 的 1 像素空心框 (两端都含)
		var w := size.x + 1
		var h := size.y + 1
		draw_rect(Rect2(0, 0, w, 1), color)
		draw_rect(Rect2(0, h - 1, w, 1), color)
		draw_rect(Rect2(0, 0, 1, h), color)
		draw_rect(Rect2(w - 1, 0, 1, h), color)


func _init() -> void:
	_list = CanvasGroup.new()  # 整体淡入: 子节点先合成再乘透明度, 重叠处不会透出底图
	add_child(_list)
	_panel = UiPanel.new()
	_list.add_child(_panel)
	_rows_node = Node2D.new()
	_list.add_child(_rows_node)
	_box = _Box.new()
	_box.color = UiLayout.color(UiLayout.val("listmenu.select_box", "color", "box.select"))
	_list.add_child(_box)
	_desc = CanvasGroup.new()
	add_child(_desc)
	_desc_panel = UiPanel.new(anim_dir, UiLayout.frame("listmenu.desc.panel"))
	_desc.add_child(_desc_panel)
	for k in int(UiLayout.el("listmenu.desc.text").get("repeat", {}).get("count", 2)):
		var t := UiText.make("listmenu.desc.text", "", k)
		_desc.add_child(t)
		_desc_text.append(t)
	visible = false


## 布局: {kind, id 前缀 k, panel_frame}
static func resolve(lay: Dictionary) -> Dictionary:
	var kind := String(lay.get("kind", "spell"))
	var k := "listmenu." + kind
	return {"kind": kind, "k": k, "panel_frame": UiLayout.frame(k + ".panel")}


## 面板位置 (((320-w)/2, (199-h-说明栏高)/2), w/h = 面板帧原版外框; 公式在布局表)
static func panel_pos(lay: Dictionary) -> Vector2:
	var k := "listmenu.%s.panel" % String(lay.get("kind", "spell"))
	return UiLayout.at(k, 0, {"dh": int(_desc_size().y)})


## 说明栏位置 (x=(319-w)/2, y=面板底+1)
static func desc_pos(lay: Dictionary) -> Vector2:
	var k := "listmenu.%s.panel" % String(lay.get("kind", "spell"))
	var p := panel_pos(lay)
	var ph := UiPanel.frame_rect(String(UiLayout.sprite(k).get("anim", "")), UiLayout.frame(k)).size.y
	return UiLayout.at("listmenu.desc.panel", 0, {"py": int(p.y), "ph": int(ph)})


static func _desc_size() -> Vector2:
	return UiPanel.frame_rect(String(UiLayout.sprite("listmenu.desc.panel").get("anim", "")), UiLayout.frame("listmenu.desc.panel")).size


## 某槽的行左上角 (相对面板; 布局表 listmenu.<kind>.row 点表, 槽 0~4 左列、5~9 右列)
func slot_pos(i: int) -> Vector2:
	return UiLayout.at(String(layout["k"]) + ".row", i)


func _row_size() -> Vector2:
	return UiLayout.size_of(String(layout["k"]) + ".row")


## 指针 (engine/ui/ui_hit.gd): 各行 (不可用的也选得中, 确认无反应, 同键盘)
func ui_hits() -> Array:
	var out: Array = []
	for i in rows.size():
		out.append(UiHit.area(Rect2(slot_pos(i), _row_size()), i, _list))
	return out


func ui_select(k) -> void:
	if k != selected:
		select(k)
		selection_changed.emit(selected)


## 换数据。sel<0 时选第一个可用槽 (物品列表原版行为), 都不可用则选 0
func setup(lay: Dictionary, items: Array, sel := -1) -> void:
	layout = resolve(lay)
	lay = layout
	rows = items.slice(0, SLOTS)
	_panel.set_frame(anim_dir, int(lay["panel_frame"]))
	UiLayout.tag_panel(_panel, "listmenu.%s.panel" % lay["kind"])
	UiLayout.tag_panel(_desc_panel, "listmenu.desc.panel")
	_list_pos = panel_pos(lay)
	_desc_pos = desc_pos(lay)
	_list.position = _list_pos
	_desc.position = _desc_pos
	_build_rows()
	if sel < 0:
		sel = 0
		for i in rows.size():
			if rows[i].get("enabled", true):
				sel = i
				break
	selected = clampi(sel, 0, maxi(0, rows.size() - 1))
	_refresh_selection()


func _build_rows() -> void:
	for c in _rows_node.get_children():
		_rows_node.remove_child(c)
		c.queue_free()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var n := Node2D.new()
		n.position = slot_pos(i)
		_rows_node.add_child(n)
		var k := String(layout["k"])
		if layout["kind"] == "spell":
			n.add_child(UiLayout.panel(k + ".tag"))
			n.add_child(UiLayout.number(k + ".num", int(r.get("mp", 0)), 0))
			n.add_child(UiLayout.number(k + ".num", int(r.get("move", 0)), 1))
		else:
			for part in [[k + ".type", int(r.get("type", -1))], [k + ".equip", int(r.get("equip", -1))]]:
				var frames: Array = UiLayout.sprite(part[0]).get("frames", [])
				if part[1] >= 0 and part[1] < frames.size():
					n.add_child(UiPanel.new(anim_dir, int(frames[part[1]]), UiLayout.at(part[0])))
		n.add_child(UiText.make(k + ".name", String(r.get("name", ""))))
		n.modulate.a = 1.0 if r.get("enabled", true) else UiLayout.num("listmenu.disabled_alpha", "value", 1.0)


func _refresh_selection() -> void:
	_box.visible = not rows.is_empty()
	if rows.is_empty():
		_set_desc("")
		return
	_box.position = slot_pos(selected)
	_box.size = _row_size() - Vector2.ONE
	_set_desc(String(rows[selected].get("desc", "")))


func _set_desc(s: String) -> void:
	var lines := UiText.wrap_chars(s, maxi(1, int(UiLayout.text("listmenu.desc.text").get("wrap_chars", 15))))
	for k in _desc_text.size():
		_desc_text[k].text = lines[k] if k < lines.size() else ""


## 打开 (滑入淡入)。返回 Tween, 可 await .finished
func open() -> Tween:
	visible = true
	is_open = true
	UiSlide.run(_desc, _desc_pos, Vector2.RIGHT, UiSlide.LIST_OFFSETS, true)
	return UiSlide.run(_list, _list_pos, Vector2.LEFT, UiSlide.LIST_OFFSETS, true)


## 收起。TODO: 原版收起时是否也有滑出动画未查, 暂按反向播放
func close(animated := true) -> void:
	is_open = false
	if not animated:
		visible = false
		return
	UiSlide.run(_desc, _desc_pos, Vector2.RIGHT, UiSlide.LIST_OFFSETS, false)
	await UiSlide.run(_list, _list_pos, Vector2.LEFT, UiSlide.LIST_OFFSETS, false).finished
	if not is_open:  # 收起动画期间又 open() 了: 别把刚打开的菜单藏掉
		visible = false


## d: 上下 (0,±1) 加减 1, 左右 (±1,0) 加减 5; 目标为空槽或越界不动。返回是否移动了
func move(d: Vector2i) -> bool:
	if rows.is_empty():
		return false
	var k := selected + d.y if d.y != 0 else selected + HALF * d.x
	if k < 0 or k >= SLOTS or k >= rows.size():
		return false
	selected = k
	_refresh_selection()
	selection_changed.emit(selected)
	return true


func select(k: int) -> void:
	if k >= 0 and k < rows.size():
		selected = k
		_refresh_selection()


## 确认: 可用项发出 confirmed 并返回槽号; 空列表或不可用项返回 -1 (原版无反应)
func confirm() -> int:
	if rows.is_empty() or not rows[selected].get("enabled", true):
		return -1
	confirmed.emit(selected)
	return selected


func cancel() -> void:
	cancelled.emit()


# ---------------- 数据转换 (内容包 data/*.json -> 行数据) ----------------

## 技能编号列表 -> 法术行; mp/move 为当前剩余术力、移动力 (够不够决定是否可用)
static func spell_rows(skill_ids: Array, mp := 9999, move := 9999) -> Array:
	var out: Array = []
	for id in skill_ids:
		var s: Dictionary = Content.skill_at(int(id))
		out.append({"name": s["name"], "desc": s["desc"], "mp": int(s["mp_cost"]), "move": int(s["move_cost"]),
			"enabled": mp >= int(s["mp_cost"]) and move >= int(s["move_cost"])})
	return out


## 物品编号列表 -> 物品行; equipped: {物品槽号: 0 武器 / 1 防具 / 2 饰物}
static func item_rows(item_ids: Array, equipped := {}, usable := Callable()) -> Array:
	var out: Array = []
	for i in item_ids.size():
		var it: Dictionary = Content.item_at(int(item_ids[i]))
		out.append({"name": it["name"], "desc": it["desc"], "type": int(it["type"]), "equip": int(equipped.get(i, -1)),
			"enabled": usable.call(it) if usable.is_valid() else true})
	return out

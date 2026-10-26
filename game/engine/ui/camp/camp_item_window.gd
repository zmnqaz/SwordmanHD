# SPDX-License-Identifier: GPL-3.0-only
class_name CampItemWindow
extends Node2D
## 囊內乾坤 / 商店: 双栏物品窗 CItemWindow + CItemProcessor (素材 Misc/Item_win)。
## 坐标按原版画面对照得出, 已与原版截图核对:
##   面板: 左栏第 0 帧 (标签在左) 在 (20,21), 右栏第 1 帧 (标签在右) 在 (162,21)。
##   非焦点栏整体压暗到 14/16 (等级 14); 打开时左栏为焦点, Tab 切换焦点。
##   栏名 (行囊 / 人名 / 商店): 在 48 像素宽的标签里居中, 左栏 x = 5 + (48−宽)/2, 右栏 x = 88 + (48−宽)/2, y = 4。
##   行: 每页 8 行, 第 k 行在栏内 (5, 22+13k), 行内:
##     类型图标 第 4~7 帧 (道具/武器/护具/饰物), 不能装备时用带记号的第 8~11 帧 (字段; 人物栏看本人, 行囊栏看对面的人), (0,0)+帧内偏移;
##     名字 (14,0); 已装备标记 第 12/13/14 帧 (武器/护具/饰物) 在 (74,2); 钱币 第 17 帧在 (85,2); 价格 第 15 帧字模 %4d 在 (101,1),
##     营地里显示卖价 = 价格/2, 商店货栏显示原价。
##     已装备的武器、护具不可选 (字段=0), 整行约 25% 不透明。
##   选中框: 1 像素空心框, 颜色 0x64a5, 行内 (−1,−2) 起 132x15, 只画在焦点栏。
##   翻页箭头: 上 第 18~21 帧在栏内 (64,1), 下 第 22~25 帧在 (64,135), 每 4 tick 换一帧。
##   说明栏 ITEM_MB 在 (20,164) (CampDescBar)。金钱框 ITEM_PRO 第 0 帧在 (234,2), 数字 ITEM_PRO 第 1 帧字模 %5d 在框内 (29,4)。
##   三选项菜单 ITEM_MEN: 在 (栏 x+93, 栏 y+13r), r 为选中行在本页的行号; 文字 (13, 9+13i); 箭头 第 1/2 帧在 (3, 9+13i);
##     禁用项改用 0x6acd 色。文字: 給予/裝備/丟棄, 給予/卸下/丟棄, 賣出/裝備/丟棄, 賣出/卸下/丟棄。
##   确认: 问句写在说明栏, 是/否框在 (栏 x+93, 栏 y+13r+30), 默认✗。
##   装备预览 (按住空格, 只对能装备的行): UiEquipPreview。
##   动画: 两栏打开/换内容时滑入 16,8,4,2,0 (左栏从左、右栏从右); 菜单、说明栏、金钱框自左滑入。
##   锚点: 整页 (两栏 + 说明栏) 按安全区居中, 金钱框贴右上 (锚点节点嵌套)。
##   以上坐标、帧号都在布局表 camp.item.* (栏用 which = 0 左 / 1 右 选 "A|B" 项, 行用序号 k, 菜单/是否框用本页行号 r)。
## 按键 (实测): ↑/↓ 选行; (扩展) Q/E 翻一页; ←/→ 循环切换焦点栏的内容 (→ 上一个, ← 下一个, 跳过对面栏正在显示的); Tab 切换焦点;
##   确认 = 打开三选项菜单 (只有可动的物品); 取消 = 关菜单 / 关窗口; 空格按住 = 装备预览。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal closed

const SIDES := ["camp.item.panel.left", "camp.item.panel.right"]
## 行压暗分两档, 来源不同: 已装备/不可移动 = CampUi.FAINT 0.25 (的 4:12 混合);
## 商店里买不起 (价格 > 金钱) = 0.4 (原版截图 逐像素测透出率约 0.35~0.42, 明显比已装备行亮)。
const SHOP_POOR_ALPHA := 0.4
## 物品菜单每种模式的三项 (界面文案键 camp.item.act.<名>): 给予/卖出 x 装备/卸下 x 丢弃
const MENU_ACTS := [["give", "equip", "discard"], ["give", "unequip", "discard"], ["sell", "equip", "discard"], ["sell", "unequip", "discard"]]

var inv: CampInventory
var side_col := [0, 1]      # 左右两栏显示的栏位下标
var focus := 0
var sel := [0, 0]
var top := [0, 0]
var desc: CampDescBar
var _panels: Array[Node2D] = []
var _money: UiNumber
var _menu: Node2D
var _menu_state := {}
var _menu_sel := 0
var _menu_arrow: UiPanel
var _menu_texts: Array = []
var _ask: CampAsk.YesNo
var _ask_action := ""
var _preview: UiEquipPreview
var _arrow_cyc := CampUi.Cycle.new(4, 4)
var _menu_cyc := CampUi.Cycle.new(4, 2)
var _arrows: Array = []
## 下翻箭头标志 [+0x1089]: 只在该栏有焦点时按「本页之后还有物品」重算; 打开时两栏都取左栏的值。
## 所以未取得过焦点的右栏会显示一个与内容无关的下箭头 (原版截图如此)。
var _down_flag := [false, false]
var _rows := 8  # 每页行数 (布局表 camp.item.row repeat.count)
var _panel_pos: Array = []
var _money_pos := Vector2.ZERO


func _init(inventory: CampInventory) -> void:
	inv = inventory
	inv.busy_fn = func(): return _menu != null or _ask != null or _preview != null   # 这些操作按格下标记着物品: 此时不能整理行囊 (攻略面板 F4)
	if inv.shop_mode:
		# 右栏初值 = 第一个在队主角 ( 栏序 [商店] 行囊 各在队主角, 进店右栏初始选中主角栏); 无在队主角回退行囊
		side_col = [0, 2 if inv.columns.size() > 2 else 1]
	else:
		side_col = [0, 1 if inv.columns.size() > 1 else 0]  # 行囊 | 第一位主角
	_rows = int(UiLayout.val("camp.item.row", "repeat", {}).get("count", _rows))
	for s in 2:
		var p := Node2D.new()
		_panel_pos.append(UiLayout.at(SIDES[s]))
		p.position = _panel_pos[s]
		add_child(p)
		_panels.append(p)
		_arrows.append([null, null])
	var mb := Node2D.new()
	var mp := UiLayout.panel("camp.item.money.panel")
	_money_pos = mp.position
	mp.position = Vector2.ZERO
	mb.position = _money_pos
	mb.add_child(mp)
	_money = UiLayout.number("camp.item.money.value")
	mb.add_child(_money)
	add_child(mb)
	ScreenLayout.wrap(mb, UiLayout.anchor("camp.item.money.panel", ScreenLayout.Anchor.TOP_RIGHT))  # 金钱框原版在右上角 (整页居中, 金钱框贴右上)
	desc = CampDescBar.new()
	add_child(desc)
	var many: bool = inv.col(side_col[0])["items"].size() > _rows
	_down_flag = [many, many]
	_rebuild(0)
	_rebuild(1)
	_update_desc(false)
	_update_money()
	UiSlide.run(mb, _money_pos, Vector2.LEFT, CampUi.SLIDE, true)


func open() -> void:
	desc.open()
	for s in 2:
		UiSlide.run(_panels[s], _panel_pos[s], Vector2.LEFT if s == 0 else Vector2.RIGHT, CampUi.SLIDE, true)


func _update_money() -> void:
	_money.text = CampUi.fmt(gc.state.gold, UiLayout.fmt_width("camp.item.money.value", 5))


func _col(s: int) -> Dictionary:
	return inv.col(side_col[s])


func _items(s: int) -> Array:
	return _col(s)["items"]


## 重画某一栏 (内容或焦点变了)
func _rebuild(s: int) -> void:
	var p := _panels[s]
	for c in p.get_children():
		p.remove_child(c)
		c.queue_free()
	var cd := _col(s)
	var bg := UiLayout.panel(SIDES[s])
	bg.position = Vector2.ZERO
	p.add_child(bg)
	p.add_child(UiText.make("camp.item.tab", String(cd["name"]), 0, {"which": s}))
	var items: Array = cd["items"]
	sel[s] = clampi(sel[s], 0, maxi(0, items.size() - 1))
	top[s] = clampi(top[s], maxi(0, sel[s] - _rows + 1), sel[s])
	var other: int = side_col[1 - s]
	for k in _rows:
		var i: int = top[s] + k
		if i >= items.size():
			break
		var row := _make_row(side_col[s], i, other)
		row.position = UiLayout.at("camp.item.row", k)
		p.add_child(row)
	if s == focus and not items.is_empty():
		var box := CampUi.Box.new()
		var r := UiLayout.rect("camp.item.select_box", sel[s] - top[s])
		box.position = r.position
		box.size = r.size
		box.color = UiLayout.color(UiLayout.val("camp.item.select_box", "color", "box.select"), CampUi.BOX)
		p.add_child(UiLayout.tag(box, "camp.item.select_box", Rect2(Vector2.ZERO, r.size)))
	var up := UiLayout.panel("camp.item.arrow_up")
	var dn := UiLayout.panel("camp.item.arrow_down")
	up.visible = top[s] > 0
	if s == focus:
		_down_flag[s] = top[s] + _rows < items.size()
	dn.visible = _down_flag[s]
	p.add_child(up)
	p.add_child(dn)
	_arrows[s] = [up, dn]
	p.modulate = Color.WHITE if s == focus else CampUi.DIM


func _make_row(c: int, i: int, other: int) -> Node2D:
	var cd: Dictionary = inv.col(c)
	var id: int = cd["items"][i]
	var it := CampInventory.item(id)
	var row := Node2D.new()
	var t := int(it["type"])
	var ic := UiLayout.panel("camp.item.row.icon")  # 帧 = 起始帧 + 类型, 不能装备时再 + no_equip
	var off := clampi(t, 0, 3)
	if not inv.equipable_for_icon(c, i, other):
		off += int(UiLayout.num("camp.item.row.icon", "no_equip", 4))
	ic.set_frame(ic.anim_dir, ic.frame + off)
	row.add_child(ic)
	row.add_child(UiText.make("camp.item.row.name", String(it["name"])))
	var slot := inv.equip_slot(c, i)
	if slot >= 0:
		var eq := UiLayout.panel("camp.item.row.equip")
		eq.set_frame(eq.anim_dir, eq.frame + slot)
		row.add_child(eq)
	row.add_child(UiLayout.panel("camp.item.row.coin"))
	var price := int(it.get("price", 0))
	if cd["kind"] != "shop":
		price /= 2
	row.add_child(UiLayout.number("camp.item.row.price", price))
	if cd["kind"] == "shop" and not _can_buy(price, other):
		row.modulate.a = SHOP_POOR_ALPHA  # 买不起 / 目标栏满了: 整行压暗 (原版实测)
	if not inv.movable(c, i):
		row.modulate.a = CampUi.FAINT
	return row


func _process(delta: float) -> void:
	if inv.dirty:   # 行囊被攻略面板「整理行囊」排过: 重画两栏 (选中格按下标留在原处)
		inv.dirty = false
		_after_change()
	if _arrow_cyc.step(delta):
		for s in 2:
			if _arrows[s][0]:
				for a in 2:
					var id: String = ["camp.item.arrow_up", "camp.item.arrow_down"][a]
					_arrows[s][a].set_frame(_arrows[s][a].anim_dir, UiLayout.frame(id) + _arrow_cyc.phase)
	if _menu and _menu_cyc.step(delta):
		_menu_arrow.set_frame(_menu_arrow.anim_dir, UiLayout.frame("camp.item.menu.arrow") + _menu_cyc.phase)


func _update_desc(typing := true) -> void:
	var items := _items(focus)
	if items.is_empty():
		desc.set_text("", false)
		return
	desc.set_text(String(CampInventory.item(items[sel[focus]]).get("desc", "")), typing)


func _row_on_page() -> int:
	return sel[focus] - top[focus]


# ---------------- 指针 (engine/ui/ui_hit.gd) ----------------
## 行: 悬停 = 焦点移到该栏并选中该行 (同 Tab + ↑/↓), 点按 = 再确认 (三选项菜单 / 买入问句);
## 栏名标签: 点非焦点栏 = 切换焦点 (同 Tab), 点焦点栏 = 循环切换该栏内容 (同 ←); 翻页箭头: 点按 = 该栏翻一页 (同 Q/E)。
## 三选项菜单打开时只有菜单三项, 点菜单外 = 关菜单 (同取消)。是/否框打开时交给它。装备预览中不响应。

func ui_pointer_target() -> Object:
	return _ask if _ask else self


func ui_hits() -> Array:
	var out: Array = []
	if _preview:
		return out
	if _menu:
		var mv := UiLayout.sprite_vars("camp.item.menu.panel")
		for k in 3:
			out.append(UiHit.area(UiLayout.rect("camp.item.hit.menu", k, mv), ["menu", k], _menu))
		return out
	for s in 2:
		if _arrows[s][0]:
			for a in 2:
				var ar: UiPanel = _arrows[s][a]
				var grow := UiLayout.num("camp.item.hit.arrow", "grow", 2)
				out.append(UiHit.area(UiPanel.frame_rect(ar.anim_dir, ar.frame).grow(grow), ["focus", s], ar, UiAction.PAGE_UP if a == 0 else UiAction.PAGE_DOWN))
		out.append(UiHit.area(UiLayout.rect("camp.item.hit.tab", 0, {"which": s}), null, _panels[s], UiAction.SWITCH if s != focus else UiAction.LEFT))
		var n := _items(s).size()
		for k in _rows:
			if top[s] + k < n:
				out.append(UiHit.area(UiLayout.rect("camp.item.hit.row", k), ["row", s, top[s] + k], _panels[s]))
	return out


## ["row", 栏, 行] 焦点移到该栏并选中该行; ["focus", 栏] 只移焦点; ["menu", k] 菜单箭头移到第 k 项
func ui_select(id) -> void:
	match id[0]:
		"menu":
			if id[1] != _menu_sel:
				_menu_sel = id[1]
				_menu_arrow.position = UiLayout.at("camp.item.menu.arrow", _menu_sel)
		"row", "focus":
			var s: int = id[1]
			var row: int = id[2] if id[0] == "row" else sel[s]
			if s != focus or sel[s] != row:
				var was := focus
				focus = s
				sel[s] = row
				_rebuild(s)
				if was != s:
					_rebuild(1 - s)
				_update_desc()


func ui_outside_action() -> int:
	return UiAction.CANCEL if _menu else UiAction.NONE


# ---------------- 按键 ----------------

## 按住 ←/→ 换栏内容的连发间隔: 原版换栏后整栏重画 + 淡入动画, 做完才再读键 (实测 21 帧 = 0.84 秒, 其余键 5 帧)
const CYCLE_REPEAT := 21 * 0.04


func repeat_interval(kind: int) -> float:
	if kind in [UiAction.LEFT, UiAction.RIGHT] and _ask == null and _menu == null and _preview == null:
		return CYCLE_REPEAT
	return KeyRepeat.REPEAT


func key(k: String) -> void:
	if _ask:
		_ask.key(k)
		return
	if _menu:
		_menu_key(k)
		return
	if _preview and k != "space_up":
		return
	match k:
		"up", "down":
			var n := _items(focus).size()
			if n == 0:
				return
			var v: int = clampi(sel[focus] + (1 if k == "down" else -1), 0, n - 1)
			if v != sel[focus]:
				sel[focus] = v
				_rebuild(focus)
				_update_desc()
		"page_up", "page_down":  # Q/E 一次跳 7 格
			var n := _items(focus).size()
			if n == 0:
				return
			sel[focus] = CampUi.page_jump(sel[focus], n, _rows, 1 if k == "page_down" else -1)
			_rebuild(focus)
			_update_desc()
		"left", "right":
			_cycle_column(1 if k == "left" else -1)
		"tab":
			focus = 1 - focus
			_rebuild(0)
			_rebuild(1)
			_update_desc()
		"accept":
			_open_menu()
		"cancel":
			inv.commit()
			closed.emit()
		"space":
			_open_preview()
		"space_up":
			if _preview:
				_preview.queue_free()
				_preview = null


func _cycle_column(d: int) -> void:
	var n := inv.columns.size()
	if n < 3:
		return
	# 两侧都按环切换, 商店也在环里 (原版实测: 商店栏上按 ←/→ 左栏换成行囊); 不会切到对面栏正在显示的那一栏
	var c: int = side_col[focus]
	while true:
		c = posmod(c + d, n)
		if c != side_col[1 - focus]:
			break
	side_col[focus] = c
	sel[focus] = 0
	top[focus] = 0
	_rebuild(0)
	_rebuild(1)
	_update_desc()
	UiSlide.run(_panels[focus], _panel_pos[focus], Vector2.LEFT if focus == 0 else Vector2.RIGHT, CampUi.SLIDE, true)


## 商店货品 (栏 c) 买得起且对面栏没满 (原版 0x41ee.. 货品行压暗 = 不能买)
func _can_buy(price: int, other: int) -> bool:
	return price <= gc.state.gold and not inv.is_full(other)


func _open_menu() -> void:
	var items := _items(focus)
	if items.is_empty():
		return
	var c: int = side_col[focus]
	var i: int = sel[focus]
	if inv.col(c)["kind"] == "shop":
		# 原版实测: 买不起或目标栏满 (货品压暗) 时确认无反应, 不弹问句
		if _can_buy(int(CampInventory.item(_items(focus)[i]).get("price", 0)), side_col[1 - focus]):
			_open_ask("buy", UiStrings.t("camp.item.ask.buy"))
		return
	if not inv.movable(c, i):
		return
	_menu_state = inv.menu_state(c, i, side_col[1 - focus])
	var mode: int = (2 if inv.shop_mode else 0) + (1 if _menu_state["unequip"] else 0)
	if inv.shop_mode and inv.col(side_col[1 - focus])["kind"] != "shop":
		mode -= 2   # 商店模式下对面不是商店时仍是给予
	_menu = Node2D.new()
	var mp := UiLayout.panel("camp.item.menu.panel", 0, {"r": _row_on_page()})
	var base: Vector2 = _panel_pos[focus] + mp.position
	mp.position = Vector2.ZERO
	_menu.position = base
	_menu.add_child(mp)
	_menu_texts.clear()
	for k in 3:
		var en: bool = _menu_state["items"][k]
		var t := UiText.make("camp.item.menu.text", UiStrings.t("camp.item.act." + String(MENU_ACTS[mode][k])), k)
		if not en:
			t.color = UiLayout.color(UiLayout.val("camp.item.menu.text", "disabled_color", "text.disabled"), CampUi.DISABLED)
		_menu.add_child(t)
		_menu_texts.append(t)
	_menu_sel = 0
	_menu_arrow = UiLayout.panel("camp.item.menu.arrow")
	_menu.add_child(_menu_arrow)
	add_child(_menu)
	UiSlide.run(_menu, base, Vector2.LEFT, CampUi.SLIDE, true)


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


func _menu_key(k: String) -> void:
	match k:
		"up", "left":
			_menu_sel = posmod(_menu_sel - 1, 3)
		"down", "right":
			_menu_sel = posmod(_menu_sel + 1, 3)
		"accept":
			if not _menu_state["items"][_menu_sel]:
				return
			var c: int = side_col[focus]
			var i: int = sel[focus]
			var other: int = side_col[1 - focus]
			match _menu_sel:
				0:
					_close_menu()
					if inv.col(other)["kind"] == "shop":
						_open_ask("sell", UiStrings.t("camp.item.ask.sell"))
						return
					inv.give(c, i, other)
					_after_change()
				1:
					inv.toggle_equip(c, i)
					_close_menu()
					_after_change()
				2:
					_close_menu()
					_open_ask("discard", UiStrings.t("camp.item.ask.discard"))
			return
		"cancel":
			_close_menu()
			return
	_menu_arrow.position = UiLayout.at("camp.item.menu.arrow", _menu_sel)


func _open_ask(action: String, q: String) -> void:
	_ask_action = action
	desc.set_text(q, false)
	_ask = CampAsk.YesNo.make("camp.item.confirm.yesno", {"r": _row_on_page()}, _panel_pos[focus])
	add_child(_ask)
	_ask.done.connect(_on_ask)


func _on_ask(yes: bool) -> void:
	_ask.queue_free()
	_ask = null
	var c: int = side_col[focus]
	var i: int = sel[focus]
	if yes:
		var id: int = _items(focus)[i]
		var price := int(CampInventory.item(id).get("price", 0))
		match _ask_action:
			"discard":
				inv.discard(c, i)
			"sell":
				gc.state.gold += price / 2
				inv.discard(c, i)
			"buy":
				var other: int = side_col[1 - focus]
				if gc.state.gold >= price and not inv.is_full(other):
					gc.state.gold -= price
					inv.col(other)["items"].append(id)
	_after_change()


func _after_change() -> void:
	_rebuild(0)
	_rebuild(1)
	_update_desc(false)
	_update_money()


func _open_preview() -> void:
	var items := _items(focus)
	if items.is_empty():
		return
	var c: int = side_col[focus]
	var cd := inv.col(c)
	var uid: int = cd["uid"] if cd["kind"] == "unit" else int(_col(1 - focus)["uid"])
	var id: int = items[sel[focus]]
	if uid < 0 or not CampInventory.can_equip(id, uid):
		return
	_preview = UiEquipPreview.new(uid, id, focus, _row_on_page())
	add_child(_preview)

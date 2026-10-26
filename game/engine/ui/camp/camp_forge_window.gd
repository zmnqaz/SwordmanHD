# SPDX-License-Identifier: GPL-3.0-only
class_name CampForgeWindow
extends Node2D
## 諸物煉化 CForgeItemProcessor (素材 Misc/FI_PRO), 坐标与原版截图核对:
##   左栏「選擇物品」第 0 帧在 (20,20); 选定第一件后右侧「結果預測」第 1 帧在 (71,20),
##   左栏选中框留在第一件上; 结果栏光标从第 0 行开始 (实测)。
##   标签文字 x = 5 + (48−宽)/2, y = 4。
##   行: 每页 8 行, 行内 (5, 22+13k) 起:
##     类型图标 FI_PRO 第 2~5 帧 (道具/武器/护具/饰物); 名字 (14,0); 已装备标记 FI_PRO 第 6/7/8 帧在 (74,2); 主人名 (90,0), 行囊里的写「行囊」;
##     结果栏另有 → (第 17 帧) 在 (141,2), 产物名 (156,0)。不可选的行约 25% 不透明。
##   选中框 0x64a5: 左栏 (4,y−2) 起 142x15, 结果栏 223x15。
##   翻页箭头: 上 第 9~12 帧、下 第 13~16 帧, 每 5 tick 换帧; x = 20+70 (左栏) / 71+110 (结果栏), y = 21 / 155。
##   说明栏 ITEM_MB 在 (20,164); 确认「是否要煉化成此物品？」写在说明栏, 是/否框在 (280, 37+13r), 默认✗。
##   打开时自左滑入 16,8,4,2,0。
##   以上坐标、帧号都在布局表 camp.forge.* (栏用 which = 0 左栏 / 1 结果栏, 行用序号 k, 是/否框用本页行号 r)。
## 规则: 材料池 = 在队各人 10 格 + 行囊; 第一步只有「可炼」的物品可选;
##   结果栏列出池中每一件与 A 的配方产物; A、B 都未装备才可炼; 产物进行囊。
## 炼成演出 (数据见内容包 fx/cutscenes.json forge, 由 engine/fx/cutscene.gd 播放):
##   确认「是」后先放 MOVIE\FORGEITE (垫 FI_PRO 第 18 帧丹炉图; 取消键可跳过, 回车不跳过), 放完弹浮动框「煉化成%s」停留 50 tick,
##   之后才改行囊并刷新列表; 演出和提示期间输入锁住 (_busy)。

signal closed

const PANELS := ["camp.forge.panel.left", "camp.forge.panel.result"]

var inv: CampInventory
var desc: CampDescBar
var pool: Array = []
var stage := 0          # 0 选第一件, 1 选第二件
var sel := [0, 0]
var top := [0, 0]
var first := -1
var _left: Node2D
var _right: Node2D
var _ask: CampAsk.YesNo
var _busy := false     # 炼成演出中: 视频 + 浮动提示, 不收按键与指针
var _arrows: Array = []
var _cyc := CampUi.Cycle.new(5, 4)
var _rows := 8  # 每页行数 (布局表 camp.forge.row repeat.count)
var _pos: Array = []


func _init(inventory: CampInventory) -> void:
	inv = inventory
	inv.busy_fn = func(): return stage == 1 or _ask != null or _busy   # 选了第一件 / 问句 / 炼成演出中: 材料按下标记着, 不能整理行囊 (攻略面板 F4)
	_rows = int(UiLayout.val("camp.forge.row", "repeat", {}).get("count", _rows))
	_pos = [UiLayout.at(PANELS[0]), UiLayout.at(PANELS[1])]
	_left = Node2D.new()
	_left.position = _pos[0]
	add_child(_left)
	_right = Node2D.new()
	_right.position = _pos[1]
	_right.visible = false
	add_child(_right)
	desc = CampDescBar.new()
	add_child(desc)
	_refresh_pool()
	_rebuild()


func open() -> void:
	desc.open()
	UiSlide.run(_left, _pos[0], Vector2.LEFT, CampUi.SLIDE, true)


func _refresh_pool() -> void:
	pool = inv.forge_pool()
	for e in pool:
		e["ok"] = CampInventory.forgeable(e["id"], pool)


func _product(b: int) -> int:
	if first < 0 or b == first:
		return -1
	return CampInventory.recipe(pool[first]["id"], pool[b]["id"])


func _selectable(s: int, i: int) -> bool:
	if s == 0:
		return pool[i]["ok"]
	return _product(i) >= 0 and pool[first]["slot"] < 0 and pool[i]["slot"] < 0


func _rebuild() -> void:
	_arrows.clear()
	_build_panel(0, _left)
	if stage == 1:
		_build_panel(1, _right)
	_update_desc()


func _build_panel(s: int, p: Node2D) -> void:
	for c in p.get_children():
		p.remove_child(c)
		c.queue_free()
	var bg := UiLayout.panel(PANELS[s])
	bg.position = Vector2.ZERO
	p.add_child(bg)
	p.add_child(UiText.make("camp.forge.tab", UiStrings.t("camp.forge.tab.%d" % s)))
	sel[s] = clampi(sel[s], 0, maxi(0, pool.size() - 1))
	top[s] = clampi(top[s], maxi(0, sel[s] - _rows + 1), sel[s])
	for k in _rows:
		var i: int = top[s] + k
		if i >= pool.size():
			break
		var e: Dictionary = pool[i]
		var it := CampInventory.item(e["id"])
		var row := Node2D.new()
		row.position = UiLayout.at("camp.forge.row", k)
		var ic := UiLayout.panel("camp.forge.row.icon")
		ic.set_frame(ic.anim_dir, ic.frame + clampi(int(it["type"]), 0, 3))
		row.add_child(ic)
		row.add_child(UiText.make("camp.forge.row.name", String(it["name"])))
		if e["slot"] >= 0:
			var eq := UiLayout.panel("camp.forge.row.equip")
			eq.set_frame(eq.anim_dir, eq.frame + int(e["slot"]))
			row.add_child(eq)
		row.add_child(UiText.make("camp.forge.row.owner", String(e["owner"])))
		if s == 1:
			var pr := _product(i)
			if pr >= 0:
				row.add_child(UiLayout.panel("camp.forge.row.arrow"))
				row.add_child(UiText.make("camp.forge.row.product", String(CampInventory.item(pr)["name"])))
		if not _selectable(s, i):
			row.modulate.a = CampUi.FAINT
		p.add_child(row)
	if not pool.is_empty():  # 选结果时左栏的框留在第一件上
		var box := CampUi.Box.new()
		var r := UiLayout.rect("camp.forge.select_box", sel[s] - top[s], {"which": s})
		box.position = r.position
		box.size = r.size
		box.color = UiLayout.color(UiLayout.val("camp.forge.select_box", "color", "box.select"), CampUi.BOX)
		p.add_child(UiLayout.tag(box, "camp.forge.select_box", Rect2(Vector2.ZERO, r.size)))
	if s == stage:
		var up := UiLayout.panel("camp.forge.arrow_up", 0, {"which": s})
		var dn := UiLayout.panel("camp.forge.arrow_down", 0, {"which": s})
		up.visible = top[s] > 0
		dn.visible = top[s] + _rows < pool.size()
		p.add_child(up)
		p.add_child(dn)
		_arrows = [up, dn]


func _process(delta: float) -> void:
	if inv.dirty:   # 行囊被攻略面板「整理行囊」排过 (只会发生在 stage 0): 重取材料池
		inv.dirty = false
		_refresh_pool()
		_rebuild()
	if _cyc.step(delta) and not _arrows.is_empty():
		_arrows[0].set_frame(_arrows[0].anim_dir, UiLayout.frame("camp.forge.arrow_up") + _cyc.phase)
		_arrows[1].set_frame(_arrows[1].anim_dir, UiLayout.frame("camp.forge.arrow_down") + _cyc.phase)


func _update_desc() -> void:
	if pool.is_empty():
		desc.set_text("", false)
		return
	desc.set_text(String(CampInventory.item(pool[sel[stage]]["id"]).get("desc", "")))


## 指针 (engine/ui/ui_hit.gd): 当前栏 (选第一件时左栏, 选第二件时结果栏) 的行, 翻页箭头 (同 Q/E);
## 选第二件时点左栏露出的部分 = 退回选第一件 (同取消)。是/否框打开时交给它。
func ui_pointer_target() -> Object:
	return _ask if _ask else self


func ui_hits() -> Array:
	var out: Array = []
	if _busy:
		return out
	var p: Node2D = _left if stage == 0 else _right
	if _arrows.size() == 2:
		var grow := UiLayout.num("camp.forge.hit.arrow", "grow", 2)
		for a in 2:
			out.append(UiHit.area(UiPanel.frame_rect(_arrows[a].anim_dir, _arrows[a].frame).grow(grow), null, _arrows[a],
				UiAction.PAGE_UP if a == 0 else UiAction.PAGE_DOWN))
	for k in _rows:
		if top[stage] + k < pool.size():
			out.append(UiHit.area(UiLayout.rect("camp.forge.hit.row", k, {"which": stage}), top[stage] + k, p))
	if stage == 1:
		var lb: UiPanel = _left.get_child(0)
		var lr := UiPanel.frame_rect(lb.anim_dir, lb.frame)
		out.append(UiHit.area(Rect2(lr.position, Vector2(_pos[1].x - _pos[0].x, lr.size.y)), null, _left, UiAction.CANCEL))  # 左栏露出的部分
	return out


func ui_select(i) -> void:
	if i != sel[stage]:
		sel[stage] = i
		_rebuild()


func key(k: String) -> void:
	if _busy:
		return
	if _ask:
		_ask.key(k)
		return
	match k:
		"up", "down":
			if pool.is_empty():
				return
			var v: int = clampi(sel[stage] + (1 if k == "down" else -1), 0, pool.size() - 1)
			if v != sel[stage]:
				sel[stage] = v
				_rebuild()
		"page_up", "page_down":  # Q/E 一次跳 7 格, 同物品窗 (CampUi.page_jump)
			if pool.is_empty():
				return
			sel[stage] = CampUi.page_jump(sel[stage], pool.size(), _rows, 1 if k == "page_down" else -1)
			_rebuild()
		"accept":
			if pool.is_empty() or not _selectable(stage, sel[stage]):
				return
			if stage == 0:
				first = sel[0]
				stage = 1
				sel[1] = 0
				top[1] = 0
				_right.visible = true
				_rebuild()
				UiSlide.run(_right, _pos[1], Vector2.LEFT, CampUi.SLIDE, true)
			else:
				desc.set_text(UiStrings.t("camp.forge.ask"), false)
				_ask = CampAsk.YesNo.make("camp.forge.yesno", {"r": sel[1] - top[1]})
				add_child(_ask)
				_ask.done.connect(_on_ask)
		"cancel":
			if stage == 1:
				stage = 0
				first = -1
				_right.visible = false
				_rebuild()
			else:
				inv.commit()
				closed.emit()


func _on_ask(yes: bool) -> void:
	_ask.queue_free()
	_ask = null
	if not yes:
		_update_desc()
		return
	_busy = true
	var a: Dictionary = pool[first]
	var b: Dictionary = pool[sel[1]]
	var pr := _product(sel[1])
	var name: String = CampInventory.item(pr)["name"]
	await Cutscene.play(self, "forge")
	var secs := Cutscene.notice_secs("forge")
	var msg := Cutscene.notice_text("forge", [name])
	if msg != "":
		var n := CampAsk.Notice.new(msg, secs)
		add_child(n)
		await n.closed
		n.queue_free()
	inv.forge(a, b, pr)
	stage = 0
	first = -1
	_right.visible = false
	_refresh_pool()
	_rebuild()
	desc.set_text(UiStrings.t("camp.forge.done", [name]), false)
	_busy = false

# SPDX-License-Identifier: GPL-3.0-only
extends Node2D
## 原版样式界面组件展示 (--scene=ui_gallery), 用来与原版截图并排比较 (截图存)。
## 依次展示: 0 法术列表、1 物品列表、2 行动菜单与物品子菜单、3 信息条、4 对话框、5 是否选择框、6 位阶上升窗、7 回合横幅 (--banner-side=N --banner-turn=N); 每页 PAGE_SEC 秒后自动翻到下一页。
## 命令行 (-- 之后): --ui-page=N 从第 N 页开始; --ui-hold 不自动翻页。
## 方向键 / 确认 / 取消转给当前页的组件 (演示调用方传键的用法); PageDown 下一页。
## 背景画 30x24 的格子 (原版地图格), 方便核对行动菜单、信息条按格定位。
##
## 截图示例 (25 帧/秒, 每页 40 帧):
##   tools/run_game.sh --fixed-fps 25 -- --scene=ui_gallery --shot=30:$PWD/ ... --quit=195 (路径要写绝对路径)

const ClearRank = preload("res://engine/rules/clear_rank.gd")
const PAGE_SEC := 1.6
const PAGES := ["法术列表", "物品列表", "行动菜单", "信息条", "对话框", "是否选择框", "位阶上升", "回合横幅", "通关序号框"]

var page := -1
var ui: UiLayer
var _t := 0.0
var _hold := false
var _list: UiListMenu
var _menu: UiIconMenu
var _sub: UiIconMenu
var _bar: UiInfoBar
var _bar2: UiInfoBar
var _msg: UiMsgBox
var _choice: ChoiceBox
var _marks: Node2D


func _ready() -> void:
	InputRouter.push(self)
	var start := 0
	start = DebugArgs.current().ui_page   # --ui-page=N / --ui-hold
	_hold = _hold or DebugArgs.current().ui_hold
	ui = UiLayer.new()
	add_child(ui)
	_show(start)


func _draw() -> void:
	# 背景: 原版画面 (安全区) 与地图格 (map.cell), 颜色取布局表 gallery.bg
	var s := float(Assets.SCALE)
	var scr := UiLayout.base_size() * s
	var cell := UiLayout.size_of("map.cell") * s
	var grid := UiLayout.color(UiLayout.val("gallery.bg", "grid"))
	draw_rect(Rect2(Vector2.ZERO, scr), UiLayout.color("gallery.bg"))
	for c in range(0, int(scr.x / cell.x) + 1):
		draw_rect(Rect2(c * cell.x, 0, s, scr.y), grid)
	for r in range(0, int(scr.y / cell.y) + 1):
		draw_rect(Rect2(0, r * cell.y, scr.x, s), grid)


func _process(delta: float) -> void:
	if _hold:
		return
	_t += delta
	if _t >= PAGE_SEC:
		_show((page + 1) % PAGES.size())


func _clear() -> void:
	for c in ui.root.get_children():
		ui.root.remove_child(c)
		c.queue_free()
	_list = null
	_menu = null
	_sub = null
	_bar = null
	_bar2 = null
	_msg = null
	if _choice:
		_choice.queue_free()
		_choice = null


func _show(p: int) -> void:
	_clear()
	page = p
	_t = 0.0
	print("界面展示: 第 %d 页 %s" % [p, PAGES[p]])
	match p:
		0: _page_spells()
		1: _page_items()
		2: _page_menus()
		3: _page_info()
		4: _page_msg()
		5: _page_choice()
		6: _page_levelup()
		7: _page_banner()
		8: _page_clear_rank()


## 封寒月 (单位 1) 按等级习得的 10 个法术 (data/levelup.json), 剩余术力 40: 消耗更大的变淡
func _page_spells() -> void:
	var ids: Array = []
	for e in Content.table("levelup"):
		if int(e["unit_id"]) == 1:
			for l in e["skills"]:
				ids.append(int(l["skill_id"]))
	_list = UiListMenu.new()
	ui.add(_list)
	_list.setup(UiListMenu.SPELL, UiListMenu.spell_rows(ids, 40), 2)
	_list.open()


## 殷劍平的随身物品 + 若干药品: 第 0 格当前武器、第 1 格当前防具、第 2 格饰物; 「使用」模式下只有道具可用
func _page_items() -> void:
	var ids := [0, 99, 158, 220, 220, 221, 1, 45]
	_list = UiListMenu.new()
	ui.add(_list)
	var rows := UiListMenu.item_rows(ids, {0: 0, 1: 1, 2: 2}, func(it): return int(it["type"]) == 0)
	_list.setup(UiListMenu.ITEM, rows)
	_list.open()


## 行动菜单 (移动过: 爆發禁用) 在 gallery.cells 第 0 格的单位旁; 物品子菜单在第 1 格, 下面压着变灰的行动菜单
func _page_menus() -> void:
	_marks = Node2D.new()
	ui.add(_marks)
	var cell := UiLayout.size_of("map.cell")
	var cells: Array[Vector2i] = []
	for i in 2:
		cells.append(Vector2i(UiLayout.at("gallery.cells", i)))
		var m := ColorRect.new()
		m.color = UiLayout.color(UiLayout.val("gallery.cells", "color"))
		m.position = Vector2(cells[i]) * cell
		m.size = cell
		_marks.add_child(m)
	var view := UiLayout.base_size()
	_menu = UiIconMenu.new()
	ui.add(_menu)
	_menu.setup_id("actionmenu.icons", [false, true, true, true, true], 2)
	_menu.position = UiIconMenu.place_near(cells[0], Vector2.ZERO, view, _menu.width(), _menu.height())
	var under := UiIconMenu.new()
	ui.add(under)
	under.setup_id("actionmenu.icons", [], 3)
	under.position = UiIconMenu.place_near(cells[1], Vector2.ZERO, view, under.width(), under.height())
	under.dimmed = true
	_sub = UiIconMenu.new()
	ui.add(_sub)
	_sub.setup_id("actionmenu.item_icons", [], 0)
	# 展示页把物品子菜单放在行动菜单下方 (gallery.cells.sub_dy); 战场里叠在上方 (BattleUi.sub_menu, actionmenu.sub_dy)
	_sub.position = under.position + Vector2((under.width() - _sub.width()) * 0.5, UiLayout.num("gallery.cells", "sub_dy"))


## 信息条: 顶端 (单位在第 5 行以下) 显示左右两块; 底部只显示左块 (光标停在单位上)
func _page_info() -> void:
	_bar = UiInfoBar.new()
	ui.add(_bar)
	_bar.show_unit({"name": "封寒月", "hp": 245, "hp_max": 260, "mp": 88, "mp_max": 120, "move": 5, "move_max": 6,
		"attack": 132, "defence": 87, "lv": 24, "exp": 56, "buffs": [true, false, true, false]},
		UiInfoBar.top_for_row(6), true)
	_bar2 = UiInfoBar.new()
	ui.add(_bar2)
	_bar2.show_unit({"name": "殷劍平", "hp": 1234, "hp_max": 12345, "mp": 0, "mp_max": 14, "move": 4, "move_max": 4},
		UiInfoBar.top_for_row(2), false)


## 对话框: 头像在左, 文字为第 0 关原版截图里的一句 (对照 原版 下原版截图)
func _page_msg() -> void:
	_msg = UiMsgBox.new()
	ui.add(_msg)
	_msg.open(2, 0, 0, "這夜魔太難對付了！\n大家一擁而上，合力打倒它！")
	_msg.confirm()  # 直接显示整页 (含页尾下箭头)


## 是/否选择框: 战场「存档/读档」确认 (系统文本 .MSG 第 3~5 句), 无头像
func _page_choice() -> void:
	_choice = ChoiceBox.new()
	add_child(_choice)
	_choice.ask("是否要载入前次储存的进度?", "是,我要载入前次储存的进度.", "否,继续目前正在进行的游戏.")


## 位阶上升窗: 第一个新学法术名画在底栏 (实测 殷剑平 15 级「无方飞剑」); 数字为演示值
func _page_levelup() -> void:
	var before := {"lv": 14, "hp_max": 76, "mp_max": 18, "stats": {"str": 38, "int": 29, "avg": 24, "vit": 40, "luk": 35}}
	var after := {"lv": 15, "hp_max": 79, "mp_max": 19, "stats": {"str": 40, "int": 30, "avg": 26, "vit": 42, "luk": 36}}
	var w := UiLevelUp.new(before, after, ["无方飞剑", "电射星驰"])
	ui.add(w, UiLayout.anchor("levelup.window"))


## 回合横幅 (UiTurnBanner): 打开页面即开始播放一次, 25 帧/秒下可按帧号截图与原版逐帧比
func _page_banner() -> void:
	var side := 1
	var turn := 1
	side = DebugArgs.current().banner_side   # --banner-side= / --banner-turn=
	turn = DebugArgs.current().banner_turn
	var b := UiTurnBanner.new()
	ui.add(b, UiLayout.anchor("turn_banner.anim"))
	b.play(side, turn)


## 0x56 通关序号框 (第 35 关番外通关; 原版是两个系统 MessageBox, 复刻用对话框显示同样文字): 第二段, 变量 30+n = 10+n 的演示序号
func _page_clear_rank() -> void:
	var p = CampInventory.params()
	var sums := ClearRank.serial(func(v): return 10 + (v - p.turn_record_base), p)
	var t: Array = Content.system_text("clear_rank")
	_msg = UiMsgBox.new()
	ui.add(_msg)
	_msg.open(-1, 0, -1, String(t[0][1]).format(sums.map(func(x): return "%X" % x)))
	_msg.confirm()


## 指针: 交给当前组件 (UiListMenu / UiIconMenu 自带命中矩形, engine/ui/ui_hit.gd)
func ui_pointer_target() -> Object:
	return _list if _list else _sub


## 统一输入层 (InputRouter): 方向/确认传给当前组件, 下翻页 (E / PageDown) 换下一页
func ui_action(a: UiAction) -> bool:
	if a.echo:
		return true
	if a.kind == UiAction.PAGE_DOWN:
		_show((page + 1) % PAGES.size())
		return true
	var d := a.dir()
	_hold = true
	if _list:
		if d != Vector2i.ZERO:
			_list.move(d)
		elif a.is_confirm():
			print("确认 ", _list.confirm())
	elif _sub:
		if d != Vector2i.ZERO:
			_sub.move(1 if d.x > 0 or d.y < 0 else -1)  # 原版: Up/Right +1, Down/Left -1
		elif a.is_confirm():
			print("确认 ", _sub.confirm())
	elif _msg and a.is_confirm():
		_msg.confirm()
	return true

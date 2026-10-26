# SPDX-License-Identifier: GPL-3.0-only
class_name BattleUi
extends Node
## 战场界面组件 (engine/ui 原版样式组件 + 战场专用窗), 只负责摆放与显示, 不读输入、不做规则判断。
## 屏幕上的组件挂在 UiLayer (原版坐标, 按锚点贴边, 见 docs/架构设计.md 6.4); 跟随单位的图标菜单挂在地图坐标系 (随镜头)。
##   信息条 UiInfoBar          左块 TOP_LEFT/BOTTOM_LEFT, 右块 TOP_RIGHT/BOTTOM_RIGHT
##   行动菜单/物品子菜单/系统菜单 UiIconMenu  地图坐标, 在单位 (光标格) 下方
##   法术/物品列表 UiListMenu  CENTER (列表与说明栏成组)
##   是/否框 ChoiceBox         BOTTOM (engine/ui/choice_box.gd 自带)
##   战场情报 / 小地图 / 单位详情 / 位階上升窗  CENTER

## 图标菜单的素材与帧表在布局表: actionmenu.icons (爆發 法術 攻擊 物品 待機)、actionmenu.item_icons (使用 交給 裝備 丟棄)、
## sysmenu.icons (存讀 設定 地圖 結束回合)、sysmenu.sl_icons (存档 读档 情報 结束游戏)、sysmenu.sound (音乐/音效 开关)。
## 子菜单相对上一级菜单的位移: actionmenu.sub_pos (-W0/4, -H2/4)

var bs
var layer: UiLayer          # 原版坐标的界面根
var text_layer: CanvasLayer # 飘字 (Label, 1280x800 像素坐标)
var info: UiInfoBar
var coord: BattleCoord
var hidden_tip: BattleHiddenTip
var choice: ChoiceBox


func _init(scene) -> void:
	bs = scene


func _ready() -> void:
	layer = UiLayer.new(30)
	add_child(layer)
	info = UiInfoBar.new()
	_add_top_left(info)
	info.use_screen_anchors()
	coord = BattleCoord.new()   # 格子坐标 (设定「格子坐标」, 默认关): 晚于信息栏加入, 画在它上面
	coord.bs = bs
	_add_top_left(coord)
	hidden_tip = BattleHiddenTip.new()   # 隐藏宝箱提示 (设定「隐藏宝箱显示」开着、光标在隐藏宝箱格上时)
	hidden_tip.bs = bs
	_add_top_left(hidden_tip)
	text_layer = CanvasLayer.new()
	text_layer.layer = 31
	ScreenLayout.bind_layer(text_layer, ScreenLayout.Anchor.TOP_LEFT)  # 飘字按地图坐标算, 跟地图一样从屏幕左上角起
	add_child(text_layer)
	choice = ChoiceBox.new()
	add_child(choice)


## 挂在界面层的屏幕左上角 (原版坐标, 与地图一样从左上角起)
func _add_top_left(n: Node) -> void:
	layer.add(n, ScreenLayout.Anchor.TOP_LEFT)


# ---------------- 跟随单位的图标菜单 ----------------

## 在地图格 cell 旁建一个图标菜单 (位置按原版, 唯一实现见 UiIconMenu.place_near)
func icon_menu(id: String, enabled: Array, sel: int, cell: Vector2i) -> UiIconMenu:
	var m := UiIconMenu.new()
	m.z_index = 30
	bs.units_node.add_child(m)
	m.setup_id(id, enabled, sel)
	m.position = UiIconMenu.place_near(cell, bs.cam, bs.view(), m.width(), m.height())
	return m


## 叠在 parent 之上的子菜单 (位置 = 上级菜单 + actionmenu.sub_pos, 原版)
## frames 非空时替换布局表的帧表 (声音开关随状态换图标)
func sub_menu(parent: UiIconMenu, id: String, enabled: Array, sel: int, frames: Array = []) -> UiIconMenu:
	var m := UiIconMenu.new()
	m.z_index = 31
	bs.units_node.add_child(m)
	m.setup_id(id, enabled, sel, frames)
	var off := UiLayout.vec_of("actionmenu.sub_pos", "pos", {"w0": parent.w0, "h": parent.height()})
	m.position = parent.position + Vector2(int(off.x), int(off.y))  # 向零取整 (原版有符号 /4)
	return m


# ---------------- 列表 ----------------

func list_menu(lay: Dictionary, rows: Array, sel := -1) -> UiListMenu:
	var l := UiListMenu.new()
	layer.add(l, ScreenLayout.Anchor.CENTER)
	l.setup(lay, rows, sel)
	l.open()
	return l


# ---------------- 居中的窗 ----------------

func add_center(n: Node) -> Node:
	return layer.add(n, ScreenLayout.Anchor.CENTER)


## 是/否 (系统确认框, 原版 GameMsgBoxChooseUI; 取消 = 否)。text: system_confirm 表的起始句号 (问句、是、否)
func confirm_text(first: int, default_yes := true) -> bool:
	var t: Array = Content.system_text("system_confirm")
	var g: Array = t[0] if not t.is_empty() else []
	var q := String(g[first]) if first < g.size() else "?"
	var y := String(g[first + 1]) if first + 1 < g.size() else UiStrings.t("common.yes")
	var n := String(g[first + 2]) if first + 2 < g.size() else UiStrings.t("common.no")
	return await choice.ask(q, y, n, default_yes)

# SPDX-License-Identifier: GPL-3.0-only
class_name ItemMenuState
extends BattleState
## 2.7 物品子菜单 (使用 / 交給 / 裝備 / 丟棄, Man_int 第 28/32/36/40 帧): 叠在变灰的行动菜单之上, 初始选「使用」;
##   方向 Up/Right +1、Down/Left −1, 夹紧不循环。确认 -> 该模式的物品列表; 取消 -> 行动菜单恢复 (选中项留在物品)。

var parent: UiIconMenu
var menu: UiIconMenu


func _init(action_menu: UiIconMenu) -> void:
	parent = action_menu


func enter() -> void:
	menu = c.ui.sub_menu(parent, "actionmenu.item_icons", [], 0)


func resume() -> void:
	parent.visible = true
	parent.dimmed = true
	menu.visible = true
	c.view.hide_info()


func exit() -> void:
	if is_instance_valid(menu):
		menu.queue_free()


func on_action(a: UiAction) -> void:
	if a.echo and not a.is_dir():  # 方向键按住 0.2 秒一格 (原版实测); 确认/取消不连发
		return
	if a.is_dir():
		menu.move(menu_step(a))
	elif a.is_confirm():
		var k := menu.confirm()
		if k >= 0:
			parent.visible = false
			menu.visible = false
			c.push(ItemListState.new(k))
	elif a.is_cancel():
		c.pop()

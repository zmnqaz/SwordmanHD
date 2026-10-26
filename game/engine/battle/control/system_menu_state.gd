# SPDX-License-Identifier: GPL-3.0-only
class_name SystemMenuState
extends BattleState
## 2.8 系统菜单 (在空地确认; 原版 Sys_int 第 0/4/8/12 帧横排, 位置跟随光标):
##   0 存讀 -> 存读子菜单; 1 設定 -> 声音子菜单; 2 地圖 -> 全图; 3 結束回合 -> 确认框 (默认「是」), 是才结束 (§5-2)。
##   初始选中第 0 项「存讀」; 方向 Up/Right +1、Down/Left −1, 夹紧。取消 -> 回到光标。

var menu: UiIconMenu


func enter() -> void:
	c.view.hide_cursor()
	c.view.hide_info()
	menu = c.ui.icon_menu("sysmenu.icons", [], 0, c.cur)


func resume() -> void:
	if is_instance_valid(menu):
		menu.visible = true
		menu.dimmed = false


func exit() -> void:
	if is_instance_valid(menu):
		menu.queue_free()


func on_action(a: UiAction) -> void:
	if a.echo and not a.is_dir():  # 方向键按住 0.2 秒一格 (原版实测); 确认/取消不连发
		return
	if a.is_dir():
		menu.move(menu_step(a))
	elif a.is_confirm():
		match menu.confirm():
			0:
				menu.dimmed = true
				c.push(SystemSubState.new(SystemSubState.SAVE_LOAD, menu))
			1:
				menu.dimmed = true
				c.push(SystemSubState.new(SystemSubState.SOUND, menu))
			2:
				c.replace(WindowState.new(WindowState.MAP))
			3:
				c.ask_end_turn()
	elif a.is_cancel():
		c.pop()

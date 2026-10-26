# SPDX-License-Identifier: GPL-3.0-only
class_name CursorState
extends BattleState
## 2.1 光标自由移动 (无选中单位), 依据 GameBattleInput.updateCursor:
##   确认: 格上有单位 -> 选中 (我方未行动: 移动范围; 其他: 显示其移动范围, 敌方用红色); 空地 -> 系统菜单。
##   取消: 光标跳到下一个未行动的我方单位 (从上次行动/巡视的单位往后找, 循环)。**不结束回合**。
##   菜单 (屏幕按钮 / M): 打开系统菜单 (扩展, 等同在空地确认)。


func _init() -> void:
	cursor_mode = true


func enter() -> void:
	resume()


func resume() -> void:
	c.sel = null
	c.show_cursor()


func confirm() -> void:
	var u: BattleUnit = c.rules.unit_at(c.cur)
	if u:
		c.select_unit(u)
	else:
		c.push(SystemMenuState.new())


func cancel() -> void:
	c.cycle_next_unit()


func on_menu() -> void:
	c.push(SystemMenuState.new())


## 原版 F2 (状态 0): 战场地图 (MAP_VIE), 与系统菜单「地圖」同一窗口
func on_f2() -> bool:
	c.push(WindowState.new(WindowState.MAP))
	return true

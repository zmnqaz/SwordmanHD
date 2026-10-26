# SPDX-License-Identifier: GPL-3.0-only
class_name UnitSelectState
extends BattleState
## 2.2 已选中单位 (显示移动范围), 依据 updateUnitMove。光标仍可自由移动、查看。
##   own (我方未行动): 确认在脚下 -> 行动菜单 (未移动); 确认在范围内 -> 沿路径移动后打开行动菜单; 范围外无反应。
##   其他 (已行动/友军/敌方): 确认 -> 单位详情。
##   取消: 收起范围, 清除选中, 回到光标 (光标留在原处, 不跳回单位)。

var own := true


func _init(is_own: bool) -> void:
	cursor_mode = true
	own = is_own


func resume() -> void:
	c.show_cursor()


func confirm() -> void:
	if not own:
		c.open_detail(c.sel)
		return
	if c.cur == Vector2i(c.sel.cx, c.sel.cy):
		c.push(ActionMenuState.new())
	elif c.reach.has(c.cur):
		c.move_selected(c.cur)


func cancel() -> void:
	c.view.clear_range()
	c.sel = null
	c.pop()


## 菜单 (屏幕按钮 / M, 扩展): 取消选中后打开系统菜单
func on_menu() -> void:
	cancel()
	c.push(SystemMenuState.new())


## 原版 F2 (实测: 回合开始已选中单位、显示移动范围时 F2 也开地图, 范围仍在地图后面) = 战场地图
func on_f2() -> bool:
	c.push(WindowState.new(WindowState.MAP))
	return true

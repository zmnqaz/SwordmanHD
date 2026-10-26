# SPDX-License-Identifier: GPL-3.0-only
class_name SpellListState
extends BattleState
## 2.6 法术列表 (原版 法术面板 Man_int 第 44 帧 + 说明栏, UiListMenu.SPELL):
##   10 槽两列; 上下 ±1, 左右 ±5 换列, 空槽不动; 不可用的法术 (术力/移动力不足、封咒、咒术已移动…) 变淡, 选得中, 确认无反应。
##   确认 -> 法术目标; 取消 -> 行动菜单。没学过法术时列表为空, 只能取消。

var list: UiListMenu
var _ids: Array = []


func enter() -> void:
	var u: BattleUnit = c.sel
	_ids = u.skills.filter(func(id): return not c.rules.skill(int(id)).is_empty()).slice(0, UiListMenu.SLOTS)
	var rows := UiListMenu.spell_rows(_ids)
	for i in rows.size():
		rows[i]["enabled"] = c.rules.can_cast(u, int(_ids[i]))
	c.view.hide_info()
	c.show_cursor(false)
	list = c.ui.list_menu(UiListMenu.SPELL, rows, 0)


func exit() -> void:
	if is_instance_valid(list):
		list.queue_free()


func on_action(a: UiAction) -> void:
	if a.echo and not a.is_dir():  # 方向键按住 0.2 秒一格 (原版实测); 确认/取消不连发
		return
	if a.is_dir():
		list.move(a.dir())
	elif a.is_confirm():
		var k := list.confirm()
		if k >= 0:
			c.replace(TargetState.new(TargetState.SPELL, c.rules.skill(int(_ids[k]))))
	elif a.is_cancel():
		c.pop()

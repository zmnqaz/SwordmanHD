# SPDX-License-Identifier: GPL-3.0-only
class_name ActionMenuState
extends BattleState
## 2.4 行动菜单 (爆發 / 法術 / 攻擊 / 物品 / 待機), 原版 图标横排, 在单位下方。
##   初始选中攻擊; 方向 Up/Right +1、Down/Left −1, 夹紧不循环, 跳过禁用项 (§5-8)。
##   禁用: 爆發 = 移动过 (或不能爆發); 法術 = 移动过且没有可用法术 (未移动时总可用)。麻痺时选攻擊无反应。
##   确认: 爆發 -> 结束行动 (下回合移动力 ×2); 法術 -> 法术列表; 攻擊 -> 攻击目标; 物品 -> 菜单变灰, 打开物品子菜单; 待機 -> 结束行动。
##   取消: 撤销移动 (单位瞬间回原位, 返还移动力), 光标留在移动后的位置, 回到光标状态 (§5-18)。

const U = preload("res://engine/rules/unit_state.gd")

var menu: UiIconMenu


func enter() -> void:
	var u: BattleUnit = c.sel
	c.view.clear_range()
	c.view.hide_info()
	c.show_cursor(false)
	var enabled := [c.rules.can_burst(u), spell_enabled(c.rules, u), true, true, true]
	menu = c.ui.icon_menu("actionmenu.icons", enabled, 2, Vector2i(u.cx, u.cy))


## 法術可用: 原地不动时总可用; 移动后须未封咒且有可用法术 (canUseSkill)
static func spell_enabled(rules, u: BattleUnit) -> bool:
	if not u.st.moved:
		return true
	if u.has_status(U.ST_SEAL):
		return false
	for id in u.skills:
		if rules.can_cast(u, int(id)):
			return true
	return false


func resume() -> void:
	if not is_instance_valid(menu):
		return
	menu.visible = true
	menu.dimmed = false
	c.view.hide_info()
	c.show_cursor(false)


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
			_choose(k)
	elif a.is_cancel():
		c.undo_move()


func _choose(k: int) -> void:
	var u: BattleUnit = c.sel
	match k:
		0:
			c.do_burst()
		1:
			menu.visible = false
			c.push(SpellListState.new())
		2:
			if u.has_status(U.ST_PARALYZE):
				return  # 原版: 麻痺时确认攻擊无反应 (GameBattleInput.cs:1482-1485)
			menu.visible = false
			c.push(TargetState.new(TargetState.ATTACK))
		3:
			menu.dimmed = true
			c.push(ItemMenuState.new(menu))
		4:
			c.do_wait()

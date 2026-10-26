# SPDX-License-Identifier: GPL-3.0-only
class_name TargetState
extends BattleState
## 选目标: 攻击 (2.5)、法术 (2.6)、物品使用 (2.7)。光标在地图上自由移动 (不是在目标间循环), 可查看单位。
##   确认: 光标格合法才执行 —— 攻击: 在武器范围内且站着敌对单位; 法术/物品: 在施放范围内且效果范围内有合法目标; 否则无反应。
##   交給 (GIVE): 范围 = 相邻 4 格, 光标格上必须是相邻的我方队友; 确认 -> BattleInput.do_give (对方物品栏满了换物品)。
##   取消: 收起范围, 回到行动菜单 (法术、物品也回行动菜单而不是列表, §5-4); 攻击取消不撤销移动。

enum { ATTACK, SPELL, ITEM, GIVE }

var kind := ATTACK
var skill := {}
var item := -1
var _cells: Array = []     # 显示的范围
var _valid := {}           # 可确认的格


func _init(k: int, payload = null) -> void:
	cursor_mode = true
	kind = k
	if k == SPELL:
		skill = payload
	elif k == ITEM:
		item = int(payload)
	elif k == GIVE:
		item = int(payload)   # 要给的物品栏格号


func enter() -> void:
	var u: BattleUnit = c.sel
	var here := Vector2i(u.cx, u.cy)
	var first := here
	match kind:
		ATTACK:
			_cells = c.rules.weapon_cells(u, here)
			for t in c.rules.targets_from(u, here):
				_valid[Vector2i(t.cx, t.cy)] = true
		SPELL:
			_cells = c.rules.cast_range(u, skill)
			for x in c.rules.cast_cells(u, skill):
				_valid[x] = true
		ITEM:
			_cells = c.rules.item_range(u, item)
			for x in c.rules.item_cells(u, item):
				_valid[x] = true
		GIVE:
			for t in c.rules.give_targets(u):
				_valid[Vector2i(t.cx, t.cy)] = true
			_cells = [here + Vector2i(1, 0), here + Vector2i(-1, 0), here + Vector2i(0, 1), here + Vector2i(0, -1)]
	c.view.show_range(_cells, BattleView.RANGE_ATTACK if kind in [ATTACK, SPELL] else BattleView.RANGE_MOVE)
	if not _valid.is_empty():
		first = _valid.keys()[0]
	c.view.set_cursor_area(_cursor_area())   # 原版: 效果范围 > 0 的落点, 光标是对应大小的菱形 (Misc/Cursor 3x3 / 5x5 / 7x7)
	c.set_cursor(first)


## 光标形状: 法术 / 道具 = 效果范围, 攻击与交給单格
func _cursor_area() -> int:
	match kind:
		SPELL:
			return c.rules.cast_area(skill)
		ITEM:
			return c.rules.item_area(item)
	return 0


func resume() -> void:
	c.view.show_range(_cells, BattleView.RANGE_ATTACK if kind in [ATTACK, SPELL] else BattleView.RANGE_MOVE)
	c.show_cursor()


func exit() -> void:
	c.view.clear_range()
	c.view.set_cursor_area(0)


func confirm() -> void:
	if not _valid.has(c.cur):
		return
	match kind:
		ATTACK:
			c.do_attack(c.rules.unit_at(c.cur))
		SPELL:
			c.do_cast(skill, c.cur)
		ITEM:
			c.do_item(item, c.cur)
		GIVE:
			c.do_give(item, c.rules.unit_at(c.cur))


func cancel() -> void:
	c.set_cursor(Vector2i(c.sel.cx, c.sel.cy))
	c.pop_to(ActionMenuState)

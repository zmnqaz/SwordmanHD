# SPDX-License-Identifier: GPL-3.0-only
class_name ItemListState
extends BattleState
## 2.7 物品列表 (原版 物品面板 Man_int 第 45 帧: 类型图标、装备标记、红框选中, 下方说明栏; UiListMenu.ITEM)。
##   列表: 本人 10 格 (装备占格, 已装备的带装备标记, 同名物品各占一行); 战斗中只能用本人的物品, 公共行囊只在营地。
##   各模式可用项: 使用 = 能用的 (BattleRules.usable_items); 交給 = 未装备的 (且相邻有队友); 裝備 = 本人能装备且不是当前武器/防具 (已装备饰物可卸下); 丟棄 = 未装备的。
##   确认: 使用 -> 物品目标; 交給 -> 选相邻队友 (TargetState.GIVE); 裝備 -> 立即装备; 丟棄 -> 是/否 (默认否), 是则丢一件。
##   装备、丢弃不消耗行动 (原版实测), 之后留在列表里刷新 (装备标记/格子), 可接着装备、卸下、丢弃, 移动范围不动
##   (2026-10-11 用户要求: 不退出菜单; 魔改开关 equip_costs_action 时仍结束行动, 见 BattleInput.after_equip_or_discard)。
##   取消 -> 物品子菜单。
##   裝備模式下按住空格 = 装备效果预览 (手柄 R3、查看键 F / 鼠标中键 / 触屏长按 / 手柄 X 同样按住有效): 选中项可装备时显示装备预览 (EE_PRO, 同营地), 松开关闭 (GetAsyncKeyState(空格))。

enum { USE, GIVE, EQUIP, DROP }

var mode := USE
var list: UiListMenu
var _ids: Array = []
var _asking := false
var _preview: Node2D


func _init(m: int) -> void:
	mode = m


func enter() -> void:
	c.view.hide_info()
	list = c.ui.list_menu(UiListMenu.ITEM, _rows(), -1)


func _rows() -> Array:
	var u: BattleUnit = c.sel
	var rules = c.rules
	_ids = u.st.items.slice(0, UiListMenu.SLOTS)
	var equipped: Dictionary = rules.inv_equipped(u)
	var usable: Array = rules.usable_items(u) if mode == USE else []
	var has_target: bool = mode != GIVE or not rules.give_targets(u).is_empty()
	var rows := UiListMenu.item_rows(_ids, equipped)
	for i in rows.size():
		match mode:
			USE:
				rows[i]["enabled"] = int(_ids[i]) in usable
			GIVE:
				rows[i]["enabled"] = has_target and rules.inv_can_give(u, i)
			DROP:
				rows[i]["enabled"] = rules.inv_can_give(u, i)
			EQUIP:
				rows[i]["enabled"] = rules.inv_can_equip(u, i)
	return rows


func _refresh() -> void:
	var sel := list.selected
	list.setup(UiListMenu.ITEM, _rows(), sel)


func exit() -> void:
	_close_preview()
	if is_instance_valid(list):
		list.queue_free()


func on_action(a: UiAction) -> void:
	if a.kind == UiAction.SELECT_UP or a.kind == UiAction.INFO_UP:
		_close_preview()
		return
	if (a.echo and not a.is_dir()) or _asking:
		return
	if (a.kind == UiAction.SELECT or a.kind == UiAction.INFO) and mode == EQUIP:
		_open_preview()
		return
	if _preview:
		return
	if a.is_dir():
		list.move(a.dir())
	elif a.is_confirm():
		var k := list.confirm()
		if k >= 0:
			_choose(k)
	elif a.is_cancel():
		c.pop()


## k = 物品栏格号 (每格一行, 同名物品各占一行)
func _choose(k: int) -> void:
	var u: BattleUnit = c.sel
	var id: int = _ids[k]
	match mode:
		USE:
			c.replace(TargetState.new(TargetState.ITEM, id))
		GIVE:  # 选相邻队友 (消耗行动; 对方满了换物品, 见 BattleInput.do_give)
			c.replace(TargetState.new(TargetState.GIVE, k))
		EQUIP:  # 只改装备记录, 物品留在格子里; 饰物再选一次卸下; 不消耗行动, 留在列表里
			c.rules.inv_equip(u, k)
			await _after_change()
		DROP:  # 原版先弹是/否小框 (默认否), 丢弃后留在列表, 不消耗行动
			_asking = true
			c.busy = true
			var yes: bool = await c.ui.choice.ask(UiStrings.t("item.ask.drop", [BattleFlow.item_name(id)]), UiStrings.t("common.yes"), UiStrings.t("common.no"), false)
			c.busy = false
			_asking = false
			if yes:
				c.rules.inv_discard(u, k)
				await _after_change()


## 装备/丢弃之后: 魔改开关下行动结束 (状态已被弹掉), 否则列表原地刷新, 选中项不变 (连着装备、卸下不用重新进菜单)
func _after_change() -> void:
	await c.after_equip_or_discard(true)
	if is_instance_valid(list) and c.top() == self:
		_refresh()


func _open_preview() -> void:
	var k := list.selected
	if _preview or k < 0 or k >= _ids.size() or not list.rows[k].get("enabled", true):
		return
	var at := UiEquipPreview.at_list_slot(UiListMenu.panel_pos(list.layout), list.slot_pos(k), k)
	_preview = UiEquipPreview.new(int(c.sel.man["unit_id"]), _ids[k], 0, 0, at, c.sel)   # 按战场单位当前装备算, 不是营地存档
	list.add_child(_preview)


func _close_preview() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null

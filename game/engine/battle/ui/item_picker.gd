# SPDX-License-Identifier: GPL-3.0-only
class_name ItemPicker
extends RefCounted
## 模态选一件物品 (战斗中: 宝箱/掉落时物品栏满了选丢哪件; 给予对方满了选换哪件)。
## 列表同物品列表 UiListMenu.ITEM (某人的 10 格, 装备带标记, 不可选的变淡); 方向/确认/取消走统一输入层 (界面栈顶), 鼠标点选走 ui_hits。
## 自动测试 (--fast) 不开界面: 直接选第一个可选的。取消返回 -1。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal picked(index: int)

var list: UiListMenu


## ui: BattleUi (无类型, 测试可换替身); ids: 物品编号; equipped: {格号: 装备槽}; enabled: 每格能否选
func run(ui, ids: Array, equipped: Dictionary, enabled: Array) -> int:
	if gc.fast:
		return enabled.find(true)
	var rows := UiListMenu.item_rows(ids, equipped)
	for i in rows.size():
		rows[i]["enabled"] = bool(enabled[i])
	list = ui.list_menu(UiListMenu.ITEM, rows, -1)
	InputRouter.push(self)
	var k: int = await picked
	InputRouter.pop(self)
	list.queue_free()
	list = null
	return k


func ui_pointer_target() -> Object:
	return list


func ui_action(a: UiAction) -> bool:
	if list == null or (a.echo and not a.is_dir()):
		return true
	if a.is_dir():
		list.move(a.dir())
	elif a.is_confirm():
		var k := list.confirm()
		if k >= 0:
			picked.emit(k)
	elif a.is_cancel():
		picked.emit(-1)
	return true

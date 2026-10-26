# SPDX-License-Identifier: GPL-3.0-only
class_name UiEquipPreview
extends Node2D
## 装备预览 CEquipEffectWindow (Misc/EE_PRO): 物品窗里在能装备的行上按住空格时显示, 松开关闭。
##   位置: x = 左栏 44 / 右栏 110; y = 54+13r (r ≤ 4) 或 13r−38 (r ≥ 5), r 为选中行在本页的行号。
##   数值 %4d, 步进 7, 空格画空白格: 左列 旧值 x=17、新值 x=54; 右列 旧值 x=96、新值 x=134;
##   行 y = 11, 20, 36, 51, 66: 左列 攻 防 火 雷 冰, 右列 命中 回避 幻 華 冥。
##   旧值用第 1 帧字模; 新值相等用第 1 帧, 变好第 2 帧 (绿), 变差第 3 帧 (红);
##   攻/防/命中/回避 越大越好, 抗性 (受伤倍率) 越小越好 (实测: 抗性 27→43 显示红色)。
##   打开时自上滑入 16,8,4,2,0。
##   战场物品列表: 裝備模式下按住空格、选中项可装备时显示,
##   位置 = 列表面板 + 槽位 + (22, 13) (左列) / (−102, 13) (右列)。
## 坐标取布局表 camp.equip.* (面板 y 按行号查表; 数值按 [列, 行] 点表: 第 2c 个 = 第 c 列旧值, 2c+1 = 新值)。


## at: 指定位置 (战场物品列表用 at_list_slot 算); 缺省按物品窗的栏/行
## unit: 战场单位 (BattleUnit); 给了就按它当前的装备/五维算, 否则取营地存档 (战场里换过装备、升过级, 存档是旧的)
func _init(uid: int, item_id: int, side: int, row: int, at := Vector2.INF, unit = null) -> void:
	var bg := UiLayout.panel("camp.equip.panel", row, {"which": side})
	var pos := bg.position if at == Vector2.INF else at
	bg.position = Vector2.ZERO
	position = pos
	add_child(bg)
	var old := UiUnitStats.calc(uid) if unit == null else UiUnitStats.calc_unit(unit)
	var new := UiUnitStats.calc(uid, UiUnitStats.gear_with(uid, item_id)) if unit == null \
		else UiUnitStats.calc_unit(unit, UiUnitStats.with_item(unit.gear, item_id))
	var keys_l := [["attack"], ["defence"], ["res", 0], ["res", 1], ["res", 2]]
	var keys_r := [["hit"], ["evade"], ["res", 3], ["res", 4], ["res", 5]]
	for k in 5:
		_pair(_val(old, keys_l[k]), _val(new, keys_l[k]), 0, k, k >= 2)
		_pair(_val(old, keys_r[k]), _val(new, keys_r[k]), 1, k, k >= 2)
	UiSlide.run(self, pos, Vector2.UP, CampUi.SLIDE, true)


static func _val(d: Dictionary, key: Array) -> int:
	return int(d["res"][key[1]]) if key[0] == "res" else int(d[key[0]])


## 第 col 列 (0 左 / 1 右) 第 row 行: 旧值 + 新值 (相等 / 变好 / 变差 选 digits.frame 的第 0/1/2 项)
## 数值只画绝对值, 不带负号: 抗性被饰品压到负数 (天河朱砂 冰 200: 75 -> -75) 原版画的是「七五」, 颜色仍按带符号的新旧比 (实测 2026-10-18)
func _pair(a: int, b: int, col: int, row: int, lower_better: bool) -> void:
	add_child(UiLayout.number("camp.equip.values", absi(a), 0, {"ix": 2 * col, "iy": row}))
	var better := b < a if lower_better else b > a
	add_child(UiLayout.number("camp.equip.values", absi(b), 0, {"ix": 2 * col + 1, "iy": row, "which": 0 if b == a else (1 if better else 2)}))


## 战场物品列表第 slot 槽的预览位置 (相对列表所在坐标系): panel = 面板左上角, slot_pos = 槽左上角 (相对面板)
static func at_list_slot(panel: Vector2, slot_pos: Vector2, slot: int) -> Vector2:
	var off := UiLayout.vec("camp.equip.list_offset", "left" if slot < 5 else "right")
	return panel + slot_pos + off

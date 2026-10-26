# SPDX-License-Identifier: GPL-3.0-only
class_name BattleUnitDetail
extends UiProfile
## 战场单位详情 (原版 / 重制版 GameUnitUI, 2.10): 与营地「體態觀覽」同一界面 (Misc/Man_pro),
## 数据取战场单位当前状态 (体力/术力为当前值)。确认翻页 (属性 → 物品 → 法术, 循环), 取消关闭; 战场中方向键不换人。
## 人物图: 主角 (单位 0~9) 用 Camp_man 立绘; 其他单位 (怪物 / NPC) 没有立绘, 循环播放它自己的战场站立动画 (原版就是动图, 用户指出, 夜魑会吐舌头)。

const UnitState = preload("res://engine/rules/unit_state.gd")
const CS = preload("res://engine/ui/unit_stats.gd")

var units: Array = []   # BattleUnit, uids 为其下标


func _init(u: BattleUnit) -> void:
	units = [u]
	super([0])


func unit_data(i: int) -> Dictionary:
	var u: BattleUnit = units[i]
	var st = u.st
	var uid := int(u.man["unit_id"])
	var gear := {"weapon": st.weapon if st.weapon >= 0 else null, "armor": st.armor if st.armor >= 0 else null,
		"accessory": st.accessory if st.accessory >= 0 else null}
	var w := _item(st.weapon)
	var a := _item(st.armor)
	var c := _item(st.accessory)
	var calc := {"attack": u.attack, "defence": u.defence,
		"hit": int(w.get("hit", 0)) + int(c.get("hit", 0)), "evade": int(a.get("miss", 0)) + int(c.get("miss", 0))}
	var mag: Dictionary = Content.table_array("attribute_defense")[int(u.info.get("attribute_defence_id", 0))]["values"]
	var res: Array = []
	for k in AttrNames.RES_KEYS:
		var ar := int(a.get("attribute_defence", {}).get(k, 0))
		var cr := int(c.get("attribute_defence", {}).get(k, 0))
		res.append(CS._round_even(int(mag.get(k, 0)) * (100 - ar) * (100 - cr) / 10000.0))
	calc["res"] = res
	var items: Array = st.items.duplicate()
	var sp := {}
	for k in 5:
		sp[AttrNames.SPIRIT[k]] = int(st.spirit[k]) if k < st.spirit.size() else 0
	return {"name": u.name_text, "lv": u.lv, "exp": u.exp, "move": u.move_now, "hp": u.hp, "hp_max": u.hp_max,
		"mp": u.mp, "mp_max": u.mp_max, "stats": st.stats, "spirit": sp, "calc": calc, "items": items,
		"gear": gear, "skills": st.skills, "man": uid if Content.is_hero(uid) and uid < man_frames().size() else -1,
		"sprite_dir": u.sprite_dir()}


static func _item(id: int) -> Dictionary:
	return Content.items()[id] if id >= 0 and id < Content.items().size() else {}


## 战场中方向键不换人
func key(k: String) -> void:
	if k in ["left", "right"]:
		return
	super(k)

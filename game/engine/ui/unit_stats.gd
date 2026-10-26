# SPDX-License-Identifier: GPL-3.0-only
class_name UiUnitStats
extends RefCounted
## 营地界面显示用的人物数值 (只读; 公式, 已用原版截图核对):
##   攻 = 攻 + 武器.attack + 饰物.attack 防 = 护具.defence + 防/2 + 饰物.defence
##   命中 = 武器.hit + 饰物.hit                            回避 = 护具.miss + 饰物.miss
##   抗性 = MAG_OPP × (100 − 护具抗) × (100 − 饰物抗) / 10000, 显示顺序 火 雷 冰 幻 華(光) 冥(暗);
##     显示值按浮点四舍六入五成双取整 (实测 42.75→43、40.5→40、55.575→56)
##   移动 = Man_base 移动 + 行/25

const AttrNames = preload("res://engine/rules/attr_names.gd")


static func _it(id) -> Dictionary:
	if id == null or int(id) < 0:
		return {}
	return CampInventory.item(int(id))


## 营地: 取存档里的人物 (party 记录)。gear: {"weapon","armor","accessory"} (可传入替换后的装备做预览)
static func calc(uid: int, gear := {}) -> Dictionary:
	var g: Dictionary = GameContext.current().state.party_of(uid)
	return calc_of(Content.unit_at(uid), g.get("stats", {}), gear if not gear.is_empty() else g.get("gear", {}))


## 战场: 取战场单位 (BattleUnit) 当前的五维与装备 —— 营地存档只是进关时的值, 战场里换了装备/升了级就过期了。
## gear 缺省 = 单位身上的装备; 预览传 with_item(u.gear, 物品)
static func calc_unit(u, gear := {}) -> Dictionary:
	return calc_of(u.info, u.stats, gear if not gear.is_empty() else u.gear)


## 数值来源无关的核心: info = Man_base 记录 (移动、抗性表行), stats = 五维, gear = 三个装备栏
static func calc_of(info: Dictionary, st: Dictionary, gear: Dictionary) -> Dictionary:
	var w := _it(gear.get("weapon"))
	var a := _it(gear.get("armor"))
	var c := _it(gear.get("accessory"))
	var out := {
		"attack": int(st.get("str", 0)) + int(w.get("attack", 0)) + int(c.get("attack", 0)),
		"defence": int(a.get("defence", 0)) + int(st.get("vit", 0)) / 2 + int(c.get("defence", 0)),
		"hit": int(w.get("hit", 0)) + int(c.get("hit", 0)),
		"evade": int(a.get("miss", 0)) + int(c.get("miss", 0)),
		"move": int(info.get("move", 0)) + int(st.get("avg", 0)) / 25,
	}
	var mag: Dictionary = Content.table_array("attribute_defense")[int(info.get("attribute_defence_id", 0))]["values"]
	var res: Array = []
	for k in AttrNames.RES_KEYS:
		var ar := int(a.get("attribute_defence", {}).get(k, 0))
		var cr := int(c.get("attribute_defence", {}).get(k, 0))
		res.append(_round_even(int(mag.get(k, 0)) * (100 - ar) * (100 - cr) / 10000.0))
	out["res"] = res
	return out


## 营地: uid 装备 item_id 之后的装备 (饰物 / 武器 / 护具按类型替换)
static func gear_with(uid: int, item_id: int) -> Dictionary:
	return with_item(GameContext.current().state.party_of(uid).get("gear", {}), item_id)


## gear 装上 item_id 之后的装备栏 (按物品类型换对应栏; 不改传入的字典)
static func with_item(gear: Dictionary, item_id: int) -> Dictionary:
	var out := gear.duplicate()
	var t := int(CampInventory.item(item_id)["type"])
	if t >= 1 and t <= 3:
		out[CampInventory.SLOT_KEYS[t - 1]] = item_id
	return out


static func _round_even(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	if is_equal_approx(d, 0.5):
		return int(f) if int(f) % 2 == 0 else int(f) + 1
	return int(roundf(x))

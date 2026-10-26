# SPDX-License-Identifier: GPL-3.0-only
class_name CampInventory
extends RefCounted
## 营地物品数据接口 (囊內乾坤 / 諸物煉化 / 商店共用), 按原版模型组织: 公共行囊 + 每个在队主角 10 格 (装备也占格)。
## 原版: 队伍记录 字段 每人 10 格物品, 字段/字段/字段 为装备的物品编号 (指向格子里的物品);
## 营地「行囊」512 格。栏位顺序: [商店] 行囊 各在队主角 (按队伍记录顺序)。
##
## 数据: Game.state.party[uid]["items"] = 10 格物品编号数组 (含已装备的那几件; 战斗读写的就是它, 见 BattleUnit._init_stats / to_party);
##   主角记录没有 "items" 时用其装备 (gear) 生成 (兼容旧存档)。公共行囊 Game.state.bag 只在这里 (营地/商店/炼化) 出现, 战斗中不可用。
##   容量取规则参数 params.unit_item_slots / bag_capacity (engine/rules/inventory.gd 同一份)。
## 所有修改先作用在本对象的栏位上, commit() 写回 Game (原版退出界面时回写)。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

const ItemRules = preload("res://engine/rules/items.gd")
const InvRules = preload("res://engine/rules/inventory.gd")

const SLOT_KEYS := ["weapon", "armor", "accessory"]

## 栏位: {"kind": "shop"/"bag"/"unit", "uid", "name", "cap", "items": Array[int]}
var columns: Array = []
var shop_mode := false

## 行囊整理 (复刻新增, 攻略面板 F4 的「整理行囊」): 窗口开着时手里有一份行囊副本 (退出才回写), 整理要同时排这份副本。
## busy_fn: 窗口设的「正在做半截操作」判断 (菜单/问句/炼化选第二件, 这些操作按格下标记着物品, 此时整理会让下标指错), 为 true 时拒绝整理;
## dirty: 副本被整理过, 窗口下一帧重画 (窗口读后清零)
static var _live: Array = []   # 活动库存的弱引用
var busy_fn := Callable()
var dirty := false


static func items_db() -> Array:
	return Content.items()


static func item(id: int) -> Dictionary:
	return Content.item_at(id)


## 在队主角编号 (原版按队伍记录顺序, 只列名册 字段 在队标志为 1 的; 复刻版按加入 Game.state.party 的顺序, 标志见 GameState.in_team)
static func party_uids() -> Array:
	var st: GameState = GameContext.current().state
	return st.party.keys().map(func(x): return int(x)).filter(func(u): return st.in_team(u))


static func unit_name(uid: int) -> String:
	return String(Content.unit_at(uid)["name"])


## 某主角的 10 格 (M5 接口): 记录里的 items, 再按 gear 补齐已装备的物品 (没有 items 的旧存档即由装备生成)。
## 规则在 engine/rules/items.gd unit_slots, 所有人物物品栏界面都经这里取数据。
static func unit_items(uid: int) -> Array:
	var g: Dictionary = GameContext.current().state.party_of(uid)
	return ItemRules.unit_slots(g.get("items", []), g.get("gear", {}))


static func gear_of(uid: int) -> Dictionary:
	return GameContext.current().state.party_of(uid).get("gear", {})


## 商店栏名 = 店种名, 取内容包 enums.json 的 shop_type (原版名称: 0=武器店(武器护具) 1=雜物店(饰物) 2=藥店,
## §5.1; 简体按内容包文本惯例); 未登记的店种回退「商店」。名字是数据, 新游戏/mod 改 enums 即可。
## 营地各页读规则参数的统一入口 (如五魂化蕴上限 spirit_add_limit)
static func params():
	return Content.params()


func _init(shop_items: Array = [], shop_type: int = -1) -> void:
	_live = _live.filter(func(w): return w.get_ref() != null)
	_live.append(weakref(self))
	shop_mode = not shop_items.is_empty()
	var p = params()
	if shop_mode:
		columns.append({"kind": "shop", "uid": -1, "name": String(Content.enums("shop_type").get(str(shop_type), UiStrings.t("camp.shop"))), "cap": 0, "items": shop_items.map(func(x): return int(x))})
	columns.append({"kind": "bag", "uid": -1, "name": UiStrings.t("camp.bag"), "cap": int(p.bag_capacity), "items": gc.state.bag.map(func(x): return int(x))})
	for uid in party_uids():
		columns.append({"kind": "unit", "uid": uid, "name": unit_name(uid), "cap": int(p.unit_item_slots), "items": unit_items(uid)})


func col(i: int) -> Dictionary:
	return columns[i]


func is_full(c: int) -> bool:
	var cd: Dictionary = columns[c]
	return cd["kind"] != "shop" and cd["items"].size() >= int(cd["cap"])


## 栏 c 第 i 格的装备槽: 0 武器 / 1 护具 / 2 饰物, 未装备 -1 (按物品编号对应, 同编号只算第一件)
func equip_slot(c: int, i: int) -> int:
	var cd: Dictionary = columns[c]
	if cd["kind"] != "unit":
		return -1
	var id: int = cd["items"][i]
	var gear := gear_of(cd["uid"])
	for s in 3:
		var v = gear.get(SLOT_KEYS[s])
		if v != null and int(v) == id and cd["items"].find(id) == i:
			return s
	return -1


## 可动 (字段): 已装备的武器、护具不能选中
func movable(c: int, i: int) -> bool:
	var s := equip_slot(c, i)
	return s != 0 and s != 1


## 栏 c 的第 i 件能否被 uid 装备 (字段; 物品 equip_units 含此人)
static func can_equip(id: int, uid: int) -> bool:
	if uid < 0:
		return false
	var it := item(id)
	if int(it["type"]) < 1 or int(it["type"]) > 3:
		return false
	return uid in it.get("equip_units", []).map(func(x): return int(x))


## 图标用的「可装备」: 人物栏看本人, 行囊栏看对面栏的人
func equipable_for_icon(c: int, i: int, other: int) -> bool:
	var cd: Dictionary = columns[c]
	var uid: int = cd["uid"] if cd["kind"] == "unit" else int(columns[other]["uid"])
	return can_equip(cd["items"][i], uid)


## 三选项菜单: [给予/卖出, 装备/卸下, 丢弃] 各项是否可用, 以及第二项是否为「卸下」
func menu_state(c: int, i: int, other: int) -> Dictionary:
	var cd: Dictionary = columns[c]
	var od: Dictionary = columns[other]
	var id: int = cd["items"][i]
	var slot := equip_slot(c, i)
	var acc_on := slot == 2
	var give: bool = (od["kind"] == "shop") or not is_full(other)
	if cd["kind"] == "unit":
		return {"items": [give and not acc_on, can_equip(id, cd["uid"]), not acc_on], "unequip": acc_on}
	return {"items": [give, false, true], "unequip": false}


## 给予: 搬到对面栏末尾
func give(c: int, i: int, other: int) -> void:
	var id: int = columns[c]["items"][i]
	columns[c]["items"].remove_at(i)
	columns[other]["items"].append(id)


## 装备 / 卸下 (饰物再按一次卸下): 只改装备记录, 物品不移动
func toggle_equip(c: int, i: int) -> void:
	var cd: Dictionary = columns[c]
	var id: int = cd["items"][i]
	var gear: Dictionary = gc.state.party[cd["uid"]]["gear"]
	var key: String = SLOT_KEYS[int(item(id)["type"]) - 1]
	if equip_slot(c, i) == 2:
		gear[key] = null
	else:
		gear[key] = id


## 丢弃
func discard(c: int, i: int) -> void:
	columns[c]["items"].remove_at(i)


## 整理公共行囊 (按物品编号从小到大): 同时排 Game 里的行囊和所有开着的窗口手里的副本。
## 返回 {"ok", "busy" (有窗口在半截操作, 没排), "moved" (位置变了的格数), "total"}
static func resort_bag(ctx: GameContext) -> Dictionary:
	var live: Array = []
	for w in _live:
		var o = w.get_ref()
		if o != null:
			live.append(o)
	for o in live:
		if o.busy_fn.is_valid() and o.busy_fn.call():
			return {"ok": false, "busy": true, "moved": 0, "total": 0}
	var shown: Array = ctx.state.bag   # 有窗口开着时以窗口里 (可能还没回写) 的行囊为准
	for o in live:
		for cd in o.columns:
			if cd["kind"] == "bag":
				shown = cd["items"]
	var r := InvRules.sort_bag(shown)
	ctx.state.bag = (r["items"] as Array).duplicate()
	for o in live:
		for cd in o.columns:
			if cd["kind"] == "bag":
				cd["items"] = (r["items"] as Array).duplicate()
				o.dirty = true
	return {"ok": true, "busy": false, "moved": int(r["moved"]), "total": (r["items"] as Array).size()}


## 写回 Game (原版退出时回写所有栏)
func commit() -> void:
	for cd in columns:
		if cd["kind"] == "bag":
			gc.state.bag = cd["items"].duplicate()
		elif cd["kind"] == "unit":
			var g: Dictionary = gc.state.party[cd["uid"]]
			g["items"] = cd["items"].duplicate()
			# 不在格子里的装备一并卸下 (给出 / 丢掉了已装备的饰物等)
			for k in SLOT_KEYS:
				var v = g["gear"].get(k)
				if v != null and not int(v) in cd["items"]:
					g["gear"][k] = null


# ---------------- 诸物炼化材料池: 在队各人 10 格 (标注已装备) + 行囊 ----------------

## [{"id", "col", "idx", "owner" (人名 / 「行囊」), "slot" (装备槽 -1~2)}]
func forge_pool() -> Array:
	var out: Array = []
	for c in columns.size():
		var cd: Dictionary = columns[c]
		if cd["kind"] == "shop":
			continue
		for i in cd["items"].size():
			out.append({"id": cd["items"][i], "col": c, "idx": i, "owner": cd["name"], "slot": equip_slot(c, i)})
	# 原版顺序: 先各人, 后行囊
	var units := out.filter(func(e): return columns[e["col"]]["kind"] == "unit")
	return units + out.filter(func(e): return columns[e["col"]]["kind"] == "bag")


## 配方: 按编号从小到大找 (A,B) 或 (B,A), 取第一个
static func recipe(a: int, b: int) -> int:
	for it in items_db():
		var syn = it.get("synthesis")
		if syn is Array and syn.size() == 2 and ((int(syn[0]) == a and int(syn[1]) == b) or (int(syn[0]) == b and int(syn[1]) == a)):
			return int(it["id"])
	return -1


## 「可炼」: 至少有一条配方的两种材料都在池中 (只要求各有 1 件)
static func forgeable(id: int, pool: Array) -> bool:
	var ids := {}
	for e in pool:
		ids[e["id"]] = true
	for it in items_db():
		var syn = it.get("synthesis")
		if syn is Array and syn.size() == 2:
			var a := int(syn[0])
			var b := int(syn[1])
			if (a == id and ids.has(b)) or (b == id and ids.has(a)):
				return true
	return false


## 炼化: 删除 A、B 两条, 产物追加到行囊
func forge(ea: Dictionary, eb: Dictionary, product: int) -> void:
	var rm := [[ea["col"], ea["idx"]], [eb["col"], eb["idx"]]]
	rm.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] > y[1]))
	for r in rm:
		columns[r[0]]["items"].remove_at(r[1])
	for cd in columns:
		if cd["kind"] == "bag":
			cd["items"].append(product)
			break

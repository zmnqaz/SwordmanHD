# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 物品栏规则 (规格 §2 / 养成与物品 §1): 每人 10 格 (装备也占格) + 营地公共行囊 512。纯逻辑, 不碰界面与文件。
## 战斗中只有本人 10 格可用; 给予/宝箱/掉落都落在人的 10 格, 剧情给物品与炼化产物才进公共行囊 (那在 GameState/营地, 不在这里)。
## 容量取参数 params.unit_item_slots / bag_capacity (内容包 rules.json 可改, 魔改用)。
## 装备按物品编号记录, 同编号多件时只把第一件算作已装备。

const GEAR_SLOTS := ["weapon", "armor", "accessory"]


static func cap(ctx) -> int:
	return int(ctx.params.unit_item_slots)


static func is_full(ctx, u) -> bool:
	return u.items.size() >= cap(ctx)


## 第 i 格的装备槽: 0 武器 / 1 护具 / 2 饰物 / -1 未装备 (同编号只算第一件)
static func equipped_slot(u, i: int) -> int:
	if i < 0 or i >= u.items.size():
		return -1
	var id: int = int(u.items[i])
	if u.items.find(id) != i:
		return -1
	for s in 3:
		if int(u.get(GEAR_SLOTS[s])) == id:
			return s
	return -1


## 各格的装备槽 {格号: 槽} (界面用: 装备标记)
static func equipped_map(u) -> Dictionary:
	var out := {}
	for i in u.items.size():
		var s := equipped_slot(u, i)
		if s >= 0:
			out[i] = s
	return out


## 能交给别人 / 能丢弃: 不是已装备的那件 (饰物要先卸下)
static func can_give(u, i: int) -> bool:
	return i >= 0 and i < u.items.size() and equipped_slot(u, i) < 0


static func can_discard(u, i: int) -> bool:
	return can_give(u, i)


## 能装备: 物品是武器/护具/饰物, 本人在可装备名单里; 已装备的武器、护具不能再选 (只能换另一件),
## 已装备的饰物可再选一次卸下
static func can_equip(ctx, u, i: int) -> bool:
	if i < 0 or i >= u.items.size():
		return false
	var rec: Dictionary = ctx.item(int(u.items[i]))
	var t := int(rec.get("type", 0))
	if t < 1 or t > 3:
		return false
	if not u.unit_id in rec.get("equip_units", []).map(func(x): return int(x)):
		return false
	return equipped_slot(u, i) in [-1, 2]


## 装备 / 卸下 (饰物再按一次卸下): 只改装备记录, 物品不移动。返回装备槽编号 0~2 (卸下返回 -1)
static func equip(ctx, u, i: int) -> int:
	if not can_equip(ctx, u, i):
		return -1
	var id: int = int(u.items[i])
	var t := int(ctx.item(id)["type"])
	var key: String = GEAR_SLOTS[t - 1]
	if equipped_slot(u, i) == 2:
		u.set(key, -1)
		return -1
	u.set(key, id)
	return t - 1


## 丢弃第 i 格 (不消耗行动)。返回丢掉的物品编号, 不可丢返回 -1
static func discard(u, i: int) -> int:
	if not can_discard(u, i):
		return -1
	var id: int = int(u.items[i])
	u.items.remove_at(i)
	return id


## 放进 10 格末尾; 满了返回 false
static func pickup(ctx, u, id: int) -> bool:
	if is_full(ctx, u):
		return false
	u.items.append(id)
	return true


## 给予 (GITEPRO.MSG): 对方未满 -> 追加到对方末尾。返回 true; 对方满了返回 false, 由调用方走 exchange
static func give(ctx, from, i: int, to) -> bool:
	if not can_give(from, i) or from == to or is_full(ctx, to):
		return false
	to.items.append(int(from.items[i]))
	from.items.remove_at(i)
	return true


## 对方 10 格已满: 双方各选一件互换, 物品留在对方换走物品的格位 (「身上物品太多了,请选择欲交换的物品.」; 格位与对方已装备者能否被选 与「不能给已装备的」一致)
## 返回 {"ok", "got": 换回的物品编号}
static func exchange(from, i: int, to, j: int) -> Dictionary:
	if from == to or not can_give(from, i) or not can_give(to, j):
		return {"ok": false, "got": -1}
	var mine: int = int(from.items[i])
	var theirs: int = int(to.items[j])
	from.items[i] = theirs
	to.items[j] = mine
	return {"ok": true, "got": theirs}


## 消耗品用掉一件: 从本人格子扣。优先扣未装备的那一件。返回是否扣到
static func remove_one(u, id: int) -> bool:
	var first := -1
	for i in u.items.size():
		if int(u.items[i]) != id:
			continue
		if equipped_slot(u, i) < 0:
			u.items.remove_at(i)
			return true
		if first < 0:
			first = i
	if first >= 0:
		u.items.remove_at(first)
		return true
	return false


## 临时单位 (召唤物) 离场/死亡: 未装备的物品全部取出 (返回编号列表, 由调用方倒进公共行囊), 装备着的留在原地 [
## 死亡 / 剧情 0x36 / 战斗结束]。行囊满也照倒 (原版不检查, 复刻不丢物品)
static func dump_unequipped(u) -> Array:
	var out: Array = []
	var keep: Array = []
	for i in u.items.size():
		if equipped_slot(u, i) >= 0:
			keep.append(u.items[i])
		else:
			out.append(int(u.items[i]))
	u.items = keep
	return out


## 满了要丢一件时可选的格 (不含已装备的)
static func discard_candidates(u) -> Array:
	var out: Array = []
	for i in u.items.size():
		if can_discard(u, i):
			out.append(i)
	return out


## 公共行囊「整理」(复刻新增, 原版没有): 按物品编号从小到大排 = 物品表自己的顺序 (tdj 前 255 件按 武器 → 护具 → 饰物 → 道具 分段, 之后是剧情/特殊物品), 同件相邻。
## 返回 {"items": 排好的新数组, "moved": 位置变了的格数}; 不改入参
static func sort_bag(bag: Array) -> Dictionary:
	var sorted: Array = bag.map(func(x): return int(x))
	sorted.sort()
	var moved := 0
	for i in sorted.size():
		if int(bag[i]) != sorted[i]:
			moved += 1
	return {"items": sorted, "moved": moved}

# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 物品栏规则 (engine/rules/inventory.gd): 每人 10 格 (装备占格)、战斗只用本人格子、给予/交换、拾取满格、
## 以及存档 v1 -> v2 迁移 (旧公共行囊原样保留)。
const REQUIRES_TEST := {
	"test_can_use_only_own_items": ["data"],
	"test_equip_toggle_and_rules": ["data"],
	"test_receive_item_full_asks_to_discard": ["content"],
	"test_save_migration_v1_returns_initial_meds_to_owner": ["content"]
}  # 个别方法的依赖 (同上)

const Inv = preload("res://engine/rules/inventory.gd")
const ItemRules = preload("res://engine/rules/items.gd")


## 殷剑平式: 长剑 0 + 软革里衣 99 (都装备) + 两瓶金创药 220
func _hero(items := [0, 99, 220, 220], uid := 0):
	return unit({"items": items, "weapon": 0, "armor": 99, "unit_id": uid})


func test_equipped_marks_first_copy_only():
	var u = _hero([220, 0, 99, 0])
	eq(Inv.equipped_map(u), {1: 0, 2: 1}, "同编号多件只把第一件算已装备")
	check(Inv.can_give(u, 3), "第二把同编号的剑是普通物品, 可给")
	check(not Inv.can_give(u, 1) and not Inv.can_give(u, 2), "已装备的武器、护具不能给/丢")
	eq(Inv.discard(u, 1), -1, "不能丢已装备的")
	eq(Inv.discard(u, 0), 220, "能丢未装备的")
	eq(u.items, [0, 99, 0])


func test_equip_toggle_and_rules():
	var c = ctx_data()
	var u = _hero([0, 99, 220, 155, 70])   # 155 龙骨项链 (饰物, 殷剑平可戴), 70 金刚杖 (只有 5 号能用)
	check(not Inv.can_equip(c, u, 0), "已装备的武器不能再选")
	check(not Inv.can_equip(c, u, 2), "药不能装备")
	check(not Inv.can_equip(c, u, 4), "不在可装备名单里的不能装备")
	eq(Inv.equip(c, u, 3), 2, "装上饰物返回槽 2")
	eq(u.accessory, 155)
	check(Inv.can_equip(c, u, 3), "已装备的饰物可再选 (卸下)")
	check(not Inv.can_give(u, 3), "饰物装着时不能给")
	eq(Inv.equip(c, u, 3), -1, "再选一次卸下")
	eq(u.accessory, -1)
	eq(u.items.size(), 5, "装备/卸下不移动物品")


func test_pickup_cap_and_params():
	var c = ctx_data()
	var u = _hero([])
	for i in 10:
		check(Inv.pickup(c, u, 220), "第 %d 件放得下" % (i + 1))
	check(Inv.is_full(c, u), "10 格满")
	check(not Inv.pickup(c, u, 220), "满了放不进")
	var c2 = ctx_data(null, {"unit_item_slots": 12})
	check(not Inv.is_full(c2, u), "容量取参数 unit_item_slots")


func test_give_and_exchange():
	var c = ctx_data()
	var a = _hero([0, 99, 220, 216])
	var b = _hero([5, 220], 1)
	check(Inv.give(c, a, 2, b), "对方未满: 直接给")
	eq(a.items, [0, 99, 216])
	eq(b.items, [5, 220, 220], "追加到对方末尾")
	check(not Inv.give(c, a, 0, b), "已装备的不能给")
	var full = _hero([], 1)
	full.items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	check(not Inv.give(c, a, 2, full), "对方满了: give 失败, 走交换")
	var r := Inv.exchange(a, 2, full, 3)
	check(r.ok, "交换成功")
	eq(r.got, 4)
	eq(a.items, [0, 99, 4], "换回的物品留在自己被给出的那格")
	eq(full.items[3], 216, "给出的物品留在对方被换走的那格")
	full.weapon = 6
	check(not Inv.exchange(a, 2, full, 5).ok, "对方已装备的不能被换走")


## 交給友军 NPC (应奉仁式, 阵营 0 + AI): 规则层与给主角相同, 追加到对方末尾 [原版实测 序幕战阵档: 应奉仁物品栏 +1];
## 目标资格 (同阵营、敌人不行) 在 BattleRules.give_targets, 见 test_give_face.gd
func test_give_to_npc_ally_appends():
	var c = ctx_data()
	var a = _hero([0, 99, 220])
	var npc = unit({"side": 0, "npc_ally": true, "items": [0, 99]})
	check(Inv.give(c, a, 2, npc), "给友军 NPC")
	eq(npc.items, [0, 99, 220], "追加到末尾")
	eq(a.items, [0, 99], "给出者 -1")


func test_remove_one_prefers_unequipped():
	var u = _hero([220, 0, 220])
	check(Inv.remove_one(u, 220))
	eq(u.items, [0, 220], "用掉一件, 另一件留着")
	u.items = [0, 99]
	check(not Inv.remove_one(u, 220), "没有这件返回 false")


func test_can_use_only_own_items():
	var c = ctx_data()
	var u = _hero([0, 99, 220])
	check(ItemRules.can_use(c, u, 220), "本人格子里的药可用")
	u.items = [0, 99]
	check(not ItemRules.can_use(c, u, 220), "药在公共行囊 (不在本人格子里) 战斗不可用")
	check(not ItemRules.after_give(ctx_data(null, {"give_costs_action": false}), u), "give_costs_action = false 不结束行动")
	check(ItemRules.after_give(c, u), "默认交給结束行动")


func test_save_migration_v1_to_v2_keeps_bag():
	var d := {"version": 1, "stage": 3, "next_stage": 3, "gold": 5, "bag": [220, 220, 15], "game_data": {},
		"party": {"0": {"lv": 3, "gear": {"weapon": 0, "armor": 99, "accessory": null}},
			"1": {"lv": 4, "gear": {"weapon": 29}, "items": [29, 220]}}, "content": [{"id": "tdj", "version": ""}]}
	var r := SaveFile.migrate(d, "game")
	check(r.ok, "v1 存档可迁移")
	eq(int(r.data["version"]), SaveFile.VERSION)
	eq(r.data["bag"], [220, 220, 15], "旧公共行囊原样保留")
	eq(r.data["party"]["0"]["items"], [0, 99], "没有 items 的主角由装备生成 10 格")
	eq(r.data["party"]["1"]["items"], [29, 220], "已有的不动")
	var b := {"version": 1, "game": d.duplicate(true), "battle": {"units": []}}
	b["game"]["version"] = 1
	r = SaveFile.migrate(b, "battle")
	check(r.ok and int(r.data["game"]["version"]) == SaveFile.VERSION, "战阵存录内层同步迁移")
	eq(r.data["game"]["party"]["0"]["items"], [0, 99])


func test_save_migration_v1_returns_initial_meds_to_owner():
	# v1 时代: 殷剑平 (uid 0, 初始 [长剑, 软革里衣, 金创药 x2]) 初登场把两瓶药倒进行囊; 迁移还给本人 10 格, 别的行囊物品不动
	if not Content.is_hero(0):
		return
	var d := {"version": 1, "stage": 3, "next_stage": 3, "gold": 5, "bag": [220, 15, 220, 220], "game_data": {}, "seeded": [0],
		"party": {"0": {"lv": 3, "gear": {"weapon": 0, "armor": 99, "accessory": null}}}, "content": [{"id": "tdj", "version": ""}]}
	var r := SaveFile.migrate(d, "game")
	check(r.ok)
	eq(r.data["party"]["0"]["items"], [0, 99, 220, 220], "初始药回到本人格子")
	eq(r.data["bag"], [15, 220], "行囊里多的一瓶药和别的东西留着")
	d = {"version": 1, "stage": 3, "next_stage": 3, "gold": 5, "bag": [220], "game_data": {}, "seeded": [],
		"party": {"0": {"lv": 3, "gear": {"weapon": 0, "armor": 99, "accessory": null}}}, "content": [{"id": "tdj", "version": ""}]}
	r = SaveFile.migrate(d, "game")
	eq(r.data["bag"], [220], "没登场过的不动")


func test_dump_unequipped_for_summon_leaving():
	# 召唤物离场/死亡: 未装备的倒进行囊, 装备着的留下
	var u = _hero([0, 99, 220, 0, 155])
	eq(Inv.dump_unequipped(u), [220, 0, 155], "同编号第二把剑也是未装备")
	eq(u.items, [0, 99])
	eq(Inv.dump_unequipped(u), [], "再倒没有了")


# ---- 战斗拾取 (BattleFlow.receive_item): 宝箱/掉落进本人 10 格, 满了问是否丢一件 ----

class FakeRules:
	extends RefCounted
	var ctx
	func inv_pickup(u, id: int) -> bool:
		return Inv.pickup(ctx, u.st, id)
	func inv_can_give(u, i: int) -> bool:
		return Inv.can_give(u.st, i)
	func inv_discard(u, i: int) -> int:
		return Inv.discard(u.st, i)
	func inv_equipped(u) -> Dictionary:
		return Inv.equipped_map(u.st)


class FakeChoice:
	extends RefCounted
	var answer := true
	var asked: Array = []
	func ask(q: String, _y, _n, _d := true, _face := -1) -> bool:
		asked.append(q)
		return answer


class FakeUi:
	extends RefCounted
	var choice := FakeChoice.new()


class FakeView:
	extends RefCounted
	var ui := FakeUi.new()


class FakeUnit:
	extends RefCounted
	var st
	var man := {"unit_id": 0}


func test_receive_item_full_asks_to_discard():
	var root: Node = Engine.get_main_loop().root
	if root.get_node("Content").packs.is_empty():
		root.get_node("Content").load_packs([ContentDB.default_main()])
	var game: Node = root.get_node("Game")
	var was: bool = game.fast
	game.fast = true   # 选择框答「是」、选格器自动选第一个可选的 (不开界面)
	var rules := FakeRules.new()
	rules.ctx = ctx_data()
	var view := FakeView.new()
	var u := FakeUnit.new()
	u.st = _hero([0, 99, 220, 220, 220, 220, 220, 220, 220, 220])
	var ask := ["是否丢弃其它物品,来存放{0}.", "是", "否"]
	check(Inv.is_full(rules.ctx, u.st), "10 格满")
	var ok: bool = await BattleFlow.take_item(rules, view.ui, u, 215, ask)
	check(ok, "选是: 丢一件后放进")
	eq(view.ui.choice.asked.size(), 1, "问了一次")
	check(String(view.ui.choice.asked[0]).contains(String(root.get_node("Content").items()[215]["name"])), "问句带物品名")
	eq(u.st.items.size(), 10)
	eq(u.st.items[0], 0, "装备的长剑不会被丢")
	eq(u.st.items[1], 99, "装备的护具不会被丢")
	eq(u.st.items[-1], 215, "新物品放在末尾")
	view.ui.choice.answer = false
	ok = await BattleFlow.take_item(rules, view.ui, u, 216, ask)
	check(not ok, "选否: 放弃该物品 (宝箱则不开)")
	check(not 216 in u.st.items, "物品栏没变")
	u.st.items.pop_back()
	ok = await BattleFlow.take_item(rules, view.ui, u, 216, ask)
	check(ok and u.st.items[-1] == 216, "有空格直接放入, 不问")
	game.fast = was


## 公共行囊「整理」(复刻新增): 按物品编号从小到大; 不改入参; moved = 位置变了的格数; JSON 读回的浮点编号也规整成整数
func test_sort_bag_by_item_number():
	var src := [220, 0, 99, 0, 236]
	var r: Dictionary = Inv.sort_bag(src)
	eq(r["items"], [0, 0, 99, 220, 236], "按编号升序, 同件相邻")
	eq(r["moved"], 2, "位置变了的格数 (220 与第二把 0 对调)")
	eq(src, [220, 0, 99, 0, 236], "不改入参")
	eq(Inv.sort_bag([0, 0, 99, 220])["moved"], 0, "本来就有序: 一格都不动")
	eq(Inv.sort_bag([])["items"], [], "空行囊")
	eq(Inv.sort_bag([236.0, 1.0])["items"], [1, 236], "浮点编号 (JSON 读回) 规整成整数")

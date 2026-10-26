# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 人物 10 格数据 (engine/rules/items.gd unit_slots) 与物品栏界面数据 (CampInventory): 已装备的物品必须在人物栏里显示并带装备标记。
## 囊內乾坤、商店人物栏、諸物煉化、体态观览都经 CampInventory 取数据。
const REQUIRES_TEST := {
	"test_commit_keeps_gear_in_slots": ["content"],
	"test_original_gsf_shows_gear": ["content"],
	"test_replica_party_shows_gear": ["content"]
}  # 个别方法的依赖 (同上)

const ItemRules = preload("res://engine/rules/items.gd")


func _game() -> Node:
	return Engine.get_main_loop().root.get_node("Game")


## 临时替换 Game 的队伍/行囊, 结束后还原 (--script 运行时 autoload 的 _ready 还没跑, 内容包在这里载入)
func _with_party(party: Dictionary, bag: Array, f: Callable) -> void:
	var content: Node = Engine.get_main_loop().root.get_node("Content")
	content.load_packs([ContentDB.default_main()])  # 别的测试可能换过内容包
	var g: GameState = _game().state
	var saved := [g.party.duplicate(true), g.bag.duplicate(), g.gold, g.camp_no, g.game_data.duplicate(), g.seeded.duplicate()]
	g.party.clear()
	for k in party:
		g.party[k] = party[k]
	g.bag = bag.duplicate()
	f.call()
	g.party = saved[0]
	g.bag = saved[1]
	g.gold = saved[2]
	g.camp_no = saved[3]
	g.game_data = saved[4]
	g.seeded = saved[5]


func _unit_col(inv: CampInventory, uid: int) -> int:
	for c in inv.columns.size():
		if inv.col(c)["kind"] == "unit" and int(inv.col(c)["uid"]) == uid:
			return c
	return -1


## 栏 c 里各已装备物品的 [编号, 装备槽]
func _marked(inv: CampInventory, c: int) -> Array:
	var out: Array = []
	for i in inv.col(c)["items"].size():
		var s := inv.equip_slot(c, i)
		if s >= 0:
			out.append([inv.col(c)["items"][i], s])
	return out


func test_unit_slots_rule():
	var gear := {"weapon": 29, "armor": 99, "accessory": null}
	eq(ItemRules.unit_slots([], gear), [29, 99], "没有 items: 由装备生成")
	eq(ItemRules.unit_slots([220, 99.0], gear), [220, 99, 29], "items 缺了剧情换上的武器: 补在末尾, 不重复已有的")
	eq(ItemRules.unit_slots([0, 99, 220], {"weapon": 0, "armor": 99, "accessory": 155}, [155]), [0, 99, 220, 155], "收走的不在格子里时不影响装备补齐")
	eq(ItemRules.unit_slots([0, 216, 99], {"weapon": 0, "armor": 99, "accessory": null}, [216]), [0, 99], "收走的物品从格子里去掉")
	eq(ItemRules.unit_slots([220, 220, -1, null], {}), [220, 220], "同编号多件保留, 空格去掉")


func test_replica_party_shows_gear():
	# 复刻存档: 营地回写过 items 之后, 战斗里剧情 0x40 换了武器 (第 21 关 封寒月 装备 29), 记录的 items 落后于 gear
	var party := {
		0: {"lv": 3, "gear": {"weapon": 0, "armor": 99, "accessory": null}},  # 旧存档: 只有 gear
		1: {"lv": 9, "gear": {"weapon": 29, "armor": 104, "accessory": 155}, "items": [104, 220]},
	}
	_with_party(party, [220, 0], func():
		for shop in [[], [0, 15, 45, 95]]:
			var inv := CampInventory.new(shop)
			var tag := "商店" if shop.size() > 0 else "囊內乾坤"
			var c0 := _unit_col(inv, 0)
			var c1 := _unit_col(inv, 1)
			check(c0 >= 0 and c1 >= 0, tag + ": 两人都有人物栏")
			eq(inv.col(c0)["items"], [0, 99], tag + ": 只有 gear 的主角由装备生成格子")
			eq(_marked(inv, c0), [[0, 0], [99, 1]], tag + ": 武器/护具带装备标记")
			eq(inv.col(c1)["items"], [104, 220, 29, 155], tag + ": 剧情换上的武器、饰物补进格子")
			eq(_marked(inv, c1), [[104, 1], [29, 0], [155, 2]], tag + ": 三件装备都带标记")
			check(not inv.movable(c1, 2) and inv.movable(c1, 3), tag + ": 已装备武器不可选, 饰物可选")
			eq(inv.col(_unit_col(inv, 0) - 1)["kind"], "bag", tag + ": 行囊在人物栏之前")
		eq(CampInventory.unit_items(1), [104, 220, 29, 155], "体态观览等用的 unit_items 同一规则")
	)


func test_commit_keeps_gear_in_slots():
	var party := {1: {"lv": 9, "gear": {"weapon": 29, "armor": null, "accessory": null}, "items": [220]}}
	_with_party(party, [], func():
		var inv := CampInventory.new()
		inv.commit()
		eq(_game().state.party[1]["items"], [220, 29], "回写后记录里的 10 格含装备")
		eq(_game().state.party[1]["gear"]["weapon"], 29, "装备不被当成「不在格子里」卸下")
	)


## 物品/商店/炼化列表 Q/E 一次跳 7 格 (8 行窗口 MAX_SLOT-1), 两端夹紧
func test_page_jump_seven():
	eq(CampUi.page_jump(0, 30, 8, 1), 7)
	eq(CampUi.page_jump(7, 30, 8, 1), 14)
	eq(CampUi.page_jump(25, 30, 8, 1), 29, "夹在末项")
	eq(CampUi.page_jump(5, 30, 8, -1), 0, "夹在首项")
	eq(CampUi.page_jump(0, 0, 8, 1), 0, "空列表")


## 战场物品列表的装备预览位置: 面板 + 槽 + (22,13) 左列 / (−102,13) 右列
func test_battle_equip_preview_pos():
	eq(UiEquipPreview.at_list_slot(Vector2(59, 41), Vector2(8, 21), 1), Vector2(89, 75))
	eq(UiEquipPreview.at_list_slot(Vector2(59, 41), Vector2(104, 8), 5), Vector2(61, 62))


## 攻略面板 F4「整理行囊」(复刻新增): 同时排 Game 里的行囊和开着的窗口手里 (含还没回写的) 那份副本, 窗口收到 dirty 重画;
## 窗口在半截操作 (busy_fn) 时拒绝, 什么都不动
func test_resort_bag_syncs_open_window_and_refuses_when_busy():
	var party := {0: {"lv": 1, "gear": {"weapon": 0, "armor": null, "accessory": null}, "items": [0]}}
	_with_party(party, [236, 0, 220, 0], func():
		var ctx := GameContext.current()
		var inv := CampInventory.new()
		var bc := -1
		for c in inv.columns.size():
			if inv.col(c)["kind"] == "bag":
				bc = c
		inv.col(bc)["items"].append(99)   # 窗口里刚「给予」进来、还没回写
		inv.busy_fn = func(): return true
		var r := CampInventory.resort_bag(ctx)
		check(r["busy"] and not r["ok"], "窗口在半截操作: 拒绝整理")
		eq(inv.col(bc)["items"], [236, 0, 220, 0, 99], "拒绝时窗口副本不动")
		eq(ctx.state.bag, [236, 0, 220, 0], "拒绝时 Game 行囊不动")
		check(not inv.dirty, "拒绝时窗口不用重画")
		inv.busy_fn = func(): return false
		r = CampInventory.resort_bag(ctx)
		check(r["ok"] and not r["busy"], "窗口空闲: 整理")
		eq(inv.col(bc)["items"], [0, 0, 99, 220, 236], "窗口副本 (含未回写的 99) 排好")
		eq(ctx.state.bag, [0, 0, 99, 220, 236], "Game 行囊同样排好, 窗口退出回写不会盖回旧顺序")
		eq([r["moved"], r["total"]], [4, 5], "位置变了几格 / 共几件 (以窗口副本为准)")
		check(inv.dirty, "窗口收到重画标记")
		inv.commit()
		eq(ctx.state.bag, [0, 0, 99, 220, 236], "回写后仍是整理后的顺序")
	)

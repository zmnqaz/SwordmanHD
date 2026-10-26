# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 营地装备预览 (UiUnitStats) 与战斗数值 (rules/stats.gd) 同一公式: 对每个 (人物, 可装备物品) 逐一比对
## 攻/防/命中/回避 (规格)。预览显示的「新值」必须等于装备后战场上的实际值。

const REQUIRES_TEST := {  # 个别方法的依赖 (run_tests.gd 头注), 缺则 SKIP
	"test_preview_draws_negative_resist_unsigned": ["original"]
}
const REQUIRES := ["content", "data"]  # 缺则整个文件 SKIP (run_tests.gd 头注); 实测: 移走对应产物后这些测试失败

var _saved: Dictionary


func _ready_content() -> bool:
	var C = Engine.get_main_loop().root.get_node_or_null("Content")
	if C == null:
		return false
	if C.packs.is_empty():
		C.load_packs([ContentDB.default_main()])
	return true


func test_preview_equals_battle_stats():
	if not _ready_content():
		check(true)
		return
	var g: GameState = GameContext.current().state
	var saved_party = g.party.duplicate(true)
	var ctx = ctx_data()
	var checked := 0
	var bad := 0
	for uid in 10:
		var base: Dictionary = {"lv": 20, "exp": 0, "hp_max": 300, "mp_max": 100, "items": [], "skills": [], "spirit": {},
			"stats": {"str": 61, "int": 47, "avg": 53, "vit": 38, "luk": 29}, "gear": {"weapon": null, "armor": null, "accessory": null}}
		for it in Content.items():
			var t := int(it["type"])
			if t < 1 or t > 3 or not uid in it.get("equip_units", []).map(func(x): return int(x)):
				continue
			var gear: Dictionary = {"weapon": null, "armor": null, "accessory": null}
			gear[["weapon", "armor", "accessory"][t - 1]] = int(it["id"])
			base["gear"] = gear.duplicate()
			g.party = {uid: base.duplicate(true)}
			var cs: Dictionary = UiUnitStats.calc(uid)
			var u = unit({"str": 61, "int": 47, "avg": 53, "vit": 38, "luk": 29})
			u.unit_id = uid
			u.weapon = -1 if gear["weapon"] == null else int(gear["weapon"])
			u.armor = -1 if gear["armor"] == null else int(gear["armor"])
			u.accessory = -1 if gear["accessory"] == null else int(gear["accessory"])
			var Stats = preload("res://engine/rules/stats.gd")
			var ok: bool = cs["attack"] == Stats.atk(ctx, u) and cs["defence"] == Stats.def(ctx, u) \
				and cs["hit"] == Stats.equip_sum(ctx, u, "hit", ["weapon", "accessory"]) \
				and cs["evade"] == Stats.equip_sum(ctx, u, "miss", ["armor", "accessory"])
			checked += 1
			if not ok:
				bad += 1
				failures.append("预览与战斗数值不一致: uid %d 物品 %d %s: %s 战斗 atk %d def %d hit %d miss %d" % [uid, int(it["id"]), it["name"], str(cs), Stats.atk(ctx, u), Stats.def(ctx, u), Stats.equip_sum(ctx, u, "hit", ["weapon", "accessory"]), Stats.equip_sum(ctx, u, "miss", ["armor", "accessory"])])
	g.party = saved_party
	check(checked > 100, "核对了 %d 个 (人物, 装备) 组合" % checked)
	eq(bad, 0, "全部一致")


## 战场上的预览 (UiEquipPreview) 要取战场单位当前的装备/五维, 不是营地存档里的 party 记录: 战场里换了饰品、升了级之后,
## 存档还是进关时的旧值 —— 之前预览的「旧值」永远是进关时的装备 (用户 2026-10-17 「战场上看装备饰品的属性没有变化」)
class FakeBattleUnit:
	extends RefCounted
	var info: Dictionary
	var stats: Dictionary
	var gear: Dictionary


func test_battle_preview_uses_live_unit_not_camp_party():
	if not _ready_content():
		check(true)
		return
	var g: GameState = GameContext.current().state
	var saved_party = g.party.duplicate(true)
	var accs: Array = Content.items().filter(func(it): return int(it["type"]) == 3 and 0 in it.get("equip_units", []).map(func(x): return int(x)) \
		and (int(it.get("defence", 0)) != 0 or int(it.get("attack", 0)) != 0))
	check(accs.size() >= 2, "有两件加攻/防的饰物可比")
	var a: Dictionary = accs[0]
	var b: Dictionary = accs[accs.size() - 1]
	# 营地存档: 进关时空手 + 旧五维; 战场单位: 战场里已换上饰物 a, 且升级后五维变了
	g.party = {0: {"lv": 5, "exp": 0, "hp_max": 100, "mp_max": 50, "items": [], "skills": [], "spirit": {},
		"stats": {"str": 30, "int": 30, "avg": 30, "vit": 30, "luk": 30}, "gear": {"weapon": null, "armor": null, "accessory": null}}}
	var fu := FakeBattleUnit.new()
	fu.info = Content.unit_at(0)
	fu.stats = {"str": 44, "int": 30, "avg": 30, "vit": 40, "luk": 30}
	fu.gear = {"weapon": null, "armor": null, "accessory": int(a["id"])}
	var ctx = ctx_data()
	var Stats = preload("res://engine/rules/stats.gd")
	var ru = unit({"str": 44, "int": 30, "avg": 30, "vit": 40, "luk": 30})
	ru.unit_id = 0
	ru.accessory = int(a["id"])
	var cur: Dictionary = UiUnitStats.calc_unit(fu)
	eq([cur["attack"], cur["defence"]], [Stats.atk(ctx, ru), Stats.def(ctx, ru)], "战场单位当前攻/防 = 规则层 (含身上的饰物、升级后的五维)")
	check(cur["attack"] != UiUnitStats.calc(0)["attack"] or cur["defence"] != UiUnitStats.calc(0)["defence"], "与营地存档的旧值不同 (否则这个用例没有区分力)")
	# 预览「换上 b」的新值 = 把 b 放进饰物栏后的规则层数值
	ru.accessory = int(b["id"])
	var nw: Dictionary = UiUnitStats.calc_unit(fu, UiUnitStats.with_item(fu.gear, int(b["id"])))
	eq([nw["attack"], nw["defence"]], [Stats.atk(ctx, ru), Stats.def(ctx, ru)], "换上另一件饰物的预览新值")
	g.party = saved_party


## 抗性被饰品压到负数 (天河朱砂 冰 200: 75 -> -75): 原版装备预览画的是「七五」(无负号) 且仍判变好 (实测 2026-10-18)
func test_preview_draws_negative_resist_unsigned():
	if not _ready_content():
		check(true)
		return
	var item = null
	for it in Content.items():
		if int(it["type"]) == 3 and int(it.get("attribute_defence", {}).get("冰", 0)) >= 150:
			item = it
	if item == null:
		skip("没有冰抗 >= 150 的饰品")
		return
	var fu := FakeBattleUnit.new()
	fu.info = Content.unit_at(0)
	fu.stats = {"str": 30, "int": 30, "avg": 30, "vit": 30, "luk": 30}
	fu.gear = {"weapon": null, "armor": null, "accessory": null}
	var new: Dictionary = UiUnitStats.calc_unit(fu, UiUnitStats.with_item(fu.gear, int(item["id"])))
	check(int(new["res"][2]) < 0, "新冰抗确是负数 (%d)" % int(new["res"][2]))
	var p := UiEquipPreview.new(0, int(item["id"]), 0, 0, Vector2.ZERO, fu)
	var texts := []
	for n in p.get_children():
		if n is UiNumber:
			texts.append(String(n.text))
	check(not texts.is_empty(), "预览里有数字")
	for t in texts:
		check(not t.contains("-"), "数字不带负号: '%s'" % t)
	p.free()

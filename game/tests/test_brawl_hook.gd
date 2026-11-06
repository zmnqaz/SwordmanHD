# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 全技能大乱斗测试钩子 (engine/test/brawl.gd) 的参数解析与选施放者规则

const Brawl = preload("res://engine/test/brawl.gd")


func test_parse_args():
	var a := Brawl.parse(["--brawl", "--brawl-skills=0-2,6,53", "--brawl-owners=53:5,68:210", "--brawl-hp=0", "--brawl-tail=1500", "--other"])
	check(a.get("on", false), "--brawl 开启")
	eq(a["skills"], [0, 1, 2, 6, 53], "区间与单个混写")
	eq(a["owners"], {53: 5, 68: 210})
	eq(a["hp"], 0)
	eq(a["tail"], 1500)
	check(not Brawl.parse(["--brawl-skills=1"]).get("on", false), "没写 --brawl 不开启")
	var b := Brawl.parse(["--brawl", "--brawl-cell=53:7;5,6:9;2", "--brawl-no-gather"])
	eq(b["cells"], {53: Vector2i(7, 5), 6: Vector2i(9, 2)}, "指定落点")
	check(b.get("no_gather", false))


## 我方会这招 → 那个队员; 妖怪专属 (精灵不是我方任何人) → 敌人来放 (自爆等施放者会死的技能不会让主角阵亡判负)
func test_caster_choice():
	var hero := _u(0, 1, [42])
	var ally := _u(0, 5, [])
	var foe := _u(1, 30, [])
	var fake := _FakeFlow.new([hero, ally, foe])
	eq(Brawl._caster(fake, [hero, ally], 42, 1), hero, "会这招的队员")
	eq(Brawl._caster(fake, [hero, ally], 53, 5), ally, "精灵是我方某人 → 那人")
	eq(Brawl._caster(fake, [hero, ally], 70, 212), foe, "妖怪专属 → 敌人放")
	for u in [hero, ally, foe]:
		u.free()


func _u(side: int, spr: int, skills: Array) -> BattleUnit:
	var u := BattleUnit.new()
	u.info = {"name": "x", "camp": side, "sprite": spr}
	u.st.side = side
	u.st.alive = true
	u.st.skills = skills
	u.shown = true
	return u


class _FakeRules:
	var _us: Array
	func _init(us: Array) -> void:
		_us = us
	func units_alive() -> Array:
		return _us


class _FakeFlow:
	var rules
	func _init(us: Array) -> void:
		rules = _FakeRules.new(us)

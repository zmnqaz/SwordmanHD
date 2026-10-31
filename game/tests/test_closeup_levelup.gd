# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 近景升级演出: 我方单位升级了, 主攻和反击都演完之后 (经验框之前) 升级的单位做握拳动作 + 身上放光环 Misc/Ftlup_r + 音效, 放完才往下。
## 先后顺序按玩家反馈 (升级排在最后), 没有 实测的逐帧时间; 这里锁: 资源声明、只对我方、每个升级事件只放一次、只在真的升级时放。

const REQUIRES_TEST := {"test_ftlup_has_13_frames_and_two_sounds": ["original"]}


class FakeCloseup:
	extends BattleCloseup
	var calls := 0

	var last_unit = null
	var opens := 0
	var closes := 0

	func open(_a, _t, _at := Vector2i(-1, -1), _hide := false) -> void:
		opens += 1

	func close() -> void:
		closes += 1

	func level_up_fx(u = null) -> void:
		calls += 1
		last_unit = u


class FakeView:
	extends BattleView
	var calls := 0

	func _init() -> void:
		super(null, null)

	func level_up_fx(_u) -> void:
		calls += 1


class FlowStub:
	extends RefCounted
	var stats := StatsStub.new()

	func note_killer(_d, _a) -> void:
		pass


class StatsStub:
	extends RefCounted

	func strike(_a, _d, _r, _ap, _e) -> void:
		pass


class Stub:
	extends RefCounted
	var controllable := true
	var hp := 10


class RecActions:
	extends BattleActions
	var got := []

	func gain_exp(u: BattleUnit, e: int) -> void:
		got.append([u, e])


func _unit(hp: int) -> BattleUnit:
	var u := BattleUnit.new()
	u.hp = hp
	u.info = {"name": "测试"}   # _after_strike 的日志要读名字
	return u


func _actions() -> Array:
	var c := FakeCloseup.new(null)
	var a := BattleActions.new(null, null, null, null, c)
	return [a, c]


func test_asset_and_layout_declared() -> void:
	eq(ThemeAssets.p("battle.levelup_fx"), "Misc/Ftlup_r", "升级光环 = Misc/Ftlup_r")
	var cfg: Dictionary = UiLayout.el("closeup.levelup")
	eq(String(cfg.get("anim", "")), "battle.levelup_fx")
	check(float(cfg.get("delay", -1.0)) >= 0.0, "有 delay")


func test_ftlup_has_13_frames_and_two_sounds() -> void:
	var d: Dictionary = Assets.anim("Misc/Ftlup_r")
	eq(d["frames"].size(), 13, "13 帧")
	var snd := []
	for i in d["frames"].size():
		if int(d["frames"][i]["sound"]) >= 0:
			snd.append(i)
	eq(snd, [0, 1], "第 0 / 1 帧各响一个音效")


func test_level_fx_plays_once_for_a_leveling_player_unit() -> void:
	var p := _actions()
	var acts: BattleActions = p[0]
	var u := Stub.new()
	acts._exp_events = [{"unit": u, "exp": 300, "levels": 1}]
	await acts._level_fx(u)
	eq(p[1].calls, 1, "升级: 放一次")
	check(p[1].last_unit == u, "传的是升级的那个单位 (握拳的是它)")
	await acts._level_fx(u)
	eq(p[1].calls, 1, "同一个升级事件不重复放")
	p[1].free()


func test_map_spell_level_up_plays_on_the_map_not_in_a_closeup() -> void:
	var c := FakeCloseup.new(null)
	var v := FakeView.new()
	var acts := BattleActions.new(null, null, v, null, c)
	var u := Stub.new()
	acts._exp_events = [{"unit": u, "exp": 300, "levels": 1}]
	await acts._map_level_fx(u)
	eq(v.calls, 1, "地图上放一次升级光旋")
	eq([c.opens, c.calls], [0, 0], "不开近景")
	await acts._map_level_fx(u)
	eq(v.calls, 1, "同一个升级事件不重复放")
	acts._exp_events = [{"unit": u, "exp": 50, "levels": 0}]
	await acts._map_level_fx(u)
	eq(v.calls, 1, "没升级不放")
	u.hp = 0
	acts._exp_events = [{"unit": u, "exp": 300, "levels": 1}]
	await acts._map_level_fx(u)
	eq(v.calls, 1, "死了不放")
	c.free()
	v.free()


func test_level_fx_skipped_when_unit_died_before_it_ends() -> void:
	var p := _actions()
	var acts: BattleActions = p[0]
	var u := Stub.new()
	u.hp = 0   # 升了级却被反击打死
	acts._exp_events = [{"unit": u, "exp": 300, "levels": 1}]
	await acts._level_fx(u)
	eq(p[1].calls, 0, "死了就不演升级")
	p[1].free()


func test_level_fx_skips_non_leveling_and_non_player_units() -> void:
	var p := _actions()
	var acts: BattleActions = p[0]
	var u := Stub.new()
	acts._exp_events = [{"unit": u, "exp": 50, "levels": 0}]
	await acts._level_fx(u)
	eq(p[1].calls, 0, "没升级不放")
	var e := Stub.new()
	e.controllable = false
	acts._exp_events = [{"unit": e, "exp": 300, "levels": 1}]
	await acts._level_fx(e)
	eq(p[1].calls, 0, "敌方 / 友军不放 (我方才在近景右侧, 也只有我方弹经验框)")
	var other := Stub.new()
	acts._exp_events = [{"unit": u, "exp": 300, "levels": 1}]
	await acts._level_fx(other)
	eq(p[1].calls, 0, "事件不是这个单位的不放")
	p[1].free()


## 经验在战斗即将结束时统一结算: 还活着的才给, 被反击打死的拿不到 (玩家: 打死了肯定不能获得经验, 流程是结算经验 -> 发现升级 -> 走升级业务)
func test_settle_exp_only_for_survivors() -> void:
	var acts := RecActions.new(null, null, null, null, null)
	var alive := _unit(20)
	var dead := _unit(0)
	acts._pending_exp = [[alive, 300], [dead, 300]]
	acts._settle_exp()
	eq(acts.got.size(), 1, "只给活着的")
	check(acts.got[0][0] == alive and acts.got[0][1] == 300, "给的是活着的那个")
	eq(acts._pending_exp, [], "结算完清空")
	alive.free()
	dead.free()


func test_after_strike_defers_exp_instead_of_adding_it() -> void:
	var acts := RecActions.new(null, null, null, null, null)
	acts.flow = FlowStub.new()
	var a := _unit(20)
	var d := _unit(5)
	acts._after_strike(a, d, {"result": 1, "crit": false, "double": false, "damage": 3}, {}, 120)
	eq(acts.got.size(), 0, "出手之后不立刻加经验")
	eq(acts._pending_exp.size(), 1, "记在待结算里")
	a.free()
	d.free()

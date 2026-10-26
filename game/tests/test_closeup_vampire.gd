# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 近景武器吸血的表现与物理绝技的数字 (实测 2026-10-18):
##   吸血光环 = 近景构造按特效号载入的 Misc/Sp001r (攻方在右) / Sp001l (攻方在左), 8 帧 x 2 tick; 不是升级光环 Ftlup_r;
##   吸到的体力 (数字与黄条) 每周期涨 2% 上限 (上限 71, 每周期约 1.4, 20 -> 71 约 36 周期);
##   物理绝技的结果记录不带伤害数值标志 (摄魂鬼触) 时近景也不弹数字, 带的 (回风枪) 弹。

const REQUIRES_TEST := {  # 个别方法的依赖 (run_tests.gd 头注), 缺则 SKIP
	"test_heal_rises_two_percent_of_max_per_tick": ["original"],
	"test_heal_target_follows_a_hit_taken_while_rising": ["original"],
	"test_heal_clamped_by_max": ["original"]
}

const Skills = preload("res://engine/rules/skills.gd")


func _skill(id: int) -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../data/skills.json").simplify_path()
	if not FileAccess.file_exists(path):
		return {}
	for k in JSON.parse_string(FileAccess.get_file_as_string(path)):
		if int(k["id"]) == id:
			return k
	return {}


func test_ring_assets_are_sp001_both_sides():
	if not has_resource("original"):
		skip("缺原版资源")
		return
	var cfg: Dictionary = UiLayout.el("closeup.vampire")
	eq(ThemeAssets.p(String(cfg["anim"])), "Misc/Sp001r", "攻方在右: Sp001r")
	eq(ThemeAssets.p(String(cfg["anim_left"])), "Misc/Sp001l", "攻方在左: Sp001l")
	var r: Dictionary = Assets.anim("Misc/Sp001r")
	var l: Dictionary = Assets.anim("Misc/Sp001l")
	eq(r["frames"].size(), 8)
	eq(l["frames"].size(), 8)
	var pr: Dictionary = r["frames"][2]["parts"][0]
	var pl: Dictionary = l["frames"][2]["parts"][0]
	# 实测左右光环中心差 (-93,-43) = 两个 SAF 的原点差
	eq(int(pl["x"]) - int(pr["x"]), -93)
	eq(int(pl["y"]) - int(pr["y"]), -42)


func test_heal_rises_two_percent_of_max_per_tick():
	var p := BattleCloseup.InfoPanel.new(true, "殷剑平", 20, 71)
	p.heal(51)
	check(p.rise_to >= 0.0, "涨到 71")
	eq(p.rise_to, 71.0)
	p._process(0.04)
	check(absf(p.shown - 21.42) < 0.01, "第 1 周期涨 2% 上限 (1.42)")
	for i in 5:
		p._process(0.04)
	eq(int(p.shown), 28, "6 周期后数字 28 (原版: 20 -> 21 -> 24 -> 28)")
	for i in 40:
		p._process(0.04)
	eq(p.shown, 71.0, "涨满停在 71, 不超上限")
	eq(p.rise_to, -1.0)
	p.free()


func test_heal_target_follows_a_hit_taken_while_rising():
	var p := BattleCloseup.InfoPanel.new(true, "殷剑平", 20, 71)
	p.heal(51)
	for i in 10:
		p._process(0.04)
	var before := p.shown
	p.hit(16.0, true)
	eq(p.shown, before - 16.0)
	eq(p.rise_to, 55.0, "涨的终点跟着降 16 (原版: 反击命中后黄条接着涨)")
	for i in 60:
		p._process(0.04)
	eq(p.shown, 55.0)
	p.free()


func test_heal_clamped_by_max():
	var p := BattleCloseup.InfoPanel.new(true, "x", 60, 71)
	p.heal(51)
	eq(p.rise_to, 71.0, "吸血量已被攻方缺口限制, 这里再封一次上限")
	p.free()


func test_physical_skill_digits_follow_damage_flag():
	var s66 := _skill(66)
	var s49 := _skill(49)
	if s66.is_empty() or s49.is_empty():
		skip("缺 data/skills.json")
		return
	check(Skills.closeup_digits(s49, {"code": 2}), "回风枪近景弹红数字 (实测 70)")
	check(Skills.closeup_digits(s66, {"code": 2}), "摄魂鬼触没吸到术力 (码 2) 照弹 (原版: 敌方没有术力时弹 35)")
	check(not Skills.closeup_digits(s66, {"code": 11}), "摄魂鬼触吸术成功 (码 11) 近景一个数字都没有 (实测)")
	check(Skills.closeup_digits(_skill(69), {"code": 9}), "化血毒沫中毒成功 (码 9) 照弹 (原版: 116)")

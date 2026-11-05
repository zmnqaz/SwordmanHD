# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 近景武器吸血的表现与物理绝技的数字 (实测 2026-10-18):
##   吸血光环 = 近景构造按特效号载入的 Misc/Sp001r (攻方在右) / Sp001l (攻方在左), 8 帧 x 2 tick; 不是升级光环 Ftlup_r;
##   吸到的体力 (数字与黄条) 每周期涨 2% 上限 (上限 71, 每周期约 1.4, 20 -> 71 约 36 周期);
##   物理绝技的结果记录带伤害数值标志就弹数字 (回风枪 / 摄魂鬼触, 后者 重测); 摄魂鬼触另有攻方吸取光环 + 蓝数字。

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
	check(absf(p.shown - (before - 16.0)) < 1e-3, "扣 16 (32 位浮点)")
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
	check(Skills.closeup_digits(s66, {"code": 11}), "摄魂鬼触吸术成功 (码 11) 也弹 (2026-11-04 直读后缓冲重测: 388 / 384, 推翻 ⑥b,)")
	check(Skills.closeup_digits(_skill(69), {"code": 9}), "化血毒沫中毒成功 (码 9) 照弹 (原版: 116)")


## 摄魂鬼触 (ot1 oe6) 的近景吸取表现: 一进分支就置结果头 [+8] = 1 (格挡 / 没吸到也放), 蓝数字 = 施放者术力实涨量; 其它绝技没有
func test_closeup_drain_only_for_mp_drain_skill():
	var s66 := _skill(66)
	var s49 := _skill(49)
	if s66.is_empty() or s49.is_empty():
		skip("缺 data/skills.json")
		return
	eq(Skills.closeup_drain(s66, {"mp_gained": 112}), 112, "吸 112 术力: 蓝数字 112 (实测)")
	eq(Skills.closeup_drain(s66, {"code": 2}), 0, "没吸到 / 被格挡: 照放光环, 蓝数字 0 (实测: 目标没术力弹「0」)")
	eq(Skills.closeup_drain(s49, {"code": 2}), -1, "回风枪: 没有吸取表现")
	eq(Skills.closeup_drain(_skill(69), {"code": 9}), -1, "化血毒沫: 没有吸取表现")


## 蓝数字是施放者术力实际涨的量: 差 10 到满时只涨 10 (实测: 290/300 吸 112 弹「10」)
func test_drain_mp_records_actual_gain():
	var c := {"mp": 290, "mp_max": 300}
	var t := {"mp": 336, "mp_max": 336}
	var rec := {}
	Skills._drain_mp(c, t, 3, rec)
	eq(int(rec["mp_drained"]), 112, "目标掉 min(术力, 上限/3) = 112")
	eq(int(rec["mp_gained"]), 10, "施放者只涨到上限, 实涨 10")
	eq(int(c["mp"]), 300)
	eq(int(t["mp"]), 224)


## 经验框前的站位 (原版近景状态 0x13): 右侧挣经验的单位现身; 它这次是远程出手 ([字段]) 则藏左侧 (破魔杵 原版 直读)
func test_exp_pose_shows_right_and_hides_left_after_ranged():
	var cu := BattleCloseup.new(null)
	var u := BattleUnit.new()
	var e := BattleUnit.new()
	var rm := Node2D.new()
	var lm := Node2D.new()
	rm.visible = false   # 远程出手放完后攻方藏着
	cu._sides = {"right": {"unit": u, "misc": rm, "ranged": true}, "left": {"unit": e, "misc": lm, "ranged": false}}
	cu.exp_pose(u)
	check(not rm.visible and lm.visible, "近景没开着: 什么都不动")
	cu.visible = true
	cu.exp_pose(e)
	check(not rm.visible and lm.visible, "左侧单位 (敌方) 不弹经验框: 不动")
	cu.exp_pose(u)
	check(rm.visible, "右侧挣经验: 现身")
	check(not lm.visible, "右侧是远程出手: 藏左侧 (镜头回到攻方一侧)")
	lm.visible = true
	cu._sides["right"]["ranged"] = false
	cu.exp_pose(u)
	check(lm.visible, "近战出手: 左侧照旧")
	for n in [rm, lm, u, e, cu]:
		n.free()


## 带横幅的技能近景: Sp000 不挡出手, 横幅滑入完 (6 tick) 就开始攻击动画 (原版横幅清阻塞标志, 原版 直读)
func test_banner_releases_attack_after_slide_in():
	eq(BattleCloseup.banner_in_ticks(), 6, "横幅滑入 5 步 + 判到 0 的一 tick: Sp000 第 0 帧 tick 12 -> 出手 tick 18")

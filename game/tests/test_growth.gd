# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 升级成长, 06 五魂与习得
const REQUIRES_TEST := {
	"test_exp_threshold_and_cap": ["data"],
	"test_levelup_side_effects": ["data"],
	"test_max_growth_matches_patch_data": ["data"],
	"test_random_growth_range_stats": ["data"],
	"test_skill_learning_on_level_up_only": ["data"],
	"test_skill_slots_full": ["data"],
	"test_stat_cap_500": ["data"],
	"test_ref_batch_levelup_seed12345": ["data"],
	"test_ref_levelcap_seed777": ["data"],
	"test_ref_lv99_exp_kept": ["data"]
}  # 个别方法的依赖 (同上)

const Growth = preload("res://engine/rules/growth.gd")


func _yin_table(c) -> Dictionary:
	return c.levelup[0]


## 随机成长区间统计: 殷剑平 Str 每级 3 + rand%(3+1) → 3..6 均匀, 期望 4.5
func test_random_growth_range_stats():
	var c = ctx_data(Rng.new(20261003))
	var tb := _yin_table(c)
	var counts := {}
	var hp_counts := {}
	var n := 4000
	var sum := 0
	for i in n:
		var u = unit({"lv": 10, "str": 100, "vit": 80, "int": 45})
		var r := Growth.level_up(c, u, tb)
		var g: int = r.gains["str"]
		counts[g] = int(counts.get(g, 0)) + 1
		sum += g
		hp_counts[r.gains["hp"]] = int(hp_counts.get(r.gains["hp"], 0)) + 1
	var keys := counts.keys()
	keys.sort()
	eq(keys, [3, 4, 5, 6], "Str 增量只取 3..6")
	for k in keys:
		near(float(counts[k]) / n, 0.25, 0.03, "Str +%d 频率" % k)
	near(float(sum) / n, 4.5, 0.08, "Str 平均")
	# HP: 3 + (80-10)/35 + rand%3 = 5..7
	var hk := hp_counts.keys()
	hk.sort()
	eq(hk, [5, 6, 7], "HP 增量 5..7")


## 最大成长补丁模式下与网上数据核对 (网友数据「体魄/50+6」): 鲜于超 Vit 406 约 60 级 HP +14; Vit 350 → 13; MP Int 350 → 10
func test_max_growth_matches_patch_data():
	var c = ctx_data(null, {"growth_mode": "max"})
	var tb: Dictionary = c.levelup[4]   # 鲜于超
	var u = unit({"lv": 60, "vit": 406, "int": 350})
	var r := Growth.level_up(c, u, tb)
	eq(r.gains["hp"], 14, "Vit 406")
	eq(r.gains["mp"], 10, "Int 350")
	var v = unit({"lv": 60, "vit": 350})
	eq(Growth.level_up(c, v, tb).gains["hp"], 13, "Vit 350")


## 当前 HP/MP 不回复; 五魂点 +2; 用升级前的 lv/Vit
func test_levelup_side_effects():
	var c = ctx_data(null, {"growth_mode": "min"})
	var u = unit({"lv": 1, "hp": 10, "hp_max": 60, "mp": 3, "mp_max": 14, "vit": 24, "int": 16})
	var r := Growth.level_up(c, u, _yin_table(c))
	eq(u.lv, 2)
	eq(u.hp, 10, "当前 HP 不变")
	eq(u.hp_max, 60 + 3 + (24 - 1) / 35, "min 模式 HPmax += 3 + (Vit-lv)/35")
	eq(u.mp_max, 14 + 1, "MPmax += 1 + (16-1)/35")
	eq(u.spirit_points, 2, "五魂点 +2")
	eq(r.gains["str"], 3, "min 模式只有 base")


## 五项属性上限 500
func test_stat_cap_500():
	var c = ctx_data(null, {"growth_mode": "max"})
	var u = unit({"str": 499, "luk": 500})
	Growth.level_up(c, u, _yin_table(c))
	eq(u.get_stat("str"), 500)
	eq(u.get_stat("luk"), 500)


## 每 500 升一级, 可连升; 99 级封顶, 多余作废
func test_exp_threshold_and_cap():
	var c = ctx_data()
	var u = unit({"lv": 1})
	var res := Growth.gain_exp(c, u, 1200, _yin_table(c))
	eq(res.size(), 1, "连升合并为一批")
	eq(res[0].levels, 2, "连升 2 级")
	eq(u.lv, 3)
	eq(u.xp, 200)
	var m = unit({"lv": 98, "xp": 400})
	Growth.gain_exp(c, m, 1500, _yin_table(c))
	eq(m.lv, 99)
	eq(m.xp, 400, "1900 = 3 级 + 400: 封顶只限级数, 余数 400 保留 [原版实测 exp/C 满级 exp 不清零]")


## 习得只在升级时判定; 五魂差一点那级学不会, 营地补点后要再升一级才学会 (贴吧)
func test_skill_learning_on_level_up_only():
	var c = ctx_data(null, {"growth_mode": "min"})
	var tb := _yin_table(c)
	var u = unit({"lv": 14})
	u.spirit = [24, 25, 25, 25, 25]
	u.skills = [0]
	var r := Growth.level_up(c, u, tb)
	eq(u.lv, 15)
	check(not u.skills.has(42), "迅 24 < 25 → 無方飛劍学不会")
	var s := Growth.spirit_session(c, u)
	check(s.inc(0), "加迅")
	s.commit()
	eq(u.spirit[0], 25)
	check(not u.skills.has(42), "加点后不会立即学会")
	r = Growth.level_up(c, u, tb)
	check(u.skills.has(42) and r.learned.has(42), "下次升级补学")
	check(not r.learned.has(0), "已会的不重复")


## 技能栏 10 格满则不学
func test_skill_slots_full():
	var c = ctx_data(null, {"growth_mode": "min"})
	var u = unit({"lv": 2})
	u.skills = [90, 91, 92, 93, 94, 95, 96, 97, 98, 99]
	var r := Growth.level_up(c, u, _yin_table(c))
	check(not u.skills.has(0) and r.learned == [0], "满 10 格放不下 (技能栏不变), 但升级窗仍列出习得 [判定不看空位, 才丢弃; w2 growth 矩阵]")


## 五魂化蘊: 只拿原值比较 100 (原值 98 本次可加到 100 以上); 只能退本次加的
func test_spirit_alloc_bug():
	var c = ctx_scripted()
	var u = unit({"spirit_points": 6})
	u.spirit = [98, 10, 10, 10, 10]
	var s := Growth.spirit_session(c, u)
	for i in 5:
		check(s.inc(0), "第 %d 点" % (i + 1))
	check(not s.dec(1), "不能退未加的")
	s.commit()
	eq(u.spirit[0], 103, "原值 98 → 103 (原版漏洞)")
	eq(u.spirit_points, 1)
	var s2 := Growth.spirit_session(c, u)
	check(not s2.inc(0), "下次进入原值 >= 100 不能再加")
	check(s2.inc(1))


## 原版实测对照 (原版 官方 1.3, 固定种子 =12345; 记录 对照_经验与成长.md §A): 殷剑平 lv12 exp2499 击杀 +2 → 连升 5 级。
## 原版在升级前已消耗 6 次 rand (命中等); 逐项一致包括 HP/MP 整批用批前 Vit/Int/lv、属性封顶 500、习得按批末等级补学
func test_ref_batch_levelup_seed12345():
	var c = ctx_data(Rng.new(12345))
	for _i in 6:
		c.rng.rand()
	var u = unit({"lv": 12, "xp": 2499, "str": 497, "int": 46, "avg": 40, "vit": 46, "luk": 490, "hp_max": 76, "mp_max": 18, "spirit_points": 8})
	u.spirit = [25, 25, 25, 25, 25]
	u.skills = [5]
	var r := Growth.gain_exp(c, u, 2, _yin_table(c))
	eq(r.size(), 1)
	eq(u.lv, 17)
	eq(u.xp, 1)
	eq([u.hp_max, u.mp_max, u.spirit_points], [94, 26, 18])
	eq([u.get_stat("str"), u.get_stat("int"), u.get_stat("avg"), u.get_stat("vit"), u.get_stat("luk")], [500, 60, 58, 66, 500])
	eq(u.skills, [5, 0, 42], "气愈(lv3)、无方飞剑(lv15, 五魂25)在批末补学 (原版槽位 [0,5,42], 复刻为追加顺序)")


## 原版实测 B: lv95 exp2499 +1 → 5 级被 99 封顶为 4 级, 种子 777 (同样 6 次前置 rand)
func test_ref_levelcap_seed777():
	var c = ctx_data(Rng.new(777))
	for _i in 6:
		c.rng.rand()
	var u = unit({"lv": 95, "xp": 2499, "str": 100, "int": 165, "avg": 40, "vit": 165, "luk": 100, "hp_max": 76, "mp_max": 18, "spirit_points": 8})
	Growth.gain_exp(c, u, 1, _yin_table(c))
	eq(u.lv, 99)
	eq(u.xp, 0)
	eq([u.hp_max, u.mp_max, u.spirit_points], [102, 32, 16])
	eq([u.get_stat("str"), u.get_stat("int"), u.get_stat("avg"), u.get_stat("vit"), u.get_stat("luk")], [118, 178, 55, 181, 114])


## 原版实测 C: 99 级继续累加经验 (exp 300 + 1 = 301), 不清零
func test_ref_lv99_exp_kept():
	var c = ctx_data(Rng.new(5))
	var u = unit({"lv": 99, "xp": 300})
	eq(Growth.gain_exp(c, u, 1, _yin_table(c)).size(), 0)
	eq(u.xp, 301)


## 营地加点条件 (UI 与规则共用): 只比原值 [cmp [原值] 0x64]
func test_spirit_can_inc_original_only():
	check(Growth.spirit_can_inc(1, 99), "原值 99 可加")
	check(not Growth.spirit_can_inc(1, 100), "原值 100 不可加")
	check(not Growth.spirit_can_inc(0, 10), "没有剩余点不可加")

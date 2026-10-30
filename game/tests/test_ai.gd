# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 09 AI
const REQUIRES_TEST := {
	"test_counter_estimate_uses_start_cell": ["data"],
	"test_curse_score_rolls_hit_measured": ["data"],
	"test_heal_score": ["data"],
	"test_recall_spell_score_measured": ["data"],
	"test_line_skill_centers_are_neighbours_measured": ["data"],
	"test_item_skill_uses_item_range_measured": ["data"],
	"test_heal_spell_ally_threshold_measured": ["data"],
	"test_heal_sub_beats_weak_attack_measured": ["data"],
	"test_item_on_ally_after_move_measured": ["data"],
	"test_item_self_heal_threshold_measured": ["data"],
	"test_single_buff_not_chosen": ["data"],
	"test_spell_score_rolls_hit": ["data"],
	"test_stage1_turn2_reposition_measured": ["data"],
	"test_status_skill_scores_110_and_last_entry_kill": ["data"],
	"test_unscored_effects": ["data"]
}  # 个别方法的依赖 (同上)

const AI = preload("res://engine/rules/ai.gd")
const Movement = preload("res://engine/rules/movement.gd")
const Skills = preload("res://engine/rules/skills.gd")


func _setup(ai_type: int, enemy_pos: Vector2i, me_pos := Vector2i(2, 2), w := 15, h := 15) -> Dictionary:
	var c = ctx_data()
	add_item(c, 900, {"attack": 30, "hit": 100})
	var b = Board.new(w, h, 0)
	var me = unit({"side": 1, "ai": ai_type, "uid": 10, "move_base": 20, "move_type": 0, "weapon": 900, "str": 50})
	me.set_pos(me_pos)
	var foe = unit({"side": 0, "uid": 1, "hp": 300, "hp_max": 300, "vit": 20})
	foe.set_pos(enemy_pos)
	b.add_unit(me)
	b.add_unit(foe)
	Movement.begin_phase(c, me)
	return {"c": c, "b": b, "me": me, "foe": foe}


## 类型 0: 不移动也不攻击 (即使敌人相邻)
func test_type0_does_nothing():
	var s := _setup(0, Vector2i(3, 2))
	var pl := AI.plan(s.c, s.b, s.me)
	eq(pl.move_to, Vector2i(2, 2))
	check(pl.action.is_empty(), "不攻击")


## 类型 2 被动: 打得到就打 (移动后普攻), 打不到原地不动
func test_type2_passive():
	var s := _setup(2, Vector2i(5, 2))   # 4 格移动 + 射程 1
	var pl := AI.plan(s.c, s.b, s.me)
	eq(pl.action.get("kind"), "attack")
	eq(Board.manhattan(pl.move_to, s.foe.pos()), 1, "移到相邻格")
	var far := _setup(2, Vector2i(12, 12))
	var pl2 := AI.plan(far.c, far.b, far.me)
	eq(pl2.move_to, Vector2i(2, 2), "打不到不动")
	check(pl2.action.is_empty())


## 类型 1 主动: 打不到 → ai_target[0]==0 时走向曼哈顿最近的敌人
func test_type1_approach_nearest():
	var s := _setup(1, Vector2i(12, 2))
	var pl := AI.plan(s.c, s.b, s.me)
	check(pl.action.is_empty(), "本阶段打不到")
	eq(pl.move_to, Vector2i(6, 2), "沿直线走满 4 格 (20 点 / 5)")


## 类型 4 前往坐标: 总是先朝坐标前进, 再只从到达格出手
func test_type4_goto():
	var s := _setup(4, Vector2i(3, 2))   # 敌人相邻, 但仍先走向目标
	s.me.ai_target = [2, 12]
	var pl := AI.plan(s.c, s.b, s.me)
	eq(pl.move_to, Vector2i(2, 6), "朝 (2,12) 走 4 格")
	check(pl.action.is_empty(), "到达格打不到敌人")


## 麻痺 / 冰結 按类型 0
func test_paralyzed_no_action():
	var s := _setup(1, Vector2i(3, 2))
	s.me.status = U.ST_PARALYZE
	var pl := AI.plan(s.c, s.b, s.me)
	check(pl.action.is_empty() and pl.move_to == Vector2i(2, 2))


## 能击杀 +50: 两个可打目标时选能打死的
func test_prefers_kill():
	var s := _setup(2, Vector2i(3, 2))
	var weak = unit({"side": 0, "uid": 2, "hp": 5, "hp_max": 300, "vit": 20})
	weak.set_pos(Vector2i(2, 3))
	s.b.add_unit(weak)
	var d := AI.decide(s.c, s.b, s.me)
	eq(d.main, 150)
	check(d.target == weak, "选能击杀的")


## 单体增益 (50 分) 不会被选中; 覆盖 2 人 (100) 才会用
func test_single_buff_not_chosen():
	var c = ctx_data()
	var b = Board.new(10, 10, 0)
	var caster = unit({"side": 1, "ai": 2, "uid": 5, "mp": 200, "move_base": 0})
	caster.skills = [28]    # 血刃之咒 rt3 eff0, area 1, 攻升要求 12 格内有敌人
	caster.set_pos(Vector2i(5, 5))
	var foe = unit({"side": 0, "uid": 1})
	foe.set_pos(Vector2i(9, 9))
	b.add_unit(caster)
	b.add_unit(foe)
	Movement.begin_phase(c, caster)
	check(AI.decide(c, b, caster).is_empty(), "只能覆盖自己 1 人 → 50 分 < 100 不行动")
	var ally = unit({"side": 1, "uid": 6})
	ally.set_pos(Vector2i(5, 6))
	b.add_unit(ally)
	var d := AI.decide(c, b, caster)
	eq(d.get("main"), 100, "覆盖 2 人 → 100")
	eq(d.get("kind"), "skill")


## 治疗打分: HP <=40% +100
func test_heal_score():
	var c = ctx_data()
	var b = Board.new(10, 10, 0)
	var healer = unit({"side": 1, "ai": 2, "uid": 5, "mp": 200, "move_base": 0})
	healer.skills = [0]    # 氣愈之術
	healer.set_pos(Vector2i(5, 5))
	var hurt = unit({"side": 1, "uid": 6, "hp": 30, "hp_max": 100})
	hurt.set_pos(Vector2i(5, 7))
	b.add_unit(healer)
	b.add_unit(hurt)
	Movement.begin_phase(c, healer)
	var d := AI.decide(c, b, healer)
	eq(d.get("main"), 100)
	hurt.hp = 70
	check(AI.decide(c, b, healer).is_empty(), "70% 只有 10 分")


## 走向敌群: 取加权最大的格
func test_crowd_target():
	var c = ctx_scripted()
	var b = Board.new(20, 20, 0)
	var me = unit({"side": 1})
	me.set_pos(Vector2i(0, 0))
	b.add_unit(me)
	for p in [Vector2i(15, 15), Vector2i(15, 17), Vector2i(3, 18)]:
		var f = unit({"side": 0})
		f.set_pos(p)
		b.add_unit(f)
	var t = AI.crowd_target(c, b, me)
	# 权重 (4,4,3,2,1) 取自 对照原版 (距离 0 与 1 同为 4): (15,16) 到两人都是 1 格 = 8 分, (15,15) = 4+3 = 7
	eq(t, Vector2i(15, 16), "夹在两人中间的格最高")


## 类型 3 (字段=0): 打不到时走到目标 2 格内最近的空格 (取离目标最近、同距取剩余移动点多者); 地缚不动
func test_type3_follow_nearest_cell():
	var s := _setup(3, Vector2i(14, 14))
	s.me.ai_target = [0, 20]
	var leader = unit({"side": 1, "uid": 20})
	leader.set_pos(Vector2i(5, 2))
	s.b.add_unit(leader)
	var pl := AI.plan(s.c, s.b, s.me)
	check(pl.action.is_empty())
	eq(pl.move_to, Vector2i(4, 2), "离目标 1 格且剩余移动点最多的空格")
	s.me.status |= 0x200
	Movement.begin_phase(s.c, s.me)
	eq(AI.plan(s.c, s.b, s.me).move_to, Vector2i(2, 2), "地缚: 不动")


## 打分表: 绝技附带状态 (ot1 oe3~6) 主分 110、末条目击杀 +30; 伤害类主分只看最后一个条目
func test_status_skill_scores_110_and_last_entry_kill():
	var c = ctx_data()
	var b = Board.new(10, 10, 0)
	var me = unit({"side": 1, "uid": 10, "str": 80})
	me.set_pos(Vector2i(0, 0))
	var weak = unit({"side": 0, "uid": 1, "hp": 1, "hp_max": 100})
	weak.set_pos(Vector2i(5, 5))
	var tough = unit({"side": 0, "uid": 2, "hp": 500, "hp_max": 500})
	tough.set_pos(Vector2i(6, 5))
	for u in [me, weak, tough]:
		b.add_unit(u)
	var sk: Dictionary = c.skill(68)   # 妖光邪眼 ot1 oe5 (封)
	eq(AI._score_skill_targets(c, b, me, sk, [tough]).main, 110, "附带状态 110")
	eq(AI._score_skill_targets(c, b, me, sk, [weak]).main, 140, "击杀 +30")
	eq(AI._score_skill_targets(c, b, me, sk, [weak, tough]).main, 110, "主分只看最后一个条目 (未击杀)")
	var plain: Dictionary = c.skill(74)   # 火莲子 ot1 oe0 普通绝技
	eq(AI._score_skill_targets(c, b, me, plain, [weak]).main, 150, "普通伤害绝技击杀 150")
	eq(AI._score_skill_targets(c, b, me, plain, [tough, weak]).main, 150)
	eq(AI._score_skill_targets(c, b, me, plain, [weak, tough]).main, 100, "最后条目没死 → 100")


## 幻影祝福固定 110; 對技/對術全禦、不動之界、天瑞仙舞、遁地神行 AI 不打分
func test_unscored_effects():
	var c = ctx_data()
	var b = Board.new(10, 10, 0)
	var me = unit({"side": 1, "uid": 10})
	me.set_pos(Vector2i(2, 2))
	var a1 = unit({"side": 1, "uid": 11})
	a1.set_pos(Vector2i(2, 3))
	b.add_unit(me)
	b.add_unit(a1)
	eq(AI._score_skill_targets(c, b, me, c.skill(35), [a1]).main, 110, "无方变幻 110")
	for id in [33, 44, 56, 39, 55, 37]:
		check(AI._score_skill_targets(c, b, me, c.skill(id), [a1]).is_empty(), "技能 %d 不打分" % id)


## 执行计划: 移动 + 普攻交换
func test_execute_attack():
	var s := _setup(2, Vector2i(4, 2))
	var pl := AI.plan(s.c, s.b, s.me)
	var rec := AI.execute(s.c, s.b, s.me, pl)
	check(rec.result != null and rec.result.main != null, "执行了普攻")
	check(s.me.acted, "行动结束")
	check(s.foe.hp < 300, "造成伤害")


func _potion_board(c):
	var b = Board.new(12, 12, 0)
	var foe = unit({"side": 0, "uid": 1})
	foe.set_pos(Vector2i(11, 11))
	b.add_unit(foe)
	return b


## 实测 第3路 (第 23 关): 持金创药的被动敌人, 自身 HP ≤40% 才用 (35%/39% 用; 41%/50%/70% 不用)
func test_item_self_heal_threshold_measured():
	var c = ctx_data()
	for case in [[183, 525, true], [166, 426, true], [215, 525, false], [213, 426, false], [298, 426, false]]:
		var b = _potion_board(c)
		var me = unit({"side": 1, "ai": 2, "uid": 13, "hp": case[0], "hp_max": case[1], "vit": 0, "move_base": 20})
		me.items = [220]
		me.set_pos(Vector2i(3, 3))
		b.add_unit(me)
		Movement.begin_phase(c, me)
		var d := AI.decide(c, b, me)
		eq(not d.is_empty() and d.get("kind") == "item", case[2], "HP %d/%d" % [case[0], case[1]])


## 实测 第3路: 自身 70% 的持药者移动到相邻格, 对 29% 的友军用药; 药从【使用者】物品栏扣掉
func test_item_on_ally_after_move_measured():
	var c = ctx_data()
	var b = _potion_board(c)
	var me = unit({"side": 1, "ai": 2, "uid": 11, "hp": 298, "hp_max": 426, "move_base": 20})
	me.items = [220]
	me.set_pos(Vector2i(3, 3))
	var ally = unit({"side": 1, "uid": 53, "hp": 85, "hp_max": 290, "vit": 0})
	ally.set_pos(Vector2i(5, 4))
	b.add_unit(me)
	b.add_unit(ally)
	Movement.begin_phase(c, me)
	var pl := AI.plan(c, b, me)
	eq(pl.action.get("kind"), "item")
	eq(Board.manhattan(pl.move_to, ally.pos()) <= 1, true, "移到相邻格")
	AI.execute(c, b, me, pl)
	eq(ally.hp, 185, "金创药 100 (Vit 0)")
	eq(me.items, [], "药从使用者物品栏消失")
	eq(ally.items, [])


## 实测 第3路: 会气愈之术的敌人给 ≤40% 的友军原地施术; 49.9% / 50% 不施术
func test_heal_spell_ally_threshold_measured():
	var c = ctx_data()
	var b = _potion_board(c)
	var healer = unit({"side": 1, "ai": 2, "uid": 38, "mp": 290, "mp_max": 290, "move_base": 20})
	healer.skills = [0]
	healer.set_pos(Vector2i(3, 3))
	var a = unit({"side": 1, "uid": 21, "hp": 262, "hp_max": 525})
	a.set_pos(Vector2i(3, 6))
	b.add_unit(healer)
	b.add_unit(a)
	Movement.begin_phase(c, healer)
	check(AI.decide(c, b, healer).is_empty(), "49.9% 不施术")
	a.hp = 87
	var d := AI.decide(c, b, healer)
	eq(d.get("kind"), "skill")
	eq(d.get("cell"), Vector2i(3, 3), "治疗术不能移动后用 → 原地")


## 接近: 斜向接近时寻路回溯同值邻格要掷 rand (消耗随机数), 落点在走满移动点的最短路上
func test_approach_diagonal_consumes_rng():
	var s := _setup(1, Vector2i(12, 12))
	var dest := AI.approach(s.c, s.b, s.me, Vector2i(12, 12))
	check(s.c.rng.used > 0, "回溯掷过 rand")
	eq(Board.manhattan(dest, Vector2i(2, 2)), 4, "走满 4 格")
	check(dest.x >= 2 and dest.y >= 2, "朝目标方向")


## 输出按行优先 (决策候选格顺序)
func test_flood_row_major():
	var s := _setup(1, Vector2i(12, 12))
	var cells: Array = AI.flood(s.b, AI.cost_grid(s.c, s.b, s.me, true), Vector2i(2, 2), 10)
	var sorted := cells.duplicate()
	sorted.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	eq(cells, sorted)
	eq(cells.size(), 13, "2 格菱形")


## 根因 (原版实测 第一幕第 2 回合): 普攻估价的「预计反击伤害」射程按【决策前起点】判定,
## 不随候选格变化 —— 站在弱反击敌人 (反击 17) 旁边, 挪去打强反击敌人 (反击 25) 时,
## 后者的反击不计, 副分 13 > -1, 于是换目标换格。若按候选格算反击 (旧实现) 则原地打封寒月。
## 单位数值取自原版: 敌(四象门剑) atk39/def20/luk23, 封寒月 atk36/def24/luk20, 殷剑平 atk44/def27/luk18
## → 敌打封 dmg16/被反 17, 敌打殷 dmg13/被反 25 (估算 Luk 项 = luk/15)
func test_counter_estimate_uses_start_cell():
	var c = ctx_data(ScriptedRng.new([], 50))   # 掷骰值固定 50: 命中、不会心、不连击、不格挡, 运气项 Luk/16 (AI 估价是真掷骰, 见 ai.gd _score_attacks)
	var b = Board.new(15, 15, 0)
	var me = unit({"side": 1, "ai": 1, "uid": 2, "move_base": 20, "move_type": 0,
		"weapon": 0, "armor": 95, "str": 15, "vit": 24, "luk": 23})
	me.set_pos(Vector2i(4, 2))   # 起点: 与弱反击的封寒月相邻
	var feng = unit({"side": 0, "uid": 1, "weapon": 15, "armor": 124, "str": 16, "vit": 22, "luk": 20})
	feng.set_pos(Vector2i(3, 2))   # 相邻: 反击 17
	var yin = unit({"side": 0, "uid": 0, "weapon": 0, "armor": 99, "str": 20, "vit": 24, "luk": 18})
	yin.set_pos(Vector2i(5, 3))    # 不与起点相邻: 殷剑平的反击 25 按起点不计
	b.add_unit(yin)
	b.add_unit(feng)
	b.add_unit(me)
	Movement.begin_phase(c, me)
	var pl := AI.plan(c, b, me)
	eq(pl.move_to, Vector2i(5, 2), "挪去殷剑平旁 (行优先第一个相邻格)")
	check(pl.action.target == yin, "改打殷剑平 (强反击不计入估价)")
	var d := AI.decide(c, b, me)
	eq(d.main, 100)
	eq(d.sub, 13, "39-27+luk23/15, 反击 25 不计")


## 原版实测全局面: 第一幕我方原地待機, 敌方第 2 轮重新评分换位换目标:
## #2 (上轮已贴封寒月) → (16,21) 改打殷剑平, #3 补进 (15,20), #4 → (14,21), #5 → (18,22) (够不着, 只移动)。
## 局面 = 记录的第 2 回合开局 (单位位置/HP) + 原版属性值 (见上表); 地形 = 第 1 关地图
## y12~26 行 (content/tdj/stages/01/map.json, 7=墙不可过 4=障碍消耗 10 0/1=地面 5/6)。
func test_stage1_turn2_reposition_measured():
	var c = ctx_data()
	var b := Board.new(33, 29, 7)   # 先填满墙, 再铺第 1 关实测地块
	var rows := [
		"777777777777777777777777777777777",
		"777700000777700000000777700777777",
		"777770000000000000000000000777777",
		"777777000000000000000000000777777",
		"777777700000000044400044400777777",
		"777777770177710177710177710777777",
		"777777770177710177710177710777777",
		"777777770177710177710177710777777",
		"777777770011100011100011100777777",
		"777777770000000000000000000777777",
		"777777770000000000044400000777777",
		"777770000000777000077700000777777",
		"770770000001777100177710000777777",
		"700770000001777100177710000777777",
		"000770000000111000011100000777777",
	]
	for yy in rows.size():
		var row: String = rows[yy]
		for xx in row.length():
			b.set_terrain(Vector2i(xx, 12 + yy), row[xx].hex_to_int())
	# 我方: 殷剑平 (16,22) hp60, 封寒月 (15,21) hp45
	var yin = unit({"side": 0, "uid": 0, "hp": 60, "hp_max": 60, "move_type": 0,
		"weapon": 0, "armor": 99, "str": 20, "vit": 24, "luk": 18, "avg": 22, "move_base": 23})
	yin.set_pos(Vector2i(16, 22))
	var feng = unit({"side": 0, "uid": 1, "hp": 45, "hp_max": 45, "move_type": 7,
		"weapon": 15, "armor": 124, "str": 16, "vit": 22, "luk": 20, "avg": 24, "move_base": 21})
	feng.set_pos(Vector2i(15, 21))
	b.add_unit(yin)
	b.add_unit(feng)
	# 敌方四象门剑: str15 vit24 luk23 avg26, 长剑+布衣, 移动 25+1; 位置/HP = 第 1 轮终了
	var foes := []
	for e in [[2, Vector2i(15, 20), 29], [3, Vector2i(14, 17), 47], [4, Vector2i(15, 17), 47], [5, Vector2i(19, 18), 47]]:
		var u = unit({"side": 1, "ai": 1, "uid": e[0], "hp": e[2], "hp_max": 47, "move_type": 0,
			"weapon": 0, "armor": 95, "str": 15, "vit": 24, "luk": 23, "avg": 26, "move_base": 25})
		u.set_pos(e[1])
		b.add_unit(u)
		foes.append(u)
		Movement.begin_phase(c, u)
	# 按 MAN 下标行动, 只落实移动 (普攻结算不影响后续落点: 无击杀)
	var plans := {}
	for e in foes:
		var pl := AI.plan(c, b, e)
		plans[e.uid] = pl
		Movement.move_to(c, b, e, pl.move_to)
	eq(plans[2].move_to, Vector2i(16, 21), "#2 换位")
	eq(plans[2].action.get("kind"), "attack")
	check(plans[2].action.target == yin, "#2 改打殷剑平")
	eq(plans[3].move_to, Vector2i(15, 20), "#3 补进 (15,20)")
	eq(plans[3].action.get("target"), feng, "#3 打封寒月")
	eq(plans[4].move_to, Vector2i(14, 21), "#4 到 (14,21)")
	eq(plans[4].action.get("target"), feng, "#4 打封寒月")
	eq(plans[5].move_to, Vector2i(18, 22), "#5 到 (18,22)")
	check(plans[5].action.is_empty(), "#5 够不着任何人, 只移动")


## 图外的单位 (第 10 关我方从图外走入): 代价表不能把 y*w+x 写到下一行的格子上, 起点在图外时洪泛/寻路无解而不越界
func test_offmap_units_do_not_corrupt_grid():
	var s := _setup(1, Vector2i(15, 2), Vector2i(2, 2))   # 敌人 x=15 在 15 宽的图外一格, 按旧写法会落到 (0,3)
	var g := AI.cost_grid(s.c, s.b, s.me, true)
	var base := AI.cost_grid(s.c, s.b, s.me, false)
	var diff := 0
	for i in g.size():
		if (g[i] & 0x7FFF) != (base[i] & 0x7FFF):
			diff += 1
	eq(diff, 0, "图外单位没有改写任何格子的代价")
	eq(AI.flood(s.b, g, Vector2i(-1, 3), 20), [], "起点在图外: 无可达格")
	eq(AI.path_cells(s.c, s.b, g, Vector2i(-1, 3), Vector2i(2, 2), 20), [Vector2i(2, 2)], "起点在图外: 只返回终点")


## 普攻估价是真掷骰 ( 调): 同一局面, 掷骰结果不同, 副分不同
func test_attack_score_rolls_dice():
	var s := _setup(2, Vector2i(3, 2))
	add_item(s.c, 901, {"attack": 30, "hit": 10})
	s.me.weapon = 901   # 命中率低, 掷骰 99 必不中
	s.c.rng = ScriptedRng.new([], 99)   # 掷骰全是 99 >= 命中率 → 估价每一击都未命中
	var d_miss := AI.decide(s.c, s.b, s.me)
	check(d_miss.sub <= 0, "掷骰未命中: 预计伤害 0, 副分不为正 (实际 %d)" % d_miss.sub)
	s.me.weapon = 900
	s.c.rng = ScriptedRng.new([], 50)
	var d_hit := AI.decide(s.c, s.b, s.me)
	check(d_hit.sub > 0, "掷骰命中: 副分为正 (实际 %d)" % d_hit.sub)


## 咒术估价先掷命中, 威力随机项固定: 掷骰全 99 → 未命中 → 副分 0; 全 0 → 命中
func test_spell_score_rolls_hit():
	var s := _setup(2, Vector2i(3, 2))
	s.me.skills = [6]   # 离火神诀
	s.me.mp = 100
	s.me.mp_max = 100
	s.me.stats["int"] = 60
	s.c.rng = ScriptedRng.new([], 99)
	var miss := AI.decide(s.c, s.b, s.me)
	var any_spell_miss := false
	for cand in [miss]:
		if cand.get("kind") == "skill" and int(cand.sub) == 0:
			any_spell_miss = true
	check(miss.is_empty() or miss.get("kind") != "skill" or any_spell_miss, "咒术掷骰未命中时副分为 0")
	s.c.rng = ScriptedRng.new([], 0)
	var hit := AI.decide(s.c, s.b, s.me)
	check(hit.get("kind") == "skill" and int(hit.sub) > 0, "咒术掷骰命中: 副分为正 %s" % str(hit.get("sub")))


## 类型 3 跟随单位 (字段==0): 领队 2 格内「洪泛点数 ×16」, 不受本阶段移动力限制 [原版第 1 关实测: 领队在 7 格外, 跟随者仍朝领队走满 4 格,
## 而不是走向敌群]。旧实现只在本阶段可达格里找领队 2 格内的空格, 找不到就走向敌群
func test_type3_follow_goal_ignores_move_range_measured():
	var s := _setup(3, Vector2i(2, 14))   # 敌人在正南, 领队在正东远处
	var leader = unit({"side": 1, "ai": 2, "uid": 20, "move_base": 20, "move_type": 0, "weapon": 900})
	leader.set_pos(Vector2i(12, 2))
	s.b.add_unit(leader)
	s.me.ai_target = [0, 20]
	var pl := AI.plan(s.c, s.b, s.me)
	eq(pl.move_to, Vector2i(6, 2), "朝领队走满 4 格, 不是走向南边的敌人")
	var g = AI.near_leader_cell(s.c, s.b, s.me, leader)
	check(g != null and Board.manhattan(g, leader.pos()) <= 2, "目标格在领队 2 格内: %s" % str(g))


## 普攻估价的目标顺序 = 射程格行优先 (y 小优先): 第一次掷骰落到最靠上的目标上 [逐射程格取单位; 对照第 1 关第 2 阶段]
func test_attack_score_target_order_row_major_measured():
	var s := _setup(2, Vector2i(2, 3))      # uid 1 在 (2,3) (单位表里排第一, 行优先排第二)
	var foe2 = unit({"side": 0, "uid": 2, "hp": 300, "hp_max": 300, "vit": 20})
	foe2.set_pos(Vector2i(3, 2))            # 行优先排第一
	s.b.add_unit(foe2)
	s.me.moved = true                       # 只有原地一个候选格, 第一次掷骰一定落在原地的第一个目标上
	s.c.rng = ScriptedRng.new([0], 99)      # 第一次掷骰 0 (命中), 其余 99 (不命中/不暴击)
	var d := AI.decide(s.c, s.b, s.me)
	eq(d.get("kind"), "attack")
	eq(d.target.uid, 2, "第一次掷骰给了行优先靠前的 (3,2)")


## 治疗的副分 = 档内目标的实际回复量之和 (记录 字段, 封顶到缺口; 累加), 所以残血友军 (100 分, 副分=回复量)
## 打得过「能打到敌人」(100 分, 副分=伤害−反击) [原版第 1 关实测: 同一分数下敌方术士选了治疗而不是普攻]
func test_heal_sub_beats_weak_attack_measured():
	var c = ctx_data()
	add_item(c, 900, {"attack": 5, "hit": 100})
	var b = Board.new(10, 10, 0)
	var me = unit({"side": 1, "ai": 2, "uid": 5, "mp": 200, "move_base": 0, "weapon": 900, "str": 10, "int": 40})
	me.skills = [0]
	me.set_pos(Vector2i(5, 5))
	var foe = unit({"side": 0, "uid": 1, "hp": 300, "hp_max": 300, "vit": 20})
	foe.set_pos(Vector2i(5, 6))
	var hurt = unit({"side": 1, "uid": 6, "hp": 30, "hp_max": 100})
	hurt.set_pos(Vector2i(4, 5))
	b.add_unit(me)
	b.add_unit(foe)
	b.add_unit(hurt)
	Movement.begin_phase(c, me)
	c.rng = ScriptedRng.new([], 0)   # 估价掷骰全中
	var d := AI.decide(c, b, me)
	eq(d.get("kind"), "skill", "残血友军的治疗压过弱普攻")
	check(int(d.get("sub", 0)) > 0, "副分是回复量, 实际 %s" % str(d.get("sub")))


## 诅咒估价对每个目标掷一次命中 (耗随机数), 但【不看命中结果】: 每个缺该状态的目标照样 +50 (case 0xb)
## [随机数消耗与原版一致 原版 直接调 逐例对照 1026 例: 封魔神道/夺魄鬼咒/鬼缚之阵, 含目标带幻影/全禦, 位置、落点、随机数全等; 旧版「未中不计分」比原版弱]
func test_curse_score_rolls_hit_measured():
	var c = ctx_data()
	var b = Board.new(12, 12, 0)
	var me = unit({"side": 1, "ai": 2, "uid": 5, "mp": 60, "mp_max": 60, "move_base": 0, "int": 40, "luk": 20})
	me.skills = [32]   # 封魔神道 (诅咒, 范围 2)
	me.set_pos(Vector2i(5, 5))
	for i in 2:
		var f = unit({"side": 0, "uid": 1 + i, "luk": 10})
		f.set_pos(Vector2i(5, 8 + i))
		b.add_unit(f)
	b.add_unit(me)
	Movement.begin_phase(c, me)
	c.rng = ScriptedRng.new([], 99)   # 每次掷骰都 99: 按命中率全未中
	var d_miss := AI.decide(c, b, me)
	eq(d_miss.get("kind"), "skill", "全未中也照样: 两人各 50 = 100 分, 放")
	eq(d_miss.get("main"), 100)
	check(c.rng.used > 0, "估价仍然耗随机数 (每个目标掷一次)")
	var used_miss: int = c.rng.used
	c.rng = ScriptedRng.new([], 0)   # 全命中: 结果与随机数消耗都和未中时一样
	var d_hit := AI.decide(c, b, me)
	eq(d_hit.get("kind"), "skill")
	eq(d_hit.get("main"), 100)
	eq(d_hit.get("center"), d_miss.get("center"), "命中与否不改变落点")
	eq(c.rng.used, used_miss, "命中与否不改变随机数消耗")
	# 目标已带该状态 (封咒 0x400) 的不计分, 两人都带则不放
	for f in b.units:
		if f.side == 0:
			f.status |= 0x400
			f.status_r[0x400] = 30000
			f.status_k[0x400] = 1
	c.rng = ScriptedRng.new([], 0)
	check(AI.decide(c, b, me).is_empty(), "目标已封咒: 不计分")
	# 参数 ai_curse_needs_hit = true 是旧写法 (未中不计分, 比原版弱)
	for f in b.units:
		if f.side == 0:
			f.status = 0
	c.params.ai_curse_needs_hit = true
	c.rng = ScriptedRng.new([], 99)
	check(AI.decide(c, b, me).is_empty(), "旧写法: 全未中 0 分")


## 返召之咒 (rt5 eff13, 41): 范围内每个本阶段已行动的友军 +40 累加不封顶, 3 个 = 120 才会施放 (2 个 = 80 不够)
## [原版 实测: 第 2 阶段 3 个友军已行动时 MP -300; 轮到过但没动的 AI 单位也算已行动, 尚未轮到的不算]
func test_recall_spell_score_measured():
	var c = ctx_data()
	var b = Board.new(12, 12, 0)
	var caster = unit({"side": 1, "ai": 1, "uid": 5, "mp": 400, "mp_max": 400, "move_base": 0})
	caster.skills = [41]
	caster.set_pos(Vector2i(5, 5))
	b.add_unit(caster)
	var allies := []
	for p in [Vector2i(5, 6), Vector2i(4, 6), Vector2i(6, 6)]:
		var a = unit({"side": 1, "uid": 6 + allies.size()})
		a.set_pos(p)
		b.add_unit(a)
		allies.append(a)
	Movement.begin_phase(c, caster)
	for a in allies:
		Movement.begin_phase(c, a)
	check(AI.decide(c, b, caster).is_empty(), "友军都还没行动: 0 分")
	allies[0].acted = true
	allies[1].acted = true
	check(AI.decide(c, b, caster).is_empty(), "2 个已行动 = 80 < 100")
	allies[2].ai_passed = true   # 轮到过但没动 (待命) 也算
	var d := AI.decide(c, b, caster)
	eq(d.get("main"), 120, "3 个已行动 = 120")
	eq(d.get("skill"), 41)
	c.params.ai_recall_count_idle = false
	check(AI.decide(c, b, caster).is_empty(), "不算待命单位时只有 2 个")


## 道具发动技能: 落点范围与效果范围都用道具自己的射程记录 (轰雷符 item -1~3 / 范围 3, 技能 九天神雷 0~3 / 范围 2),
## [原版 实测: 敌方持符的 4 种道具 2 阶段位置/随机数逐阶段全等, 用技能范围则落点选错]
func test_item_skill_uses_item_range_measured():
	var c = ctx_data()
	var Items = preload("res://engine/rules/items.gd")
	var sk: Dictionary = Items.skill_of(c, 240)
	eq(int(sk.range.area), 3, "轰雷符 效果范围取道具的 3")
	eq(int(sk.range.max), 3)
	eq(int(sk.range.min), -1)


## 直线射程技能 (分天斩 53 等) 的落点候选 = 本格四邻 N/E/S/W, 不是射程内每一格;
## 菱形射程仍取射程格表。[原版 实测: 分天斩单位 4 个候选格评估后总取数 8/24 次, 与复刻逐位一致; 修前 20/44]
func test_line_skill_centers_are_neighbours_measured():
	var c = ctx_data()
	var line: Dictionary = c.skill(53)
	var cs: Array = AI._skill_centers(line, Vector2i(5, 5))
	eq(cs, [Vector2i(5, 4), Vector2i(6, 5), Vector2i(5, 6), Vector2i(4, 5)], "北东南西")
	var dia: Dictionary = c.skill(42)
	eq(AI._skill_centers(dia, Vector2i(5, 5)).size(), Skills.cast_cells(dia, Vector2i(5, 5)).size(), "菱形射程取射程格")

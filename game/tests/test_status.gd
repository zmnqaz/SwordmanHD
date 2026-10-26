# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 05 状态异常

const Status = preload("res://engine/rules/status.gd")
const Damage = preload("res://engine/rules/damage.gd")


## 中毒: 本阵营阶段开始扣 HPmax/5, 可致死; 到期那一次也扣
func test_poison_fifth_lethal():
	var c = ctx_scripted()
	var u = unit({"hp": 100, "hp_max": 100})
	Status.apply(u, U.ST_POISON, 300, 100)
	var hp_seq := []
	for i in 6:
		var r := Status.phase_tick(c, u)
		hp_seq.append(u.hp)
		if r.died:
			break
	eq(hp_seq, [80, 60, 40, 40, 40, 40], "每次 -20, 第 3 次也扣, 之后解除不再扣")
	check(not u.has_status(U.ST_POISON), "到期解除")
	var v = unit({"hp": 39, "hp_max": 100})
	Status.apply(v, U.ST_POISON, 500, 100)
	Status.phase_tick(c, v)
	var r2 := Status.phase_tick(c, v)
	check(r2.died and not v.alive, "中毒可致死")
	eq(v.hp, 0)


## R < K 不施加; 同种 = 覆盖刷新; 持续 ⌈R/K⌉ 次
func test_apply_refresh_duration():
	var u = unit({})
	check(not Status.apply(u, U.ST_ATK_UP, 50, 60), "R<K 不施加")
	check(Status.apply(u, U.ST_ATK_UP, 205, 70), "施加")
	eq(Status.duration_ticks(205, 70), 3)
	check(Status.apply(u, U.ST_ATK_UP, 100, 100), "重复施加不拒绝")
	eq(u.status_r[U.ST_ATK_UP], 100, "覆盖, 不叠加")
	var c = ctx_scripted()
	Status.phase_tick(c, u)
	check(not u.has_status(U.ST_ATK_UP), "100/100 → 1 次结算后解除")


## R=K=0 (日輪神劍) 可施加, 下次本阵营阶段开始即移除
func test_zero_zero_status():
	var c = ctx_scripted()
	var u = unit({})
	check(Status.apply(u, U.ST_GUARD_SKILL, 0, 0), "0<0 不成立 → 施加")
	var r := Status.phase_tick(c, u)
	eq(r.expired, [U.ST_GUARD_SKILL])


## 例: 無方變幻 200/100 → 2 次; 不動之界 300/100 → 3 次
func test_examples_duration():
	eq(Status.duration_ticks(200, 100), 2)
	eq(Status.duration_ticks(300, 100), 3)


## 祝福 K = rate10 - 2×(目标Int/(5+rand%6)); 诅咒 K = rate10 + …; AI 2×(Int/7)
func test_bless_curse_k():
	var t = unit({"int": 100})
	eq(Status.bless_k(ctx_scripted([0]), t, 100), 100 - 2 * 20, "Int100/5")
	eq(Status.bless_k(ctx_scripted([5]), t, 100), 100 - 2 * 10, "Int100/10")
	eq(Status.curse_k(ctx_scripted([0]), t, 100), 140)
	eq(Status.bless_k(ctx_scripted(), t, 100, true), 100 - 28, "AI 2×(100/7)")
	# 规格例: 血刃之咒 power 100, 施术者 Int 200 → P≈205; 目标 Int 100 → K 60~80 → 约 3 次
	var k_lo: int = Status.bless_k(ctx_scripted([0]), t, 100)
	var k_hi: int = Status.bless_k(ctx_scripted([5]), t, 100)
	check(k_lo == 60 and k_hi == 80, "K 60~80")
	eq(Status.duration_ticks(205, 70), 3)


## 解除掩码: 驱散不清全禦/幻影; 靈淨只解毒麻; 天護靈燁不解冰結
func test_cleanse_masks():
	var u = unit({})
	for b in [U.ST_ATK_UP, U.ST_DEF_UP, U.ST_BERSERK, U.ST_GUARD_SKILL, U.ST_PHANTOM, U.ST_POISON, U.ST_PARALYZE, U.ST_SEAL, U.ST_BIND, U.ST_FREEZE]:
		Status.apply(u, b, 100, 1)
	Status.remove(u, Status.DISPEL_MASK)
	check(not u.has_status(U.ST_ATK_UP) and not u.has_status(U.ST_BERSERK), "驱散增益")
	check(u.has_status(U.ST_GUARD_SKILL) and u.has_status(U.ST_PHANTOM), "驱散不清全禦、幻影")
	Status.remove(u, Status.PURIFY_MASK)
	check(not u.has_status(U.ST_POISON) and not u.has_status(U.ST_PARALYZE), "靈淨解毒麻")
	check(u.has_status(U.ST_SEAL), "靈淨不解封")
	Status.remove(u, Status.HOLY_CLEANSE_MASK)
	check(not u.has_status(U.ST_SEAL) and not u.has_status(U.ST_BIND), "天護解封、地缚")
	check(u.has_status(U.ST_FREEZE), "天護不解冰結")
	Damage.apply_damage(u, 1)
	check(not u.has_status(U.ST_FREEZE), "受伤解冰結")


## 友军 NPC 一轮结算两次
func test_ally_npc_double_tick():
	var c = ctx_scripted()
	var npc = unit({"side": 0, "npc_ally": true, "uid": 3})
	var pc = unit({"side": 0, "uid": 1})
	var en = unit({"side": 1, "uid": 2})
	var units := [npc, pc, en]
	eq(Status.units_to_tick(c, units, "ally"), [npc])
	eq(Status.units_to_tick(c, units, "player"), [pc, npc], "我方阶段含 NPC, 按下标")
	eq(Status.units_to_tick(c, units, "enemy"), [en])
	var c2 = ctx_scripted([], {"ally_npc_double_tick": false})
	eq(Status.units_to_tick(c2, units, "player"), [pc])


## 麻痺/冰結 不能行动
func test_can_act():
	var u = unit({})
	check(Status.can_act(u))
	u.status = U.ST_PARALYZE
	check(not Status.can_act(u), "麻痺")
	u.status = U.ST_FREEZE
	check(not Status.can_act(u), "冰結")
	u.status = U.ST_SEAL | U.ST_POISON
	check(Status.can_act(u), "封咒/中毒仍可行动")


## w1 实机 (真实战斗流程逐阶段记录): 武器附加反击施加的毒 R=K=0, 目标阵营下一阶段开始扣一次 HPmax/5 (3000→2400) 后立即解除;
## 麻痺/封咒同样在下一阶段开始解除; 主攻路径永不施加
func test_counter_applied_poison_zero_rk_expires_next_phase():
	var c = ctx_scripted()
	var u = unit({"hp": 3000, "hp_max": 3000})
	Status.apply(u, U.ST_POISON, 0, 0)
	var r := Status.phase_tick(c, u)
	eq(u.hp, 2400, "到期那次也扣 HPmax/5")
	check(not u.has_status(U.ST_POISON) and r.expired == [U.ST_POISON], "同一次结算内解除")
	var p = unit({})
	Status.apply(p, U.ST_PARALYZE, 0, 0)
	Status.apply(p, U.ST_SEAL, 0, 0)
	Status.phase_tick(c, p)
	eq(p.status & (U.ST_PARALYZE | U.ST_SEAL), 0, "麻/封 R=K=0 下一阶段开始解除")


## 实机时间线 (仓库外的开发脚本): 冰結 R/K 逐阶段递减, 按「目标所属阵营的阶段开始」结算, 与施放方无关
## - 敌方阶段冻我方 (R=1,K=1): 下一个我方阶段开始结算即清位, 之后可行动; - 注入 R=3,K=1: 连续 3 次本阵营阶段开始 3→2→1→0 解除 (R=2: 2 次)
## - 我方阶段给敌方 R=1,K=1: 当回合敌方阶段开始即清; R=3,K=1: 3 次敌方阶段开始后解除
func test_d305_freeze_expiry_by_target_phase_measured():
	var c = ctx_scripted()
	var mine = unit({"side": 0, "uid": 0})
	var foe = unit({"side": 1, "uid": 2})
	Status.apply(mine, U.ST_FREEZE, 1, 1)   # 敌方阶段施加
	check(not Status.can_act(mine), "被冻不能行动")
	for u in Status.units_to_tick(c, [mine, foe], "enemy"):
		Status.phase_tick(c, u)
	check(mine.has_status(U.ST_FREEZE), "敌方阶段开始结算不动我方单位")
	for u in Status.units_to_tick(c, [mine, foe], "player"):
		Status.phase_tick(c, u)
	check(not mine.has_status(U.ST_FREEZE) and Status.can_act(mine), "下一个我方阶段开始即清位, 之后可行动")
	var a = unit({"side": 0, "uid": 0})
	var b = unit({"side": 1, "uid": 3})
	Status.apply(a, U.ST_FREEZE, 3, 1)
	Status.apply(b, U.ST_FREEZE, 3, 1)
	var left_a := []
	var left_b := []
	for i in 4:
		for u in Status.units_to_tick(c, [a, b], "player"):
			Status.phase_tick(c, u)
		left_a.append(int(a.status_r.get(U.ST_FREEZE, -9)))
		for u in Status.units_to_tick(c, [a, b], "enemy"):
			Status.phase_tick(c, u)
		left_b.append(int(b.status_r.get(U.ST_FREEZE, -9)))
	eq(left_a, [2, 1, -9, -9], "我方 R=3/K=1: 3 次我方阶段开始后解除 (原版 3→2→1→0)")
	eq(left_b, [2, 1, -9, -9], "敌方同规则 (对称)")

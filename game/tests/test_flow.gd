# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 10 回合流程与胜负 (实测 T13 T14 T16 T26 T36 第4路.md)
const REQUIRES_TEST := {
	"test_annihilation_exempt": ["data"]
}  # 个别方法的依赖 (同上)

const Flow = preload("res://engine/rules/flow.gd")
const Status = preload("res://engine/rules/status.gd")


func _enemy(uid: int, alive := true, kill_event := -1):
	var e = unit({"side": 1, "uid": uid, "kill_event": kill_event})
	e.alive = alive
	return e


## 先判胜利再判失败: 主角与最后一个敌人同批死亡时算胜
func test_judge_win_before_lose():
	var hero = unit({"side": 0, "uid": 0})
	hero.alive = false
	var units := [hero, _enemy(9, false)]
	var win := [{"type": 1, "id": -1, "event": 3}, {"type": 0}]
	var lose := [{"type": 2, "id": 0, "event": 4}, {"type": 0}]
	var r := Flow.judge(units, win, lose)
	eq(r.result, "win")
	eq(r.event, 3)
	units[1].alive = true
	eq(Flow.judge(units, win, lose).result, "lose")
	hero.alive = true
	eq(Flow.judge(units, win, lose).result, "")


## 全灭: 不计 字段 (齐祀 uid85 = units.json defence_type 1), 跳过下标 == id 的单位
func test_annihilation_exempt():
	var c = ctx_data()
	var qisi = Stats.make_enemy(c.units[85], 1)
	qisi.uid = 30
	check(qisi.annihilation_exempt, "齐祀 字段")
	var other = _enemy(31)
	eq(Flow.cond_met([qisi], {"type": 1, "id": -1}), true, "只剩齐祀 = 全灭")
	eq(Flow.cond_met([qisi, other], {"type": 1, "id": -1}), false)
	eq(Flow.cond_met([qisi, other], {"type": 1, "id": 31}), true, "跳过 id 本人")


## 中毒致死且 kill_event = -1: 不判定; 之后任何行动结算 (连治疗术) 才判; 装备/待機/回合推进不判
func test_t13_poison_death_no_judge():
	var c = ctx_scripted()
	var e = _enemy(9)
	e.hp = 1
	Status.apply(e, U.ST_POISON, 100, 1)
	var r := Status.phase_tick(c, e)
	check(r.died, "毒死")
	check(not Flow.should_judge(c, Flow.TRIGGER_STATUS_DEATH, [e]), "kill_event -1 不判")
	check(Flow.should_judge(c, Flow.TRIGGER_STATUS_DEATH, [_enemy(10, false, 2)]), "kill_event ≠ -1 判")
	check(not Flow.should_judge(c, Flow.TRIGGER_OTHER), "装备/丢弃/待機/回合推进")
	check(not Flow.should_judge(c, Flow.TRIGGER_TEVT))
	check(not Flow.should_judge(c, Flow.TRIGGER_MAP_EVENT))
	check(Flow.should_judge(c, Flow.TRIGGER_ACTION), "治疗术结算后判定 → 过关")
	eq(Flow.judge([e], [{"type": 1, "id": -1}], []).result, "win")


## 友军 NPC 一轮结算两次: HPmax 464 中毒 → 一轮 -92 ×2; 玩家单位 478 → -95 一次
func test_t14_npc_poison_twice_measured():
	var c = ctx_scripted()
	var npc = unit({"side": 0, "npc_ally": true, "uid": 8, "hp": 449, "hp_max": 464})
	var pc = unit({"side": 0, "uid": 7, "hp": 478, "hp_max": 478})
	Status.apply(npc, U.ST_POISON, 100, 1)
	Status.apply(pc, U.ST_POISON, 100, 1)
	for phase in ["ally", "player"]:
		for u in Status.units_to_tick(c, [npc, pc], phase):
			Status.phase_tick(c, u)
	eq(npc.hp, 449 - 92 - 92, "357 → 265")
	eq(pc.hp, 383)


## 同阵营按 MAN 下标升序 (与登记顺序、距离无关)
func test_t16_order_by_uid():
	var c = ctx_scripted()
	var us := []
	for uid in [54, 9, 12, 30, 10]:
		us.append(_enemy(uid))
	var order := []
	for u in Status.units_to_tick(c, us, "enemy"):
		order.append(u.uid)
	eq(order, [9, 10, 12, 30, 54])


## TEVT 只执行第一条匹配; 第 1 回合也检查; turn=-1 排在前面会挡住后面的 turn=N
func test_tevt_first_match():
	var recs := [{"turn": 1, "type": 0, "event": 1}, {"turn": -1, "type": 2, "event": 5}, {"turn": 3, "type": 2, "event": 6}]
	eq(Flow.tevt_match(recs, 0, 1), 0, "开场 turn=1 type=0")
	eq(Flow.tevt_match(recs, 2, 1), 1, "第 1 回合 type 2 也检查")
	eq(Flow.tevt_match(recs, 2, 3), 1, "turn=-1 挡住 turn=3")
	eq(Flow.tevt_match(recs, 1, 1), -1)


## 100 回合判负
func test_turn_limit():
	var c = ctx_scripted()
	eq(Flow.end_turn(c, 98), {"turn": 99, "game_over": false})
	eq(Flow.end_turn(c, 99), {"turn": 100, "game_over": true})


## 同批 kill_event 去重
func test_kill_event_dedup():
	eq(Flow.kill_events([_enemy(1, false, 2), _enemy(2, false, -1), _enemy(3, false, 2), _enemy(4, false, 5)]), [2, 5])


## 战阵存档: 我方阶段开始、无人行动才可存; 有人待機后不可
func test_t36_save_only_before_action():
	var a = unit({"side": 0})
	var b = unit({"side": 0})
	var npc = unit({"side": 0, "npc_ally": true, "acted": true})
	check(Flow.can_save_battle([a, b, npc], true), "回合开始可存 (友军 NPC 已行动不算)")
	a.acted = true
	check(not Flow.can_save_battle([a, b, npc], true), "殷剑平待機后不可存")
	check(not Flow.can_save_battle([b], false), "非我方阶段")


## judge 的 all 参数: type 1 (全灭) 只看在场单位, type 2 (指定单位离场) 看全部单位 (未现身的预置单位不算离场)
func test_judge_present_vs_all():
	var ghost = unit({"side": 1, "uid": 7})   # 活着但未现身: 不在 present 里
	var win := [{"type": 1, "id": -1, "event": 1}]
	eq(Flow.judge([], win, [], [ghost]).result, "win", "全灭只数在场单位")
	var lose := [{"type": 2, "id": 7, "event": 2}]
	eq(Flow.judge([], [], lose, [ghost]).result, "", "指定单位按全部单位判: 活着就没离场")
	ghost.alive = false
	eq(Flow.judge([], [], lose, [ghost]).result, "lose")
	eq(Flow.judge([], [{"type": 0}, {"type": 1, "id": -1, "event": 1}], []).result, "", "type 0 表结束")

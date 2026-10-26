# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 02 移动与地形

const Movement = preload("res://engine/rules/movement.gd")
const Attack = preload("res://engine/rules/attack.gd")


func _plain(w: int = 41, h: int = 41, cls: int = 0):
	return Board.new(w, h, cls)


## 在开阔单一地形上, 最远可达的曼哈顿距离 (= 格数)
func _max_reach(c, b, u) -> int:
	var best := 0
	for cell in Movement.reachable(c, b, u):
		best = maxi(best, Board.manhattan(cell, u.pos()))
	return best


func _walker(move_type: int, mov: int, pos := Vector2i(20, 20)):
	var u = unit({"move_base": mov, "avg": 0, "move_type": move_type})
	u.set_pos(pos)
	return u


## 网友数据 第 5 楼: 殷剑平 (步行0, 平地类别 0 消耗 5) 移动力 M → 平地格数 / 蓄力后格数
## 实测: 30→6/12, 35~37→7/14, 38→7/15, 43→8/17, 47→9, 52→10/20, 57→11/22, 64→12/25, 70→14/28
## (60→12/25 一组与公式 24 不符, 规格判为记录误差, 不纳入)
func test_tieba_move_cells_ten_groups():
	var data := [[30, 6, 12], [35, 7, 14], [37, 7, 14], [38, 7, 15], [43, 8, 17], [47, 9, -1],
		[52, 10, 20], [57, 11, 22], [64, 12, 25], [70, 14, 28]]
	for row in data:
		var c = ctx_scripted()
		var b = _plain()
		var u = _walker(0, row[0])
		b.add_unit(u)
		Movement.begin_phase(c, u)
		eq(_max_reach(c, b, u), row[1], "M=%d 平地格数" % row[0])
		if row[2] < 0:
			continue
		check(Movement.burst(c, u), "M=%d 可爆發" % row[0])
		Movement.begin_phase(c, u)
		eq(u.move_cap, row[0] * 2, "爆發后移动点 = 2M")
		eq(_max_reach(c, b, u), row[2], "M=%d 蓄力格数" % row[0])


## 网友数据 1 楼: 第 2 幕平地 殷 24→4、封寒月(步行7, 消耗 6) 22→3;
## 第 3 幕类别 1: 殷 25→4、封 24→3、上官远(步行3, 消耗 7) 28→4、44→6
func test_tieba_other_samples():
	var cases := [[0, 0, 24, 4], [7, 0, 22, 3], [0, 1, 25, 4], [7, 1, 24, 3], [3, 1, 28, 4], [3, 1, 44, 6]]
	for cs in cases:
		var c = ctx_scripted()
		var b = _plain(41, 41, cs[1])
		var u = _walker(cs[0], cs[2])
		b.add_unit(u)
		Movement.begin_phase(c, u)
		eq(_max_reach(c, b, u), cs[3], "类型%d 类别%d M=%d" % [cs[0], cs[1], cs[2]])


## MOV = move + Avg/25; 速敏 ×1.5 截断 (真胤 Avg 500: 45 → 67, 网友数据)
func test_move_points_and_haste():
	var c = ctx_scripted()
	var u = unit({"move_base": 25, "avg": 500})
	eq(Movement.move_cap(c, u), 45, "25 + 500/25")
	u.status |= U.ST_HASTE
	eq(Movement.move_cap(c, u), 67, "int(45×1.5)")
	u.status = U.ST_BIND
	eq(Movement.move_cap(c, u), 1, "地縛 → 1")


## 地縛 = 1 点, 最小格消耗 >=5 → 不能动
func test_bind_cannot_move():
	var c = ctx_scripted()
	var b = _plain()
	var u = _walker(6, 40)
	u.status = U.ST_BIND
	b.add_unit(u)
	Movement.begin_phase(c, u)
	eq(Movement.reachable(c, b, u).size(), 1, "只有原地")


## 地形消耗按路径累加; 不可通过格; 类别 10 消耗 4
func test_terrain_costs_on_path():
	var c = ctx_scripted()
	var b = _plain(10, 1)
	b.set_rows(["0003000000"])
	var u = _walker(0, 15, Vector2i(0, 0))
	b.add_unit(u)
	Movement.begin_phase(c, u)
	var r := Movement.reachable(c, b, u)
	eq(r.get(Vector2i(2, 0)), 10, "两格平地 10")
	check(not r.has(Vector2i(3, 0)), "进第 3 格要 18 > 15")
	b.set_rows(["0070000000"])
	r = Movement.reachable(c, b, u)
	check(not r.has(Vector2i(3, 0)), "步行过不了类别 7")
	b.set_rows(["aaa0000000"])
	u.set_pos(Vector2i(0, 0))
	Movement.begin_phase(c, u)
	eq(Movement.reachable(c, b, u).get(Vector2i(2, 0)), 8, "类别 10 每格 4")
	var flyer = _walker(4, 15, Vector2i(0, 0))
	var b2 = _plain(10, 1)
	b2.set_rows(["0770000000"])
	b2.add_unit(flyer)
	Movement.begin_phase(c, flyer)
	eq(Movement.reachable(c, b2, flyer).get(Vector2i(1, 0)), 12, "飞行4 过类别 7 消耗 12")


## ZOC: 进入敌人相邻格必须停下; 没有飞行例外; 不加消耗
func test_zoc_stop():
	var c = ctx_scripted()
	var b = _plain(11, 11)
	var u = _walker(6, 50, Vector2i(0, 5))     # 飞行6, 平地 5/格, 10 格
	var e = unit({"side": 1})
	e.set_pos(Vector2i(4, 5))
	b.add_unit(u)
	b.add_unit(e)
	Movement.begin_phase(c, u)
	var r := Movement.reachable(c, b, u)
	check(r.has(Vector2i(3, 5)), "可进入 ZOC 格")
	eq(r.get(Vector2i(3, 5)), 15, "ZOC 不加消耗")
	check(not r.has(Vector2i(4, 5)), "敌人格不可进")
	check(r.has(Vector2i(5, 5)), "单个敌人的 ZOC 可以绕过 (只有 4 格)")
	# 两行宽的走廊: 敌人在 (4,0), ZOC = (3,0),(5,0),(4,1)。沿下行走到 (4,1) 必须停下 → (5,1) 不可达
	var b2 = _plain(9, 2)
	var u2 = _walker(6, 50, Vector2i(0, 1))
	var e2 = unit({"side": 1})
	e2.set_pos(Vector2i(4, 0))
	b2.add_unit(u2)
	b2.add_unit(e2)
	Movement.begin_phase(c, u2)
	var r2 := Movement.reachable(c, b2, u2)
	check(r2.has(Vector2i(4, 1)), "可进入 ZOC 格 (4,1)")
	check(not r2.has(Vector2i(5, 1)), "进入 ZOC 后不能继续")
	check(not r2.has(Vector2i(6, 1)), "走廊被 ZOC 截断")
	u2.status = U.ST_PHANTOM
	check(Movement.reachable(c, b2, u2).has(Vector2i(6, 1)), "幻影无视 ZOC")
	# 幻影无视单位阻挡与 ZOC
	u.status = U.ST_PHANTOM
	r = Movement.reachable(c, b, u)
	check(r.has(Vector2i(6, 5)), "幻影可穿过敌人格")
	check(not r.has(Vector2i(4, 5)), "幻影也不能停在敌人格")


## 同阵营单位格可穿过不可停留; 敌对单位格不可穿过
func test_pass_through_allies():
	var c = ctx_scripted()
	var b = _plain(7, 1)
	var u = _walker(0, 30, Vector2i(0, 0))
	var ally = unit({"side": 0, "npc_ally": true})
	ally.set_pos(Vector2i(1, 0))
	b.add_unit(u)
	b.add_unit(ally)
	Movement.begin_phase(c, u)
	var r := Movement.reachable(c, b, u)
	check(not r.has(Vector2i(1, 0)), "不能停在友军格")
	check(r.has(Vector2i(2, 0)), "可穿过友军")


## 起点在 ZOC 内可以离开
func test_zoc_start_can_leave():
	var c = ctx_scripted()
	var b = _plain(9, 9)
	var u = _walker(0, 20, Vector2i(4, 4))
	var e = unit({"side": 1})
	e.set_pos(Vector2i(5, 4))
	b.add_unit(u)
	b.add_unit(e)
	Movement.begin_phase(c, u)
	check(Movement.reachable(c, b, u).has(Vector2i(2, 4)), "起点在 ZOC 可离开")
	var c2 = ctx_scripted([], {"zoc_start_free": false})
	eq(Movement.reachable(c2, b, u).size(), 1, "参数关闭时只能原地")


## 爆發: 未移动才可用; 保留点在下一次行动结束时清零; 带保留点期间不能反击; 移动先扣保留点
func test_burst_lifecycle():
	var c = ctx_scripted()
	var b = _plain()
	var u = _walker(0, 38)
	var e = unit({"side": 1})
	e.set_pos(Vector2i(21, 20))
	b.add_unit(u)
	b.add_unit(e)
	Movement.begin_phase(c, u)
	check(Movement.can_burst(c, u), "未移动可爆發")
	Movement.burst(c, u)
	eq(u.burst_reserve, 38)
	check(u.acted, "爆發立即结束行动")
	check(not Attack.can_counter(c, u, e), "带保留点不能反击 ")
	Movement.begin_phase(c, u)
	eq(u.move_cap, 76, "下一阶段 = 38 + 38")
	Movement.move_to(c, b, u, Vector2i(18, 20))
	eq(u.burst_reserve, 28, "移动先扣保留点")
	check(not Movement.can_burst(c, u), "移动后不可爆發")
	Movement.end_action(u)
	eq(u.burst_reserve, 0, "行动结束清零")
	check(Attack.can_counter(c, u, e) == false, "不相邻不反击")


## 速敏 ×1.5 先乘后加保留点
func test_haste_with_reserve_order():
	var c = ctx_scripted()
	var u = unit({"move_base": 30, "avg": 0})
	u.burst_reserve = 30
	u.status = U.ST_HASTE
	eq(Movement.move_cap(c, u), 45 + 30, "int(30×1.5)+30")
	var c2 = ctx_scripted([], {"haste_before_reserve": false})
	eq(Movement.move_cap(c2, u), 90, "另一读法 int(60×1.5)")

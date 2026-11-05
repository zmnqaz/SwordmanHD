# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 近景战斗里被打一方的反应 (HitReaction, 差异) 与命中震屏 (原版 Win10 原生逐帧实测)。除体力显示 (信息栏要原版底图) 外不依赖原版资源。

const REQUIRES_TEST := {"test_hp_display_float32_per_hit_frame": ["original"]}


## 震屏偏移 (原版像素): (7, 3) = 左上 3 像素, 每级缩小 1; 幅度 = shake/2, unk4 为轴位掩码
func test_shake_offsets():
	# 读原版内存表 (静态观察 3.2): 方向 (shake-1)/3 取整, 幅度序列 (shake-1)%3
	var seq := [[3, 2, 1], [6, 4, 2, 1], [12, 6, 4, 1]]
	var dirs := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1)]
	for shake in range(1, 13):
		var want := []
		for n in seq[(shake - 1) % 3]:
			want.append(dirs[(shake - 1) / 3] * float(n))
		eq(BattleCloseup.shake_offsets(shake), want, "shake=%d" % shake)
	eq(BattleCloseup.shake_offsets(7), [Vector2(-3, -3), Vector2(-2, -2), Vector2(-1, -1)], "原版实测 shake=7: 3,2,1 左上")
	eq(BattleCloseup.shake_offsets(0), [], "shake=0 不震")
	eq(BattleCloseup.shake_offsets(13), [], "shake>12 不震")


## 帧头 color -> 色闪 (级, 色号): 十位定级 (1~10 背景 / 11~20 不可见 / 21~30 人物之下 / >30 盖住一切), 个位 1..7 = 白红绿蓝黄品红青 (读码 + Windows 直读状态)
func test_color_code():
	eq(BattleCloseup.color_code(0), [], "0 无色闪")
	eq(BattleCloseup.color_code(14), [], "11~20 级 2: 原版没有绘制代码读, 不可见")
	eq(BattleCloseup.color_code(3), [1, 3], "级 1 绿")
	eq(BattleCloseup.color_code(21), [3, 1], "级 3 白")
	eq(BattleCloseup.color_code(25), [3, 5], "级 3 黄")
	eq(BattleCloseup.color_code(31), [4, 1], "级 4 白 (会心)")
	eq(BattleCloseup.color_code(32), [4, 2], "级 4 红 (格挡)")
	eq(BattleCloseup.color_code(10), [], "个位 10 无效")
	eq(BattleCloseup.color_code(28), [], "个位 8 无效")


## 近景体力显示按原版 32 位浮点逐命中帧扣: 体力 100 受 10 伤分 3 帧 → 显示 89 (真实 90), 判倒下 / 留 1 仍用真实值
func test_hp_display_float32_per_hit_frame() -> void:
	var p := BattleCloseup.InfoPanel.new(true, "甲", 100, 100)
	for i in 3:
		p.hit(10.0 / 3, true)
	eq(int(p.shown), 89, "原版显示 89 (96.666664 → 93.33333 → 89.99999)")
	eq(p.hp_exact, 100, "真实体力由调用方记, hit 不动它")
	var q := BattleCloseup.InfoPanel.new(true, "乙", 100, 100)
	for i in 4:
		q.hit(10.0 / 4, true)
	eq(int(q.shown), 90, "4 帧整除: 不差")
	p.free()
	q.free()


## 跑到回待机, 返回每 tick 的 [帧, 偏移] (第 0 项是命中当下)
func _run(r: HitReaction, max_ticks := 60) -> Array:
	var out := [[r.frame(), r.offset]]
	for i in max_ticks:
		var going := r.tick()
		out.append([r.frame(), r.offset])
		if not going:
			break
	return out


## 普通命中 hit=1 time=2: 帧 1, 等 3 tick, 3 步位移 (合计 0), 一进归零就回待机; 不再固定 1→2→1→2 12 tick
func test_hurt_single_hit_frame1_then_idle():
	var r := HitReaction.new(true)
	r.hit(1, 2, false)
	var seq := _run(r)
	eq(seq[0][0], 1, "命中: 帧 1")
	check(seq.all(func(e): return e[0] in [1, -1]), "单次命中不出现帧 2")
	var idle_at := seq.map(func(e): return e[0]).find(-1)
	eq(idle_at, 7, "time+1 = 3 tick 等待 + 3 步位移 + 1 = 第 7 tick 回待机")
	eq(seq[4][1], Vector2(-12, -8), "等完后第 1 步: 左侧向左上 (-12,-8)")
	eq(seq[-1][1], Vector2.ZERO, "位移回原位")


## 还在受击姿势里再被命中: 帧 1 ↔ 2 翻转, 等待重新计; hit=4 不翻
func test_hurt_repeated_hits_flip():
	var r := HitReaction.new(false)
	r.hit(1, 2, false)
	r.tick()
	r.hit(1, 2, false)
	eq(r.frame(), 2, "第二次命中: 帧 2")
	r.hit(1, 2, false)
	eq(r.frame(), 1, "第三次: 回帧 1")
	r.hit(4, 2, false)
	eq(r.frame(), 1, "hit=4 不翻")


## 格挡 / 闪避 (AB 系): 一直帧 0, 不交替 ((0) 每次清翻转); 位移归零那 tick 才回待机
func test_guard_always_frame0_and_returns_by_itself():
	var r := HitReaction.new(true)
	r.hit(1, 2, true)
	eq(r.frame(), 0, "格挡: 帧 0")
	r.hit(1, 2, true)
	eq(r.frame(), 0, "再被命中仍帧 0")
	var seq := _run(r)
	var idle_at := seq.map(func(e): return e[0]).find(-1)
	check(idle_at > 0 and idle_at <= 8, "几 tick 内自己回待机 (第 %d tick), 不等攻击动画放完" % idle_at)


## hit=2 / hit=3 位移 (Windows 直读 U3): hit=2 (6,4) 左负右正且累加, hit=3 ±(3,2) 交替**累加**, 等完后每 tick 按 (6,4) 收回
func test_hit2_hit3_displacement():
	var r := HitReaction.new(true)
	r.hit(2, 2, false)
	eq(r.offset, Vector2(-6, -4), "hit=2 左侧 (-6,-4)")
	r.hit(2, 2, false)
	eq(r.offset, Vector2(-12, -8), "连续 hit=2 累加")
	var r2 := HitReaction.new(false)
	r2.hit(2, 2, false)
	eq(r2.offset, Vector2(6, 4), "右侧取反")
	var r3 := HitReaction.new(true)
	r3.hit(3, 2, false)
	eq(r3.offset, Vector2(-3, -2), "hit=3 左先负")
	r3.hit(3, 2, false)
	eq(r3.offset, Vector2.ZERO, "hit=3 交替 (累加: -3 + 3)")
	var r4 := HitReaction.new(true)
	r4.hit(4, 2, false)
	eq(r4.offset, Vector2.ZERO, "hit=4 无位移")
	var seq := _run(r)
	eq(seq[-1][1], Vector2.ZERO, "收回到原位")


func test_push_steps_return_to_origin():
	for ab in [false, true]:
		var sum := Vector2.ZERO
		for st in HitReaction.STEPS[ab]:
			sum += st
		eq(sum, Vector2.ZERO, "位移三步累计回原位 ab=%s" % ab)


## 守方不可见 (攻击动画的藏守方窗口) 时反应不走
func test_hidden_defender_does_not_step():
	var r := HitReaction.new(true)
	r.hit(1, 0, false)
	for i in 5:
		r.tick(false)
	eq(r.frame(), 1, "不可见期间不推进")
	eq(r.wait, 1, "等待也不减")


## 连击: 两遍各扣 总伤 / 2 (奇数也两遍相同), 数字读同一个值; total 带真实总伤供判倒下
func test_double_passes_each_half_total():
	var ks := BattleRules.strike_kinds({"result": 1, "crit": false, "double": true, "damage": 9})
	eq(ks.map(func(k): return k["damage"]), [4, 4], "9 → 每遍 4 (sar 1), 不是 4 + 5")
	eq(ks.map(func(k): return k["total"]), [9, 9], "真实总伤 9")
	var gs := BattleRules.strike_kinds({"result": 2, "crit": true, "double": true, "damage": 7})
	eq(gs.map(func(k): return k["damage"]), [3, 3], "格挡 + 连击同样各半")
	var one := BattleRules.strike_kinds({"result": 1, "crit": true, "double": false, "damage": 9})
	check(one.size() == 1 and not one[0].has("total"), "非连击一遍, 不带 total")

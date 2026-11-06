# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 城镇主角走路节拍 (TownHeroGait + RpgScene 接线): 原版 Windows 逐 tick 实测。
##   每格 10 tick; 行走帧 0 在第 0 tick, 帧 1 在第 1 tick, 帧 2 在第 3 tick, 帧 3 在第 5 tick 起一直到格末 (1/2/2/5);
##   主角位置分三段跳: 第 0 / 1 / 3 / 5 tick 起分别在格内 0 / 1/3 / 2/3 / 满格 (不是匀速滑过);
##   走完松键后, 行走末帧再停 3 tick 才换站立; 站立动画每帧 2 tick。城镇主角精灵没有起步 / 收步帧。
## 用合成动画数据 (只要 Assets 单例), 本机没有原版资源也照跑。

const KEY := "Test/gait_hero"


func _fake_ok() -> bool:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Assets") != null


## 站立 3 帧、行走 4 帧 (原版城镇主角 11 / 4), 每帧 time=2; 行走帧 1、3 带音效 (原版 Rpgman 同)
func _fake_anim() -> void:
	var A = (Engine.get_main_loop() as SceneTree).root.get_node("Assets")
	var frames := []
	for i in 4 * (3 + 4):
		var snd := -1
		if i >= 12:
			var k := (i - 12) % 4
			snd = 0 if k == 1 else (1 if k == 3 else -1)
		frames.append({"sound": snd, "time": 2, "hit": 0, "color": 0, "shake": 0, "unk4": 0, "parts": []})
	A._anims[KEY.to_lower()] = {"frames": frames, "action_counts": [3, 4, 0, 0, 0], "textures": [], "sounds": [], "dir": KEY}
	A._index[(KEY + "/anim.json").to_lower()] = true
	ThemeAssets.use({"names": {"rpg.hero": KEY}})


func _unfake() -> void:
	var A = (Engine.get_main_loop() as SceneTree).root.get_node("Assets")
	A._anims.erase(KEY.to_lower())
	A._index.erase((KEY + "/anim.json").to_lower())
	ThemeAssets.reload()


# ---------------- 纯节拍 ----------------

func test_frame_timeline_is_1_2_2_5_ticks() -> void:
	var f: Array = []
	for t in 12:
		f.append(TownHeroGait.frame_at(t, 4))
	eq(f, [0, 1, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3], "帧 0/1/2/3 依次从第 0/1/3/5 tick 起, 末帧一直停到格末")


func test_position_jumps_in_thirds() -> void:
	var p: Array = []
	for t in 10:
		p.append(snappedf(TownHeroGait.fraction_at(t, 4), 0.001))
	eq(p, [0.0, 0.333, 0.333, 0.667, 0.667, 1.0, 1.0, 1.0, 1.0, 1.0], "格内位置 0 / 1/3 / 2/3 / 满格, 与帧同步")


func test_other_frame_counts_still_reach_the_cell() -> void:
	for n in [2, 3, 4, 5, 8]:
		eq(TownHeroGait.frame_at(9, n), n - 1, "%d 帧: 格末停在末帧" % n)
		eq(TownHeroGait.fraction_at(9, n), 1.0, "%d 帧: 格末满格" % n)
		eq(TownHeroGait.frame_at(0, n), 0)
	eq(TownHeroGait.frame_at(5, 1), 0, "只有 1 个行走帧也不越界")
	check(TownHeroGait.fraction_at(9, 1) >= 0.0 and TownHeroGait.fraction_at(9, 1) <= 1.0, "1 帧时位置不越界")


func test_pure_step_queues_frames_and_positions_per_tick() -> void:
	var g := TownHeroGait.new(4)
	g.face_walk()
	var frames: Array = g.take_frames()
	g.begin(Vector2(100, 50), Vector2(130, 50))
	var xs: Array = []
	var done_at := -1
	for t in 12:
		var done := g.advance(TownHeroGait.TICK)
		frames.append_array(g.take_frames())
		xs.append(snappedf(g.position.x, 0.01))
		if done and done_at < 0:
			done_at = t + 1
	eq(done_at, 10, "每格 10 tick")
	eq(xs.slice(0, 10), [110.0, 110.0, 120.0, 120.0, 130.0, 130.0, 130.0, 130.0, 130.0, 130.0], "每过一个 tick 后的位置: 第 1 tick 起 1/3, 第 3 tick 起 2/3, 第 5 tick 起满格")
	eq(frames, [0, 1, 2, 3], "行走帧按 0 1 2 3 各排一次")


func test_a_long_hitch_still_queues_every_walk_frame() -> void:
	var g := TownHeroGait.new(4)
	g.face_walk()
	g.take_frames()
	g.begin(Vector2.ZERO, Vector2(0, 24))
	g.advance(0.3)   # 一次卡顿跨过帧 1 2 3
	eq(g.take_frames(), [1, 2, 3], "跨过的帧逐个交给场景 (脚步声在帧 1、3, 不能漏)")


func test_carry_over_keeps_the_ten_tick_cadence() -> void:
	var g := TownHeroGait.new(4)
	g.face_walk()
	g.begin(Vector2.ZERO, Vector2(0, 24))
	var elapsed := 0.0
	var cells := 0
	var dt := 0.0173   # 约 58 帧/秒, 不整除 tick
	while cells < 5:
		elapsed += dt
		if g.advance(dt):
			cells += 1
			g.face_walk()
			g.begin(Vector2.ZERO, Vector2(0, 24))
	check(absf(elapsed - 5 * 10 * TownHeroGait.TICK) <= dt + 1e-6, "连走 5 格总用时 %.3f 应约 2.0 秒 (余量带进下一格, 不累积误差)" % elapsed)


func test_carry_is_dropped_after_standing_a_frame() -> void:
	var g := TownHeroGait.new(4)
	g.face_walk()
	g.begin(Vector2.ZERO, Vector2(0, 24))
	check(g.advance(0.46), "一次走满")
	check(g.carry > 0.05, "有余量 %.3f" % g.carry)
	g.settle(0)
	g.update_tail(1.0 / 60)   # 站着过了一个帧
	eq(g.carry, 0.0, "余量作废")
	g.face_walk()
	g.take_frames()
	g.begin(Vector2.ZERO, Vector2(0, 24))
	eq(g.take_frames(), [], "从帧 0 开始, 不被旧余量抢跑")


func test_stop_holds_last_walk_frame_3_ticks_then_asks_for_stand() -> void:
	var g := TownHeroGait.new(4)
	g.face_walk()
	g.begin(Vector2.ZERO, Vector2(0, 24))
	while not g.advance(TownHeroGait.TICK):
		pass
	g.settle(1)
	eq(g.update_tail(TownHeroGait.TICK), -1, "第 1 tick 还在末帧")
	eq(g.update_tail(TownHeroGait.TICK), -1, "第 2 tick 还在末帧")
	eq(g.update_tail(TownHeroGait.TICK), 1, "满 3 tick 才站立, 朝向是 settle 时的")
	eq(g.update_tail(TownHeroGait.TICK), -1, "只触发一次")


func test_new_step_or_turn_cancels_the_pending_stand() -> void:
	var g := TownHeroGait.new(4)
	g.settle(2)
	g.face_walk()   # 尾巴里又起步
	eq(g.update_tail(1.0), -1, "起步后先前挂着的站立不会再触发")
	g.settle(2)
	g.cancel_tail()   # 被挡转向 / 对话转身: 场景立刻站立
	eq(g.update_tail(1.0), -1, "取消后不会改回旧朝向")


# ---------------- 场景接线 ----------------

## RpgScene 不进场景树、不读地图, 只给一张全可走的 5x6 小地图和合成动画; _cam_moving 置真让它不去碰窗口
func _scene(rows := 6) -> Variant:
	var s = (load("res://engine/rpg/rpg_scene.gd") as GDScript).new()
	var st := RpgStage.new()
	st.width = 5
	st.height = rows
	for i in 5 * rows:
		st.cells.append({"walk": true, "talk": 0, "step": 0})
	s.st = st
	s.hero = AnimPlayer.new()
	s.hero.play_sound = false
	s.gait = TownHeroGait.new()
	s._cam_moving = true
	s._place_hero(1, 1, BattleUnit.Dir.SOUTH)
	return s


func _scene_free(s) -> void:
	s.hero.free()
	s.free()


func test_scene_walks_a_cell_in_thirds_and_keeps_the_last_frame_after_stopping() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	WalkStyle.override = 1   # 原版步进 (内置缺省是平滑)
	var s = _scene()
	var y0: float = s.hero.position.y
	var base := 3 * 4 + 0 * 4   # 站立 3*4 + 朝南 (d=0) 的行走首帧
	eq(s.hero.tick_override, 2, "站立每帧 2 tick")
	s._step(BattleUnit.Dir.SOUTH)
	eq(s.hero.frame, base, "按下后立刻是行走帧 0")
	var ys: Array = []
	var fr: Array = []
	for t in 10:
		s._walk_tick(TownHeroGait.TICK)
		ys.append(snappedf(s.hero.position.y - y0, 0.01))
		fr.append(s.hero.frame - base)
	eq(ys, [8.0, 8.0, 16.0, 16.0, 24.0, 24.0, 24.0, 24.0, 24.0, 24.0], "竖向一格 24 像素分 8/16/24 三段跳 (原版实测)")
	eq(fr, [1, 1, 2, 2, 3, 3, 3, 3, 3, 3], "行走帧 0/1/2/3 从第 0/1/3/5 tick 起")
	eq(Vector2i(s.hx, s.hy), Vector2i(1, 2), "第 10 tick 到格")
	check(not s._moving, "走完")
	check(not s.hero.playing and s.hero.frame == base + 3, "停下后行走末帧再保持一会儿, 不立刻站立")
	for t in 2:
		var sd: int = s.gait.update_tail(TownHeroGait.TICK)
		eq(sd, -1)
	var sd2: int = s.gait.update_tail(TownHeroGait.TICK)
	eq(sd2, 0, "满 3 tick 回到朝南站立")
	s._hero_act(false, sd2)
	check(s.hero.playing and s.hero.start_frame == 0 and s.hero.tick_override == 2, "站立动画在播, 每帧 2 tick")
	eq(s.hero.frame, TownHeroGait.STAND_RESUME_FRAME % 3, "走完停下后站立从段内第 4 帧续 (假动画站立 3 帧 → 4 mod 3)")
	WalkStyle.override = -1
	_scene_free(s)
	_unfake()


func test_scene_horizontal_cell_jumps_10_20_30() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	WalkStyle.override = 1
	var s = _scene()
	var x0: float = s.hero.position.x
	s._step(BattleUnit.Dir.EAST)
	var xs: Array = []
	for t in 6:
		s._walk_tick(TownHeroGait.TICK)
		xs.append(snappedf(s.hero.position.x - x0, 0.01))
	eq(xs, [10.0, 10.0, 20.0, 20.0, 30.0, 30.0], "横向一格 30 像素分 10/20/30 三段跳 (原版实测 ±10 ±20)")
	WalkStyle.override = -1
	_scene_free(s)
	_unfake()


## 缺省 (WalkStyle.SMOOTH = true): 同样每格 10 tick, 位置匀速滑过, 到格 30 像素; 行走帧的节拍不变
func test_scene_smooth_walk_slides_evenly_over_ten_ticks() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	WalkStyle.override = 0
	var s = _scene()
	var x0: float = s.hero.position.x
	s._step(BattleUnit.Dir.EAST)
	var xs: Array = []
	for t in 10:
		s._walk_tick(TownHeroGait.TICK)
		xs.append(snappedf(s.hero.position.x - x0, 0.01))
	WalkStyle.override = -1
	eq(xs, [3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 24.0, 27.0, 30.0], "匀速 30 像素 / 10 tick")
	_scene_free(s)
	_unfake()


func test_scene_holding_a_direction_keeps_a_ten_tick_cadence_without_standing() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	var s = _scene()
	var dt := 0.0173
	var elapsed := 0.0
	var cells := 0
	s._step(BattleUnit.Dir.SOUTH)
	while cells < 4 and elapsed < 5.0:
		elapsed += dt
		s._walk_tick(dt)
		if not s._moving:   # 到格: 按住方向键就在同一帧接着走下一格 (RpgScene._process 的按住连走)
			cells += 1
			if cells < 4:
				s._step(BattleUnit.Dir.SOUTH)
	eq(Vector2i(s.hx, s.hy), Vector2i(1, 5), "连走 4 格")
	check(absf(elapsed - 4 * 10 * TownHeroGait.TICK) <= dt + 1e-6, "连走 4 格用时 %.3f 应约 1.6 秒" % elapsed)
	check(not s.hero.playing, "连走途中没有切到站立")
	_scene_free(s)
	_unfake()


func test_scene_turning_against_a_wall_stands_immediately() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	var s = _scene()
	s._step(BattleUnit.Dir.SOUTH)
	while s._moving:
		s._walk_tick(TownHeroGait.TICK)
	s._hero_act(false, BattleUnit.Dir.WEST)   # 走完后被挡转向 / 对话转身: 立刻站立, 不等收尾
	check(s.hero.playing and s.hero.start_frame == 1 * 3, "立刻朝西站立")
	eq(s.gait.update_tail(1.0), -1, "挂着的收尾已取消, 不会改回旧朝向")
	_scene_free(s)
	_unfake()


## 前提: 原版城镇主角 Rpgman.saf 只有站立 (44) + 行走 (16) 共 60 帧; 文件头里的起步 7 / 收步 7 / 胜利 10 是战场模板残留, 没有帧数据
func test_town_hero_sprite_has_no_start_stop_frames() -> void:
	var A = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Assets")
	if A == null or A._index.is_empty() or not Assets.exists("Rpg/Rpgman/anim.json"):
		check(true, "无原版资源, 跳过")
		return
	var d := Assets.anim("Rpg/Rpgman")
	var c: Array = d["action_counts"]
	eq(d["frames"].size(), (int(c[0]) + int(c[1])) * 4, "只有站立和行走, 没有起步 / 收步帧")


# ---------------- 点按只走一格 (游戏加速时) ----------------

func test_may_chain_gate_is_pure_real_time() -> void:
	check(TownHeroGait.may_chain(true, 0.0), "新按下立刻走")
	check(not TownHeroGait.may_chain(false, 0.1), "同一次按下、按住 0.1 真实秒: 点按, 不连走")
	check(not TownHeroGait.may_chain(false, TownHeroGait.HOLD_GATE - 0.001), "没到门槛不连走")
	check(TownHeroGait.may_chain(false, TownHeroGait.HOLD_GATE), "到门槛算按住")
	check(TownHeroGait.HOLD_GATE < TownHeroGait.STEP_TICKS * TownHeroGait.TICK, "门槛小于 1 倍速一格用时: 原速完全不受影响")


const FRAME := 0.02   # 模拟真实帧长 (秒)


## 模拟 RpgScene._process 的一帧 (真实 FRAME 秒, 游戏时间 = FRAME x time_scale): 输入层先走 (优先级 -50), 再推进走路 / 站立, 空闲时读按住的方向
func _frame(s, r) -> void:
	var delta := FRAME * Engine.time_scale
	r._process(delta)
	if s._moving:
		s._walk_tick(delta)
	else:
		var sd: int = s.gait.update_tail(delta)
		if sd >= 0:
			s._hero_act(false, sd)
	if not s._moving:   # 同帧刚走完也读键 (同 RpgScene._process: 到格同一帧接着走)
		s._held_walk(r)


## 速度 mult 下按下 Down 键, 按住 hold 真实秒后松开, 一共跑 total 真实秒; 返回主角走了几格 (y 方向) 和过程中是否曾切到站立
func _tap(mult: float, hold: float, total := 3.0) -> Dictionary:
	var Router = load("res://engine/input/input_router.gd")
	var r = Router.new()
	var s = _scene(30)
	var saved := Engine.time_scale
	Engine.time_scale = mult
	var down := false
	var t := 0.0
	var stood_while_holding := false
	var cells0: int = s.hy
	var walked_once := false
	while t < total:
		if not down and t == 0.0:
			r.repeat.press(UiAction.DOWN)
			down = true
		if down and t >= hold - 1e-9:
			r.repeat.release(UiAction.DOWN)
			down = false
		_frame(s, r)
		t += FRAME
		if s._moving:
			walked_once = true
		if down and walked_once and not s._moving and s.hero.playing:
			stood_while_holding = true
	var out := {"cells": int(s.hy) - cells0, "stood": stood_while_holding}
	Engine.time_scale = saved
	r.free()
	_scene_free(s)
	return out


func test_tap_walks_one_cell_at_any_game_speed() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	for mult in [1.0, 1.5, 2.0, 3.0, 4.0, 5.0]:
		for hold in [0.06, 0.1, 0.15, 0.2, 0.24]:
			eq(_tap(mult, hold)["cells"], 1, "x%s 倍速点按 %s 秒只走一格" % [mult, hold])
	_unfake()


func test_hold_keeps_walking_continuously_at_any_game_speed() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	for mult in [1.0, 2.0, 3.0, 5.0]:
		var o := _tap(mult, 1.0, 1.0 + 0.4 / mult + 0.2)   # 按住 1 秒松开, 再等当前这格走完
		# 按住 1 真实秒 = 游戏 mult 秒 = 2.5 x mult 格; 第一格后最多多等 (门槛 - 一格用时) 真实秒
		var one_cell: float = TownHeroGait.STEP_TICKS * TownHeroGait.TICK / mult
		var pause: float = maxf(0.0, TownHeroGait.HOLD_GATE - one_cell)
		var want: float = (1.0 - pause) / one_cell
		check(float(o["cells"]) >= floorf(want) and float(o["cells"]) <= ceilf(want) + 2.0, "x%s 按住 1 秒走了 %d 格, 预期约 %.1f" % [mult, o["cells"], want])
		check(float(o["cells"]) >= 2.0, "x%s 按住确实连走 (>= 2 格)" % mult)
	_unfake()


func test_one_x_speed_is_unchanged_by_the_gate() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	eq(_tap(1.0, 0.3)["cells"], 1, "原速点按 0.3 秒 (< 0.4) 只走一格 (原版同)")
	eq(_tap(1.0, 0.5, 1.2)["cells"], 2, "原速按住 0.5 秒: 到格边界还按着, 再走一格 (原版同)")
	eq(_tap(1.0, 1.25, 1.25 + 0.4)["cells"], 4, "原速按住 1.25 秒连走 (0.4 秒一格, 无停顿): 1.6 秒内走 4 格")
	_unfake()


func test_waiting_for_the_gate_keeps_the_walk_pose_instead_of_standing() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	check(not _tap(3.0, 1.0)["stood"], "3 倍速按住时第一格后的等待期间不闪回站立")
	_unfake()


func test_a_new_press_walks_at_once_even_if_the_old_one_just_stepped() -> void:
	if not _fake_ok():
		check(true, "无 Assets, 跳过")
		return
	_fake_anim()
	var Router = load("res://engine/input/input_router.gd")
	var r = Router.new()
	var s = _scene(30)
	var saved := Engine.time_scale
	Engine.time_scale = 3.0
	r.repeat.press(UiAction.DOWN)
	_frame(s, r)
	check(s._moving, "按下的这一帧起步")
	r.repeat.release(UiAction.DOWN)
	while s._moving:
		_frame(s, r)
	eq(s.hy, 2, "点按走一格")
	r.repeat.press(UiAction.DOWN)   # 再点一下: 新的一次按下, 立刻再走一格 (不被上一次的门槛拖住)
	_frame(s, r)
	check(s._moving, "第二次点按立刻起步")
	Engine.time_scale = saved
	r.free()
	_scene_free(s)
	_unfake()

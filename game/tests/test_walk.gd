# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战场单位逐格行走 (BattleUnit.walk / _process): 任意帧长都要走到终点并发 move_finished。
## 回归: 原先 |差| <= 0.01 像素就不再移动、又要 is_equal_approx 才算到格, 帧长不整除格宽时
## (60/144Hz 实机, 无 --fixed-fps) 停在差 0.00x 像素处, 剧情行走与 AI 移动永远等不到 move_finished。


func _assets_ready() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var A = tree.root.get_node_or_null("Assets")
	var C = tree.root.get_node_or_null("Content")
	if A == null or C == null:
		return false
	if A._index.is_empty():
		A._ready()
	if C.packs.is_empty():
		C.load_packs([ContentDB.default_main()])
	return not A._index.is_empty()


func _unit(c: Vector2i) -> BattleUnit:
	var u := BattleUnit.new()
	u.info = {"name": "甲", "camp": 0, "sprite": 1}
	u._anim_dir = "Sprite/man001/001man"
	u.anim = AnimPlayer.new()
	u.anim.play_sound = false
	u.add_child(u.anim)
	u.set_cell(c.x, c.y)
	return u


## 各种帧长 (含实测卡住的 0.006896 秒 = 145 帧/秒) 下都能走完, 用时与帧率无关
func test_walk_finishes_at_any_frame_rate():
	if not _assets_ready():
		check(true, "无资源, 跳过")
		return
	var path := [Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7), Vector2i(9, 8), Vector2i(9, 9)]
	var dist := 5.0 * BattleStage.CELL_W   # 每格用时横竖相同 (原版实测): 5 格 = 5 个横向格宽的时间
	for dt in [1.0 / 25, 1.0 / 30, 1.0 / 60, 1.0 / 144, 0.006896, 0.00694444444444, 0.0173, 0.1]:
		for speed in [150.0, 125.0, 75.0, 35.0]:
			var u := _unit(Vector2i(6, 7))
			var done := [false]
			u.move_finished.connect(func(): done[0] = true)
			u.walk(path, speed)
			var frames := 0
			while not done[0] and frames < 100000:
				u._process(dt)
				frames += 1
			check(done[0], "帧长 %.6f 速度 %d 走完" % [dt, speed])
			eq(Vector2i(u.cx, u.cy), Vector2i(9, 9), "帧长 %.6f 速度 %d 终点格" % [dt, speed])
			eq(u.position, Vector2(9 * BattleStage.CELL_W, 9 * BattleStage.CELL_H), "终点像素")
			var c: Array = Assets.anim(u._anim_dir)["action_counts"]
			var extra: float = (float(c[2] - 1) + float(c[3] - 1)) * 2 * AnimPlayer.TICK if int(c[2]) > 1 and int(c[3]) > 1 else 0.0   # 起步 + 收步 (每组第 0 帧不显示, 每帧 2 tick)
			check(absf(frames * dt - (dist / speed + extra)) <= 3 * dt + 1e-6, "帧长 %.6f 速度 %d 用时 %.3f 应约 %.3f 秒" % [dt, speed, frames * dt, dist / speed + extra])
			u.free()


## 合成动画数据的测试只要 Assets 单例在 (不读任何资源文件), 本机没有原版资源也照跑
func _fake_ok() -> bool:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Assets") != null


## 合成的动画数据 (不依赖原版资源): 站立 1 帧、行走 mv 帧、起步 4 帧 (显示第 1..3 帧)、收步 3 帧 (显示第 1..2 帧), 每帧 time=2; 帧号布局同原版 (见 BattleUnit.play_act)
func _fake_anim(key: String, mstart := 4, mend := 3, mv := 2) -> void:
	var A = (Engine.get_main_loop() as SceneTree).root.get_node("Assets")
	var win := 0
	var base := 2 + 1
	var n := base + 4 * (1 + mv + mstart + mend)
	var frames := []
	for i in n:
		frames.append({"sound": -1, "time": 2, "hit": 0, "color": 0, "shake": 0, "unk4": 0, "parts": []})
	A._anims[key.to_lower()] = {"frames": frames, "action_counts": [1, mv, mstart, mend, win], "textures": [], "sounds": [], "dir": key}
	A._index[(key + "/anim.json").to_lower()] = true   # AnimPlayer.play 先问 Assets.exists; 用完要 _unfake 清掉, 免得别的测试以为有资源


func _unfake(key: String) -> void:
	var A = (Engine.get_main_loop() as SceneTree).root.get_node("Assets")
	A._anims.erase(key.to_lower())
	A._index.erase((key + "/anim.json").to_lower())


func _unit_with(key: String, c: Vector2i) -> BattleUnit:
	var u := _unit(c)
	u._anim_dir = key
	return u


## 推进 u 和它的动画 dt 秒 (节点不在树里, 手动驱动)
func _tick(u: BattleUnit, dt: float) -> void:
	u._process(dt)
	u.anim._process(dt)


## 起步 (原版「提箱子」): 确认移动后单位先原地播起步动画, 播完才开始走; 起步每帧 2 tick, 第 0 帧不显示 (原版实测 11 帧起步 = 20 tick = 0.80 秒)
func test_move_start_plays_in_place_before_walking():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_ms/a")
	var u := _unit_with("Sprite/test_ms/a", Vector2i(6, 7))
	var start_pos := u.position
	u.walk([Vector2i(7, 7)], 150.0)
	eq(u.act, BattleUnit.Act.MOVE_START, "一开始播起步")
	eq(u.dir, BattleUnit.Dir.EAST, "起步朝第一步的方向")
	eq(u.anim.tick_override, 2, "起步每帧 2 tick")
	eq(u.anim.end_frame - u.anim.start_frame, 3, "起步 4 帧只放第 1..3 帧")
	for i in 5:   # 起步放 3 帧 x 0.08 秒 = 0.24 秒; 0.20 秒时还在原地
		_tick(u, 0.04)
	eq(u.position, start_pos, "起步期间原地不动")
	eq(u.act, BattleUnit.Act.MOVE_START, "0.20 秒仍在起步")
	for i in 3:
		_tick(u, 0.04)
	eq(u.act, BattleUnit.Act.MOVE, "起步播完转行走")
	eq(u.anim.tick_override, 2, "走路每帧也是 2 tick (原版逐帧实测 0.08 秒)")
	for i in 3:
		_tick(u, 0.04)
	check(u.position.x > start_pos.x, "之后开始走")
	u.free()
	_unfake("Sprite/test_ms/a")


## 收步 (原版「放箱子」): 到格后播收步动画, 播完才算走完 (move_finished), 行动菜单才出来; 之后站立
func test_move_end_plays_after_arrival_and_finishes_after_it():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_me/a")
	var u := _unit_with("Sprite/test_me/a", Vector2i(6, 7))
	var done := [false]
	u.move_finished.connect(func(): done[0] = true)
	u.walk([Vector2i(7, 7)], 150.0)
	var guard := 0
	while u.act != BattleUnit.Act.MOVE_END and guard < 2000:
		_tick(u, 0.01)
		guard += 1
	eq(u.act, BattleUnit.Act.MOVE_END, "到格后播收步")
	eq(u.position, Vector2(7 * BattleStage.CELL_W, 7 * BattleStage.CELL_H), "收步在终点")
	check(not done[0], "收步没播完不算走完")
	check(u.is_moving(), "收步期间仍算在移动 (剧情等它走完)")
	for i in 3:   # 收步 2 帧 x 0.08 = 0.16 秒
		_tick(u, 0.04)
	check(not done[0], "0.12 秒时还没完")
	_tick(u, 0.04)
	_tick(u, 0.04)
	check(done[0], "收步播完才发 move_finished")
	eq(u.act, BattleUnit.Act.STAND, "走完回到站立")
	check(not u.is_moving(), "不再移动")
	u.free()
	_unfake("Sprite/test_me/a")


## 每格用时横竖相同 (原版实测: 40 次格间隔, 横向 0.236 s / 竖向 0.237 s = 6 tick); 玩家 / AI 走路速度 125 像素/秒 => 每格 0.24 秒
func test_each_cell_takes_the_same_time_horizontal_or_vertical():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_cell/a", 0, 0)
	var times := []
	for step in [Vector2i(7, 7), Vector2i(6, 8)]:   # 起点 (6,7): 右一格 / 下一格
		var u := _unit_with("Sprite/test_cell/a", Vector2i(6, 7))
		var done := [false]
		u.move_finished.connect(func(): done[0] = true)
		u.walk([step], BattleStage.UNIT_WALK_SPEED)
		var t := 0.0
		while not done[0] and t < 2.0:
			_tick(u, 0.001)
			t += 0.001
		times.append(t)
		u.free()
	check(absf(times[0] - 0.24) < 0.004, "横向一格 %.3f 秒, 应约 0.24" % times[0])
	check(absf(times[1] - 0.24) < 0.004, "竖向一格 %.3f 秒, 应约 0.24 (不是按像素等速的 0.19)" % times[1])
	_unfake("Sprite/test_cell/a")


## 没有起步 / 收步动作的单位 (绝大多数) 行为不变: 直接走, 到格就完
func test_units_without_start_end_walk_as_before():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_none/a", 0, 0)
	var u := _unit_with("Sprite/test_none/a", Vector2i(6, 7))
	var done := [false]
	u.move_finished.connect(func(): done[0] = true)
	u.walk([Vector2i(7, 7)], 150.0)
	eq(u.act, BattleUnit.Act.STAND, "没起步动作: 还没开始 (等 _process 起步走)")
	var t := 0.0
	while not done[0] and t < 2.0:
		_tick(u, 0.01)
		t += 0.01
	check(done[0], "走完")
	check(t <= BattleStage.CELL_W / 150.0 + 0.02, "用时就是走格时间, 没有多余动作")
	u.free()
	_unfake("Sprite/test_none/a")


## 起步 / 收步动画被别的动作打断 (撤销移动等) 时不能卡住后续: 打断后回调作废
func test_interrupting_move_start_does_not_leave_it_stuck():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_int/a")
	var u := _unit_with("Sprite/test_int/a", Vector2i(6, 7))
	u.walk([Vector2i(7, 7)], 150.0)
	u._path.clear()   # 撤销移动 (undo_move) 时路径已走完, 只剩动作被换掉
	u.play_act(BattleUnit.Act.STAND, BattleUnit.Dir.SOUTH)
	for i in 20:
		_tick(u, 0.04)
	eq(u.act, BattleUnit.Act.STAND, "被打断后不再被旧的起步回调改回行走")
	u.free()
	_unfake("Sprite/test_int/a")


## 走路指令只改坐标, 不让单位出场 (在场标志只由出场指令置位)。
## 原版第 16~31 关开场脚本对没入队的夏侯仪无条件下达走路指令 (show_group 才受 var14 保护);
## 以前 walk() 顺手置 shown, 没入队的夏侯仪凭空出现并被当玩家单位行动。
func test_d70_walk_does_not_show_hidden_unit():
	if not _assets_ready():
		check(true, "无资源, 跳过")
		return
	var hidden := _unit(Vector2i(6, 7))
	hidden.shown = false
	hidden.visible = false
	hidden.walk([Vector2i(7, 7)], 150.0)
	check(not hidden.shown, "没出场的单位走路后仍不在场")
	check(not hidden.visible, "也不显示")
	hidden.free()
	var on := _unit(Vector2i(6, 7))
	on.shown = true
	on.visible = false
	on.walk([Vector2i(7, 7)], 150.0)
	check(on.shown and on.visible, "在场的单位走路时显示")
	on.free()


## 起步 / 收步第 0 帧不显示 (原版实测 254 次全部如此): 播放范围从组内第 1 帧起
func test_start_and_end_skip_frame_zero():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_skip/a")
	var u := _unit_with("Sprite/test_skip/a", Vector2i(6, 7))
	var base := 3 + (1 + 2) * 4   # 2 + 胜利 (无, 取 1) = 3, 之后站立 1 + 行走 2 各 4 个方向, 才是起步组 (朝南的第 0 帧)
	u.walk([Vector2i(7, 7)], 150.0)
	eq(u.anim.start_frame, base + 4 * BattleUnit.Dir.EAST + 1, "起步从组内第 1 帧起")
	_unfake("Sprite/test_skip/a")
	u.free()


## 行走帧号从第 1 帧起 (1,2,3,0,1,...), 站立每帧 3 tick, 与帧自带的 time 无关 (原版实测)
func test_walk_starts_at_frame_one_and_stand_is_three_ticks():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_f1/a", 0, 0, 4)
	var u := _unit_with("Sprite/test_f1/a", Vector2i(6, 7))
	u.walk([Vector2i(7, 7)], 150.0)
	u._process(0.001)
	eq(u.anim.frame - u.anim.start_frame, 1, "行走第一帧是组内第 1 帧")
	u.play_act(BattleUnit.Act.STAND, BattleUnit.Dir.SOUTH)
	eq(u.anim.tick_override, BattleUnit.STAND_TICKS, "站立每帧 3 tick")
	u.free()
	_unfake("Sprite/test_f1/a")


## 位置随行走帧跳, 不是匀速滑: 横向每帧 +10、竖向每帧 +8 原版像素 (原版实测, 每帧 2 tick = 0.08 秒), 第 3 帧正好到格
func test_position_jumps_with_walk_frames():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_jump/a", 0, 0, 4)
	WalkStyle.override = 1   # 原版步进 (内置缺省是平滑)
	for case in [[Vector2i(7, 7), Vector2(10, 0)], [Vector2i(6, 8), Vector2(0, 8)]]:
		var u := _unit_with("Sprite/test_jump/a", Vector2i(6, 7))
		var p0 := u.position
		u.walk([case[0]], BattleStage.UNIT_WALK_SPEED)
		var seen := []
		for i in 24:   # 0.01 秒一步看 0.24 秒
			u._process(0.01)
			if i in [2, 10, 18]:
				seen.append(u.position - p0)
		eq(seen, [case[1], case[1] * 2, case[1] * 3], "三个行走帧各跳 1/3 格 %s" % case[0])
		u.free()
	WalkStyle.override = -1
	_unfake("Sprite/test_jump/a")


## 没有行走帧的精灵 (014 / 150 / 209 等) 照样有起步收步; 走路时固定显示行走组起点那一帧 (不播站立)
func test_no_walk_frames_still_has_start_end_and_holds_one_frame():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_nw/a", 4, 3, 0)
	var u := _unit_with("Sprite/test_nw/a", Vector2i(6, 7))
	check(u._has_group(2) and u._has_group(3), "move=0 也有起步收步")
	u.walk([Vector2i(7, 7)], 150.0)
	eq(u.act, BattleUnit.Act.MOVE_START, "起步照播")
	for i in 7:
		_tick(u, 0.04)
	eq(u.act, BattleUnit.Act.MOVE, "起步完走路")
	eq(u.anim.end_frame - u.anim.start_frame, 1, "走路固定 1 帧")
	eq(u.anim.start_frame, 3 + 1 * 4, "就是行走组起点 (= 起步组朝南的第 0 帧)")
	u.free()
	_unfake("Sprite/test_nw/a")


## 回站立相位 (原版实测 F, 53 次移动): 第一帧恒为帧 1; 回站立那一刻 tick%3 = 0 → 帧 1 再显示 1 tick, 2 → 帧 1 再显示 2 tick, 1 → 直接第 2 帧显示 3 tick;
## 之后每帧 3 tick, 换帧都落在全局 tick%3==1 的网格上 (所以所有单位同相)
func test_stand_phase_follows_global_three_tick_grid():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_ph/a", 0, 0)   # 站立 1 帧; 这里要多帧站立, 手动改计数
	var A = (Engine.get_main_loop() as SceneTree).root.get_node("Assets")
	var data: Dictionary = A._anims["sprite/test_ph/a"]
	data["action_counts"] = [5, 2, 0, 0, 0]
	while data["frames"].size() < 3 + 4 * 7:
		data["frames"].append({"sound": -1, "time": 2, "hit": 0, "color": 0, "shake": 0, "unk4": 0, "parts": []})
	var cases := {0: [1, 0.03, 2], 1: [2, 0.11, 3], 2: [1, 0.07, 2]}   # tick%3 -> [首帧序号, 该帧还要显示多久, 之后的帧序号]
	for tm in cases:
		var u := _unit_with("Sprite/test_ph/a", Vector2i(6, 7))
		BattleUnit._clock = tm * 0.04 + 0.01
		u.play_act(BattleUnit.Act.STAND, BattleUnit.Dir.SOUTH)
		var base := 3   # 朝南站立组起点
		eq(u.anim.frame, base + cases[tm][0], "tick%%3=%d 回站立首帧" % tm)
		u.anim._process(cases[tm][1] - 0.005)
		eq(u.anim.frame, base + cases[tm][0], "还没到换帧时刻 tick%%3=%d" % tm)
		u.anim._process(0.01)
		eq(u.anim.frame, base + cases[tm][2], "换帧后 tick%%3=%d" % tm)
		u.free()
	_unfake("Sprite/test_ph/a")


## 缺省 (WalkStyle.SMOOTH = true): 位置匀速滑动, 不分步跳; 每格用时不变
func test_smooth_walk_slides_evenly():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_smooth/a", 0, 0, 4)
	WalkStyle.override = 0
	var u := _unit_with("Sprite/test_smooth/a", Vector2i(6, 7))
	var p0 := u.position
	u.walk([Vector2i(7, 7)], BattleStage.UNIT_WALK_SPEED)
	var seen := []
	for i in 24:
		u._process(0.01)
		if i in [4, 9, 14]:
			seen.append(u.position.x - p0.x)
	WalkStyle.override = -1
	check(absf(seen[0] - 6.25) < 0.01 and absf(seen[1] - 12.5) < 0.01 and absf(seen[2] - 18.75) < 0.01, "匀速: %s" % str(seen))
	u.free()
	_unfake("Sprite/test_smooth/a")


## 战场单位每个动作的帧声音都要响 (推进帧时, 只要帧声音有效就 PlaySfx, 与动作无关; 原版 内存对照原版确认):
## 起步 / 收步 (钢破鬼 227 / 刀凛鬼 204 / 殷剑平 等: 起步第 4、7 帧出刀声, 收步收刀声)、站立 (赤炼鬼 169 等)、胜利 (主角升级姿势) 与行走脚步一样。
## 回归: 原先只有行走 (MOVE) 开声, 提 / 放剑匣、出刀 / 收刀的动作全是哑的 (玩家反馈钢破鬼走路出刀没声音)
func test_every_act_plays_its_frame_sound():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	var key := "Sprite/test_snd/a"
	_fake_anim(key)
	var A = (Engine.get_main_loop() as SceneTree).root.get_node("Assets")
	for f in A._anims[key.to_lower()]["frames"]:
		f["sound"] = 0
	var u := _unit_with(key, Vector2i(6, 7))
	u.walk([Vector2i(7, 7)], 150.0)
	eq(u.act, BattleUnit.Act.MOVE_START, "一开始播起步")
	check(u.anim.sfx_count >= 1, "起步帧的声音 (出刀) 响了")
	var guard := 0
	var prev := u.anim.sfx_count
	while u.act != BattleUnit.Act.MOVE_END and guard < 2000:
		prev = u.anim.sfx_count
		_tick(u, 0.01)
		guard += 1
	eq(u.act, BattleUnit.Act.MOVE_END, "到格后播收步")
	check(u.anim.sfx_count > prev, "收步帧的声音 (收刀) 响了")
	while u.act != BattleUnit.Act.STAND and guard < 4000:
		prev = u.anim.sfx_count
		_tick(u, 0.01)
		guard += 1
	eq(u.act, BattleUnit.Act.STAND, "走完回站立")
	check(u.anim.sfx_count > prev, "站立帧的声音 (赤炼鬼的喘息等) 响了")
	prev = u.anim.sfx_count
	u.play_act(BattleUnit.Act.WIN, u.dir)
	check(u.anim.sfx_count > prev, "胜利帧的声音响了")
	u.free()
	_unfake(key)


## 剧情走路: 指令头 +2 = 0 不放起步 / 收步 (原版剧情走路对象 [esi] = 0 直接走), 每帧 速度+1 tick (速度 5 = 6 tick)
func test_script_walk_without_phases_and_slow_frames():
	if not _fake_ok():
		check(true, "无资源, 跳过")
		return
	_fake_anim("Sprite/test_ms/a")
	var u := _unit_with("Sprite/test_ms/a", Vector2i(6, 7))
	var done := [false]
	u.move_finished.connect(func(): done[0] = true)
	u.walk([Vector2i(7, 7)], 250.0 / 6.0, false, false, 6)
	_tick(u, 0.04)
	eq(u.act, BattleUnit.Act.MOVE, "不放起步, 直接走")
	eq(u.anim.tick_override, 6, "每帧 6 tick")
	for i in 30:
		_tick(u, 0.04)
	check(done[0], "18 tick 走完一格")
	eq(u.act, BattleUnit.Act.STAND, "到格直接站立, 不放收步")
	u.free()

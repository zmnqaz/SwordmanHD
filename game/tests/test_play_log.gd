# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 通关录像 (engine/core/play_log.gd): 录制、读档剪辑、回放顺序

const REQUIRES_TEST := {
	"test_game_saves_roundtrip_keeps_the_whole_recording": ["content"]
}

const Router = preload("res://engine/input/input_router.gd")


class Rec:
	extends RefCounted
	var log: Array = []
	func ui_action(a: UiAction) -> bool:
		log.append(a.name())
		return true


func _rec_player() -> Array:
	var r = Router.new()
	var rec := Rec.new()
	r.push(rec)
	var p := PlayLog.new()
	p.mode = "record"
	p.router = r
	p._ready()
	return [p, r, rec]


func _press(r, k: int) -> void:
	r.dispatch(UiAction.of(k, "key"))


func test_record_events_in_order() -> void:
	var x := _rec_player()
	var p: PlayLog = x[0]
	_press(x[1], UiAction.UP)
	p._process(0.5)
	_press(x[1], UiAction.CONFIRM)
	eq(p._events.size(), 2)
	eq(int(p._events[0]["k"]), UiAction.UP)
	check(float(p._events[1]["t"]) >= 0.5)
	PlayLog.current = null


## 模态浮层 (设定 / 攻略面板) 开着时的操作不录: 回放时没有浮层, 录了会落到游戏里
func test_overlay_actions_not_recorded() -> void:
	var x := _rec_player()
	var p: PlayLog = x[0]
	_press(x[1], UiAction.UP)
	var ov := Rec.new()
	x[1].push(ov, true)
	_press(x[1], UiAction.DOWN)
	_press(x[1], UiAction.CANCEL)
	x[1].pop(ov)
	_press(x[1], UiAction.CONFIRM)
	eq(p._events.map(func(e): return UiAction.NAMES[int(e["k"])]), ["up", "confirm"], "浮层里的 down/cancel 不进录像")
	eq(ov.log, ["down", "cancel"], "浮层照常收到")
	PlayLog.current = null


## 攻略面板「整理行囊」(浮层里, 输入不录) 要单独记一条 bag_sort 事件: 录制时按序记下, 回放到这里调 bag_sort_hook; 没在录像时不记
func test_bag_sort_is_recorded_and_replayed() -> void:
	PlayLog.note_bag_sort()   # 没有当前录像: 不报错, 什么都不记
	var x := _rec_player()
	var p: PlayLog = x[0]
	_press(x[1], UiAction.UP)
	var ov := Rec.new()
	x[1].push(ov, true)
	_press(x[1], UiAction.MENU)          # 浮层里按 M 整理: 这个按键本身不录
	PlayLog.note_bag_sort()              # 整理成功后由面板单独记一条
	x[1].pop(ov)
	_press(x[1], UiAction.CONFIRM)
	eq(p._events.map(func(e): return "bag_sort" if e.has("bag_sort") else UiAction.NAMES[int(e["k"])]), ["up", "bag_sort", "confirm"], "整理按事件记在顺序里, 浮层里的按键不记")
	var calls := [0]
	PlayLog.bag_sort_hook = func(): calls[0] += 1
	p._play(p._events[1])
	p._play(p._events[0])
	eq(calls[0], 1, "回放 bag_sort 事件调一次回调, 普通按键不调")
	PlayLog.bag_sort_hook = Callable()
	PlayLog.current = null


func test_load_cuts_abandoned_branch_and_replays_the_good_one() -> void:
	var x := _rec_player()
	var p: PlayLog = x[0]
	_press(x[1], UiAction.UP)          # 存档前
	_press(x[1], UiAction.DOWN)
	PlayLog.note_save("slot", 2)       # 存档点
	_press(x[1], UiAction.LEFT)        # 失败的一段
	_press(x[1], UiAction.LEFT)
	PlayLog.note_load("slot", 2, {"x": 1})   # 读档: 剪掉上面两个 LEFT
	_press(x[1], UiAction.RIGHT)       # 顺利的一段
	_press(x[1], UiAction.CONFIRM)
	var names: Array = []
	for e in p._events:
		if not e.has("load"):
			names.append(UiAction.NAMES[int(e["k"])])
	eq(names, ["up", "down", "right", "confirm"], "录像只留存档之前 + 读档之后的顺利一段")
	check(p._base.is_empty(), "存档是本次录像存的, 不用嵌入起点")
	# 回放: 新的输入层收到同样的顺序
	var r2 = Router.new()
	var rec2 := Rec.new()
	r2.push(rec2)
	var q := PlayLog.new()
	q.mode = "replay"
	q.router = r2
	q._events = p._events.duplicate(true)
	q._ready()
	for i in 20:
		q._process(0.5)
	eq(rec2.log, ["up", "down", "right", "confirm"])
	Engine.time_scale = 1.0
	PlayLog.current = null


func test_load_old_save_becomes_recording_base() -> void:
	var x := _rec_player()
	var p: PlayLog = x[0]
	_press(x[1], UiAction.UP)
	PlayLog.note_load("slot", 0, {"stage": 5})   # 录像开始前的老档
	_press(x[1], UiAction.CONFIRM)
	eq(p._base_kind, "slot")
	eq(int(p._base.get("stage", -1)), 5)
	var kinds: Array = []
	for e in p._events:
		if not e.has("load"):
			kinds.append(int(e["k"]))
	eq(kinds, [UiAction.CONFIRM], "老档之前的操作全部省掉")
	PlayLog.current = null


func test_battle_seed_recorded_and_replayed_in_order() -> void:
	var x := _rec_player()
	var p: PlayLog = x[0]
	eq(PlayLog.seed_for_battle(111), 111)
	eq(PlayLog.seed_for_battle(222), 222)
	var q := PlayLog.new()
	q.mode = "replay"
	q._seeds = p._seeds.duplicate()
	q._ready()
	eq(PlayLog.seed_for_battle(999), 111)
	eq(PlayLog.seed_for_battle(888), 222)
	PlayLog.current = null


func test_stage_segment_exports_clean_path_after_load() -> void:
	var x := _rec_player()
	var p: PlayLog = x[0]
	p.path = "user://replays_test/session.json"
	_press(x[1], UiAction.UP)                    # 这一幕之前的操作 (不进本幕录像)
	PlayLog.stage_begin(7, {"stage": 7, "gold": 100})
	_press(x[1], UiAction.DOWN)
	PlayLog.note_save("battle", 0)              # 战中存档
	_press(x[1], UiAction.LEFT)                 # 之后失败的一段
	PlayLog.note_load("battle", 0, {"game": {"stage": 7}, "battle": {}})
	_press(x[1], UiAction.RIGHT)                # 顺利的一段
	PlayLog.stage_end(7, true)
	var found := ""
	var dir := DirAccess.open("user://replays_test")
	check(dir != null, "导出目录存在")
	if dir != null:
		for f in dir.get_files():
			if f.begins_with("stage_07_"):
				found = "user://replays_test/" + f
	check(found != "", "导出了第 7 幕的单幕录像")
	if found != "":
		var j = JSON.parse_string(FileAccess.get_file_as_string(found))
		eq(String(j["kind"]), "stage")
		eq(int(j["base"]["stage"]), 7)
		var names: Array = []
		for e in j["events"]:
			if not e.has("load"):
				names.append(UiAction.NAMES[int(e["k"])])
		eq(names, ["down", "right"], "本幕录像只留顺利的一段 (之前的 up、放弃的 left 都不在)")
		DirAccess.remove_absolute(found)
	PlayLog.current = null


# ---------------------------------------------------------------- 跨次启动: 存档带着录像历史 (整场录像)

const SIDE_DIR := "user://replays_test"


func _side_path(tag: String) -> String:
	DirAccess.make_dir_recursive_absolute(SIDE_DIR)
	return "%s/save_%s_%d.json" % [SIDE_DIR, tag, Time.get_ticks_usec()]


func _names(p: PlayLog) -> Array:
	var out: Array = []
	for e in p._events:
		if not e.has("load"):
			out.append(UiAction.NAMES[int(e["k"])])
	return out


func _session_a(path: String) -> String:
	## 第一次启动: 玩了 up down, 存档, 又玩了 left (存档之后的, 之后退出); 返回存档里的 replay_id
	var x := _rec_player()
	var p: PlayLog = x[0]
	_press(x[1], UiAction.UP)
	p._process(1.0)
	_press(x[1], UiAction.DOWN)
	var id := PlayLog.begin_save()
	PlayLog.note_save("slot", 3, path)
	_press(x[1], UiAction.LEFT)
	PlayLog.current = null
	return id


func test_save_gets_replay_id_only_while_recording():
	PlayLog.current = null
	eq(PlayLog.begin_save(), "", "没在录像: 存档不带 id")
	var x := _rec_player()
	var id := PlayLog.begin_save()
	check(id != "", "录像中存档带 id")
	check(PlayLog.begin_save() != id, "每次存档 id 不同")
	PlayLog.current = null


func test_loading_a_save_from_an_earlier_session_continues_the_whole_history():
	var path := _side_path("a")
	var id := _session_a(path)
	check(FileAccess.file_exists(path + ".replay"), "存档旁边有录像历史文件")
	# 第二次启动: 读上次的存档接着玩
	var x := _rec_player()
	var p: PlayLog = x[0]
	PlayLog.note_load("slot", 3, {"replay_id": id}, path)
	_press(x[1], UiAction.CONFIRM)
	eq(_names(p), ["up", "down", "confirm"], "整场录像: 上次存档之前的历史接上, 存档之后放弃的 left 不在")
	check(p._base.is_empty(), "从游戏开头录起, 不再以老档为起点")
	check(p._t >= 1.0, "录像时钟接着上次的")
	DirAccess.remove_absolute(path + ".replay")
	PlayLog.current = null


func test_history_chains_across_three_sessions():
	var path := _side_path("c")
	var id := _session_a(path)
	var x := _rec_player()                      # 第二次: 读档, 再玩 right, 再存档
	PlayLog.note_load("slot", 3, {"replay_id": id}, path)
	_press(x[1], UiAction.RIGHT)
	var id2 := PlayLog.begin_save()
	PlayLog.note_save("slot", 3, path)          # 覆盖同一个存档位
	PlayLog.current = null
	var y := _rec_player()                      # 第三次
	var p3: PlayLog = y[0]
	PlayLog.note_load("slot", 3, {"replay_id": id2}, path)
	_press(y[1], UiAction.CONFIRM)
	eq(_names(p3), ["up", "down", "right", "confirm"], "三次启动接成一条")
	DirAccess.remove_absolute(path + ".replay")
	PlayLog.current = null


func test_stale_or_missing_history_falls_back_to_old_behavior():
	var path := _side_path("b")
	var id := _session_a(path)
	var x := _rec_player()
	var p: PlayLog = x[0]
	PlayLog.note_load("slot", 3, {"replay_id": "someone-else", "stage": 5}, path)   # id 对不上: 存档被覆盖过
	_press(x[1], UiAction.CONFIRM)
	eq(_names(p), ["confirm"], "对不上: 老办法, 从这个存档开始")
	eq(p._base_kind, "slot")
	DirAccess.remove_absolute(path + ".replay")
	var y := _rec_player()
	var q: PlayLog = y[0]
	PlayLog.note_load("slot", 3, {"replay_id": id, "stage": 5}, path)               # 旁边的文件没了
	eq(q._base_kind, "slot", "没有历史文件: 老办法")
	PlayLog.current = null
	var z := _rec_player()
	var r: PlayLog = z[0]
	PlayLog.note_load("slot", 3, {"stage": 5}, path)                                 # 老存档没有 id
	eq(r._base_kind, "slot", "老存档 (没有 id): 老办法")
	PlayLog.current = null


func test_battle_save_from_earlier_session_keeps_history_and_stage_start_after_it():
	var path := _side_path("d")
	var id := _session_a(path)
	var x := _rec_player()
	var p: PlayLog = x[0]
	PlayLog.note_load("battle", 0, {"game": {"stage": 7, "replay_id": id}, "battle": {}}, path)
	eq(_names(p), ["up", "down"], "战阵存录同样接上历史")
	eq(int(p._seg["ev0"]), 2, "本幕录像的起点接在历史之后, 不把历史算进单幕")
	DirAccess.remove_absolute(path + ".replay")
	PlayLog.current = null


## 端到端: GameSaves 存档 -> (模拟退出重启) -> GameSaves 读档, 录像历史接上
func test_game_saves_roundtrip_keeps_the_whole_recording():
	var old_dir := GameSaves.base_dir
	GameSaves.base_dir = "user://replays_test/"
	DirAccess.make_dir_recursive_absolute(GameSaves.base_dir)
	var x := _rec_player()
	_press(x[1], UiAction.UP)
	_press(x[1], UiAction.DOWN)
	var st := GameState.new()
	check(GameSaves.save_slot(st, 4), "存档")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(GameSaves.slot_path(4)))
	check(String(saved.get("replay_id", "")) != "", "存档里有 replay_id")
	check(FileAccess.file_exists(GameSaves.slot_path(4) + ".replay"), "旁边有录像历史")
	PlayLog.current = null
	var y := _rec_player()                                   # 重启后
	var p: PlayLog = y[0]
	var r := GameSaves.load_slot(GameState.new(), 4)
	check(r.ok, "读档")
	_press(y[1], UiAction.CONFIRM)
	eq(_names(p), ["up", "down", "confirm"], "读档续玩: 录像是整场")
	check(p._base.is_empty(), "不以存档为起点")
	for f in [GameSaves.slot_path(4), GameSaves.slot_path(4) + ".replay", GameSaves.slot_path(4) + ".bak"]:
		DirAccess.remove_absolute(f)
	GameSaves.base_dir = old_dir
	PlayLog.current = null


func test_replay_locks_live_input_until_it_ends():
	var r = Router.new()
	var q := PlayLog.new()
	q.mode = "replay"
	q.router = r
	q._events = [{"t": 0.1, "k": UiAction.UP}]
	q._ready()
	eq(r.replay_lock, true, "回放开始: 锁住真实输入")
	for i in 5:
		q._process(0.5)
	eq(r.replay_lock, false, "放完: 解锁, 可以接着手动玩")
	Engine.time_scale = 1.0
	PlayLog.current = null
	r.free()


func test_stopping_a_replay_unlocks_input():
	var r = Router.new()
	var q := PlayLog.new()
	q.mode = "replay"
	q.router = r
	q._events = [{"t": 100.0, "k": UiAction.UP}]
	q._ready()
	eq(r.replay_lock, true)
	PlayLog.stop_current()
	eq(r.replay_lock, false, "结束回放: 解锁")
	Engine.time_scale = 1.0
	r.free()


# ---------------------------------------------------------------- 回放放完 / 结束后接着玩: 继续录像 (不然之后存的档没有录像历史, 下次读档录像就改成从该存档开始)

func _finished_replay(events: Array, seeds: Array, router) -> PlayLog:
	var q := PlayLog.new()
	q.mode = "replay"
	q.router = router
	q._events = events
	q._seeds = seeds
	q._meta = {"viewport": [1280, 720]}
	q._ready()
	for i in 20:
		q._process(0.5)
	Engine.time_scale = 1.0
	return q


func test_finished_replay_continues_as_one_recording() -> void:
	var r = Router.new()
	var rec := Rec.new()
	r.push(rec)
	var q := _finished_replay([{"t": 0.1, "k": UiAction.UP}, {"t": 0.2, "k": UiAction.DOWN}], [111], r)
	check(q._finished, "放完了")
	check(PlayLog.current == null, "放完后没有在录")
	eq(PlayLog.begin_save(), "", "没在录: 这时存的档不带录像历史 (这就是旧问题)")
	var c := q.continuation()
	c.router = r
	c._ready()
	check(PlayLog.current == c, "接着录")
	_press(r, UiAction.CONFIRM)
	eq(_names(c), ["up", "down", "confirm"], "新录像 = 放过的整段 + 之后手动玩的")
	eq(c._seeds, [111], "战斗种子接着")
	check(c._t >= q._t, "录像时钟接着放完的时刻")
	check(c.path != q.path or q.path == "", "新文件, 不覆盖被放的录像")
	var id := PlayLog.begin_save()
	check(id != "", "之后存的档带录像历史")
	PlayLog.current = null
	r.free()


func test_save_after_replay_then_new_session_loads_whole_game() -> void:
	var r = Router.new()
	var q := _finished_replay([{"t": 0.1, "k": UiAction.UP}], [], r)
	var c := q.continuation()
	c.router = r
	c._ready()
	_press(r, UiAction.DOWN)
	var path := _side_path("replay_then_play")
	var id := PlayLog.begin_save()
	PlayLog.note_save("battle", 0, path)
	PlayLog.current = null
	var y := _rec_player()                       # 重启后读这个存档
	var p: PlayLog = y[0]
	PlayLog.note_load("battle", 0, {"game": {"stage": 3, "replay_id": id}, "battle": {}}, path)
	eq(_names(p), ["up", "down"], "放过的段 + 放完后玩的段, 整场")
	check(p._base.is_empty(), "不是从存档起算")
	DirAccess.remove_absolute(path + ".replay")
	PlayLog.current = null
	r.free()


func test_fresh_recording_after_stopping_a_replay_starts_at_title() -> void:
	var f := PlayLog.fresh()
	eq(f.mode, "record")
	check(bool(f._meta.get("title_start", false)), "标记从标题起录 (回放时直接进标题, 不放 logo 动画)")
	check(f._events.is_empty())
	f.free()
	var l := PlayLog.new()
	l.mode = "replay"
	l._meta = {"title_start": true}
	PlayLog.current = l
	check(PlayLog.title_start(), "回放这种录像: 起点是标题画面")
	l._meta = {}
	check(not PlayLog.title_start(), "普通录像不是")
	PlayLog.current = null
	l.free()


# ---------------------------------------------------------------- 进程内回放 (菜单入口)

func _write_replay(events: Array) -> String:
	var p := "user://test_replay_%d.json" % Time.get_ticks_usec()
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": PlayLog.VERSION, "kind": "play", "meta": {}, "duration": 1.0, "seeds": [], "checkpoints": [], "events": events}))
	f.close()
	return p


func _rm(p: String) -> void:
	DirAccess.remove_absolute(p)


func test_open_replay_ok_and_bad_file() -> void:
	var p := _write_replay([{"t": 0.1, "k": UiAction.UP}])
	var l := PlayLog.open_replay(p, 2.0)
	check(l != null, "好文件能打开")
	eq(l.mode, "replay")
	eq(l.speed, 2.0)
	l.free()
	eq(PlayLog.open_replay("user://no_such_replay.json", 1.0), null, "不存在 -> null")
	var bad := "user://test_bad_replay.json"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	eq(PlayLog.open_replay(bad, 1.0), null, "版本不对 -> null")
	_rm(p)
	_rm(bad)


func test_step_speed_stops_at_ends() -> void:
	eq(PlayLog.step_speed(1.0, 1), 2.0)
	eq(PlayLog.step_speed(1.0, -1), 0.5)
	eq(PlayLog.step_speed(0.5, -1), 0.5, "最低档停住")
	eq(PlayLog.step_speed(16.0, 1), 16.0, "最高档停住")
	eq(PlayLog.step_speed(3.0, 1), 4.0, "不在档位上: 先取最近档再挪")


func test_speed_text() -> void:
	eq(PlayLog.speed_text(2.0), "×2")
	eq(PlayLog.speed_text(0.5), "×0.5")


## 游戏速度 (设定) 与回放: 回放中 time_scale 归回放自己管, 设定里的倍数只记下, 回放结束 / 被停掉后还原
func test_replay_restores_game_speed() -> void:
	var p := _write_replay([{"t": 100.0, "k": UiAction.UP}])
	GameSpeed.set_tenths(15)
	eq(Engine.time_scale, 1.5, "平时按游戏速度")
	var l := PlayLog.open_replay(p, 2.0)
	l._ready()
	eq(Engine.time_scale, 2.0, "回放用回放自己的速度, 不叠加游戏速度")
	GameSpeed.set_tenths(20)
	eq(Engine.time_scale, 2.0, "回放中改游戏速度只记下, 不动 time_scale")
	PlayLog.stop_current()
	eq(Engine.time_scale, 2.0, "回放结束还原成设定的游戏速度 (2.0)")
	GameSpeed.set_tenths(10)
	eq(Engine.time_scale, 1.0)
	_rm(p)


func test_set_speed_only_while_replaying_and_clamps() -> void:
	var p := _write_replay([{"t": 100.0, "k": UiAction.UP}])
	PlayLog.set_speed(4.0)
	eq(Engine.time_scale, 1.0, "没有回放时不动 time_scale")
	var l := PlayLog.open_replay(p, 1.0)
	l._ready()
	check(PlayLog.replaying())
	PlayLog.set_speed(4.0)
	eq(Engine.time_scale, 4.0)
	PlayLog.set_speed(99.0)
	eq(Engine.time_scale, 16.0, "夹到最高档")
	PlayLog.set_speed(0.01)
	eq(Engine.time_scale, 0.5, "夹到最低档")
	PlayLog.stop_current()
	eq(Engine.time_scale, 1.0, "stop_current 还原倍速")
	eq(PlayLog.current, null)
	check(not PlayLog.replaying())
	_rm(p)


func test_replay_redirects_saves_to_sandbox_and_restores() -> void:
	var p := _write_replay([{"t": 100.0, "k": UiAction.UP}])
	var real := GameSaves.base_dir
	var l := PlayLog.open_replay(p, 1.0)
	l._ready()
	eq(GameSaves.base_dir, PlayLog.REPLAY_SAVE_DIR, "回放期间存档写沙盒")
	PlayLog.stop_current()
	eq(GameSaves.base_dir, real, "结束后恢复真实目录")
	_rm(p)


func test_replay_clock_freezes_while_overlay_open() -> void:
	var r = Router.new()
	var p := _write_replay([{"t": 100.0, "k": UiAction.UP}])
	var l := PlayLog.open_replay(p, 4.0)
	l.router = r
	l._ready()
	eq(Engine.time_scale, 4.0)
	var ov := Rec.new()
	r.push(ov, true)
	l._process(0.1)
	eq(Engine.time_scale, 0.0, "模态浮层开着: 时间冻结 (回放事件不会落进浮层)")
	r.pop(ov)
	l._process(0.1)
	eq(Engine.time_scale, 4.0, "浮层关了: 恢复倍速")
	PlayLog.stop_current()
	r.free()
	_rm(p)


func test_replay_finish_restores_everything_and_signals() -> void:
	var r = Router.new()
	var rec := Rec.new()
	r.push(rec)
	var p := _write_replay([{"t": 0.0, "k": UiAction.UP}])
	var real := GameSaves.base_dir
	var l := PlayLog.open_replay(p, 8.0)
	l.router = r
	l._ready()
	var done := [false]
	l.replay_finished.connect(func(): done[0] = true)
	l._process(0.1)
	eq(rec.log, ["up"], "事件按时钟送出")
	check(done[0], "发 replay_finished")
	eq(Engine.time_scale, 1.0, "放完倍速 1x")
	eq(GameSaves.base_dir, real, "放完恢复真实存档目录")
	eq(PlayLog.current, null, "放完不再占着 current (之后手动玩的战斗不再取录像种子)")
	l.free()
	r.free()
	_rm(p)


func _read_json(file: String) -> Dictionary:
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if j is Dictionary else {}


## 自动存盘在后台线程写: 文件内容是触发那一刻的快照, 之后继续录不会影响它; 写完才能再启动下一次
func test_autosave_runs_in_background_and_writes_a_snapshot() -> void:
	var x := _rec_player()
	var p: PlayLog = x[0]
	p.path = "user://playlog_async_test_%d.json" % Time.get_ticks_usec()
	for i in 50:
		_press(x[1], UiAction.UP)
	p._process(PlayLog.AUTOSAVE_SEC + 0.1)   # 到点: 触发后台存盘
	for i in 30:
		_press(x[1], UiAction.DOWN)            # 存盘期间主线程继续录
	p._wait_save()
	var j := _read_json(p.path)
	eq((j.get("events", []) as Array).size(), 50, "文件是触发时刻的快照 (50 个), 不含之后录的 30 个")
	eq(p._events.size(), 80)
	check(int(j.get("version", 0)) == PlayLog.VERSION, "是完整的录像 JSON")
	check(not FileAccess.file_exists(p.path + ".tmp"), "临时文件已改名")
	p.save()   # 同步存盘拿到全部
	eq(((_read_json(p.path)).get("events", []) as Array).size(), 80)
	DirAccess.remove_absolute(p.path)
	PlayLog.current = null


## 关窗时 WM_CLOSE_REQUEST / _exit_tree / PREDELETE 连着调 save(): 内容没变就不重写第二遍 (大录像每遍几百毫秒), 内容变了照写
func test_repeated_save_is_skipped_until_something_changes() -> void:
	var x := _rec_player()
	var p: PlayLog = x[0]
	p.path = "user://playlog_dedupe_test_%d.json" % Time.get_ticks_usec()
	_press(x[1], UiAction.UP)
	p.save()
	var m0 := FileAccess.get_modified_time(p.path)
	var stamp := FileAccess.open(p.path, FileAccess.READ).get_as_text()
	p.save()   # 内容没变: 跳过
	eq(FileAccess.open(p.path, FileAccess.READ).get_as_text(), stamp, "没变化时文件不动")
	_press(x[1], UiAction.DOWN)
	p.save()   # 变了: 照写
	eq(((_read_json(p.path)).get("events", []) as Array).size(), 2, "有新操作时重新写")
	check(m0 > 0)
	DirAccess.remove_absolute(p.path)
	PlayLog.current = null

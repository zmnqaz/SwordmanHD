# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 存档界面的「游戏时间 / 总回合」(复刻新增统计, GameState.play_time / turns):
## 累计规则、存读档往返 (存档位 + 战阵存录)、旧存档没有字段时的显示与补算、关卡结束 0x02 累加回合不重复计

const ClearRank = preload("res://engine/rules/clear_rank.gd")
const CampScene := preload("res://engine/camp/camp_scene.gd")
const TitleScene := preload("res://scripts/title_scene.gd")

const REQUIRES_TEST := {"test_save_load_roundtrip_slot_and_battle": ["content"]}   # 存档格摘要要核对存档里的内容包

static var DIR: String = tmp_dir("test_play_stats/")


class FakeRules extends RefCounted:
	var ctx := {"params": Params.new()}


class FakeCtl extends RefCounted:
	var rules := FakeRules.new()


class FakeScene extends RefCounted:
	var gc := GameContext.new()
	var ctl := FakeCtl.new()
	var turn := 0


func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)


func _d(vals: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(vals.size() * 2)
	for i in vals.size():
		b.encode_s16(i * 2, vals[i])
	return b


func test_add_and_reset():
	var s := GameState.new()
	eq([s.play_time, s.turns], [0.0, 0], "新状态从 0 起")
	s.add_play_time(1.5)
	s.add_play_time(-3.0)
	s.add_turns(12)
	s.add_turns(-1)
	eq([s.play_time, s.turns], [1.5, 12], "累加 (负数不计)")
	s.reset(5)
	eq([s.play_time, s.turns], [0.0, 0], "新游戏清零")


func test_unknown_stays_unknown_or_backfills():
	var s := GameState.new()
	s.apply_dict({"stage": 3, "next_stage": 4, "gold": 1, "bag": [], "game_data": {"31": 18, "32": 9}, "party": {}})
	eq([s.play_time, s.turns], [-1.0, -1], "旧存档没字段 = 未知")
	s.add_play_time(10.0)
	eq(s.play_time, -1.0, "未知的游戏时间不从 0 起算冒充总时间")
	var d := s.to_dict()
	check(not d.has("play_time") and not d.has("turns"), "未知的不写进存档 (读回仍未知)")
	s.add_turns(5, -1)
	eq(s.turns, -1, "补不出 (内容包不记录) 保持未知")
	s.add_turns(5, 27)
	eq(s.turns, 32, "旧档第一次打完一关: 先用原版过关回合记录补出此前之和, 再加本关")


func test_recorded_turns_reads_clear_rank_vars():
	var p = Params.new()
	var gd := {31: 18, 32: 9, 54: 51, 65: 99, 20: 7}
	eq(ClearRank.recorded_turns(func(v): return gd.get(v, 0), p), 78, "只加变量 30~64 (序号 A+B+C+D)")
	eq(ClearRank.recorded_turns(func(v): return gd.get(v, 0), Params.new({"turn_record_base": -1})), -1, "不记录的内容包补不出")


func test_slot_text_formats():
	eq(CampSaveWindow.play_time_text(0.0), "0:00")
	eq(CampSaveWindow.play_time_text(59.9), "0:00")
	eq(CampSaveWindow.play_time_text(3600.0 * 12 + 34 * 60 + 5), "12:34")
	eq(CampSaveWindow.play_time_text(3600.0 * 123456), "9999:59", "封顶")
	eq(CampSaveWindow.play_time_text(-1.0), UiStrings.t("camp.save.unknown"), "未知显示 --")
	eq(CampSaveWindow.turns_text({"turns": 321.0, "game_data": {"31": 5}}), "321", "有字段用字段")
	eq(CampSaveWindow.turns_text({"game_data": {"31": 18.0, "32": 9.0}}), "27", "旧存档用过关回合记录补")
	eq(CampSaveWindow.turns_text({"game_data": {}}), "0", "没有记录 = 0 回合")
	eq(CampSaveWindow.turns_text({}), UiStrings.t("camp.save.unknown"), "连剧情变量都没有显示 --")


## 关卡结束 0x02: 总回合 += 本关回合, 过关回合记录 (var 30+next) 照旧; 同一 VM 再次执行 (ended 后) 不重复加
func test_stage_over_adds_turns_once():
	var sc := FakeScene.new()
	var vm := EventVM.new(sc)
	vm.log_enabled = false
	vm.gc = sc.gc
	sc.gc.state.turns = 40
	sc.turn = 18
	vm._ops[0x02].call(0x02, _d([-1, 1, 1]))
	eq(sc.gc.state.turns, 58, "加上本关 18 回合")
	eq(sc.gc.state.get_data(31), 18, "原版过关回合记录不变 (var 30+next)")
	vm._ops[0x02].call(0x02, _d([-1, 1, 1]))
	eq(sc.gc.state.turns, 58, "已结束不再加")
	vm.free()
	# 旧存档 (未知) 打完一关: 补算此前各关 + 本关, 本关的记录不算两次
	var sc2 := FakeScene.new()
	var vm2 := EventVM.new(sc2)
	vm2.log_enabled = false
	vm2.gc = sc2.gc
	sc2.gc.state.apply_dict({"stage": 2, "next_stage": 3, "gold": 1, "bag": [], "game_data": {"31": 18, "32": 9}, "party": {}})
	sc2.turn = 11
	vm2._ops[0x02].call(0x02, _d([-1, 3, 3]))
	eq(sc2.gc.state.turns, 38, "18 + 9 + 本关 11")
	vm2.free()


func test_save_load_roundtrip_slot_and_battle():
	var old_dir := GameSaves.base_dir
	GameSaves.base_dir = DIR
	_clean()
	var st := GameState.new()
	st.stage = 3
	st.next_stage = 4
	st.party = {0: {"lv": 7}}
	st.play_time = 3725.25
	st.turns = 88
	check(GameSaves.save_slot(st, 0), "存档")
	var info := CampSaveWindow.slot_info(0)
	eq([info["turns"], info["play_time"]], ["88", "1:02"], "存档格摘要")
	var b := GameState.new()
	b.play_time = 5.0
	b.turns = 1
	check(GameSaves.load_slot(b, 0).ok, "读档")
	eq([b.play_time, b.turns], [3725.25, 88], "读档回到存档值, 之后从这里接着累计")
	check(GameSaves.save_battle(st, {"turn": 3}), "战阵存录")
	var raw = SaveFile.load_file(GameSaves.battle_path(), "battle")
	eq([raw.data["game"]["play_time"], int(raw.data["game"]["turns"])], [3725.25, 88], "战阵存录带上两项")
	# 旧存档: 删掉两项再读, 摘要显示 --(时间) / 补算 (回合)
	var d: Dictionary = SaveFile.load_file(GameSaves.slot_path(0), "game").data
	d.erase("play_time")
	d.erase("turns")
	d["game_data"] = {"31": 18, "32": 9}
	check(SaveFile.write_json(GameSaves.slot_path(1), d), "写旧格式档")
	info = CampSaveWindow.slot_info(1)
	eq([info["turns"], info["play_time"]], ["27", UiStrings.t("camp.save.unknown")], "旧存档摘要不报错")
	check(GameSaves.load_slot(b, 1).ok, "旧存档能读")
	eq([b.play_time, b.turns], [-1.0, -1], "读旧存档 = 未知")
	_clean()
	GameSaves.base_dir = old_dir


## 组装层计时 (scripts/game.gd _count_play_time): 只在游玩画面计, 按真实时间; 标题 / 失焦 / 浮层开着不计
func test_game_counts_real_time_only_in_play():
	var old_cur = Game.current
	var old_state: GameState = Game.state
	var old_scale := Engine.time_scale
	var s := GameState.new()
	Game.state = s
	var camp := CampScene.new()
	var title := TitleScene.new()
	Game.current = camp
	Engine.time_scale = 2.0
	Game._count_play_time(0.4)   # 2 倍速下 delta 0.4 = 真实 0.2 秒
	check(absf(s.play_time - 0.2) < 1e-6, "加速按真实时间计 (%s)" % s.play_time)
	Engine.time_scale = 1.0
	Game._count_play_time(30.0)
	check(absf(s.play_time - 0.2 - Game.PLAY_TIME_MAX_STEP) < 1e-6, "超长帧封顶")
	var t := s.play_time
	Game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	Game._count_play_time(0.1)
	eq(s.play_time, t, "失焦 (后台) 不计")
	Game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	Game.current = title
	Game._count_play_time(0.1)
	eq(s.play_time, t, "标题画面不计")
	Game.current = camp
	var overlay := RefCounted.new()
	InputRouter.push(overlay, true)
	Game._count_play_time(0.1)
	InputRouter.pop(overlay)
	eq(s.play_time, t, "浮层 (设定面板等) 开着不计")
	Game._count_play_time(0.1)
	check(absf(s.play_time - t - 0.1) < 1e-6, "关掉浮层接着计")
	Engine.time_scale = old_scale
	Game.current = old_cur
	Game.state = old_state
	camp.free()
	title.free()

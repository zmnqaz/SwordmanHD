# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 存档健壮性模糊测试 (固定种子, 可复现): 截断、字段类型被改坏、字段被删的存档/存录读进来,
## 必须是「读入成功且状态自洽」或「拒绝并给出提示、游戏状态一字不动」, 绝不能脚本报错或读成半截状态。
## 存档目录临时指向 user://test_save_fuzz, 不碰玩家真存档。
const REQUIRES_TEST := {
	"test_battle_save_fuzz": ["content"],
	"test_scene_range_error": ["content"],
	"test_slot_roundtrip_state_equal": ["content"],
	"test_stage_out_of_range_rejected": ["content"],
	"test_title_recovers_after_failed_battle_load": ["original", "content"],
	"test_truncated_slot_uses_backup": ["content"]
}  # 个别方法的依赖 (同上)

const DIR := "user://test_save_fuzz/"
const BattleScene := preload("res://engine/battle/battle_scene.gd")


func _good_state() -> GameState:
	var st := GameState.new()
	st.stage = 3
	st.next_stage = 4
	st.camp_no = 3
	st.gold = 1234
	st.bag = [1, 2, 3]
	st.game_data = {5: 1, 9: 7}
	st.seeded = {0: true, 1: true}
	st.party = {0: {"lv": 7, "exp": 12, "hp_max": 90, "mp_max": 40, "stats": {"atk": 10}, "gear": {"weapon": 1}, "items": [1, 2, -1]},
		1: {"lv": 5, "exp": 3, "hp_max": 70, "mp_max": 30, "stats": {"atk": 8}, "gear": {}, "items": []}}
	return st


func _snapshot(st: GameState) -> Dictionary:
	var d := st.to_dict()
	d["where"] = "camp"
	d["time"] = "2026-10-05 13:00:00"
	d["content"] = Content.signature()
	d["version"] = SaveFile.VERSION
	return JSON.parse_string(JSON.stringify(d))   # 走一遍 JSON, 键变字符串、数字变 float, 同真实读回


func _battle_snapshot() -> Dictionary:
	return {"turn": 2, "layers": [0], "cam": [10.0, 20.0],
		"objs1": {"3": {"visible": true, "playing": false, "frame": 0, "dir": "Stage/a", "x": 1.0, "y": 2.0}},
		"units": [{"dir": 0, "shown": true, "summon_flag": -1, "st": {"hp": 30, "x": 1, "y": 2}}],
		"ctl": {"map_events": [1, 2]}}


func _write(name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)


## 随机改坏一处: 沿随机路径走到某节点, 换成别的类型的值或删掉
func _mutate(d: Variant, rng: RandomNumberGenerator) -> Variant:
	var root = d.duplicate(true)
	var node = root
	for _i in 8:
		var keys: Array = node.keys() if node is Dictionary else range(node.size())
		if keys.is_empty():
			break
		var k = keys[rng.randi() % keys.size()]
		var child = node[k]
		if (child is Dictionary or child is Array) and rng.randi() % 3 != 0:
			node = child
			continue
		var junk: Array = [null, "x", "12", 1.5, -7, 99999999, [], {}, [1, "a"], {"a": 1}, true, 1e30]
		if node is Dictionary and rng.randi() % 4 == 0:
			node.erase(k)
		else:
			node[k] = junk[rng.randi() % junk.size()]
		break
	return root


func test_slot_load_never_half_applies():
	var old_dir := GameSaves.base_dir
	GameSaves.base_dir = DIR
	_clean()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	var good := _snapshot(_good_state())
	var ok_n := 0
	var rej_n := 0
	for i in 600:
		var m = _mutate(good, rng)
		if i % 3 != 0:  # 三分之二用旧版本存档作底 (v0 无 version / v1 无 items), 一起过迁移
			m.erase("content" if i % 3 == 1 else "version")
			if i % 3 == 1:
				m["version"] = 1
			var pm = m.get("party")
			if pm is Dictionary:
				for k in pm:
					if pm[k] is Dictionary:
						pm[k].erase("items")
		_write("save1.json", JSON.stringify(m))
		DirAccess.remove_absolute(DIR + "save1.json.bak")
		var st := GameState.new()
		st.gold = 777
		var before := JSON.stringify(st.to_dict())
		var r := GameSaves.load_slot(st, 0)
		CampSaveWindow.slot_info(0)   # 存档位摘要同样不能因坏档脚本报错
		if r.ok:
			ok_n += 1
			eq(GameState.validate_dict(st.to_dict()), "", "读入成功后状态自洽 #%d" % i)
		else:
			rej_n += 1
			eq(JSON.stringify(st.to_dict()), before, "拒绝读取时状态不变 #%d" % i)
			check(r.error != "" or r.missing, "拒绝时有提示 #%d" % i)
	check(ok_n > 0 and rej_n > 0, "两种结果都出现过 (ok=%d rej=%d)" % [ok_n, rej_n])
	GameSaves.base_dir = old_dir


func test_truncated_slot_uses_backup():
	var old_dir := GameSaves.base_dir
	GameSaves.base_dir = DIR
	_clean()
	var st := _good_state()
	check(GameSaves.save_slot(st, 0), "存档")
	check(GameSaves.save_slot(st, 0), "再存一次, 留下 .bak")
	var text := FileAccess.get_file_as_string(DIR + "save1.json")
	for cut in [0, 1, text.length() / 2, text.length() - 1]:
		_write("save1.json", text.substr(0, cut))
		var t := GameState.new()
		var r := GameSaves.load_slot(t, 0)
		check(r.ok, "正式文件截断 %d 字节, 回退 .bak 读入" % cut)
		eq(t.gold, 1234, "回退读到的内容正确")
	DirAccess.remove_absolute(DIR + "save1.json.bak")   # 备份也没了: 报损坏, 状态不动
	var t2 := GameState.new()
	t2.gold = 5
	var r2 := GameSaves.load_slot(t2, 0)
	check(not r2.ok and r2.error != "", "没有备份时报损坏")
	eq(t2.gold, 5, "状态不动")
	_write("save1.json", "")
	DirAccess.remove_absolute(DIR + "save1.json.bak")
	check(not GameSaves.load_slot(GameState.new(), 0).ok, "空文件")
	GameSaves.base_dir = old_dir


func test_stage_out_of_range_rejected():
	var old_dir := GameSaves.base_dir
	GameSaves.base_dir = DIR
	GameSaves.stage_limit = 36
	_clean()
	var d := _snapshot(_good_state())
	d["stage"] = 999
	_write("save1.json", JSON.stringify(d))
	var st := GameState.new()
	var r := GameSaves.load_slot(st, 0)
	check(not r.ok and r.error.contains("超出"), "关卡编号越界拒绝读取")
	eq(st.stage, 0, "状态不动")
	GameSaves.stage_limit = 0
	GameSaves.base_dir = old_dir


func test_battle_save_fuzz():
	var old_dir := GameSaves.base_dir
	GameSaves.base_dir = DIR
	_clean()
	var st0 := _good_state()
	check(GameSaves.save_battle(st0, _battle_snapshot()), "存战阵")
	var st := GameState.new()
	var r := GameSaves.load_battle(st, BattleScene.validate_snapshot)
	check(r.ok, "好的存录能读")
	eq(BattleScene.validate_snapshot(_battle_snapshot()), "")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var good := _battle_snapshot()
	var rejected := 0
	for i in 300:
		var m = _mutate(good, rng)
		var msg := BattleScene.validate_snapshot(m)
		if msg != "":
			rejected += 1
	check(rejected > 50, "改坏的快照多数被拒 (%d/300)" % rejected)
	# 整个存录文件的随机改坏: 读入要么成功要么拒绝, 状态不半截
	var full = JSON.parse_string(FileAccess.get_file_as_string(DIR + "battle.json"))
	for i in 200:
		var m = _mutate(full, rng)
		_write("battle.json", JSON.stringify(m))
		DirAccess.remove_absolute(DIR + "battle.json.bak")
		var t := GameState.new()
		t.gold = 777
		var before := JSON.stringify(t.to_dict())
		var rr := GameSaves.load_battle(t, BattleScene.validate_snapshot)
		if rr.ok:
			eq(GameState.validate_dict(t.to_dict()), "", "存录读入后状态自洽 #%d" % i)
			eq(BattleScene.validate_snapshot(rr.battle), "", "存录快照自洽 #%d" % i)
		else:
			eq(JSON.stringify(t.to_dict()), before, "存录被拒时状态不变 #%d" % i)
	GameSaves.base_dir = old_dir


## 回归: 战阵存录里的地图事件号读回是 float, 以前按字符串比较, 读档后全部事件被当成已触发
func test_resume_map_events_survive_json():
	var saved: Array = JSON.parse_string(JSON.stringify([1, 2, 7]))
	eq(BattleFlow.events_taken_since([1, 2, 3, 7], saved), [3], "只有存档前已触发的 (3) 被收走")
	eq(BattleFlow.events_taken_since([1, 2], saved), [], "都没触发过")
	eq(BattleFlow.events_taken_since([1, 2], []), [1, 2], "存档时已全部触发")


## 存档 -> 读档后, 全局状态逐字段一致 (用回归记录的摊平口径: 整数/浮点/键类型差异都会暴露)
func test_slot_roundtrip_state_equal():
	var old_dir := GameSaves.base_dir
	GameSaves.base_dir = DIR
	_clean()
	var a := _good_state()
	check(GameSaves.save_slot(a, 2), "存档")
	var b := GameState.new()
	var r := GameSaves.load_slot(b, 2)
	check(r.ok, "读档")
	var fa := {}
	var fb := {}
	RegressLog.flatten(a.regress_state(), "g", fa)
	RegressLog.flatten(b.regress_state(), "g", fb)
	eq(fb, fa, "读档后状态与存档前一致")
	check(fa.size() > 20, "比对了足够多的字段 (%d)" % fa.size())
	GameSaves.base_dir = old_dir


## 回归: 标题「战阵重现」读不了存录 (损坏/不兼容) 后, 标题必须恢复可操作 (以前 _busy 一直为真, 所有输入被吞, 只能重启)
func test_title_recovers_after_failed_battle_load():
	var old_dir := GameSaves.base_dir
	GameSaves.base_dir = DIR
	_clean()
	_write("battle.json", '{"game": {}, "battle": 5}')
	var title = load("res://scripts/title_scene.gd").new()
	Engine.get_main_loop().root.add_child(title)
	title.selection = 2
	await title._confirm()
	check(not title._busy, "读存录失败后标题恢复可操作")
	title.queue_free()
	InputRouter.pop(title)
	GameSaves.base_dir = old_dir


## 越界的 --scene 编号给出提示而不是每帧断言; 合法编号不受影响
func test_scene_range_error():
	var Gm = load("res://scripts/game.gd")
	var n := Content.stage_count()
	check(Gm.scene_range_error("stage%d" % n) != "", "关卡越界")
	check(Gm.scene_range_error("rpg%d" % Content.town_count()) != "", "城镇越界")
	eq(Gm.scene_range_error("stage0"), "", "合法关卡")
	eq(Gm.scene_range_error("title"), "", "非编号场景")
	eq(Gm.scene_range_error("camp99"), "", "营地不查")

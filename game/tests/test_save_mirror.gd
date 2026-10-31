# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 存档镜像 (engine/core/save_mirror.gd): 本地存档同步一份到公开目录, 外部换进来的存档按内容指纹识别并导入

const ROOT := "user://test_save_mirror"
var _local := ROOT + "/local"
var _mirror := ROOT + "/mirror"


func _reset() -> void:
	_rm(ROOT)
	DirAccess.make_dir_recursive_absolute(_local)
	DirAccess.make_dir_recursive_absolute(_mirror)


func _rm(d: String) -> void:
	if not DirAccess.dir_exists_absolute(d):
		return
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	for s in DirAccess.get_directories_at(d):
		_rm(d.path_join(s))
	DirAccess.remove_absolute(d)


func _game(gold: int) -> Dictionary:
	return {"version": SaveFile.VERSION, "stage": 3, "next_stage": 4, "gold": gold, "bag": [1, 2], "game_data": {"5": 1}, "party": {"0": {"lv": 7}}, "seeded": [], "where": "camp", "time": "", "content": SaveFile.SaveMigrations.DEFAULT_CONTENT}


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _gold(path: String) -> int:
	return int(JSON.parse_string(FileAccess.get_file_as_string(path))["gold"])


func _ours(gold: int) -> void:
	SaveFile.write_json(_local + "/save1.json", _game(gold))
	SaveMirror.push(_local, _mirror, "save1.json")


func test_push_mirrors_the_file():
	_reset()
	check(not SaveMirror.push(_local, _mirror, "save1.json"), "本地没有存档: 不镜像")
	_ours(100)
	eq(_gold(_mirror + "/save1.json"), 100, "镜像里是同样的内容")
	eq(FileAccess.get_md5(_mirror + "/save1.json"), FileAccess.get_md5(_local + "/save1.json"), "字节一致")
	check(DirAccess.get_files_at(_mirror).size() == 1, "镜像目录不留临时文件")


func test_own_mirror_is_not_imported():
	_reset()
	_ours(100)
	SaveFile.write_json(_local + "/save1.json", _game(150))   # 本地被改 (不经镜像): 镜像仍是游戏自己写的旧版本, 不能反向覆盖本地
	var r := SaveMirror.pull(_local, _mirror)
	check(r.imported.is_empty() and r.rejected.is_empty(), "指纹和记录一致 = 自己写的, 不导入")
	eq(_gold(_local + "/save1.json"), 150, "本地存档不变")


func test_replaced_mirror_is_imported_even_if_older():
	_reset()
	_ours(100)
	_write(_mirror + "/save1.json", JSON.stringify(_game(777)))   # 玩家 adb push 换进来的 (文件时间不比本地新也要生效)
	var r := SaveMirror.pull(_local, _mirror)
	eq(r.imported, ["save1.json"], "导入被换过的存档")
	eq(_gold(_local + "/save1.json"), 777, "本地存档被覆盖")
	eq(_gold(_local + "/save1.json.bak"), 100, "旧存档留作 .bak")
	eq(SaveMirror.pull(_local, _mirror).imported.size(), 0, "导入后再同步不重复导入")
	_ours(800)
	eq(_gold(_mirror + "/save1.json"), 800, "之后游戏存档照常刷新镜像")
	eq(SaveMirror.pull(_local, _mirror).imported.size(), 0, "刷新后的镜像仍视为自己写的")


func test_new_slot_can_be_imported():
	_reset()
	_write(_mirror + "/save3.json", JSON.stringify(_game(55)))   # 本地该槽位原本是空的
	var r := SaveMirror.pull(_local, _mirror)
	eq(r.imported, ["save3.json"], "空槽位也能换进去")
	eq(_gold(_local + "/save3.json"), 55)
	check(not FileAccess.file_exists(_local + "/save3.json.bak"), "原来没有存档就没有 .bak")


func test_bad_files_are_rejected_and_left_alone():
	_reset()
	_ours(100)
	var bad := {
		"not json": "写到一半 {",
		"not a dict": "[1, 2]",
		"missing field": JSON.stringify({"version": SaveFile.VERSION, "stage": 1}),
		"newer version": JSON.stringify({"version": SaveFile.VERSION + 5}),
	}
	for why in bad:
		_write(_mirror + "/save1.json", bad[why])
		var r := SaveMirror.pull(_local, _mirror)
		check(r.imported.is_empty() and r.rejected.has("save1.json"), "拒绝: " + why)
		eq(_gold(_local + "/save1.json"), 100, "本地存档不受影响: " + why)
		eq(FileAccess.get_file_as_string(_mirror + "/save1.json"), bad[why], "镜像里的文件原样保留: " + why)


func test_extra_check_rejects():
	_reset()
	_ours(100)
	_write(_mirror + "/save1.json", JSON.stringify(_game(9)))
	var r := SaveMirror.pull(_local, _mirror, func(_n, _d): return "关卡超范围")
	eq(r.rejected.get("save1.json"), "关卡超范围", "附加校验不通过也拒绝")
	eq(_gold(_local + "/save1.json"), 100)


func test_lost_state_same_content_is_not_an_import():
	_reset()
	_ours(100)
	DirAccess.remove_absolute(_local + "/" + SaveMirror.STATE_FILE)
	var r := SaveMirror.pull(_local, _mirror)
	check(r.imported.is_empty() and r.rejected.is_empty(), "记录丢了但内容一致: 补记录, 不导入")
	check(SaveMirror.pull(_local, _mirror).imported.is_empty(), "补过记录后仍无事发生")


func test_sync_backfills_missing_mirror_but_keeps_rejected_file():
	_reset()
	SaveFile.write_json(_local + "/save1.json", _game(100))   # 升级前就有的存档: 没有镜像
	SaveFile.write_json(_local + "/save2.json", _game(200))
	_write(_mirror + "/save2.json", "玩家放错的文件")
	var r := SaveMirror.sync(_local, _mirror)
	eq(_gold(_mirror + "/save1.json"), 100, "没有镜像的存档补镜像")
	eq(FileAccess.get_file_as_string(_mirror + "/save2.json"), "玩家放错的文件", "被拒绝的文件不覆盖, 留给玩家处理")
	check(r.rejected.has("save2.json"), "报告被拒绝的文件")
	eq(_gold(_local + "/save2.json"), 200, "本地存档不变")


func test_battle_save_is_managed():
	_reset()
	var d := {"game": _game(10), "battle": {"turn": 2, "units": []}, "version": SaveFile.VERSION, "content": SaveFile.SaveMigrations.DEFAULT_CONTENT}
	_write(_mirror + "/battle.json", JSON.stringify(d))
	eq(SaveMirror.pull(_local, _mirror).imported, ["battle.json"], "战阵存录同样能换")
	_write(_mirror + "/battle.json", JSON.stringify(_game(1)))
	check(SaveMirror.pull(_local, _mirror).rejected.has("battle.json"), "战阵存录按 battle 结构校验")


func test_game_saves_hooks():
	_reset()
	var old_base := GameSaves.base_dir
	var old_limit := GameSaves.stage_limit
	GameSaves.base_dir = _local
	GameSaves.enable_mirror(_local, _mirror)
	GameSaves.stage_limit = 10
	SaveFile.write_json(_local + "/save1.json", _game(1))
	GameSaves._mirror_push(_local + "/save1.json")
	eq(_gold(_mirror + "/save1.json"), 1, "存档后镜像")
	var far := _game(2)
	far["stage"] = 99
	_write(_mirror + "/save1.json", JSON.stringify(far))
	check(GameSaves.sync_mirror().rejected.has("save1.json"), "关卡编号超出内容包范围的不导入")
	_write(_mirror + "/save1.json", JSON.stringify(_game(3)))
	eq(GameSaves.sync_mirror().imported, ["save1.json"], "合法的换进来")
	eq(_gold(_local + "/save1.json"), 3)
	GameSaves.base_dir = old_base
	eq(GameSaves.mirror_dir(), "", "base_dir 换走 (回放沙盒) 后不镜像")
	GameSaves.enable_mirror("", "")
	GameSaves.stage_limit = old_limit
	eq(GameSaves.mirror_dir(), "", "没登记不镜像 (桌面缺省)")
	_rm(ROOT)

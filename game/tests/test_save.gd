# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 存档读写 (engine/core/save_file.gd): 原子写入、损坏回退 .bak、版本迁移

const DIR := "user://test_save"


func _path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var p := DIR.path_join(name)
	for f in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	return p


func _write_raw(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _v0_game() -> Dictionary:
	return {"stage": 3, "next_stage": 4, "gold": 100, "bag": [1, 2], "game_data": {"5": 1}, "party": {"0": {"lv": 7}}}


func test_atomic_write():
	var p := _path("a.json")
	check(SaveFile.write_json(p, {"n": 1}), "首次写入")
	check(FileAccess.file_exists(p) and not FileAccess.file_exists(p + ".bak"), "首次写入无 .bak")
	check(SaveFile.write_json(p, {"n": 2}), "再次写入")
	eq(int(SaveFile.read_json(p)["n"]), 2, "正式文件为新内容")
	eq(int(JSON.parse_string(FileAccess.get_file_as_string(p + ".bak"))["n"]), 1, ".bak 为上一版")
	check(not FileAccess.file_exists(p + ".tmp"), "不留 .tmp")
	SaveFile.write_json(p, {"n": 3})
	eq(int(JSON.parse_string(FileAccess.get_file_as_string(p + ".bak"))["n"]), 2, ".bak 只留上一版")


func test_corrupt_falls_back_to_bak():
	var p := _path("b.json")
	SaveFile.write_json(p, {"n": 1})
	SaveFile.write_json(p, {"n": 2})
	_write_raw(p, "{\"n\": 2, 写到一半")   # 正式文件损坏
	eq(int(SaveFile.read_json(p)["n"]), 1, "损坏时读 .bak")
	DirAccess.remove_absolute(p)            # 正式文件丢失 (改名中途断电)
	check(SaveFile.exists(p), "只有 .bak 也算存在")
	eq(int(SaveFile.read_json(p)["n"]), 1, "缺失时读 .bak")
	_write_raw(p + ".bak", "")
	check(SaveFile.read_json(p) == null, "都坏了返回 null")
	var r := SaveFile.load_file(p, "game")
	check(not r.ok and not r.missing and r.error != "", "都坏了给出提示")
	check(SaveFile.load_file(_path("none.json"), "game").missing, "不存在")


func test_migrate_game_v0():
	var r := SaveFile.migrate(_v0_game(), "game")
	check(r.ok, "v0 存档可迁移")
	eq(int(r.data["version"]), SaveFile.VERSION, "迁移到当前版本")
	eq(r.data["seeded"], [], "补 seeded")
	eq(r.data["where"], "camp", "补 where")
	eq(r.data["content"][0]["id"], "tdj", "补内容包标识")
	var bad := _v0_game()
	bad.erase("party")
	r = SaveFile.migrate(bad, "game")
	check(not r.ok and r.error.contains("party"), "缺必需字段报错不崩溃")
	r = SaveFile.migrate({"version": SaveFile.VERSION + 1}, "game")
	check(not r.ok, "更新版本的存档拒绝读取")
	var cur := _v0_game()
	cur["version"] = SaveFile.VERSION
	check(SaveFile.migrate(cur, "game").ok, "当前版本直接通过")
	var cur_bad := _v0_game()
	cur_bad["version"] = SaveFile.VERSION
	cur_bad.erase("gold")
	var rb := SaveFile.migrate(cur_bad, "game")
	check(not rb.ok and rb.error.contains("gold"), "当前版本缺必需字段也拒绝 (不留给 apply_dict 半途 KeyError)")
	cur_bad = _v0_game()
	cur_bad["version"] = SaveFile.VERSION
	cur_bad["bag"] = "oops"
	check(not SaveFile.migrate(cur_bad, "game").ok, "当前版本字段类型不对也拒绝")


func test_migrate_battle():
	var old := {"game": _v0_game(), "battle": {"turn": 2, "units": [{"cx": 1, "cy": 2, "hp": 30, "stats": {}}]}}
	var r := SaveFile.migrate(old, "battle")
	check(not r.ok, "规则接入前的战阵存录不能转换")
	eq(r.error, "存录版本过旧")
	var v0 := {"game": _v0_game(), "battle": {"turn": 2, "units": [{"dir": 0, "shown": true, "st": {"hp": 30}}]}}
	r = SaveFile.migrate(v0, "battle")
	check(r.ok, "新单位格式的 v0 存录可迁移")
	eq(int(r.data["version"]), SaveFile.VERSION)
	eq(int(r.data["game"]["version"]), SaveFile.VERSION, "内层存档同步版本")
	check(r.data.has("content"), "补内容包标识")
	check(not SaveFile.migrate({"game": 1}, "battle").ok, "结构不对报错")


func test_load_file_roundtrip():
	var p := _path("c.json")
	var d := SaveFile.stamp(_v0_game(), "game", [{"id": "tdj", "version": "1.3.0"}])
	check(SaveFile.write_json(p, d), "写入")
	var r := SaveFile.load_file(p, "game")
	check(r.ok, "读回")
	eq(r.data["content"][0]["version"], "1.3.0", "内容包版本保留")
	_write_raw(p, JSON.stringify(_v0_game()))  # 旧程序写的无版本存档
	r = SaveFile.load_file(p, "game")
	check(r.ok and int(r.data["version"]) == SaveFile.VERSION, "无版本旧档读入时迁移")

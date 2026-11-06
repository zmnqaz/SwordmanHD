# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 存档读写 (engine/core/save_file.gd): 原子写入 + 校验后删 .bak、读时从 .tmp / .bak 恢复 (每个崩溃点)、版本迁移

static var DIR: String = tmp_dir("test_save")


func _path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var p := DIR.path_join(name)
	for f in [p, p + ".bak", p + ".tmp"] + SaveFile._tmps(p):
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	return p


func _write_raw(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _v0_game() -> Dictionary:
	return {"stage": 3, "next_stage": 4, "gold": 100, "bag": [1, 2], "game_data": {"5": 1}, "party": {"0": {"lv": 7}}}


func _only(p: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(p.get_base_dir()):
		if f.begins_with(p.get_file()):
			out.append(f.trim_prefix(p.get_file()))
	out.sort()
	return out


## 写成功: 新档读回校验通过才删 .bak, 目录里只剩正式文件 (2026-11-06「确认 OK 就删」)
func test_atomic_write():
	var p := _path("a.json")
	check(SaveFile.write_json(p, {"n": 1}), "首次写入")
	eq(_only(p), [""], "首次写入只有正式文件")
	check(SaveFile.write_json(p, {"n": 2}), "再次写入")
	eq(int(SaveFile.read_json(p)["n"]), 2, "正式文件为新内容")
	eq(_only(p), [""], "校验通过后 .bak 删掉, 不留 .tmp")


## 每个崩溃点磁盘上都有一份完整的, 读时自动恢复:
##   ① 写临时文件途中 (临时文件残缺): 正式文件 = 旧档
##   ② 旧档已改名 .bak、临时文件还没改成正式 (正式文件缺席): 用临时文件 (新档) 恢复
##   ③ 临时文件也坏了: 用 .bak (旧档) 恢复
##   ④ 新档已就位、.bak 还没删: 读正式文件, 顺手删 .bak
func test_every_crash_point_recovers():
	var p := _path("c.json")
	SaveFile.write_json(p, {"n": 1})
	_write_raw(p + ".tmp777", "{\"n\": 2, 写到")             # ①
	eq(int(SaveFile.read_json(p)["n"]), 1, "① 写临时文件时崩溃: 读旧档")
	DirAccess.remove_absolute(p + ".tmp777")
	DirAccess.rename_absolute(p, p + ".bak")                 # ②
	_write_raw(p + ".tmp777", "{\"n\": 2}")
	check(SaveFile.exists(p), "② 正式文件缺席也算存在")
	eq(int(SaveFile.read_json(p)["n"]), 2, "② 用临时文件 (新档) 恢复")
	eq(int(JSON.parse_string(FileAccess.get_file_as_string(p))["n"]), 2, "② 恢复后正式文件就位")
	check(not FileAccess.file_exists(p + ".bak"), "② 恢复后 .bak 删掉")
	DirAccess.rename_absolute(p, p + ".bak")                 # ③
	_write_raw(p + ".tmp777", "")
	eq(int(SaveFile.read_json(p)["n"]), 2, "③ 临时文件坏了用 .bak 恢复")
	check(FileAccess.file_exists(p) and not FileAccess.file_exists(p + ".bak"), "③ .bak 改回正式文件")
	_write_raw(p + ".bak", "{\"n\": 1}")                       # ④
	eq(int(SaveFile.read_json(p)["n"]), 2, "④ 正式文件好的就用它")
	check(not FileAccess.file_exists(p + ".bak"), "④ 残留 .bak 删掉")
	DirAccess.remove_absolute(p + ".tmp777")


func test_corrupt_falls_back_to_bak():
	var p := _path("b.json")
	SaveFile.write_json(p, {"n": 1})
	_write_raw(p + ".bak", "{\"n\": 1}")   # 上一版的备份 (写到一半崩溃留下的)
	_write_raw(p, "{\"n\": 2, 写到一半")   # 正式文件损坏
	eq(int(SaveFile.read_json(p)["n"]), 1, "损坏时读 .bak")
	DirAccess.rename_absolute(p, p + ".bak")
	check(SaveFile.exists(p) and not FileAccess.file_exists(p), "只有 .bak 也算存在")
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

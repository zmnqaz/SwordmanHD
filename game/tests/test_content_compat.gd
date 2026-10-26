# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 内容包版本策略与存档兼容 (engine/content/content_compat.gd、content_db.gd 缺省主包与引擎要求、game_saves.gd 读档检查)
const REQUIRES_TEST := {
	"test_builtin_manifests_have_version_fields": ["content"],
	"test_legacy_save_defaults_to_base_pack": ["content"],
	"test_pack_engine_requirement_enforced": ["content"]
}  # 个别方法的依赖 (同上)

const ContentDBScript = preload("res://engine/content/content_db.gd")
const TMP := "user://compat_test"


func _write(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(data if data is String else JSON.stringify(data))
	f.close()


func _rmtree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rmtree(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func test_version_compare():
	eq(ContentCompat.compare("1.3.0", "1.3.0"), 0)
	eq(ContentCompat.compare("1.3", "1.3.0"), 0, "缺的段按 0")
	eq(ContentCompat.compare("1.10.0", "1.9.9"), 1, "按数字不按字典序")
	eq(ContentCompat.compare("0.9", "1"), -1)
	eq(ContentCompat.compare("", "1.0"), 0, "未知版本不算冲突")
	check(ContentCompat.is_version("1.0.0") and ContentCompat.is_version("2"), "合法版本号")
	check(not ContentCompat.is_version("v1") and not ContentCompat.is_version("1..2") and not ContentCompat.is_version(""), "非法版本号")


func test_engine_requirement():
	eq(ContentCompat.engine_error({"id": "a"}), "", "没写要求不限")
	eq(ContentCompat.engine_error({"id": "a", "engine_min": "1.0.0"}, "1.0.0"), "")
	check("需要引擎" in ContentCompat.engine_error({"id": "a", "engine_min": "2.0.0"}, "1.4.0"), "引擎太旧")
	check("只支持引擎" in ContentCompat.engine_error({"id": "a", "engine_max": "1.9"}, "2.0.0"), "引擎太新")
	eq(ContentCompat.engine_error({"id": "a", "engine_min": "1", "engine_max": "1.9"}, "1.5.2"), "", "范围内")


func _loaded() -> Array:
	return [{"id": "tdj", "version": "1.3.0", "save_compat_min": "1.2.0"}, {"id": "mod", "version": "0.2.0", "save_compat_min": ""}]


func test_check_save_policy():
	var ok := ContentCompat.check_save([{"id": "tdj", "version": "1.3.0"}, {"id": "mod", "version": "0.2.0"}], _loaded())
	eq(ok.level, "ok")
	var missing := ContentCompat.check_save([{"id": "tdj", "version": "1.3.0"}, {"id": "gone", "version": "1"}], _loaded())
	eq(missing.level, "error", "存档需要的包没加载")
	check("gone" in missing.text and "--mods=gone" in missing.text, "说明缺哪个包、怎么启用: " + missing.text)
	var newer := ContentCompat.check_save([{"id": "tdj", "version": "1.4.0"}, {"id": "mod", "version": "0.2.0"}], _loaded())
	eq(newer.level, "error", "存档的包比当前新")
	check("更新" in newer.text, newer.text)
	var old := ContentCompat.check_save([{"id": "tdj", "version": "1.1.0"}, {"id": "mod", "version": "0.2.0"}], _loaded())
	eq(old.level, "error", "低于 save_compat_min")
	check("过旧" in old.text, old.text)
	var upgraded := ContentCompat.check_save([{"id": "tdj", "version": "1.2.5"}, {"id": "mod", "version": "0.1.0"}], _loaded())
	eq(upgraded.level, "warn", "旧但兼容: 读档并提示")
	eq(upgraded.messages.size(), 2)
	var extra := ContentCompat.check_save([{"id": "tdj", "version": "1.3.0"}], _loaded())
	eq(extra.level, "warn", "当前多启用了存档没有的包")
	var unknown := ContentCompat.check_save([{"id": "tdj", "version": ""}, {"id": "mod", "version": ""}], _loaded())
	eq(unknown.level, "ok", "存档版本未知不拦")
	eq(ContentCompat.check_save(null, [{"id": "tdj", "version": "1.3.0", "save_compat_min": ""}]).level, "ok", "缺 content 字段 = 旧档, 按原版包")
	eq(ContentCompat.check_save([], [{"id": "other", "version": "1"}]).level, "error", "旧档在没有原版包的环境读不了")


## 旧存档 (没有 content / version 字段) 迁移后记为原版包, 在原版包环境照常读
func test_legacy_save_defaults_to_base_pack():
	var d := {"stage": 1, "next_stage": 2, "gold": 5, "bag": [], "game_data": {}, "party": {}}
	var r := SaveFile.migrate(d, "game")
	check(r.ok, "旧档迁移成功")
	eq(r.data["content"][0]["id"], ContentCompat.LEGACY_PACK_ID)
	var content: Node = Engine.get_main_loop().root.get_node("Content")
	var packs: Array = content.packs.map(func(p): return p["id"])
	var c := GameSaves.check_content(r.data["content"])
	if packs == ["tdj"]:
		eq(c.level, "ok", "只加载原版包时旧档可读")
	else:
		check(c.level != "error", "旧档在 %s 下不应被拒绝" % str(packs))


## 缺省主包由配置决定: res://content/content.json; 没配置时取第一个没有 base 的包
func test_default_main_from_config():
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://content/content.json"))
	eq(ContentDBScript.default_main(["res://content"]), String(cfg["main"]), "配置里的主包")
	_write(TMP + "/dm1/zz_mod/manifest.json", {"format": "tdj-content/1", "id": "zz_mod", "version": "1", "base": ["aa_main"]})
	_write(TMP + "/dm1/aa_main/manifest.json", {"format": "tdj-content/1", "id": "aa_main", "version": "1", "base": []})
	eq(ContentDBScript.default_main([TMP + "/dm1"]), "aa_main", "无配置: 第一个没有 base 的包")
	_write(TMP + "/dm1/content.json", {"main": "zz_mod"})
	eq(ContentDBScript.default_main([TMP + "/dm1"]), "zz_mod", "配置优先")
	eq(ContentDBScript.default_main([TMP + "/empty"]), "", "没有任何包")
	_rmtree(TMP)


## 包要求的引擎版本不满足: 报错、该包不加载 (不崩溃)
func test_pack_engine_requirement_enforced():
	var dir := "user://content/compat_need_new_engine"
	_write(dir + "/manifest.json", {"format": "tdj-content/1", "id": "compat_need_new_engine", "version": "1", "base": ["tdj"], "engine_min": "99.0.0"})
	var db = ContentDBScript.new()
	db.load_packs(["tdj", "compat_need_new_engine"])
	eq(db.errors.size(), 1, "报一条引擎版本错")
	check("需要引擎 99.0.0" in String(db.errors[0]), String(db.errors[0]))
	eq(db.packs.map(func(p): return p["id"]), ["tdj"], "不满足的包不加载")
	db.free()
	_rmtree(dir)


## 内置包的版本字段齐全、合法, 引擎满足要求
func test_builtin_manifests_have_version_fields():
	for id in ["tdj", "example_mod"]:
		var m = JSON.parse_string(FileAccess.get_file_as_string("res://content/%s/manifest.json" % id))
		check(ContentCompat.is_version(String(m["version"])), "%s version" % id)
		check(ContentCompat.is_version(String(m.get("engine_min", ""))), "%s engine_min" % id)
		eq(ContentCompat.engine_error(m), "", "%s 引擎满足要求" % id)
	var base = JSON.parse_string(FileAccess.get_file_as_string("res://content/tdj/manifest.json"))
	check(ContentCompat.is_version(String(base["save_compat_min"])), "原版包声明存档兼容下限")

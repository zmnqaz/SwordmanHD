# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 资源命名清单 (ui_theme/assets.json): 代码引用的逻辑名都在清单里, 叠加覆盖, 代码里不再写原版资源路径


func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


func _sources() -> Array:
	var files := []
	_scan("res://engine", files)
	_scan("res://scripts", files)
	return files


func test_every_referenced_name_is_in_manifest():
	var content: Node = Engine.get_main_loop().root.get_node("Content")
	content.load_packs([ContentDB.default_main()])
	ThemeAssets.reload()
	var re := RegEx.create_from_string("ThemeAssets\\.(?:p|f)\\(\"([a-z_.]+)\"")
	var used := {}
	for f in _sources():
		if f.ends_with("theme_assets.gd"):
			continue
		var s := FileAccess.get_file_as_string(f)
		for m in re.search_all(s):
			used[m.get_string(1)] = f
	# 布局表的 sprite/digits.anim 也用逻辑名 (UiLayout.asset 解析), 一并核对
	var lre := RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")
	var els: Dictionary = UiLayout.data().get("elements", {})
	for id in els:
		for f in ["sprite", "digits"]:
			var an = els[id].get(f).get("anim") if els[id] is Dictionary and els[id].get(f) is Dictionary else null
			if an is String and lre.search(an) != null:
				used[an] = "layout.json " + id
	check(used.size() > 30, "扫到足够多的引用 (%d)" % used.size())
	for k in used:
		check(ThemeAssets.has(k), "清单缺 %s (%s)" % [k, used[k]])


func test_no_original_asset_path_literals_in_code():
	var re := RegEx.create_from_string("\"(Misc|Movie|Face|Music|Sprite|Shop|Magic|Rpg)/[A-Za-z0-9_%{}]")
	for f in _sources():
		for line in FileAccess.get_file_as_string(f).split("\n"):
			if line.strip_edges().begins_with("#") or line.contains("##"):
				continue
			var m := re.search(line)
			check(m == null, "%s 里写了原版资源路径: %s" % [f, line.strip_edges()])


func test_lookup_format_and_override():
	ThemeAssets.use({"names": {"a.b": "Misc/X"}, "patterns": {"face": "Face/FACE%02d"}})
	eq(ThemeAssets.p("a.b"), "Misc/X")
	eq(ThemeAssets.f("face", [5]), "Face/FACE05")
	var merged := UiLayout.merge({"names": {"a.b": "Misc/X", "c": "Misc/C"}}, {"names": {"a.b": "Mod/Y", "c": null}})
	eq(merged["names"], {"a.b": "Mod/Y"}, "后包覆盖, null 删除")
	ThemeAssets.reload()

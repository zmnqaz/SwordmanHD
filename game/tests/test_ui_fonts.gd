# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 字体清单 (content ui_theme/fonts.json, engine/ui/ui_fonts.gd): 合法性、文件存在、基线合理、缺字回退、叠加

func test_manifest_valid():
	var list := UiFonts.all()
	check(list.size() >= 3, "至少 3 个字体")
	var seen := {}
	for e in list:
		var id: String = e["id"]
		check(not seen.has(id), "id 唯一 " + id)
		seen[id] = true
		for k in ["name", "desc", "file", "baseline_in_cell", "license", "license_file"]:
			check(e.has(k), "%s 有 %s" % [id, k])
		check(FileAccess.file_exists(e["file"]), "字体文件存在 " + e["file"])
		check(FileAccess.file_exists(e["license_file"]), "许可文件存在 " + e["license_file"])
		# 字体按路径用 load_dynamic_font 读原文件, 必须带 importer="keep" 的 .import (原样进 pck);
		# 缺了它 Godot 会按默认字体导入, 导出包里没有原文件, 界面文字全部消失 (开发机直接读文件, 看不出来)
		var imp := FileAccess.get_file_as_string(String(e["file"]) + ".import")
		check(imp.contains('importer="keep"'), "字体带 keep 的 .import (入库, 不能被 .gitignore 挡) " + e["file"])
		var b := float(e["baseline_in_cell"])
		check(b >= 9.5 and b <= 12.0, "%s 基线在字格合理范围 %s" % [id, b])
		check(String(e["desc"]).length() <= 24, "%s 说明够短 (设定面板两行)" % id)
	check(not UiFonts.find(UiFonts.default_id()).is_empty(), "缺省字体在清单里")
	eq(UiFonts.default_id(), "kai", "缺省霞鹜文楷")


func test_unknown_falls_back():
	eq(UiFonts.get_or_default("nope")["id"], UiFonts.default_id(), "未知 id 回退缺省")
	eq(UiFonts.baseline("nope"), UiFonts.baseline(UiFonts.default_id()), "基线同缺省")


func test_every_font_covers_common_text():
	for e in UiFonts.all():
		var f := FontFile.new()
		f.load_dynamic_font(ProjectSettings.globalize_path(e["file"]))
		for ch in "天地劫神魔至尊传的了一是，。、！？":
			check(f.has_char(ch.unicode_at(0)), "%s 有字 %s" % [e["id"], ch])


func test_set_font_swaps_proxy():
	var before := Assets.font_id
	Assets.set_font("sans")  # 与本机设定里的字体无关, 保证下面 set_font("kai") 一定是一次切换
	var f := Assets.font()
	var n := [0]
	Assets.font_changed.connect(func(): n[0] += 1)
	Assets.set_font("kai")
	eq(Assets.font_id, "kai")
	eq(Assets.font(), f, "代理对象不变, 已建的 Label 自动跟随")
	eq(UiText.baseline(12.0), UiFonts.baseline("kai"), "基线随字体")
	Assets.set_font("nope")
	eq(Assets.font_id, UiFonts.default_id(), "未知回退缺省")
	check(n[0] >= 1, "发了 font_changed (缺省就是 kai, 回退缺省那一次不一定再发)")
	Assets.set_font(before if before != "" else UiFonts.default_id())


func test_merge_dirs():
	var m := UiFonts.merge_dirs(["res://content/tdj", "res://content/remake", "res://content/example_mod"])
	check(m["list"].size() >= 3, "叠加不丢字体")
	eq(UiFonts.merge_dirs([])["list"].size(), 0, "没有包 = 空清单 (_ensure 再退回内置)")


## 回归 (2026-10-29): 缺省字体是文楷子集, 以前「只有非缺省字体才回退」, 文楷自己没兜底, 繁体「畫質診斷」的「診」字 (子集里没有) 直接丢了
func test_subset_fonts_fall_back_to_the_complete_font():
	eq(UiFonts.complete_id(), "sans", "完整字库 = 思源黑体 (清单 full 标记)")
	var ch := "診".unicode_at(0)
	var full: FontFile = Assets._face("sans")
	check(full.has_char(ch), "思源黑体有「診」")
	for id in ["kai", "serif"]:
		var f: FontFile = Assets._face(id)
		check(f.fallbacks.size() == 1 and f.fallbacks[0] == full, "%s (裁过的子集) 缺字回退到思源黑体" % id)
	check(full.fallbacks.is_empty(), "完整字库自己不回退")
	eq(UiFonts.merge_dirs(["res://content/tdj", "res://content/remake"])["list"].filter(func(e): return e.get("full", false)).size(), 1, "清单里恰好一个完整字库")

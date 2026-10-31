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
		# 内置字库 (res://assets/font) 要许可文本与 keep 的 .import; 由原版生成的字体 (原版点阵, 内容包 ui_theme 里, 不入库) 只要文件在
		var builtin := String(e["file"]).begins_with("res://assets/")
		for k in ["name", "desc", "file", "baseline_in_cell", "license"] + (["license_file"] if builtin else []):
			check(e.has(k), "%s 有 %s" % [id, k])
		check(FileAccess.file_exists(e["file"]), "字体文件存在 " + e["file"])
		if builtin:
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
		for ch in ("天地劫神魔至尊傳的了一是，。、！？" if e.get("lang", "") == "hant" else "天地劫神魔至尊传的了一是，。、！？"):   # 限定繁体的字体只查繁体字
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


## 原版点阵 (生成工具的脚本 从原版 Tfont.dat 生成, 内容包 tdj 里, 只服务繁体): 没生成时跳过; 简体下不可用, 繁体下能用, 缺字回退思源黑体
func test_tfont_from_original():
	var e := UiFonts.find("tfont")
	if e.is_empty():
		skip("没生成原版点阵 (生成工具的脚本, 需要原版)")
		return
	var before: String = Content.lang
	Content.set_lang("hans")
	eq(e["lang"], "hant", "限定繁体")
	eq(UiFonts.get_or_default("tfont")["id"], UiFonts.default_id(), "简体下回退缺省字体")
	check(not UiFonts.options().any(func(o): return o["v"] == "tfont"), "简体下设定里不列")
	check(UiFonts.options(true).any(func(o): return o["v"] == "tfont"), "全量选项里有 (设定文件校验用)")
	Content.set_lang("hant")
	eq(UiFonts.get_or_default("tfont")["id"], "tfont", "繁体下可用")
	check(UiFonts.options().any(func(o): return o["v"] == "tfont"), "繁体下设定里列出")
	eq(float(e["baseline_in_cell"]), 12.0, "点阵字基线在字格最后一行下沿")
	eq(float(e.get("embolden", 0.0)), 0.0, "点阵字不加粗")
	var f: FontFile = Assets._face("tfont")
	for ch in "天地劫神魔至尊傳的了一是，。、！？ABab09":
		check(f.has_char(ch.unicode_at(0)), "点阵字有 " + ch)
	check(f.has_char(0x20), "有空格 (宽度)")
	var bare := FontFile.new()   # 不挂回退的原字体 (has_char / get_supported_chars 都会把回退字体算进去)
	bare.load_dynamic_font(String(e["file"]))
	for ch in "闇鼩蓮祂布錘噁墬喲":   # 原版字模是空的、make_tfont.py 补上的字 (ALIAS / tfont_extra.json / COMPOSE)
		check(bare.has_char(ch.unicode_at(0)), "补字后字体自己有「%s」" % ch)
	check(not bare.has_char("气".unicode_at(0)), "不做简体别名 (「气」的字形在繁体码位「氣」上)")
	check(f.fallbacks.size() == 1 and f.fallbacks[0] == Assets._face("sans"), "缺字回退到思源黑体")
	check(f.get_char_size("天".unicode_at(0), 48).x == 48.0, "全角 1 em")
	check(f.get_char_size("A".unicode_at(0), 48).x == 24.0, "半角 1/2 em")
	Content.set_lang(before)


## order: 后加载的包 (tdj) 的字体排到内置字体之后; 同 order 保持加载顺序
func test_merge_order():
	var root := "user://_fonts_order_test"
	var mk := func(name: String, fonts: Array):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join(name).path_join("ui_theme")))
		var f := FileAccess.open(root.path_join(name).path_join("ui_theme/fonts.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"fonts": fonts}))
		f.close()
	mk.call("a", [{"id": "late", "file": "x", "order": 100}, {"id": "a1", "file": "x"}])
	mk.call("b", [{"id": "b1", "file": "x"}, {"id": "a1", "file": "y"}])
	var ids: Array = UiFonts.merge_dirs([root.path_join("a"), root.path_join("b")])["list"].map(func(e): return e["id"])
	eq(ids, ["a1", "b1", "late"], "order 大的排后面, 同值保持加载顺序 (同 id 合并不挪位置)")
	for n in ["a", "b"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join(n).path_join("ui_theme/fonts.json")))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join(n).path_join("ui_theme")))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join(n)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


## 点阵风字体 (hinting = none) 画对话等样式 5 时保留原版左右光边; 矢量字仍是单色 (2026-10-06 用户拍板)
func test_pixel_font_keeps_original_halo_style():
	eq(UiLayout.style(5, false).size(), 1, "矢量字: 单色")
	var px: Array = UiLayout.style(5, true)
	eq(px.size(), 3, "点阵字: 左右光边 + 本色")
	eq([int(px[0][0]), int(px[1][0]), int(px[2][0])], [-1, 1, 0], "先画左右光边再画本色")
	eq(UiLayout.style(0, true).size(), 1, "没有 pixel_draws 的样式不受影响")
	check(not UiFonts.is_pixel(UiFonts.default_id()), "默认字体不是点阵风")

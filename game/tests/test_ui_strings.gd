# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 界面文案进内容包 (text/ui.json, UiStrings): 迁移前后文案逐字相同 + 内容包可覆盖。
## tests/data/ui_text_before_s3.json 是迁移前从代码里导出的文案 (设定面板/营地菜单/标题菜单), 此后只增不改 (2026-10-07 用户嫌设定菜单项和说明太多: 去掉隐藏的 tex/aspect/win/popup 四项, 说明改短, 快照随之更新)。

const BEFORE := "res://tests/data/ui_text_before_s3.json"


func _before() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(BEFORE))


## 各键经真实取用路径 (SettingsSchema / CampMenu / 标题场景) 取到的文案
func _resolved() -> Dictionary:
	var out := {}
	for r in SettingsSchema.shown_rows():
		var k: String = r["key"]
		out["settings.%s.label" % k] = SettingsSchema.label_of(r)
		out["settings.%s.desc" % k] = SettingsSchema.row_desc(r)
		if r.has("options"):
			for o in SettingsSchema.options_of(r):
				out["settings.%s.opt.%s" % [k, str(o["v"])]] = o["t"]
	for i in CampMenu.COUNT:
		out["camp.menu.item.%d" % i] = CampMenu.item_text(i)
	var ts = load("res://scripts/title_scene.gd")
	for i in ts.ITEM_COUNT:
		out["title.menu.item.%d" % i] = ts._item(i)
	for k in ["settings.title", "settings.button.reset", "settings.button.done", "settings.desc.reset", "settings.desc.done"]:
		out[k] = UiStrings.t(k)
	return out


func test_texts_unchanged_after_migration():
	if not FileAccess.file_exists(BEFORE):
		skip("缺迁移前文案快照")
		return
	UiStrings.reload()
	var want := _before()
	var got := _resolved()
	check(want.size() > 40, "迁移前文案表读到 (%d)" % want.size())
	eq(got.size(), want.size(), "取到的键数与迁移前一致")
	for k in want:
		eq(got.get(k), want[k], "文案 " + k)


func test_pack_ui_json_has_every_key():
	if not FileAccess.file_exists(BEFORE):
		skip("缺迁移前文案快照")
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/remake/text/ui.json"))
	for k in _before():
		check(d.has(k), "remake/text/ui.json 有 " + k)


func test_later_pack_overrides_and_null_deletes():
	var base := "user://ui_strings_test"
	for p in ["a", "b"]:
		DirAccess.make_dir_recursive_absolute(base.path_join(p).path_join("text"))
	var fa := FileAccess.open(base.path_join("a/text/ui.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify({"x.one": "甲", "x.two": "乙", "x.fmt": "第 %d 关", "_comment": "说明键不入表"}))
	fa.close()
	var fb := FileAccess.open(base.path_join("b/text/ui.json"), FileAccess.WRITE)
	fb.store_string(JSON.stringify({"x.one": "丙", "x.two": null}))
	fb.close()
	var m := UiStrings.merge_dirs([base.path_join("a"), base.path_join("b")])
	eq(m.get("x.one"), "丙", "后加载的包覆盖")
	check(not m.has("x.two"), "null 删除键")
	check(not m.has("_comment"), "下划线开头的说明键不入表")
	UiStrings.use(m)
	eq(UiStrings.t("x.fmt", [3]), "第 3 关", "带参数格式化")
	eq(UiStrings.t("x.two"), "x.two", "缺键返回键名")
	UiStrings.reload()
	for p in ["a", "b"]:
		DirAccess.remove_absolute(base.path_join(p).path_join("text/ui.json"))

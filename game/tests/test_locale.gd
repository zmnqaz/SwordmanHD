# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 语言叠加层 (ContentDB.set_lang / locale/<lang>/): 简体模式不读叠加层, 繁体模式把它合到包数据之上
## (对象深合并, 数组整个替换, 数据表按键合并, 系统文本按表名, ui.json 按键), 设计 docs/设计_繁简切换.md

const ContentDBScript = preload("res://engine/content/content_db.gd")
const ROOT := "user://content/loc_test"


func _write(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(data if data is String else JSON.stringify(data))
	f.close()


func _make_pack() -> void:
	_write(ROOT + "/manifest.json", {"format": "tdj-content/1", "id": "loc_test", "version": "1", "base": [], "stage_count": 1,
		"tables": {"things": {"file": "data/things.json", "key": "id"}}})
	_write(ROOT + "/data/things.json", [{"id": 0, "name": "长剑", "atk": 5, "r": {"min": 1, "max": 2}}, {"id": 1, "name": "短刀", "atk": 3}])
	_write(ROOT + "/stages/00/stage.json", {"id": 0, "name": "第五幕 十方鬼众", "briefing": {"title": "甲", "win": "敌全灭", "lose": "乙"},
		"map_events": [{"type": 1, "show": -1}]})
	_write(ROOT + "/stages/00/text.json", {"_source": "x", "groups": [["黄牛货", "卖您"], ["再见"]]})
	_write(ROOT + "/text/system.json", {"treasure": [["宝箱"]], "give_item": [["给予"]]})
	_write(ROOT + "/text/ui.json", {"a.b": "设定", "a.c": "确认"})
	# 叠加层: 只写不同的文字
	_write(ROOT + "/locale/hant/data/things.json", [{"id": 0, "name": "長劍"}])
	_write(ROOT + "/locale/hant/stages/00/stage.json", {"name": "第五幕 十方鬼眾", "briefing": {"win": "敵全滅"}})
	_write(ROOT + "/locale/hant/stages/00/text.json", {"groups": [["黃牛貨", "賣您"], ["再見"]]})
	_write(ROOT + "/locale/hant/text/system.json", {"treasure": [["寶箱"]]})
	_write(ROOT + "/locale/hant/text/ui.json", {"a.b": "設定"})


func _db() -> Node:
	_make_pack()
	var db = ContentDBScript.new()
	db.load_packs(["loc_test"])
	return db


func test_default_language_ignores_locale():
	var db = _db()
	eq(db.errors, [])
	eq(db.lang, "", "缺省简体")
	eq(String(db.record("things", 0)["name"]), "长剑")
	eq(db.stage_name(0), "第五幕 十方鬼众")
	eq(db.text_groups("stages/00/text.json")[0][0], "黄牛货")
	eq(db.system_text("treasure")[0][0], "宝箱")
	db.free()


func test_hant_overlays_every_kind_of_file():
	var db = _db()
	db.set_lang("hant")
	var t0: Dictionary = db.record("things", 0)
	eq(String(t0["name"]), "長劍", "数据表: 按键合并")
	eq(int(t0["atk"]), 5, "没写的字段保留")
	eq(int(t0["r"]["max"]), 2, "子对象保留")
	eq(String(db.record("things", 1)["name"]), "短刀", "叠加层没提到的记录不变")
	eq(db.stage_name(0), "第五幕 十方鬼眾", "stage.json: 对象深合并")
	var info: Dictionary = db.stage_info(0)
	eq(String(info["briefing"]["win"]), "敵全滅")
	eq(String(info["briefing"]["title"]), "甲", "简报里没写的字段保留")
	eq(info["map_events"].size(), 1, "叠加层不含的字段 (地图事件) 保留")
	eq(db.text_groups("stages/00/text.json"), [["黃牛貨", "賣您"], ["再見"]], "对白: 数组整个替换")
	eq(db.system_text("treasure")[0][0], "寶箱", "系统文本: 按表名替换")
	eq(db.system_text("give_item")[0][0], "给予", "叠加层没提到的表不变")
	db.free()


func test_switching_back_restores_simplified():
	var db = _db()
	db.set_lang("hant")
	eq(db.stage_name(0), "第五幕 十方鬼眾")
	db.set_lang("hans")
	eq(db.lang, "", "hans 与空串等价")
	eq(db.stage_name(0), "第五幕 十方鬼众", "切回简体: 缓存重建")
	eq(String(db.record("things", 0)["name"]), "长剑")
	eq(db.text_groups("stages/00/text.json")[0][0], "黄牛货")
	db.free()


func test_ui_strings_locale_merge():
	_make_pack()
	var dirs := [ROOT]
	eq(UiStrings.merge_dirs(dirs), {"a.b": "设定", "a.c": "确认"}, "缺省不读叠加层")
	eq(UiStrings.merge_dirs(dirs, "hant"), {"a.b": "設定", "a.c": "确认"}, "繁体: 按键合并, 没写的键保留简体")


func test_overlay_from_a_later_pack_applies_to_earlier_packs_file():
	_make_pack()
	var b := "user://content/loc_test_b"
	_write(b + "/manifest.json", {"format": "tdj-content/1", "id": "loc_test_b", "version": "1", "base": ["loc_test"]})
	_write(b + "/locale/hant/stages/00/stage.json", {"name": "改名後的第五幕"})
	var db = ContentDBScript.new()
	db.load_packs(["loc_test_b"])
	db.set_lang("hant")
	eq(db.stage_name(0), "改名後的第五幕", "后加载包的叠加层覆盖前面包的叠加层")
	eq(String(db.stage_info(0)["briefing"]["win"]), "敵全滅", "前面包的叠加层其余部分仍生效")
	db.set_lang("")
	eq(db.stage_name(0), "第五幕 十方鬼众")
	db.free()


func test_unknown_language_and_missing_overlay_are_harmless():
	var db = _db()
	db.set_lang("fr")
	eq(db.stage_name(0), "第五幕 十方鬼众", "没有该语言的叠加层: 退回包数据")
	eq(db.text_groups("stages/00/text.json")[0][0], "黄牛货")
	db.free()

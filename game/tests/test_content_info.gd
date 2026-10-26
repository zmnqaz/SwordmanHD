# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## core 层问内容包的窄接口 (ContentInfo, 经 GameContext.content): 代替 core 直接引用 autoload Content。


func test_default_reads_autoload_content():
	var ci := GameContext.new().content
	eq(ci.signature(), Content.signature(), "存档签名同 Content")
	eq(ci.pack_infos(), Content.pack_infos(), "包信息同 Content")
	eq(ci.is_hero(1), Content.is_hero(1), "主角判定同 Content")
	eq(ci.party_init(1), Content.party_init(1), "初始配置同 Content")


func test_db_override_and_no_content():
	var db := ContentDB.new()
	db.load_packs([ContentDB.default_main()])
	var ci := ContentInfo.new()
	ci.db = db
	eq(ci.signature(), db.signature(), "指定 db 时读它")
	eq(ci.is_hero(0), db.is_hero(0))
	db.free()
	var empty := ContentInfo.new()
	empty.db = null
	check(empty.signature() is Array, "签名总是数组")

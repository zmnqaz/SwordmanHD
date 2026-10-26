# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 全屏过场演出 (engine/fx/cutscene.gd + 内容包 fx/cutscenes.json): 诸物炼化炼成 = 丹炉垫图 + FORGEITE 视频 + 浮动提示。
## 原版: /。


func test_forge_spec_from_content():
	var s := Cutscene.spec("forge")
	check(not s.is_empty(), "内容包有 forge 演出")
	eq(s["skip"], ["cancel"], ": 取消键跳过, 回车不跳过")
	eq(ThemeAssets.p(s["movie"]), "Movie/Forgeite", "视频走资源清单逻辑名")
	eq(Cutscene.spec("没有这个"), {}, "未知 id 返回空")


func test_forge_backdrop_in_layout_table():
	var bd: String = Cutscene.spec("forge")["backdrop"]
	check(UiLayout.has(bd), "垫图位置在布局表里")
	eq(UiLayout.pos(bd), Vector2.ZERO, "画在 (0,0) ")
	var sp := UiLayout.sprite(bd)
	eq(sp["anim"], ThemeAssets.p("camp.forge"), "素材 FI_PRO")
	eq(int(sp["frame"]), 18, "第 18 帧 (丹炉图)")
	eq(UiLayout.validate(), [], "布局表无错")


func test_notice():
	eq(Cutscene.notice_text("forge", ["天河朱砂"]), "炼化成天河朱砂")
	eq(Cutscene.notice_text("没有这个"), "")
	if not Game.fast:
		near(Cutscene.notice_secs("forge"), 2.0, 0.001, "50 tick x 40 ms (参数 0x32)")
	else:
		near(Cutscene.notice_secs("forge"), 0.0, 0.001, "快进时不停留")


func test_movie_skip_keys():
	var m = MovieScene.create(["x"], func(): pass, ["cancel"])
	check(m.skips(UiAction.of(UiAction.CANCEL)), "取消键跳过")
	check(not m.skips(UiAction.of(UiAction.CONFIRM)), "确认键不跳过 (炼化)")
	var echo := UiAction.of(UiAction.CANCEL)
	echo.echo = true
	check(not m.skips(echo), "连发不跳过")
	m.free()
	var both = MovieScene.create(["x"], func(): pass)
	check(both.skips(UiAction.of(UiAction.CONFIRM)) and both.skips(UiAction.of(UiAction.CANCEL)), "缺省两者都跳过 (片头)")
	both.free()

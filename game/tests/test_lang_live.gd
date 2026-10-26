# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 设定里切简繁立即生效: 已经加载的关卡 / 城镇, 之后的每一句对白马上是新语言 (关卡对象缓存了对白表, 语言一换要重取)。
## 需要内容包 tdj (含繁体叠加层 locale/hant); 找不到时跳过。
const REQUIRES_TEST := {
	"test_battle_stage_dialog_follows_language": ["content"],
	"test_town_dialog_follows_language": ["content"],
}


func _first_line(talk: Callable, groups: int) -> Array:
	for g in groups:
		var s: String = talk.call(g, 0)
		if s != "":
			return [g, s]
	return [-1, ""]


func test_battle_stage_dialog_follows_language():
	Content.set_lang("hans")
	var st := BattleStage.load_stage(1)
	var f := _first_line(st.talk, st.emsg.size())
	check(f[0] >= 0, "第 1 关有对白")
	var hans: String = f[1]
	Content.set_lang("hant")
	var hant: String = st.talk(f[0], 0)
	Content.set_lang("hans")
	var back: String = st.talk(f[0], 0)
	Content.set_lang("hans")
	check(hant != "" and hant != hans, "切繁体后同一句对白变成繁体: %s -> %s" % [hans, hant])
	eq(back, hans, "切回简体后又是简体")


func test_town_dialog_follows_language():
	Content.set_lang("hans")
	var st := RpgStage.load_stage(0)
	var f := _first_line(st.talk, st.emsg.size())
	check(f[0] >= 0, "城镇 0 有对白")
	var hans: String = f[1]
	Content.set_lang("hant")
	var hant: String = st.talk(f[0], 0)
	Content.set_lang("hans")
	var back: String = st.talk(f[0], 0)
	check(hant != "" and hant != hans, "切繁体后同一句对白变成繁体: %s -> %s" % [hans, hant])
	eq(back, hans, "切回简体后又是简体")

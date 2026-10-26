# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 交給提示的头像与目标范围 (原版实测, 原版 第 1 幕档与第 0 幕档):
##   满格提示「身上物品太多了…」、放弃提示 = 给出者的头像 (目标是主角封寒月或友军 NPC 应奉仁都一样);
##   「取得X.」(X = 给出的物品) = 接收者的头像, 接收者没有头像 (友军 NPC) 时回退给出者的;
##   友军 NPC 也能作为交給目标。

const REQUIRES_TEST := {
	"test_face_of_hero_mapping": ["content"]
}


func test_give_face_rules():
	eq(BattleActions.give_face("full", 1, 2), 1, "满格提示用给出者头像 (实测: 殷剑平给满格的封寒月, 头像是殷剑平)")
	eq(BattleActions.give_face("full", 1, -1), 1, "目标是友军 NPC 时同样用给出者 (实测: 应奉仁)")
	eq(BattleActions.give_face("cancel", 1, 2), 1, "放弃给予物品. 用给出者头像")
	eq(BattleActions.give_face("got", 1, 2), 2, "取得X. 用接收者头像 (实测: 封寒月)")
	eq(BattleActions.give_face("got", 1, -1), 1, "接收者是 NPC (无头像) 时回退给出者头像 (实测: 应奉仁收到燧石)")


## 战斗头像 = 单位号经布局表 battle.face 换成对白头像号: 上官远 (2) = FACE04、紫枫 (3) = FACE03 (原版 Man_Face 帧表对调, 实测), 其余 uid+1
func test_face_of_hero_mapping():
	var C = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Content")
	if C == null or not C.has_method("is_hero"):
		skip("没有内容库")
		return
	if C.packs.is_empty():
		C.load_packs([ContentDB.default_main()])
	var want := {0: 1, 1: 2, 2: 4, 3: 3, 4: 5, 5: 6, 6: 7, 7: 8, 8: 9, 9: 10}
	for uid in want:
		eq(BattleActions.face_of({"man": {"unit_id": uid}}), want[uid], "单位 %d" % uid)
	eq(BattleActions.face_of({"man": {"unit_id": 31}}), -1, "非主角没有头像")


class FStage:
	extends RefCounted
	var width := 4
	var height := 4
	func cell(_x, _y) -> Dictionary:
		return {"move": 0}


class FScene:
	extends RefCounted
	var units: Array = []
	var st := FStage.new()


func _unit(sc: FScene, x: int, y: int, side: int, ctl: bool) -> BattleUnit:
	var u := BattleUnit.new()
	u.shown = true
	u.cx = x
	u.cy = y
	u.alive = true
	u.controllable = ctl
	u.st.side = side
	sc.units.append(u)
	return u


## 友军 NPC (不受玩家控制, 同阵营) 也是交給目标; 敌人、不相邻的不是
func test_give_targets_include_friendly_npc():
	var sc := FScene.new()
	var a := _unit(sc, 1, 1, 0, true)
	var npc := _unit(sc, 2, 1, 0, false)
	var foe := _unit(sc, 1, 2, 1, false)
	var far := _unit(sc, 3, 3, 0, true)
	var rules = BattleRules.new(sc)
	var t: Array = rules.give_targets(a)
	check(t.has(npc), "友军 NPC 可作目标")
	check(not t.has(foe) and not t.has(far), "敌人、非相邻不是目标")
	eq(t.size(), 1)
	for u in sc.units:
		u.free()

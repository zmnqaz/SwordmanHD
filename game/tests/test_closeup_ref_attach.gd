# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 近景攻击动画的 ref 部件 (画守方) 与大体型守方 (玩家反馈第 33 幕飞星神剑打心脏贴图乱飞):
## 守方 misc 头计数 [2] != 0 时不挂守方 (ref 部件不画、命中窗口不藏守方); 绘制 第一个 ref 部件画在最底下。


func _fr(parts: Array) -> Dictionary:
	return {"parts": parts}


func test_big_defender_not_attached() -> void:
	check(BattleCloseup.defender_attaches({"action_counts": [0, 4, 0, 0]}), "普通守方 (计数[2]=0) 挂上")
	check(not BattleCloseup.defender_attaches({"action_counts": [0, 31, 1, 0]}), "心脏 171MISC (计数[2]=1) 不挂")
	check(BattleCloseup.defender_attaches({}), "没有 misc 数据按普通处理")


func test_ref_part_drawn_first_and_only_once() -> void:
	var a := {"tex": 5, "x": 1, "y": 1}
	var r1 := {"tex": null, "ref": 1, "x": 106, "y": 57}
	var r2 := {"tex": null, "ref": 2, "x": 99, "y": 59}
	var b := {"tex": 6, "x": 2, "y": 2}
	var got := AnimPlayer.draw_parts(_fr([a, r1, b, r2]), true)
	eq(got.size(), 3, "只画第一个 ref 部件")
	check(got[0] == r1, "ref 部件画在最底下")
	check(got[1] == a and got[2] == b, "普通部件保持原顺序")
	eq(AnimPlayer.draw_parts(_fr([a, r1, b]), false).size(), 2, "没挂 other 不画 ref 部件")


## 原版数据: 心脏不挂, 普通敌兵挂 (缺原版资源跳过)
func test_original_heart_misc() -> void:
	if not has_resource("original"):
		skip("缺原版资源")
		return
	check(not BattleCloseup.defender_attaches(Assets.anim("Sprite/man171/171misc")), "心脏")
	check(BattleCloseup.defender_attaches(Assets.anim("Sprite/man238/238misc")), "普通敌兵")


## 远程出手藏守方到攻方一侧那段 (action_counts[0]) 结束, 不是到第一个命中帧: 破魔杵 006s [15, 45, 69] 第 44 帧才命中,
## 原版第 15 帧切到守方一侧红幕就现身 (④); 玩家 2026-11-06 反馈复刻整段红幕看不到守方
func test_ranged_hides_defender_only_through_attacker_segment():
	var frames := []
	for i in 69:
		frames.append({"hit": 1 if i == 44 else 0})
	eq(BattleCloseup.ranged_hide_until({"action_counts": [15, 45, 69], "frames": frames}), 15, "破魔杵: 藏到第 15 帧")
	var plain := []
	for i in 30:
		plain.append({"hit": 1 if i == 7 else 0})
	eq(BattleCloseup.ranged_hide_until({"action_counts": [0, 0, 0], "frames": plain}), 7, "没有攻方一段: 退回第一个命中帧")
	eq(BattleCloseup.ranged_hide_until({"action_counts": [0, 0, 0], "frames": [{"hit": 0}]}), -1, "没有命中帧: 不藏")

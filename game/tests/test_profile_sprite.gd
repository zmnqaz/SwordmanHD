# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战场单位详情里非主角单位 (怪物 / NPC) 没有 Camp_man 立绘, 循环播放自己的战场站立动画 (原版就是动图, 用户指出; 夜魑会吐舌头)。
## 站立动画的帧范围算法同 BattleUnit.play_act(STAND, 南)。需要原版动画数据; 找不到时跳过。
const REQUIRES_TEST := {
	"test_stand_range_of_a_monster_sprite": ["original"],
}


func test_stand_range_of_a_monster_sprite():
	var dir := "Sprite/man201/201man"   # 四象门剑
	var r := UiProfile.stand_range(dir)
	check(r.x >= 2, "站立帧在头部若干特殊帧之后: 起 %d" % r.x)
	check(r.y > r.x, "至少一帧: [%d, %d)" % [r.x, r.y])
	var c: Array = Assets.anim(dir)["action_counts"]
	eq(r.y - r.x, maxi(int(c[0]), 1), "帧数 = 站立动作帧数 (没有则 1)")

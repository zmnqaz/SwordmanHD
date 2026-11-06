# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 近景动画贴图预热 (Assets.anim_textures / load_anims): 攻击动画一套上百张, 播到一半现载入会卡、一次跨过多帧
## (玩家反馈: 1.6 倍加速下近景二段攻击, 怪死了还显示 50 血)。预热之后播放时不再有新载入。
const REQUIRES := ["original"]

const DIR := "Sprite/man002/002A"   # 封寒月普攻, 116 张


func test_anim_textures_lists_every_texture():
	var rels := Assets.anim_textures(DIR)
	eq(rels.size(), (Assets.anim(DIR)["textures"] as Array).size(), "每张贴图一条")
	eq(Assets.anim_textures("Sprite/man002/nope"), [], "目录不存在给空")


func test_warm_then_play_loads_nothing_new():
	Assets.clear_cache()
	Assets.load_anims([DIR], true)
	var l0 := Assets.loads
	var a := AnimPlayer.new()
	a.play(DIR, 0, -1, false)
	for i in 400:
		a._process(0.04)
	eq(Assets.loads, l0, "预热过的动画整段播完没有现载入")
	a.free()
	Assets.clear_cache()

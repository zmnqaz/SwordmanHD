# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 演出贴图定位 (engine/fx): 约定偏移、锚点换算、技能演出解析
const REQUIRES_TEST := {  # 个别方法的依赖 (run_tests.gd 头注), 缺则 SKIP
	"test_skill_movie_from_has_movie": ["original"],
}


func test_conventions():
	FxPlace.reload()
	eq(FxPlace.offset("fx"), Vector2(-145, -88), "演出/光标约定 ")
	eq(FxPlace.offset("unit"), Vector2(-142, -110), "战场人物约定 ")
	eq(FxPlace.offset("object"), Vector2(-142, -106), "地图物件约定 ")
	# 格 (20,78): 原版镜头 (455,1784), 演出帧画在屏幕 (0,0) => 帧原点 = 镜头
	eq(FxPlace.at_cell(Vector2i(20, 78), "fx"), Vector2(455, 1784))
	eq(FxPlace.center_cam(Vector2i(20, 78)), Vector2(455, 1784))
	eq(FxPlace.at_pixel(Vector2(600.4, 1872), "unit"), Vector2(458, 1762), "单位像素位置取整后加约定")


func test_skill_movie_from_has_movie():
	CastFx.reload()
	var a := CastFx.for_skill({"animation_id": 71, "battle_type": -1, "battle_sprite": 0, "has_movie": true}, 1)
	eq(a["movie"], "Magic/magic071/M71", "has_movie: 全屏视频 ")
	eq(a["anim"], "Magic/magic071/M71", "视频之后仍播法术动画 (状态 4 -> 6)")
	eq(a["movie_skip"], ["cancel"], "只有取消键可跳过 (CBinkPlayer skip_confirm=0)")
	eq(CastFx.for_skill({"animation_id": 9, "battle_type": -1, "has_movie": true}, 1)["movie"], "Magic/magic009/M9")
	check(not CastFx.for_skill({"animation_id": 10, "battle_type": -1, "has_movie": false}, 1).has("movie"), "无 has_movie 不放视频")
	for id in [71, 70, 9, 60]:
		check(Assets.movie_exists("Magic/magic%03d/M%d" % [id, id]), "视频资源 %d 存在" % id)


func test_skill_anim_by_battle_type():
	CastFx.reload()
	var magic := CastFx.for_skill({"animation_id": 10, "battle_type": -1, "battle_sprite": 0}, 1)
	eq(magic["anim"], "Magic/magic010/M10", "法术: Magic 动画")
	eq(magic["convention"], "fx")
	eq(magic["anchor"], "target")
	eq(CastFx.for_skill({"move_attack_type": 1, "animation_id": 50, "battle_type": 1, "battle_sprite": 3}, 1)["anim"], "Sprite/man001/001-3s", "地图演出绝技: NNN-nS ")
	eq(CastFx.for_skill({"move_attack_type": 1, "animation_id": 51, "battle_type": 2, "battle_sprite": 4}, 1)["anim"], "Sprite/man001/001-4sm", "战斗画面+地图: NNN-nSM")
	eq(CastFx.for_skill({"move_attack_type": 1, "animation_id": 0, "battle_type": 1, "battle_sprite": 0}, 12)["anim"], "Sprite/man012/012s")
	var custom := CastFx.for_skill({"animation_id": 7, "battle_type": -1, "fx": {"anim": "Magic/my/{anim}", "anchor": "caster"}}, 1)
	eq(custom["anim"], "Magic/my/7", "技能记录 fx 字段覆盖")
	eq(custom["anchor"], "caster")

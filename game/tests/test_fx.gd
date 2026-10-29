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


## battle_type 2 的物理绝技 (电射星驰等) 先放施放者单人近景, 再转地图放 SM; 咒术 / 其它类型不放
func test_solo_closeup_only_for_battle_type_2_skills():
	const Skills = preload("res://engine/rules/skills.gd")
	check(Skills.has_solo_closeup({"move_attack_type": 1, "battle_type": 2}), "绝技 + battle_type 2")
	check(not Skills.has_solo_closeup({"move_attack_type": 1, "battle_type": 1}), "地图 S 绝技: 没有单人近景")
	check(not Skills.has_solo_closeup({"move_attack_type": 1, "battle_type": 0}), "battle_type 0 走原来的攻防近景")
	check(not Skills.has_solo_closeup({"move_attack_type": 0, "battle_type": 2}), "咒术忽略 battle_type")
	var path := ProjectSettings.globalize_path("res://").path_join("../data/skills.json").simplify_path()
	if not FileAccess.file_exists(path):
		return
	var ids := []
	for k in JSON.parse_string(FileAccess.get_file_as_string(path)):
		if Skills.has_solo_closeup(k):
			ids.append(int(k["id"]))
	eq(ids, [43, 45, 48, 50, 53, 58, 59, 60, 78, 82], "技能表里共 10 个: 电射星驰 火灵/天华神剑 刚烈破 分天斩 鬼神灭破 金刚法轮 双环映月 鬼缚之阵 万邪天灭")


## 地图演出绝技 (battle_type 1): 演出文件自带施放者, 落点是自己时才藏地图上的人 (battle_view.cast_fx); 演出表里要有这个开关
func test_map_skill_hides_caster_only_on_self():
	var fx := CastFx.for_skill({"move_attack_type": 1, "animation_id": 0, "battle_type": 1, "battle_sprite": 3}, 7)
	eq(fx["anim"], "Sprite/man007/007-3s")
	eq(bool(fx.get("hide_caster_on_self", false)), true, "type 1: 落点是自己时藏施放者")
	eq(bool(fx.get("hide_caster", false)), false, "不是一律藏")
	eq(bool(CastFx.for_skill({"move_attack_type": 1, "battle_type": 2, "battle_sprite": 2}, 1).get("hide_caster_on_self", false)), false, "type 2 (SM) 施放者全程可见 (实测火灵神剑)")


## 按方向分 4 段的演出动画 (007-1sm 等): 只放对应方向那一段; 方向取施放者 -> 落点, 同格用自身朝向
func test_direction_segments():
	var data := {"action_counts": [28], "frames": []}
	data["frames"].resize(112)
	eq(CastFx.direction_segment(data, 0), Vector2i(0, 28), "上 = 第 0 段")
	eq(CastFx.direction_segment(data, 1), Vector2i(28, 56), "右 = 第 1 段")
	eq(CastFx.direction_segment(data, 2), Vector2i(56, 84), "下 = 第 2 段")
	eq(CastFx.direction_segment(data, 3), Vector2i(84, 112), "左 = 第 3 段")
	var plain := {"action_counts": [38], "frames": []}
	plain["frames"].resize(68)
	eq(CastFx.direction_segment(plain, 1), Vector2i(0, -1), "近景攻击动画 (action_counts[0] = 命中帧号) 不分段")
	eq(CastFx.direction_segment({"action_counts": [0], "frames": [1, 2]}, 1), Vector2i(0, -1), "没有分段")
	eq(CastFx.direction_variant(Vector2i(9, 12), Vector2i(9, 18)), 2, "目标在下")
	eq(CastFx.direction_variant(Vector2i(9, 12), Vector2i(9, 5)), 0, "目标在上")
	eq(CastFx.direction_variant(Vector2i(9, 12), Vector2i(15, 12)), 1, "目标在右")
	eq(CastFx.direction_variant(Vector2i(9, 12), Vector2i(3, 12)), 3, "目标在左")
	eq(CastFx.direction_variant(Vector2i(9, 12), Vector2i(9, 12), 1), 1, "同格: 用自身朝向")

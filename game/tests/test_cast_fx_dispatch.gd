# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 技能演出分派 (engine/fx/cast_fx.gd CastFx.for_skill): battle_type 只对绝技有意义, 咒术一律放 Magic/M<animation_id>
## (先看 skill+0)。审计 2026-10-12。
const REQUIRES := ["content"]


func test_spell_with_battle_type_1_still_plays_magic_anim():
	CastFx.reload()
	var sk := {"move_attack_type": 0, "battle_type": 1, "animation_id": 22, "battle_sprite": 0}   # 妖氛鬼雾 (88)
	var fx := CastFx.for_skill(sk, 210)
	eq(fx["anim"], "Magic/magic022/M22", "咒术: Magic 动画, 不是施放者的 NNNs")


func test_physical_skill_uses_battle_type_sprite_anim():
	CastFx.reload()
	var s1 := {"move_attack_type": 1, "battle_type": 1, "animation_id": 0, "battle_sprite": 0}
	eq(CastFx.for_skill(s1, 210)["anim"], "Sprite/man210/210s", "绝技 battle_type 1: 施放者的 S")
	var s2 := {"move_attack_type": 1, "battle_type": 2, "animation_id": 0, "battle_sprite": 2}
	eq(CastFx.for_skill(s2, 5)["anim"], "Sprite/man005/005-2sm", "绝技 battle_type 2: SM, 带 -n")

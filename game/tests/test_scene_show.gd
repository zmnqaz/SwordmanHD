# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 场景演出 SceneShow / 商店进出时序。原版实测 (40 ms 间隔录像, 商店 Shop06 武器店, §商店进出时序):
##   进店: 城镇渐黑 14 tick → 黑场 4 tick → 店面渐入 14 tick → 开场动画 120 tick → 物品窗
##   退店: 物品窗渐隐 7 tick → 店面渐黑 14 tick → 黑场 6 tick → 城镇渐入 14 tick
const REQUIRES_TEST := {
	"test_every_shop_goes_through_black": ["content"],
	"test_shop_timeline_matches_original": ["content"]
}  # 个别方法的依赖 (同上)

const SceneShow := preload("res://engine/ui/scene_show.gd")


func test_every_shop_goes_through_black():
	var n := 0
	for sh in Content.table("shops"):
		var sp = sh.get("show")
		if not (sp is Dictionary):
			continue
		n += 1
		check(bool(sp.get("via_black", false)), "%s 进出店经黑场" % sh["id"])
		eq([int(sp["black_hold"][0]), int(sp["black_hold"][1])], [4, 6], "%s 黑场停留 [进, 出]" % sh["id"])
		eq(sp.get("ui_fade_out", []).size(), 7, "%s 物品窗渐隐 7 档" % sh["id"])
		eq(sp.get("ui_fade_tick"), 1, "%s 物品窗渐隐每档 1 tick" % sh["id"])
	check(n >= 9, "至少检查了 9 家店, 实际 %d" % n)


func test_shop_timeline_matches_original():
	var sp: Dictionary = Content.shop("town00.0")["show"]
	var frames: Array = Assets.anim(String(sp["anim"]))["frames"] if SceneShow.valid(sp) else []
	var tl := SceneShow.timeline(sp, frames)
	if frames.is_empty():  # 没有原版素材的环境: 只核对渐变段
		eq(tl["enter"].slice(0, 3), [14, 4, 14], "进店 (无素材时只核对渐变段)")
	else:
		eq(tl["enter"], [14, 4, 14, 120], "进店: 城镇渐黑 / 黑场 / 店面渐入 / 开场动画 (Shop06 开场 40 帧, 时长合计 120 tick)")
	eq(tl["leave"], [7, 14, 6, 14], "退店: 物品窗渐隐 / 店面渐黑 / 黑场 / 城镇渐入")


func test_crossfade_without_black():
	var tl := SceneShow.timeline({"anim": "x", "fade_in": [2, 4, 6], "fade_out": [6, 4, 2], "fade_tick": 2})
	eq(tl["enter"].slice(0, 3), [0, 0, 6], "不经黑场 (营地背景): 只有渐入")
	eq(tl["leave"], [0, 6, 0, 0], "不经黑场: 只有渐出")

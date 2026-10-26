# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## UiSlide 重入/取消 (信息条滑动竞态): 玩家选目标后立刻确认攻击时, hide_info 走在滑入动画中途,
## 旧 tween 若不取消会把 visible 拉回 —— 表现为被打死的单位信息条在结算对白间隙里一直挂着 (第 0 幕实测)。
## 用真实等帧断言行为, 不碰 UiSlide 内部; 修复前跑本文件应当失败 (复现)。
const REQUIRES_TEST := {
	"test_close_block_during_slide_stays_closed": ["original"],
	"test_hide_during_slide_stays_hidden": ["original"]
}  # 个别方法的依赖 (同上)

const SLIDE_TIME := 0.5  # BRI_OFFSETS 5 档 x 0.04s = 0.2s; headless 帧率不定, 用真实时间等才与帧率解耦


func _wait_slide() -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(SLIDE_TIME).timeout


func _bar() -> UiInfoBar:
	var tree := Engine.get_main_loop() as SceneTree
	var bar := UiInfoBar.new()
	tree.root.add_child(bar)
	bar.use_screen_anchors()
	return bar


func _info(hp := 89) -> Dictionary:
	return {"name": "夜魑", "hp": hp, "hp_max": 89, "mp": 0, "mp_max": 0, "move": 23, "move_max": 23,
		"attack": 30, "defence": 10, "lv": 1, "exp": 0, "buffs": [false, false, false, false]}


## 症状复现: 滑入中途 hide (选目标后马上确认攻击), 信息条必须保持隐藏
func test_hide_during_slide_stays_hidden() -> void:
	var bar := _bar()
	bar.show_unit(_info(), false, true, true)
	check(bar._left.visible and bar._right.visible, "滑入时可见")
	bar.hide_bar()
	check(not bar._left.visible and not bar._right.visible, "hide 后立刻不可见")
	await _wait_slide()
	check(not bar._left.visible and not bar._right.visible, "动画走完后仍保持隐藏")
	bar.queue_free()


## 关右块 (detail=false) 也一样: 旧滑入不能把右块拉回来
func test_close_block_during_slide_stays_closed() -> void:
	var bar := _bar()
	bar.show_unit(_info(), false, true, true)
	bar.show_unit(_info(), false, false, true)
	await _wait_slide()
	check(not bar._right.visible, "右块动画走完后仍保持关闭")
	check(bar._left.visible, "左块正常显示")
	bar.queue_free()


## 同节点重入: 滑出中再滑入 -> 以最后一次为准 (可见); 滑入中再滑出 -> 结束后隐藏
func test_reentry_last_wins() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var n := Node2D.new()
	tree.root.add_child(n)
	UiSlide.run(n, Vector2.ZERO, Vector2.LEFT, UiSlide.BRI_OFFSETS, false)
	UiSlide.run(n, Vector2.ZERO, Vector2.LEFT, UiSlide.BRI_OFFSETS, true)
	await _wait_slide()
	check(n.visible, "滑出中重入滑入: 以滑入为准")
	UiSlide.run(n, Vector2.ZERO, Vector2.LEFT, UiSlide.BRI_OFFSETS, true)
	UiSlide.run(n, Vector2.ZERO, Vector2.LEFT, UiSlide.BRI_OFFSETS, false)
	await _wait_slide()
	check(not n.visible, "滑入中重入滑出: 以滑出为准")
	n.queue_free()

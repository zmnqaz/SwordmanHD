# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 帧推进被卡顿一次跨过多帧时, 被跨过的有声帧也要响 (scripts/anim_player.gd _catch_up_sounds)。
## 原版固定 25 tick 逐帧推进, 区间内每个进入的帧都发声; 复刻按累计时间算帧, 原先一次 delta 跨过多帧时只播最终帧的声音。
## 审计 2026-10-12: 这是「音效偶尔丢」的通用根因之一 (如第 7 幕法阵击碎帧 77 的呻吟)。
const REQUIRES := ["original"]

const DIR := "Stage/Stage07/Eanm_07"   # 紫枫的剧情动画, 144 帧, 帧 6~30、77 带声


func _expected(start: int, end: int) -> int:
	var n := 0
	var a := AnimPlayer.new()
	a.show_frame(DIR, 0)
	for f in range(start, end):
		if int(a.data["frames"][f]["sound"]) >= 0:
			n += 1
	a.free()
	return n


func test_one_big_hitch_still_plays_every_sound_frame():
	var a := AnimPlayer.new()
	a.play(DIR, 0, 40, false)
	a._process(100.0)   # 一次卡顿跨过整段
	eq(a.sfx_count, _expected(0, 40), "跨过的有声帧都响了一次")
	check(not a.playing, "播完")
	a.free()


func test_normal_stepping_plays_each_once():
	var a := AnimPlayer.new()
	a.play(DIR, 0, 40, false)
	for i in 400:
		a._process(0.04)
	eq(a.sfx_count, _expected(0, 40), "正常逐帧推进: 每个有声帧一次, 不重复")
	a.free()


func test_partial_skip_in_the_middle():
	var a := AnimPlayer.new()
	a.play(DIR, 70, 85, false)   # 含帧 77 (呻吟)
	a._process(0.04)
	a._process(0.04 * 9)         # 一次跳 9 帧
	for i in 30:
		a._process(0.04)
	eq(a.sfx_count, _expected(70, 85), "中间被跳过的帧 77 的声音补上了")
	a.free()


## 帧事件 frame_shown 也要补: 近景命中帧扣血挂在它上面, 卡顿跨过命中帧 (含一次跨过末尾直接播完) 时体力条停在半截 (玩家反馈: 怪死了还显示 50 血)
func test_hitch_still_emits_every_frame_event():
	var a := AnimPlayer.new()
	var seen: Array = []
	a.frame_shown.connect(func(f: int): seen.append(f))
	a.play(DIR, 70, 85, false)
	a._process(0.04)
	a._process(0.04 * 9)   # 中间跳帧
	a._process(100.0)      # 一次跨过末尾
	eq(seen, range(70, 85), "每帧的帧事件按顺序各一次")
	check(not a.playing, "播完")
	a.free()

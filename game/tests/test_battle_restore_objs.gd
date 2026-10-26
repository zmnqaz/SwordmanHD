# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战阵重现时地图物件的恢复 (BattleScene.apply_obj_snapshot): 帧 -1 (可见但从没画过帧) 恢复后仍什么都不画。
## 用户 2026-10-11 报告: 第 3 幕战阵重现后背景上冒出一堆人物贴图 (原先把 -1 夹成第 0 帧画出来)。
const REQUIRES := ["original"]

const BattleScene = preload("res://engine/battle/battle_scene.gd")
const DIR := "Stage/Stage03/Eanm_14"


func _snap(frame: int, playing := false, visible := true) -> Dictionary:
	return {"dir": DIR, "frame": frame, "playing": playing, "visible": visible, "x": 213.0, "y": 5380.0}


func test_never_drawn_object_stays_blank():
	var a := AnimPlayer.new()
	a.play_sound = false
	BattleScene.apply_obj_snapshot(a, _snap(-1))
	eq(a.frame, -1, "帧 -1 不画第 0 帧")
	check(not a.playing, "不在播放")
	eq(a.dir, DIR, "动画目录仍记着 (之后事件播放用)")
	eq(a.position, Vector2(213, 5380), "位置")
	a.free()


func test_shown_frame_and_playing_restored():
	var a := AnimPlayer.new()
	a.play_sound = false
	BattleScene.apply_obj_snapshot(a, _snap(3))
	eq(a.frame, 3, "停在第 3 帧")
	var b := AnimPlayer.new()
	b.play_sound = false
	BattleScene.apply_obj_snapshot(b, _snap(1, true))
	check(b.playing, "播放中的接着播")
	var c := AnimPlayer.new()
	c.play_sound = false
	BattleScene.apply_obj_snapshot(c, _snap(0, false, false))
	check(not c.visible, "隐藏的仍隐藏")
	a.free()
	b.free()
	c.free()


## 剧情「播放一次」的地图物件动画要出声 (第 8 幕朱慎攻击法阵的音效曾因物件一律静音而丢失), 播完关回静音
func test_one_shot_object_sound_on_then_off():
	var a := AnimPlayer.new()
	a.play_sound = false
	BattleScene.one_shot_sound(a)
	check(a.play_sound, "播放一次: 开声音")
	a.finished.emit()
	check(not a.play_sound, "播完: 关回静音")
	a.free()


## 单帧 obj_play (from==to) 显示该帧、声音只响一次且不留开着的 play_sound
func test_single_frame_sound_restores_flag():
	var a := AnimPlayer.new()
	a.play_sound = false
	a.dir = "Stage/Stage31/Eanm_01"
	BattleScene.single_frame_sound(a, 1)
	eq(a.frame, 1, "显示了第 1 帧")
	check(not a.play_sound, "播完立刻关回静音")
	a.free()

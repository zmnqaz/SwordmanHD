# SPDX-License-Identifier: GPL-3.0-only
class_name UiPanel
extends Node2D
## 面板: 把原版界面素材 (如 Misc/Man_int) 的某一帧当底图, 左上角放在 position (原版坐标)。
## 帧里部件自带的偏移照常生效 (与原版贴 SAF 帧一致)。可选播放 [frame, end) 循环动画。

var anim_dir := ""
var frame := 0
var _anim: AnimPlayer

static var _rects := {}


func _init(dir := "", f := 0, pos := Vector2.ZERO) -> void:
	position = pos
	_anim = AnimPlayer.new()
	_anim.play_sound = false
	add_child(_anim)
	if dir != "":
		set_frame(dir, f)


func set_frame(dir: String, f: int) -> void:
	anim_dir = dir
	frame = f
	_anim.show_frame(dir, f)


## 循环播放 [start, end) 帧 (图标选中时的呼吸动画等)
func play(dir: String, start: int, end: int, looped := true) -> void:
	anim_dir = dir
	frame = start
	_anim.play(dir, start, end, looped)


## 本帧的大小 (不透明区域, 原版像素)
func size() -> Vector2:
	return frame_rect(anim_dir, frame).size


## 某帧所有部件不透明区域的外接矩形 (帧坐标, 原版像素, 整数)。原版按 SAF 帧的实际大小排版 (如 面板居中、
## 图标间距); 一律按原版 1 倍贴图算 (Assets.used_rect), 不读 hd4x/hd6x, 所以与画质无关。
static func frame_rect(dir: String, f: int) -> Rect2:
	var key := "%s#%d" % [dir.to_lower(), f]
	if _rects.has(key):
		return _rects[key]
	var data := Assets.anim(dir)
	var r := Rect2()
	var first := true
	for p in data["frames"][f]["parts"]:
		if p["tex"] == null:
			continue
		var used := Assets.used_rect("%s/%s" % [data["dir"], data["textures"][int(p["tex"])]["file"]])
		var pr := Rect2(Vector2(used.position) + Vector2(p["x"], p["y"]), Vector2(used.size))
		r = pr if first else r.merge(pr)
		first = false
	_rects[key] = r
	return r


## 某帧第一个部件的贴图与偏移: {"texture", "scale", "hd", "offset"} (字模等按格切图用)
static func frame_texture(dir: String, f: int) -> Dictionary:
	var data := Assets.anim(dir)
	for p in data["frames"][f]["parts"]:
		if p["tex"] == null:
			continue
		var t: Dictionary = Assets.tex("%s/%s" % [data["dir"], data["textures"][int(p["tex"])]["file"]]).duplicate()
		t["offset"] = Vector2(p["x"], p["y"])
		return t
	return {}

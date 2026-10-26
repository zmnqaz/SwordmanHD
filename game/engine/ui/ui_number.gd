# SPDX-License-Identifier: GPL-3.0-only
class_name UiNumber
extends Node2D
## 字模数字: 某素材某帧的一行 8x7 字模 (0~9 数字, 10 空白底, 11 「?」, 12 「+」 13 「-」; Sfman 的 12/13 是「:」「/」), 步进 7。
## space: "blank" 空格画第 10 格 (多数界面), "gap" 空格只占位不画 (存读档), "skip" 空格既不画也不占位 (五魂已加点数; 是 blank, 见布局表 camp.spirit.added)。
## vertical: 竖排, 步进 6 (体态五魂数值、五魂化蕴数值)。

const W := 8
const H := 7
var dir := ""
var frame := 0
var space := "blank"
var vertical := false
## 步进 (原版像素); -1 = 缺省 (横排 7、竖排 6)。布局表 digits.step
var step := -1
## 「?」在字模里的格号 (多数 11; 近景 Fig_misc 为 10)。布局表 digits.qmark
var qmark := 11
var text := "":
	set(v):
		text = v
		queue_redraw()
var _tex := {}


func _init(d: String, f: int, t := "", pos := Vector2.ZERO, space_mode := "blank", vert := false) -> void:
	dir = d
	frame = f
	position = pos
	space = space_mode
	vertical = vert
	text = t


func set_frame(f: int) -> void:
	if f != frame:
		frame = f
		_tex = {}
		queue_redraw()


func _draw() -> void:
	if _tex.is_empty():
		_tex = UiPanel.frame_texture(dir, frame)
	var tex: Texture2D = _tex["texture"]
	var sc := float(_tex["scale"])
	var off: Vector2 = _tex["offset"]
	texture_filter = TextureSource.filter_for(_tex["hd"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * sc)
	var k := 0
	for c in text:
		var g := -1
		match c:
			" ":
				if space == "skip":
					continue
				g = 10 if space == "blank" else -1
			"?": g = qmark
			":", "+": g = 12
			"/", "-": g = 13
			_: g = int(c)
		if g >= 0:
			var st := step if step > 0 else (6 if vertical else 7)
			var p := Vector2(0, st * k) if vertical else Vector2(st * k, 0)
			var src := Rect2(Vector2(W * g, 0) / sc, Vector2(W, H) / sc)
			draw_texture_rect_region(tex, Rect2((p + off) / sc, Vector2(W, H) / sc), src)
		k += 1

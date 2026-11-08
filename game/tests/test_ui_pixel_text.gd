# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## UiPixelText: 布局表 pixel_fonts 的手绘点阵字 (存档档位条「回合/」「时长/」); 排宽、上色、描边、缺字、高清柔化

const REQUIRES_TEST := {"test_save_labels_have_glyphs": ["original"]}   # hd_like 要读 Misc/Sfman 判断是否高清

const FONT := {"gap": 1, "colors": {"b": [99, 24, 0], "e": [198, 123, 49]},
	"glyphs": {"口": ["bbb", "b.b", "bbb"], "/": ["..e", ".e.", "e.."]}}


func test_size_and_pixels():
	var t := UiPixelText.new(FONT, "口/口")
	eq(t.size(), Vector2(11, 3), "字宽 3×3 + 字间 1×2")
	var img := t.image()
	eq(img.get_pixel(0, 0), Color8(99, 24, 0), "笔画色")
	eq(img.get_pixel(1, 1).a, 0.0, "「.」透明")
	eq(img.get_pixel(3, 0).a, 0.0, "字间空 1 像素")
	eq(img.get_pixel(6, 0), Color8(198, 123, 49), "斜杠过渡色")
	t.free()


func test_outline_around_ink_and_holes():
	var f := FONT.duplicate()
	f["outline"] = [239, 222, 148]
	var t := UiPixelText.new(f, "口")
	eq(t.size(), Vector2(3, 3), "排宽不算描边")
	var img := t.image()
	eq([img.get_width(), img.get_height()], [5, 5], "四周各多 1 像素描边")
	eq(img.get_pixel(1, 1), Color8(99, 24, 0), "笔画挪到 (1,1)")
	eq(img.get_pixel(0, 1), Color8(239, 222, 148), "左边描边")
	eq(img.get_pixel(2, 2), Color8(239, 222, 148), "字里空洞也描")
	eq(img.get_pixel(0, 0).a, 0.0, "斜角不描 (4 邻, 同原版字模)")
	t.free()


func test_missing_glyph_skipped():
	var t := UiPixelText.new(FONT, "口X")
	eq(t.size(), Vector2(3, 3), "缺字不占位")
	t.free()


func test_hd_soften_keeps_size_and_rounds_corners():
	var t := UiPixelText.new(FONT, "口")
	var img := t.image()
	t.free()
	var big := UiPixelText.soften(img, 4)
	eq([big.get_width(), big.get_height()], [12, 12], "放大 4 倍")
	check(big.get_pixel(0, 0).a < 1.0 and big.get_pixel(0, 0).a > 0.0, "外角柔化成半透明")
	eq(big.get_pixel(1, 1), Color8(99, 24, 0), "笔画内部颜色不变")


## 布局表里存档条标签用到的字都在字表里 (简繁)
func test_save_labels_have_glyphs():
	UiLayout.reload()
	var fonts: Dictionary = UiLayout.data().get("pixel_fonts", {})
	for s in ["回合/", "时长/", "時長/"]:
		for c in s:
			check(fonts.get("camp_save_label", {}).get("glyphs", {}).has(c), "标签字表有「%s」" % c)
	for c in "0123456789:?":
		check(fonts.get("camp_save_num", {}).get("glyphs", {}).has(c), "数值字表有「%s」" % c)
	var t := UiLayout.pixel_text("camp.save.slot.turns", "回合/")
	eq(t.size(), Vector2(19, 6), "「回合/」宽 19, 主体 6 行同「位」")
	t.free()
	var a := UiLayout.pixel_text("camp.save.slot.turns_value", "99999")
	var b := UiLayout.pixel_text("camp.save.slot.turns_value", "7")
	eq(a.position.x + a.size().x, b.position.x + b.size().x, "回合数值靠右按位对齐")
	eq(a.position.x, UiLayout.at("camp.save.slot.turns_value").x, "最大 99999 正好占满框")
	a.free()
	b.free()
	var c := UiLayout.pixel_text("camp.save.slot.play_time_value", "9999:59")
	var d := UiLayout.pixel_text("camp.save.slot.play_time_value", "3:25")
	eq(c.position.x + c.size().x, d.position.x + d.size().x, "时长靠右对齐")
	eq(c.position.x, UiLayout.at("camp.save.slot.play_time_value").x, "最大 9999:59 正好占满框")
	c.free()
	d.free()

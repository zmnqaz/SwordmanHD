# SPDX-License-Identifier: GPL-3.0-only
class_name UiPixelText
extends Node2D
## 点阵字: 复刻新增的手绘小字 (原版素材里没有的字, 照旁边原版字模数字的字高、笔画色与描边手绘),
## 字形在布局表 pixel_fonts[名字] 里, 文字照常走文案表 (简繁/ mod 换字只改文案, 缺的字在字表里补)。
## 字表: {"gap": 字间空几像素, "colors": {字符: 颜色}, "glyphs": {字: ["行", ...]}, "outline": 颜色, "hd_like": {"anim": 素材, "frame": 帧}}
##   每字等高, 行内 "." 透明, 其它字符查 colors; 字宽 = 行长。缺字跳过并警告一次。
##   outline: 笔画外圈 (上下左右 4 邻, 含字里的空洞) 补一圈描边色, 同原版字模数字; 描边画在 size() 外 1 像素。
##   高清下不描: 高清字模数字的这圈浅底被 GlyphKey 抠掉了, 描上反而多出浅框。
## 画质: 跟 hd_like 那张素材同档 —— 它是原图就逐像素最近邻 (与旁边的原版字模一样锐利);
##   它是高清就把字形 SCALE 倍放大后柔化边角、线性过滤 (与 AI 放大的字模观感一致), 不出锯齿方块。

const SCALE := 4

var font := {}
var hd := false
var text := "":
	set(v):
		text = v
		_tex = null
		queue_redraw()
var _tex: ImageTexture
static var _warned := {}


func _init(f: Dictionary, t := "", pos := Vector2.ZERO, hd_tex := false) -> void:
	font = f
	hd = hd_tex
	position = pos
	text = t


## 整串宽高 (原版像素)
func size() -> Vector2:
	var w := 0
	var h := 0
	var gap := int(font.get("gap", 1))
	for c in text:
		var g := _glyph(c)
		if g.is_empty():
			continue
		w += (gap if w > 0 else 0) + String(g[0]).length()
		h = maxi(h, g.size())
	return Vector2(w, h)


func _glyph(c: String) -> Array:
	var g = font.get("glyphs", {}).get(c)
	if g is Array and not g.is_empty():
		return g
	if c != " " and not _warned.has(c):
		_warned[c] = true
		push_warning("UiPixelText: 点阵字表缺字「%s」" % c)
	return []


## 描边占的边距 (有 outline 时 1)
func pad() -> int:
	return 1 if font.has("outline") else 0


## 1 倍字形图 (透明底; 有描边时四周各多 pad() 像素)
func image() -> Image:
	var sz := size()
	if sz.x <= 0 or sz.y <= 0:
		return null
	var m := pad()
	var img := Image.create(int(sz.x) + 2 * m, int(sz.y) + 2 * m, false, Image.FORMAT_RGBA8)
	var cols: Dictionary = font.get("colors", {})
	var gap := int(font.get("gap", 1))
	var x := 0
	for c in text:
		var g := _glyph(c)
		if g.is_empty():
			continue
		for r in g.size():
			var row := String(g[r])
			for k in row.length():
				var ch := row[k]
				if ch != "." and cols.has(ch):
					img.set_pixel(m + x + k, m + r, UiLayout.color(cols[ch]))
		x += String(g[0]).length() + gap
	if m > 0 and not hd:
		var oc := UiLayout.color(font["outline"])
		var ink := img.duplicate() as Image
		for y in img.get_height():
			for xx in img.get_width():
				if ink.get_pixel(xx, y).a > 0.0:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(xx, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and ink.get_pixelv(q).a > 0.0:
						img.set_pixel(xx, y, oc)
						break
	return img


## 高清: 最近邻放大 SCALE 倍后做一次 3x3 平均 (预乘 alpha), 方块边角变圆, 线性过滤画回原尺寸
static func soften(src: Image, scale: int) -> Image:
	var big := src.duplicate() as Image
	big.resize(src.get_width() * scale, src.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var w := big.get_width()
	var h := big.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var acc := Vector4.ZERO
			var n := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var xx: int = x + dx
					var yy: int = y + dy
					n += 1
					if xx < 0 or yy < 0 or xx >= w or yy >= h:
						continue
					var p := big.get_pixel(xx, yy)
					acc += Vector4(p.r * p.a, p.g * p.a, p.b * p.a, p.a)
			acc /= n
			out.set_pixel(x, y, Color(acc.x / acc.w, acc.y / acc.w, acc.z / acc.w, acc.w) if acc.w > 0.0 else Color(0, 0, 0, 0))
	return out


func _draw() -> void:
	if _tex == null:
		var img := image()
		if img == null:
			return
		_tex = ImageTexture.create_from_image(soften(img, SCALE) if hd else img)
	texture_filter = TextureSource.filter_for(hd)
	var sc := float(SCALE) if hd else 1.0
	draw_set_transform(-Vector2.ONE * pad(), 0.0, Vector2.ONE / sc)
	draw_texture(_tex, Vector2.ZERO)

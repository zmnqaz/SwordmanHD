# SPDX-License-Identifier: GPL-3.0-only
class_name GlyphKey
extends RefCounted
## 高清画质下抠掉原版小素材自带的羊皮纸底 (shaders/glyph_key.gdshader)。
## 原版的字模数字、增益图标等每格都带一块和原版面板同色的底, 1 倍画面里看不出; 高清面板颜色不同, 底就露成一个个浅色方块。
## 底色取贴图里一块纯底区域的平均色 (调用方给区域, 原版像素), 按 (贴图, 区域) 缓存。

const SHADER := preload("res://shaders/glyph_key.gdshader")
static var _cache := {}


## sample: 原版 1 倍像素坐标里的纯底区域; scale: 贴图的缩放 (Assets.tex 的 scale, = 1/倍数)。取不到像素返回 null (不抠)
static func material(tex: Texture2D, sample: Rect2, scale: float) -> ShaderMaterial:
	var key := "%d:%s" % [tex.get_rid().get_id(), sample]
	if not _cache.has(key):
		_cache[key] = _make(tex, sample, scale)
	return _cache[key]


static func _make(tex: Texture2D, sample: Rect2, scale: float) -> ShaderMaterial:
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var r := Rect2i(Vector2i(sample.position / scale), Vector2i(sample.size / scale)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var sum := Vector3.ZERO
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
	var n := r.get_area()
	if n <= 0:
		return null
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("key", sum / n)
	return m

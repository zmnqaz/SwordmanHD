# SPDX-License-Identifier: GPL-3.0-only
class_name UiText
extends Node2D
## 统一文字排版: 一切原版样式的界面文字都走这里, 任何字体的基线与对齐一致。
##
## 字格模型 (原版字体函数 (buf, w, h, x, y, 0, str, flags)): position 是第一个字格的左上角 (原版像素)。
##   汉字 (Big5 双字节) 占 size x size 的字格 (正文 12x12), 半角 (单字节) 占 size/2 宽; 第 n 个字的 x = 前面的字节数 * size/2。
##   每个字形放进自己的字格: 全角字形从字格左边起, 半角字形在半格里水平居中 (矢量字体半角宽 6.8 左右)。
##   宽度/折行/居中一律按字节算 (measure/bytes), 字体实测宽度不参与定位, 所以换字体不会挪动任何东西。
## 基线: 每个字库字体在清单 (UiFonts, ui_theme/fonts.json) 里有 baseline_in_cell (原版像素, 12 号字格内),
##   由 生成工具的脚本 按字体度量量出, 使汉字墨迹中心落在原版 Tfont 字格第 6.4 行; 其他字号按比例。换字体 = 换基线, 脚本与布局不动。
## 样式 flags (布局表 text_styles): 0 单色; 5 = 先在 (−1,0)(+1,0) 画光边 text.halo 再画本色 (flags&4 用);
##   edge5 = 近景名字的暗描边。edge_color 不透明时等同样式 5 换边色。
## 行距 line_height (原版对话框 13)。visible_chars >= 0 时只显示前若干字 (对话框逐字显示)。
## 绘制: 放在 UiLayer.root (放大 SCALE 倍) 下, 以 size*SCALE 的字号画再缩小 1/SCALE, 1:1 采样不糊。

## 原版正文主色 0x59a5 (x*255/31 换算)
const BROWN := Color8(181, 107, 41)
## 内置字库缺的字 的替代字形: 字库没有该字时才换, 否则靠 Godot 系统字体回退。排版按字节宽, 换字形不挪位置
const SUBST := {"\u2027": "\u00b7", "\u2212": "-"}

var text := "":
	set(v):
		text = v
		_relayout()
var size := 12.0:
	set(v):
		size = v
		_relayout()
var color := BROWN:
	set(v):
		color = v
		queue_redraw()
var line_height := 13.0:
	set(v):
		line_height = v
		queue_redraw()
## 自动折行宽度 (原版像素, 按字节宽逐字断行); 0 = 只按 "\n" 分行
var max_width := 0.0:
	set(v):
		max_width = v
		_relayout()
var visible_chars := -1:
	set(v):
		visible_chars = v
		queue_redraw()
## 样式: 布局表 text_styles 的键 (0 / 5 / "edge5" ...)
var flags: Variant = 0:
	set(v):
		flags = v
		queue_redraw()
## 自定边色 (不透明时按样式 5 的位置画边, 覆盖 flags 里的边色)
var edge_color := Color(0, 0, 0, 0):
	set(v):
		edge_color = v
		queue_redraw()

var lines := PackedStringArray()


func _init(t := "", sz := 12.0, c := BROWN, pos := Vector2.ZERO) -> void:
	size = sz
	color = c
	position = pos
	text = t
	Assets.font_changed.connect(queue_redraw)  # 设定里换字体: 立即重画


## 按布局表元素建文字: text 字段给 font/flags/color/line_height/max_width/align, 位置 = UiLayout.at(id, i, vars)
## (第 i 个重复、公式变量 vars)。对齐 center_in / right 按 text.box (或元素 size) 的宽、center_bytes 按 text.center_x,
## 位置在每次改 text 时按字节宽重算 (见 align_x), 所以调用方只给文字。
static func make(id: String, t := "", i := 0, vars := {}) -> UiText:
	var spec := UiLayout.text(id)
	var n := UiText.new("", float(spec.get("size", 12)), spec["color"], UiLayout.at(id, i, vars))
	n.apply_spec(spec)
	var al := String(spec.get("align", "left"))
	if al != "left":
		var box = spec.get("box")
		var bw := float(box[0]) if box is Array else (float(box) if box != null else UiLayout.size_of(id, vars).x)
		n.set_align(al, bw, float(spec.get("center_x", 0)))
	n.text = t
	n.set_meta("ui_layout_id", id)
	return n


## 对齐: align = left / center_in / right (在 [position.x, position.x+box_w) 内) / center_bytes (以 center_x 为中, 相对 position.x)
var align := "left"
var _align_x0 := 0.0
var _align_w := 0.0
var _align_cx := 0.0


func set_align(al: String, box_w := 0.0, center_x := 0.0) -> void:
	align = al
	_align_x0 = position.x
	_align_w = box_w
	_align_cx = center_x
	_realign()


func _realign() -> void:
	if align != "left":
		position.x = UiText.align_x(align, text, _align_x0, _align_w, _align_x0 + _align_cx, size)


## 套用文字规格 (UiLayout.text 的结果)
func apply_spec(spec: Dictionary) -> void:
	size = float(spec.get("size", size))
	color = spec.get("color", color)
	line_height = float(spec.get("line_height", line_height))
	flags = spec.get("flags", 0)
	if spec.has("max_width"):
		max_width = float(spec["max_width"])


## 字数 (不含换行)
func char_count() -> int:
	var n := 0
	for l in lines:
		n += l.length()
	return n


## 某行的排版宽度 (原版像素, 按字节)
func line_width(i: int) -> float:
	return measure(lines[i], size)


# ---------------------------------------------------------------- 排版规则 (静态, 与字体无关)

## 原版坐标 (320x200) 的文字: 在不缩放的图层上按 SCALE 倍位置和字号绘制, 保持清晰 (原 Game.make_label)
static func make_label(text: String, pos: Vector2, size: float, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", game_font(bold))
	l.add_theme_font_size_override("font_size", int(round(size * Assets.SCALE)))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.position = pos * Assets.SCALE
	return l


## 当前游戏字体 (设定里换字体时已建的 Label / RichTextLabel 跟着变, 见 Assets.font)
static func game_font(bold := false) -> Font:
	return Assets.font(bold)


## 字节数 (原版 Big5: 汉字 2、ASCII 1)
static func bytes(s: String) -> int:
	var n := 0
	for ch in s:
		n += 1 if ch.unicode_at(0) < 0x80 else 2
	return n


## 排版宽度 (原版像素) = 字节数 * size/2; 单字节宽 = 字格宽/2
static func measure(s: String, sz := 12.0) -> float:
	return bytes(s) * sz / 2.0


## 对齐后的 x (原版整除): left = x; center_in = x + (box_w - 宽)/2; center_bytes = center_x - 字节数*size/4 (法术名横幅 46 - 字节*3)
static func align_x(align: String, s: String, x: float, box_w := 0.0, center_x := 0.0, sz := 12.0) -> float:
	match align:
		"center_in", "center":
			return x + int(box_w - measure(s, sz)) / 2
		"center_bytes":
			return center_x - int(bytes(s) * sz / 4.0)
		"right":
			return x + box_w - measure(s, sz)
	return x


## 按宽度折行 (逐字断行, 与原版一样不按词; 宽度按字节); width<=0 只按 "\n" 分行
static func wrap_width(s: String, width: float, sz := 12.0) -> PackedStringArray:
	var out := PackedStringArray()
	var half := sz / 2.0
	for para in s.split("\n"):
		if width <= 0.0:
			out.append(para)
			continue
		var cur := ""
		var w := 0.0
		for ch in para:
			var cw := half * (1 if ch.unicode_at(0) < 0x80 else 2)
			if cur != "" and w + cw > width + 0.01:
				out.append(cur)
				cur = ""
				w = 0.0
			cur += ch
			w += cw
		out.append(cur)
	return out


## 按字数折行 (原版说明栏「每行最多 N 个汉字」)
static func wrap_chars(s: String, n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var i := 0
		while i < para.length():
			out.append(para.substr(i, n))
			i += n
		if para == "":
			out.append("")
	return out


## 基线在字格里的位置 (原版像素, 字格顶 = 0)。sz 号字按 12 号的比例缩放
static func baseline(sz := 12.0) -> float:
	return UiFonts.baseline(Assets.font_id) * sz / 12.0


# ---------------------------------------------------------------- 绘制

func _relayout() -> void:
	lines = UiText.wrap_width(text, max_width, size)
	_realign()
	queue_redraw()


## 绘制列表 [[dx, dy, Color], ...] (样式 + 本色)
func _draws() -> Array:
	var out: Array = []
	if edge_color.a > 0.0:
		return [[-1, 0, edge_color], [1, 0, edge_color], [0, 0, color]]
	for d in UiLayout.style(flags):
		var cname := String(d[2]) if d.size() > 2 else "color"
		out.append([int(d[0]), int(d[1]), color if cname == "color" else UiLayout.color(cname, color)])
	return out


func _draw() -> void:
	var f := Assets.font()
	var sc := float(Assets.SCALE)
	var px := int(round(size * sc))
	var half := size / 2.0
	var base := baseline(size)
	var draws := _draws()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / sc)
	var left := visible_chars
	for i in lines.size():
		var s: String = lines[i]
		if left >= 0:
			if left == 0:
				break
			if s.length() > left:
				s = s.left(left)
			left -= s.length()
		var y := (i * line_height + base) * sc
		var x := 0.0
		for ch in s:
			var cp := ch.unicode_at(0)
			var cw := half if cp < 0x80 else size
			if cp != 32:
				if SUBST.has(ch) and not f.has_char(cp):
					ch = SUBST[ch]
				var gx := x
				if cp < 0x80:  # 半角: 字形在半格里居中
					gx += (half - f.get_char_size(cp, px).x / sc) / 2.0
				for d in draws:
					draw_char(f, Vector2(round((gx + d[0]) * sc), y + d[1] * sc), ch, px, d[2])
			x += cw

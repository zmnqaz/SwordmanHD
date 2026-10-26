# SPDX-License-Identifier: GPL-3.0-only
class_name UiDebugOverlay
extends CanvasLayer
## 布局校对工具: 盖在最上层, 用原版坐标 (320x200 安全区) 画
##   - 网格: 10 像素细线、50 像素粗线, 安全区外框;
##   - 元素框: 场景里所有按布局表建的元素 (UiLayout.tag 过的节点, 如 UiText.make 建的文字) 的外框与 id,
##     颜色按 status (绿 verified / 黄 screenshot / 红 conflict / 灰 unknown); 文字另画每个字格与基线;
##   - 叠加原版截图: --overlay=<png> 半透明盖在安全区上 (任何尺寸缩放到 320x200), --overlay-alpha=0.5, --overlay-offset=dx,dy (原版像素)。
## 启动参数 --layout-debug 打开; 运行中 Ctrl+F9 开关元素框/网格, Ctrl+F10 开关叠加截图, Alt+方向键 1 像素微调叠加偏移 (屏幕左上角显示当前偏移)。
## 只读显示, 不影响游戏输入 (Ctrl+F9/Ctrl+F10/Alt+方向键以外的键照常传给游戏)。

const STATUS_COLORS := {"verified": Color(0.2, 1, 0.3), "screenshot": Color(1, 0.9, 0.2), "conflict": Color(1, 0.25, 0.2),
	"unknown": Color(0.7, 0.7, 0.7)}

var show_boxes := true
var show_overlay := true
var overlay_alpha := 0.5
var overlay_offset := Vector2.ZERO
var _root: Node2D
var _draw_node: Node2D
var _overlay: Sprite2D
var _anchor: Node2D
var _t := 0.0


## 按命令行参数创建 (没有 --layout-debug / --overlay= 时返回 null)
static func from_args(args: PackedStringArray) -> UiDebugOverlay:
	var on := false
	var path := ""
	var o := UiDebugOverlay.new()
	for a in args:
		if a == "--layout-debug":
			on = true
		elif a.begins_with("--overlay="):
			path = a.trim_prefix("--overlay=")
			on = true
		elif a.begins_with("--overlay-alpha="):
			o.overlay_alpha = float(a.trim_prefix("--overlay-alpha="))
		elif a.begins_with("--overlay-offset="):
			var v := a.trim_prefix("--overlay-offset=").split(",")
			if v.size() == 2:
				o.overlay_offset = Vector2(float(v[0]), float(v[1]))
	if not on:
		o.free()
		return null
	o.show_boxes = "--layout-debug" in args
	o._overlay_path = path
	return o


var _overlay_path := ""


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Node2D.new()
	_root.scale = Vector2.ONE * Assets.SCALE
	add_child(_root)
	_anchor = ScreenLayout.anchor_node(ScreenLayout.SAFE)
	_root.add_child(_anchor)
	if _overlay_path != "":
		var img := Image.load_from_file(_overlay_path)
		if img:
			_overlay = Sprite2D.new()
			_overlay.centered = false
			_overlay.texture = ImageTexture.create_from_image(img)
			_overlay.scale = Vector2(320.0 / img.get_width(), 200.0 / img.get_height())
			_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_anchor.add_child(_overlay)
		else:
			push_warning("UiDebugOverlay: 读不了叠加截图 " + _overlay_path)
	_draw_node = Node2D.new()
	_draw_node.draw.connect(_paint)
	_root.add_child(_draw_node)
	_apply()


func _apply() -> void:
	if _overlay:
		_overlay.visible = show_overlay
		_overlay.modulate.a = overlay_alpha
		_overlay.position = overlay_offset
	_draw_node.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t > 0.25:  # 元素会动 (滑入等), 定时重画
		_t = 0.0
		_draw_node.queue_redraw()


func _input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed:
		return
	if k.ctrl_pressed and k.keycode == KEY_F9:   # 要按 Ctrl: 单独 F10 是设定面板
		show_boxes = not show_boxes
	elif k.ctrl_pressed and k.keycode == KEY_F10:
		show_overlay = not show_overlay
	elif k.alt_pressed and k.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		overlay_offset += {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[k.keycode]
	else:
		return
	_apply()
	get_viewport().set_input_as_handled()


## 屏幕像素 -> 本层原版坐标 (_root 局部)
func _to_local_orig(xf: Transform2D, p: Vector2) -> Vector2:
	return _root.get_global_transform_with_canvas().affine_inverse() * (xf * p)


func _paint() -> void:
	var n := _draw_node
	var safe: Rect2 = ScreenLayout.safe_rect
	if show_boxes:
		var sz: Vector2 = ScreenLayout.size
		var ox := fposmod(safe.position.x, 10.0)
		var oy := fposmod(safe.position.y, 10.0)
		for i in int(sz.x / 10) + 2:
			var x := ox + i * 10
			var major := int(round(x - safe.position.x)) % 50 == 0
			n.draw_line(Vector2(x, 0), Vector2(x, sz.y), Color(1, 1, 1, 0.35 if major else 0.15), 0.25)
		for i in int(sz.y / 10) + 2:
			var y := oy + i * 10
			var major := int(round(y - safe.position.y)) % 50 == 0
			n.draw_line(Vector2(0, y), Vector2(sz.x, y), Color(1, 1, 1, 0.35 if major else 0.15), 0.25)
		n.draw_rect(safe, Color(0, 1, 1, 0.8), false, 0.5)
		_paint_elements(get_tree().root)
	if _overlay:
		var f := ThemeDB.fallback_font
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / Assets.SCALE)
		n.draw_string(f, Vector2(4, 16), "叠加 %s  偏移 (%d,%d)  Ctrl+F10 开关  Alt+方向键微调" % [_overlay_path.get_file(), overlay_offset.x, overlay_offset.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 0))
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_elements(node: Node) -> void:
	for c in node.get_children():
		if c == self:
			continue
		if c is CanvasItem and not (c as CanvasItem).is_visible_in_tree():
			continue
		if c is CanvasItem and c.has_meta("ui_layout_id"):
			_paint_one(c)
		_paint_elements(c)


func _paint_one(c: CanvasItem) -> void:
	var id := String(c.get_meta("ui_layout_id"))
	var xf := c.get_global_transform_with_canvas()
	var r: Rect2 = c.get_meta("ui_layout_rect", Rect2(0, 0, 8, 8))
	var size := r.end
	var org := r.position
	if c is UiText:
		var t := c as UiText
		var w := 0.0
		for i in t.lines.size():
			w = maxf(w, t.line_width(i))
		size = Vector2(maxf(w, 1), maxf(1, t.lines.size()) * t.line_height)
		org = Vector2.ZERO
	var a := _to_local_orig(xf, org)
	var b := _to_local_orig(xf, size)
	var col: Color = STATUS_COLORS.get(String(UiLayout.el(id).get("status", "unknown")), STATUS_COLORS["unknown"])
	var n := _draw_node
	n.draw_rect(Rect2(a, b - a), col, false, 0.5)
	if c is UiText:  # 字格与基线
		var t := c as UiText
		var base := UiText.baseline(t.size)
		for i in t.lines.size():
			var x := 0.0
			for ch in t.lines[i]:
				var cw := t.size / 2.0 if ch.unicode_at(0) < 0x80 else t.size
				var p := _to_local_orig(xf, Vector2(x, i * t.line_height))
				n.draw_rect(Rect2(p, Vector2(cw, t.size)), Color(col, 0.35), false, 0.25)
				x += cw
			var y0 := _to_local_orig(xf, Vector2(0, i * t.line_height + base))
			var y1 := _to_local_orig(xf, Vector2(t.line_width(i), i * t.line_height + base))
			n.draw_line(y0, y1, Color(1, 0, 1, 0.7), 0.25)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / Assets.SCALE)
	n.draw_string(ThemeDB.fallback_font, (a + Vector2(0, -1)) * Assets.SCALE, id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# SPDX-License-Identifier: GPL-3.0-only
extends CanvasLayer
## 版权声明页 (比片头动画还早): 每次启动都弹, 同意才能继续, 不记住同意 (没有「不再提示」)。不同意 = 退出游戏。
## 文案走 UiStrings notice.* (内容包 text/ui.json, 繁体叠加层同名键); 按钮 = 原生 Button, 鼠标 / 触屏直接点;
## 键盘 / 手柄走统一输入层: 方向键在两个按钮间切换, 确认执行, 取消无作用 (免得误按退出游戏)。

var _on_agree: Callable
var _on_decline: Callable
var _buttons: Array[Button] = []
var _sel := 0
var _done := false


## 启动流程该不该先显示声明: 自动测试 / 跳过片头 / 录像回放 (skip 为真) 不拦, 其余每次都显示
static func needed(skip: bool) -> bool:
	return not skip


static func create(on_agree: Callable, on_decline: Callable) -> CanvasLayer:
	var s = (load("res://scripts/notice_scene.gd") as GDScript).new()
	s._on_agree = on_agree
	s._on_decline = on_decline
	return s


func _ready() -> void:
	layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := MarginContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var h := float(get_viewport().get_visible_rect().size.y)
	var m := int(0.06 * h)
	for side in ["left", "top", "right", "bottom"]:
		box.add_theme_constant_override("margin_" + side, m)
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(m * 0.5))
	box.add_child(v)
	var font := UiText.game_font(false)
	var size := maxi(14, int(0.034 * h))
	v.add_child(_label(UiStrings.t("notice.title"), font, int(size * 1.5), Color(0.96, 0.76, 0.30)))
	var sc := ScrollContainer.new()   # 小屏放不下时可以滚 (触屏拖动 / 滚轮)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var body := _label(UiStrings.t("notice.body"), font, size, Color(1.0, 0.94, 0.78))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(m * 1.5))
	v.add_child(row)
	for i in 2:
		var b := Button.new()
		b.text = UiStrings.t("notice.agree" if i == 0 else "notice.decline")
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", int(size * 1.2))
		b.custom_minimum_size = Vector2(size * 8, size * 2.4)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pick.bind(i))
		row.add_child(b)
		_buttons.append(b)
	_refresh()
	InputRouter.push(self)


func _exit_tree() -> void:
	InputRouter.pop(self)


func _label(t: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _refresh() -> void:
	for i in _buttons.size():
		_buttons[i].modulate = Color(1, 0.85, 0.4) if i == _sel else Color(0.75, 0.72, 0.65)


func _pick(i: int) -> void:
	if _done:
		return
	_done = true
	if i == 0:
		_on_agree.call()
	else:
		_on_decline.call()


## 统一输入层 (InputRouter): 没有 ui_hits, 鼠标 / 触屏交给上面的 Button
func ui_action(a: UiAction) -> bool:
	if a.echo:
		return true
	if a.is_dir():
		_sel = 1 - _sel
		_refresh()
	elif a.is_confirm():
		_pick(_sel)
	return true

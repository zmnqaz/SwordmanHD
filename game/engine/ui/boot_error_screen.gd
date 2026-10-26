# SPDX-License-Identifier: GPL-3.0-only
class_name BootErrorScreen
extends CanvasLayer
## 启动自检失败 (缺资源包等) 时, 手机上显示的整屏文字提示。
## 桌面用 OS.alert (阻塞的系统对话框) 再退出; 手机上 OS.alert 不阻塞 (iOS 没有), 立刻退出会让人看到的是「闪退」,
## 资源该放哪的提示根本看不见 —— 所以手机上不退出, 把提示画在屏幕上, 由用户自己返回 / 划掉应用。
## 字体直接用随包的思源黑体 (这时内容包 / 字体清单多半没加载), 版面按画面高度算, 贴边留出系统安全区。

const FONT_PATH := "res://assets/font/NotoSansSC-Medium.otf"
## 文案走 UiStrings (键 boot.error.title / boot.error.foot); 缺包时内容包多半没加载 (取不到文案表), 这时用后备文字
const TITLE_KEY := "boot.error.title"
const TITLE_FALLBACK := "无法启动"
const FOOT_KEY := "boot.error.foot"
const FOOT_FALLBACK := "请放好资源包后重新打开本应用 (按返回键或划掉应用退出)。"

var message := ""
var _label: Label


static func make(text: String) -> BootErrorScreen:
	var s := BootErrorScreen.new()
	s.message = text
	return s


func _ready() -> void:
	layer = 200
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := MarginContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := 0.06 * float(get_viewport().get_visible_rect().size.y)
	for side in ["left", "top", "right", "bottom"]:
		box.add_theme_constant_override("margin_" + side, int(m))
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(m * 0.5))
	box.add_child(v)
	var font = load(FONT_PATH)
	var size := maxi(14, int(0.036 * float(get_viewport().get_visible_rect().size.y)))
	v.add_child(_text(title(), font, int(size * 1.5), Color(0.96, 0.76, 0.30)))
	_label = _text(message, font, size, Color(1.0, 0.94, 0.78))
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_label)
	v.add_child(_text(foot(), font, int(size * 0.85), Color(0.7, 0.66, 0.55)))


static func title() -> String:
	return UiStrings.t(TITLE_KEY) if UiStrings.has(TITLE_KEY) else TITLE_FALLBACK


static func foot() -> String:
	return UiStrings.t(FOOT_KEY) if UiStrings.has(FOOT_KEY) else FOOT_FALLBACK


func _text(t: String, font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

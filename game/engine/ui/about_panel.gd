# SPDX-License-Identifier: GPL-3.0-only
class_name AboutPanel
extends CanvasLayer
## 「关于」页 (设定面板最后一行打开的模态子面板): 游戏名、版本号、项目主页 (GitHub 地址)、许可。玩家报 bug 时对着这里写版本号。
## 操作: 确认键 = 在浏览器里打开项目主页; 点 / 触地址那一行 = 同样打开; 点别处、取消键 = 返回。刚打开有防误触 (打开它的那一下点按不算)。
## 版本号与主页地址取自 project.godot (GameVersion), 文字走文案表 about.*; 打开浏览器的动作可替换 (opener, 测试里不真开)。

const GUARD := 0.3

var gc: GameContext
var router   # 统一输入层, 由设定面板传入 (引擎层不直接引用 InputRouter); 测试可换成独立实例
## 打开网址的动作 (参数 = 网址); 缺省交给系统浏览器 (手机上也是)
var opener: Callable = func(url: String) -> void: OS.shell_open(url)

signal closed(save: bool)

var _link: Label
var _age := 0.0
var _closing := false


## 正文各行 (简体 / 繁体跟文案表): 名称、版本、主页地址、许可
static func lines() -> Array:
	return [UiStrings.t("about.name"),
		UiStrings.t("about.version") % GameVersion.label(),
		UiStrings.t("about.home"),
		GameVersion.homepage(),
		UiStrings.t("about.license")]


func open() -> bool:
	layer = 56
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var h := float(get_viewport().get_visible_rect().size.y)
	var size := clampi(int(h * 0.036), 12, 48)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", int(size * 0.6))
	add_child(box)
	box.add_child(_label(UiStrings.t("about.title"), int(size * 1.5), Color(0.96, 0.76, 0.30)))
	var ls := lines()
	box.add_child(_label(ls[0], size, Color(1.0, 0.94, 0.78)))
	box.add_child(_label(ls[1], int(size * 1.2), Color(0.96, 0.76, 0.30)))
	box.add_child(_label(ls[2], size, Color(1.0, 0.94, 0.78)))
	_link = _label(ls[3], size, Color(0.55, 0.78, 1.0))
	box.add_child(_link)
	box.add_child(_label(ls[4], int(size * 0.8), Color(0.75, 0.70, 0.60)))
	box.add_child(_label(UiStrings.t("about.hint"), int(size * 0.8), Color(0.75, 0.70, 0.60)))
	router.push(self, true)
	set_process(true)
	await closed
	router.pop(self)
	queue_free()
	return false


func _label(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.custom_minimum_size.x = get_viewport().get_visible_rect().size.x * 0.8
	l.add_theme_font_override("font", UiText.game_font(false))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _process(delta: float) -> void:
	_age += delta


## 地址那一行在屏幕上的矩形 (点按判断用); 还没排版时为空矩形
func link_rect() -> Rect2:
	return _link.get_global_rect() if _link != null else Rect2()


func ui_action(a: UiAction) -> bool:
	if a.echo or _closing or _age < GUARD:
		return true
	if a.is_cancel():
		_closing = true
		closed.emit(false)
	elif a.is_confirm():
		if not a.has_pos() or link_rect().has_point(a.pos):   # 键盘确认 / 点在地址上: 打开主页; 点别处: 返回
			opener.call(GameVersion.homepage())
		else:
			_closing = true
			closed.emit(false)
	return true

# SPDX-License-Identifier: GPL-3.0-only
class_name UiMsgBox
extends Node2D
## 原版样式对话框 (原版 /), 剧情对话 (engine/ui/dialog_box.gd MsgBox) 与展示画面共用这一份实现。
## 坐标、字体、行距、颜色全部来自布局表 (ui_theme/layout.json):
##   dialog.box   卷轴 Misc/MSG_BOX 第 0 帧 (2,137)
##   dialog.face  头像: 按本帧原版 1 倍不透明外框 W,H 贴屏幕底边 (y=200-H); side 0 在左 (x=0, 水平镜像), 其余在右 (x=320-W)
##   dialog.text  文字 (相对卷轴): 无头像 / 头像在右 (9,4) 宽 298 / 185; 头像在左 x=122 宽 185; 12 号字、行距 13、每页 3 行、主色 0x59a5
##   dialog.arrow 页尾下箭头 (MSG_BOX 第 27~40 帧) 在最后一个字后 (2,2)
## 文字排版走 UiText (字格 + 按字节折行), 换字体不改变折行与位置。
## 锚点: 整体贴底水平居中 (ui_anchor = BOTTOM); 头像再贴所在一侧的屏幕边 (BOTTOM_LEFT / BOTTOM_RIGHT)。
## 不读输入: 调用方按确认时调 confirm() (打字中补全本页, 否则翻页/关闭); 快进由调用方设 fast_forward;
## 自动测试 Game.fast 下自动翻页, Game.skip_dialog 直接跳过。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal closed

const CHARS_PER_SEC := 10.0

var ui_anchor := ScreenLayout.Anchor.BOTTOM
var fast_forward := false
## 页尾停多少秒后自动继续 (0 = 等按键)。原版页尾停 5 秒自动继续
var auto_next_sec := 0.0
var is_open := false
var _box: AnimPlayer
var _face: AnimPlayer
var _face_anchor: Node2D  # 锚点节点 (engine/ui/ui_anchor.gd)
var _text: UiText
var _arrow: AnimPlayer
var _typing := false
var _wait := 0.0
var _pages: Array = []
var _page := 0
var _lines_per_page := 3
var _lines_default := 3
var _cps := CHARS_PER_SEC
var _last_auto := 0.0   # 末页停多少秒自动关 (0 = 等按键); opts.auto_last_sec


func _init() -> void:
	ui_anchor = UiLayout.anchor("dialog.box", ScreenLayout.Anchor.BOTTOM)
	_box = AnimPlayer.new()
	_box.position = UiLayout.at("dialog.box")
	add_child(_box)
	_face = AnimPlayer.new()
	add_child(_face)
	_face_anchor = ScreenLayout.wrap(_face, ScreenLayout.Anchor.BOTTOM_RIGHT)
	_text = UiText.make("dialog.text")
	add_child(_text)
	_lines_default = int(UiLayout.text("dialog.text").get("max_lines", 3))
	_lines_per_page = _lines_default
	_arrow = AnimPlayer.new()
	_arrow.play_sound = false
	_arrow.visible = false
	add_child(_arrow)
	visible = false


## face < 0 表示无头像; expr 为头像表情 (Face 动画的帧号); side: -1 居中 / 0 左 / 1 右。等到对话框关闭才返回
## opts: lines_per_page 每页行数 / chars_per_sec 打字速度 / auto_last_sec 末页停多久自动关 (缺省 = 剧情对话的值; 状态解除框见 dialog.release)
func show_text(face: int, expr: int, side: int, text: String, opts := {}) -> void:
	open(face, expr, side, text, opts)
	if not is_open:
		await get_tree().process_frame
		return
	await closed


## 只打开, 不等待 (展示画面 / 调用方自己连 closed 信号)
func open(face: int, expr: int, side: int, text: String, opts := {}) -> void:
	visible = true
	is_open = true
	_lines_per_page = int(opts.get("lines_per_page", _lines_default))
	_cps = float(opts.get("chars_per_sec", CHARS_PER_SEC))
	_last_auto = float(opts.get("auto_last_sec", 0.0))
	var spr := UiLayout.sprite("dialog.box")
	_box.show_frame(String(spr.get("anim", "")), UiLayout.frame("dialog.box"))
	UiLayout.tag(_box, "dialog.box", UiPanel.frame_rect(String(spr.get("anim", "")), UiLayout.frame("dialog.box")))
	var has_face := place_face(_face, _face_anchor, face, expr, side)
	var r := text_rect(has_face, side)
	_text.position = r.position
	_text.max_width = r.size.x
	_pages = _paginate(text, r.size.x)
	_page = 0
	if gc.skip_dialog:  # 调试: 跳过对白
		is_open = false
		visible = false
		return
	_show_page()


## 文字区 (原版坐标, 第一个字格左上角 + 宽): 布局表 dialog.text (pos/size 相对卷轴; face_left_x/face_w 头像在左/右时)
static func text_rect(has_face: bool, side: int) -> Rect2:
	var base := UiLayout.at("dialog.box")
	var p := UiLayout.at("dialog.text")
	var sz := UiLayout.size_of("dialog.text")
	var t: Dictionary = UiLayout.el("dialog.text").get("text", {})
	if has_face:
		sz.x = float(t.get("face_w", sz.x))
		if side == 0:
			p.x = float(t.get("face_left_x", p.x))
	return Rect2(base + p, sz)


## 头像: face < 0 无头像; 按本帧原版 1 倍不透明外框贴屏幕底边, side 0 在左 (水平镜像) 其余在右。
## 返回是否有头像。是/否框 (ChoiceBox) 共用。
static func place_face(fnode: AnimPlayer, anchor: Node2D, face: int, expr: int, side: int) -> bool:
	fnode.visible = false
	fnode.scale = Vector2.ONE
	var face_dir := ThemeAssets.f("face", [face])
	if face < 0 or not Assets.exists(face_dir + "/anim.json"):
		return false
	var data := Assets.anim(face_dir)
	var f := clampi(expr, 0, data["frames"].size() - 1)
	var parts: Array = data["frames"][f]["parts"]
	if parts.is_empty() or parts[0]["tex"] == null:
		return false
	fnode.show_frame(face_dir, f)
	fnode.visible = true
	var r := UiPanel.frame_rect(face_dir, f)  # 帧坐标里的不透明外框 (部件偏移 + 1 倍 used_rect)
	var screen := UiLayout.base_size()
	var fy := screen.y - r.end.y
	anchor.set("anchor", ScreenLayout.Anchor.BOTTOM_LEFT if side == 0 else ScreenLayout.Anchor.BOTTOM_RIGHT)
	if side == 0:  # 左侧: 水平镜像
		fnode.scale = Vector2(-1, 1)
		fnode.position = Vector2(r.end.x, fy)
	else:
		fnode.position = Vector2(screen.x - r.end.x, fy)
	return true


## 按宽度 (字节) 逐字折行, 每页 max_lines 行
func _paginate(text: String, width: float) -> Array:
	var lines := UiText.wrap_width(text, width, _text.size)
	var pages: Array = []
	var i := 0
	while i < lines.size():
		pages.append("\n".join(lines.slice(i, i + _lines_per_page)))
		i += _lines_per_page
	return pages if not pages.is_empty() else [text]


func _show_page() -> void:
	_text.text = _pages[_page]
	_text.visible_chars = 0
	_arrow.visible = false
	_typing = true
	_wait = 0.0


## 本页显示完: 下箭头放在最后一个字后面 (布局表 dialog.arrow.pos = 相对字尾的偏移)
func _page_done() -> void:
	_text.visible_chars = -1
	_typing = false
	_wait = 0.0
	var last := _text.lines.size() - 1
	var spr := UiLayout.sprite("dialog.arrow")
	var dir := String(spr.get("anim", ""))
	var start := int(spr.get("start", 0))
	var cursor := _text.position + Vector2(_text.line_width(last), last * _text.line_height)
	_arrow.position = cursor + UiLayout.at("dialog.arrow")
	_arrow.visible = true
	_arrow.play(dir, start, int(spr.get("end", start + 1)))


func _process(delta: float) -> void:
	if not is_open or InputRouter.overlay_open():  # 设定面板等模态浮层打开时, 对白不打字、不自动翻页
		return
	var ff := gc.fast or fast_forward
	if _typing:
		_wait += delta * (20.0 if ff else 1.0)
		_text.visible_chars = int(_wait * _cps)
		if _text.visible_chars >= _text.char_count():
			_page_done()
	else:
		_wait += delta
		if ff and _wait >= (0.4 if gc.fast else 0.08):  # 自动测试 / 快进: 不等按键
			_next()
		elif auto_next_sec > 0.0 and _wait >= auto_next_sec:
			_next()
		elif _last_auto > 0.0 and _page == _pages.size() - 1 and _wait >= _last_auto:
			_next()


## 确认键: 打字中补全本页, 否则翻页或关闭
func confirm() -> void:
	if not is_open:
		return
	if _typing:
		_page_done()
	else:
		_next()


## 取消键: 原版对话中取消也翻页, 与确认相同
func cancel() -> void:
	confirm()


func _next() -> void:
	if _page + 1 < _pages.size():
		_page += 1
		_show_page()
	else:
		_close()


func _close() -> void:
	_arrow.visible = false
	is_open = false
	visible = false
	closed.emit()

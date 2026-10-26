# SPDX-License-Identifier: GPL-3.0-only
class_name ChoiceBox
extends CanvasLayer
## 是/否 选择框 (原版 的选择形式; 重制版 GameMsgBoxChooseUI)。原版截图:
##   对话框卷轴 Misc/MSG_BOX 第 0 帧在 (2,137), 可带头像 (位置同对话框, UiMsgBox.place_face);
##   第一行问句, 下面两行选项, 选项前有图标: 是 = MSG_BOX 第 1~11 帧 (圆), 否 = 第 12~22 帧 (叉), 选中项图标循环播放、字为主色,
##   未选项图标静止、字为浅棕。行距 13, 文字起点同对话框 (UiMsgBox.text_rect), 选项图标在文字左边。
## 坐标/颜色取自布局表 choice.* (缺省为上述原版值), 文字走统一排版 UiText。
## 操作: 任意方向键切换, 确认选当前项, 取消 = 否; 鼠标见 ui_hits (统一输入层处理)。
## 锚点: 卷轴贴底 (BOTTOM), 头像贴所在一侧的屏幕边。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal chosen(ok: bool)


var _root: Node2D
var _face: AnimPlayer
var _face_anchor: Node2D
var _q: UiText
var _opts: Array[UiText] = []
var _icons: Array[AnimPlayer] = []
var _sel := 0
var _on_color := UiText.BROWN
var _idle_color := Color8(213, 181, 107)
var _icon_frames: Array = []   # [[起, 止), ...] 是 / 否 (布局表 choice.option_icon.sprite.frames)


func _ready() -> void:
	layer = 52
	ScreenLayout.bind_layer(self, UiLayout.anchor("choice.box", ScreenLayout.Anchor.BOTTOM))  # 卷轴贴底, 水平居中
	_root = Node2D.new()
	_root.scale = Vector2.ONE * Assets.SCALE
	add_child(_root)
	var box := AnimPlayer.new()
	box.position = UiLayout.pos("choice.box")
	var spr := UiLayout.sprite("choice.box", {"anim": ThemeAssets.p("ui.dialog"), "frame": 0})
	box.show_frame(String(spr["anim"]), int(spr["frame"]))
	_root.add_child(box)
	_face = AnimPlayer.new()
	_face_anchor = ScreenLayout.anchor_node(ScreenLayout.Anchor.BOTTOM_RIGHT)
	_root.add_child(_face_anchor)
	_face_anchor.add_child(_face)
	_q = UiText.make("choice.question")
	_root.add_child(_q)
	_on_color = UiLayout.text("choice.option")["color"]
	_idle_color = UiLayout.color("choice.idle_color", _idle_color)
	_icon_frames = UiLayout.sprite("choice.option_icon").get("frames", [[1, 12], [12, 23]])
	for i in 2:
		var ic := AnimPlayer.new()
		ic.play_sound = false
		_root.add_child(ic)
		_icons.append(ic)
		var l := UiText.make("choice.option")
		_root.add_child(l)
		_opts.append(l)
	visible = false


## default_yes: 初始选项 (系统类确认框默认「是」, 丢弃/出发/回标题默认「否」, 4.4)
## face/expr/side: 头像 (同对话框; 宝箱「發現了寶箱」带开箱者头像)
func ask(question: String, yes: String, no: String, default_yes := true, face := -1, expr := 0, side := 0) -> bool:
	var has_face := UiMsgBox.place_face(_face, _face_anchor, face, expr, side)
	var tr := UiMsgBox.text_rect(has_face, side)  # 问句起点同对话框
	var indent := UiLayout.pos("choice.option")  # 选项: 图标格 (13) + 间隙 4, 每行 13 (有无头像相同)
	var tx := tr.position.x + indent.x
	var ip := UiLayout.pos("choice.option_icon")  # 图标相对选项文字
	_q.text = question
	_q.position = tr.position
	_opts[0].text = yes if yes != "" else UiStrings.t("common.yes")
	_opts[1].text = no if no != "" else UiStrings.t("common.no")
	for i in 2:
		_opts[i].position = Vector2(tx, tr.position.y + indent.y * (i + 1))
		_icons[i].position = _opts[i].position + ip
	_sel = 0 if default_yes else 1
	_update()
	visible = true
	if gc.fast:  # 自动测试: 选"是"; --choose=1,0,... 按顺序给出每个选择框的答案 (1 是 / 0 否), 用完后仍选"是"
		await get_tree().create_timer(0.3).timeout
		visible = false
		return _scripted_answer()
	InputRouter.push(self)
	var r: bool = await chosen
	InputRouter.pop(self)
	visible = false
	return r


## 测试 --choose=1,0,...: 剧情选择框的预设答案 (按弹出顺序消费)
static var _answers: Array = []


## 取消键 = 选「否」。城镇剧情选择框 (0x2E, 起的轮询: 只有 ↑↓ 切换、Enter 确认; Esc 只在 字段 标志为 1 时取消,
## 该标志在剧情选择框里恒为 0, 实测按 Esc 无任何反应, 选项与脚本都不动) 置 false; 战场宝箱等其它是/否保持取消 = 否。
var cancel_means_no := true
static var _answers_read := false


static func _scripted_answer() -> bool:
	if not _answers_read:
		_answers_read = true
		_answers.append_array(DebugArgs.current().choose)   # --choose=1,0,...
	return _answers.pop_front() if not _answers.is_empty() else true


func _update() -> void:
	for i in 2:
		var on := i == _sel
		_opts[i].color = _on_color if on else _idle_color
		if on:
			_icons[i].play(_icon_dir(), int(_icon_frames[i][0]), int(_icon_frames[i][1]))
		else:
			_icons[i].show_frame(_icon_dir(), int(_icon_frames[i][0]))
		_icons[i].modulate.a = 1.0 if on else UiLayout.num("choice.option_icon", "idle_alpha", 1.0)


## 指针 (engine/ui/ui_hit.gd): 每个选项一行 (左边图标 + 文字), 选项文字的局部坐标
func ui_hits() -> Array:
	var out: Array = []
	for i in 2:
		var o := _opts[i]
		var ip := UiLayout.pos("choice.option_icon")  # 命中区: 从图标左缘起, 高 = 行距 + 1
		out.append(UiHit.area(Rect2(Vector2(ip.x, -1), Vector2(UiText.measure(o.text) - ip.x, UiLayout.pos("choice.option").y + 1)), i, o))
	return out


func ui_select(i) -> void:
	if i != _sel:
		_sel = i
		_update()


## 统一输入层 (打开期间在界面栈顶): 任意方向键切换是/否, 确认选当前项, 取消 = 否 (鼠标见 ui_hits)。
func ui_action(a: UiAction) -> bool:
	if not visible or (a.echo and not a.is_dir()):
		return true
	if a.is_dir():
		_sel = 1 - _sel
		_update()
	elif a.is_confirm():
		chosen.emit(_sel == 0)
	elif a.is_cancel() and cancel_means_no:
		chosen.emit(false)
	return true


func _icon_dir() -> String:
	return String(UiLayout.sprite("choice.option_icon").get("anim", ThemeAssets.p("ui.dialog")))

# SPDX-License-Identifier: GPL-3.0-only
class_name MsgBox
extends CanvasLayer
## 剧情对话框 (战场/城镇的 0x18 说话等): 图层 + 统一输入层的外壳, 画面与排版全部由 UiMsgBox (engine/ui/msg_box.gd) 负责,
## 坐标/字体/行距/颜色取自布局表 dialog.* (原版 12 号字、行距 13、主色 0x59a5)。
## 原版确认和取消作用相同: 打字中补全本页, 否则翻页/关闭; 按住 Ctrl 快进; 自动测试 (--fast) 自动翻页。

signal closed

var box: UiMsgBox


func _ready() -> void:
	layer = 50
	var root := Node2D.new()  # 原版坐标根 (同 UiLayer.root)
	root.scale = Vector2.ONE * Assets.SCALE
	add_child(root)
	box = UiMsgBox.new()
	var a := ScreenLayout.anchor_node(box.ui_anchor)
	root.add_child(a)
	a.add_child(box)
	box.closed.connect(_on_closed)
	visible = false


## face < 0 表示无头像; expr 为头像表情 (Face 动画的帧号); side: -1 居中 / 0 左 / 1 右
func show_text(face: int, expr: int, side: int, text: String, opts := {}) -> void:
	visible = true
	box.open(face, expr, side, text, opts)
	if not box.is_open:  # Game.skip_dialog
		visible = false
		await get_tree().process_frame
		return
	InputRouter.push(self)
	await closed


## 统一输入层: 打开期间在界面栈顶。触摸点按、鼠标左键 (确认) 同样
func ui_action(a: UiAction) -> bool:
	if a.echo or not (a.is_confirm() or a.is_cancel()):
		return true
	box.confirm()
	return true


func _process(_d: float) -> void:
	if box and box.is_open:
		box.fast_forward = InputRouter.fast_held()


func _on_closed() -> void:
	visible = false
	InputRouter.pop(self)
	closed.emit()

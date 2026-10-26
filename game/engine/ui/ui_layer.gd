# SPDX-License-Identifier: GPL-3.0-only
class_name UiLayer
extends CanvasLayer
## 原版样式界面组件的容器: 一个 CanvasLayer + 放大 Assets.SCALE 倍的根节点 root。
## 组件 (UiPanel / UiIconMenu / UiListMenu / UiNumber / UiInfoBar / UiMsgBox / UiText) 都用 320x200 原版坐标,
## 加到 root 下即得 1280x800 画面。文字由 UiText 按 4 倍字号绘制再缩小, 所以放大后仍清晰。
##
## 锚点 (docs/架构设计.md「锚点界面」): add() 把组件包进一个锚点节点 (ui_anchor.gd), 原版坐标以安全区为基准按锚点贴屏幕边;
##   不传锚点时取组件的 ui_anchor 属性 (如 UiMsgBox 贴底), 都没有就按安全区居中。16:10 下所有锚点偏移为 0。
##
## 约定 (见 docs/架构设计.md「界面可换皮」):
##   - 组件只负责显示与选择状态, 不读全局输入; 调用方把按键翻译成 move()/confirm()/cancel()。
##   - 坐标、帧号对照原版; 查不到的留参数并标 TODO。

var root: Node2D


func _init(layer_index := 40) -> void:
	layer = layer_index
	root = Node2D.new()
	root.name = "UiRoot"
	root.scale = Vector2.ONE * Assets.SCALE
	add_child(root)


## 加一个组件到放大的根节点下, 按锚点定位 (−1 = 取 node.ui_anchor, 没有则安全区居中)。返回组件本身。
func add(node: Node, anchor: int = -1) -> Node:
	if anchor < 0:
		anchor = int(node.get("ui_anchor")) if "ui_anchor" in node else ScreenLayout.SAFE
	var w := ScreenLayout.anchor_node(anchor)
	root.add_child(w)
	w.add_child(node)
	return node

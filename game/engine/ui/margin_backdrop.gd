# SPDX-License-Identifier: GPL-3.0-only
extends CanvasLayer
## 触摸界面的留边底 (由 ScreenLayout 创建): 逻辑画面比 320x200 宽时, 安全区左右留给虚拟键的部分铺纯黑 (盖住战场地图伸出去的部分)。
## 原来这里画压暗的原版标题背景纹理做装饰, 手机上看着是灰蒙蒙的一大块、战场里还能看到「开场的贴图」, 用户觉得怪, 2026-10-25 改成纯黑。
## 普通 (非触摸) 宽屏不用它: 两侧由各场景的边缘镜像层铺 (engine/ui/edge_mirror.gd)。
##   触摸界面 (ScreenLayout.keep_side_margins) 时画在场景之上、界面之下 (layer 25)。16:10 下没有留边, 不显示。

var _root: Node2D


func _init() -> void:
	layer = -100
	_root = Node2D.new()
	add_child(_root)


func _ready() -> void:
	ScreenLayout.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	layer = 25 if ScreenLayout.keep_side_margins else -100
	var size: Vector2 = ScreenLayout.size
	var margin := (size.x - ScreenLayout.ORIGINAL.x) / 2.0
	visible = margin > 0.5 and ScreenLayout.keep_side_margins  # 非触摸: 两侧由各场景的边缘镜像层 (edge_mirror.gd) 铺, 其余场景 (视频等) 留黑
	if not visible:
		return
	for side in 2:
		var bg := ColorRect.new()
		bg.color = Color.BLACK
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.position = Vector2(0 if side == 0 else size.x - margin, 0)
		bg.size = Vector2(margin, size.y)
		_root.add_child(bg)
	_root.scale = Vector2.ONE * Assets.SCALE

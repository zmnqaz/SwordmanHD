# SPDX-License-Identifier: GPL-3.0-only
extends Node2D
## 锚点节点 (由 ScreenLayout.anchor_node() / wrap() / UiLayer.add() 创建; 不设 class_name, 免得依赖全局类缓存):
## 把子节点 (原版坐标) 按锚点贴到屏幕边, 视口大小变化时自动重新定位 (见 engine/ui/screen_layout.gd)。
## 在放大 SCALE 倍的坐标系 (UiLayer.root、场景根等) 下使用; position 由本节点管理, 子节点的 position 照旧是原版坐标
## (UiSlide 等动画只改子节点, 不受影响)。
## 可嵌套: 外层有锚点 (锚点节点或 bind_layer/bind_node 过的节点) 时只平移两者之差,
##   例如营地「囊内乾坤」整页居中, 页内的金钱框再用 TOP_RIGHT 贴右上。
## 子节点离开 (被 queue_free) 后本节点自动删除, 调用方照常只管子节点。

var anchor: int = ScreenLayout.SAFE:
	set(v):
		anchor = v
		set_meta("ui_anchor", v)
		if is_inside_tree():
			_place()


func _init(a: int = ScreenLayout.SAFE) -> void:
	name = "Anchor"
	anchor = a
	child_order_changed.connect(_on_children_changed)


func _enter_tree() -> void:
	ScreenLayout.changed.connect(_place)
	_place()


func _exit_tree() -> void:
	ScreenLayout.changed.disconnect(_place)


func _place() -> void:
	var outer := ScreenLayout.frame_anchor(self)
	position = ScreenLayout.offset(anchor) - (ScreenLayout.offset(outer) if outer >= 0 else Vector2.ZERO)
	scale = ScreenLayout.stretch_scale() if anchor == ScreenLayout.Anchor.STRETCH else Vector2.ONE


func _on_children_changed() -> void:
	if get_child_count() == 0 and not is_queued_for_deletion():
		queue_free()

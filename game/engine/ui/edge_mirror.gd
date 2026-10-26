# SPDX-License-Identifier: GPL-3.0-only
extends ColorRect
## 宽屏两侧不留黑边: 逻辑画面比 320x200 宽时, 把安全区里已画好的画面按边界镜像铺到两侧并压暗 (shaders/edge_mirror.gdshader)。
## 通用: 画面是动画 / 渐入渐出都自动跟随, 场景只需一行 ScreenLayout.mirror_edges(场景根或界面层)。
## 本节点要画在场景内容之后 (z_index 很大); 16:10 (没有留边) 时不显示, 与加宽前逐像素一致。
## 不设 class_name (免得依赖全局类缓存); 由 ScreenLayout.mirror_edges() 创建。

const SHADER := preload("res://shaders/edge_mirror.gdshader")


func _init() -> void:
	name = "EdgeMirror"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4000
	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = SHADER


func _ready() -> void:
	ScreenLayout.cover(self)
	ScreenLayout.changed.connect(_update)
	_update()


func _update() -> void:
	var sz: Vector2 = ScreenLayout.size
	var margin := (sz.x - ScreenLayout.ORIGINAL.x) / 2.0
	visible = margin > 0.5 and not ScreenLayout.keep_side_margins
	var m := material as ShaderMaterial
	m.set_shader_parameter("safe_a", ScreenLayout.safe_rect.position.x / sz.x)
	m.set_shader_parameter("safe_b", (ScreenLayout.safe_rect.position.x + ScreenLayout.ORIGINAL.x) / sz.x)

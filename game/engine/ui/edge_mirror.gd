# SPDX-License-Identifier: GPL-3.0-only
extends ColorRect
## 安全区外不留黑边: 逻辑画面比 320x200 宽时, 把安全区里已画好的画面按边界镜像铺到两侧并压暗;
## 比 320x200 高时 (4:3 等), 上下铺黑 (同原来的留边; shaders/edge_mirror.gdshader)。
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
	var extra := sz - ScreenLayout.ORIGINAL
	var side := extra.x > 0.5 and not ScreenLayout.keep_side_margins  # 触摸界面: 左右留边归虚拟键的黑底 (margin_backdrop)
	visible = side or extra.y > 0.5
	if not visible:
		return
	var a := ScreenLayout.safe_rect.position
	var b := a + ScreenLayout.ORIGINAL
	if not side:
		a.x = 0.0
		b.x = sz.x
	var m := material as ShaderMaterial
	m.set_shader_parameter("keep_a", a / sz)
	m.set_shader_parameter("keep_b", b / sz)

# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 范围格叠加: 原版近乎不透明且不闪 —— 地板 (60,33,16) 叠加后 (153,33,198),
## 纹理拟合地板透出率约 13% (RANGE_ALPHA=0.87); 旧实现 0.25~0.5 呼吸动画是回归。
## 用假场景构建 BattleView, 真实等帧断言透明度稳定。

class FakeScene:
	extends Node2D
	var units_node := Node2D.new()
	func _init() -> void:
		add_child(units_node)
const REQUIRES_TEST := {  # 个别方法的依赖 (run_tests.gd 头注), 缺则 SKIP
	"test_range_solid_no_pulse": ["original"],
}


func _view() -> BattleView:
	var scene := FakeScene.new()
	_tree().root.add_child(scene)
	var ui := BattleUi.new(scene)
	scene.add_child(ui)  # 挂进假场景, 一起释放 (BattleUi 是 Node, 不挂树就是孤儿)
	var v := BattleView.new(scene, ui)
	scene.add_child(v)  # 触发 _ready
	return v


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_range_solid_no_pulse() -> void:
	var v := _view()
	v.show_range([Vector2i(3, 4), Vector2i(4, 4)], BattleView.RANGE_MOVE)
	near(v._range_node.modulate.a, BattleView.RANGE_ALPHA, 0.001, "范围格透明度 = 原版实测值")
	eq(v._range_node.get_child_count(), 2, "两个范围格")
	eq((v._range_node.get_child(0) as ColorRect).color, Color(BattleView.RANGE_MOVE, 1.0), "移动范围色 (叠加色)")
	var tree := Engine.get_main_loop() as SceneTree
	for i in 30:  # 0.5 秒: 旧呼吸动画会走到 0.25 附近
		await tree.process_frame
	near(v._range_node.modulate.a, BattleView.RANGE_ALPHA, 0.001, "等 0.5 秒后透明度不变 (原版不闪)")
	v.get_parent().free()  # 连假场景一起释放 (只 free v 会留下 scene 与 units_node)

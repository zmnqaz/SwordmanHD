# SPDX-License-Identifier: GPL-3.0-only
extends SceneTree
## 入口: 在第一帧 (autoload 已就绪) 才加载 town_dialog_body.gd, 见该文件说明。
## 用法: godot --headless --path game --script res://tests/town_dialog_probe.gd -- cases.json observed.json


func _initialize() -> void:
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _go() -> void:
	var body = load("res://tests/town_dialog_body.gd").new()
	await body.run(self)
	quit(0)

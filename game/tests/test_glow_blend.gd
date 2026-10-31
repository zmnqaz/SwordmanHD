# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 发光部件 (原版 type 2~6) 的混合: 饱和相加 底*p10/16 + 源*p8/16 (shaders/screen_blend.gdshader, AnimPlayer.glow_weights)。
## 回归 (2026-10-31): 以前是近似滤色且强度取 p8*0.05, 亮底上几乎没效果, 序章壁灯 (p8=5, p10=16) 没有光晕, 原版 里是白热核心 + 照亮整面墙。


func test_glow_weights_from_part_params() -> void:
	eq(AnimPlayer.glow_weights(16, 16), [1.0, 1.0], "最常见的 (16,16): 纯相加")
	eq(AnimPlayer.glow_weights(5, 16), [0.3125, 1.0], "壁灯 (5,16): 源按 5/16 相加, 底不变")
	eq(AnimPlayer.glow_weights(16, 8), [1.0, 0.5], "(16,8): 底压暗一半再加源")
	eq(AnimPlayer.glow_weights(0, 16), [0.0, 1.0], "p8=0: 不加")
	eq(AnimPlayer.glow_weights(99, -3), [1.0, 0.0], "越界夹住")


func test_glow_material_params_and_cache() -> void:
	var m: ShaderMaterial = AnimPlayer._glow_material(0.3125, 1.0)
	eq(m.get_shader_parameter("strength"), 0.3125)
	eq(m.get_shader_parameter("dst_keep"), 1.0)
	check(AnimPlayer._glow_material(0.3125, 1.0) == m, "同参数共用一个材质")
	check(AnimPlayer._glow_material(0.3125, 0.5) != m, "底保留不同是另一个材质")
	var r: ShaderMaterial = AnimPlayer._glow_material(1.0, 1.0, true)
	eq(r.get_shader_parameter("red"), true, "红色版 (隐藏宝箱闪光)")

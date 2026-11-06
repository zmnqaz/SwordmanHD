# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 营地五魂分配的描边呼吸 (2026-11-06 无出处细节核实): 强度 16↔32 每 3 tick ±2 往返, 画法是把描边形状下的底按 k/16 调亮


func test_glow_step_pingpong():
	var k := 16
	var up := true
	var seq := [k]
	for i in 20:
		var r := CampSpirit.glow_step(k, up)
		k = r[0]
		up = r[1]
		seq.append(k)
	eq(seq, [16, 18, 20, 22, 24, 26, 28, 30, 32, 30, 28, 26, 24, 22, 20, 18, 16, 18, 20, 22, 24], "16 起往上到 32 转向, 降到 16 再转向 (一圈 16 步 = 48 tick)")


func test_brighten_shader_uses_screen():
	var sh: Shader = load("res://shaders/screen_brighten.gdshader")
	check(sh.code.contains("hint_screen_texture"), "读屏幕: 调亮的是底, 不画描边贴图自身")
	check(sh.code.contains("mod(t, 2.0)"), "权重表结果清最低位 (同 unit_status 的 tw)")

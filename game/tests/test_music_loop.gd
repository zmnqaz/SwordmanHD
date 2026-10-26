# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 场景音乐必须循环: 曲子放完一遍后不能静音 (eae7c5cc 去重复时误删 s.loop = true, 战斗里音乐中途消失、音效还在)。
const REQUIRES := ["original"]



func test_scene_music_loops():
	var A = Engine.get_main_loop().root.get_node("Assets")
	var tried := 0
	for n in range(0, 40):
		var rel: String = ThemeAssets.f("music", [n])
		if not A.exists(rel):
			continue
		var s: AudioStreamMP3 = A.music(rel)
		check(s != null, "音乐 %s 能读" % rel)
		if s != null:
			check(s.loop, "音乐 %s 循环播放" % rel)
		tried += 1
		if tried >= 3:
			break
	check(tried > 0, "至少有一首场景音乐可测 (没有原版资源/资源包时本测试无意义)")

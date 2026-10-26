# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 过场视频声音 (w5 项 5, 原版 实测): 不受音乐/音效开关影响 (Master 总线), 增益 +6.2 dB, Esc 立即停。


func test_video_bus_and_gain():
	var src := FileAccess.get_file_as_string("res://scripts/movie_scene.gd")
	check(src.contains('_player.bus = "Master"'), "视频走 Master 总线 (原版音乐/音效开关关掉视频照响)")
	check(not src.contains('_player.bus = "Music"'), "不再走 Music 总线")
	near(float(load("res://scripts/movie_scene.gd").VIDEO_GAIN_DB), 6.2, 0.01, "视频增益 +6.2 dB (原版实测, Logo rms 原版 -9.59 / 复刻 -9.70)")
	check(src.contains("_player.stop()"), "跳过时立即 stop (原版 Esc 后约 0.2 秒内静音)")

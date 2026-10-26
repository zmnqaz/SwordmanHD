# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 音效文件解析 (Assets.sound_file): 开发版原版目录里是 wav; 导出版 common_assets.pck 里同名 wav 被转成了 .ogg (生成工具的脚本)。
## 先找 wav, 没有再找 ogg, 都没有返回 ""。

func test_sound_file_prefers_wav_then_ogg():
	var dir := OS.get_user_data_dir().path_join("test_sound_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir.path_join("Sprite/x"))
	for n in ["Sprite/x/a.wav", "Sprite/x/b.ogg", "Sprite/x/c.wav", "Sprite/x/c.ogg"]:
		var f := FileAccess.open(dir.path_join(n), FileAccess.WRITE)
		f.store_8(0)
		f = null
	var old_orig: String = Assets.orig
	var old_idx: Dictionary = Assets._index
	Assets.orig = dir
	Assets._index = {"sprite/x/a.wav": "Sprite/x/a.wav", "sprite/x/b.wav": "Sprite/x/b.wav", "sprite/x/c.wav": "Sprite/x/c.wav", "sprite/x/d.wav": "Sprite/x/d.wav"}
	eq(Assets.sound_file("Sprite/x/a.wav"), dir.path_join("Sprite/x/a.wav"), "只有 wav: 读 wav")
	eq(Assets.sound_file("Sprite/x/b.wav"), dir.path_join("Sprite/x/b.ogg"), "wav 不在、有同名 ogg (导出版): 读 ogg")
	eq(Assets.sound_file("Sprite/x/c.wav"), dir.path_join("Sprite/x/c.wav"), "两个都有: 优先 wav (无损)")
	eq(Assets.sound_file("Sprite/x/d.wav"), "", "都没有: 空串 (sound() 会报错并返回 null)")
	Assets.orig = old_orig
	Assets._index = old_idx
	for n in ["Sprite/x/a.wav", "Sprite/x/b.ogg", "Sprite/x/c.wav", "Sprite/x/c.ogg"]:
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir.path_join("Sprite/x"))
	DirAccess.remove_absolute(dir.path_join("Sprite"))
	DirAccess.remove_absolute(dir)

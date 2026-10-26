# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 头像风格 (设定 face_style + Assets 的可选港漫 头像 mod): 设定行只在装了包时列、缺省经典、非法值回退;
## Assets 只在风格为 hk 且包里有这一帧时才改读包里的头像, 其余 (经典 / 没有这一帧 / 非头像 / 原版画质) 一律用 hd4x。

func test_setting_default_and_sanitize():
	eq(SettingsSchema.defaults()["face_style"], "hk", "头像风格缺省港漫 (没装头像 mod时 Assets 回退经典)")
	eq(SettingsSchema.sanitize({"face_style": "hk"})["face_style"], "hk", "hk 合法")
	eq(SettingsSchema.sanitize({"face_style": "classic"})["face_style"], "classic", "经典合法")
	eq(SettingsSchema.sanitize({"face_style": "xxx"})["face_style"], "hk", "非法值回退缺省")
	eq(SettingsSchema.sanitize({})["face_style"], "hk", "旧设定文件没有这个键: 取缺省")


func test_row_listed_only_with_the_pack():
	check(not SettingsSchema._need_ok("face_hk", false, false, false), "没装头像 mod不列")
	check(SettingsSchema._need_ok("face_hk", false, false, true), "装了头像 mod才列")
	eq(String(SettingsSchema.row("face_style").get("needs", "")), "face_hk", "行声明了 needs face_hk")


func test_assets_reads_alt_face_only_when_available():
	var dir := OS.get_user_data_dir().path_join("test_face_hk_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir.path_join("Face/Face05"))
	var fa := FileAccess.open(dir.path_join("Face/Face05/t0.webp"), FileAccess.WRITE)
	fa.store_8(0)
	fa = null   # 关文件: 只需要它存在
	var old := [Assets.face_style, Assets.face_alt_dir, Assets.gfx]
	Assets.face_alt_dir = dir
	Assets.gfx = "hd"
	Assets.face_style = "hk"
	eq(Assets._face_alt_file("Face/Face05/t0.png"), dir.path_join("Face/Face05/t0.webp"), "hk 且包里有: 读包里的 webp")
	eq(Assets._face_alt_file("Face/Face05/t1.png"), "", "包里没有这一帧: 回退经典")
	eq(Assets._face_alt_file("Stage/Stage01/map01.png"), "", "不是头像: 不碰")
	check(Assets.face_alt_available(), "包目录有 Face/ 即可用")
	Assets.gfx = "orig"
	eq(Assets._face_alt_file("Face/Face05/t0.png"), "", "原版画质: 不读")
	Assets.gfx = "hd"
	Assets.face_style = "classic"
	eq(Assets._face_alt_file("Face/Face05/t0.png"), "", "经典风格: 不读")
	Assets.face_style = "hk"
	Assets.face_alt_dir = ""
	eq(Assets._face_alt_file("Face/Face05/t0.png"), "", "没有头像 mod: 回退经典")
	check(not Assets.face_alt_available(), "没目录不可用")
	Assets.face_style = old[0]
	Assets.face_alt_dir = old[1]
	Assets.gfx = old[2]
	DirAccess.remove_absolute(dir.path_join("Face/Face05/t0.webp"))
	DirAccess.remove_absolute(dir.path_join("Face/Face05"))
	DirAccess.remove_absolute(dir.path_join("Face"))
	DirAccess.remove_absolute(dir)

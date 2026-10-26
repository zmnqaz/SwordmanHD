# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## macOS 资源包位置: 程序在 X/SwordmanHD.app/Contents/MacOS/, 资源包放在 .app 旁边的 X/resource/ (不放进 .app 内部)

const ResPacksScript = preload("res://engine/core/res_packs.gd")


func test_mac_pack_dir_is_beside_the_app() -> void:
	var root := OS.get_cache_dir().path_join("tdj_mac_pack_test_%d" % Time.get_ticks_usec())
	var exe_dir := root.path_join("SwordmanHD.app/Contents/MacOS")
	DirAccess.make_dir_recursive_absolute(exe_dir)
	DirAccess.make_dir_recursive_absolute(root.path_join("resource"))
	# 没有资源包: 仍指向 .app 旁边 (诊断里显示的就是这个目录)
	eq(ResPacksScript.mac_pack_dir(exe_dir), root, "没有包时指向 .app 所在目录")
	var f := FileAccess.open(root.path_join("resource/common_assets.pck"), FileAccess.WRITE)
	f.close()
	eq(ResPacksScript.mac_pack_dir(exe_dir), root, "包在 .app 旁边的 resource/ 里")
	DirAccess.remove_absolute(root.path_join("resource/common_assets.pck"))
	DirAccess.remove_absolute(root.path_join("resource"))
	DirAccess.remove_absolute(exe_dir)
	DirAccess.remove_absolute(root.path_join("SwordmanHD.app/Contents"))
	DirAccess.remove_absolute(root.path_join("SwordmanHD.app"))
	DirAccess.remove_absolute(root)

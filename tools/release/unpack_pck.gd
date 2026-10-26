# SPDX-License-Identifier: GPL-3.0-only
extends SceneTree
## 把 pack_pck.gd 打出的 .pck 原样解回目录 (包内 res:// 路径 → <out>/ 下的相对路径), 用于备份还原与校验:
##   godot --headless --path <空工程目录> --script tools/release/unpack_pck.gd -- --pck=<x.pck> --out=<目录>
## 必须用空工程目录做 --path, 否则 res:// 里会混进游戏自己的文件。同时打印文件数与总字节数。

func _initialize() -> void:
	var pck := ""
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pck="):
			pck = a.trim_prefix("--pck=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	quit(_unpack(pck, out))


func _unpack(pck: String, out: String) -> int:
	if pck == "" or out == "":
		printerr("unpack_pck: 需要 --pck= 与 --out=")
		return 1
	if not ProjectSettings.load_resource_pack(pck):
		printerr("unpack_pck: 无法挂载 ", pck)
		return 1
	var st := [0, 0]
	var err := _walk("res://", out, st)
	print("unpack_pck: %s %d 个文件, %d 字节" % [pck.get_file(), st[0], st[1]])
	return err


func _walk(dir: String, out: String, st: Array) -> int:
	var d := DirAccess.open(dir)
	if d == null:
		printerr("unpack_pck: 打不开 ", dir)
		return 1
	for sub in d.get_directories():
		if _walk(dir.path_join(sub), out, st) != 0:
			return 1
	for fn in d.get_files():
		var src := dir.path_join(fn)
		var data := FileAccess.get_file_as_bytes(src)
		if data.is_empty() and FileAccess.get_open_error() != OK:
			printerr("unpack_pck: 读失败 ", src)
			return 1
		var dst := out.path_join(src.trim_prefix("res://"))
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var w := FileAccess.open(dst, FileAccess.WRITE)
		if w == null:
			printerr("unpack_pck: 写失败 ", dst)
			return 1
		w.store_buffer(data)
		w.close()
		st[0] += 1
		st[1] += data.size()
	return 0

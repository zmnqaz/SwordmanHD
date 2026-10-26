# SPDX-License-Identifier: GPL-3.0-only
extends SceneTree
## 按清单把文件原样打成 Godot .pck (PCKPacker), 供 tools/build_windows.py 组装发布包:
##   godot --headless --script tools/release/pack_pck.gd -- --list=<清单> --out=<x.pck>
## 清单每行 "源文件绝对路径<TAB>res://包内路径" (UTF-8)。文件不导入、不转换 (WebP/mp3/ogv 本身已压缩)。
## 游戏启动时 Assets 用 ProjectSettings.load_resource_pack() 挂载, 之后按 res:// 路径用 FileAccess / Image.load_from_file 读取。

func _initialize() -> void:
	var list := ""
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--list="):
			list = a.trim_prefix("--list=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	quit(_pack(list, out))


func _pack(list: String, out: String) -> int:
	var f := FileAccess.open(list, FileAccess.READ)
	if f == null or out == "":
		printerr("pack_pck: 打不开清单 %s 或缺 --out" % list)
		return 1
	var pk := PCKPacker.new()
	if pk.pck_start(out) != OK:
		printerr("pack_pck: 无法创建 ", out)
		return 1
	var n := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line == "":
			continue
		var kv := line.split("\t")
		if kv.size() != 2:  # 清单行必须是 <源文件>\t<res://路径>; 否则 kv[1] 越界, 脚本出错但退出码不一定非 0
			printerr("pack_pck: 清单格式错误: ", line)
			return 1
		if pk.add_file(kv[1], kv[0]) != OK:
			printerr("pack_pck: 加入失败 ", kv[0])
			return 1
		n += 1
	if pk.flush(false) != OK:
		printerr("pack_pck: 写出失败 ", out)
		return 1
	print("pack_pck: %s %d 个文件" % [out.get_file(), n])
	return 0

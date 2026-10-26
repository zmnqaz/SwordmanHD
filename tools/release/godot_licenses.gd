# SPDX-License-Identifier: GPL-3.0-only
## 导出当前 Godot 引擎自带的许可文本 (发布包要附带): godot --headless -s tools/release/godot_licenses.gd -- <输出目录>
## 写出 Godot-LICENSE.txt (引擎 MIT 全文) 与 Godot-COPYRIGHT.txt (捆绑第三方组件的版权与许可全文), 由 tools/build_windows.py 调用。
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("用法: godot --headless -s tools/release/godot_licenses.gd -- <输出目录>")
		quit(2)
		return
	var out := args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("Godot-LICENSE.txt"), FileAccess.WRITE)
	f.store_string(Engine.get_license_text())
	f.close()
	var lines := PackedStringArray(["Godot Engine %s 捆绑的第三方组件 (Engine.get_copyright_info / get_license_info)" % Engine.get_version_info().string, ""])
	for c in Engine.get_copyright_info():
		lines.append("Component: " + str(c["name"]))
		for part in c["parts"]:
			for cr in part["copyright"]:
				lines.append("  Copyright: " + str(cr))
			lines.append("  License: " + str(part["license"]))
		lines.append("")
	var lic: Dictionary = Engine.get_license_info()
	for k in lic.keys():
		lines.append("-".repeat(72))
		lines.append("License: " + str(k))
		lines.append("")
		lines.append(str(lic[k]))
		lines.append("")
	f = FileAccess.open(out.path_join("Godot-COPYRIGHT.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	quit(0)

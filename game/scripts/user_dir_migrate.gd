# SPDX-License-Identifier: GPL-3.0-only
extends Node
## 用户目录迁移 (autoload, 排在最前, 先于 Content 读 user://settings.json)。
## 工程名改为 SwordmanHD 并启用自定义用户目录后, user:// 从
##   <数据目录>/Godot/app_userdata/天地劫：神魔至尊傳 復刻/  (Linux 为小写 godot)
## 变为 <数据目录>/SwordmanHD/ (Windows %APPDATA%\SwordmanHD, Linux ~/.local/share/SwordmanHD)。
## 新目录里还没有存档与设置时, 把旧目录的存档、设置、用户内容包复制过来 (只复制不删旧目录)。
## 然后把存档 / 回放搬到现在的位置 (UserPaths: 导出版在游戏文件夹的 save/ replay/, 其它在 user://save/ replay/), 见 UserDataMigrate。

const OLD_NAME := "天地劫：神魔至尊傳 復刻"
const SKIP := ["logs", "shader_cache", "objectdb_snapshots", "vulkan"]


func _init() -> void:
	var dst := OS.get_user_data_dir()
	var godot_dir := "godot" if OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"] else "Godot"
	var src := OS.get_data_dir().path_join(godot_dir).path_join("app_userdata").path_join(OLD_NAME)
	if src != dst and DirAccess.dir_exists_absolute(src) and not _has_user_data(dst):
		var n := _copy_tree(src, dst)
		if n > 0:
			print("用户目录迁移: 从 %s 复制 %d 个文件到 %s" % [src, n, dst])
	if DisplayServer.get_name() != "headless":   # 无头 (测试 / 工具) 不动玩家存档
		UserDataMigrate.run()   # 只在 macOS / 手机 / 源码运行静默整理; Windows / Linux 导出版由标题画面问玩家 (UserPaths.needs_prompt)


static func _has_user_data(dir: String) -> bool:
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		if f == "settings.json" or f == "battle.json" or (f.begins_with("save") and f.ends_with(".json")) or f == UserPaths.SAVE_SUB:
			return true
	return false


static func _copy_tree(src: String, dst: String) -> int:
	DirAccess.make_dir_recursive_absolute(dst)
	var n := 0
	for f in DirAccess.get_files_at(src):
		if not FileAccess.file_exists(dst.path_join(f)) and DirAccess.copy_absolute(src.path_join(f), dst.path_join(f)) == OK:
			n += 1
	for d in DirAccess.get_directories_at(src):
		if d not in SKIP:
			n += _copy_tree(src.path_join(d), dst.path_join(d))
	return n

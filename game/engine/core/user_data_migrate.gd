# SPDX-License-Identifier: GPL-3.0-only
class_name UserDataMigrate
extends RefCounted
## macOS / 手机 / 编辑器 (UserPaths 模式 user) 的存档整理: 把 user:// 根目录的旧存档与 user://replays/ 静默挪进 user://save/、user://replay/。
## 只在同一个 user:// 里挪, 先复制、读回校验, 成功才删旧文件; 启动时跑一次 (scripts/user_dir_migrate.gd), 幂等。
## Windows / Linux 导出版不走这里 (要玩家确认、可选位置, 见 SaveRelocate 与「存档位置」面板)。
## 规则: 目标没有就搬; 两边都有就留修改时间新的那份并记日志; 读不出来的旧存档不搬也不删, 留在原处并记日志。


## 返回搬动的文件数 (测试用); 日志写 print
static func run() -> int:
	if UserPaths.mode() != "user":
		return 0
	var save_dir := UserPaths.save_dir()
	var replay_dir := UserPaths.replay_dir()
	var n := 0
	var root := UserPaths.user_root
	n += _move_saves(root, save_dir)
	n += _move_dir(root.path_join(UserPaths.LEGACY_REPLAY_SUB), replay_dir)
	_remove_tree(root.path_join("replay_saves"))   # 旧回放沙盒: 每次回放都清空, 没有要留的东西
	if n > 0:
		print("存档目录: 已把 %d 个存档 / 回放文件整理到 %s 和 %s" % [n, UserPaths.shown(save_dir), UserPaths.shown(replay_dir)])
	return n


static func _move_saves(src_dir: String, dst_dir: String) -> int:
	if not DirAccess.dir_exists_absolute(src_dir) or src_dir.simplify_path() == dst_dir.simplify_path():
		return 0
	var names := {}
	for f in DirAccess.get_files_at(src_dir):
		var base := f
		for suf in [".bak"]:
			base = base.trim_suffix(suf)
		var at := base.find(".json.tmp")
		if at >= 0:
			base = base.substr(0, at + 5)
		if SaveRelocate.is_save_name(base):
			names[base] = true
	var n := 0
	for name in names:
		if String(name).ends_with(".replay"):
			n += 1 if _move_file(src_dir.path_join(name), dst_dir.path_join(name), false) else 0
		else:
			n += 1 if _move_json(src_dir.path_join(name), dst_dir.path_join(name)) else 0
	return n


## 存档 JSON: 源读得出来才搬 (read_json 顺带用源处的 .tmp / .bak 恢复并清掉 .bak); 目标已有且读得出来时比修改时间
static func _move_json(src: String, dst: String) -> bool:
	if not SaveFile.exists(src):
		return false
	var d = SaveFile.read_json(src)
	if d == null:
		print("存档目录: %s 读不出来, 留在原处没搬" % ProjectSettings.globalize_path(src))
		return false
	if SaveFile.read_json(dst) != null:
		if FileAccess.get_modified_time(src) <= FileAccess.get_modified_time(dst):
			print("存档目录: %s 新位置已有更新的一份, 旧的删掉" % dst.get_file())
			_remove_save(src)
			return false
		print("存档目录: %s 旧位置的更新, 覆盖新位置那份" % dst.get_file())
	if not SaveFile.write_json(dst, d) or SaveFile.read_json(dst) == null:
		print("存档目录: %s 写不进新位置, 留在原处" % src.get_file())
		return false
	_remove_save(src)
	return true


static func _remove_save(src: String) -> void:
	DirAccess.remove_absolute(src)
	DirAccess.remove_absolute(src + ".bak")
	for t in SaveFile._tmps(src):
		DirAccess.remove_absolute(t)


## 普通文件 (回放、录像历史): 目标没有或比源旧就拷过去, 大小一致才删源
static func _move_file(src: String, dst: String, _json: bool) -> bool:
	if not FileAccess.file_exists(src):
		return false
	if FileAccess.file_exists(dst) and FileAccess.get_modified_time(dst) >= FileAccess.get_modified_time(src):
		DirAccess.remove_absolute(src)
		return false
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	if DirAccess.copy_absolute(src, dst) != OK or _size(dst) != _size(src):
		print("存档目录: %s 拷不到新位置, 留在原处" % src.get_file())
		return false
	DirAccess.remove_absolute(src)
	return true


## 整个目录 (含子目录) 搬过去
static func _move_dir(src_dir: String, dst_dir: String) -> int:
	if not DirAccess.dir_exists_absolute(src_dir) or src_dir.simplify_path() == dst_dir.simplify_path():
		return 0
	var n := 0
	for f in DirAccess.get_files_at(src_dir):
		n += 1 if _move_file(src_dir.path_join(f), dst_dir.path_join(f), false) else 0
	for sub in DirAccess.get_directories_at(src_dir):
		n += _move_dir(src_dir.path_join(sub), dst_dir.path_join(sub))
	_remove_if_empty(src_dir)
	return n


static func _size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n


static func _remove_if_empty(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir) and DirAccess.get_files_at(dir).is_empty() and DirAccess.get_directories_at(dir).is_empty():
		DirAccess.remove_absolute(dir)


static func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)

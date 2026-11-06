# SPDX-License-Identifier: GPL-3.0-only
class_name SaveRelocate
extends RefCounted
## 把存档 / 回放从一个位置搬到另一个位置 (UserPaths 的模式之间), 第一原则「绝不丢档」(2026-11-06 用户要求):
##   1. 先把源处的存档读一遍 (SaveFile.read_json: 正式文件坏了用 .tmp / .bak 恢复), 读不出来的存档整体中止, 什么都不动;
##   2. 逐个复制到目标, 读回校验 (字节一致; 存档另要能解析成字典); 目标已有同名而内容不同 → 中止 (不覆盖);
##   3. 全部成功才切换位置 (UserPaths.save_choice 写进设定并读回);
##   4. 任一步失败: 删掉这次复制出去的文件 (目标原有的不碰), 继续用原位置, 返回原因;
##   5. 成功后旧文件不删, 改名挪进旧位置下的「旧存档备份_日期时间」文件夹 (玩家确认无误后可自己删), 不再有散落的 .bak。
## 受管文件: 存档目录里的 save1~5.json、battle.json、它们的录像历史 .replay、镜像记录 mirror_state.json (连同 .bak / .tmp* 残留, 只进备份不复制);
## 回放目录里除沙盒 (sandbox/) 外的全部录像 .json (含子目录)。

## 备份文件夹名前缀 (跟界面语言: 简体「旧存档备份_」/ 繁体「舊存檔備份_」, 文本表 savelocation.backup_dir)
static func backup_prefix() -> String:
	return UiStrings.t("savelocation.backup_dir")


## 存档类文件名? (不含 .bak / .tmp 残留)
static func is_save_name(f: String) -> bool:
	var base := f.trim_suffix(PlayLog.HISTORY_EXT)
	if base == "battle.json" or base == SaveMirror.STATE_FILE:
		return true
	return base.begins_with("save") and base.ends_with(".json") and base.trim_prefix("save").trim_suffix(".json").is_valid_int()


## 存档目录里的残留 (.bak / .tmp*) 属于哪个存档; 不是残留返回 ""
static func leftover_of(f: String) -> String:
	if f.ends_with(".bak"):
		return f.trim_suffix(".bak")
	if f.ends_with(SaveMirror.BEFORE_IMPORT):
		return f.trim_suffix(SaveMirror.BEFORE_IMPORT)
	var at := f.find(".json.tmp")
	return f.substr(0, at + 5) if at >= 0 else ""


## 位置 {save, replay} 里的受管文件: {saves: [文件名], leftovers: [文件名], replays: [相对路径]}
static func list(dirs: Dictionary) -> Dictionary:
	var out := {"saves": [], "leftovers": [], "replays": []}
	var sd := String(dirs["save"])
	if DirAccess.dir_exists_absolute(sd):
		for f in DirAccess.get_files_at(sd):
			if is_save_name(f):
				out.saves.append(f)
			elif is_save_name(leftover_of(f)):
				out.leftovers.append(f)
	_walk(String(dirs["replay"]), "", out.replays)
	return out


static func _walk(root: String, rel: String, out: Array) -> void:
	var d := root.path_join(rel) if rel != "" else root
	if not DirAccess.dir_exists_absolute(d):
		return
	for f in DirAccess.get_files_at(d):
		if f.ends_with(".json"):   # 录像都是 .json; 说明文字 (说明.txt) 等不算、不搬
			out.append(rel.path_join(f) if rel != "" else f)
	for sub in DirAccess.get_directories_at(d):
		if rel == "" and sub == UserPaths.SANDBOX_SUB:
			continue
		_walk(root, rel.path_join(sub) if rel != "" else sub, out)


## 数一数: {saves: 存档个数 (只算 saveN.json / battle.json), replays: 回放个数, total: 受管文件总数}
static func count(dirs: Dictionary) -> Dictionary:
	var l := list(dirs)
	var n_save := 0
	for f in l.saves:
		if f.ends_with(".json") and f != SaveMirror.STATE_FILE:
			n_save += 1
	for f in l.leftovers:   # 只剩 .bak / .tmp (正式文件没了) 的存档也算
		var base := leftover_of(f)
		if not l.saves.has(base) and base != SaveMirror.STATE_FILE:
			n_save += 1
	var n_rep := 0
	for f in l.replays:
		if f.ends_with(".json"):
			n_rep += 1
	return {"saves": n_save, "replays": n_rep, "total": l.saves.size() + l.leftovers.size() + l.replays.size()}


## 从 src 搬到 dst (两者都是 {save, replay}); 成功后调 on_switch (返回 bool: 切换位置是否成功, 失败也回滚)。
## 返回 {ok, error (给玩家看的原因), copied: 复制的文件数, backup: 旧文件备份文件夹 (globalize 后的路径, 没有则 "")}
static func relocate(src: Dictionary, dst: Dictionary, on_switch: Callable) -> Dictionary:
	var res := {"ok": false, "error": "", "copied": 0, "backup": ""}
	if _same(src.save, dst.save) and _same(src.replay, dst.replay):
		res.ok = bool(on_switch.call())
		res.error = "" if res.ok else "error.switch"
		return res
	# 1. 源存档先读一遍 (顺带用 .tmp / .bak 恢复), 读不出来就整体不动
	var l := list(src)
	for f in l.leftovers:
		var base := leftover_of(f)
		if not l.saves.has(base):
			l.saves.append(base)
	for f in l.saves:
		if f.ends_with(".json") and SaveFile.read_json(String(src.save).path_join(f)) == null:
			res.error = "error.unreadable:" + f
			return res
	l = list(src)   # 恢复后重新列 (.bak 已被吸收)
	var jobs := []   # [源, 目标, 是存档 JSON]
	for f in l.saves:
		jobs.append([String(src.save).path_join(f), String(dst.save).path_join(f), f.ends_with(".json")])
	for f in l.replays:
		jobs.append([String(src.replay).path_join(f), String(dst.replay).path_join(f), false])
	# 2. 复制 + 校验; 失败回滚
	var created := []
	for j in jobs:
		var why := _copy_verified(j[0], j[1], j[2], created)
		if why != "":
			_rollback(created)
			res.error = why
			return res
	res.copied = jobs.size()
	# 3. 切换位置
	if not bool(on_switch.call()):
		_rollback(created)
		res.error = "error.switch"
		return res
	# 4. 旧文件挪进备份文件夹 (失败只告警: 新位置已经完整可用)
	res.backup = _backup(src, list(src))
	res.ok = true
	return res


static func _same(a: String, b: String) -> bool:
	return UserPaths.shown(a).simplify_path() == UserPaths.shown(b).simplify_path()


## 复制一个文件并校验; 成功返回 "", 失败返回原因代号。目标已有且内容相同算成功 (不计入 created), 内容不同中止
static func _copy_verified(src: String, dst: String, is_save: bool, created: Array) -> String:
	var data := FileAccess.get_file_as_bytes(src)
	if FileAccess.file_exists(dst):
		return "" if FileAccess.get_file_as_bytes(dst) == data else "error.conflict:" + dst.get_file()
	if DirAccess.make_dir_recursive_absolute(dst.get_base_dir()) != OK:
		return "error.mkdir"
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return "error.write:" + dst.get_file()
	f.store_buffer(data)
	f.flush()
	var err := f.get_error()
	f.close()
	created.append(dst)
	if err != OK or FileAccess.get_file_as_bytes(dst) != data:
		return "error.verify:" + dst.get_file()
	if is_save and SaveFile._parse(dst) == null:
		return "error.verify:" + dst.get_file()
	return ""


static func _rollback(created: Array) -> void:
	for p in created:
		DirAccess.remove_absolute(p)


## 旧位置的受管文件挪进 <旧存档目录>/旧存档备份_YYYYMMDD_HHMMSS/ (存档在其根下, 回放在 replay/ 下); 返回备份文件夹路径
static func _backup(src: Dictionary, l: Dictionary) -> String:
	var d := Time.get_datetime_dict_from_system()
	var name := backup_prefix() + "%04d%02d%02d_%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	var root := String(src.save).path_join(name)
	DirAccess.make_dir_recursive_absolute(root)
	for f in l.saves + l.leftovers:
		_move(String(src.save).path_join(f), root.path_join(f))
	for f in l.replays:
		_move(String(src.replay).path_join(f), root.path_join(UserPaths.REPLAY_SUB).path_join(f))
	_prune_empty(String(src.replay))
	var rd := String(src.replay)
	if DirAccess.dir_exists_absolute(rd) and DirAccess.get_files_at(rd).is_empty() and DirAccess.get_directories_at(rd).is_empty():
		DirAccess.remove_absolute(rd)   # 旧录像目录搬空了就删掉 (留着空目录玩家会以为还有东西)
	return UserPaths.shown(root)


static func _move(a: String, b: String) -> void:
	DirAccess.make_dir_recursive_absolute(b.get_base_dir())
	if DirAccess.rename_absolute(a, b) != OK:   # 不同盘: 复制成功再删
		if DirAccess.copy_absolute(a, b) == OK and FileAccess.get_file_as_bytes(a) == FileAccess.get_file_as_bytes(b):
			DirAccess.remove_absolute(a)
		else:
			push_warning("存档位置: 旧文件 %s 没能挪进备份文件夹, 留在原处" % a)


## 回放目录里空掉的子目录删掉 (不删回放目录本身以外的东西; 沙盒照留)
static func _prune_empty(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		if sub != UserPaths.SANDBOX_SUB:
			_prune_empty(dir.path_join(sub))
			if DirAccess.get_files_at(dir.path_join(sub)).is_empty() and DirAccess.get_directories_at(dir.path_join(sub)).is_empty():
				DirAccess.remove_absolute(dir.path_join(sub))

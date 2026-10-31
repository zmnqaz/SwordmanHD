# SPDX-License-Identifier: GPL-3.0-only
class_name SaveMirror
extends RefCounted
## 存档镜像 (Android): 应用私有目录 (user://) 里的存档, 没 root 取不出来也放不进去, 所以每次存档同时在公开的应用外部目录
## (/sdcard/Android/data/<包名>/files/saves/, 和资源包同处, adb push/pull 能读写) 留一份同名拷贝, 玩家可以备份、导入转换后的原版存档。
##
## 判断「镜像文件是不是被人换过」不比修改时间 (换进来的常是旧档), 比内容指纹: 每次镜像写出时把文件的 MD5 记进
## <本地目录>/mirror_state.json; 镜像里文件的指纹和记录一致 = 游戏自己写的, 不用管; 对不上 = 外部换过, 校验通过就覆盖本地存档
## (旧的先改名 .bak), 不通过 (格式/版本/关卡范围) 就保留镜像文件不动并报告原因, 本地存档不受影响。
## 纯静态, 目录都由调用方给 (GameSaves 决定什么时候、在哪个目录启用)。

const SUBDIR := "saves"
const STATE_FILE := "mirror_state.json"


## 受管的文件名: 5 个存档位 + 战阵存录
static func names() -> Array:
	var out := []
	for i in GameSaves.SLOTS:
		out.append("save%d.json" % (i + 1))
	out.append("battle.json")
	return out


static func _kind(name: String) -> String:
	return "battle" if name == "battle.json" else "game"


static func _read_state(local_dir: String) -> Dictionary:
	var d = SaveFile.read_json(local_dir.path_join(STATE_FILE))
	return d if d is Dictionary else {}


static func _write_state(local_dir: String, state: Dictionary) -> void:
	SaveFile.write_json(local_dir.path_join(STATE_FILE), state)


## 整文件拷贝 (先写临时文件再改名); keep_bak 时目标已有的旧文件先改名 .bak
static func _copy(src: String, dst: String, keep_bak: bool) -> bool:
	var data := FileAccess.get_file_as_bytes(src)
	if data.is_empty():
		return false
	var tmp := "%s.tmp%d" % [dst, OS.get_process_id()]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(dst):
		if keep_bak:
			if FileAccess.file_exists(dst + ".bak"):
				DirAccess.remove_absolute(dst + ".bak")
			DirAccess.rename_absolute(dst, dst + ".bak")
		else:
			DirAccess.remove_absolute(dst)
	if DirAccess.rename_absolute(tmp, dst) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true


## 把本地存档 name 镜像出去 (存档成功后调); 镜像目录写不了只告警, 不影响存档本身
static func push(local_dir: String, mirror_dir: String, name: String) -> bool:
	var src := local_dir.path_join(name)
	if not FileAccess.file_exists(src):
		return false
	DirAccess.make_dir_recursive_absolute(mirror_dir)
	var dst := mirror_dir.path_join(name)
	if not _copy(src, dst, false):
		push_warning("存档镜像写入失败: " + dst)
		return false
	var state := _read_state(local_dir)
	state[name] = FileAccess.get_md5(dst)
	_write_state(local_dir, state)
	return true


## 镜像文件能不能当存档读进来: "" = 可以。check(name, data) 是调用方的附加校验 (如关卡范围), 返回 "" 通过
static func validate(path: String, name: String, check := Callable()) -> String:
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Dictionary:
		return "不是有效的存档文件"
	var d: Dictionary = j.data
	var r := SaveFile.migrate(d, _kind(name))
	if not r.ok:
		return String(r.error)
	if check.is_valid():
		return String(check.call(name, r.data))
	return ""


## 导入被外部换过的镜像存档: 返回 {"imported": [文件名], "rejected": {文件名: 原因}}
static func pull(local_dir: String, mirror_dir: String, check := Callable()) -> Dictionary:
	var out := {"imported": [], "rejected": {}}
	var state := _read_state(local_dir)
	var dirty := false
	for name in names():
		var m := mirror_dir.path_join(name)
		if not FileAccess.file_exists(m):
			continue
		var h := FileAccess.get_md5(m)
		if h == String(state.get(name, "")):
			continue   # 游戏自己写的镜像
		var local := local_dir.path_join(name)
		if FileAccess.file_exists(local) and h == FileAccess.get_md5(local):
			state[name] = h   # 内容本来就一样 (状态记录丢了): 补记录
			dirty = true
			continue
		var why := validate(m, name, check)
		if why != "":
			out.rejected[name] = why
			push_warning("镜像存档 %s 未导入: %s" % [m, why])
			continue
		if _copy(m, local, true):
			state[name] = h
			dirty = true
			out.imported.append(name)
		else:
			out.rejected[name] = "无法写入本地存档"
	if dirty:
		_write_state(local_dir, state)
	return out


## 启动/打开读档窗时调: 先导入换进来的, 再把还没镜像的本地存档补镜像出去 (已有镜像文件的不覆盖, 被拒绝的文件留给玩家处理)
static func sync(local_dir: String, mirror_dir: String, check := Callable()) -> Dictionary:
	var r := pull(local_dir, mirror_dir, check)
	for name in names():
		if FileAccess.file_exists(local_dir.path_join(name)) and not FileAccess.file_exists(mirror_dir.path_join(name)):
			push(local_dir, mirror_dir, name)
	return r

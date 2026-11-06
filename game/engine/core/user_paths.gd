# SPDX-License-Identifier: GPL-3.0-only
class_name UserPaths
extends RefCounted
## 玩家数据放在哪 (存档 / 回放): 所有路径都从这里取, 别的代码不拼 "user://save..." 之类。
## 设定 settings.json、日志、hq_cache、shader_cache 一律留在 user:// 根目录, 不归这里管 (位置选择本身也记在 settings.json 的 save_location)。
##
## 位置模式 (settings.json 的 "save_location": {"mode", "path"}):
##   game   游戏文件夹 (程序旁) 的 save/、replay/ —— Windows / Linux 导出版的缺省: 整个文件夹拷走, 存档跟着走 (2026-11-06 用户要求)
##   custom 玩家选的文件夹 (path) 下的 save/、replay/
##   legacy 旧位置: user:// 根目录的 saveN.json / battle.json 与 user://replays/ (2026-11-06 以前的版本都放这里; 玩家选「先不动」时继续用)
##   user   user:// 下的 save/、replay/ —— macOS (.app 里写东西破坏签名, App Translocation 下程序在只读随机路径)、手机、编辑器 / 源码运行,
##          以及游戏文件夹写不进去 (C:\Program Files、/opt、只读介质) 时的退路
## Windows / Linux 导出版 (relocatable) 第一次跑新版本时若旧位置有存档 / 回放, 先按 legacy 用着并置 needs_prompt, 由标题画面弹「存档位置」
## 让玩家选 (搬到游戏文件夹 / 选其它文件夹 / 先不动), 绝不静默搬; 搬迁见 SaveRelocate。其它平台在 user:// 里静默整理 (UserDataMigrate)。
## 选过的位置失效 (盘符没了、写不进去) 时退回缺省位置并置 problem, 标题画面提示玩家, 不悄悄写别处。

const SAVE_SUB := "save"
const REPLAY_SUB := "replay"
const LEGACY_REPLAY_SUB := "replays"
const SANDBOX_SUB := "sandbox"   # 回放期间的存档沙盒 (回放里的「存档」写这里, 不碰真存档), 在回放目录下
const SETTINGS := "user://settings.json"   # 游戏用的设定文件 (测试换 user_root 时用 settings_path())
const KEY := "save_location"
const MODES := ["game", "custom", "legacy", "user"]

## user:// (测试换成沙盒目录: 旧位置、user 模式目录、设定文件都在它下面)
static var user_root := "user://"
## 测试 / 工具改根目录用 (非空 = 按 custom 处理这个目录, 不读不写设定)
static var root_override := ""
## 测试用: 假装是 Windows / Linux 导出版, 程序目录 = 这个 (空 = 按真实情况)
static var exe_override := ""
static var _mode := ""
static var _path := ""
## 启动时要不要弹「存档位置」(旧位置发现存档, 或选过的位置失效)
static var needs_prompt := false
## 选过的位置为什么用不了 ("" 没问题 / "game" 游戏文件夹写不进去 / "custom" 自选文件夹用不了), UI 提示用
static var problem := ""


static func mode() -> String:
	_resolve()
	return _mode


static func custom_path() -> String:
	_resolve()
	return _path


## 存档目录
static func save_dir() -> String:
	_resolve()
	return dirs_for(_mode, _path)["save"]


static func replay_dir() -> String:
	_resolve()
	return dirs_for(_mode, _path)["replay"]


static func replay_sandbox() -> String:
	return replay_dir().path_join(SANDBOX_SUB)


## 某模式下的存档 / 回放目录 (搬迁前算目标用)
## 「game」没有程序目录 (源码运行 / 测试把 exe_override 清掉之后)、「custom」没给目录时按 user 算: 绝不返回相对路径
## (相对路径落在当前目录, 2026-11-06 测试中途出过一次 game/replay/)
static func dirs_for(m: String, path := "") -> Dictionary:
	if (m == "game" and exe_dir() == "") or (m == "custom" and path == ""):
		m = "user"
	match m:
		"legacy":
			return {"save": user_root, "replay": user_root.path_join(LEGACY_REPLAY_SUB)}
		"game":
			return {"save": exe_dir().path_join(SAVE_SUB), "replay": exe_dir().path_join(REPLAY_SUB)}
		"custom":
			return {"save": path.path_join(SAVE_SUB), "replay": path.path_join(REPLAY_SUB)}
	return {"save": user_root.path_join(SAVE_SUB), "replay": user_root.path_join(REPLAY_SUB)}


static func settings_path() -> String:
	return user_root.path_join("settings.json")


## 能不能把存档放到游戏文件夹 / 自选文件夹 (Windows / Linux 导出版)
static func relocatable() -> bool:
	return exe_dir() != ""


## Windows / Linux 导出版的程序目录 (其它情况返回 "")
static func exe_dir() -> String:
	if exe_override != "":
		return exe_override
	if not OS.has_feature("template") or not (OS.get_name() in ["Windows", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]):
		return ""
	return OS.get_executable_path().get_base_dir()


## 缺省位置: 游戏文件夹写得进去就用它, 否则 user://save
static func default_mode() -> String:
	return "game" if relocatable() and writable(exe_dir()) else "user"


## 存在设定里的位置选择 ({} = 没选过)
static func saved_choice() -> Dictionary:
	var d = SaveFile.read_json(settings_path())
	var c = d.get(KEY) if d is Dictionary else null
	return c if c is Dictionary and String(c.get("mode", "")) in MODES else {}


## 记下位置选择并立即生效 (合并写入 settings.json, 不动别的键); 写成功并读回一致才算数
static func save_choice(m: String, path := "") -> bool:
	var d = SaveFile.read_json(settings_path())
	if not d is Dictionary:
		d = {}
	d[KEY] = {"mode": m, "path": path}
	if not SaveFile.write_json(settings_path(), SaveFile.stamp(d, "settings")):
		return false
	var c := saved_choice()
	if String(c.get("mode", "")) != m or String(c.get("path", "")) != path:
		return false
	_mode = m
	_path = path
	needs_prompt = false
	problem = ""
	GameSaves.base_dir = save_dir()
	return true


## 定下当前模式 (第一次用到路径时跑一次; reset() 后重来)
static func _resolve() -> void:
	if _mode != "":
		return
	needs_prompt = false
	problem = ""
	var dr := DebugArgs.current().data_root   # --data-root=<目录>: 工具 (仓库外的开发脚本 等) 让游戏把存档写进临时目录, 别碰玩家的存档
	if dr != "":
		_mode = "custom"
		_path = dr
		return
	if root_override != "":
		_mode = "custom"
		_path = root_override
		return
	if not relocatable():
		_mode = "user"
		return
	var c := saved_choice()
	if not c.is_empty():
		var m := String(c["mode"])
		var p := String(c.get("path", ""))
		var bad := ""
		if m == "game" and not writable(exe_dir()):
			bad = "game"
		elif m == "custom" and (p == "" or not writable(p)):
			bad = "custom"
		if bad == "":
			_mode = m
			_path = p
			return
		problem = bad   # 选过的位置用不了: 退回缺省位置, 标题画面提示 (不悄悄写别处)
		needs_prompt = true
		_mode = default_mode()
		_path = ""
		print("存档位置: 设定里的位置 %s 用不了, 暂用 %s" % [p if m == "custom" else exe_dir(), shown(save_dir())])
		return
	if SaveRelocate.count(dirs_for("legacy")).total > 0:   # 老玩家: 旧位置有存档 / 回放, 先照旧用着, 让玩家选
		_mode = "legacy"
		needs_prompt = true
		return
	_mode = default_mode()   # 新玩家: 直接用缺省位置并记下 (以后不再问)
	save_choice(_mode)


## 目录能不能写: 建 save/ 子目录并写一个测试文件再删掉 (只读介质、Program Files 无权限都会失败); 不靠猜路径
static func writable(dir: String) -> bool:
	if dir == "" or FileAccess.file_exists(dir) or FileAccess.file_exists(dir.path_join(SAVE_SUB)):   # 路径是个文件: 不是文件夹
		return false
	var sub := dir.path_join(SAVE_SUB)
	if DirAccess.make_dir_recursive_absolute(sub) != OK:
		return false
	var probe := sub.path_join(".write_test%d" % OS.get_process_id())
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	var ok := FileAccess.get_file_as_string(probe) == "ok"
	DirAccess.remove_absolute(probe)
	return ok


## 给人看的路径 (user:// 换成真实路径)
static func shown(p: String) -> String:
	return ProjectSettings.globalize_path(p)


## 测试用: 清掉缓存的选择
static func reset() -> void:
	_mode = ""
	_path = ""
	root_override = ""
	exe_override = ""
	user_root = "user://"
	needs_prompt = false
	problem = ""

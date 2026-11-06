# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 存档位置 (engine/core/user_paths.gd) 与搬迁 (save_relocate.gd)、静默整理 (user_data_migrate.gd)、「存档位置」面板条目 (2026-11-06):
## 全部在测试沙盒里 (UserPaths.user_root / exe_override 指过去), 不碰真实 user:// 与设定文件。

var _root := ""
var _user := ""
var _game := ""


func _setup() -> void:
	UserPaths.reset()
	_root = tmp_dir("save_location_%d" % Time.get_ticks_usec())
	_user = _root.path_join("user")
	_game = _root.path_join("game")
	DirAccess.make_dir_recursive_absolute(_user)
	DirAccess.make_dir_recursive_absolute(_game)
	UserPaths.user_root = _user
	UserPaths.exe_override = _game   # 假装是 Windows / Linux 导出版, 程序在 _game


func _done() -> void:
	UserPaths.reset()
	GameSaves.base_dir = UserPaths.save_dir()
	remove_tree(_root)


func _write(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _save(dir: String, name: String, gold: int) -> void:
	_write(dir.path_join(name), JSON.stringify({"version": SaveFile.VERSION, "gold": gold}))


## 旧位置 (user:// 根目录 + replays/) 摆一套老玩家的数据
func _legacy() -> void:
	_save(_user, "save1.json", 100)
	_save(_user, "save3.json", 300)
	_write(_user.path_join("save3.json.bak"), JSON.stringify({"version": SaveFile.VERSION, "gold": 299}))
	_save(_user, "battle.json", 7)
	_write(_user.path_join("save1.json.replay"), "HIST")
	_write(_user.path_join("replays/play_20261101_100000.json"), "{\"v\":1}")
	_write(_user.path_join("replays/sub/stage_01_20261101_100000.json"), "{\"v\":2}")
	_write(_user.path_join("replays/sandbox/save1.json"), "{}")   # 回放沙盒: 不搬
	_write(_user.path_join("settings.json"), JSON.stringify({"version": SaveFile.VERSION, "music": 7}))


func test_new_player_goes_to_game_folder_silently():
	_setup()
	eq(UserPaths.mode(), "game", "旧位置没东西: 直接用游戏文件夹")
	check(not UserPaths.needs_prompt, "不弹")
	eq(UserPaths.saved_choice().get("mode"), "game", "记进设定")
	eq(UserPaths.save_dir(), _game.path_join("save"))
	eq(UserPaths.replay_dir(), _game.path_join("replay"))
	UserPaths._mode = ""   # 重启
	UserPaths._resolve()
	check(not UserPaths.needs_prompt, "下次启动也不弹")
	_done()


func test_old_player_is_asked_and_keeps_using_old_place_meanwhile():
	_setup()
	_legacy()
	eq(UserPaths.mode(), "legacy", "旧位置有存档: 先照旧用")
	check(UserPaths.needs_prompt, "要问玩家")
	eq(UserPaths.save_dir(), _user)
	eq(UserPaths.replay_dir(), _user.path_join("replays"))
	var c := SaveRelocate.count(UserPaths.dirs_for("legacy"))
	eq([c.saves, c.replays], [3, 2], "3 个存档 (含 battle)、2 份录像 (沙盒不算)")
	check(UserPaths.saved_choice().is_empty(), "没选之前不写设定")
	_done()


func test_move_to_game_folder_copies_verifies_switches_and_backs_up():
	_setup()
	_legacy()
	UserPaths.mode()
	var r := SaveRelocate.relocate(UserPaths.dirs_for("legacy"), UserPaths.dirs_for("game"), func(): return UserPaths.save_choice("game"))
	check(r.ok, "搬成功: " + str(r))
	var sd := _game.path_join("save")
	eq(int(SaveFile.read_json(sd.path_join("save1.json"))["gold"]), 100)
	eq(int(SaveFile.read_json(sd.path_join("save3.json"))["gold"]), 300, "正式文件好的就用正式文件")
	eq(FileAccess.get_file_as_string(sd.path_join("save1.json.replay")), "HIST", "录像历史跟着走")
	check(FileAccess.file_exists(_game.path_join("replay/sub/stage_01_20261101_100000.json")), "子目录的录像")
	check(not FileAccess.file_exists(_game.path_join("replay/sandbox/save1.json")), "沙盒不搬")
	check(not FileAccess.file_exists(sd.path_join("save3.json.bak")), "新位置没有散落的 .bak")
	eq(UserPaths.mode(), "game", "已切换")
	check(not UserPaths.needs_prompt)
	eq(UserPaths.saved_choice().get("mode"), "game")
	eq(int(SaveFile.read_json(_user.path_join("settings.json"))["music"]), 7, "设定里别的键没动")
	# 旧文件挪进备份文件夹, 不删
	check(String(r.backup) != "", "有备份文件夹")
	var bk := ""
	for d in DirAccess.get_directories_at(_user):
		if d.begins_with(SaveRelocate.backup_prefix()):
			bk = _user.path_join(d)
	check(bk != "", "旧存档备份_日期 文件夹在旧位置下")
	check(FileAccess.file_exists(bk.path_join("save1.json")) and FileAccess.file_exists(bk.path_join("battle.json")), "旧存档在备份里")
	check(FileAccess.file_exists(bk.path_join("replay/sub/stage_01_20261101_100000.json")), "旧录像在备份里")
	check(not FileAccess.file_exists(_user.path_join("save1.json")) and not FileAccess.file_exists(_user.path_join("save3.json.bak")), "旧位置不再散落存档 / .bak")
	check(FileAccess.file_exists(_user.path_join("settings.json")), "设定文件留在原处")
	eq(SaveRelocate.count(UserPaths.dirs_for("legacy")).total, 0, "旧位置清空 (只剩沙盒), 下次不会再问")
	_done()


func test_conflict_rolls_back_everything():
	_setup()
	_legacy()
	UserPaths.mode()
	_save(_game.path_join("save"), "save3.json", 999)   # 新位置已经有一份不同的
	var r := SaveRelocate.relocate(UserPaths.dirs_for("legacy"), UserPaths.dirs_for("game"), func(): return UserPaths.save_choice("game"))
	check(not r.ok and String(r.error).begins_with("error.conflict"), "中止: " + str(r))
	check(not FileAccess.file_exists(_game.path_join("save/save1.json")), "这次复制出去的全撤回")
	eq(int(SaveFile.read_json(_game.path_join("save/save3.json"))["gold"]), 999, "目标原有的不碰")
	eq(int(SaveFile.read_json(_user.path_join("save1.json"))["gold"]), 100, "原位置完好")
	eq(UserPaths.mode(), "legacy", "继续用原位置")
	check(UserPaths.saved_choice().is_empty(), "设定没改")
	check(SaveLocationPanel.result_text(r).contains("save3.json"), "原因里说是哪个文件")
	_done()


func test_unreadable_source_aborts_before_copying():
	_setup()
	_legacy()
	UserPaths.mode()
	_write(_user.path_join("save1.json"), "{坏")
	var r := SaveRelocate.relocate(UserPaths.dirs_for("legacy"), UserPaths.dirs_for("game"), func(): return UserPaths.save_choice("game"))
	check(not r.ok and String(r.error) == "error.unreadable:save1.json", str(r))
	check(not DirAccess.dir_exists_absolute(_game.path_join("replay")), "什么都没复制")
	check(FileAccess.file_exists(_user.path_join("save1.json")), "坏档留在原处")
	_done()


func test_switch_failure_rolls_back():
	_setup()
	_legacy()
	UserPaths.mode()
	var r := SaveRelocate.relocate(UserPaths.dirs_for("legacy"), UserPaths.dirs_for("game"), func(): return false)
	check(not r.ok and r.error == "error.switch", str(r))
	check(not FileAccess.file_exists(_game.path_join("save/save1.json")), "撤回")
	check(FileAccess.file_exists(_user.path_join("save1.json")), "原位置完好, 没进备份")
	_done()


func test_custom_folder_gone_falls_back_and_asks():
	_setup()
	var gone := _root.path_join("is_a_file")
	_write(gone, "x")   # 选过的文件夹现在是个文件 (盘符没了 / 写不进去 的替身)
	UserPaths.save_choice("custom", gone)
	UserPaths._mode = ""
	UserPaths._resolve()
	eq(UserPaths.problem, "custom", "选过的位置用不了")
	check(UserPaths.needs_prompt, "启动提示")
	eq(UserPaths.mode(), "game", "暂用缺省位置")
	eq(UserPaths.saved_choice().get("path"), gone, "设定不偷偷改, 等玩家决定")
	_done()


func test_keep_records_choice_and_stops_asking():
	_setup()
	_legacy()
	UserPaths.mode()
	check(UserPaths.save_choice(UserPaths.mode()), "先不动")
	UserPaths._mode = ""
	UserPaths._resolve()
	eq(UserPaths.mode(), "legacy", "继续用原位置")
	check(not UserPaths.needs_prompt, "不再问")
	_done()


func test_move_to_custom_then_back_to_game():
	_setup()
	_save(_user.path_join("save"), "save2.json", 2)   # user 模式残留不算旧位置
	UserPaths.mode()
	var other := _root.path_join("other")
	_save(_game.path_join("save"), "save2.json", 22)
	var r := SaveRelocate.relocate(UserPaths.dirs_for("game"), UserPaths.dirs_for("custom", other), func(): return UserPaths.save_choice("custom", other))
	check(r.ok, str(r))
	eq(UserPaths.save_dir(), other.path_join("save"))
	eq(int(SaveFile.read_json(other.path_join("save/save2.json"))["gold"]), 22)
	var r2 := SaveRelocate.relocate(UserPaths.dirs_for("custom", other), UserPaths.dirs_for("game"), func(): return UserPaths.save_choice("game"))
	check(r2.ok, "搬回来 (游戏文件夹的旧档已进备份, 不冲突): " + str(r2))
	eq(int(SaveFile.read_json(_game.path_join("save/save2.json"))["gold"]), 22)
	_done()


func test_not_relocatable_platform_tidies_inside_user_dir():
	_setup()
	UserPaths.exe_override = ""   # macOS / 手机 / 源码运行
	_legacy()
	eq(UserPaths.mode(), "user")
	check(not UserPaths.needs_prompt, "不弹")
	var n := UserDataMigrate.run()
	check(n >= 5, "静默整理 %d 个" % n)
	eq(int(SaveFile.read_json(_user.path_join("save/save1.json"))["gold"]), 100)
	check(FileAccess.file_exists(_user.path_join("replay/sub/stage_01_20261101_100000.json")))
	check(not FileAccess.file_exists(_user.path_join("save1.json")), "旧档复制校验后删掉")
	eq(UserDataMigrate.run(), 0, "幂等")
	_done()


func test_panel_entries():
	_setup()
	UserPaths.mode()
	var e := SaveLocationPanel.entries(true)
	check(e.has("game") and e.has("pick") and e.has("keep"), str(e))
	eq(SaveLocationPanel.blocked("game"), "savelocation.game.already", "已经在游戏文件夹: 灰掉并说明")
	UserPaths.exe_override = ""
	UserPaths._mode = ""
	check(not SaveLocationPanel.entries(false).has("game"), "不能搬的平台不列")
	_done()


func test_dirs_never_relative():
	_setup()
	UserPaths.exe_override = ""   # 源码运行: 没有程序目录
	eq(UserPaths.dirs_for("game")["replay"], _user.path_join("replay"), "game 没有程序目录时按 user 算")
	eq(UserPaths.dirs_for("custom", "")["save"], _user.path_join("save"), "custom 没给目录时按 user 算")
	_done()


## 0.9.8 手机存不了档也读不到旧档: GameSaves.base_dir 在静态初始化里取 UserPaths.save_dir(), 那时 UserPaths.user_root 还是空串, 得到相对路径 "save"
func test_save_dir_absolute_even_before_user_paths_initialized():
	UserPaths.reset()
	check(GameSaves.base_dir.begins_with("user://") or GameSaves.base_dir.is_absolute_path(), "游戏里的存档目录不是相对路径: " + GameSaves.base_dir)
	UserPaths.user_root = ""   # 模拟别的类静态初始化时 UserPaths 的静态变量还没初始化
	eq(UserPaths.dirs_for("user")["save"], "user://save", "user_root 空时按 user:// 算")
	eq(UserPaths.dirs_for("legacy")["save"], "user://", "旧位置同理")
	UserPaths.reset()
	var old := GameSaves.base_dir
	GameSaves.base_dir = ""
	eq(GameSaves.base_dir, UserPaths.save_dir(), "设空串回到 UserPaths.save_dir()")
	GameSaves.base_dir = old

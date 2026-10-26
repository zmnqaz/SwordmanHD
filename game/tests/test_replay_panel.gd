# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 录像列表子面板 (engine/ui/replay_panel.gd): 文件名解析、倒序、空/坏文件、倍速、选定

const Router = preload("res://engine/input/input_router.gd")
const DIR := "user://replay_panel_test"


func _clean() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.make_dir_recursive_absolute(DIR)


func _put(name: String, text: String) -> String:
	var p := DIR.path_join(name)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return p


func _good() -> String:
	return JSON.stringify({"version": PlayLog.VERSION, "kind": "play", "meta": {}, "duration": 125.0, "seeds": [], "checkpoints": [], "events": [{"t": 1.0, "k": UiAction.UP}, {"t": 2.0, "k": UiAction.DOWN}]})


func _panel() -> ReplayPanel:
	var p := ReplayPanel.new()
	p.gc = GameContext.new()
	p.router = Router.new()
	return p


func _free(p: ReplayPanel) -> void:
	p.router.free()
	p.free()


func test_label_of_parses_file_names() -> void:
	UiStrings.reload()
	var a := ReplayPanel.label_of("play_20261012_103005.json")
	eq(a[0], UiStrings.t("replay.kind.play"))
	eq(a[1], "2026-10-12 10:30")
	check(a[0] != "replay.kind.play", "文案表里有这个键")
	var b := ReplayPanel.label_of("stage_03_20261011_235959.json")
	eq(b[0], UiStrings.t("replay.kind.stage") % 3)
	eq(b[1], "2026-10-11 23:59")
	var c := ReplayPanel.label_of("my_run.json")
	eq(c, ["my_run.json", ""], "不认识的名字原样显示")


func test_list_files_newest_first_and_only_json() -> void:
	_clean()
	_put("play_20261010_100000.json", _good())
	_put("play_20261012_100000.json", _good())
	_put("stage_01_20261011_100000.json", _good())
	_put("notes.txt", "x")
	var l := ReplayPanel.list_files(DIR)
	eq(l.size(), 3, "只列 .json")
	eq(l[0], "stage_01_20261011_100000.json", "按文件名倒序: stage_ 排在 play_ 前, 同类新的在前")
	eq(l[1], "play_20261012_100000.json")
	eq(l[2], "play_20261010_100000.json")


func test_empty_dir_has_only_two_buttons() -> void:
	_clean()
	var p := _panel()
	p.load_files(DIR)
	eq(p.total(), 2, "没有录像: 只有「速度」「返回」两个按钮条目")
	_free(p)


func test_entries_and_info_text() -> void:
	_clean()
	_put("play_20261012_100000.json", _good())
	var p := _panel()
	p.load_files(DIR)
	eq(p.total(), 3)
	eq(p.info_text(0), UiStrings.t("replay.info") % ["2:05", 2, UiStrings.t("replay.start.full")], "时长 mm:ss + 操作数 + 起点 (整场从标题开始)")
	_free(p)


func test_bad_file_cannot_be_started() -> void:
	_clean()
	_put("play_20261012_100000.json", "not json")
	var p := _panel()
	p.load_files(DIR)
	eq(p.info_text(0), UiStrings.t("replay.bad"))
	var closed := [0]
	p.closed.connect(func(_k): closed[0] += 1)
	p.ui_action(UiAction.of(UiAction.CONFIRM, "key"))
	eq(closed[0], 0, "坏文件确认无效, 面板不关")
	eq(p.chosen_path, "")
	_free(p)


func test_speed_keys_and_confirm_choose() -> void:
	_clean()
	var path := _put("play_20261012_100000.json", _good())
	var p := _panel()
	p.load_files(DIR)
	eq(p._speed, 1.0, "缺省 1x")
	p.ui_action(UiAction.of(UiAction.RIGHT, "key"))
	eq(p._speed, 2.0)
	p.ui_action(UiAction.of(UiAction.LEFT, "key"))
	p.ui_action(UiAction.of(UiAction.LEFT, "key"))
	p.ui_action(UiAction.of(UiAction.LEFT, "key"))
	eq(p._speed, 0.5, "到头停住")
	p.ui_action(UiAction.of(UiAction.RIGHT, "key"))   # 1x
	p.ui_action(UiAction.of(UiAction.RIGHT, "key"))   # 2x
	var got := []
	p.closed.connect(func(k): got.append(k))
	p.ui_action(UiAction.of(UiAction.CONFIRM, "key"))   # 选中第 0 个录像
	eq(got, [true], "选定: closed(true)")
	eq(p.chosen_path, path)
	eq(p.chosen_speed, 2.0)
	_free(p)


func test_cancel_and_done_button_do_not_choose() -> void:
	_clean()
	_put("play_20261012_100000.json", _good())
	var p := _panel()
	p.load_files(DIR)
	var got := []
	p.closed.connect(func(k): got.append(k))
	p.ui_action(UiAction.of(UiAction.CANCEL, "key"))
	eq(got, [false])
	p._sel = p._n + 1   # 「返回」按钮
	p.ui_action(UiAction.of(UiAction.CONFIRM, "key"))
	eq(got, [false, false])
	eq(p.chosen_path, "")
	_free(p)


func test_speed_button_cycles_and_wraps() -> void:
	_clean()
	var p := _panel()
	p.load_files(DIR)
	p._sel = p._n   # 「速度」按钮
	for i in 4:
		p.ui_action(UiAction.of(UiAction.CONFIRM, "key"))
	eq(p._speed, 16.0, "1x 起确认 4 次到 16x")
	p.ui_action(UiAction.of(UiAction.CONFIRM, "key"))
	eq(p._speed, 0.5, "到头后循环回最低档")
	_free(p)


func test_info_tells_where_the_recording_starts() -> void:
	eq(ReplayPanel._start_text({"events": []}), UiStrings.t("replay.start.full"), "没有起点存档 = 整场从标题开始")
	eq(ReplayPanel._start_text({"base": {"game": {}}, "base_kind": "slot"}), UiStrings.t("replay.start.slot"), "读了没有历史的存档位")
	eq(ReplayPanel._start_text({"base": {"game": {}}, "base_kind": "battle"}), UiStrings.t("replay.start.battle"), "读了没有历史的战阵存录")
	eq(ReplayPanel._start_text({"kind": "stage", "base": {"a": 1}, "base_kind": "stage_start"}), UiStrings.t("replay.start.stage"), "单幕录像从开战前开始")

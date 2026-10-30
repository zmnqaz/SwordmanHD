# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 画质诊断页 (engine/ui/diag_panel.gd): 文字内容 (含生成器失败的醒目提示)、点按 / 确认 / 取消返回 (刚打开有防误触)、写 user://diag.txt。

const Router = preload("res://engine/input/input_router.gd")
const TEST_OUT := "user://test_diag_panel.txt"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _info(failed: bool) -> Dictionary:
	return {"hq": "gen", "hq_scale": 6, "auto_scale": 6, "hq_codec": "astc", "hq_compressed": 0, "hq_failed": failed, "hq_fail_reason": "readback timeout",
		"hq_generated": 12, "hq_bad_readbacks": 0, "hq_cache": false, "hq_cache_hits": 0, "hq_cache_writes": 0,
		"sharp": {"by_mult": {1: 30, 6: 400}, "low": 7, "total": 430}, "cache": {"mb": 321.5, "budget_mb": 768, "budget_grown": 0, "loads": 450, "evicted": 3, "baker_pending": 2},
		"max_tex": 4096, "gfx": "hd"}


func _joined(ls: Array) -> String:
	return "\n".join(ls)


func test_lines_show_scale_distribution_and_failure():
	var ok := _joined(DiagPanel.lines(_info(false)))
	check("Window" in ok and "Textures" in ok and "VRAM" in ok, "平台 / 贴图 / 显存各行都在")
	check(ok.contains("Game      " + GameVersion.label()) and GameVersion.number().count(".") == 2, "第一行是游戏版本号 (x.y.z)")
	check("1x: 30" in ok and "6x: 400" in ok and "placeholders 7" in ok, "清晰度分布: 1 倍 30 张 / 6 倍 400 张 / 占位 7")
	check("max texture side 4096" in ok, "显示单边贴图上限")
	check(not ("!! FAILED" in ok), "生成器正常: 没有失败提示")
	var bad := _joined(DiagPanel.lines(_info(true)))
	check("!! FAILED readback timeout" in bad, "生成器失败: 醒目提示 + 原因")
	check("p95" in _joined(DiagPanel.lines(_info(false), [10.0, 12.0, 30.0])), "给了帧时间: 显示平均 / p95 / 最差")
	var inf := _info(false)
	inf["slow_loads"] = [{"rel": "Sprite/man001/t5.png", "ms": 212.4}, {"rel": "Face/f1.png", "ms": 40.0}]
	var sl := _joined(DiagPanel.lines(inf))
	check(sl.contains("SlowLoad") and sl.contains("212 ms") and sl.contains("40 ms"), "最慢的贴图载入: 列出名字和耗时")
	check(DiagPanel.lines().size() >= 10, "没有贴图信息 (无头 / 没注入) 也不报错")


## 测试结束复位全局上下文上的诊断数据源
func _reset_gc() -> void:
	GameContext.current().diag_info = Callable()


func _open_panel(failed := false) -> DiagPanel:
	var gc := GameContext.current()
	var info := _info(failed)
	gc.diag_info = func(): return info   # 只捕获局部数据, 不能捕获测试对象: 全局 GameContext 退出时才析构这个 lambda, 捕获了已释放的测试对象会让进程退出时堆损坏崩溃 (CI 退出码 -6)
	var p := DiagPanel.new()
	p.gc = gc
	p.router = Router.new()
	p.out_path = TEST_OUT   # 不写玩家真实的 user://diag.txt
	_tree().root.add_child(p)
	p.open()
	return p


func test_close_by_confirm_cancel_and_click_with_guard():
	var p := _open_panel()
	var closed := []
	p.closed.connect(func(s): closed.append(s))
	check(p._label.text.contains("Textures"), "打开即显示内容")
	p.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
	eq(closed, [], "刚打开的确认不算 (防误触)")
	await _tree().create_timer(DiagPanel.GUARD + 0.05).timeout
	p.ui_action(UiAction.new(UiAction.RIGHT, "key"))
	eq(closed, [], "方向键不关")
	p.ui_action(UiAction.new(UiAction.CONFIRM, "mouse", Vector2(5, 5)))
	eq(closed, [false], "点任意处 (带坐标的确认) = 返回")
	p.ui_action(UiAction.new(UiAction.CANCEL, "key"))
	eq(closed, [false], "只关一次")
	await _tree().process_frame
	await _tree().process_frame
	check(FileAccess.file_exists(TEST_OUT), "关闭时写出诊断文件")
	check(FileAccess.get_file_as_string(TEST_OUT).contains("Window"), "文件里是诊断文字")
	DirAccess.remove_absolute(TEST_OUT)
	_reset_gc()


func test_cancel_closes_too():
	var p := _open_panel()
	var closed := []
	p.closed.connect(func(s): closed.append(s))
	await _tree().create_timer(DiagPanel.GUARD + 0.05).timeout
	p.ui_action(UiAction.new(UiAction.CANCEL, "key"))
	eq(closed, [false], "取消键返回")
	await _tree().process_frame
	await _tree().process_frame
	DirAccess.remove_absolute(TEST_OUT)
	_reset_gc()


func test_settings_has_diag_row_opening_diag_panel():
	check("diag" in SettingsSchema.shown_rows("display").map(func(r): return r["key"]), "「显示」二级菜单里有「画质诊断」行")
	check(UiStrings.t("settings.diag.label") != "settings.diag.label", "行名有文案")
	check(UiStrings.t("diag.title") != "diag.title" and UiStrings.t("diag.hint") != "diag.hint", "标题 / 提示有文案")

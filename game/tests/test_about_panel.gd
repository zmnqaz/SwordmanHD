# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 「关于」页 (engine/ui/about_panel.gd) 与版本号 (engine/core/game_version.gd): 版本号 / 主页地址取自 project.godot, 设定面板主菜单有「关于」行,
## 确认 / 点地址 = 打开主页, 取消 / 点别处 = 返回 (刚打开有防误触)。

const Router = preload("res://engine/input/input_router.gd")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _open_panel(opened: Array) -> AboutPanel:
	var p := AboutPanel.new()
	p.gc = GameContext.current()
	p.router = Router.new()
	p.opener = func(url): opened.append(url)   # 只捕获局部数组, 不捕获测试对象 (见 test_diag_panel 的说明)
	_tree().root.add_child(p)
	p.open()
	return p


func test_version_and_homepage_come_from_project_settings():
	check(GameVersion.number().split(".").size() == 3, "版本号是 x.y.z: %s" % GameVersion.number())
	eq(GameVersion.label(), "v" + GameVersion.number())
	check(GameVersion.homepage().begins_with("https://github.com/"), "主页是 GitHub 地址: %s" % GameVersion.homepage())


func test_lines_show_version_and_link():
	var t := "\n".join(AboutPanel.lines())
	check(t.contains(GameVersion.label()) and t.contains(GameVersion.homepage()), "正文里有版本号和主页地址")
	for k in ["about.title", "about.name", "about.version", "about.home", "about.license", "about.hint", "settings.about.label"]:
		check(UiStrings.t(k) != k, "%s 有文案" % k)


func test_settings_main_menu_has_about_row():
	var keys := SettingsSchema.shown_rows().map(func(r): return r["key"])
	check(keys.has("about"), "设定主菜单有「关于」")
	eq(keys[-1], "about", "放在最后一行")
	eq(SettingsSchema.row("about")["kind"], "action")


func test_confirm_opens_homepage_and_cancel_closes():
	var opened := []
	var p := _open_panel(opened)
	var closed := []
	p.closed.connect(func(s): closed.append(s))
	p.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
	eq(opened, [], "刚打开的确认不算 (防误触)")
	await _tree().create_timer(AboutPanel.GUARD + 0.05).timeout
	p.ui_action(UiAction.new(UiAction.RIGHT, "key"))
	eq([opened, closed], [[], []], "方向键无作用")
	p.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
	eq(opened, [GameVersion.homepage()], "键盘确认 = 打开主页")
	eq(closed, [], "打开主页不关页面")
	p.ui_action(UiAction.new(UiAction.CANCEL, "key"))
	eq(closed, [false], "取消 = 返回")
	p.ui_action(UiAction.new(UiAction.CANCEL, "key"))
	eq(closed, [false], "只关一次")
	await _tree().process_frame
	await _tree().process_frame


func test_tap_on_link_opens_and_tap_elsewhere_closes():
	var opened := []
	var p := _open_panel(opened)
	var closed := []
	p.closed.connect(func(s): closed.append(s))
	await _tree().create_timer(AboutPanel.GUARD + 0.05).timeout
	await _tree().process_frame
	var r := p.link_rect()
	check(r.size.x > 0 and r.size.y > 0, "地址行排好版有矩形")
	p.ui_action(UiAction.new(UiAction.CONFIRM, "mouse", r.get_center()))
	eq(opened, [GameVersion.homepage()], "点地址 = 打开主页")
	eq(closed, [])
	p.ui_action(UiAction.new(UiAction.CONFIRM, "mouse", Vector2(2, 2)))
	eq(closed, [false], "点别处 = 返回")
	await _tree().process_frame
	await _tree().process_frame

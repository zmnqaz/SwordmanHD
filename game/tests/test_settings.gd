# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 设定项 (engine/settings/settings_schema.gd): 缺省、校验、旧设定文件兼容、步进; 布局表里 F10 面板元素齐全

func test_defaults_cover_every_row():
	var d := SettingsSchema.defaults()
	var valued := SettingsSchema.ROWS.filter(func(r): return r["kind"] != "action" and r["kind"] != "live")
	eq(d.size(), valued.size() + 2, "每个有值的行都有缺省, 另有 pad_map / key_map (手柄、键盘覆盖项, 不是行)")
	eq(d["music"], 10, "音乐缺省 10 (原版音量)")
	eq(d["gfx"], "hd", "画质缺省高清")
	eq(d["fullscreen"], 0, "缺省窗口")
	for r in SettingsSchema.ROWS:
		check(SettingsSchema.row_desc(r) != "" and SettingsSchema.label_of(r) != "", "%s 有说明" % r["key"])


func test_old_settings_file_is_compatible():
	# 旧版只有四个键 (值可能来自 JSON, 整数读回为 float)
	var s := SettingsSchema.sanitize({"music": 3.0, "sfx": 0, "gfx": "orig", "font": "pixel"})
	eq(s["music"], 3, "旧音量保留")
	eq(s["gfx"], "hd", "画质固定高清: 旧设定文件里的原版画质作废")
	eq(s["font"], "kai", "旧字体值 (pixel / pixel_smooth) 不在清单里, 回退缺省字库字体")
	eq(SettingsSchema.sanitize({"font": "pixel_smooth"})["font"], "kai")
	eq(s["win"], 0, "窗口大小缺省 0 = 自动")
	eq(s["aspect"], "auto", "画面比例缺省自适应")
	eq(s["tex"], "auto", "新键取缺省")


func test_sanitize_rejects_bad_values():
	var s := SettingsSchema.sanitize({"music": 99, "sfx": "x", "gfx": "ultra", "win": 9, "fullscreen": "1", "tex": 4})
	eq(s["music"], 10, "音量夹到 10")
	eq(s["sfx"], 10, "类型不对取缺省")
	eq(s["gfx"], "hd", "未知选项取缺省")
	eq(s["win"], 0, "越界档取缺省 (自动)")
	eq(s["fullscreen"], 0, "字符串不当数值")
	eq(s["tex"], "auto", "数值不当字符串选项")


## 设定面板里去掉的项 (画质/贴图精度/画面比例/地图飘字): 数据仍在 (命令行/QA 可写 Game.settings), 但设定文件里存的旧值一律作废取缺省
func test_hidden_rows_ignore_saved_values():
	var s := SettingsSchema.sanitize({"tex": "6", "aspect": "keep", "gfx": "orig", "music": 3})
	eq([s["tex"], s["aspect"], s["gfx"]], ["auto", "auto", "hd"], "旧设定文件里隐藏项的值作废")
	eq(s["music"], 3, "可见项照常读")
	var keys := []
	for r in SettingsSchema.shown_rows():
		keys.append(r["key"])
	for k in ["tex", "aspect", "gfx"]:
		check(not keys.has(k), "面板不显示 %s" % k)
	keys = keys.filter(func(k): return k != "face_style")   # 头像风格只有装了港漫 mod (mod/face_hk.pck) 才列, 带资源包跑测试时会出现
	eq(keys, ["lang", "font", "sound", "display", "controls", "show_hidden", "coord", "bag_sort", "replay"], "主菜单项与顺序 (内容包带攻略时, 最后再多一行游戏攻略): 语言 字体 [头像风格] 声音 图像显示 控制器设置 隐藏宝箱设置 战场坐标显示 整理行囊 录像回放 游戏攻略; 没有画质项")
	eq(SettingsSchema.shown_rows("sound").map(func(r): return r["key"]), ["music", "sfx"], "「声音」二级菜单: 音乐 / 音效")
	eq(SettingsSchema.shown_rows("display").map(func(r): return r["key"]), ["fullscreen", "win", "hq", "diag"], "「显示」二级菜单: 窗口模式 / 分辨率 / 贴图精度 / 画质诊断")
	eq(SettingsSchema.shown_rows("controls").map(func(r): return r["key"]), ["key_edit", "pad_preset", "pad_edit"], "「控制器」二级菜单: 键盘按键 / 手柄预设 / 手柄按键")


## 窗口大小自动: 屏幕可用区域放得下的最大档 (16:10, 留标题栏), 放不下用最小档
func test_resolution_row_default_auto_and_manual_choices():
	eq(SettingsSchema.row("win")["def"], 0, "分辨率缺省自动")
	eq(SettingsSchema.sanitize({"win": 1600.0})["win"], 1600, "手选 1600 保留 (JSON 读回的 1600.0)")
	eq(SettingsSchema.sanitize({"win": 1920})["win"], 1920)
	eq(SettingsSchema.sanitize({"win": 777})["win"], 0, "不在档里取自动")
	eq(SettingsSchema.text_of("win", 0), "自动", "显示文字")
	eq(SettingsSchema.text_of("win", 1920), "1920x1200")
	eq(SettingsSchema.label_of(SettingsSchema.row("win")), "分辨率")


func test_auto_win_picks_largest_fitting_size():
	eq(SettingsSchema.auto_win(Vector2i(3840, 2160)), 1920, "4K: 最大档")
	eq(SettingsSchema.auto_win(Vector2i(1920, 1080)), 1280, "1080p 可用高度放不下 1600x1000 (标题栏), 取 1280x800")
	eq(SettingsSchema.auto_win(Vector2i(2560, 1440)), 1920, "1440p: 放得下 1920x1200")
	eq(SettingsSchema.auto_win(Vector2i(1920, 1200)), 1600, "1920x1200 屏: 1920 宽放不下 (留边框), 取 1600x1000")
	eq(SettingsSchema.auto_win(Vector2i(1366, 768)), 1280, "小屏也不低于最小档")


func test_step_cycles_and_clamps():
	eq(SettingsSchema.step("music", 10, 1), 10, "音量到头停住")
	eq(SettingsSchema.step("music", 0, -1), 0, "音量到底停住")
	eq(SettingsSchema.step("music", 5, 1), 6, "音量 +1")
	eq(SettingsSchema.step("tex", "6", 1), "auto", "选项循环到头")
	eq(SettingsSchema.step("tex", "auto", -1), "6", "选项反向循环")
	eq(SettingsSchema.step("gfx", "hd", 1), "orig", "两项互切")
	eq(SettingsSchema.step("aspect", "auto", 1), "keep", "画面比例两项互切")


func test_win_sizes_are_16_10_and_not_below_min():
	var min_w: int = ScreenLayout.MIN_WINDOW.x
	for o in SettingsSchema.row("win")["options"]:
		if int(o["v"]) == 0:
			continue   # 0 = 自动 (按屏幕挑下面这几档之一, 见 auto_win)
		var sz := SettingsSchema.win_size(int(o["v"]))
		eq(sz.x * 10, sz.y * 16, "%d 是 16:10" % int(o["v"]))
		check(sz.x >= min_w and sz.y >= ScreenLayout.MIN_WINDOW.y, "%d 不小于最小窗口 1280x800" % int(o["v"]))
	eq(SettingsSchema.win_size(1280), Vector2i(1280, 800), "标准档 = 视口大小")
	eq(SettingsSchema.def_of(SettingsSchema.row("win")), 0, "缺省 0 = 自动")


func test_settings_layout_elements():
	for id in ["settings.panel", "settings.title", "settings.hint", "settings.row", "settings.value", "settings.button",
			"settings.desc", "settings.cursor", "settings.arrow", "settings.bar"]:
		check(UiLayout.has(id), "布局表有 " + id)
	eq(UiLayout.validate().size(), 0, "布局表校验无错")
	# 全部行 + 说明放得进面板
	var vis := SettingsPanel.visible_rows()
	var last_y := UiLayout.at("settings.row", vis - 1).y + UiLayout.size_of("settings.row").y
	check(last_y <= UiLayout.at("settings.desc").y, "最后一个可见行不压说明")
	check(SettingsSchema.ROWS.size() + 2 > vis, "项目比版面长: 靠滚动显示 (列表滚动由 SettingsPanel._scroll_to_sel 负责)")
	check(UiLayout.at("settings.desc").y + UiLayout.size_of("settings.desc").y <= UiLayout.size_of("settings.panel").y, "说明在面板内")


func test_window_size_follows_aspect():
	# 窗口大小各档按当前画面比例换算 (--aspect): 单一来源, 设定面板与命令行预览一致
	var sl = ScreenLayout
	var old: float = sl.aspect
	sl.aspect = 0.0
	eq(sl.window_size_for(Vector2i(1920, 1200)), Vector2i(1920, 1200), "无 --aspect 原样")
	sl.aspect = 16.0 / 9.0
	eq(sl.window_size_for(Vector2i(1280, 800)), Vector2i(1424, 800), "16:9 加宽, 高不变 (356x200 逻辑)")
	var s: Vector2i = sl.window_size_for(Vector2i(1920, 1200))
	eq(s.y, 1200, "宽屏高不变")
	eq(s.x % 6, 0, "取整到原版像素整数倍")
	sl.aspect = 4.0 / 3.0
	eq(sl.window_size_for(Vector2i(1280, 800)), Vector2i(1280, 960), "4:3 加高窗口 (自适应下画面仍 320x200, 上下留黑边)")
	sl.aspect = old


func test_window_fit_and_center():
	var sl = ScreenLayout
	eq(sl.fit_size(Vector2i(1920, 1200), Vector2i(3290, 1862)), Vector2i(1920, 1200), "放得下原样")
	var f: Vector2i = sl.fit_size(Vector2i(1920, 1200), Vector2i(1600, 900))
	check(f.x <= 1600 and f.y <= 900, "放不下缩进可用区")
	check(absf(float(f.x) / f.y - 1.6) < 0.01, "缩小保持 16:10")
	eq(sl.center_pos(Vector2i(1920, 1200), Rect2i(134, 64, 3290, 1862)), Vector2i(819, 395), "可用区内居中")
	eq(sl.center_pos(Vector2i(2000, 1300), Rect2i(0, 40, 1000, 700)), Vector2i(0, 40), "放不下贴左上, 标题栏不出屏")


func test_display_mult_from_window():
	# 贴图倍数按窗口像素换算: 与 canvas_items 的缩放系数一致 (keep 留边时取小的一边)
	var sl = ScreenLayout
	eq(sl.display_mult_of(Vector2(1280, 800)), 4.0, "标准窗口 4 倍")
	eq(sl.display_mult_of(Vector2(1920, 1200)), 6.0, "1920x1200 = 6 倍")
	eq(sl.display_mult_of(Vector2(960, 600)), 3.0, "小窗 3 倍")
	eq(sl.display_mult_of(Vector2(3424, 1926)), 4.0 * 1926.0 / 800.0, "全屏 16:9 以高为准")


func test_font_row_from_manifest():
	var r := SettingsSchema.row("font")
	check(not r.is_empty(), "有字体项")
	var opts := SettingsSchema.options_of(r)
	check(opts.size() >= 3, "清单里至少 3 个字体")
	eq(SettingsSchema.defaults()["font"], "kai", "缺省是霞鹜文楷")
	eq(SettingsSchema.sanitize({"font": "kai"})["font"], "kai", "合法字体保留")
	eq(SettingsSchema.sanitize({"font": "pixel"})["font"], "kai", "旧点阵值回退缺省")
	eq(SettingsSchema.sanitize({"font": 3})["font"], "kai", "类型不对回退缺省")
	eq(SettingsSchema.sanitize({})["font"], "kai", "缺失取缺省")
	eq(SettingsSchema.step("font", "sans", 1), opts[1]["v"], "字体选项循环")
	eq(SettingsSchema.step("font", opts[opts.size() - 1]["v"], 1), "sans", "循环回头")
	check(SettingsSchema.desc_of("font", "kai").length() > SettingsSchema.row_desc(SettingsSchema.row("font")).length(), "说明带当前字体的一句话")


func test_aspect_mode_widens_only_wide_windows():
	var sl = ScreenLayout
	check(sl.widens(Vector2i(1600, 900), "auto"), "16:9 自适应加宽")
	check(sl.widens(Vector2i(2560, 1080), "auto"), "21:9 自适应加宽")
	check(not sl.widens(Vector2i(1920, 1200), "auto"), "16:10 不加宽")
	check(not sl.widens(Vector2i(1280, 960), "auto"), "4:3 退化为留上下黑边")
	check(not sl.widens(Vector2i(1600, 900), "keep"), "原版 16:10 模式不加宽")


func test_min_window_clamps_old_small_sizes():
	var sl = ScreenLayout
	eq(sl.MIN_WINDOW, Vector2i(1280, 800), "最小窗口 1280x800")
	eq(sl.window_size_for(Vector2i(960, 600)), Vector2i(1280, 800), "旧 960x600 回退 1280x800")


func test_new_rows_defaults_and_validation():
	var d := SettingsSchema.defaults()
	eq(d["show_hidden"], 0, "隐藏宝箱缺省关 (与原版一致)")
	eq(d["coord"], 0, "格子坐标缺省关")
	eq(d["pad_preset"], "std", "手柄预设缺省标准")
	eq(d["pad_map"], {}, "手柄覆盖项缺省为空")
	var s := SettingsSchema.sanitize({"show_hidden": 1.0, "coord": 1.0, "pad_preset": "swap", "pad_map": {"info": 5.0}})
	eq(s["show_hidden"], 1, "JSON 读回的 1.0")
	eq(s["coord"], 1, "JSON 读回的 1.0")
	eq(s["pad_preset"], "swap")
	eq(s["pad_map"], {"info": 5})
	var bad := SettingsSchema.sanitize({"show_hidden": 7, "coord": "x", "pad_preset": "???", "pad_map": 3})
	eq(bad["show_hidden"], 0, "越界取缺省")
	eq(bad["coord"], 0, "未知取缺省")
	eq(bad["pad_preset"], "std", "未知预设取缺省")
	eq(bad["pad_map"], {}, "pad_map 不是字典取空")
	var old := SettingsSchema.sanitize({"music": 3, "gfx": "orig"})
	eq([old["show_hidden"], old["coord"], old["pad_preset"]], [0, 0, "std"], "旧设定文件兼容 (旧版的 grid 键直接忽略)")
	check(not SettingsSchema.sanitize({"grid": "lines"}).has("grid"), "已取消的 grid 设定不再保留")


func test_action_row_has_no_value():
	var r := SettingsSchema.row("pad_edit")
	eq(r["kind"], "action", "手柄按键设置是动作行")
	check(not SettingsSchema.defaults().has("pad_edit"), "动作行不进设定值")
	check(SettingsSchema.label_of(r) != "" and SettingsSchema.row_desc(r) != "", "动作行有名称和说明")
	eq(SettingsSchema.step("show_hidden", 0, 1), 1)
	eq(SettingsSchema.step("coord", 0, 1), 1)
	eq(SettingsSchema.step("coord", 1, 1), 0, "两档循环")
	eq(SettingsSchema.step("pad_preset", "std", 1), "swap")


func test_panel_list_scrolls_with_selection():
	var p := SettingsPanel.new()
	var vis: int = p._vis
	var total: int = p.total()
	check(total > vis, "条目比版面行数多")
	p._sel = 0
	p._scroll_to_sel()
	eq(p._top, 0, "选第一项: 不滚")
	eq(p.slot_of(0), 0)
	p._sel = vis - 1
	p._scroll_to_sel()
	eq(p._top, 0, "选最后一个可见行: 不滚")
	p._sel = vis
	p._scroll_to_sel()
	eq(p._top, 1, "选到下一行: 列表上滚一行")
	eq(p.slot_of(vis), vis - 1, "选中项落在最后一行")
	eq(p.slot_of(0), -1, "滚出去的条目不可见")
	p._sel = total - 1
	p._scroll_to_sel()
	eq(p._top, total - vis, "选最后一项: 滚到底")
	p._sel = 0
	p._scroll_to_sel()
	eq(p._top, 0, "回到第一项: 滚回顶 (到头循环)")
	p.free()


# ---------------------------------------------------------------- 两层与写入入口 (SettingsSchema.set_value 等)

class Flow:
	extends SceneFlow
	var applied := 0
	var saved := 0
	func apply_settings() -> void:
		applied += 1
	func save_settings() -> void:
		saved += 1


func _gc(saved := {}, overrides := {}) -> GameContext:
	var gc := GameContext.new()
	gc.flow = Flow.new()
	SettingsSchema.load_layers(gc, saved, overrides)
	return gc


## 命令行覆盖值只进覆盖层: 读到的是合并值, 持久层 (写盘的内容) 不含它; 改别的项存盘也不会把它带进去
func test_override_layer_is_not_persisted():
	var gc := _gc({"music": 3, "lang": "hans"}, {"lang": "hant", "coord": 1, "gfx": "orig"})
	eq([gc.settings["lang"], gc.settings["coord"], gc.settings["gfx"]], ["hant", 1, "orig"], "生效值带覆盖 (隐藏项 gfx 也可临时改)")
	eq([gc.settings_saved["lang"], gc.settings_saved["coord"], gc.settings_saved["gfx"]], ["hans", 0, "hd"], "持久层不含覆盖值")
	check(SettingsSchema.set_value(gc, "music", 5), "改音乐")
	eq(gc.settings_saved["music"], 5, "改的项进持久层")
	eq(gc.settings_saved["lang"], "hans", "存盘内容仍不含命令行语言")
	eq(gc.settings["lang"], "hant", "本次运行仍按命令行语言")
	eq([(gc.flow as Flow).applied, (gc.flow as Flow).saved], [1, 1], "写入入口: 生效一次、存盘一次")
	SettingsSchema.set_value(gc, "lang", "hant")
	eq(gc.settings_saved["lang"], "hant", "用户亲手改被覆盖的项: 以用户为准写进持久层")
	check(not gc.settings_override.has("lang"), "该项覆盖去掉")


func test_set_override_applies_without_saving():
	var gc := _gc()
	check(SettingsSchema.set_override(gc, "music", 4), "临时改音乐")
	eq([gc.settings["music"], gc.settings_saved["music"]], [4, 10], "生效值变, 持久层不变")
	eq([(gc.flow as Flow).applied, (gc.flow as Flow).saved], [1, 0], "生效但不存盘")
	check(not SettingsSchema.set_override(gc, "music", "loud"), "非法值拒绝")
	eq(gc.settings["music"], 4)


## 覆盖值与写入值同设定文件一样校验: 非法的丢掉 (取持久层的值), 音量夹到 0~10
func test_invalid_values_are_sanitized():
	var gc := _gc({"music": 3}, {"lang": "xx", "font": "nope", "coord": 7, "show_hidden": 1, "aspect": 3, "music": 99.0})
	eq([gc.settings["lang"], gc.settings["font"], gc.settings["coord"], gc.settings["aspect"]], ["hans", "kai", 0, "auto"], "非法覆盖值忽略")
	eq(gc.settings["show_hidden"], 1, "合法覆盖值保留")
	eq(gc.settings["music"], 10, "音量覆盖夹到 10")
	check(not gc.settings_override.has("lang") and not gc.settings_override.has("coord"), "非法值不进覆盖层")
	var f: Flow = gc.flow
	check(not SettingsSchema.set_value(gc, "win", 777), "不在档里的分辨率拒绝")
	check(not SettingsSchema.set_value(gc, "nope", 1), "未知键拒绝")
	check(not SettingsSchema.set_value(gc, "pad_edit", 1), "动作行没有值")
	eq([gc.settings["win"], f.applied, f.saved], [0, 0, 0], "拒绝时不改不生效不存盘")
	check(SettingsSchema.set_value(gc, "win", 1600.0), "JSON 式 1600.0 合法")
	eq(gc.settings["win"], 1600)
	SettingsSchema.set_value(gc, "pad_map", {"info": 5.0, "bogus": 3})
	eq(gc.settings["pad_map"], {"info": 5}, "pad_map 按预设校验")


func test_preset_change_clears_pad_map_and_reset_all_clears_layers():
	var gc := _gc({"pad_map": {"info": 5}}, {"lang": "hant"})
	SettingsSchema.set_value(gc, "pad_preset", "std")
	eq(gc.settings["pad_map"], {"info": 5}, "预设没变: 逐键自定义保留")
	SettingsSchema.set_value(gc, "pad_preset", "swap")
	eq([gc.settings["pad_map"], gc.settings_saved["pad_map"]], [{}, {}], "换预设清掉逐键自定义")
	SettingsSchema.set_value(gc, "music", 2)
	SettingsSchema.reset_all(gc)
	eq(gc.settings, SettingsSchema.defaults(), "还原预设: 生效值全缺省")
	eq(gc.settings_saved, SettingsSchema.defaults(), "持久层全缺省")
	eq(gc.settings_override, {}, "命令行覆盖一并清掉")


## 战场系统菜单「声音」开关: 关 = 0, 开 = 恢复关之前的值, 没有就取设定缺省 (不再写死 8)
func test_volume_toggle_restores_previous_value():
	var gc := _gc({"music": 6})
	SettingsSchema.toggle_volume(gc, "music")
	eq([gc.settings["music"], gc.settings_saved["music"]], [0, 0], "关 = 0 并存盘")
	SettingsSchema.toggle_volume(gc, "music")
	eq(gc.settings["music"], 6, "开 = 恢复关之前的 6")
	eq((gc.flow as Flow).saved, 2, "每次切换都存盘")
	var gc2 := _gc({"sfx": 0})
	SettingsSchema.toggle_volume(gc2, "sfx")
	eq(gc2.settings["sfx"], SettingsSchema.row("sfx")["def"], "从没开过: 取设定缺省")
	eq(gc2.settings["sfx"], 10)


## 守卫: 引擎/组装层不得绕过写入入口直接改设定字典 (gc.settings[k] = v / Game.settings[k] = v)
func test_no_direct_settings_writes():
	var re := RegEx.create_from_string("settings(_saved|_override)?\\s*\\[[^\\]]*\\]\\s*=[^=]")
	var files := []
	for dir in ["res://engine", "res://scripts"]:
		_scan_gd(dir, files)
	var bad := []
	for f in files:
		if f == "res://engine/settings/settings_schema.gd":
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(f).split("\n"):
			n += 1
			if re.search(line.split("#")[0]) != null:
				bad.append("%s:%d" % [f, n])
	eq(bad, [], "设定写入走 SettingsSchema.set_value / set_override / reset_all")


func _scan_gd(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan_gd(dir.path_join(d), out)


## 二级菜单「控制器」的「还原预设」只复位本组 (手柄预设 + 逐键覆盖 + 键盘覆盖), 不动音量 / 语言等别的设定
func test_reset_group_controls_only_touches_controls():
	var gc := _gc({"pad_preset": "swap", "pad_map": {"info": 5}, "key_map": {"menu": 81}, "music": 2, "coord": 1})
	SettingsSchema.reset_group(gc, "controls")
	eq([gc.settings["pad_preset"], gc.settings["pad_map"], gc.settings["key_map"]], ["std", {}, {}], "手柄预设 / 逐键覆盖 / 键盘覆盖恢复缺省")
	eq([gc.settings["music"], gc.settings["coord"]], [2, 1], "别的设定不动")
	eq([gc.settings_saved["pad_preset"], gc.settings_saved["music"]], ["std", 2], "持久层同步")
	check(gc.flow.saved > 0, "存盘了")


## 「控制器」入口: 主菜单一行, 确认后打开同一个面板类的二级菜单 (只列键盘 / 手柄行, 标题 = 控制器, 自己的 _n)
func test_controls_row_opens_submenu_with_its_own_rows():
	var gc := _gc()
	var sp := SettingsPanel.new()
	sp.gc = gc
	var sub := SettingsPanel.new()
	sub.gc = gc
	sub._group = "controls"
	eq(sub._srows().map(func(r): return r["key"]), ["key_edit", "pad_preset", "pad_edit"], "二级菜单的行")
	check(sp._srows().map(func(r): return r["key"]).has("controls"), "主菜单有「控制器」入口行")
	check(not sp._srows().map(func(r): return r["key"]).has("pad_preset"), "手柄预设不在主菜单")
	eq(UiStrings.t("settings.controls.title"), "控制器设置", "二级菜单标题")
	sp.free()
	sub.free()


## 端到端: 主菜单确认「控制器」→ 打开二级菜单 (兄弟节点, 主菜单先藏), 取消回到主菜单; 二级菜单里的「还原预设」只复位本组
func test_controls_submenu_opens_and_returns():
	var Router = load("res://engine/input/input_router.gd")
	var tree := Engine.get_main_loop() as SceneTree
	var gc := _gc({"pad_preset": "swap", "music": 4})
	var sp := SettingsPanel.new()
	sp.gc = gc
	sp.router = Router.new()
	tree.root.add_child(sp)
	sp.open()
	var idx: int = sp._srows().map(func(r): return r["key"]).find("controls")
	check(idx >= 0, "主菜单里有「控制器」")
	sp._sel = idx
	sp.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
	var sub: SettingsPanel = null
	for c in tree.root.get_children():
		if c is SettingsPanel and c != sp and c._group == "controls":
			sub = c
	check(sub != null, "二级菜单作为兄弟节点打开")
	if sub != null:
		eq(sub._n, SettingsSchema.shown_rows("controls").size(), "二级菜单只有自己的行")
		check(not sp.visible and sub.visible, "主菜单先藏起来, 二级菜单显示")
		sub._sel = sub._n   # 「还原预设」
		sub.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
		eq([gc.settings["pad_preset"], gc.settings["music"]], ["std", 4], "二级菜单的还原预设: 手柄预设复位, 音量不动")
		sub.ui_action(UiAction.new(UiAction.CANCEL, "key"))
		await tree.process_frame
		await tree.process_frame
		check(sp.visible, "关掉二级菜单后回到主菜单")
		check(not is_instance_valid(sub) or sub.is_queued_for_deletion(), "二级菜单已释放")
	sp.closed.emit(true)
	await tree.process_frame
	await tree.process_frame


## 端到端: 主菜单 → 「显示」二级菜单 → 画质诊断 (三层), 每层关掉都回到上一层; 二级菜单里的行是窗口模式 / 分辨率 / 画质诊断
func test_display_submenu_reaches_diag_and_returns():
	var Router = load("res://engine/input/input_router.gd")
	var tree := Engine.get_main_loop() as SceneTree
	var gc := _gc({"win": 1600})
	gc.diag_info = Callable()
	var sp := SettingsPanel.new()
	sp.gc = gc
	sp.router = Router.new()
	tree.root.add_child(sp)
	sp.open()
	sp._sel = sp._srows().map(func(r): return r["key"]).find("display")
	sp.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
	var sub: SettingsPanel = null
	for c in tree.root.get_children():
		if c is SettingsPanel and c != sp and c._group == "display":
			sub = c
	check(sub != null, "「显示」二级菜单打开")
	if sub != null:
		eq(sub._srows().map(func(r): return r["key"]), ["fullscreen", "win", "hq", "diag"], "二级菜单的行")
		eq(UiStrings.t("settings.fullscreen.label"), "窗口模式", "里面那一行不再和菜单同名叫「显示」")
		sub._sel = sub._srows().map(func(r): return r["key"]).find("diag")
		sub.ui_action(UiAction.new(UiAction.CONFIRM, "key"))
		var dp: DiagPanel = null
		for c in tree.root.get_children():
			if c is DiagPanel:
				dp = c
		check(dp != null and not sub.visible, "画质诊断打开, 二级菜单先藏")
		if dp != null:
			await tree.create_timer(DiagPanel.GUARD + 0.05).timeout
			dp.ui_action(UiAction.new(UiAction.CANCEL, "key"))
			await tree.process_frame
			await tree.process_frame
			check(sub.visible, "关掉诊断回到「显示」二级菜单")
		sub.ui_action(UiAction.new(UiAction.CANCEL, "key"))
		await tree.process_frame
		await tree.process_frame
		check(sp.visible, "关掉二级菜单回到主菜单")
	sp.closed.emit(true)
	await tree.process_frame
	await tree.process_frame


## 贴图精度 (hq): 缺省自动, 选项 自动 / 6 / 4 / 3 步进循环, 非法值取缺省; 启动时 Assets 直接读设定文件定生成倍数 (非法 / 缺文件 = 自动)
func test_texture_quality_row_and_saved_scale():
	eq(SettingsSchema.defaults()["hq"], 0, "缺省自动")
	eq([SettingsSchema.step("hq", 0, 1), SettingsSchema.step("hq", 6, 1), SettingsSchema.step("hq", 4, 1), SettingsSchema.step("hq", 3, 1)], [6, 4, 3, 0], "自动 → 高 → 中 → 低 → 自动")
	eq(SettingsSchema.sanitize({"hq": 5})["hq"], 0, "非法倍数取缺省")
	eq(SettingsSchema.sanitize({"hq": 4.0})["hq"], 4, "JSON 式 4.0 合法")
	var p := "user://test_hq_settings.json"
	for case in [[{"hq": 6}, 6], [{"hq": 3.0}, 3], [{"hq": 5}, 0], [{"hq": "6"}, 0], [{"music": 3}, 0]]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(JSON.stringify(case[0]))
		f.close()
		eq(Assets.saved_hq_scale(p), case[1], "设定文件 %s -> %d" % [JSON.stringify(case[0]), case[1]])
	DirAccess.remove_absolute(p)
	eq(Assets.saved_hq_scale("user://no_such_settings_file.json"), 0, "没有设定文件 = 自动")


## 「声音」二级菜单的「还原预设」只复位音乐 / 音效 (缺省 10), 不动别的
func test_reset_group_sound_only_touches_volumes():
	var gc := _gc({"music": 2, "sfx": 3, "coord": 1})
	SettingsSchema.reset_group(gc, "sound")
	eq([gc.settings["music"], gc.settings["sfx"], gc.settings["coord"]], [10, 10, 1], "音量复位, 别的设定不动")

# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 界面布局统一: 布局表叠加、统一文字排版 (字格 + 字节宽 + 基线)、图标菜单排版与定位、帧外框按原版 1 倍
const REQUIRES_TEST := {
	"test_levelup_window": ["original"]
}  # 个别方法的依赖 (同上)


func _db(ids: Array):
	var db = ContentDB.new()
	db.load_packs(ids)
	return db


func test_merge_rules():
	var a := {"elements": {"x": {"pos": [1, 2], "text": {"font": "body", "flags": 5}}, "y": {"pos": [0, 0]}}, "colors": {"c": {"rgb555": "0x7fff"}}}
	var b := {"elements": {"x": {"text": {"flags": null, "color": "c"}}, "y": null}, "colors": {"c": {"rgb555": null, "rgb": [1, 2, 3]}}}
	var m := UiLayout.merge(a, b)
	eq(m["elements"]["x"]["pos"], [1, 2], "没写的字段保留")
	eq(m["elements"]["x"]["text"], {"font": "body", "color": "c"}, "逐字段深合并, null 删除字段")
	check(not m["elements"].has("y"), "元素写 null = 删除")
	eq(m["colors"]["c"], {"rgb": [1, 2, 3]})
	eq(a["elements"]["x"]["text"]["flags"], 5, "不改动原表")


## 内容包叠加: example_mod 只改对话框文字位置、近景白闪与名字颜色, 其余沿用基础包
func test_pack_overlay():
	var base = _db(["remake"])
	var db = _db(["remake", "example_mod"])
	var lb := UiLayout.merge_dirs(base.pack_dirs())
	var lm := UiLayout.merge_dirs(db.pack_dirs())
	eq(UiLayout.warnings, [], "mod 没有拼错的元素")
	UiLayout.use(lb)
	eq(UiLayout.pos("dialog.text"), Vector2(9, 4), "基础包")
	eq(UiLayout.abs_pos("dialog.text"), Vector2(11, 141), "累加父元素 dialog.box (2,137)")
	eq(UiLayout.color("closeup.name"), Color8(239, 222, 148), "0x7772 按 round(x*255/31)")
	UiLayout.use(lm)
	eq(UiLayout.pos("dialog.text"), Vector2(10, 4), "mod 覆盖 pos")
	eq(UiLayout.text("dialog.text")["line_height"], 13, "同元素没写的字段保留")
	eq(UiLayout.text("dialog.text")["color"], UiText.BROWN, "颜色名解析")
	eq(UiLayout.color("closeup.name"), Color8(255, 255, 255), "mod 删掉 rgb555 改用 rgb")
	eq(UiLayout.el("closeup.hpbar.flash")["blend"], {"dst16": 12.0, "add16": [16.0, 8.0]}, "嵌套对象逐字段合并")
	eq(UiLayout.el("infobar.name"), lb["elements"]["infobar.name"], "没改的元素不变")
	UiLayout.use(null)
	base.free()
	db.free()


func test_layout_valid():
	UiLayout.reload()
	var errs := UiLayout.validate()
	eq(errs, [], "布局表引用都存在")
	eq(UiLayout.anchor("infobar.left", -1, 0), ScreenLayout.Anchor.TOP_LEFT, "A|B 锚点")
	eq(UiLayout.anchor("infobar.left", -1, 1), ScreenLayout.Anchor.BOTTOM_LEFT)
	eq(UiLayout.pos("infobar.left", Vector2.ZERO, 1), Vector2(1, 168), "A|B 坐标")
	eq(UiLayout.color("text.main"), Color8(181, 107, 41), "主色 0x59a5")
	eq(UiLayout.color("0x7730"), Color8(239, 206, 132), "光边 0x7730")


## 字格排版: 宽度按字节 (汉字 12、半角 6), 对齐按原版整除, 折行按字节
func test_text_cells():
	eq(UiText.bytes("位階上升"), 8)
	eq(UiText.bytes("HP99"), 4)
	eq(UiText.measure("位階上升"), 48.0)
	eq(UiText.measure("A1天"), 24.0)
	eq(UiText.measure("天", 10.0), 10.0, "10 号字格")
	eq(UiText.align_x("center_bytes", "火靈神劍", 0, 0, 46), 22.0, "法术名横幅 46 - 字节*3 ")
	eq(UiText.align_x("center_in", "位階上升", 0, 92), 22.0, "窗内居中 (92-48)/2")
	eq(UiText.align_x("center_in", "天", 5, 49), 23.0, "C 整除 (49-12)/2 = 18")
	eq(UiText.wrap_width("一二三四五", 36), PackedStringArray(["一二三", "四五"]), "按字节宽折行")
	eq(UiText.wrap_width("ab一二", 24), PackedStringArray(["ab一", "二"]))


## 标题卷轴菜单: 文字按字节宽居中在卷面 (框 130,67; 卷面 x 3..57、y 8..58 取自 Misc/Title 帧 0)
func test_title_menu_centered():
	UiLayout.reload()
	for i in 4:
		var t := UiText.make("title.menu_item", "新章初始", i)
		eq(t.position.x + UiText.measure(t.text) / 2.0, 130.0 + 30.5, "水平中心 = 卷面中心")
		eq(t.position.y, 76.0 + 12 * i, "四行 48 高垂直居中于卷面 51 高")
		t.free()


## 基线: 字库字体的汉字墨迹都落在原版字格第 1~11 行
func test_baselines():
	UiLayout.reload()
	var before := Assets.font_id
	Assets.set_font("sans")  # 不受本机设定里选的字体影响
	eq(UiFonts.baseline("sans"), 10.75, "思源黑体按墨迹中心对齐")
	eq(UiText.baseline(6.0), 5.375, "按字号比例")
	Assets.set_font(before if before != "" else UiFonts.default_id())
	# 思源黑体: 汉字字面 (ascent 0.88em 处到基线) 中心不应偏离原版墨迹中心 6.4 行超过半像素
	var sans := FontFile.new()
	sans.load_dynamic_font(ProjectSettings.globalize_path("res://assets/font/NotoSansSC-Medium.otf"))
	var asc := sans.get_ascent(480) / 480.0 * 12.0
	check(asc > 10.0 and asc < 15.0, "思源黑体 ascent (12 号) %s" % asc)


## 行动菜单: 图标间距与菜单宽由素材帧算, 位置按, 唯一实现 UiIconMenu.place_near
func test_icon_menu_metrics():
	if not Assets.exists("Misc/Man_int/anim.json"):
		check(true)
		return
	UiLayout.reload()
	var m := UiIconMenu.metrics("Misc/Man_int")
	eq(m["step"], 25, "W0 23 + gap 2")
	eq(m["gap"], 2, "(W2 27 - W0 23)/2")
	eq(m["h"], 21, "H2")
	eq(m["origin"], Vector2.ZERO, "第 0 帧自带 (2,2) 偏移 = gap")
	var menu := UiIconMenu.new()
	menu.setup(UiIconMenu.ACTION_FRAMES)
	eq(menu.width(), 127.0, "5*23 + 6*2")
	eq(menu.height(), 21.0)
	var off := UiLayout.vec_of("actionmenu.sub_pos", "pos", {"w0": menu.w0, "h": menu.height()})
	eq(Vector2(int(off.x), int(off.y)), Vector2(-5, -5), "子菜单位移 (-W0/4, -H2/4) 向零取整 (原版实测 2026-10-05)")
	menu.free()
	# 镜头按格对齐 (卷动 ≡ 20 mod 30, -4 mod 24): 菜单以格为中心, 顶边在格顶下 3 (原版截图 差异_第0幕_行动菜单)
	var cam := Vector2(-10, -4)
	var p := UiIconMenu.place_near(Vector2i(5, 4), cam, Vector2(320, 200), 127, 21)
	eq(p, Vector2(102, 99), "x = 5*30 - 63 + 25 + cam")
	eq(p.x + 63.5, 5 * 30 + 15.5, "中心对准格中心 (+0.5 为 C 整除)")
	eq(UiIconMenu.place_near(Vector2i(5, 4), Vector2(7, 9), Vector2(320, 200), 127, 21), Vector2(102, 99), "镜头不按格对齐时仍相对单位格")
	eq(UiIconMenu.place_near(Vector2i(9, 4), cam, Vector2(320, 200), 127, 21).x, 183.0, "第 9 列往里挪 30 (202), 再夹在可见区 (320-127-10)")
	eq(UiIconMenu.place_near(Vector2i(0, 4), cam, Vector2(320, 200), 127, 21).x, -10.0, "第 0 列 +30 后仍出界, 夹在可见区")


## 帧外框按原版 1 倍贴图 (与画质无关): 法术名横幅 93x21, 列表面板 246x94
func test_frame_rect_original():
	if not Assets.exists("Misc/Mag_misc/anim.json"):
		check(true)
		return
	eq(UiPanel.frame_rect("Misc/Mag_misc", 0).size, Vector2(93, 21))
	eq(UiPanel.frame_rect("Misc/Man_int", 44).size, Vector2(246, 94))
	eq(UiPanel.frame_rect("Misc/Man_int", 0), Rect2(2, 2, 23, 17), "部件偏移 + used_rect")


## 取位置: 固定 + repeat、二选一、多列/多行、点表、公式 (C 整除)、帧外框变量 w/h
func test_at_forms():
	UiLayout.use({"elements": {
		"a": {"pos": [3, 4], "repeat": {"count": 3, "step": [0, 13]}},
		"b": {"pos": ["1|168", 2]},
		"c": {"pos": [[25, 62], 56], "repeat": {"step": [0, 10]}},
		"d": {"pos": [[1, 2], [3, 4], [5, 6]]},
		"e": {"pos": ["7+28*k", "(200-h)/2"], "size": [160, "44+20*n"]},
		"f": {"parent": "a", "pos": [1, 1]}}})
	eq(UiLayout.at("a", 2), Vector2(3, 30), "repeat.step")
	eq(UiLayout.at("b", 0, {"which": 1}), Vector2(168, 2), "A|B")
	eq(UiLayout.at("c", 1), Vector2(62, 56), "多列: 按列取, 不再加 step")
	eq(UiLayout.at("d", 2), Vector2(5, 6), "点表")
	eq(UiLayout.at("e", 2, {"h": 21}), Vector2(63, 89), "公式整除")
	eq(UiLayout.size_of("e", {"n": 3}), Vector2(160, 104), "size 公式")
	eq(UiLayout.abs_at("f"), Vector2(4, 5), "父链")
	UiLayout.use(null)


## 代码里按字面 id 引用的布局元素都要在基础包布局表里 (漏写/拼错时这里报)
func test_code_ids_exist():
	UiLayout.reload()
	var re := RegEx.new()
	re.compile("(?:UiLayout\\.(?:pos|abs_pos|at|abs_at|rect|size|size_of|step|anchor|sprite|digits|text|el|val|num|vec|frame|fmt_width|panel|label|number|tag|tag_panel|sprite_vars)|UiText\\.make)\\(\\s*(?:[a-z_]+\\s*,\\s*)?\"([a-z0-9_.]+)\"")
	var missing: Array = []
	for dir in ["res://engine", "res://scripts"]:
		for f in _gd_files(dir):
			var src := FileAccess.get_file_as_string(f)
			for m in re.search_all(src):
				var id := m.get_string(1)
				if id.contains(".") and not id.ends_with(".") and not UiLayout.has(id) and not UiLayout.data().get("colors", {}).has(id):
					missing.append("%s: %s" % [f.get_file(), id])
	eq(missing, [], "代码引用的布局元素都存在")


func _gd_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


## 位階上升窗: 窗体 = Maplup 第 0 帧按外框居中 (114,36); 数字为 Maplup 第 1 帧, 旧/新两列; 属性行序 攻防咒行運
func test_levelup_window():
	UiLayout.reload()
	var b := {"lv": 4, "hp_max": 170, "mp_max": 18, "stats": {"str": 32, "int": 24, "avg": 27, "vit": 38, "luk": 31}}
	var a := {"lv": 5, "hp_max": 174, "mp_max": 19, "stats": {"str": 35, "int": 25, "avg": 27, "vit": 41, "luk": 30}}
	var w := UiLevelUp.new(b, a, ["火靈神劍", "水靈"])
	var win: UiPanel = w.get_child(0)
	eq(UiPanel.frame_rect("Misc/Maplup", 0).size, Vector2(92, 127), "窗体帧外框")
	eq(UiLayout.at("levelup.window"), Vector2(114, 36), "((320-w)/2, (200-h)/2)")
	var nums: Array = win.get_children().filter(func(n): return n is UiNumber)
	eq(nums.size(), 16, "8 行 x 旧/新")
	eq([nums[0].position, nums[0].text, nums[1].position, nums[1].text], [Vector2(23, 19), " 4", Vector2(46, 19), " 5"], "位")
	eq([nums[2].position, nums[2].text, nums[3].position], [Vector2(22, 32), " 170", Vector2(58, 32)], "体")
	eq([nums[8].position, nums[8].text, nums[9].text], [Vector2(25, 66), " 38", " 41"], "第 2 行是防 (Vit, 字段)")
	eq(nums[15].position, Vector2(62, 96), "運")
	eq(nums[0].dir, "Misc/Maplup", "字模 Maplup")
	var txt: Array = win.get_children().filter(func(n): return n is UiText)
	eq([txt.size(), txt[0].text, txt[0].position], [1, "火靈神劍", Vector2(24, 112)], "只画第一个新学法术 (原版 实测 2026-10-05)")
	w.free()

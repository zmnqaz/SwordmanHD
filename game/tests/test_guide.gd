# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 攻略 (内容包 guide/ + engine/ui/guide_panel.gd): markdown 转 BBCode、目录与繁体叠加层、默认章选择、
## 面板的切章/滚动/关闭、键鼠与触屏拖动、F4 热键、没有攻略的内容包 (设定面板不列「攻略」, 面板只显示「没有攻略」)。

const Router = preload("res://engine/input/input_router.gd")


## 假内容包: 只答 json / has_file (ContentInfo.db 用)
class FakeDb:
	extends RefCounted
	var files := {}
	func json(rel: String) -> Variant:
		return files.get(rel)
	func has_file(rel: String) -> bool:
		return files.has(rel)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## stages: 关卡章的关号; 另有一个非关卡章 (说明) 在最前; 每章正文 lines 行
func _db(stages: Array = [0, 1, 3, 5], lines := 80) -> FakeDb:
	var db := FakeDb.new()
	var chapters: Array = [{"id": "about", "file": "guide/about.json"}]
	db.files["guide/about.json"] = {"title": "说明", "label": "说明", "body": "# 说明\n正文"}
	for s in stages:
		var id := "stage_%02d" % s
		chapters.append({"id": id, "file": "guide/%s.json" % id, "stage": s})
		var body := PackedStringArray(["## 第%d关" % s])
		for i in lines:
			body.append("- 第 %d 行 **要点**" % i)
		db.files["guide/%s.json" % id] = {"title": "第%d幕 测试" % s, "label": "%d 测试" % s, "body": "\n".join(body)}
	db.files[GuideBook.INDEX] = {"format": "tdj-guide/1", "chapters": chapters}
	return db


func _gc(db: Object, stage := 0, next_stage := 0, in_battle := true) -> GameContext:
	var gc := GameContext.new()
	gc.content.db = db
	gc.state.stage = stage
	gc.state.next_stage = next_stage
	gc.in_battle = in_battle
	return gc


func _open(gc: GameContext, r = null) -> GuidePanel:
	GuidePanel.last_id = ""   # 每个用例都当「本次运行第一次打开」
	var p := GuidePanel.new()
	p.gc = gc
	p.router = r if r != null else Router.new()
	_tree().root.add_child(p)
	p.open()   # 协程: 停在 await closed, 面板已搭好并入栈
	return p


func set_chapter_for_test(p: GuidePanel, i: int) -> void:
	p.set_chapter(i)


func _close(p: GuidePanel) -> void:
	var r = p.router
	p.close()
	await _tree().process_frame
	if is_instance_valid(r) and r.get_parent() == null:
		r.free()


func _act(p: GuidePanel, k: int, pos := Vector2.INF) -> void:
	p.router.dispatch(UiAction.new(k, "key" if pos == Vector2.INF else "wheel", pos))


func test_markdown_to_bbcode():
	var b := GuideText.to_bbcode("# 标题\n- 一级 **粗** [x]\n  - 二级\n\n---\n普通", Color8(255, 0, 0))
	var ls := b.split("\n")
	eq(ls[0], "[b][color=#ff0000]标题[/color][/b]", "标题 = 粗体 + 标题色")
	eq(ls[1], "[ul bullet=·]一级 [b]粗[/b] [lb]x[rb][/ul]", "列表项、粗体、方括号转义")
	eq(ls[2], "[indent][ul bullet=-]二级[/ul][/indent]", "缩进两格 = 二级列表")
	eq(ls[3], "", "空行保留")
	check(ls[4].begins_with("[center]"), "分隔线")
	eq(ls[5], "普通")
	eq(GuideText.inline("a]b[c"), "a[rb]b[lb]c", "行内转义")
	eq(GuideText.to_bbcode("\n\nA\n\n\nB\n\n", Color.WHITE, 16), "A\n[font_size=16] \n[/font_size]B",
		"开头/结尾空行去掉, 连续空行算一个, 画成矮行 (换行符在小字号里)")


## 仓库里的攻略内容包 (game/content/remake/guide, 生成工具的脚本 生成): 目录完整、关卡章对得上、繁体叠加层生效
func test_pack_guide_loads_with_locale():
	var db := ContentDB.new()
	db.load_packs(["remake"])   # 缺原版内容包 tdj 时 base 报错, remake 自己的文件照样能读
	var info := ContentInfo.new()
	info.db = db
	check(GuideBook.available(info), "remake 包带攻略")
	var g := GuideBook.load_from(info)
	check(g.chapters.size() >= 38, "通用章 + 36 关 (%d 章)" % g.chapters.size())
	eq(g.chapters[0]["stage"], -1, "第一章是非关卡章 (完美结局)")
	eq(g.chapters[0]["title"], "完美结局")
	for s in 36:
		eq(g.chapters[g.index_for_stage(s)]["stage"], s, "第 %d 关有章" % s)
	var i23 := g.index_for_stage(23)
	eq(g.chapters[i23]["title"], "第23幕 焚炎劫火")
	eq(g.chapters[g.index_for_stage(24)]["title"], "第23幕 黄泉幽径", "第 24 关起幕号 = 关号 - 1")
	eq(g.chapters[g.index_for_stage(35)]["title"], "番外 两百块帝国", "关 35 = 番外")
	# 玩家版: 不带出处/网址/开发字眼, 每关正文不过长 (超过一屏用 ↑↓ 滚动)
	for c in g.chapters:
		var body := String(c["body"])
		for w in ["http", "[VV]", "3DM", "SINA", "来源", "出处", "dossier", "本作", "复刻", "脚本", "变量"]:
			check(not body.contains(w), "%s 不含「%s」" % [c["title"], w])
		if int(c["stage"]) >= 0:
			check(body.length() <= 1500, "%s 正文不长 (%d 字)" % [c["title"], body.length()])
	db.set_lang("hant")
	var gt := GuideBook.load_from(info)
	eq(gt.chapters[0]["title"], "完美結局", "繁体叠加层: 标题转繁体")
	check(String(gt.chapters[i23]["body"]).contains("勝利"), "繁体叠加层: 正文转繁体")
	check(String(gt.chapters[g.index_for_stage(8)]["body"]).contains("天河朱砂"), "繁体叠加层: 物品名用游戏繁体原名")
	db.free()


func test_default_chapter_selection():
	var g := GuideBook.load_from(_gc(_db([0, 1, 3, 5])).content)
	eq(g.chapters.size(), 5)
	eq(g.index_for_stage(3), 3, "有该关的章: 就是它")
	eq(g.index_for_stage(4), 3, "该关没有章: 取关号不超过它的最近一章")
	eq(g.index_for_stage(99), 4, "超过最后一关: 最后一章")
	eq(g.index_for_stage(-5), 1, "比所有关都小: 第一个关卡章 (跳过说明章)")
	eq(GuideBook.current_stage(_gc(null, 3, 4, true)), 3, "战场里: 本关")
	eq(GuideBook.current_stage(_gc(null, 3, 4, false)), 4, "城镇/营地: 下一关")
	var empty := GuideBook.load_from(_gc(FakeDb.new()).content)
	check(empty.is_empty(), "没有 guide.json: 空")
	eq(empty.index_for_stage(3), 0)


## 战场里 = 本关的章, 不看「上次看的章」, 在战场里翻页也不改它
func test_battle_always_opens_stage_chapter():
	var gc := _gc(_db([0, 1, 3, 5]), 3, 4, true)
	var p := _open(gc)
	eq(p.book.chapters[p.chapter]["id"], "stage_03", "战场: 本关")
	p.set_chapter(1)
	eq(GuidePanel.last_id, "", "战场里翻到的章不记")
	await _close(p)
	GuidePanel.last_id = "stage_05"
	var q := GuidePanel.new()
	q.gc = gc
	q.router = Router.new()
	_tree().root.add_child(q)
	q.open()
	eq(q.book.chapters[q.chapter]["id"], "stage_03", "战场: 不理会营地里记下的章")
	await _close(q)
	gc.in_battle = false
	var r := GuidePanel.new()
	r.gc = gc
	r.router = Router.new()
	_tree().root.add_child(r)
	r.open()
	eq(r.book.chapters[r.chapter]["id"], "stage_05", "出了战场: 用营地里记下的章")
	await _close(r)


## 第一次打开 = 目录第一章 (非关卡章); 之后关了再开 = 上次看的章; 目录第一章是关卡章的内容包仍按当前关
func test_first_open_then_remember_last_chapter():
	var gc := _gc(_db([0, 1, 3, 5]), 3, 4, false)
	var p := _open(gc)
	eq(p.book.chapters[p.chapter]["id"], "about", "第一次: 第一章, 不是当前关")
	p.set_chapter(3)
	await _close(p)
	var q := GuidePanel.new()
	q.gc = gc
	q.router = Router.new()
	_tree().root.add_child(q)
	q.open()
	eq(q.book.chapters[q.chapter]["id"], "stage_03", "再开: 停在上次看的章")
	await _close(q)
	GuidePanel.last_id = ""
	var g := GuideBook.load_from(_gc(_db([0, 1, 3, 5])).content)
	g.chapters.remove_at(0)
	eq(g.first_open_index(3), 2, "第一章是关卡章: 按关号")
	eq(g.index_of("stage_05"), 3)
	eq(g.index_of("nope"), -1)


## 指定章 id 打开 (营地「五魂化蘊」翻到 spirit_<单位号>): 有就直接是它, 没有按默认章
func test_open_at_chapter_id():
	var db := _db([0, 1, 3, 5])
	db.files["guide/spirit_2.json"] = {"title": "五魂 上官远", "label": "五魂 上官远", "body": "正文"}
	db.files["guide/guide.json"]["chapters"].append({"id": "spirit_2", "file": "guide/spirit_2.json"})
	var gc := _gc(db, 1, 1, false)
	GuidePanel.last_id = ""
	var p := GuidePanel.new()
	p.gc = gc
	p.router = Router.new()
	p.start_id = "spirit_2"
	_tree().root.add_child(p)
	p.open()
	eq(p.book.chapters[p.chapter]["id"], "spirit_2", "直接翻到指定章")
	await _close(p)
	var q := GuidePanel.new()
	q.gc = gc
	q.router = Router.new()
	q.start_id = "spirit_99"
	_tree().root.add_child(q)
	q.open()
	eq(q.book.chapters[q.chapter]["id"], "spirit_2", "没有这一章: 按上次看的章 (刚才翻到的 spirit_2)")
	await _close(q)


## 打开默认章 → 左右切章 (首尾循环, 正文回顶) → 上下/翻页滚动 (夹在 0..最大) → 取消关闭出栈
func test_panel_switch_scroll_close():
	var p := _open(_gc(_db(), 5, 6, false))
	var r = p.router
	check(GuidePanel.is_open(), "面板打开")
	eq(r.top(), p, "模态浮层在栈顶")
	eq(p.chapter, 0, "第一次打开: 目录第一章 (说明)")
	set_chapter_for_test(p, 4)
	eq(p._title.text, "第5幕 测试", "标题")
	check(p.max_scroll() > 0.0, "长正文可以滚 (%.1f)" % p.max_scroll())
	_act(p, UiAction.DOWN)
	eq(p.scroll, p.line_step(), "↓ 滚一行")
	_act(p, UiAction.PAGE_DOWN)
	eq(p.scroll, p.line_step() + p.page(), "翻页键下翻一屏")
	_act(p, UiAction.CONFIRM)
	check(p.scroll > p.line_step() + p.page(), "确认也下翻一屏")
	for i in 400:
		_act(p, UiAction.DOWN)
	eq(p.scroll, p.max_scroll(), "滚到底停住")
	_act(p, UiAction.PAGE_UP)
	check(p.scroll < p.max_scroll(), "翻页键上翻")
	_act(p, UiAction.RIGHT)
	eq([p.chapter, p.scroll], [0, 0.0], "→ 下一章 (末章回绕到第一章), 正文回顶")
	_act(p, UiAction.LEFT)
	eq(p.chapter, 4, "← 上一章 (回绕)")
	_act(p, UiAction.LEFT)
	eq(p._title.text, "第3幕 测试", "换章后标题跟着变")
	_act(p, UiAction.UP)
	eq(p.scroll, 0.0, "顶上再 ↑ 不动")
	_act(p, UiAction.CANCEL)
	await _tree().process_frame
	check(not GuidePanel.is_open(), "取消关闭")
	check(r.top() == null, "关闭后出栈")
	r.free()


## 鼠标: 悬停不换章、点章节换章、滚轮在章节栏滚章节栏/在正文滚正文、点面板内空白不关、点面板外关闭; 触屏: 正文上拖动 = 滚动
func test_pointer_and_touch():
	var stages: Array = []
	for i in 20:
		stages.append(i)
	var p := _open(_gc(_db(stages), 0, 0, true))
	var r = p.router
	eq(p.chapter, 1, "战场第 0 关")
	var row3: Vector2 = p._origin.get_global_transform_with_canvas() * (UiLayout.at("guide.cursor", 3) + Vector2(10, 5))
	await _tree().create_timer(UiHit.GUARD + 0.05).timeout   # 防误触: 面板刚出现时的点按不算
	var mv := InputEventMouseMotion.new()
	mv.position = row3
	r._handle(mv)
	eq(p.chapter, 1, "悬停不换章")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = row3
	r._handle(click)
	eq(p.chapter, 3, "点第 3 行 = 换到该章")
	_act(p, UiAction.DOWN, row3)
	eq([p.list_top, p.scroll], [1, 0.0], "滚轮在章节栏: 滚章节栏, 不动正文")
	var body: Vector2 = p._origin.get_global_transform_with_canvas() * (UiLayout.rect("guide.body").get_center())
	_act(p, UiAction.DOWN, body)
	eq(p.scroll, p.line_step(), "滚轮在正文: 滚正文")
	click.position = p._origin.get_global_transform_with_canvas() * (UiLayout.at("guide.hint") + Vector2(2, 2))
	r._handle(click)
	check(GuidePanel.is_open(), "点面板内空白处不关闭")
	# 触屏: 在正文上手指往上拖 3.5 行 = 3 步「下」(正文上卷 3 行), 抬手不确认
	_tree().root.add_child(r)
	r.set_touch_mode(true)
	var pitch: float = (p._origin.get_global_transform_with_canvas().basis_xform(Vector2(0, p.line_step()))).y
	p.scroll = 0.0
	p._update()
	_drag(r, body, body - Vector2(0, pitch * 3.5))
	eq(p.scroll, p.line_step() * 3, "正文上拖动 = 按行滚动 (InputRouter 竖排列表拖动机制)")
	eq(p.chapter, 3, "拖动不换章")
	r.set_touch_mode(false)
	click.position = Vector2(2, 2)   # 屏幕左上角: 面板外
	r._handle(click)
	await _tree().process_frame
	check(not GuidePanel.is_open(), "点面板外关闭")
	r.get_parent().remove_child(r)
	r.free()


func _drag(r, from: Vector2, to: Vector2, steps := 7) -> void:
	var t := InputEventScreenTouch.new()
	t.position = from
	t.pressed = true
	r._handle(t)
	var prev := from
	for i in range(1, steps + 1):
		var pt := from.lerp(to, float(i) / steps)
		var d := InputEventScreenDrag.new()
		d.position = pt
		d.relative = pt - prev
		r._handle(d)
		prev = pt
	t = InputEventScreenTouch.new()
	t.position = to
	t.pressed = false
	r._handle(t)


## 「整理行囊」搬到了设定面板 (2026-10-25): 确认该行 → 公共行囊按物品编号排, 结果显示在这一行的值上; 攻略面板里不再有按钮, 菜单键也不整理
func test_settings_row_sorts_bag_and_guide_no_longer_does():
	var gc := _gc(_db(), 0, 0, false)
	gc.state.bag = [236, 0, 220]
	var p := _open(gc)
	_act(p, UiAction.MENU)
	eq(gc.state.bag, [236, 0, 220], "攻略面板里菜单键不再整理行囊")
	await _close(p)
	var holder := Node.new()
	_tree().root.add_child(holder)
	var sp := SettingsPanel.new()
	sp.gc = gc
	sp.router = Router.new()
	holder.add_child(sp)
	sp.open()   # 协程: 停在等关闭
	check("bag_sort" in SettingsSchema.shown_rows().map(func(rr): return rr["key"]), "设定面板有「整理行囊」行")
	sp._activate("bag_sort")
	eq(gc.state.bag, [0, 220, 236], "行囊按编号排")
	eq(sp._sort_msg, UiStrings.t("settings.bag_sort.done", [3]), "提示: 已整理 3 格")
	sp._activate("bag_sort")
	eq(sp._sort_msg, UiStrings.t("settings.bag_sort.same"), "再整理一次: 已是顺序")
	check(sp.visible, "整理不藏设定面板")
	sp.closed.emit(true)
	await _tree().process_frame
	holder.queue_free()


## F4: 输入层发 guide_requested; GuidePanel.toggle 开着就关
func test_hotkey_toggles():
	var r = Router.new()
	var got := [0]
	r.guide_requested.connect(func(): got[0] += 1)
	var e := InputEventKey.new()
	e.keycode = KEY_F4
	e.pressed = true
	eq(r._handle(e), true, "F4 吞键")
	eq(got[0], 1, "F4 = 攻略")
	var gc := _gc(_db(), 1, 1, true)
	GuidePanel.last_id = ""
	var p := GuidePanel.toggle(_tree().root, gc, r)
	check(p != null and GuidePanel.is_open(), "第一次: 打开")
	eq(p.chapter, 2, "战场第 1 关")
	eq(GuidePanel.toggle(_tree().root, gc, r), null, "再按: 关闭")
	await _tree().process_frame
	check(not GuidePanel.is_open(), "已关闭")
	r.free()


## 内容包没有攻略: 设定面板不列「攻略」行; 面板 (热键) 只显示「没有攻略」, 按键不出错, 取消关闭
func test_pack_without_guide():
	var cur := GameContext.current()
	var keep: Object = cur.content.db
	cur.content.db = FakeDb.new()
	var keys := SettingsSchema.shown_rows().map(func(rr): return rr["key"])
	check(not keys.has("guide"), "没有攻略: 设定面板不列「攻略」")
	cur.content.db = _db()
	keys = SettingsSchema.shown_rows().map(func(rr): return rr["key"])
	check(keys.has("guide"), "有攻略: 列「攻略」(动作行)")
	eq(SettingsSchema.row("guide")["kind"], "action")
	cur.content.db = keep
	var p := _open(_gc(FakeDb.new(), 3, 3, true))
	eq(p.chapter_count(), 0, "没有章")
	eq(p._title.text, UiStrings.t("guide.title"))
	eq(p._text.text, UiStrings.t("guide.empty"), "正文 = 没有攻略")
	for k in [UiAction.LEFT, UiAction.RIGHT, UiAction.DOWN, UiAction.CONFIRM]:
		_act(p, k)
	check(p.ui_hits().size() >= 1, "命中区: 没有章节行, 正文条与面板底照常")
	await _close(p)
	check(not GuidePanel.is_open(), "关闭")


## 设定面板「攻略」行: 确认打开攻略面板 (设定面板先藏起来), 关掉后回到设定面板
func test_settings_row_opens_guide():
	var cur := GameContext.current()
	var keep: Object = cur.content.db
	cur.content.db = _db()
	var gc := _gc(_db(), 3, 3, true)
	var holder := Node.new()
	_tree().root.add_child(holder)
	var sp := SettingsPanel.new()
	sp.gc = gc
	sp.router = Router.new()
	holder.add_child(sp)
	sp.open()   # 协程: 停在等关闭
	var idx := SettingsSchema.shown_rows().map(func(rr): return rr["key"]).find("guide")
	check(idx >= 0, "设定面板有「攻略」行")
	sp._activate("guide")   # 协程: 停在等攻略面板关闭
	check(GuidePanel.is_open(), "打开攻略面板")
	eq(sp.visible, false, "设定面板藏起来")
	GuidePanel._current.close()
	await _tree().process_frame
	eq(sp.visible, true, "关掉攻略回到设定面板")
	eq(sp.router.top(), sp, "输入回到设定面板")
	var sr = sp.router
	sp.closed.emit(true)
	cur.content.db = keep
	await _tree().process_frame
	sr.free()
	holder.queue_free()
	await _tree().process_frame

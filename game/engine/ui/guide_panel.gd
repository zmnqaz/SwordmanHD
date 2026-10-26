# SPDX-License-Identifier: GPL-3.0-only
class_name GuidePanel
extends UiLayer
## 攻略面板 (复刻新增): 热键 F2 / F4 (任何画面, InputRouter.guide_requested) 或设定面板「攻略」行打开。模态浮层, 同设定面板。
## 内容来自内容包 guide/ (GuideBook, docs/内容格式.md §16), 版式来自布局表 guide.*, 文案 UiStrings guide.*。
##   左栏章节列表 (超出版面时滚动), 右栏正文 (RichTextLabel; 内容是 markdown 子集, GuideText 转 BBCode)。
##   ↑↓ 滚动正文 (按住连发)   ←→ 换章 (首尾循环)   翻页键 / 确认 = 正文上/下翻一屏   取消 / 右键 / 点面板外 / 再按 F2 或 F4 = 关闭
##   鼠标: 点章节换章; 滚轮在章节栏上滚章节栏、在正文上滚正文。触屏: 在正文或章节栏上拖动 = 滚动 (InputRouter 的竖排列表
##   拖动机制: 正文按 line_step 切成一条条命中区, 拖过一条发一步 ↑/↓), 点章节换章。手柄同键位语义 (十字键/摇杆、确认、取消、LB/RB)。
## (「整理行囊」原来是这里的左上角按钮, 2026-10-25 搬进了设定面板, 见 SettingsPanel._sort_bag。)
## 打开时默认当前关卡的章 (GuideBook.current_stage: 战场 = 本关, 城镇/营地 = 下一关; 该关没有章取前面最近的一章)。
## 内容包没有攻略 (mod / 新游戏): 面板只显示「没有攻略」(设定面板也不列「攻略」行)。

signal closed

static var _current: GuidePanel = null   # 同时只开一个: 再按热键 = 关闭

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)
var router: Object = null    # 统一输入层: 打开方注入 (组装层 / 设定面板传 InputRouter, 测试传独立实例)
var book := GuideBook.new()
var chapter := 0             # 当前章
var start_id := ""           # 打开时直接翻到的章 id (如营地「五魂化蘊」翻到 spirit_<单位号>); 空/找不到 = 当前关卡的章
var list_top := 0            # 章节栏第一个可见行
var scroll := 0.0            # 正文已上卷的高度 (原版像素)

var _origin: Node2D          # 面板左上角 (原版坐标), 布局表 guide.* 的 pos 相对它
var _draw_node: Node2D
var _title: UiText
var _hint: UiText
var _rows: Array[UiText] = []
var _text: RichTextLabel
var _vis := 13
var _s := 4.0                # 原版像素 -> 屏幕像素 (UiLayer.root 的放大倍数)


func _init() -> void:
	super(55)   # 压在设定面板 (54) 之上


## 热键入口 (组装层调): 没开就打开 (挂在 parent 下, 不 await), 开着就关掉。返回新开的面板 (关掉时 null)
static func toggle(parent: Node, ctx: GameContext, input: Object) -> GuidePanel:
	if is_open():
		_current.close()
		return null
	var p := GuidePanel.new()
	p.gc = ctx
	p.router = input
	parent.add_child(p)
	p.open()
	return p


## 直接打开到章 chapter_id (没开才开; 挂在 parent 下, 不 await)。内容包没有这一章就按默认章打开
static func open_chapter(parent: Node, ctx: GameContext, input: Object, chapter_id: String) -> GuidePanel:
	if is_open():
		return null
	var p := GuidePanel.new()
	p.gc = ctx
	p.router = input
	p.start_id = chapter_id
	parent.add_child(p)
	p.open()
	return p


static func is_open() -> bool:
	return is_instance_valid(_current) and not _current.is_queued_for_deletion()


## 打开并等到关闭 (调用方先 add_child)
func open() -> void:
	_current = self
	book = GuideBook.load_from(gc.content)
	chapter = book.index_for_stage(GuideBook.current_stage(gc))
	if start_id != "":
		for i in book.chapters.size():
			if book.chapters[i]["id"] == start_id:
				chapter = i
	_build()
	_show_chapter()
	if router != null:
		router.push(self, true)   # 模态浮层: 之后下层再入栈也抢不走输入
	await closed
	if router != null:
		router.pop(self)
	if _current == self:
		_current = null
	queue_free()


func close() -> void:
	closed.emit()


# ---------------------------------------------------------------- 搭界面

func _build() -> void:
	_s = root.scale.x
	var dim := ColorRect.new()   # 整屏压暗 (模态): 盖得比任何窗口都大, 不依赖屏幕尺寸
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.position = Vector2(-8192, -8192)
	dim.size = Vector2(16384, 16384)
	add_child(dim)
	move_child(dim, 0)
	var frame := Node2D.new()
	add(frame, UiLayout.anchor("guide.panel", -1))
	_origin = Node2D.new()
	_origin.position = UiLayout.pos("guide.panel")
	frame.add_child(_origin)
	_draw_node = _Frame.new()
	_draw_node.panel = self
	_origin.add_child(_draw_node)
	_title = UiText.make("guide.title")
	_origin.add_child(_title)
	_hint = UiText.make("guide.hint", UiStrings.t("guide.hint"))
	_origin.add_child(_hint)
	var rep = UiLayout.val("guide.list", "repeat", {})
	_vis = maxi(1, int(rep.get("count", 13))) if rep is Dictionary else 13
	for i in _vis:
		var t := UiText.make("guide.list", "", i)
		_origin.add_child(t)
		_rows.append(t)
	# 正文: 在「反缩放」节点下按 SCALE 倍字号排版 (同 UiText 的做法, 放大后不糊); 裁剪框 = 布局表 guide.body
	var hi := Node2D.new()
	hi.scale = Vector2.ONE / _s
	_origin.add_child(hi)
	var br := UiLayout.rect("guide.body")
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = br.position * _s
	clip.size = br.size * _s
	hi.add_child(clip)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.size = Vector2(br.size.x * _s, 0)
	var spec := UiLayout.text("guide.body")
	var fs := int(round(UiLayout.num("guide.body", "font_size", 10) * _s))
	_text.add_theme_font_override("normal_font", UiText.game_font(false))
	_text.add_theme_font_override("bold_font", UiText.game_font(true))
	_text.add_theme_font_size_override("normal_font_size", fs)
	_text.add_theme_font_size_override("bold_font_size", fs)
	_text.add_theme_color_override("default_color", spec["color"])
	_text.add_theme_constant_override("line_separation", int(round(UiLayout.num("guide.body", "line_gap", 2) * _s)))
	clip.add_child(_text)


func chapter_count() -> int:
	return book.chapters.size()


## 一步滚动的高度 (原版像素; 方向键/滚轮/拖动一条)
func line_step() -> float:
	return UiLayout.num("guide.body", "line_step", 12)


func page() -> float:
	return maxf(line_step(), UiLayout.size_of("guide.body").y - line_step())


## 正文最多能上卷多少 (原版像素)
func max_scroll() -> float:
	if _text == null:
		return 0.0
	return maxf(0.0, _text.get_content_height() / _s - UiLayout.size_of("guide.body").y)


func _show_chapter() -> void:
	scroll = 0.0
	if book.is_empty():
		_title.text = UiStrings.t("guide.title")
		_text.text = GuideText.inline(UiStrings.t("guide.empty"))
	else:
		var c: Dictionary = book.chapters[chapter]
		_title.text = String(c["title"])
		_text.text = GuideText.to_bbcode(String(c["body"]), UiLayout.color(UiLayout.val("guide.body", "head_color"), Color8(255, 224, 116)),
			int(round(UiLayout.num("guide.body", "para_gap", 4) * _s)))
	list_top = SettingsPanel.scroll_top(chapter, list_top, _vis, chapter_count())
	_update()


func _update() -> void:
	scroll = clampf(scroll, 0.0, max_scroll())
	_text.position.y = -roundf(scroll * _s)
	var sel_c := UiLayout.color("guide.sel_color", Color8(255, 224, 116))
	var dim_c := UiLayout.color("guide.dim_color", Color8(170, 160, 140))
	var max_b := int(UiLayout.size_of("guide.list").x / (float(UiLayout.text("guide.list").get("size", 10)) / 2.0))
	for s in _vis:
		var e := list_top + s
		_rows[s].visible = e < chapter_count()
		if e < chapter_count():
			_rows[s].text = fit_bytes(String(book.chapters[e]["label"]), max_b)
			_rows[s].color = sel_c if e == chapter else dim_c
	_draw_node.queue_redraw()


## 超出 max_bytes (原版按字节排版: 汉字 2) 的文字截断并加省略号
static func fit_bytes(s: String, max_bytes: int) -> String:
	if UiText.bytes(s) <= max_bytes:
		return s
	var out := ""
	for ch in s:
		if UiText.bytes(out + ch) > max_bytes - 2:
			break
		out += ch
	return out + "…"


func set_chapter(i: int) -> void:
	if chapter_count() == 0:
		return
	chapter = posmod(i, chapter_count())
	_show_chapter()


func scroll_by(d: float) -> void:
	scroll += d
	_update()


func scroll_list(d: int) -> void:
	list_top = clampi(list_top + d, 0, maxi(0, chapter_count() - _vis))
	_update()


## 视口坐标 p 是否落在章节栏 (滚轮/拖动在这里滚章节栏)
func _in_list(p: Vector2) -> bool:
	var local := _origin.get_global_transform_with_canvas().affine_inverse() * p
	var r := UiLayout.rect("guide.cursor", 0)
	return Rect2(r.position, Vector2(r.size.x, UiLayout.step("guide.cursor").y * _vis)).has_point(local)


# ---------------------------------------------------------------- 指针 / 输入

## 命中区 (engine/ui/ui_hit.gd): 章节行 (点 = 换章)、正文按 line_step 切的条 (只为触屏拖动滚动, 点按无动作)、面板底 (点面板内空白不关闭)
func ui_hits() -> Array:
	var out: Array = []
	if _origin == null:
		return out
	var csz := UiLayout.size_of("guide.cursor")
	for s in _vis:
		var e := list_top + s
		if e >= chapter_count():
			break
		out.append(UiHit.area(Rect2(UiLayout.at("guide.cursor", s), csz), "c:%d" % e, _origin))
	var br := UiLayout.rect("guide.body")
	var st := line_step()
	var k := 0
	while br.position.y + st * (k + 1) <= br.end.y + 0.01:
		out.append(UiHit.area(Rect2(br.position.x, br.position.y + st * k, br.size.x, st), "b:%d" % k, _origin, UiAction.NONE))
		k += 1
	out.append(UiHit.area(Rect2(Vector2.ZERO, UiLayout.size_of("guide.panel")), null, _origin, UiAction.NONE))
	return out


func ui_select(_i) -> void:
	pass   # 悬停不换章 (鼠标划过章节栏不该把正文换掉), 点按才换 (ui_action 里按 a.hit)


func ui_outside_action() -> int:
	return UiAction.CANCEL   # 点面板外 = 关闭 (触屏靠它退出)


func ui_action(a: UiAction) -> bool:
	match a.kind:
		UiAction.UP, UiAction.DOWN:
			var d := -1 if a.kind == UiAction.UP else 1
			if a.has_pos() and _in_list(a.pos):
				scroll_list(d)
			else:
				scroll_by(d * line_step())
		UiAction.LEFT, UiAction.RIGHT:
			if not a.echo:
				set_chapter(chapter + (-1 if a.kind == UiAction.LEFT else 1))
		UiAction.PAGE_UP:
			scroll_by(-page())
		UiAction.PAGE_DOWN:
			scroll_by(page())
		UiAction.CONFIRM, UiAction.SELECT:
			if a.hit is String and String(a.hit).begins_with("c:"):
				set_chapter(int(String(a.hit).substr(2)))
			elif a.hit == null and not a.echo:
				scroll_by(page())
		UiAction.CANCEL:
			close()
	return true   # 模态: 下层收不到


## 底图: 底板、边框、分隔线、选中章光标、章节栏 ▲▼、正文滚动条 (坐标颜色全取布局表 guide.*)
class _Frame:
	extends Node2D
	var panel: GuidePanel

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, UiLayout.size_of("guide.panel"))
		draw_rect(r, UiLayout.color(UiLayout.val("guide.panel", "color"), Color(0.04, 0.02, 0.01, 0.96)))
		var bc := UiLayout.color(UiLayout.val("guide.panel", "border"), Color8(150, 112, 52))
		draw_rect(r.grow(-0.5), bc, false, 1.0)
		draw_rect(r.grow(-2.5), Color(bc, 0.35), false, 1.0)
		draw_rect(UiLayout.rect("guide.divider"), UiLayout.color(UiLayout.val("guide.divider", "color"), bc))
		var slot := panel.chapter - panel.list_top
		if slot >= 0 and slot < panel._vis and panel.chapter_count() > 0:
			draw_rect(UiLayout.rect("guide.cursor", slot), UiLayout.color(UiLayout.val("guide.cursor", "color")))
		var ac := UiLayout.color("guide.sel_color", Color8(255, 224, 116))
		var cr := UiLayout.rect("guide.cursor", 0)
		var cx := cr.end.x - 4.0
		if panel.list_top > 0:
			var y0 := cr.position.y - 1.0
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 3, y0 + 3), Vector2(cx + 3, y0 + 3), Vector2(cx, y0 - 1)]), ac)
		if panel.list_top + panel._vis < panel.chapter_count():
			var y1 := UiLayout.at("guide.cursor", panel._vis - 1).y + cr.size.y + 1.0
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 3, y1 - 3), Vector2(cx + 3, y1 - 3), Vector2(cx, y1 + 1)]), ac)
		var ms := panel.max_scroll()
		if ms > 0.0:
			var tr := UiLayout.rect("guide.scrollbar")
			draw_rect(tr, UiLayout.color(UiLayout.val("guide.scrollbar", "color_off"), Color(0.35, 0.3, 0.25, 0.6)))
			var view := UiLayout.size_of("guide.body").y
			var h := maxf(6.0, tr.size.y * view / (view + ms))
			var y := tr.position.y + (tr.size.y - h) * panel.scroll / ms
			draw_rect(Rect2(tr.position.x, y, tr.size.x, h), UiLayout.color(UiLayout.val("guide.scrollbar", "color"), ac))

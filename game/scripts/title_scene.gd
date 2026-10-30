# SPDX-License-Identifier: GPL-3.0-only
extends Node2D
## 标题画面 (布局参照重制版 TitleScene): Misc/Title 第 1 帧为标题图, 第 0 帧为菜单框 (居中, 有效区域 61x67);
## 四个选项纵向居中排列, 行距 12, 原版点阵字 (UiText 12 号), 选中项主色, 其余浅棕色不透明。
## 原版: logo 之后只显示标题图, 按任意键 (确认/取消/方向) 才出现菜单, 同时背景压暗约一半。
## 操作: ↑/← 减 1, ↓/→ 加 1, 首尾循环; 确认执行; 取消无作用;
##   菜单出现不足 1 秒时对「新章初始」按确认无效。鼠标悬停 = 选中项跟随, 点按 = 选中并确认 (ui_hits)。
## 锚点: 标题图与菜单都按安全区居中 (加宽时两边留给装饰边)。

const ITEM_COUNT := 4  # 各项文字取自文案表 title.menu.item.<i> (内容包 text/ui.json)
## 选中项主色 (0x59a5); 未选中项浅棕 (布局表 title.idle_color, 同营地禁用色 0x6acd); 菜单出现时背景压暗 (title.dim)
const SEL_COLOR := UiText.BROWN
const NEW_GAME_GUARD := 1.0

static func _item(i: int) -> String:
	return UiStrings.t("title.menu.item.%d" % i)


var selection := 0
var _busy := false
var _menu_shown := false
var _shown_at := 0.0
var _clock := 0.0       # 游戏时间 (按帧累加 delta): 「菜单出现 1 秒内忽略新章初始」按它算, 不用墙钟, 固定帧率的自动测试 (跑得比真实时间快) 才能复现
var _bg: AnimPlayer
var _menu: Node2D
var _texts: Array[UiText] = []
var _save_win: CampSaveWindow   # 「前歷再續」存读档窗 (与营地共用, 原版)


func _ready() -> void:
	scale = Vector2.ONE * Assets.SCALE
	ScreenLayout.bind_node(self, ScreenLayout.SAFE)
	_bg = AnimPlayer.new()
	_bg.show_frame(ThemeAssets.p("title.art"), 1)
	add_child(_bg)
	ScreenLayout.mirror_edges(self)  # 宽屏两侧镜像铺满
	_menu = Node2D.new()
	_menu.visible = false
	add_child(_menu)
	_menu.add_child(UiLayout.panel("title.menu_box"))  # 菜单框 (Misc/Title 第 0 帧), 位置取布局表
	for i in ITEM_COUNT:
		var t := UiText.make("title.menu_item", _item(i), i)
		_menu.add_child(t)
		_texts.append(t)
	_add_version_label()
	_update()
	InputRouter.push(self)
	Game.fade_in(0.5)
	if Game.fast or Game.skip_movies:  # 自动测试: 直接显示菜单
		_show_menu()


func _process(delta: float) -> void:
	_clock += delta


## 右下角的版本号 (玩家报 bug 时对得上哪一版): 屏幕坐标的小字, 半透明, 不挡点按; 画在黑幕 (layer 100) 之下
func _add_version_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var l := Label.new()
	l.text = GameVersion.label()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UiText.game_font(false))
	l.add_theme_font_size_override("font_size", maxi(12, int(0.025 * get_viewport().get_visible_rect().size.y)))
	l.add_theme_color_override("font_color", Color(1, 0.94, 0.78, 0.7))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(l)


func _show_menu() -> void:
	if _menu_shown:
		return
	_menu_shown = true
	_shown_at = _clock
	if Game.fast or Game.skip_movies:  # 自动测试: 一步到位
		_menu.visible = true
		_bg.modulate = UiLayout.color("title.dim")
		return
	# 原版 (录像对照 2026-10-05): 背景分 4 步压暗 (每步 2 个时钟), 随后菜单框自左滑入并淡入 (UiSlide, 表 slide.title)
	var dim: Dictionary = UiLayout.motion("title.dim")
	var tick := float(UiLayout.motion("tick").get("sec", 0.04))
	for k in dim.get("steps", []):
		_bg.modulate = Color(float(k), float(k), float(k))
		await get_tree().create_timer(2 * tick).timeout
	_bg.modulate = UiLayout.color("title.dim")
	var m := UiLayout.motion("slide.title")
	_menu.position = Vector2.ZERO
	UiSlide.run(_menu, Vector2.ZERO, Vector2.LEFT, m.get("offsets", [0]), true)


func _update() -> void:
	for i in _texts.size():
		_texts[i].color = SEL_COLOR if i == selection else UiLayout.color("title.idle_color")


## 指针 (engine/ui/ui_hit.gd): 菜单出现后为各选项文字外扩 2 像素; 存读档窗打开时交给它
func ui_pointer_target() -> Object:
	if _save_win:
		return _save_win
	return self if _menu_shown and not _busy else null


func ui_hits() -> Array:
	var out: Array = []
	for i in _texts.size():
		out.append(UiHit.area(Rect2(_texts[i].position, Vector2(UiText.measure(_item(i)), _texts[i].size)).grow(2), i, _menu))
	return out


func ui_select(i) -> void:
	if i != selection:
		selection = i
		_update()


## 统一输入层 (标题在界面栈底; 存读档窗打开时转给它)
func ui_action(a: UiAction) -> bool:
	if _save_win:
		var k := a.camp_key()
		if k != "" and not (a.echo and k in ["accept", "cancel"]):
			_save_win.key(k)
		return true
	if _busy or (a.echo and not a.is_dir()):
		return true
	if not _menu_shown:
		if a.is_confirm() or a.is_cancel() or a.is_dir():
			_show_menu()
		return true
	if a.is_dir():
		var d := 1 if a.kind in [UiAction.DOWN, UiAction.RIGHT] else -1
		selection = posmod(selection + d, ITEM_COUNT)
		_update()
	elif a.is_confirm():
		_confirm()
	return true


func _confirm() -> void:
	match selection:
		0:
			if _clock - _shown_at < NEW_GAME_GUARD and not Game.fast:
				return  # 原版: 出现不足 1 秒时忽略 (GameTitleInput.cs:448-451)
			_busy = true
			Game.new_game()
		1:
			# 原版 实测: 没有任何存档时「前历再续」照样打开 5 个空档位的读档窗 (空档确认无反应, 取消返回), 不是无反应
			_busy = true
			var ui := UiLayer.new(30)
			add_child(ui)
			_save_win = CampSaveWindow.new(false)
			ui.add(_save_win)
			_save_win.open()
			var slot: int = await _save_win.picked
			_save_win = null
			if slot >= 0 and await Game.load_game(slot):
				return
			ui.queue_free()
			_busy = false
		2:
			if GameSaves.has_battle_save():
				_busy = true
				if not await Game.load_battle():  # 读不了 (存录损坏/内容包不兼容): Game 已弹提示, 标题要恢复可操作, 否则输入全被 _busy 吞掉
					_busy = false
			else:
				print("没有战阵存录")
		3: Game.quit_game()
		_: print("尚未实现: ", _item(selection))

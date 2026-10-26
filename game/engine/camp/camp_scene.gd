# SPDX-License-Identifier: GPL-3.0-only
extends Node2D
## 营地 (原版 CCampProcessor / CCampMenu):
##   背景为内容包 camps/camps.json 里营地 Game.state.camp_no (进度值, 关卡结束/城镇 0x29 给出) 的 background_anim (原版 Camp/Image/campNN, NN 来自 CAMPnn.DAT)。
##   左上主菜单 7 项 (game/engine/ui/camp/camp_menu.gd): 囊内乾坤 诸物炼化 体态观览 五魂化蕴 今况记入 前历再续 空明流转。
##   各子页面都在 game/engine/ui/camp/ 下, 按原版素材与对照原版坐标绘制, 对照。
## 原版流程:
##   主菜单 ↑/← 减 1、↓/→ 加 1 循环; 确认进入子页面 (主菜单收起, 退出子页面后再滑入);
##   第 6 项「空明流转」问「是否返回到标头画面？」, 是则回标题; 取消键问「确定要准备出发了吗？」, 是才离开营地。问句默认✗。
## 锚点: 背景按安全区居中; 主菜单贴左上 (CampMenu.ui_anchor); 各子页面是成组的窗口, 整页按安全区居中。
## 本场景把统一输入层的动作翻译成按键名传给当前页面 (页面类不读输入): up down left right accept cancel tab space space_up。
## 测试参数 (-- 之后): --camp-hold-space 空格按下后不因松开而关闭装备预览 (自动截图用)。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

const SceneShow := preload("res://engine/ui/scene_show.gd")

var camp := 0
var town := -1
var town_pos := 0
var ui: UiLayer
var menu: CampMenu
var _top: Node          # 当前接收按键的页面
var _busy := false
var _hold_space := false


func _ready() -> void:
	_hold_space = gc.debug.camp_hold_space
	scale = Vector2.ONE * Assets.SCALE
	ScreenLayout.bind_node(self, ScreenLayout.SAFE)
	var info: Dictionary = Content.camp(gc.state.camp_no if gc.state.camp_no >= 0 else gc.state.stage)
	camp = int(info.get("background", 0))
	town = int(info.get("town", -1))
	town_pos = int(info.get("town_entry", 0))
	var spec = info.get("background_show")  # 背景走通用场景演出 (旧内容包只有 background_anim: 整段循环)
	if not SceneShow.valid(spec) and info.get("background_anim") != null:
		spec = {"anim": info["background_anim"], "loop": [0, -1]}
	if SceneShow.valid(spec):
		var bg: Node2D = SceneShow.new(spec)
		add_child(bg)
		bg.enter(true)
	ScreenLayout.mirror_edges(self)  # 宽屏两侧镜像铺满
	ui = UiLayer.new(20)
	add_child(ui)
	menu = CampMenu.new()
	ui.add(menu)
	menu.chosen.connect(_choose)
	menu.cancelled.connect(_depart)
	menu.open()
	_top = menu
	InputRouter.push(self)
	print("营地 camp%02d, 离开去向: %s" % [camp, ("城镇 %d" % town) if town >= 0 else ("第 %d 关" % gc.state.next_stage)])
	RegressLog.checkpoint("camp_enter", {"camp": gc.state.camp_no})
	if gc.fast:  # 自动测试: 五魂点数平均分配后出发
		for uid in CampInventory.party_uids():
			var g: Dictionary = gc.state.party[uid]
			while int(g.get("spirit_points", 0)) > 0:
				var low := ""
				for k in g["spirit"]:
					if low == "" or int(g["spirit"][k]) < int(g["spirit"][low]):
						low = k
				g["spirit"][low] = int(g["spirit"][low]) + 1
				g["spirit_points"] = int(g["spirit_points"]) - 1
		await get_tree().create_timer(1.0).timeout
		_busy = true
		await gc.flow.leave_camp(town, town_pos)


# ---------------- 输入 ----------------

## 统一输入层 (InputRouter): 动作 -> 页面按键名 (UiAction.camp_key)。原版菜单不连发, 只有列表上下按住连移。
## --camp-hold-space: 松开空格不关闭装备预览 (自动截图用)。鼠标/触摸见 ui_pointer_target。
func ui_action(a: UiAction) -> bool:
	if _busy or _top == null:
		return true
	var k := a.camp_key()
	if k == "" or (a.echo and not a.is_dir()):
		return true
	if k == "space_up" and _hold_space:
		return true
	_top.key(k)
	return true


## 界面连发间隔: 转给当前页面 (见 KeyRepeat / InputRouter._repeat_interval)
func repeat_interval(kind: int) -> float:
	if _top != null and _top.has_method("repeat_interval"):
		return _top.repeat_interval(kind)
	return KeyRepeat.REPEAT


## 指针: 交给当前页面的命中矩形 (InputRouter -> UiHit, 悬停 = 选中项跟随, 点按 = 选中并确认)
func ui_pointer_target() -> Object:
	return null if _busy else _top


# ---------------- 主菜单 ----------------

## 主菜单收起, 打开子页面; 子页面发出 closed 后删掉并滑回主菜单
func _push(page: Node2D, close_signal: Signal) -> void:
	menu.close()
	ui.add(page)
	if page.has_method("open"):
		page.open()
	_top = page
	await close_signal
	page.queue_free()
	_back_to_menu()


func _back_to_menu() -> void:
	_top = menu
	menu.open()


func _choose(i: int) -> void:
	match i:
		0:
			var w := CampItemWindow.new(CampInventory.new())
			_push(w, w.closed)
		1:
			var f := CampForgeWindow.new(CampInventory.new())
			_push(f, f.closed)
		2:
			var party := CampInventory.party_uids()
			if party.is_empty():
				return
			var p := UiProfile.new(party)
			_push(p, p.closed)
		3:
			var party := CampInventory.party_uids()
			if party.is_empty():
				return
			var s := CampSpirit.new(party)
			s.guide_requested.connect(func(uid: int): GuidePanel.open_chapter(self, gc, InputRouter, "spirit_%d" % uid))
			_push(s, s.closed)
		4, 5:
			var saving := i == 4
			var w := CampSaveWindow.new(saving)
			menu.close()
			ui.add(w)
			w.open()
			_top = w
			var slot: int = await w.picked
			if slot >= 0 and saving:
				gc.flow.save_game(slot)
			if slot >= 0 and not saving:
				_busy = true
				if await gc.flow.load_game(slot):
					return
				_busy = false
			w.queue_free()
			_back_to_menu()
		6:
			if await _ask(UiStrings.t("camp.ask.back_title")):
				_busy = true
				await gc.flow.return_to_title()


## 主菜单取消键: 准备出发
func _depart() -> void:
	if await _ask(UiStrings.t("camp.ask.depart")):
		_busy = true
		await gc.flow.leave_camp(town, town_pos)


## 问句框 (主菜单收起), 返回是否选「是」
func _ask(text: String) -> bool:
	menu.close()
	var q := CampAsk.Question.new(text)
	ui.add(q)
	_top = q
	var yes: bool = await q.done
	q.queue_free()
	if not yes:
		_back_to_menu()
	else:
		_top = null
	return yes

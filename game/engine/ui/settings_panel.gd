# SPDX-License-Identifier: GPL-3.0-only
class_name SettingsPanel
extends CanvasLayer
## F10 设定面板。项目、取值、说明来自 engine/settings/settings_schema.gd (SettingsSchema.ROWS), 版式来自布局表 settings.*,
## 文字走统一排版 UiText, 面板里没有写死的坐标。改了就生效并存盘 (SettingsSchema.set_value), 没有「保存/放弃」:
##   上下选行 (到头循环)   左右调整 (音量 ±1 / 选项循环)   确认 / 取消 / 右键 / 点面板外 = 关闭
##   底部两个按钮: 「还原预设」把全部项恢复缺省 (立即存盘, 命令行临时值一并清掉), 「完成」关闭 (鼠标、触摸用)。
##   项目比版面行数多时是滚动列表: 一次显示 visible_rows() 行 (布局表 settings.row 的 repeat.count), 选中项带着列表滚动, 过长的一侧画 ▲▼ 提示。
##   动作行 (kind action, 如「手柄按键设置」): 没有值, 确认键打开子界面。
##   live 行 (回放速度, 仅回放中): 值取自运行中的回放, 左右调、立即生效、不存盘。
## 指针 (engine/ui/ui_hit.gd): 值栏左半点 = 减、右半点 = 加, 点按钮 = 确认, 悬停选行; 手柄走同一套动作。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)
var router = InputRouter                     # 统一输入层 (测试可换成独立实例)

signal closed(save: bool)

const Body := preload("res://engine/ui/settings_body.gd")

var _origin: Node2D          # 面板左上角 (原版坐标), 布局表里 settings.* 的 pos 相对它
var _body: Node2D
var _rows: Array[UiText] = []
var _values: Array[UiText] = []
var _buttons: Array[UiText] = []
var _desc: UiText
var _sel := 0            # 选中的条目 (0.._n-1 设定项, _n / _n+1 两个按钮)
var _top := 0            # 列表第一个可见条目
var _group := ""              # 二级菜单: 只列 SettingsSchema 里 group 相同的行 ("" = 主菜单; 「控制器」= controls); 标题 settings.<组>.title, 「还原预设」只复位本组
var _n := SettingsSchema.shown_rows().size()  # 设定项数; 之后是「还原预设」「完成」两个按钮行 (二级菜单在 open 里按本组重算)
var _vis := visible_rows()
var _sort_msg := ""          # 「整理行囊」的结果提示, 临时换掉这一行的值文字约 2 秒
var _sort_flash := 0         # 提示的代号 (旧提示的复位计时不能盖掉新提示)


## 一屏能放几行 (布局表 settings.row 的重复数)
static func visible_rows() -> int:
	var rep = UiLayout.val("settings.row", "repeat", {})
	return maxi(1, int(rep.get("count", 11))) if rep is Dictionary else 11


## 条目总数 (设定项 + 两个按钮)
func total() -> int:
	return _n + 2


## 条目 e 在屏幕上的行位置 (不可见返回 -1)
func slot_of(e: int) -> int:
	var s := e - _top
	return s if s >= 0 and s < _vis else -1


func _scroll_to_sel() -> void:
	_top = scroll_top(_sel, _top, _vis, total())


## 列表滚动: 选中项 sel 不在 [top, top+vis) 内就把窗口挪到刚好露出它; 夹在合法范围 (PadMapPanel 共用)
static func scroll_top(sel: int, top: int, vis: int, total_n: int) -> int:
	if sel < top:
		top = sel
	elif sel >= top + vis:
		top = sel - vis + 1
	return clampi(top, 0, maxi(0, total_n - vis))


func _ready() -> void:
	layer = 54
	ScreenLayout.bind_layer(self, UiLayout.anchor("settings.panel", ScreenLayout.SAFE))


## 本面板列的行 (主菜单或某个二级菜单)
func _srows() -> Array:
	return SettingsSchema.shown_rows(_group)


## 打开并等到关闭 (改动当场生效并存盘, 没有「保存/放弃」: 确认、取消、点面板外都只是关闭)
func open() -> bool:
	if _group == "":
		FrameStats.freeze()   # 冻结打开菜单之前玩的那段帧耗时, 画质诊断页读它 (不混进菜单自己的帧)
	_n = _srows().size()
	_body = Body.new()
	_build("settings.title" if _group == "" else "settings.%s.title" % _group, "")
	_update()
	router.push(self, true)  # 模态浮层: 之后下层 (对白、选择框) 再入栈也抢不走输入
	await closed
	router.pop(self)
	if _group == "":
		FrameStats.unfreeze()
	queue_free()
	return true


## 搭面板框架 (PadMapPanel 共用): 整屏压暗的模态底、原版坐标根与面板原点、底图 _body、标题与提示、每个版面行一套行名/值/按钮文字、说明
func _build(title_key: String, hint_key: String) -> void:
	var dim := ColorRect.new()  # 模态: 整屏压暗, 面板之外的点击不传给下层, 也不关闭 (只有取消键/右键/按钮能关)
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	ScreenLayout.cover(dim, 2048.0)
	var root := Node2D.new()
	root.scale = Vector2.ONE * Assets.SCALE
	add_child(root)
	_origin = Node2D.new()
	_origin.position = UiLayout.pos("settings.panel")
	root.add_child(_origin)
	_body.panel = self
	_origin.add_child(_body)
	_origin.add_child(UiText.make("settings.title", UiStrings.t(title_key)))
	if hint_key != "":   # 设定面板自己不要提示行 (2026-10-07); 手柄子面板仍有
		_origin.add_child(UiText.make("settings.hint", UiStrings.t(hint_key)))
	for i in _vis:  # 每个版面行一套: 行名、值、按钮文字 (按当前条目种类显示其一)
		var t := UiText.make("settings.row", "", i)
		_origin.add_child(t)
		_rows.append(t)
		var v := UiText.make("settings.value", "", i)
		_origin.add_child(v)
		_values.append(v)
		var b := UiText.make("settings.button", "", i)
		_origin.add_child(b)
		_buttons.append(b)
	_desc = UiText.make("settings.desc")
	_origin.add_child(_desc)


func _update() -> void:
	_scroll_to_sel()
	var sel_c := UiLayout.color("settings.sel_color", Color8(255, 224, 116))
	var dim_c := UiLayout.color("settings.dim_color", Color8(170, 160, 140))
	for s in _vis:
		var e := _top + s
		var on := e < total()
		var is_btn := on and e >= _n
		var is_row := on and e < _n
		_rows[s].visible = is_row
		_values[s].visible = is_row
		_buttons[s].visible = is_btn
		var c := sel_c if e == _sel else dim_c
		if is_btn:
			_buttons[s].text = UiStrings.t("settings.button.reset" if e == _n else "settings.button.done")
			_buttons[s].color = c
		elif is_row:
			var r: Dictionary = _srows()[e]
			_rows[s].text = SettingsSchema.label_of(r)
			_rows[s].color = c
			_values[s].color = c
			match r["kind"]:
				"volume": _values[s].text = ""
				"action": _values[s].text = _sort_msg if (r["key"] == "bag_sort" and _sort_msg != "") else UiStrings.t("settings.%s.value" % r["key"])
				"live": _values[s].text = SettingsSchema.text_of(r["key"], SettingsSchema.live_value(r["key"]))
				_: _values[s].text = SettingsSchema.text_of(r["key"], gc.settings[r["key"]])
	if _sel < _n:
		var rs: Dictionary = _srows()[_sel]
		_desc.text = SettingsSchema.row_desc(rs) if (rs["kind"] == "action" or rs["kind"] == "live") else SettingsSchema.desc_of(rs["key"], gc.settings[rs["key"]])
		if rs["key"] == "hq":
			_desc.text += _hq_note(int(gc.settings["hq"]))
	else:
		_desc.text = UiStrings.t("settings.desc.reset" if _sel == _n else "settings.desc.done")
	_body.queue_redraw()


## 「贴图精度」要重启才生效: 选的倍数 (自动取当前自动值) 与正在跑的倍数不同时, 说明后面补一句当前实际倍数 (数据取自 GameContext.diag_info, 没有就不提示)
func _hq_note(want: int) -> String:
	if not gc.diag_info.is_valid():
		return ""
	var info: Dictionary = gc.diag_info.call()
	var run := int(info.get("hq_scale", 0))
	if want == 0:
		want = int(info.get("auto_scale", run))
	return "" if run == 0 or run == want else " " + UiStrings.t("settings.hq.running", [run])


func _change(d: int) -> void:
	if _sel >= _n or _srows()[_sel]["kind"] == "action":
		return
	var k: String = _srows()[_sel]["key"]
	if _srows()[_sel]["kind"] == "live":   # 回放速度: 直接改运行中的回放, 不进设定文件
		SettingsSchema.set_live(k, SettingsSchema.step(k, SettingsSchema.live_value(k), d))
		if not _rows.is_empty():
			_update()
		return
	SettingsSchema.set_value(gc, k, SettingsSchema.step(k, gc.settings[k], d))   # 校验 → 生效 → 存盘 (换手柄预设连带清逐键自定义)
	for t in _rows + _values + _buttons + [_desc]:  # 字体设定即时重画本面板
		t.queue_redraw()
	_update()


# ---------------------------------------------------------------- 指针 / 输入

func ui_hits() -> Array:
	var out: Array = []
	var vr := UiLayout.rect("settings.value", 0)
	var rr := UiLayout.rect("settings.row", 0)
	var half := vr.size.x / 2.0
	var pad := UiLayout.num("settings.hit", "pad", 4)      # 行命中区左缘比文字多出的宽度
	var gap := UiLayout.num("settings.hit", "gap", 20)     # 行名命中区右缘到数值框的距离
	var arw := UiLayout.num("settings.hit", "arrow_w", 16) # 数值框左右各外扩 (小三角所在)
	for s in _vis:
		var e := _top + s   # 命中区的 index 是条目号 (不是版面行号), 滚动后仍指向同一项
		if e >= total():
			break
		var y := UiLayout.at("settings.row", s).y - 1.0
		var x0 := rr.position.x - pad
		if e >= _n:
			out.append(UiHit.area(Rect2(x0, y, UiLayout.size_of("settings.button").x, rr.size.y), e, _origin))
			continue
		if _srows()[e]["kind"] == "action":   # 动作行: 整行点按 = 确认 (打开子界面)
			out.append(UiHit.area(Rect2(x0, y, vr.position.x + vr.size.x + arw - x0, rr.size.y), e, _origin))
			continue
		out.append(UiHit.area(Rect2(x0, y, vr.position.x - gap - x0, rr.size.y), e, _origin, UiAction.NONE))
		out.append(UiHit.area(Rect2(vr.position.x - arw, y, arw + half, rr.size.y), e, _origin, UiAction.LEFT))
		out.append(UiHit.area(Rect2(vr.position.x + half, y, half + arw, rr.size.y), e, _origin, UiAction.RIGHT))
	return out


func ui_select(i) -> void:
	_sel = int(i)
	_update()


func ui_outside_action() -> int:
	return UiAction.CANCEL  # 点面板外 = 关闭 (改动早已生效并存盘, 没有可丢的; 触屏靠它退出)


func ui_action(a: UiAction) -> bool:
	if a.echo:
		return true
	match a.kind:
		UiAction.DOWN: _sel = posmod(_sel + 1, total())
		UiAction.UP: _sel = posmod(_sel - 1, total())
		UiAction.LEFT, UiAction.PAGE_UP: _change(-1)
		UiAction.RIGHT, UiAction.PAGE_DOWN: _change(1)
		UiAction.CONFIRM, UiAction.SELECT:
			if _sel == _n:
				if _group == "":
					SettingsSchema.reset_all(gc)
				else:
					SettingsSchema.reset_group(gc, _group)
			elif _sel < _n and _srows()[_sel]["kind"] == "action":
				_activate(String(_srows()[_sel]["key"]))
			else:
				closed.emit(true)
		UiAction.CANCEL: closed.emit(true)
	if is_inside_tree():
		_update()
	return true


## 整理公共行囊: CampInventory.resort_bag (营地/城镇的行囊窗口开着时同步排它手里的副本, 窗口在菜单/问句/炼化选材等半截操作时拒绝)。
## 结果 (已整理 N 格 / 已是顺序 / 先关掉菜单) 显示在本行的值上约 2 秒
func _sort_bag() -> void:
	var r := CampInventory.resort_bag(gc)
	if r["ok"] and int(r["moved"]) > 0:
		PlayLog.note_bag_sort()   # 浮层里的输入不进录像, 整理要单独记一条, 回放才对得上之后按格下标的操作
	var key := "settings.bag_sort.busy" if r["busy"] else ("settings.bag_sort.done" if int(r["moved"]) > 0 else "settings.bag_sort.same")
	_sort_msg = UiStrings.t(key, [int(r["moved"])]) if key == "settings.bag_sort.done" else UiStrings.t(key)
	_sort_flash += 1
	var mine := _sort_flash
	get_tree().create_timer(2.0).timeout.connect(func():
		if mine == _sort_flash:
			_sort_msg = ""
			if is_inside_tree() and not _rows.is_empty():
				_update())
	if is_inside_tree():
		_update()


## 动作行被确认: bag_sort = 整理行囊 (就地执行, 不开子面板); key_edit = 键盘按键设置 (engine/ui/key_map_panel.gd, 同手柄那个); pad_edit = 手柄按键设置 (模态子面板, 压在本面板之上; 每次绑定自己存盘, 取消时它自己还原覆盖项);
## SettingsSchema.GROUPS (声音 / 显示 / 控制器) = 二级菜单 (本类的另一个实例, 只列同组的行); guide = 攻略面板 (engine/ui/guide_panel.gd, 关掉后回到设定面板); diag = 画质诊断页 (engine/ui/diag_panel.gd, 点任意处返回);
## replay = 录像列表 (engine/ui/replay_panel.gd): 选定后关掉本面板, 下一帧经 SceneFlow.start_replay 切到回放;
## replay_stop = 结束回放 (关掉本面板, 经 SceneFlow.stop_replay 回标题)
func _activate(key: String) -> void:
	if key == "bag_sort":
		_sort_bag()
		return
	if key == "replay_stop":
		gc.flow.stop_replay.call_deferred()   # 等本面板关闭流程走完 (浮层出栈) 再切
		closed.emit(true)
		return
	var sub: Node
	if SettingsSchema.GROUPS.has(key):   # 二级菜单: 同一个面板类, 只列该组的行 (声音 = 音乐 / 音效; 图像显示 = 窗口模式 / 分辨率 / 贴图精度 / 画质诊断; 控制器设置 = 键盘 / 手柄)
		var cp := SettingsPanel.new()
		cp._group = key
		cp.router = router
		sub = cp
	match key:
		"pad_edit":
			sub = PadMapPanel.new()
		"key_edit":
			sub = KeyMapPanel.new()
		"guide":
			sub = GuidePanel.new()
			sub.router = router
		"replay":
			sub = ReplayPanel.new()
			sub.router = router
		"diag":
			sub = DiagPanel.new()
			sub.router = router
		_:
			if sub == null:
				return
	sub.gc = gc
	get_parent().add_child(sub)   # 兄弟节点而不是子节点: 下面把本面板藏起来时不能连子面板一起藏
	visible = false   # 子面板整屏盖在上面: 本面板先藏起来, 否则两层半透明底会让下层文字透上来
	var ok = await sub.open()
	if key == "replay" and ok:
		gc.flow.start_replay.call_deferred(sub.chosen_path, sub.chosen_speed)
		closed.emit(true)
		return
	visible = true
	if is_inside_tree():
		_update()

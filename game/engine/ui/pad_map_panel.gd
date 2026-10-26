# SPDX-License-Identifier: GPL-3.0-only
class_name PadMapPanel
extends SettingsPanel
## 手柄按键设置 (设定面板「手柄按键设置」行打开的模态子面板, 设计见 docs/设计_输入映射与战场辅助.md §2.4)。
## 继承 SettingsPanel: 共用框架 (压暗底、面板、行/值/按钮文字、滚动列表) 与 settings.* 布局表元素, 只换条目: 每个逻辑动作一行
## (行名 = 动作名, 值 = 当前绑的手柄键), 之后「恢复预设」「完成」两个按钮 (_n = 动作数, 按钮在它之后)。
##   上下选行   确认 = 开始改键 (「按下手柄键…」, 之后第一个手柄键即绑定; 取消键 / 5 秒无输入放弃)
##   「恢复预设」清掉全部逐键覆盖, 「完成」保留并返回; 取消键 (不在改键中) = 还原进入前的覆盖项并返回。
## 绑定只存与当前预设不同的项 (settings["pad_map"], 稀疏), 每次绑定即时生效并存盘 (SettingsSchema.set_value → InputRouter.set_pad)。
## 关闭信号沿用基类 closed(save): true = 保留改动, false = 已还原。

const CAPTURE_TIMEOUT := 5.0

var _saved := {}          # 进入时的覆盖项 (取消还原)
var _capturing := ""      # 正在为哪个动作等待按键 ("" = 没在改键)
var _cap_t := 0.0
var _joy_name := ""


func _init() -> void:
	_n = PadMap.ACTIONS.size()


func capturing() -> String:
	return _capturing


## 子类 (KeyMapPanel) 换动作表与文案前缀: 行名 <前缀>.action.<动作>、说明 <前缀>.desc.<动作>、标题 <前缀>.title 等
func actions() -> Array:
	return PadMap.ACTIONS


func txt() -> String:
	return "pad"


## 动作 e 当前绑的键名 (改过的加 *)
func value_text(e: int) -> String:
	var a: String = PadMap.ACTIONS[e]
	var eff := PadMap.effective(String(gc.settings["pad_preset"]), gc.settings["pad_map"])
	var t := PadMap.button_name(int(eff[a]), _joy_name)
	return t + " *" if (gc.settings["pad_map"] as Dictionary).has(a) else t


func begin() -> void:
	_saved = (gc.settings["pad_map"] as Dictionary).duplicate()


## 把动作 action 绑到键 b: 与预设默认键相同则删覆盖项; 整个字典替换 (不原地改, 设定面板取消时按拷贝还原)
func bind(action: String, b: int) -> void:
	var m: Dictionary = (gc.settings["pad_map"] as Dictionary).duplicate()
	if b == int(PadMap.preset_map(String(gc.settings["pad_preset"]))[action]):
		m.erase(action)
	else:
		m[action] = b
	SettingsSchema.set_value(gc, "pad_map", m)


func reset_all() -> void:
	SettingsSchema.set_value(gc, "pad_map", {})


func cancel_changes() -> void:
	SettingsSchema.set_value(gc, "pad_map", _saved.duplicate())


# ---------------------------------------------------------------- 改键

func start_capture(action: String) -> void:
	_capturing = action
	_cap_t = 0.0
	router.pad_capture = Callable(self, "_on_captured")


func end_capture() -> void:
	_capturing = ""
	router.pad_capture = Callable()


func _on_captured(b: int) -> void:
	if _capturing != "":
		bind(_capturing, b)
	end_capture()
	if is_inside_tree():
		_update()


## 改键等待计时 (_process 每帧调); 超时放弃
func tick_capture(delta: float) -> void:
	if _capturing == "":
		return
	_cap_t += delta
	if _cap_t >= CAPTURE_TIMEOUT:
		end_capture()
		if is_inside_tree():
			_update()


func _process(delta: float) -> void:
	tick_capture(delta)


# ---------------------------------------------------------------- 界面

func _ready() -> void:
	super._ready()
	layer = 55   # 压在设定面板 (54) 之上


func ui_outside_action() -> int:
	return UiAction.NONE   # 模态: 点面板外不关闭 (取消 = 放弃本次改键, 误触会丢改动)


## 打开并等到关闭 (返回 true = 保留改动)
func open() -> bool:
	begin()
	var pads := Input.get_connected_joypads()
	_joy_name = Input.get_joy_name(pads[0]) if not pads.is_empty() else ""
	_body = Body.new()
	_build(txt() + ".title", txt() + ".hint")
	_update()
	router.push(self, true)
	var keep: bool = await closed
	end_capture()
	router.pop(self)
	if not keep:
		cancel_changes()
	queue_free()
	return keep


func _update() -> void:
	var acts := actions()
	var pre := txt()
	_scroll_to_sel()
	var sel_c := UiLayout.color("settings.sel_color", Color8(255, 224, 116))
	var dim_c := UiLayout.color("settings.dim_color", Color8(170, 160, 140))
	for s in _vis:
		var e := _top + s
		var is_btn := e >= _n and e < total()
		var is_row := e < _n
		_rows[s].visible = is_row
		_values[s].visible = is_row
		_buttons[s].visible = is_btn
		var c := sel_c if e == _sel else dim_c
		if is_btn:
			_buttons[s].text = UiStrings.t(pre + (".button.reset" if e == _n else ".button.done"))
			_buttons[s].color = c
		elif is_row:
			_rows[s].text = UiStrings.t(pre + ".action." + String(acts[e]))
			_rows[s].color = c
			_values[s].color = c
			_values[s].text = UiStrings.t(pre + ".capture") if _capturing == acts[e] else value_text(e)
	if _sel < _n:
		_desc.text = UiStrings.t(pre + ".capture.desc") if _capturing != "" else UiStrings.t(pre + ".desc." + String(acts[_sel]))
	else:
		_desc.text = UiStrings.t(pre + (".desc.reset" if _sel == _n else ".desc.done"))
	_body.queue_redraw()


func ui_hits() -> Array:
	var out: Array = []
	var rr := UiLayout.rect("settings.row", 0)
	var vr := UiLayout.rect("settings.value", 0)
	var pad := UiLayout.num("settings.hit", "pad", 4)
	for s in _vis:
		var e := _top + s
		if e >= total():
			break
		var y := UiLayout.at("settings.row", s).y - 1.0
		var x0 := rr.position.x - pad
		out.append(UiHit.area(Rect2(x0, y, vr.position.x + vr.size.x + 16.0 - x0, rr.size.y), e, _origin))
	return out


func ui_select(i) -> void:
	if _capturing != "":
		return
	_sel = int(i)
	_update()


func ui_action(a: UiAction) -> bool:
	if a.echo:
		return true
	if _capturing != "":   # 改键中: 手柄键由路由器捕获; 键盘/鼠标只认取消 (放弃), 其余吞掉
		if a.kind == UiAction.CANCEL:
			end_capture()
			if is_inside_tree():
				_update()
		return true
	match a.kind:
		UiAction.DOWN: _sel = posmod(_sel + 1, total())
		UiAction.UP: _sel = posmod(_sel - 1, total())
		UiAction.CONFIRM, UiAction.SELECT:
			if _sel < _n:
				start_capture(actions()[_sel])
			elif _sel == _n:
				reset_all()
			else:
				closed.emit(true)
		UiAction.CANCEL: closed.emit(false)
	if is_inside_tree():
		_update()
	return true


## 底图: 面板底板、边框、选中行光标、列表可滚动的 ▲▼ (版式同 settings_body.gd)
class Body:
	extends Node2D
	var panel: Node

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, UiLayout.size_of("settings.panel"))
		draw_rect(r, UiLayout.color(UiLayout.val("settings.panel", "color"), Color(0.04, 0.02, 0.01, 0.96)))
		var bc := UiLayout.color(UiLayout.val("settings.panel", "border"), Color8(150, 112, 52))
		draw_rect(r.grow(-0.5), bc, false, 1.0)
		draw_rect(r.grow(-2.5), Color(bc, 0.35), false, 1.0)
		var s: int = panel._sel - panel._top
		if s >= 0 and s < panel._vis:
			draw_rect(Rect2(UiLayout.at("settings.cursor", s), UiLayout.size_of("settings.cursor")),
				UiLayout.color(UiLayout.val("settings.cursor", "color")))
		var ac := UiLayout.color(UiLayout.val("settings.arrow", "color"))
		var rr := UiLayout.rect("settings.row", 0)
		var cx := UiLayout.size_of("settings.panel").x - 8.0
		if panel._top > 0:
			var y0 := rr.position.y + 1.0
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 3, y0 + 4), Vector2(cx + 3, y0 + 4), Vector2(cx, y0)]), ac)
		if panel._top + panel._vis < panel.total():
			var y1 := UiLayout.at("settings.row", panel._vis - 1).y + rr.size.y - 1.0
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 3, y1 - 4), Vector2(cx + 3, y1 - 4), Vector2(cx, y1)]), ac)

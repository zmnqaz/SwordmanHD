# SPDX-License-Identifier: GPL-3.0-only
extends Node
## 统一输入层 (autoload "InputRouter")。键盘、鼠标、触摸、手柄、自动测试注入的事件都在这里翻译成动作 UiAction,
## 交给「界面栈」栈顶的接收方; 界面与场景不再直接读按键 (docs/架构设计.md「输入」, 1、3)。
##
## 界面栈: 接收方用 push(self) 入栈、pop(self) 出栈 (节点被释放后自动出栈)。动作从栈顶往下传,
##   接收方实现 func ui_action(a: UiAction) -> bool, 返回 true 表示已处理 (模态界面总返回 true, 下层收不到)。
##   模态浮层 (push(self, true)) 恒在最上层: 它打开期间别的界面入栈只会插在它下面。
##
## 键位 (原版 P/InputManager.asset, 1.1; 扩展项标 *; 键盘除方向与 Esc / F10 外都可在设定里改, 见 KeyMap):
##   方向 ↑↓←→ / WASD (按住 0.5 秒后连发, KeyRepeat)    确认 Enter / 小键盘 Enter    空格 = SELECT (*营地/战场物品列表按住 = 装备效果预览, 其他画面同确认)
##   取消 Esc / C / Delete    查看 F    翻页 Q / E (PageUp / PageDown)    *设定 F1 (F10 同效)    *攻略 F2 (F4 同效)    *战场地图 M
##   *Tab = 营地/商店切换栏   (没有小键盘 +/− 选目标跳转: 2026-10-25 用户要求删掉)
##   *F3 跳过对白开关   *按住 Ctrl 快进对白 (攻略再按一次关闭)
##   手柄: 十字键与左摇杆方向固定; 其余键由 PadMap (engine/input/pad_map.gd) 决定: 标准预设 A 确认 B 取消 X 查看 Y 菜单 LB/RB 翻页
##   LT 切栏 R3 空格 (装备效果预览) Back 战场地图 Start 设定 L3 跳过对白; 「交换」预设 A/B 对调; 设定面板可逐键改 (set_pad)。
## 鼠标 (*): 移动 = POINT (光标/选中项跟随), 左键 = 确认 (点哪选哪), 右键 = 取消, 中键 = 查看, 滚轮 = 上/下。
##   界面组件只声明各选项的命中矩形, 悬停/点按/查看由这里统一换算成选中项与动作 (_pointer, engine/ui/ui_hit.gd)。
## 触摸 (*, 只在 Android/iOS 或 --touch 的触摸界面下): 点按 = 确认 (点哪选哪), 双指点按 = 取消, 长按 = 查看, 拖动 = 卷动,
##   左右快滑 = 翻页 (TouchGestures); 外加手游式虚拟键 (engine/input/touch_pad.gd: 左下圆形摇杆、右下两个一样大的确认/取消键、右上开关/设置钮)。
##   桌面永不显示虚拟键, 也不因收到触摸事件而切换 (远程桌面/触控板会发): 桌面上的触摸事件忽略, 由 Godot 模拟出的鼠标事件处理。
## 自动测试 (scripts/autotest.gd --press): InputEventAction 的 ui_accept / ui_cancel / ui_up... / ui_select / ui_focus_next,
##   或直接用动作名 confirm / cancel / info / menu / page_up / page_down / up ...
## 调试: --touch 用鼠标模拟触摸 (左键 = 一根手指, 右键 = 双指点按) 并显示虚拟键。

signal dispatched(a: UiAction)
signal settings_requested
signal speed_requested   # 手机加速钮: 弹出加速档位菜单
signal skip_dialog_toggled
signal guide_requested   # F4: 打开/关闭攻略面板 (组装层接, engine/ui/guide_panel.gd)

## 键盘方向键: 固定, 不可改绑 (其余键盘键由 KeyMap 决定, 可在设定面板「键盘按键设置」里改)
const DIR_KEYS := {
	KEY_UP: UiAction.UP, KEY_W: UiAction.UP, KEY_DOWN: UiAction.DOWN, KEY_S: UiAction.DOWN,
	KEY_LEFT: UiAction.LEFT, KEY_A: UiAction.LEFT, KEY_RIGHT: UiAction.RIGHT, KEY_D: UiAction.RIGHT,
}
## 十字键: 固定为方向 (不可改绑)
const JOY_DPAD := {
	JOY_BUTTON_DPAD_UP: UiAction.UP, JOY_BUTTON_DPAD_DOWN: UiAction.DOWN,
	JOY_BUTTON_DPAD_LEFT: UiAction.LEFT, JOY_BUTTON_DPAD_RIGHT: UiAction.RIGHT,
}
## 手柄逻辑动作 (PadMap.ACTIONS) -> UiAction; map / settings / skip_dialog 不是 UiAction, 在 _pad_action 里单独处理
const PAD_UI := {
	"confirm": UiAction.CONFIRM, "cancel": UiAction.CANCEL, "info": UiAction.INFO, "menu": UiAction.MENU,
	"page_up": UiAction.PAGE_UP, "page_down": UiAction.PAGE_DOWN, "switch": UiAction.SWITCH,
	"select": UiAction.SELECT,
}
## InputEventAction (自动测试注入、Godot 内置 ui_*) -> 动作
const ACTIONS := {
	"ui_up": UiAction.UP, "ui_down": UiAction.DOWN, "ui_left": UiAction.LEFT, "ui_right": UiAction.RIGHT,
	"ui_accept": UiAction.CONFIRM, "ui_cancel": UiAction.CANCEL, "ui_select": UiAction.SELECT,
	"ui_focus_next": UiAction.SWITCH, "ui_page_up": UiAction.PAGE_UP, "ui_page_down": UiAction.PAGE_DOWN,
}
## 有「松开」动作的键
const RELEASE := {UiAction.SELECT: UiAction.SELECT_UP, UiAction.INFO: UiAction.INFO_UP}
const STICK_DEADZONE := 0.5

## 触摸界面 (Android/iOS 或 --touch): 显示虚拟键, 触摸事件按手势处理
var touch_mode := false
## --touch: 鼠标按触摸处理
var emulate_touch := false
var repeat := KeyRepeat.new()
var gestures := TouchGestures.new()
var _stack: Array = []
var _overlays: Array = []   # _stack 里的模态浮层 (总在栈的上部)
var _time := 0.0
var _buttons: Node
## 触摸在竖排列表上拖动 = 滚动 (↑/↓ 步进, 同滚轮语义; _drag_list_step): 0 未判定, 1 列表, 2 不是 (交给界面自己的 DRAG, 如战场卷地图, 或横向快滑翻页)
var _drag_mode := 0
var _drag_pitch := 0.0      # 行距 (视口像素), 手指每拖过一行发一步
var _drag_acc := 0.0
var _button_touch := {}     # 手指 -> 按住的虚拟键动作 (这根手指的后续事件吞掉, 松开时松键; 摇杆是 TouchPad.STICK, 拖动时更新方向)
var _stick_dir := UiAction.NONE   # 摇杆当前按住的方向键 (UiAction.UP.. 或 NONE)
var _stick := Vector2i.ZERO
var _axes := {}
var _pad_table := PadMap.resolve(PadMap.DEFAULT_PRESET, {})   # 手柄键 -> [动作名]
var _key_table := KeyMap.resolve({})   # 键盘键 (可带 Shift) -> [动作名]
var _trig := {PadMap.TRIGGER_L: false, PadMap.TRIGGER_R: false}   # 扳机虚拟键是否按下
## 设定面板「手柄按键设置」捕获新键时设置: 有效时手柄键 (含扳机) 不当游戏动作, 只把可绑定键的键号交给它
## 最近收到的按键 / 手柄键原始事件 (新的在前, 至多 RECENT_MAX 条), 诊断页显示: 安卓掌机 (RP6 等) 的实体键有的报手柄键、有的报键盘键,
## 两个物理键报同一个键号就没法分开绑 —— 让玩家把「按了什么键、系统报了什么」原样发回来
const RECENT_MAX := 12
var recent_inputs: Array = []
var pad_capture := Callable()
## 设定面板「键盘按键设置」捕获新键时设置: 有效时键盘键 (除 Esc) 不当游戏动作, 只把可绑定键的键值交给它
var key_capture := Callable()
var _last_point := Vector2.INF
## 回放锁 (PlayLog 回放期间置位): 真实的键盘/鼠标/手柄/触摸不再进游戏, 免得混进回放的指令流打乱后面的操作;
## 只放行打开设定面板 (F10 / 手柄 Start / 触屏设置钮: 暂停、调速、结束回放)。设定面板开着时输入照常给面板 (回放此时冻结)
var replay_lock := false:
	set(v):
		replay_lock = v
		if v:   # 锁上之前按着的键/手指不能在回放里继续连发、续上手势
			repeat.clear()
			gestures = TouchGestures.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -50
	emulate_touch = DebugArgs.current().touch
	if emulate_touch or Platform.is_mobile():
		set_touch_mode(true)


# ---------------- 界面栈 ----------------

## overlay = true: 模态浮层 (F10 设定面板): 始终压在普通接收方之上。之后入栈的普通接收方 (对白框、选择框、场景切换……)
## 插到浮层下面, 不会把输入从浮层手里抢走; 浮层关闭后它们就是栈顶, 原界面状态不受影响。
func push(r: Object, overlay := false) -> void:
	_stack.erase(r)
	_overlays.erase(r)
	if overlay:
		_overlays.append(r)
		_stack.append(r)
		return
	var at := _stack.size()
	for i in _stack.size():
		if _stack[i] in _overlays:
			at = i
			break
	_stack.insert(at, r)


func pop(r: Object) -> void:
	_stack.erase(r)
	_overlays.erase(r)


## 有模态浮层打开 (下层界面的计时演出、自动翻页等应暂停)
func overlay_open() -> bool:
	_prune()
	return not _overlays.is_empty()


func top() -> Object:
	_prune()
	return _stack[-1] if not _stack.is_empty() else null


func has(r: Object) -> bool:
	return r in _stack


static func _alive(r) -> bool:
	return is_instance_valid(r) and not (r is Node and r.is_queued_for_deletion())


## 清掉已释放/排队释放的接收方。top()/dispatch/每帧指针轮询都会调, 先不分配地扫一遍, 有失效项才重建数组
func _prune() -> void:
	var dirty := false
	for r in _stack:
		if not _alive(r):
			dirty = true
			break
	if not dirty:
		for r in _overlays:
			if not _alive(r):
				dirty = true
				break
	if dirty:
		_stack = _stack.filter(_alive)
		_overlays = _overlays.filter(_alive)


## 把动作交给栈顶 (返回 false 的接收方让给下一层)。测试与屏幕按钮也直接调用。
## 指针动作 (带坐标的悬停/确认/查看) 先按接收方当前组件的命中矩形处理 (_pointer, engine/ui/ui_hit.gd)。
func dispatch(a: UiAction) -> bool:
	dispatched.emit(a)
	_prune()
	for i in range(_stack.size() - 1, -1, -1):
		var r: Object = _stack[i]
		if a.has_pos() and _pointer(r, a):
			return true
		if not r.has_method("ui_action"):
			continue
		if r.call("ui_action", a) != false:
			return true
	return false


## 指针 (鼠标/触摸) 的统一处理, 界面不写鼠标代码 (协议见 engine/ui/ui_hit.gd)。返回 true = 已处理完。
##   悬停: 命中 → 组件 ui_select(index)。点按: 命中 → ui_select(index) 后把该区的 action (默认确认) 交给接收方 ui_action;
##   点空处 → 组件的 ui_outside_action()。查看 (中键/长按): 先选中指针下的项, 再照常交给 ui_action。
func _pointer(r: Object, a: UiAction) -> bool:
	if not (r.has_method("ui_pointer_target") or r.has_method("ui_hits")):
		return false
	var t := UiHit.resolve(r)
	_track(t)
	if t == null:
		return false
	var confirm := a.is_confirm() and not a.echo
	if not (a.kind == UiAction.POINT or confirm or a.kind == UiAction.INFO):
		return false
	var h := UiHit.find(t, a.pos)
	a.hit = h.get("index")
	if not h.is_empty() and h["index"] != null and t.has_method("ui_select") and not (confirm and _guarded()):
		t.call("ui_select", h["index"])
	if a.kind == UiAction.POINT:
		if not h.is_empty():
			_pt_hovered = true
		return true
	if a.kind == UiAction.INFO:
		return false
	var k: int = UiAction.NONE
	if h.is_empty():
		k = int(t.call("ui_outside_action")) if t.has_method("ui_outside_action") else UiAction.NONE
	elif not _guarded():
		k = h["action"]
	if k != UiAction.NONE and r.has_method("ui_action"):
		var out := UiAction.new(k, a.source)
		out.hit = a.hit
		r.call("ui_action", out)
	return true


## 防误触 (UiHit.GUARD): 记录当前接收指针的组件何时出现、指针是否在它上面悬停命中过
var _pt_id := 0
var _pt_since := 0.0
var _pt_hovered := false


func _track(t: Object) -> void:
	var id := t.get_instance_id() if t != null else 0
	if id != _pt_id:
		_pt_id = id
		_pt_since = _time
		_pt_hovered = false


func _guarded() -> bool:
	return not _pt_hovered and _time - _pt_since < UiHit.GUARD


## 栈顶接收方当前的指针组件 (每帧跟踪, 供防误触计时)
func _poll_pointer_target() -> void:
	_prune()
	if _stack.is_empty():
		return
	var r: Object = _stack[-1]
	if r.has_method("ui_pointer_target") or r.has_method("ui_hits"):
		_track(UiHit.resolve(r))


## 当前按住的方向 (城镇行走用电平; 原版 getKey, 1.2)
func held_dir() -> Vector2i:
	return UiAction.DIRS.get(repeat.current(), Vector2i.ZERO)


## 按固定优先级取按住的方向 (order: UiAction.UP... 的先后); 都没按住返回 ZERO。
## 城镇行走用: 按 上 > 下 > 左 > 右 依次查 GetKeyState, 同时按住多个键时不看先后 (差异)
func held_dir_by_priority(order: Array) -> Vector2i:
	var h := repeat.held()
	for k in order:
		if k in h:
			return UiAction.DIRS[k]
	return Vector2i.ZERO


## 按住 Ctrl 快进对白 (扩展)
func fast_held() -> bool:
	return Input.is_key_pressed(KEY_CTRL)


func set_touch_mode(on: bool) -> void:
	touch_mode = on
	ScreenLayout.keep_side_margins = on  # 左右留边给虚拟键, 贴边的界面改贴安全区
	if on and _buttons == null:
		_buttons = load("res://engine/input/touch_pad.gd").new()
		add_child(_buttons)
	if _buttons:
		_buttons.visible = on


# ---------------- 事件翻译 ----------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		repeat.clear()
		if replay_lock:
			return
		for k in RELEASE:  # 失焦后收不到按键松开事件: 补发「松开」, 否则营地按住预览等会一直卡在按下状态
			dispatch(UiAction.new(RELEASE[k], "key"))


func _process(delta: float) -> void:
	_time += delta
	_poll_pointer_target()
	for k in repeat.tick(delta, _repeat_interval()):
		dispatch(UiAction.new(k, "key", Vector2.INF, true))
	for a in gestures.tick(_time):
		dispatch(a)


## 栈顶界面对当前按住方向的连发间隔 (界面可实现 repeat_interval(kind: int) -> float, 缺省 KeyRepeat.REPEAT)
func _repeat_interval() -> float:
	var h := repeat.current()
	if h == UiAction.NONE:
		return KeyRepeat.REPEAT
	var r: Object = top()
	if r != null and r.has_method("repeat_interval"):
		return maxf(float(r.call("repeat_interval", h)), KeyRepeat.REPEAT)
	return KeyRepeat.REPEAT


func _input(e: InputEvent) -> void:
	if _handle(e):
		get_viewport().set_input_as_handled()


## 处理一个原始事件, 返回是否吃掉
func _handle(e: InputEvent) -> bool:
	_note_recent(e)
	if replay_lock and not overlay_open() and not _replay_passes(e):
		return true   # 回放中: 吞掉真实输入
	if e is InputEventKey:
		return _key(e)
	if e is InputEventAction:
		return _action_event(e)
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		if not touch_mode:
			return false  # 桌面: 忽略, 交给模拟出的鼠标事件
		return _touch(e)
	if e is InputEventMouseButton or e is InputEventMouseMotion:
		if e.device == InputEvent.DEVICE_ID_EMULATION and touch_mode and not emulate_touch:
			return true  # 触摸模拟出的鼠标事件: 已按触摸处理
		return _mouse_as_touch(e) if emulate_touch else _mouse(e)
	if e is InputEventJoypadButton:
		if JOY_DPAD.has(e.button_index):
			if not pad_capture.is_valid():
				_press(JOY_DPAD[e.button_index], e.pressed, "pad")
			return true
		_pad_button(e.button_index, e.pressed)
		return true
	if e is InputEventJoypadMotion and e.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		var tb: int = PadMap.TRIGGER_L if e.axis == JOY_AXIS_TRIGGER_LEFT else PadMap.TRIGGER_R
		var now := PadMap.trigger_on(_trig[tb], e.axis_value)
		if now != _trig[tb]:   # 扳机过阈值当按键 (带迟滞), 与普通键走同一套绑定
			_trig[tb] = now
			_pad_button(tb, now)
		return true
	if e is InputEventJoypadMotion and e.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		_axes[e.axis] = e.axis_value
		var v := Vector2(_axes.get(JOY_AXIS_LEFT_X, 0.0), _axes.get(JOY_AXIS_LEFT_Y, 0.0))
		var s := Vector2i.ZERO
		if v.length() >= STICK_DEADZONE:  # 取主方向 (四向)
			s = Vector2i(signi(roundi(v.x)), 0) if absf(v.x) >= absf(v.y) else Vector2i(0, signi(roundi(v.y)))
		if s != _stick:
			for k in UiAction.DIRS:
				var on: bool = UiAction.DIRS[k] == s
				var was: bool = UiAction.DIRS[k] == _stick
				if on != was:
					_press(k, on, "pad")
			_stick = s
		return true
	return false


## 记一条原始按键事件 (只记按下, 不记连发 / 摇杆 / 触摸)
func _note_recent(e: InputEvent) -> void:
	var t := ""
	if e is InputEventKey and e.pressed and not e.echo:
		t = "key %s (keycode %d, physical %d) device %d" % [OS.get_keycode_string(e.keycode), e.keycode, e.physical_keycode, e.device]
	elif e is InputEventJoypadButton and e.pressed:
		t = "pad button %d (%s) device %d \"%s\"" % [e.button_index, PadMap.NAMES.get(e.button_index, "?"), e.device, Input.get_joy_name(e.device)]
	if t == "":
		return
	recent_inputs.push_front(t)
	if recent_inputs.size() > RECENT_MAX:
		recent_inputs.resize(RECENT_MAX)


## 回放锁开着时放行的真实输入: 只有能打开设定面板的那几个
func _replay_passes(e: InputEvent) -> bool:
	if e is InputEventKey:
		return "settings" in KeyMap.lookup(_key_table, e)
	if e is InputEventJoypadButton:
		return "settings" in _pad_table.get(e.button_index, [])
	if e is InputEventScreenTouch or e is InputEventMouseButton:
		return _pos_hits_settings(e.position)
	return false


func _pos_hits_settings(pos: Vector2) -> bool:
	return _buttons != null and _buttons.visible and _buttons.hit(pos) == _buttons.SETTINGS


func _key(e: InputEventKey) -> bool:
	if key_capture.is_valid() and e.keycode != KEY_ESCAPE:
		if e.pressed and not e.echo and not (e.keycode in KeyMap.MODIFIERS):
			var k: int = e.keycode | (KeyMap.SHIFT if e.shift_pressed else 0)
			if e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
				k |= KEY_MASK_CTRL   # 带了不能绑的修饰键: 交给面板按「不可绑定」处理
			key_capture.call(k)
		return true   # 改键中: 其余按键 (含松开) 一律吞掉, 不当游戏动作
	if DIR_KEYS.has(e.keycode):
		if e.echo:
			return true  # 系统自动重复不用, 连发由 KeyRepeat 控制
		_press(DIR_KEYS[e.keycode], e.pressed, "key")
		return true
	var names := KeyMap.lookup(_key_table, e)
	if names.is_empty():
		return false
	if e.echo:
		return true
	var swallow := false
	for name in names:
		swallow = _logic_action(String(name), e.pressed, "key") or swallow
	return swallow


## 换键盘映射 (设定变化时由 Game.apply_settings 调): overrides = {动作名: 键值} 逐项覆盖主键
func set_keys(overrides: Dictionary) -> void:
	_key_table = KeyMap.resolve(overrides)


## 换手柄映射 (设定变化时由 Game.apply_settings 调): preset 预设名, overrides = {动作名: 键号} 逐项覆盖
func set_pad(preset: String, overrides: Dictionary) -> void:
	_pad_table = PadMap.resolve(preset, overrides)


## 一个手柄键 (含扳机虚拟键) 按下/松开: 捕获中只回报键号, 否则按映射派发它绑定的动作
func _pad_button(b: int, pressed: bool) -> void:
	if pad_capture.is_valid():
		if pressed and PadMap.is_bindable(b):
			pad_capture.call(b)
		return
	for name in _pad_table.get(b, []):
		_pad_action(String(name), pressed)


func _pad_action(name: String, pressed: bool) -> void:
	_logic_action(name, pressed, "pad")


## 一个逻辑动作按下/松开 (键盘与手柄共用): UiAction 类的走界面栈, map / skip_dialog / guide 直接处理。
## 返回是否吃掉这个键: 只有「战场地图」没人接 (不在战场空闲态) 时返回 false, 让键盘事件继续往下走
func _logic_action(name: String, pressed: bool, src: String) -> bool:
	if PAD_UI.has(name):
		_press(PAD_UI[name], pressed, src)
		return true
	if not pressed:
		return true
	match name:
		"map": return open_battle_map()
		"settings": settings_requested.emit()
		"skip_dialog": skip_dialog_toggled.emit()
		"guide": guide_requested.emit()
	return true


## 战场地图 (原版 F2, 现默认 M): 问栈顶 ui_f2(); 返回是否有人处理 (手柄 Back 键同走这里)
func open_battle_map() -> bool:
	var t := top()
	return t != null and t.has_method("ui_f2") and bool(t.call("ui_f2"))


func _action_event(e: InputEventAction) -> bool:
	if String(e.action) == "toggle_skip_dialog":  # 自动测试: 同 F3
		if e.pressed:
			skip_dialog_toggled.emit()
		return true
	var k: int = ACTIONS.get(String(e.action), UiAction.NAMES.find(String(e.action)))
	if k <= UiAction.NONE:
		return false
	_press(k, e.pressed, "test" if e.device == 0 else "key")
	return true


## 按下 / 松开一个逻辑键
func _press(k: int, pressed: bool, src: String) -> void:
	if UiAction.DIRS.has(k):
		if pressed:
			for d in repeat.press(k):
				dispatch(UiAction.new(d, src))
		else:
			repeat.release(k)
		return
	if pressed:
		dispatch(UiAction.new(k, src))
	elif RELEASE.has(k):
		dispatch(UiAction.new(RELEASE[k], src))


func _mouse(e: InputEvent) -> bool:
	if e is InputEventMouseMotion:
		if e.button_mask == 0 and e.position != _last_point:
			_last_point = e.position
			dispatch(UiAction.new(UiAction.POINT, "mouse", e.position))
		return true
	var b := e as InputEventMouseButton
	match b.button_index:
		MOUSE_BUTTON_LEFT:
			if b.pressed:
				dispatch(UiAction.new(UiAction.CONFIRM, "mouse", b.position))
		MOUSE_BUTTON_RIGHT:
			if b.pressed:
				dispatch(UiAction.new(UiAction.CANCEL, "mouse", b.position))
		MOUSE_BUTTON_MIDDLE:
			dispatch(UiAction.new(UiAction.INFO if b.pressed else UiAction.INFO_UP, "mouse", b.position))
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if b.pressed:
				dispatch(UiAction.new(UiAction.UP if b.button_index == MOUSE_BUTTON_WHEEL_UP else UiAction.DOWN, "wheel", b.position))
		_:
			return false
	return true


## --touch: 左键 = 手指 0, 右键 = 双指点按 (取消)
func _mouse_as_touch(e: InputEvent) -> bool:
	if e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_touch_event(0, e.position, true, true)
		return true
	var b := e as InputEventMouseButton
	if b.button_index == MOUSE_BUTTON_LEFT:
		_touch_event(0, b.position, b.pressed, false)
	elif b.button_index == MOUSE_BUTTON_RIGHT and b.pressed:
		dispatch(UiAction.new(UiAction.CANCEL, "touch"))
	return true


func _touch(e: InputEvent) -> bool:
	if e is InputEventScreenDrag:
		_touch_event(e.index, e.position, true, true)
	else:
		_touch_event(e.index, e.position, e.pressed, false)
	return true


func _touch_event(index: int, pos: Vector2, pressed: bool, moved: bool) -> void:
	if _buttons:
		_buttons.touched()
	if _button_touch.has(index):  # 这根手指按在虚拟键上
		if not pressed:
			_release_button(_button_touch[index])
			_button_touch.erase(index)
		elif moved and _buttons != null and int(_button_touch[index]) == _buttons.STICK:
			_stick_update(pos)   # 摇杆: 手指拖到哪, 方向就跟到哪
		return
	var out: Array = []
	if moved:
		out = gestures.touch_move(index, pos, _time)
	elif pressed:
		var k := _hit_button(pos)
		if k != UiAction.NONE:
			_button_touch[index] = k
			return
		out = gestures.touch_down(index, pos, _time)
		_drag_mode = 0
		_drag_acc = 0.0
	else:
		out = gestures.touch_up(index, pos, _time)
	for a in out:
		if a.kind == UiAction.DRAG and _drag_list_step(a):
			continue
		dispatch(a)


## 触摸拖动落在竖排列表上 → 换算成 ↑/↓ 步进 (每拖过一行一步, 手指向上拖 = 选中项下移, 同手机列表手感); 返回 true = 已当列表滚动处理
## 判定在一次拖动的第一个事件做一次: 起点命中某个选项, 同一栏 (x 范围重叠) 里有 >= 2 个竖排选项, 主要是竖向拖动, 且不是格子型命中区 (战场地图自己卷镜头)。
## 行距取同栏相邻选项中心的竖向间距 (按节点全局变换换成视口像素), 所以各界面不用写任何拖动代码。
func _drag_list_step(a: UiAction) -> bool:
	if _drag_mode == 0:
		_drag_mode = 2
		_drag_pitch = _list_pitch(a.pos - a.delta, a.delta)
		if _drag_pitch > 0.0:
			_drag_mode = 1
	if _drag_mode != 1:
		return false
	_drag_acc += a.delta.y
	while absf(_drag_acc) >= _drag_pitch:
		var up := _drag_acc > 0.0   # 手指向下拖 = 内容下移 = 选中项上移
		_drag_acc -= _drag_pitch if up else -_drag_pitch
		dispatch(UiAction.new(UiAction.UP if up else UiAction.DOWN, "wheel", a.pos))
	return true


## 起点 start 所在竖排列表的行距 (视口像素); 不是竖排列表 (或横向拖) 返回 0
func _list_pitch(start: Vector2, first_delta: Vector2) -> float:
	if absf(first_delta.y) <= absf(first_delta.x):
		return 0.0
	_prune()
	if _stack.is_empty():
		return 0.0
	var r: Object = _stack[-1]
	if not (r.has_method("ui_pointer_target") or r.has_method("ui_hits")):
		return 0.0
	var t := UiHit.resolve(r)
	if t == null or _guarded():
		return 0.0
	var h := UiHit.find(t, start)
	if h.is_empty() or h["index"] == null or h["index"] is Vector2i or h["grid"] != Vector2.ZERO:
		return 0.0
	var col := _hit_center_and_span(t, h)
	var ys: Array = []
	for o in t.call("ui_hits"):
		if o["index"] == null or o["index"] is Vector2i or o["grid"] != Vector2.ZERO:
			continue
		var c := _hit_center_and_span(t, o)
		if c.is_empty() or absf(c["x"] - col["x"]) > maxf(col["w"], c["w"]) * 0.5:
			continue   # 不在同一栏
		ys.append(c["y"])
	ys.sort()
	var gaps: Array = []
	for i in range(1, ys.size()):
		var g: float = ys[i] - ys[i - 1]
		if g > 1.0:
			gaps.append(g)
	if gaps.is_empty():
		return 0.0
	gaps.sort()
	return float(gaps[gaps.size() / 2])


## 命中区在视口里的中心 (x, y) 与宽 w (节点全局变换换算); 节点不可见返回 {}
func _hit_center_and_span(t: Object, h: Dictionary) -> Dictionary:
	var n: CanvasItem = h["node"] if h["node"] != null else t as CanvasItem
	if n == null or not is_instance_valid(n) or not UiHit.shown(n):
		return {}
	var rect: Rect2 = h["rect"]
	var xf := n.get_global_transform_with_canvas()
	var c := xf * rect.get_center()
	return {"x": c.x, "y": c.y, "w": (xf.basis_xform(Vector2(rect.size.x, 0))).length()}


## 虚拟键: 命中则按下该键 (方向键按住连发, 松开时 _release_button), 返回其动作; 开关钮切换显示
func _hit_button(pos: Vector2) -> int:
	if _buttons == null or not _buttons.visible:
		return UiAction.NONE
	var k: int = _buttons.hit(pos)
	if k == UiAction.NONE:
		return k
	_buttons.press(k, true)
	if k == _buttons.TOGGLE:
		_buttons.toggle()
	elif k == _buttons.SETTINGS:
		settings_requested.emit()
	elif k == _buttons.SPEED:
		speed_requested.emit()
	elif k == _buttons.STICK:
		_stick_update(pos)
	else:
		_press(k, true, "button")
	return k


func _release_button(k: int) -> void:
	if _buttons:
		_buttons.press(k, false)
		if k == _buttons.STICK:
			_stick_release()
	if k > UiAction.NONE:
		_press(k, false, "button")


## 摇杆: 手指在 pos, 方向变了就松开旧方向键、按下新的 (方向键语义同键盘, 按住连发由 repeat 处理)
func _stick_update(pos: Vector2) -> void:
	var d: int = _buttons.stick_dir(pos)
	if d == _stick_dir:
		return
	if _stick_dir != UiAction.NONE:
		_press(_stick_dir, false, "button")
	_stick_dir = d
	if d != UiAction.NONE:
		_press(d, true, "button")


func _stick_release() -> void:
	if _stick_dir != UiAction.NONE:
		_press(_stick_dir, false, "button")
	_stick_dir = UiAction.NONE
	_buttons.stick_release()

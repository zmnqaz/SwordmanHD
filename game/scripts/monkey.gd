# SPDX-License-Identifier: GPL-3.0-only
class_name Monkey
extends RefCounted
## 猴子测试驱动 (QA): 固定随机种子往游戏里随机按键 / 点鼠标, 同时盯着卡死与内存增长。由 Autotest 在 --monkey= 时创建。
##   --monkey=<种子>:<总帧数>[:<换场景间隔帧>]   例 --monkey=7:20000:2500
##   --monkey-scenes=a,b,c      换场景候选 (名字同 --scene=, 默认 title,camp1,camp12,camp25,rpg0,rpg5,rpg14,stage0,stage1,stage10,stage20)
##   --monkey-rate=<N>          平均每 N 帧一个输入事件 (默认 2)
##   --monkey-actions=<a,b,..>  只用这些输入类型: act(统一输入层动作) key(真实按键) mouse(移动/点/滚轮) hold(按住) fn(F10/F3 等功能键) win(窗口大小/画面比例) setting(随机改一个设定项并立即应用: 画质/贴图倍数/字体/全屏/比例/窗口档/音量)
## 用 --fixed-fps 25 + --headless 跑 (同一种子同一启动参数基本可复现; 音频/贴图加载不影响游戏状态)。
## 输出 (stdout, 一行一条, 便于 grep):
##   MONKEY-STAT f=.. scene=.. stack=.. objs=.. nodes=.. orphans=.. mem=..MB    每 250 帧采样
##   MONKEY-HOP f=.. -> 场景名                                                   换场景
##   MONKEY-STUCK ...                                                             同一场景同一栈顶且游戏状态哈希长时间不变 (随后试 取消x30 恢复, 恢复不了再报 UNRECOVERED)
##   MONKEY-LEAK ...                                                              同一场景下节点数/孤儿节点数持续增长
##   MONKEY-DONE                                                                  正常跑完
## 脚本错误 / 断言不由本类捕获, 由外层 grep 日志里的 "SCRIPT ERROR|ERROR:|WARNING:"。

const STAT_EVERY := 250
const STUCK_FRAMES := 3000        # 输入一直在发而状态/栈顶不变这么多帧 = 疑似卡死
const KEYS := [
	KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE,
	KEY_ESCAPE, KEY_C, KEY_BACKSPACE, KEY_F, KEY_F1, KEY_Q, KEY_E, KEY_PAGEUP, KEY_PAGEDOWN, KEY_TAB, KEY_M, KEY_F2,
]
const ACTS := ["up", "down", "left", "right", "confirm", "cancel", "info", "menu", "page_up", "page_down", "switch", "select"]
const FN_KEYS := [KEY_F10, KEY_F3]
const DEFAULT_SCENES := ["title", "camp1", "camp12", "camp25", "rpg0", "rpg5", "rpg14", "stage0", "stage1", "stage10", "stage20"]

var rng := RandomNumberGenerator.new()
var total := 0
var hop := 0
var rate := 2
var scenes: Array = DEFAULT_SCENES.duplicate()
var kinds: Array = ["act", "key", "mouse", "hold", "fn", "win", "setting"]
var _frame := 0
var _held: Array = []         # [[释放帧, 键码或 "act:名字"]]
var _same_since := 0
var _last_sig := ""
var _recover_at := -1
var _scene_key := ""
var _nodes0: Array = []       # 当前场景内的节点数采样
var _stuck_reported := false
var autotest: Node


static func from_args(args: PackedStringArray, at: Node) -> Monkey:
	var m: Monkey
	for a in args:
		if a.begins_with("--monkey="):
			var p := a.trim_prefix("--monkey=").split(":")
			m = Monkey.new()
			m.autotest = at
			m.rng.seed = int(p[0])
			m.total = int(p[1]) if p.size() > 1 else 10000
			m.hop = int(p[2]) if p.size() > 2 else 0
	if m == null:
		return null
	Game.block_quit = true
	for a in args:
		if a.begins_with("--monkey-scenes="):
			m.scenes = Array(a.trim_prefix("--monkey-scenes=").split(","))
		elif a.begins_with("--monkey-rate="):
			m.rate = maxi(1, int(a.trim_prefix("--monkey-rate=")))
		elif a.begins_with("--monkey-actions="):
			m.kinds = Array(a.trim_prefix("--monkey-actions=").split(","))
	return m


## 每帧由 Autotest 调用; 返回 true = 该退出了
func tick(frame: int) -> bool:
	_frame = frame
	for h in _held.duplicate():
		if h[0] <= frame:
			_release(h[1])
			_held.erase(h)
	if hop > 0 and frame > 0 and frame % hop == 0:
		var sc: String = scenes[rng.randi() % scenes.size()]
		print("MONKEY-HOP f=%d -> %s" % [frame, sc])
		_release_all()
		Game.enter_test_scene(sc)
	elif rng.randi() % rate == 0:
		_random_event()
	if frame % STAT_EVERY == 0:
		_sample()
	if _frame >= total:
		_release_all()
		print("MONKEY-DONE f=%d" % frame)
		return true
	return false


func _scene_name() -> String:
	var c = Game.current
	return String(c.get_script().resource_path.get_file()) if c and c.get_script() else "none"


func _signature() -> String:
	var top = InputRouter.top()
	return "%s|%s|%s|%s" % [_scene_name(), top.get_instance_id() if top else 0, InputRouter._stack.size(), RegressLog.state_hash()]


func _sample() -> void:
	var sc := _scene_name()
	var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orph := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mem := OS.get_static_memory_usage() / 1048576.0
	print("MONKEY-STAT f=%d scene=%s stack=%d objs=%d nodes=%d orphans=%d mem=%.0fMB" % [_frame, sc, InputRouter._stack.size(), objs, nodes, orph, mem])
	# 卡死: 栈顶与状态哈希长时间不变
	var sig := _signature()
	if sig != _last_sig:
		_last_sig = sig
		_same_since = _frame
		_stuck_reported = false
		_recover_at = -1
	elif _frame - _same_since >= STUCK_FRAMES:
		if _recover_at < 0:
			print("MONKEY-STUCK f=%d scene=%s top=%s 已 %d 帧无变化, 试取消x30" % [_frame, sc, str(InputRouter.top()), _frame - _same_since])
			print("MONKEY-STUCK-STATE held=", InputRouter.repeat._held, " ", _dump_vars(Game.current), " top: ", _dump_vars(InputRouter.top()))
			for i in 30:
				InputRouter.dispatch(UiAction.of(UiAction.CANCEL))
			Engine.get_main_loop().root.print_tree_pretty()  # 卡死现场的节点树 (找挂住的对白/过场/菜单)
			_recover_at = _frame
			_same_since = _frame - STUCK_FRAMES + 500  # 再给 500 帧
		elif not _stuck_reported:
			print("MONKEY-STUCK-UNRECOVERED f=%d scene=%s top=%s" % [_frame, sc, str(InputRouter.top())])
			push_error("MONKEY: 卡死无法恢复 scene=%s" % sc)
			_stuck_reported = true
	# 泄漏: 同一个场景里节点数一路涨 (每次换场景重新计)
	if sc != _scene_key:
		_scene_key = sc
		_nodes0 = []
	_nodes0.append([nodes, orph])
	if _nodes0.size() >= 24 and _nodes0.size() % 8 == 0:
		var a: Array = _nodes0[_nodes0.size() - 24]
		var b: Array = _nodes0[-1]
		var mono := true
		for i in range(_nodes0.size() - 24, _nodes0.size() - 1):
			if _nodes0[i + 1][0] < _nodes0[i][0] - 2:
				mono = false
				break
		if mono and b[0] - a[0] > 400:
			print("MONKEY-LEAK f=%d scene=%s 节点数 %d -> %d (近 %d 帧) orphans %d -> %d" % [_frame, sc, a[0], b[0], 24 * STAT_EVERY, a[1], b[1]])


func _random_event() -> void:
	var k: String = kinds[rng.randi() % kinds.size()]
	match k:
		"act":
			var an: String = ACTS[rng.randi() % ACTS.size()]
			_act(an, true)
			_held.append([_frame + 1, "act:" + an])
		"key":
			var kc: int = KEYS[rng.randi() % KEYS.size()]
			_key(kc, true)
			_held.append([_frame + 1, kc])
		"hold":  # 按住一个键若干帧 (连发 / 与别的输入交错)
			var kc2: int = KEYS[rng.randi() % KEYS.size()]
			_key(kc2, true)
			_held.append([_frame + 3 + rng.randi() % 40, kc2])
		"fn":
			if rng.randi() % 4 == 0:  # 功能键少按点, 免得老停在设定面板
				var fk: int = FN_KEYS[rng.randi() % FN_KEYS.size()]
				_key(fk, true)
				_held.append([_frame + 1, fk])
		"mouse":
			_mouse()
		"win":
			if rng.randi() % 60 == 0:
				_window()
		"setting":
			if rng.randi() % 80 == 0:
				_setting()


func _act(name: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = name
	e.pressed = pressed
	Input.parse_input_event(e)


func _key(kc: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = kc
	e.physical_keycode = kc
	e.pressed = pressed
	Input.parse_input_event(e)


func _release(what) -> void:
	if what is String:
		_act(what.trim_prefix("act:"), false)
	else:
		_key(int(what), false)


func _release_all() -> void:
	for h in _held:
		_release(h[1])
	_held.clear()
	for n in ACTS:
		_act(n, false)


func _mouse() -> void:
	var p := Vector2(rng.randf() * 1280.0, rng.randf() * 800.0)
	var r := rng.randi() % 10
	if r < 5:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		Input.parse_input_event(mm)
		return
	var btn := MOUSE_BUTTON_LEFT
	if r == 7:
		btn = MOUSE_BUTTON_RIGHT
	elif r == 8:
		btn = MOUSE_BUTTON_MIDDLE
	elif r == 9:
		btn = MOUSE_BUTTON_WHEEL_UP if rng.randi() % 2 == 0 else MOUSE_BUTTON_WHEEL_DOWN
	for pressed in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = btn
		m.pressed = pressed
		m.position = p
		m.global_position = p
		Input.parse_input_event(m)


## 随机改窗口大小 / 画面比例 (headless 下窗口是虚拟的, 但布局重算照走)
func _window() -> void:
	var sizes := [Vector2i(1280, 800), Vector2i(1600, 900), Vector2i(1280, 960), Vector2i(2560, 1080), Vector2i(1024, 768)]
	var s: Vector2i = sizes[rng.randi() % sizes.size()]
	var win: Window = (Engine.get_main_loop() as SceneTree).root
	win.size = s
	if rng.randi() % 3 == 0:
		ScreenLayout.set_aspect_mode(["keep", "auto"][rng.randi() % 2])


## 随机改一个设定项并应用 (走覆盖层 SettingsSchema.set_override: 校验并即时生效, 不写盘)
func _setting() -> void:
	var rows: Array = SettingsSchema.all_shown_rows()   # 含二级菜单里的行 (音量、手柄预设、分辨率等)
	var r: Dictionary = rows[rng.randi() % rows.size()]
	var key := String(r["key"])
	if r["kind"] == "volume":
		SettingsSchema.set_override(Game.ctx, key, rng.randi() % 11)
	else:
		var opts := SettingsSchema.options_of(r)
		if opts.is_empty():
			return
		SettingsSchema.set_override(Game.ctx, key, opts[rng.randi() % opts.size()]["v"])


## 卡死时打印场景/栈顶对象的脚本变量 (布尔、数字、对象是否存在), 看是哪个标志位挂住了
func _dump_vars(o: Object) -> String:
	if o == null or o.get_script() == null:
		return str(o)
	var parts := []
	for p in o.get_script().get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = o.get(p.name)
			if v is bool or v is int or v is float or v is String:
				parts.append("%s=%s" % [p.name, str(v).left(30)])
			elif v is Object:
				parts.append("%s=%s" % [p.name, "obj" if is_instance_valid(v) else "freed"])
			elif v == null:
				parts.append("%s=null" % p.name)
	return "{" + " ".join(parts) + "}"

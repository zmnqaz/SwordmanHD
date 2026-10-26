# SPDX-License-Identifier: GPL-3.0-only
extends Node
## 无人值守测试 (autoload "Autotest"), 建议配合 --fixed-fps 25 使每帧固定 0.04 秒:
##   godot --path game --fixed-fps 25 -- --skip-movies --press=30:ui_accept --shot=20:/tmp/a.png --quit=60
## --press=<帧>:<动作>  在该帧按下并于下一帧松开输入动作 (ui_accept/ui_down/... 或统一输入层动作名 confirm/cancel/info/menu/page_up...)
## --hold=<帧>:<动作>:<帧数> 按住若干帧再松开 (测试按住连发)
## --shot=<帧>:<路径>   在该帧保存截图
## --click=<帧>:<x>,<y> 在该帧于屏幕坐标 (1280x800) 左键单击 (--touch 下等于点按)
## --rclick=<帧>:<x>,<y> 右键单击
## --mdown= / --mup= / --mmove=<帧>:<x>,<y>  左键按下 / 松开 / 按住拖到 (--touch 下模拟长按、拖动)
## --move=<帧>:<x>,<y>  不按键移动鼠标到该点 (悬停: 选中项跟随指针)
## --key=<帧>:<键名>    在该帧按下并于下一帧松开一个真实按键 (InputEventKey, 键名同 OS.find_keycode_from_string: Enter / Space / Escape / Left ...)
## --kdown= / --kup=<帧>:<键名>  真实按键按下 / 松开 (录制的输入用它保留按住时长)
## --input-script=<文件> 从文件读入上述参数 (一行一个); --record-input=<文件> 录制本次的键盘鼠标输入成这种文件 (录制时锁 25 帧/秒)
## --monkey=<种子>:<帧数>[:<换场景间隔>]  猴子测试: 固定种子随机输入, 查卡死/泄漏 (scripts/monkey.gd 文件头)
## --dump=<帧>:<标签>  在该帧打印界面状态 (UIDUMP 一行 JSON: 场景/界面栈/脚本变量/音频/窗口, scripts/ui_probe.gd; 验收工具 仓库外的开发脚本 用)
## --quit=<帧>          在该帧退出
## --perf-log=<文件>   性能采样: 每帧记墙钟耗时, 退出时写 JSON (帧时间均值/P95/最大、静态内存峰值、纹理/显存、节点数, 见 _perf_write)
## --regress-out=<文件> 等: 确定性回归记录, 见 engine/test/regress_log.gd

var frame := 0
var _press := {}
var _shots := {}
var _clicks := {}
var _quit := -1
var _release: Array = []
var _holds := {}      # 帧 -> [[动作, 帧数]]
var _late := {}       # 帧 -> [松开的动作]
var _mouse := {}      # 帧 -> [[类型, 坐标]]
var _dumps := {}      # 帧 -> [标签] (--dump)


var _rec: FileAccess    # --record-input
var _perf_slow: Array = []   # 稳态后 > 40ms 的帧 [帧号, ms]
var _perf_path := ""    # --perf-log
var _perf_ms: PackedFloat32Array = PackedFloat32Array()
var _perf_last := 0
var _perf_spikes: Array = []   # 超过 100ms 的帧 [帧号, 毫秒] (最多 20 个): 看顿帧出现在哪
var _perf_mem_peak := 0
var _perf_proc_sum := 0.0   # Performance.TIME_PROCESS (上一帧逻辑耗时, 秒) 逐帧累加 (无头下墙钟帧时间只是主循环限速, 逻辑耗时看它)
var _perf_proc_n := 0
const PERF_SPIKE_SKIP := 20  # 前 20 帧 (加载/着色器首次编译) 的顿帧不计入 spikes
var _monkey: Monkey     # --monkey= 猴子测试 (scripts/monkey.gd)


func _ready() -> void:
	process_priority = -100
	RegressLog.setup(DebugArgs.current().raw)  # 确定性回归记录 (--regress-out=..., engine/test/regress_log.gd)
	var args: PackedStringArray = DebugArgs.current().raw.duplicate()
	for arg in DebugArgs.current().raw:
		if arg.begins_with("--input-script="):  # 输入脚本: 每行一个上面的参数 (# 开头为注释), 由 --record-input 录制或手写
			var f := FileAccess.open(arg.trim_prefix("--input-script="), FileAccess.READ)
			while f and not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line != "" and not line.begins_with("#"):
					args.append(line)
		elif arg.begins_with("--record-input="):
			_rec = FileAccess.open(arg.trim_prefix("--record-input="), FileAccess.WRITE)
			_rec.store_line("# 输入录制 (Autotest --record-input); 回放: --input-script=<本文件>, 须同样 --fixed-fps 25 与相同启动参数")
			Engine.max_fps = 25  # 录制时按真实速度跑, 帧号与回放 (--fixed-fps 25) 对得上
	_monkey = Monkey.from_args(args, self)
	for arg in args:
		var kv := arg.split("=", true, 1)
		if kv.size() < 2:
			continue
		var v := kv[1].split(":", true, 1)
		match kv[0]:
			"--press": _press.get_or_add(int(v[0]), []).append(v[1])
			"--key": _press.get_or_add(int(v[0]), []).append("key:" + v[1])
			"--kdown": _holds.get_or_add(int(v[0]), []).append(["key:" + v[1], -1])
			"--kup": _late.get_or_add(int(v[0]), []).append("key:" + v[1])
			"--shot": _shots[int(v[0])] = v[1]
			"--dump": _dumps.get_or_add(int(v[0]), []).append(v[1] if v.size() > 1 else "")
			"--click": _clicks[int(v[0])] = Vector2(float(v[1].split(",")[0]), float(v[1].split(",")[1]))
			"--hold":
				var hv := v[1].split(":")
				_holds.get_or_add(int(v[0]), []).append([hv[0], int(hv[1]) if hv.size() > 1 else 25])
			"--rclick", "--mdown", "--mup", "--mmove", "--move":
				var xy := v[1].split(",")
				_mouse.get_or_add(int(v[0]), []).append([kv[0].trim_prefix("--"), Vector2(float(xy[0]), float(xy[1]))])
			"--quit": _quit = int(kv[1])
			"--perf-log": _perf_path = kv[1]


func _process(_d: float) -> void:
	for a in _release:
		_send(a, false)
	_release.clear()
	if _shots.has(frame):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shots[frame])
		print("截图 帧%d -> %s" % [frame, _shots[frame]])
	for l in _dumps.get(frame, []):
		UiProbe.dump(l, frame)
	for a in _press.get(frame, []):
		_send(a, true)
		_release.append(a)
	for h in _holds.get(frame, []):
		_send(h[0], true)
		if int(h[1]) >= 0:
			_late.get_or_add(frame + int(h[1]), []).append(h[0])
	for a in _late.get(frame, []):
		_send(a, false)
	for m in _mouse.get(frame, []):
		_mouse_event(m[0], m[1])
	if _clicks.has(frame):
		for pressed in [true, false]:
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT
			m.pressed = pressed
			m.position = _clicks[frame]
			m.global_position = _clicks[frame]
			Input.parse_input_event(m)
	if _perf_path != "":
		_perf_tick()
	if _monkey and _monkey.tick(frame):
		if _perf_path != "":
			_perf_write()
		quit_clean(get_tree())
	if frame == _quit:
		if _perf_path != "":
			_perf_write()
		quit_clean(get_tree())
	RegressLog.tick(frame)
	frame += 1
	RegressLog.log_frame = frame


func _perf_tick() -> void:
	var now := Time.get_ticks_usec()
	if _perf_last > 0:
		var ms := (now - _perf_last) / 1000.0
		_perf_ms.append(ms)
		if ms > 100.0 and frame >= PERF_SPIKE_SKIP and _perf_spikes.size() < 20:
			_perf_spikes.append([frame, snappedf(ms, 1.0)])
		if ms > 40.0 and frame >= 150 and _perf_slow.size() < 40:   # 稳态后的 40ms+ 顿帧: 帧号与耗时, 用来对时间线找原因
			_perf_slow.append([frame, snappedf(ms, 1.0)])
	_perf_last = now
	if frame >= 10:
		_perf_proc_sum += Performance.get_monitor(Performance.TIME_PROCESS)
		_perf_proc_n += 1
	_perf_mem_peak = maxi(_perf_mem_peak, OS.get_static_memory_usage())


## 不同机器的 perf-log 要能归类比较: 适配器/厂商/渲染方法/驱动/OS/窗口/Godot 版本; HqBaker 回退状态 (显卡跑不了 6 倍生成时 failed=true)
func _perf_env() -> Dictionary:
	var win := get_window()
	var env := {
		"adapter": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(), "rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"rendering_driver": str(RenderingServer.get_current_rendering_driver_name()), "display_driver": DisplayServer.get_name(),
		"os": OS.get_name(), "os_version": OS.get_version(), "godot": Engine.get_version_info().get("string", ""),
		"window": [win.size.x, win.size.y] if win else [0, 0], "cpu": OS.get_processor_name(), "cpu_count": OS.get_processor_count(),
	}
	env.merge(Assets.hq_report())
	return env


func _perf_write() -> void:
	var xs := Array(_perf_ms.slice(maxi(0, mini(10, _perf_ms.size() - 1))))  # 跳过前 10 帧 (加载/着色器编译)
	xs.sort()
	var sum := 0.0
	for x in xs:
		sum += x
	var n := xs.size()
	# 体感卡顿: 跳过前 150 帧 (载入/着色器编译) 之后超过 25 / 50 ms 的帧数与 P99 (平均和 P95 看不出偶发的几十毫秒顿帧)
	var steady := Array(_perf_ms.slice(mini(150, _perf_ms.size())))
	var over25 := 0
	var over50 := 0
	for x in steady:
		over25 += 1 if x > 25.0 else 0
		over50 += 1 if x > 50.0 else 0
	steady.sort()
	var out := {
		"frames": frame, "ms_avg": snappedf(sum / maxf(n, 1), 0.01), "ms_p95": xs[int(n * 0.95)] if n > 0 else 0.0,
		"ms_p99": steady[int(steady.size() * 0.99)] if steady.size() > 0 else 0.0, "frames_over_25ms": over25, "frames_over_50ms": over50,
		"ms_max": xs[-1] if n > 0 else 0.0, "ms_first10_max": (Array(_perf_ms.slice(0, 10)).max() if _perf_ms.size() > 0 else 0.0),
		"static_mem_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1), "static_mem_peak_mb": snappedf(_perf_mem_peak / 1048576.0, 0.1),
		"tex_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), "draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	}
	out["time_process_ms"] = snappedf(_perf_proc_sum / maxi(_perf_proc_n, 1) * 1000.0, 0.001)
	out["env"] = _perf_env()
	out["tex_cache"] = Assets.cache_report()
	out["spikes"] = _perf_spikes
	out["slow_frames"] = _perf_slow
	var f := FileAccess.open(_perf_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out))
	print("perf: ", JSON.stringify(out))


## --record-input: 把真实的按键与鼠标按下/松开/移动按帧号写成输入脚本 (键用 --kdown/--kup 保留按住时长)
func _input(e: InputEvent) -> void:
	if _rec == null:
		return
	if e is InputEventKey and not e.echo:
		_rec.store_line("--%s=%d:%s" % ["kdown" if e.pressed else "kup", frame, OS.get_keycode_string(e.keycode)])
	elif e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var kind := ("mdown" if e.pressed else "mup") if e.button_index == MOUSE_BUTTON_LEFT else "rclick"
		if kind == "rclick" and not e.pressed:
			return
		_rec.store_line("--%s=%d:%d,%d" % [kind, frame, e.position.x, e.position.y])
	elif e is InputEventMouseMotion:
		_rec.store_line("--%s=%d:%d,%d" % ["mmove" if e.button_mask & MOUSE_BUTTON_MASK_LEFT else "move", frame, e.position.x, e.position.y])
	else:
		return
	_rec.flush()


func _send(action: String, pressed: bool) -> void:
	if action.begins_with("key:"):
		var k := InputEventKey.new()
		var s := action.trim_prefix("key:")
		var code := OS.find_keycode_from_string(s)
		if code == 0 and s.begins_with("KEY_"):
			code = OS.find_keycode_from_string(s.trim_prefix("KEY_"))  # 手写习惯 KEY_F10; get_keycode_string 的返回其实是 "F10"
		k.keycode = code
		k.physical_keycode = k.keycode
		k.pressed = pressed
		Input.parse_input_event(k)
		return
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	Input.parse_input_event(e)


func _mouse_event(kind: String, p: Vector2) -> void:
	if kind == "mmove" or kind == "move":
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if kind == "mmove" else 0
		Input.parse_input_event(mm)
		return
	for pressed in ([true, false] if kind == "rclick" else [kind == "mdown"]):
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_RIGHT if kind == "rclick" else MOUSE_BUTTON_LEFT
		m.pressed = pressed
		m.position = p
		m.global_position = p
		Input.parse_input_event(m)


## 自动测试的退出: 先停掉所有音频播放器并让音频线程松手, 否则退出时 MP3/WAV 播放对象还被音频线程握着,
## Godot 报「ObjectDB instances were leaked」(退出顺序现象, 不是真泄漏; 日志里这条噪声会盖住真问题)
static func quit_clean(tree: SceneTree) -> void:
	for p in tree.root.find_children("*", "AudioStreamPlayer", true, false):
		p.stop()
		p.stream = null
	OS.delay_msec(150)
	tree.quit()

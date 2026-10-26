# SPDX-License-Identifier: GPL-3.0-only
class_name ScriptVM
extends Node
## 剧情脚本解释器基类 (战场 EventVM / 城镇 RpgVM 共用)。
## 一个事件是一串指令 (engine/script/evs_compiler.gd 编出的 {type, data}), 顺序执行, 指令用 await 可阻塞。
## 指令注册表: 操作码 -> Callable(t: int, d: PackedByteArray), 子类在 _register_ops() 里登记; 内容包/mod 的代码
## 也可在场景建好后调 register_op() 追加或覆盖指令 (不必改解释器)。未登记的指令打印警告后跳过, 不中断剧情。
## 子类只需: 实现 _events_of(id) 给出指令序列、_register_ops() 登记本场景的指令集。

var gc: GameContext = GameContext.current()  # 运行上下文 (状态/开关/场景流转); 场景在创建时可显式换成自己的

const END_STEP := 1 << 30
const CMP_NAMES := ["==", ">", ">=", "<", "<="]
## 同一帧内最多连续执行的指令数: 不含让出指令的 jump 回环 (剧本缺陷, 第三方内容包可能有) 超过它就报错并中止该事件,
## 不锁死主线程 。正常剧本一帧内连续执行的指令远少于此, 不影响正常行为
const MAX_STEPS_PER_FRAME := 10000

var ctx                      # 所属场景 (战场 battle_scene / 城镇 rpg_scene), 指令实现通过它操作画面
var log_enabled := true
var kind := "事件"            # 日志与警告里的称呼
var _id := -1                # 当前事件号
var _step := 0               # 当前指令下标; 跳转 = 改 _step (执行完本条后 +1, 故目标写 target - 1)
var _ops := {}               # 操作码 -> Callable
var _spin_frame := -1        # 防死循环计数: 所在帧号与本帧已执行的指令数 (见 _runaway)
var _spin := 0


func _init(scene) -> void:
	ctx = scene
	if scene != null and "gc" in scene:  # 跟随所属场景的上下文 (显式注入)
		gc = scene.gc
	_register_ops()


## 子类登记指令集 (用 register_op / register_ops)
func _register_ops() -> void:
	pass


## 子类返回事件 id 的指令序列; 无此事件返回 null
func _events_of(_event_id: int) -> Variant:
	return null


## 登记一条指令: handler(t, d) 可以是协程。mod 也用它追加或覆盖指令
func register_op(code: int, handler: Callable) -> void:
	_ops[code] = handler


## 多个操作码共用一个处理函数 (handler 靠 t 区分)
func register_ops(codes: Array, handler: Callable) -> void:
	for c in codes:
		_ops[c] = handler


## 顺序执行一个事件到结束
func _exec_event(id: int) -> void:
	var cmds: Variant = _events_of(id)
	if cmds == null:
		return
	_id = id
	_step = 0
	if log_enabled:
		print("== %s %d (%d 条指令)" % [kind, id, cmds.size()])
	while _step < cmds.size():
		var c: Dictionary = cmds[_step]
		await _do(int(c["type"]), c["data"])
		if _runaway():
			return
		_step += 1


## 本帧连续执行的指令超过 MAX_STEPS_PER_FRAME (无出口回环) 时报错并返回 true, 调用方中止当前事件
func _runaway() -> bool:
	var f := Engine.get_process_frames()
	if f != _spin_frame:
		_spin_frame = f
		_spin = 0
	_spin += 1
	if _spin <= MAX_STEPS_PER_FRAME:
		return false
	push_error("%s %d 第 %d 条: 同一帧连续执行了 %d 条指令没有让出 (无出口的跳转回环?), 中止该事件" % [kind, _id, _step, MAX_STEPS_PER_FRAME])
	_spin = 0
	return true


func _do(t: int, d: PackedByteArray) -> void:
	var h: Callable = _ops.get(t, Callable())
	if h.is_valid():
		await h.call(t, d)
		await _after_op(t)
	else:
		push_warning("未实现的%s指令 0x%02X (事件 %d 第 %d 条)" % [kind, t, _id, _step])


## 指令执行完后的原版解释器开销 (子类覆盖; 战场见 EventVM: 让出帧的指令完成后还要 2 帧才执行下一条)
func _after_op(_t: int) -> void:
	pass


## 等 n 个原版帧 (25 帧/秒)
func wait_frames(n: int) -> void:
	if n > 0 and is_inside_tree():
		await SceneGuard.wait(self, n / 25.0)


## 结束当前事件 (含切换场景)
func _end_event() -> void:
	_step = END_STEP


static func _s(d: PackedByteArray, o: int) -> int:
	return d.decode_s16(o) if o + 2 <= d.size() else 0


static func _i(d: PackedByteArray, o: int) -> int:
	return d.decode_s32(o) if o + 4 <= d.size() else 0


func _log(msg: String) -> void:
	if log_enabled:
		print("  [%d:%d] %s" % [_id, _step, msg])


## ---- 战场与城镇共有的指令实现 (操作码不同, 由子类登记) ----

## 变量比较 (== > >= < <=), 成立则跳到 step p3; 登记在连续五个操作码上, base 为第一个
func op_compare(base: int) -> Callable:
	return func(t: int, d: PackedByteArray) -> void:
		var v := gc.state.get_data(_s(d, 0))
		var x := _i(d, 2)
		var ok: bool = [v == x, v > x, v >= x, v < x, v <= x][t - base]
		_log("判断 变量%d=%d %s %d -> %s" % [_s(d, 0), v, CMP_NAMES[t - base], x, ok])
		if ok:
			_step = _s(d, 6) - 1


## 延时 p0 帧 (25 帧/秒)
func op_delay(_t: int, d: PackedByteArray) -> void:
	await SceneGuard.wait(self, _s(d, 0) / 25.0)


func op_music_load(_t: int, d: PackedByteArray) -> void:
	_log("音乐 Music_%02d 载入通道 %d" % [_s(d, 0), _s(d, 2)])
	ctx.load_music(_s(d, 2), _s(d, 0))


func op_music_start(_t: int, d: PackedByteArray) -> void:
	_log("通道 %d 开始播放 fade=%d" % [_s(d, 0), _s(d, 2)])
	ctx.start_music(_s(d, 0), _s(d, 2))


func op_music_close(_t: int, d: PackedByteArray) -> void:
	ctx.close_music(_s(d, 0))


func op_music_pause(_t: int, d: PackedByteArray) -> void:
	ctx.pause_music(_s(d, 0), true)


func op_music_resume(_t: int, d: PackedByteArray) -> void:
	ctx.pause_music(_s(d, 0), false)


func op_get_item(_t: int, d: PackedByteArray) -> void:
	_log("获得物品 %d" % _s(d, 0))
	gc.state.add_item(_s(d, 0))

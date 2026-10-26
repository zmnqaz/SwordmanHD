# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 场景协程保护 (engine/core/scene_guard.gd):
## 战场协程等计时器时场景被释放/排队释放/移出场景树, 不报错、不在过期场景上继续跑。
## 脚本错误由 run_tests.gd 统一捕获算失败, 所以「不报错」不必另写断言。


## 只登记三条指令的最小解释器: 1 = 延时 p0 帧 (基类 op_delay), 2 = 记一笔, 3 = 跳到 step p0 (test_script_runaway.gd 也用)
class MiniVM extends ScriptVM:
	var events := {}
	var marks := 0

	func _register_ops() -> void:
		register_op(1, op_delay)
		register_op(2, func(_t, _d): marks += 1)
		register_op(3, func(_t, d: PackedByteArray): _step = _s(d, 0) - 1)

	func _events_of(id: int) -> Variant:
		return events.get(id)


class FakeStage extends RefCounted:
	var events: Array = []


## EventVM 只用到 st.events 与 gc (变量指令)
class FakeScene extends RefCounted:
	var gc := GameContext.new()
	var st := FakeStage.new()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _cmd(t: int, vals: Array = []) -> Dictionary:
	var b := PackedByteArray()
	b.resize(maxi(vals.size() * 2, 6))
	for i in vals.size():
		b.encode_s16(i * 2, vals[i])
	return {"type": t, "data": b}


## 场景根 (holder) 下挂一个解释器节点, 模拟战场里 BattleScene -> EventVM
func _mini_scene(cmds: Array) -> Array:
	var holder := Node.new()
	var vm := MiniVM.new(null)
	vm.log_enabled = false
	vm.events[0] = cmds
	holder.add_child(vm)
	_tree().root.add_child(holder)
	return [holder, vm]


func test_alive_rules():
	var n := Node.new()
	check(not SceneGuard.alive(n), "不在场景树: 无效")
	var p := Node.new()
	p.add_child(n)
	_tree().root.add_child(p)
	check(SceneGuard.alive(n), "在树内: 有效")
	p.queue_free()
	check(not SceneGuard.alive(n), "祖先排队释放 (切场景 queue_free 场景根): 无效")
	await _tree().process_frame
	check(not SceneGuard.alive(n), "已释放: 无效")
	check(not SceneGuard.alive(null), "null 无效")


func test_battle_vm_freed_while_waiting():
	# 真 EventVM: 延时 3 帧 -> 变量 50 += 1; 等待中整个场景被释放
	var sc := FakeScene.new()
	var add := PackedByteArray()
	add.resize(6)
	add.encode_s16(0, 50)
	add.encode_s32(2, 1)
	sc.st.events = [[_cmd(0x05, [3]), {"type": 0x3A, "data": add}]]
	var holder := Node.new()
	var vm := EventVM.new(sc)
	vm.log_enabled = false
	vm.gc = sc.gc
	holder.add_child(vm)
	_tree().root.add_child(holder)
	vm._exec_event(0)   # 不 await: 同战场里的后台协程
	await _tree().create_timer(0.02).timeout
	holder.free()
	await _tree().create_timer(0.3).timeout
	eq(sc.gc.state.get_data(50), 0, "场景释放后事件不再继续")


func test_queued_scene_stops_vm():
	# 计时器到点的同一帧里场景刚被 queue_free (还没真正释放): 以前协程照样恢复, 在过期场景上执行后续指令
	var r := _mini_scene([_cmd(1, [3]), _cmd(2)])
	var holder: Node = r[0]
	var vm: MiniVM = r[1]
	var marks := [0]   # 放在测试里, 场景释放后仍可读
	vm.register_op(2, func(_t, _d): marks[0] += 1)
	var t := _tree().create_timer(3 / 25.0)   # 先建 = 同一帧里先触发 (SceneTree 按创建顺序处理计时器)
	t.timeout.connect(holder.queue_free)
	vm._exec_event(0)
	await _tree().create_timer(0.3).timeout
	eq(marks[0], 0, "排队释放的场景: 延时之后的指令不执行")


func test_removed_scene_pauses_then_resumes():
	var r := _mini_scene([_cmd(1, [2]), _cmd(2)])
	var holder: Node = r[0]
	var vm: MiniVM = r[1]
	vm._exec_event(0)
	await _tree().create_timer(0.02).timeout
	_tree().root.remove_child(holder)
	await _tree().create_timer(0.2).timeout
	eq(vm.marks, 0, "移出场景树: 停住, 不继续 (也不因 get_tree() 为空报错)")
	_tree().root.add_child(holder)
	await _tree().process_frame
	eq(vm.marks, 1, "重新入树后继续")
	holder.free()


func test_wait_returns_true_when_alive():
	var n := Node.new()
	_tree().root.add_child(n)
	check(await SceneGuard.wait(n, 0.01), "节点有效: 等完返回 true")
	n.free()

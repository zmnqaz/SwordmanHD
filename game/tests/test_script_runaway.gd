# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 剧情解释器防死循环 (engine/script/script_vm.gd): 不含让出指令的 jump 回环报错中止该事件, 不锁死主线程;
## 带让出 (延时) 的回环跨帧计数清零, 不误报。

const G = preload("res://tests/test_scene_guard.gd")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _mini_scene(cmds: Array) -> Array:
	return G.new()._mini_scene(cmds)


func _cmd(t: int, vals: Array = []) -> Dictionary:
	return G.new()._cmd(t, vals)


func test_jump_loop_aborts():
	var r := _mini_scene([_cmd(2), _cmd(3, [0]), _cmd(2)])
	var vm: G.MiniVM = r[1]
	var t0 := Time.get_ticks_msec()
	vm._exec_event(0)   # 全是同步指令: 以前这里永不返回
	check(Time.get_ticks_msec() - t0 < 5000, "及时中止")
	eq(vm.marks, ScriptVM.MAX_STEPS_PER_FRAME / 2 + 1, "执行到上限 (记一笔+跳转, 每轮两条) 后中止, 回环后面的指令不执行")
	# 中止后同一个解释器还能正常跑别的事件 (计数已清)
	vm.events[1] = [_cmd(2)]
	vm.marks = 0
	vm._exec_event(1)
	eq(vm.marks, 1, "之后的事件照常执行")
	r[0].free()


func test_loop_with_yield_not_aborted():
	# 回环里有延时 (让出帧): 跨帧计数清零, 不误报; 这里用变量计数在若干轮后跳出
	var r := _mini_scene([])
	var vm: G.MiniVM = r[1]
	var n := [0]
	vm.register_op(4, func(_t, _d):
		n[0] += 1
		if n[0] >= 3:
			vm._step = 99)   # 第 3 轮跳出
	vm.events[0] = [_cmd(1, [1]), _cmd(4), _cmd(3, [0])]
	await vm._exec_event(0)
	eq(n[0], 3, "带延时的回环按条件正常退出")
	r[0].free()

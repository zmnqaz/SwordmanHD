# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 剧情解释器基类: 指令注册表、跳转、结束、未登记指令跳过


class MiniVM extends ScriptVM:
	var events := []
	var trace := []

	func _register_ops() -> void:
		register_op(1, func(_t, d): trace.append(_s(d, 0)))
		register_op(2, func(_t, d): _step = _s(d, 0) - 1)
		register_op(3, func(_t, _d): _end_event())

	func _events_of(id: int) -> Variant:
		return events[id] if id < events.size() else null

	func go(id: int) -> void:
		await _exec_event(id)


func _cmd(t: int, v := 0) -> Dictionary:
	var d := PackedByteArray()
	d.resize(8)
	d.encode_s16(0, v)
	return {"type": t, "data": d}


func test_registry_and_flow():
	var vm := MiniVM.new(null)
	vm.log_enabled = false
	vm.events = [[_cmd(1, 10), _cmd(2, 3), _cmd(1, 11), _cmd(1, 12), _cmd(3), _cmd(1, 13)]]
	vm.go(0)  # 无阻塞指令, 同步跑完
	eq(vm.trace, [10, 12], "跳转跳过第 3 条, 结束指令截断后续")
	vm.free()


func test_mod_can_register_op():
	var vm := MiniVM.new(null)
	vm.log_enabled = false
	vm.register_op(0x77, func(_t, d): vm.trace.append(1000 + vm._s(d, 0)))
	vm.events = [[_cmd(0x77, 5), _cmd(0x78), _cmd(1, 1)]]
	vm.go(0)
	eq(vm.trace, [1005, 1], "mod 指令生效, 未登记的 0x78 跳过")
	vm.free()

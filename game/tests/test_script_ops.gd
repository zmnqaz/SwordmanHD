# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 剧情指令 (战场): 变量/坐标/镜头格/回血/震动等小指令按对照原版语义 (docs/剧情脚本格式.md §5.1)


class FakeUnit extends RefCounted:
	var cx := 0
	var cy := 0
	var hp := 10
	var hp_max := 10
	var mp := 5
	var mp_max := 5
	var camp := 0
	var alive := true
	var shown := true
	var st := {"annihilation_exempt": false}
	var man := {"unit_id": 0}


class FakeScene extends RefCounted:
	var gc := GameContext.new()
	var units: Array = []
	var cam := Vector2(100, 50)
	var shake := Vector2.ZERO
	var calls: Array = []
	func load_music(ch: int, num: int) -> void:
		calls.append(["load", ch, num])
	func start_music(ch: int, fade: int) -> void:
		calls.append(["start", ch, fade])
	func close_music(ch: int) -> void:
		calls.append(["close", ch])
	func unit(i: int):
		return units[i] if i >= 0 and i < units.size() else null
	func orig_cam() -> Vector2:
		return cam
	func cam_offset() -> Vector2:
		return Vector2(10, 4)


func _d(vals: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(vals.size() * 2)
	for i in vals.size():
		b.encode_s16(i * 2, vals[i])
	return b


func _run(vm: EventVM, op: int, vals: Array) -> void:
	vm._ops[op].call(op, _d(vals))


func test_var_and_position_ops():
	var sc := FakeScene.new()
	var a := BattleUnit.new()
	a.st = preload("res://engine/rules/unit_state.gd").new()
	a.cx = 12
	a.cy = 7
	a.hp_max = 10
	a.mp_max = 5
	sc.units = [a]
	var vm := EventVM.new(sc)
	vm.log_enabled = false
	vm.gc = sc.gc
	sc.gc.state.set_data(96, 20)
	# 0x3B sub_var: var -= p1 (int32); 数据 int16 变量号 + int32 值
	var d := PackedByteArray()
	d.resize(6)
	d.encode_s16(0, 96)
	d.encode_s32(2, 5)
	vm._ops[0x3B].call(0x3B, d)
	eq(sc.gc.state.get_data(96), 15, "0x3B 减")
	_run(vm, 0x3C, [0, 96, 97])  # 单位 0 的格 -> var96, var97
	eq(sc.gc.state.get_data(96), 12, "0x3C x")
	eq(sc.gc.state.get_data(97), 7, "0x3C y")
	_run(vm, 0x3D, [98, 99])  # 镜头格 = ((100+10)/30, (50+4)/24)
	eq(sc.gc.state.get_data(98), 3, "0x3D x")
	eq(sc.gc.state.get_data(99), 2, "0x3D y")
	a.hp = 3
	a.mp = 0
	_run(vm, 0x4B, [0])
	eq([a.hp, a.mp], [10, 5], "0x4B 回满")
	_run(vm, 0x50, [4, 4])
	eq(sc.shake, Vector2(4, 4), "0x50 震动幅度")
	_run(vm, 0x51, [])
	eq(sc.shake, Vector2.ZERO, "0x51 停止震动")
	sc.gc.state.set_data(10, -3)
	_run(vm, 0x4D, [10, 11])
	eq(sc.gc.state.get_data(11), 1, "0x4D 是 & 1 (负奇数 -> 1)")
	a.hp = 0
	a.alive = false
	_run(vm, 0x41, [0, 12])
	eq(sc.gc.state.get_data(12), 1, "0x41 只看 hp != hpmax, 不查存活")
	vm.free()
	a.free()


func test_count_enemies_skips_exempt():
	var sc := FakeScene.new()
	for i in 3:
		var u := FakeUnit.new()
		u.camp = 1
		sc.units.append(u)
	sc.units[2].st["annihilation_exempt"] = true
	var vm := EventVM.new(sc)
	vm.log_enabled = false
	vm.gc = sc.gc
	_run(vm, 0x37, [5])
	eq(sc.gc.state.get_data(5), 2, "0x37 不计 字段 单位")
	vm.free()


func test_music_load_does_not_play():
	var sc := FakeScene.new()
	var vm := EventVM.new(sc)
	vm.log_enabled = false
	vm.gc = sc.gc
	_run(vm, 0x2A, [50, 1])      # music_load music=50 ch=1: 只载入
	eq(sc.calls, [["load", 1, 50]], "0x2A 只载入, 不播放")
	_run(vm, 0x2C, [1, 1])       # music_play ch=1 fade=1: 开始播放 (淡入), 不是音量减半
	_run(vm, 0x2B, [1])
	eq(sc.calls, [["load", 1, 50], ["start", 1, 1], ["close", 1]], "0x2C 播放 / 0x2B 关闭")
	vm.free()


## 剧情指令 0x36 [原版实机: 第一关事件 2 (开头 clear_status) 执行后, 殷剑平的状态位仍在、召唤物 on=0 但 字段 与 var103 不变]
func test_clear_status_keeps_status_bits_and_summon_flag():
	var US = preload("res://engine/rules/unit_state.gd")
	var sc := FakeScene.new()
	var a := BattleUnit.new()
	a.st = US.new()
	a.st.status = US.ST_ATK_UP
	a.st.status_r[US.ST_ATK_UP] = 300
	a.st.status_k[US.ST_ATK_UP] = 100
	var s := BattleUnit.new()
	s.st = US.new()
	s.st.summon = true
	s.st.alive = true
	s.summon_flag = 103
	sc.units = [a, s]
	sc.gc.state.set_data(103, 1)
	var vm := EventVM.new(sc)
	vm.log_enabled = false
	vm.gc = sc.gc
	_run(vm, 0x36, [])
	eq(a.st.status, US.ST_ATK_UP, "0x36 不清状态位")
	eq(a.st.status_r[US.ST_ATK_UP], 300, "R 不变")
	check(not s.st.alive, "召唤物退场")
	eq(sc.gc.state.get_data(103), 1, "标志变量不清")
	eq(s.summon_flag, 103, "字段 不清")
	vm.free()
	a.free()
	s.free()

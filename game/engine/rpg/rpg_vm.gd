# SPDX-License-Identifier: GPL-3.0-only
class_name RpgVM
extends ScriptVM
## RPG 场景 (城镇) 剧情脚本解释器, 执行内容包 scripts/town_NN.evs 编译出的指令 (engine/script/evs_compiler.gd),
## 指令语义移植自重制版 GameRPGEventManager.doEvent。解释循环与注册表在 ScriptVM, 这里只登记城镇指令集。

var rs:
	get:
		return ctx


func _init(scene) -> void:
	super(scene)
	kind = "RPG 事件"


func _register_ops() -> void:
	register_op(0x00, func(_t, _d): _end_event())
	register_op(0x01, _wait)  # 延时 p0 帧
	register_op(0x02, func(_t, _d): await get_tree().process_frame)  # 只让出一帧, 不改显示
	register_op(0x04, _camera)
	register_op(0x06, func(_t, d): await rs.fade_light(16, 0, _s(d, 0)))
	register_op(0x07, func(_t, d): await rs.fade_light(0, 16, _s(d, 0)))
	register_op(0x09, _talk)
	register_op(0x10, func(_t, d): gc.state.set_data(_s(d, 0), _i(d, 2)))
	register_op(0x15, func(_t, d): rs.add_animation(_s(d, 0), _s(d, 2)))
	register_op(0x16, func(_t, d): rs.clear_animation(_s(d, 0), _s(d, 2)))
	register_op(0x18, func(_t, d): await rs.play_animation(_s(d, 0), _s(d, 2), _s(d, 4), _s(d, 6)))
	register_op(0x1A, op_music_load)
	register_op(0x1B, op_music_close)
	register_op(0x1D, op_music_pause)
	register_op(0x1C, op_music_start)
	register_op(0x1E, op_music_resume)
	register_ops([0x20, 0x21, 0x22, 0x23, 0x24], op_compare(0x20))  # 剧情变量比较 == > >= < <=
	register_op(0x26, _goto_rpg)
	register_op(0x27, _shop)
	register_op(0x28, _to_battle)
	register_op(0x29, _to_camp)
	register_op(0x2A, func(_t, _d): rs.hero.visible = true)   # 显示主角精灵
	register_op(0x2B, func(_t, _d): rs.hero.visible = false)  # 隐藏主角精灵
	register_op(0x2C, func(_t, d): gc.state.set_data(_s(d, 0), gc.state.get_data(_s(d, 0)) + _i(d, 2)))
	register_op(0x2D, func(_t, d): gc.state.set_data(_s(d, 0), gc.state.get_data(_s(d, 0)) - _i(d, 2)))
	register_op(0x2E, _choice)
	register_op(0x2F, op_get_item)
	register_op(0x30, _has_item)
	register_op(0x31, func(_t, d): gc.state.set_data(_s(d, 0), gc.state.gold))
	register_op(0x32, func(_t, d): gc.state.gold -= _s(d, 0))
	register_op(0x33, func(_t, d): gc.state.next_stage = _s(d, 0))


func _events_of(id: int) -> Variant:
	if id < 0 or id >= rs.st.events.size():
		return null
	return rs.st.events[id]


func run(id: int) -> void:
	await _exec_event(id)


func _camera(_t: int, d: PackedByteArray) -> void:
	_log("镜头 -> (%d,%d)" % [_s(d, 0), _s(d, 2)])
	await rs.pan_camera(_s(d, 0), _s(d, 2), _s(d, 4), _s(d, 6))


## 0x01: 状态机每帧先减计数再判 >0, N 帧后完成, N<=0 也占 1 帧 (实测 wait 10 -> 12 帧含 2 帧开销)
func _wait(_t: int, d: PackedByteArray) -> void:
	await wait_frames(maxi(_s(d, 0), 1))


## 让出帧的指令完成后还要 2 帧才执行下一条 (状态 1 解释 -> 2 等完成 -> 1); 名单来自分派 逐项分类
const YIELD_OPS := [0x01, 0x02, 0x04, 0x05, 0x06, 0x07, 0x09, 0x2E]


func _after_op(t: int) -> void:
	if t in YIELD_OPS:
		await wait_frames(2)


## 对白: 头像, 表情, 位置, 句号
func _talk(_t: int, d: PackedByteArray) -> void:
	var text: String = rs.st.talk(_id, _s(d, 12))
	_log("对白 头像%d 表情%d 位置%d #%d %s" % [_s(d, 6), _s(d, 8), _s(d, 10), _s(d, 12), text.replace("\n", " ")])
	if text != "":
		await rs.msgbox.show_text(_s(d, 6), _s(d, 8), _s(d, 10), text)


func _goto_rpg(_t: int, d: PackedByteArray) -> void:
	_log("切换 RPG 场景 %d 入口 %d" % [_s(d, 0), _s(d, 2)])
	gc.flow.goto_rpg.call_deferred(_s(d, 0), _s(d, 2))
	_end_event()


func _shop(_t: int, d: PackedByteArray) -> void:
	var sid := _s(d, 0)
	_log("商店 %d" % sid)
	if sid < rs.st.shops.size():
		await rs.shop.open(rs.st.shops[sid])


func _to_battle(_t: int, _d: PackedByteArray) -> void:
	_log("出城 -> 第 %d 关" % gc.state.next_stage)
	gc.flow.goto_battle.call_deferred(gc.state.next_stage)
	_end_event()


## 城镇里的营地: p0 = CAMP 编号 (记为进度值), 离开营地时回到城镇入口 1
func _to_camp(_t: int, d: PackedByteArray) -> void:
	_log("营地 %d" % _s(d, 0))
	gc.flow.goto_camp.call_deferred(_s(d, 0))
	_end_event()


## 是/否 选择框: 三句文字 (标题、是、否), 结果写入变量
func _choice(_t: int, d: PackedByteArray) -> void:
	var num := _s(d, 6)
	var ok: bool = await rs.choice.ask(rs.st.talk(_id, num), rs.st.talk(_id, num + 1), rs.st.talk(_id, num + 2))
	gc.state.set_data(_s(d, 8), 1 if ok else 0)


## 持有物品 -> var = 1/0 (->): 先查在队各人的 10 格, 再查行囊; 不单独查装备 (装备只是引用 10 格里的物品)
func _has_item(_t: int, d: PackedByteArray) -> void:
	var id := _s(d, 0)
	var ok := gc.state.has_item(id)
	for uid in gc.state.party:
		if id in gc.state.party[uid].get("items", []).map(func(v): return int(v)):
			ok = true
	gc.state.set_data(_s(d, 2), 1 if ok else 0)

# SPDX-License-Identifier: GPL-3.0-only
class_name EventVM
extends ScriptVM
## 战场剧情脚本解释器, 执行内容包 scripts/stage_NN.evs 编译出的指令 (engine/script/evs_compiler.gd, 与原版 EVENT_NN.COD 逐条相同),
## 指令语义逐条移植自重制版 GameBattleEventManager.doEvent 并按对照原版修正 (docs/剧情脚本格式.md)。
## 解释循环与指令注册表在 ScriptVM, 这里登记战场指令集并管理事件队列。
## 会阻塞的指令 (移动、对白、动画、镜头、延时、视频) 用 await 等待完成。

const Flow = preload("res://engine/rules/flow.gd")
const ClearRank = preload("res://engine/rules/clear_rank.gd")
const ROSTER_OUT := GameState.ROSTER_OUT  # 0x4F 离队标志在 game_data 中的键基址 (剧情变量只用 0~127)

var running := false
var _queue: Array = []
var _show_count := 0      # 0x0B 之后的 0x01: 显示单位
var _clear_count := 0     # 0x09/0x0A 之后的 0x01: 隐藏单位
var _clear_remove := 0
var _clear_unshow := 0
var _move_count := 0      # 0x0E/0x10 之后的移动指令批次
var _move_start := 0
var _move_follow := 0
var _move_step := 0
var _move_speed := 0
var _moved := 0
var _pending_moves: Array = []
var ended := false        # 已执行关卡结束/游戏结束 (0x02/0x03/0x54), 不再处理后续判定
var _ending_movie := false  # 本次脚本 (队列) 播过结局过场

## 场景别名 (指令实现里沿用 bs)
var bs:
	get:
		return ctx


func _init(scene) -> void:
	super(scene)
	kind = "事件"


func _events_of(id: int) -> Variant:
	if id < 0 or id >= bs.st.events.size():
		return null
	return bs.st.events[id]


## 执行一个事件; 若已有事件在执行, 排队 (同重制版 eventList)
func run(id: int) -> void:
	if ended:
		return
	if running:
		_queue.append(id)
		return
	running = true
	_ending_movie = false
	while true:
		await _exec_event(id)
		if _queue.is_empty():
			break
		id = _queue.pop_front()
	running = false
	# 脚本结束时由规则决定是否回标题 (结局过场 + END 无出口; 开关 params.fix_ending_return_title,
	# 关掉 = 原版: 停在原处, 战斗继续空转)
	if Flow.script_end_exit(bs.ctl.rules.ctx, _ending_movie, ended) == "title":
		ended = true
		await gc.flow.ending()


func _register_ops() -> void:
	register_op(0x00, _end)
	register_op(0x01, _unit_show_hide)
	register_op(0x02, _stage_over)
	register_op(0x03, _game_over)
	register_op(0x04, _title_card)
	register_op(0x05, _delay)
	register_ops([0x06, 0x1F, 0x20], _nop)
	register_op(0x56, _clear_rank)
	register_op(0x07, _camera_to)
	register_op(0x08, _camera_pan)
	register_op(0x09, _clear_fade)
	register_op(0x0A, _clear_leave)
	register_op(0x0B, _show_batch)
	register_op(0x0C, _unit_turn)
	register_op(0x0D, _unit_place)
	register_op(0x0E, _move_begin)
	register_op(0x10, _move_begin_step)
	register_op(0x0F, _unit_walk_to)
	register_op(0x11, _unit_walk_dir)
	register_op(0x12, _screen_fade_op)
	register_op(0x13, _fade_out)
	register_op(0x14, _fade_in)
	register_op(0x15, _mask_off)
	register_op(0x16, _talk)
	register_op(0x17, _show_units)
	register_op(0x18, _anim_add)
	register_op(0x19, _anim_play)
	register_op(0x1A, _anim_start)
	register_ops([0x1C, 0x1D], _anim_hide)
	register_op(0x1E, _set_var)
	register_op(0x21, _cursor_center)
	register_op(0x22, _cursor_hide)
	register_op(0x23, _layer_show)
	register_op(0x24, _layer_unshow)
	register_op(0x25, _effect_show)
	register_op(0x26, _effect_unshow)
	register_op(0x28, _effect_play)
	register_op(0x29, _movie)
	register_op(0x2A, op_music_load)
	register_op(0x2B, op_music_close)
	register_op(0x2D, op_music_pause)
	register_op(0x2C, op_music_start)
	register_op(0x2E, op_music_resume)
	register_op(0x2F, _unit_ai)
	register_op(0x30, _jump)
	register_ops([0x31, 0x32, 0x33, 0x34, 0x35], op_compare(0x31))  # 剧情变量比较, 成立则跳到 step
	register_op(0x36, _clear_status)
	register_op(0x37, _count_enemies)
	register_op(0x3A, _var_add)
	register_op(0x3B, _var_sub)
	register_op(0x3C, _unit_pos_to_var)
	register_op(0x3D, _camera_cell_to_var)
	register_op(0x3E, _camera_pan_var)
	register_op(0x4B, _heal_unit)
	register_op(0x50, _shake_on)
	register_op(0x3F, _turn_to_var)
	register_op(0x40, _equip)
	register_op(0x41, _unit_hurt_to_var)
	register_op(0x42, _fade_unit_of_var)
	register_op(0x43, _copy_stats)
	register_op(0x44, _camp_switch)
	register_op(0x45, _weapon_to_var)
	register_op(0x46, _damage_all)
	register_op(0x4A, _damage_unit)
	register_op(0x47, _all_y_ge)
	register_op(0x48, _all_x_le)
	register_op(0x49, _equip_from_var)
	register_op(0x4C, _show_units_var)
	register_op(0x4D, _var_odd)
	register_op(0x4E, op_get_item)
	register_op(0x4F, _roster)
	register_op(0x51, _shake_off)
	register_op(0x53, _take_item_op)
	register_op(0x54, _ending)


func _end(_t: int, _d: PackedByteArray) -> void:
	_end_event()
	await SceneGuard.wait(self, 0.25)


func _nop(t: int, _d: PackedByteArray) -> void:
	_log("无操作 0x%02X" % t)


func _title_card(_t: int, _d: PackedByteArray) -> void:
	_log("关卡标题")
	await bs.show_title_card()


## 0x05: 状态机每帧先减计数再判 >0, 所以 N 帧后完成, N<=0 也要 1 帧 (实测 25 -> 27 帧、50 -> 52 帧含 2 帧开销)
func _delay(_t: int, d: PackedByteArray) -> void:
	_log("延时 %d" % _s(d, 0))
	await wait_frames(maxi(_s(d, 0), 1))


## 让出一帧的指令 (状态 1 解释一条 -> 状态 2 等完成 -> 完成后再 1 帧回到状态 1, 实测一条空转指令共 3 帧): 完成后补 2 帧。
## 不让出帧的指令 (坐标/朝向/变量等) 与同帧连续执行, 无开销。名单分派 逐项分类。
const YIELD_OPS := [0x04, 0x05, 0x06, 0x08, 0x09, 0x0E, 0x10, 0x12, 0x13, 0x14, 0x16, 0x29, 0x3E, 0x42, 0x54]


func _after_op(t: int) -> void:
	if t in YIELD_OPS:
		await wait_frames(2)


## 对一个单位执行 0x0B(显示) / 0x09,0x0A(隐藏) 登记的操作
func _unit_show_hide(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	if u:
		if _show_count > 0:
			u.alive = true
			u.show_unit(u.dir)
			_show_count -= 1
		if _clear_count > 0:
			if _clear_unshow == -1:
				u.hide_unit()
			elif _clear_remove == -1:
				u.fade_out()
			_clear_count -= 1
	_log("单位显隐 %d" % _s(d, 0))


## 关卡结束, 切换场景
func _stage_over(_t: int, d: PackedByteArray) -> void:
	_log("切换场景 town=%d camp=%d next=%d" % [_s(d, 0), _s(d, 2), _s(d, 4)])
	# 战斗销毁时 GD[0x94+4*GD.stage] = GD.turn; 此时 GD.stage 已被 0x02 改成「下一关」next,
	# 所以回合数记在变量 base+next (base = params.turn_record_base, 默认 30; 算法见 rules/clear_rank.gd) (原版存档核对: 第 0 关打了 18 回合 -> 变量 31 = 18; 第 22->24 关跳关时 var53 = 0、var54 = 51)。只有 0x56 读取
	var rec := ClearRank.record_var(bs.ctl.rules.ctx.params, _s(d, 4))
	if rec >= 0:
		gc.state.set_data(rec, bs.turn)
	_end_event()
	ended = true
	gc.flow.stage_over.call_deferred(_s(d, 0), _s(d, 2), _s(d, 4))


## 0x56 通关序号框 (第 35 关番外通关): 原版是两个系统 MessageBox (图标 i, 确定钮; 标题 = 窗口标题):
## 先「恭喜您…」, 再「为了本活动的公正性…序号: A-B-C-D-E」。A~D = 第 0~7、8~16、17~24、25~34 关回合数 (变量 30~64) 分四段求和,
## E = (A+B+C+D) xor 0xA50712A5, 都按 %X 大写十六进制无前导零。复刻用对话框显示同样文字 (见 对照_演出时序与界面.md §3)
func _clear_rank(_t: int, _d: PackedByteArray) -> void:
	var sums := ClearRank.serial(func(v): return gc.state.get_data(v), bs.ctl.rules.ctx.params)
	var t: Array = Content.system_text("clear_rank")
	if t.is_empty() or t[0].size() < 2:
		return
	var hex: Array = sums.map(func(x): return "%X" % x)
	_log("通关序号 %s" % "-".join(hex))
	await bs.msgbox.show_text(-1, 0, -1, String(t[0][0]))
	await bs.msgbox.show_text(-1, 0, -1, String(t[0][1]).format(hex))


func _game_over(_t: int, _d: PackedByteArray) -> void:
	_log("游戏结束")
	if bs.ctl != null and bs.ctl.flow != null:
		bs.ctl.flow.stats.result = "lose"   # 统计: 战败 (BattleStats)
		bs.ctl.flow.stats.report()   # 战败后流程直接退出, 不会走到战斗循环收尾, 这里先打统计 (内部防重复)
	_end_event()
	ended = true
	gc.flow.game_over.call_deferred()


func _ending(_t: int, _d: PackedByteArray) -> void:
	_log("结局")  # 原版: 销毁战斗回到标题 (不是 GAME OVER 画面), 第 34 关完美结局 / 第 35 关番外通关
	_end_event()
	ended = true
	gc.flow.ending.call_deferred()


func _camera_to(_t: int, d: PackedByteArray) -> void:
	_log("镜头 -> (%d,%d)" % [_s(d, 0), _s(d, 2)])
	bs.move_camera_to_cell(_s(d, 0), _s(d, 2))


func _camera_pan(_t: int, d: PackedByteArray) -> void:
	_log("镜头平移 -> (%d,%d) 速度 %d,%d" % [_s(d, 0), _s(d, 2), _s(d, 4), _s(d, 6)])
	await bs.pan_camera_to_cell(_s(d, 0), _s(d, 2), _s(d, 4), _s(d, 6))


## 0x09: p0 = -1 按类别淡出, 阻塞到全部淡出结束 (原先靠 0x36 隐藏敌人顶替); 否则登记批量淡出
func _clear_fade(_t: int, d: PackedByteArray) -> void:
	if _s(d, 0) == -1:
		_log("类别 %d 淡出" % _s(d, 2))
		var fading: Array = _group(_s(d, 2))
		for u in fading:
			u.fade_out()
		if not fading.is_empty():
			await SceneGuard.wait(self, 0.55)
		return
	_clear_count = _s(d, 0)
	_clear_remove = _s(d, 2)
	_clear_unshow = 0
	_show_count = 0


## 0x0A: p0 = -1 按类别立即离场; 否则登记批量离场
func _clear_leave(_t: int, d: PackedByteArray) -> void:
	if _s(d, 0) == -1:
		_log("类别 %d 离场" % _s(d, 2))
		for u in _group(_s(d, 2)):
			u.hide_unit()
		return
	_clear_count = _s(d, 0)
	_clear_unshow = _s(d, 2)
	_clear_remove = 0
	_show_count = 0


func _show_batch(_t: int, d: PackedByteArray) -> void:
	_show_count = _s(d, 0)
	_clear_count = 0
	_clear_remove = 0


## 单位转向
func _unit_turn(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	if u and u.shown:
		u.play_act(BattleUnit.Act.STAND, _s(d, 2))
	elif u:
		u.dir = _s(d, 2)  # 未出场也记朝向, 之后 0x0B 出场按此朝向 (原版只写 字段)
	_log("单位 %d 转向 %d" % [_s(d, 0), _s(d, 2)])


## 单位瞬移
func _unit_place(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	if u:  # 只设 x、y、朝向, 不让单位出场 (已在场的就地转向)
		u.set_cell(_s(d, 2), _s(d, 4))
		if u.shown:
			u.visible = true  # 走出地图离场的单位 (_leave_if_off_map) 再放回来就显示
			u.play_act(BattleUnit.Act.STAND, _s(d, 6))
		else:
			u.dir = _s(d, 6)
	_log("单位 %d 放到 (%d,%d)" % [_s(d, 0), _s(d, 2), _s(d, 4)])


func _move_begin(_t: int, d: PackedByteArray) -> void:
	_move_count = _s(d, 0)
	_move_start = _s(d, 2)
	_move_follow = _s(d, 4)
	_move_speed = _s(d, 6)
	_moved = 0
	_pending_moves.clear()


func _move_begin_step(_t: int, d: PackedByteArray) -> void:
	_move_count = _s(d, 0)
	_move_start = _s(d, 2)
	_move_follow = _s(d, 4)
	_move_step = _s(d, 6)
	_move_speed = _s(d, 8)
	_moved = 0
	_pending_moves.clear()


## 单位走到 (x,y): 原版不寻路, 走直角折线; 第 4 参数 vfirst=0 先横后竖, 否则先竖后横
func _unit_walk_to(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	_log("单位 %d 走到 (%d,%d) %s" % [_s(d, 0), _s(d, 2), _s(d, 4), "先竖" if _s(d, 6) != 0 else "先横"])
	if u:
		_start_move(u, _line_path(u, _s(d, 2), _s(d, 4), _s(d, 6) != 0))
	await _after_move()


## 单位朝某方向直走 move_step 格: 0 北 1 南 2 西 3 东
func _unit_walk_dir(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	_log("单位 %d 朝 %d 走 %d 格" % [_s(d, 0), _s(d, 2), _move_step])
	if u:
		var delta: Vector2i = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)][clampi(_s(d, 2), 0, 3)]
		var path: Array = []
		for k in range(1, _move_step + 1):
			path.append(Vector2i(u.cx, u.cy) + delta * k)
		_start_move(u, path)
	await _after_move()


## 全屏色彩渐变 (设参数, 每帧推进, 阻塞到两项都到终值; 结束后遮罩保留, 由 0x15 撤掉)
func _screen_fade_op(_t: int, d: PackedByteArray) -> void:
	await _screen_fade(_s(d, 0), _s(d, 2), _s(d, 4), _s(d, 6), _s(d, 8), _s(d, 10), _s(d, 12), _s(d, 14))


## 0x13 渐黑 / 0x14 渐亮 (2026-10-05 实测 状态机): 都是 0x12 的特例 (色 0, 混色 0),
## 亮度 16->0 / 0->16 每 (delay+1) 帧 -2/+2 共 8 级, 阶梯式不是平滑; 全程阻塞 (含最后 1 帧判完成)。
## 渐亮完成后遮罩关闭, 渐黑完成后保持全黑到 0x14/0x15。
func _fade_out(_t: int, d: PackedByteArray) -> void:
	_log("渐黑 %d" % _s(d, 0))
	await _screen_fade(0, 0, 0, 0, 16, 0, 2, _s(d, 0))


func _fade_in(_t: int, d: PackedByteArray) -> void:
	_log("渐亮 %d" % _s(d, 0))
	await _screen_fade(0, 0, 0, 0, 0, 16, 2, _s(d, 0))
	_set_mask(0, 16)


## 原版 立即撤掉 0x12 的颜色遮罩
func _mask_off(_t: int, _d: PackedByteArray) -> void:
	_set_mask(0, 16)


## 对白: 单位, ?, 头像, 表情, 位置(-1 中 0 左 1 右), 句号
func _talk(_t: int, d: PackedByteArray) -> void:
	var who := _s(d, 0)
	var num := _s(d, 10)
	var text: String = bs.st.talk(_id, num)
	_log("对白 单位%d 头像%d 表情%d 位置%d #%d %s" % [who, _s(d, 4), _s(d, 6), _s(d, 8), num, text.replace("\n", " ")])
	var u: BattleUnit = bs.unit(who) if who >= 0 else null
	if u and u.cx >= 0:
		await bs.story_cursor_to(u.cx, u.cy, _s(d, 2) == 1)  # 第 2 个参数 = 1: 光标滑过去 (实测 1 格/帧), 否则立即到位
	if text != "":
		await bs.msgbox.show_text(_s(d, 4), _s(d, 6), _s(d, 8), text)
	bs.hide_cursor()


func _show_units(_t: int, d: PackedByteArray) -> void:
	_log("显示单位 出场参数=%d" % _s(d, 0))
	bs.show_units(_s(d, 0), _s(d, 2))


func _show_units_var(_t: int, d: PackedByteArray) -> void:
	bs.show_units(gc.state.get_data(_s(d, 0)), _s(d, 2))


func _anim_add(_t: int, d: PackedByteArray) -> void:
	_log("登记动画 %d = Eanm_%02d" % [_s(d, 2), _s(d, 0)])
	bs.add_animation(_s(d, 2), _s(d, 0))


func _anim_play(_t: int, d: PackedByteArray) -> void:
	_log("播放动画 %d 帧 %d~%d" % [_s(d, 0), _s(d, 6), _s(d, 8)])
	await bs.play_animation(_s(d, 0), _s(d, 6), _s(d, 8))


## 原版 (->) 设起始帧后立即继续, 不阻塞
func _anim_start(_t: int, d: PackedByteArray) -> void:
	_log("开始动画 %d" % _s(d, 0))
	bs.play_animation(_s(d, 0), -1, -1)


func _anim_hide(_t: int, d: PackedByteArray) -> void:
	_log("隐藏动画 %d" % _s(d, 0))
	bs.clear_animation(_s(d, 0))


## 变量写入: 原版 只写变量, 值为 int32; 物件显隐由 LAYER effect 字段每帧读变量决定,
## 我们没有每帧检查, 改变量时立即同步一次 effect==var 的物件 (效果等价)
func _set_var(_t: int, d: PackedByteArray) -> void:
	var v := _i(d, 2)
	_log("变量 %d = %d" % [_s(d, 0), v])
	gc.state.set_data(_s(d, 0), v)
	bs.show_effect_parm(_s(d, 0), v)


func _var_add(_t: int, d: PackedByteArray) -> void:
	gc.state.set_data(_s(d, 0), gc.state.get_data(_s(d, 0)) + _i(d, 2))  # value 是 int32


func _var_odd(_t: int, d: PackedByteArray) -> void:
	gc.state.set_data(_s(d, 2), gc.state.get_data(_s(d, 0)) & 1)  # 是 & 1 (负数同样得 0/1)


func _turn_to_var(_t: int, d: PackedByteArray) -> void:
	gc.state.set_data(_s(d, 0), bs.turn)


## 原版: var[p0] -= p1 (int32)
func _var_sub(_t: int, d: PackedByteArray) -> void:
	gc.state.set_data(_s(d, 0), gc.state.get_data(_s(d, 0)) - _i(d, 2))


## 原版: var[p1] = 单位 p0 的格 x, var[p2] = 格 y
func _unit_pos_to_var(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	if u:
		gc.state.set_data(_s(d, 2), u.cx)
		gc.state.set_data(_s(d, 4), u.cy)
	_log("取单位 %d 坐标 -> 变量%d,%d" % [_s(d, 0), _s(d, 2), _s(d, 4)])


## 原版 (反算): 镜头格 = ((卷动x+10)/30, (卷动y+4)/24)
func _camera_cell_to_var(_t: int, d: PackedByteArray) -> void:
	var c: Vector2 = bs.orig_cam() + bs.cam_offset()
	gc.state.set_data(_s(d, 0), floori(c.x / BattleStage.CELL_W))
	gc.state.set_data(_s(d, 2), floori(c.y / BattleStage.CELL_H))


## 原版: 镜头平移到 (var[p0], var[p1]) 格, 速度 p2,p3, 阻塞
func _camera_pan_var(_t: int, d: PackedByteArray) -> void:
	var x := gc.state.get_data(_s(d, 0))
	var y := gc.state.get_data(_s(d, 2))
	_log("镜头平移(变量) -> (%d,%d)" % [x, y])
	await bs.pan_camera_to_cell(x, y, _s(d, 4), _s(d, 6))


## 原版: 单位 HP/MP 回满
func _heal_unit(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	if u:
		u.hp = u.hp_max
		u.mp = u.mp_max


## 原版: 屏幕震动开 (幅度 x,y 像素) / 关
func _shake_on(_t: int, d: PackedByteArray) -> void:
	bs.shake = Vector2(_s(d, 0), _s(d, 2))


func _shake_off(_t: int, _d: PackedByteArray) -> void:
	bs.shake = Vector2.ZERO


func _jump(_t: int, d: PackedByteArray) -> void:
	_step = _s(d, 0) - 1


func _cursor_center(_t: int, _d: PackedByteArray) -> void:
	bs.show_cursor(int((bs.cam.x + 160) / BattleStage.CELL_W), int((bs.cam.y + 100) / BattleStage.CELL_H))


func _cursor_hide(_t: int, _d: PackedByteArray) -> void:
	bs.hide_cursor()


func _layer_show(_t: int, d: PackedByteArray) -> void:
	_log("加载图层 %d" % _s(d, 0))
	bs.show_layer(_s(d, 0))


func _layer_unshow(_t: int, d: PackedByteArray) -> void:
	_log("卸载图层 %d" % _s(d, 0))
	bs.unshow_layer(_s(d, 0))


func _effect_show(_t: int, d: PackedByteArray) -> void:
	_log("显示地图物件 %d" % _s(d, 2))
	bs.show_effect(_s(d, 2))


func _effect_unshow(_t: int, d: PackedByteArray) -> void:
	bs.unshow_effect(_s(d, 2))


func _effect_play(_t: int, d: PackedByteArray) -> void:
	_log("播放地图物件 %d 帧 %d~%d" % [_s(d, 2), _s(d, 4), _s(d, 6)])
	await bs.play_once_effect(_s(d, 2), _s(d, 4), _s(d, 6))


func _movie(_t: int, d: PackedByteArray) -> void:
	_log("播放过场 Movie_%02d" % _s(d, 0))
	await bs.play_movie(_s(d, 0))
	if Content.is_ending_movie(_s(d, 0)):  # 结局过场 (内容包 manifest.ending_movies; 原版 Movie_13) 见 run()
		_ending_movie = true


func _unit_ai(_t: int, d: PackedByteArray) -> void:
	_log("单位 %d AI=%d" % [_s(d, 0), _s(d, 2)])
	var u: BattleUnit = bs.unit(_s(d, 0))
	if u:
		u.set_ai(_s(d, 2), _s(d, 4), _s(d, 6))


## 原版 0x36: 对每个单位调 12 次 (单位, 效果号, 0) = 只清【状态特效的显示标志】(字段 的状态光环动画),
## **不碰状态位 字段 与各状态的 R/K** [实机: 第一关事件 2 (开头 clear_status) 真实执行后, 殷剑平写入的攻击提昇 (0x1, R300 K100) 仍在;
## 旧复刻/旧规格「清除所有单位状态异常」不成立]。召唤物 (字段>0): 未装备物品倒回行囊 、+8=0 退场, **不清 字段 与标志变量 103~106**
## (实机: 退场后 var103 仍为 1, 字段 仍为 103 [实机复核])。不隐藏敌人。
## 原版漏 break 落入 0x37, 把下一条指令的类型号当变量号写入敌人数, 经核对对剧情无影响, 不模拟
func _clear_status(_t: int, _d: PackedByteArray) -> void:
	_log("清除状态特效 (状态位不变)")
	for u in bs.units:
		if u.summoned and u.alive:
			u.dump_items_to_bag()
			u.hide_unit()
			u.alive = false


func _count_enemies(_t: int, d: PackedByteArray) -> void:
	var n := 0
	for u in bs.units:
		if u.camp == 1 and u.alive and u.shown and not u.st.annihilation_exempt:  # 排除 字段 (齐祀)
			n += 1
	gc.state.set_data(_s(d, 0), n)


## 更换装备 (单位, 物品)
func _equip(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	if u:
		u.equip_item(_s(d, 2))
	_log("单位 %d 装备 %d" % [_s(d, 0), _s(d, 2)])


## 单位存活且受过伤 -> 变量
func _unit_hurt_to_var(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	gc.state.set_data(_s(d, 2), 1 if u and u.hp != u.hp_max else 0)  # 只看 hp≠hpmax, 不查存活


## 变量所指单位淡出
func _fade_unit_of_var(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(gc.state.get_data(_s(d, 0)))
	if u:
		u.fade_out()
		await SceneGuard.wait(self, 0.55)  # 阻塞到淡出结束 (同 0x09 类别淡出)


## 复制单位属性 (id1 -> id2)
func _copy_stats(_t: int, d: PackedByteArray) -> void:
	# p0 是角色 id (名册), 不是单位下标: 取我方单位里 unit_id == p0 的那个, 找不到才退回按下标
	var a: BattleUnit = null
	for cand in bs.units:
		if cand.camp == 0 and int(cand.man["unit_id"]) == _s(d, 0):
			a = cand
			break
	if a == null:
		a = bs.unit(_s(d, 0))
	var b: BattleUnit = bs.unit(_s(d, 2))
	if a and b:
		b.stats = a.stats.duplicate()
		b.lv = a.lv
		b.hp_max = a.hp_max
		b.hp = a.hp_max
		b.mp_max = a.mp_max
		b.mp = a.mp_max
		# -> -> 按名册记录整条重设单位: 装备、10 格物品栏、10 格技能也一并复制 (对照原版: 复制 字段、字段 起 20 字节、字段 起 20 字节)
		# (第 19 关紫枫替身 u48 先成为紫枫的完整副本, 再 equip 357 在原位替换她的武器,)
		b.st.weapon = a.st.weapon
		b.st.armor = a.st.armor
		b.st.accessory = a.st.accessory
		b.st.items = a.st.items.duplicate()
		b.st.skills = a.st.skills.duplicate()   # 同一段复制里还有 字段 起 10 格技能


## 我方/友军切换: 0 = 友军加入我方, 否则我方转为友军并走向地图事件点
func _camp_switch(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	if u:
		u.set_npc(_s(d, 2) != 0)   # 只写 字段, AI 类型由随后的 0x2F 另设


## 单位当前武器 -> 变量
func _weapon_to_var(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 0))
	var w = u.gear.get("weapon") if u else null
	gc.state.set_data(_s(d, 2), -1 if w == null else int(w))


## 我方与友军全体受到体力上限 33% 的伤害 (重制版 damageAllUser)
func _damage_all(_t: int, _d: PackedByteArray) -> void:
	_log("事件伤害: 我方全体")
	await bs.ctl.event_damage(-1)


## 指定主角 (unit_id) 受到体力上限 33% 的伤害 (重制版 damageUser)
func _damage_unit(_t: int, d: PackedByteArray) -> void:
	_log("事件伤害: 单位 %d" % _s(d, 0))
	await bs.ctl.event_damage(_s(d, 0))


## 原版: var[p1] = 在场玩家单位 (阵营 0 且非 AI) 全都 y >= p0 (第 24 关撤离)
func _all_y_ge(_t: int, d: PackedByteArray) -> void:
	var ok := _all_players(func(u): return u.cy >= _s(d, 0))
	_log("全员 y>=%d -> 变量%d = %d" % [_s(d, 0), _s(d, 2), ok])
	gc.state.set_data(_s(d, 2), ok)


## 原版: var[p1] = 在场玩家单位全都 x <= p0 (第 26 关)
func _all_x_le(_t: int, d: PackedByteArray) -> void:
	var ok := _all_players(func(u): return u.cx <= _s(d, 0))
	_log("全员 x<=%d -> 变量%d = %d" % [_s(d, 0), _s(d, 2), ok])
	gc.state.set_data(_s(d, 2), ok)


## 原版: 单位 p1 装备 var[p0] 里存的物品 (第 28 关装回 0x45 存进 var15 的武器)
func _equip_from_var(_t: int, d: PackedByteArray) -> void:
	var u: BattleUnit = bs.unit(_s(d, 2))
	var it := gc.state.get_data(_s(d, 0))
	_log("单位 %d 装备 变量%d = %d" % [_s(d, 2), _s(d, 0), it])
	if u and it >= 0:
		u.equip_item(it)


## 原版: 名册里角色 p0 的在队标志 = p1 (0 离队, 1 入队)。
## 复刻没有名册结构, 记在剧情变量 ROSTER_OUT + 角色号 (1 = 离队, 随存档保存), 供出战/营地列表读取
func _roster(_t: int, d: PackedByteArray) -> void:
	_log("角色 %d %s" % [_s(d, 0), "入队" if _s(d, 2) != 0 else "离队"])
	gc.state.set_data(ROSTER_OUT + _s(d, 0), 0 if _s(d, 2) != 0 else 1)


## 原版 (->): 持有就收走 (先查在场单位装备, 饰品等会卸下; 再查各人 10 格、行囊), var[p1] = 1/0
func _take_item_op(_t: int, d: PackedByteArray) -> void:
	var ok := _take_item(_s(d, 0))
	_log("收走物品 %d -> 变量%d = %d" % [_s(d, 0), _s(d, 2), ok])
	gc.state.set_data(_s(d, 2), ok)



## 0x0F 的直角折线: 从当前格先沿 x 走到目标列再沿 y (vfirst 时反之), 不看地形与占位
func _line_path(u: BattleUnit, tx: int, ty: int, vfirst: bool) -> Array:
	var path: Array = []
	var c := Vector2i(u.cx, u.cy)
	for axis in ([1, 0] if vfirst else [0, 1]):
		while c[axis] != (ty if axis == 1 else tx):
			c[axis] += signi((ty if axis == 1 else tx) - c[axis])
			path.append(c)
	return path


## 0x09/0x0A p0=-1 的类别: 0 玩家单位 (阵营 0 非 AI), 1 友军 NPC, 2 敌人 (docs/剧情脚本格式.md 2.1)
func _group(g: int) -> Array:
	return bs.units.filter(func(u): return u.shown and [u.controllable, u.camp == 2 or (u.camp == 0 and not u.controllable), u.camp == 1][clampi(g, 0, 2)])


## 0x47/0x48: 在场 (存活且显示) 的玩家单位 (阵营 0, 非 AI 控制) 是否都满足 cond; 返回 1/0
func _all_players(cond: Callable) -> int:
	for u in bs.units:
		if u.alive and u.shown and u.controllable and not cond.call(u):
			return 0
	return 1


## 0x53: 按单位顺序查我方 (阵营 0) 单位的 10 格, 第一个有的就从那格拿走 (后面各格前移), 若是装备着的饰物则卸下;
## 单位里都没有再查公共行囊。原版不单独查「装备」: 装备只是引用 10 格里的物品。找到返回 1
func _take_item(id: int) -> int:
	for u in bs.units:
		if u.camp != 0 or not u.st.items.has(id):
			continue
		u.st.items.erase(id)
		for slot in ["weapon", "armor", "accessory"]:  # 原版只清饰物 (字段); 复刻对不再持有的装备一并卸下, 免得凭空留着
			if int(u.st.get(slot)) == id and not u.st.items.has(id):
				u.st.set(slot, -1)
				u.taken.append(id)
		return 1
	if id in gc.state.bag:
		gc.state.bag.erase(id)
		return 1
	return 0


## 0x12 屏幕遮罩: 画面先向 color 混色 mix/16, 再乘亮度 light/16 (都是 0~16)
var _mask_dim: ColorRect

func _set_mask(mix: int, light: int, col := Color.WHITE) -> void:
	if _mask_dim == null:
		_mask_dim = ColorRect.new()
		_mask_dim.color = Color(0, 0, 0, 0)
		_mask_dim.size = bs._white.size
		_mask_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bs._white.get_parent().add_child(_mask_dim)
		bs.cover(_mask_dim)   # 同白场: 跟窗口走, 宽屏/全屏时盖满整屏 (原先按 320x200 固定大小, 全屏时只暗中间一块)
	bs._white.color = Color(col, clampf(mix / 16.0, 0, 1))
	_mask_dim.color.a = clampf(1.0 - light / 16.0, 0, 1)


## 0x12: 混色从 mix_from 每次 ±mix_step 到 mix_to, 亮度同理; 每 (delay+1) 帧变一次, 两项都到终值才继续
func _screen_fade(c: int, m0: int, m1: int, ms: int, l0: int, l1: int, ls: int, delay: int) -> void:
	var col := Color8(((c >> 10) & 31) << 3, ((c >> 5) & 31) << 3, (c & 31) << 3)
	_log("屏幕渐变 色%04X 混色 %d->%d/%d 亮度 %d->%d/%d 间隔 %d" % [c, m0, m1, ms, l0, l1, ls, delay])
	var m := m0
	var l := l0
	_set_mask(m, l, col)
	while m != m1 or l != l1:
		await SceneGuard.wait(self, (delay + 1) / 25.0)
		m = mini(m + ms, m1) if m < m1 else maxi(m - ms, m1)
		l = mini(l + ls, l1) if l < l1 else maxi(l - ls, l1)
		if (m != m1 and ms <= 0) or (l != l1 and ls <= 0):  # 步长为 0 永远到不了 (原版会卡住), 直接到终值
			m = m1
			l = l1
		_set_mask(m, l, col)
	await wait_frames(1)  # 原版状态机下一帧才发现两项都到终值


func _start_move(u: BattleUnit, path: Array) -> void:
	_moved += 1
	if path.is_empty():
		return
	var speed := maxf(BattleStage.WALK_SPEED - _move_speed * 25.0, 35.0)
	u.walk(path, speed)
	_pending_moves.append(u)
	if _move_follow > 0:
		bs.follow_cell(path[-1].x, path[-1].y)
	_move_follow = 0


## 剧情让单位走出地图 (如第 0 幕结尾小师妹走下山) 算离场: 原版走到画面外就看不见, 脚本里没有退场指令;
## 复刻的镜头跟着走 / 宽屏看得见画面外, 她会站在边上不退场。走到地图格子之外就不再画 (在场标志和坐标不动), 再 place / 走动就恢复
func _leave_if_off_map(u: BattleUnit) -> void:
	if u.shown and (u.cx < 0 or u.cy < 0 or u.cx >= bs.st.width or u.cy >= bs.st.height):
		u.visible = false


## 一批移动 (0x0E/0x10 声明的数量) 全部下达后, 等所有单位走完才继续
func _after_move() -> void:
	if _moved < _move_count:
		return
	for u in _pending_moves:
		if not u._path.is_empty():
			await u.move_finished
		_leave_if_off_map(u)
	_pending_moves.clear()

# SPDX-License-Identifier: GPL-3.0-only
extends Node2D
## 战斗场景: 图层、镜头、单位、光标、演出动画、黑白场、过场视频、音乐。
## 流程参照重制版 GameSceneManager(StartBattle) + GameBattleTurn.start:
##   显示图层 1 -> 本关音乐 -> 布置单位 -> 显示出场参数为 0 的单位 -> 触发回合开始事件 (TEVT)。
## 坐标: 原版像素; 图层 id 的内容放在 y = id * 5000 处, cam 是当前图层内的视口左上角。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal camera_arrived

var SCREEN: Vector2 = UiLayout.base_size()  # 原版画面大小 (布局表 base_size)
## 镜头对准格时的余量 (布局表 map.camera_offset: 卷动 = 格*30-10, 格*24-4)
static func cam_offset() -> Vector2:
	return UiLayout.at("map.camera_offset")

var st: BattleStage
var vm: EventVM
var ctl: BattleController
var world: Node2D
var units_node: Node2D
var units: Array = []          # BattleUnit, 下标 = 单位编号
var layer_list: Array = []     # 已加载的图层 id, 最后一个为当前图层
var layer_y := 0.0
var cam := Vector2.ZERO
var _cam_target := Vector2.ZERO
var _cam_speed := Vector2.ZERO
var _cam_moving := false
var objs0 := {}                # L0 下标 -> 节点
var objs1 := {}                # L1 下标 -> AnimPlayer
var layer_size := {}           # 图层 id -> 地图尺寸
var _parallax: Array = []      # 远景图 (L0 尺寸参数不是 10x8): 跟随镜头视差滚动, 画在当前场景后面
var anims := {}                # 事件动画 (0x18) id -> AnimPlayer
var last_unit_id := -1         # 事件动画跟随的单位 (原 0x3C 的重制版语义; 0x3C 实为取坐标, 现无人设置)
var shake := Vector2.ZERO      # 0x50/0x51 屏幕震动幅度 (像素)
var cursor: AnimPlayer
var msgbox: MsgBox
var _black: ColorRect
var _white: ColorRect
var music := SceneMusic.new(self)  # 音乐通道
var turn := 1


static func create(n: int) -> Node2D:
	var s: Node2D = (load("res://engine/battle/battle_scene.gd") as GDScript).new()
	s.st = BattleStage.load_stage(n)
	return s


func _ready() -> void:
	scale = Vector2.ONE * Assets.SCALE
	# 宽屏扩展视野 (docs/架构设计.md 6.5): 地图从屏幕左上角起画, 视口 = 逻辑画面 (view()), 地图够宽就多显示, 不够宽则居中。
	# 16:10 下 view = 320x200, 与原版逐像素相同
	ScreenLayout.bind_node(self, ScreenLayout.Anchor.TOP_LEFT)
	ScreenLayout.changed.connect(func(): cam = _clamp_cam(cam))
	world = Node2D.new()
	add_child(world)
	units_node = Node2D.new()
	units_node.z_index = 10
	units_node.y_sort_enabled = true  # 人物按纵坐标排前后: 靠下的挡住靠上的 (走动中实时更新)
	world.add_child(units_node)
	cursor = AnimPlayer.new()
	cursor.play_sound = false
	cursor.visible = false
	cursor.z_index = -1  # 选择框画在人物下面 (范围色块之上)
	units_node.add_child(cursor)
	var fx := CanvasLayer.new()
	fx.layer = 40
	add_child(fx)
	_black = _overlay(fx, Color.BLACK)
	_white = _overlay(fx, Color.WHITE)
	cover(_black)  # 黑白场铺满全屏
	cover(_white)
	msgbox = MsgBox.new()
	add_child(msgbox)
	vm = EventVM.new(self)
	add_child(vm)
	ctl = BattleController.new(self)
	add_child(ctl)
	await _start()


const COVER_MARGIN := 2048.0   # 遮罩四边多铺的像素: 任何窗口 / 全屏 / 宽屏都不露边

## 盖满整个屏幕 (宽屏/全屏也盖满, 跟窗口走): 黑白场、剧情遮罩、标题卡黑底共用
func cover(c: Control) -> void:
	ScreenLayout.cover(c, COVER_MARGIN)


func _overlay(parent: Node, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(c, 0.0)
	r.size = SCREEN * Assets.SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _start() -> void:
	show_layer(1)
	play_music(0, st.music)
	for i in st.man.size():
		var p: Dictionary = st.xy[i] if i < st.xy.size() else {"x": 0, "y": 0}
		var u := BattleUnit.create(i, st.man[i], int(p["x"]), int(p["y"]), ctl.rules.ctx)
		units_node.add_child(u)
		units.append(u)
	show_units(0, 0)
	RegressLog.provide("battle", regress_state)
	tree_exiting.connect(func(): RegressLog.drop("battle", self))
	RegressLog.checkpoint("battle_start", {"stage": st.n})
	if not gc.battle_resume.is_empty():  # 戰陣重現: 恢复存录时的战场, 不再播开场事件
		var d: Dictionary = gc.battle_resume
		gc.battle_resume = {}
		restore(d)
		await ctl.run(d["ctl"])
		return
	if await BattleTestHooks.inject(self):   # 测试: 开场注入 (剧情分支验证, engine/test/battle_test_hooks.gd)
		return
	# 开场事件就是第 1 回合 type 0 的 TEVT, 由回合流程在陽之陣横幅、友军结算之后执行
	print("进入战斗")
	await ctl.run()


func _process(delta: float) -> void:
	if _cam_moving:
		cam.x = move_toward(cam.x, _cam_target.x, _cam_speed.x * delta)
		cam.y = move_toward(cam.y, _cam_target.y, _cam_speed.y * delta)
		if cam.is_equal_approx(_cam_target):
			_cam_moving = false
			camera_arrived.emit()
	world.position = -(cam + Vector2(0, layer_y)).round()
	if shake != Vector2.ZERO:
		world.position += Vector2(randf_range(-shake.x, shake.x), randf_range(-shake.y, shake.y)).round()
	units_node.position.y = layer_y
	# 远景视差: 镜头在场景里的可移动范围映射到远景图的可移动范围
	var v := view()
	var msize: Vector2 = layer_size.get(_current_layer(), v)
	for p in _parallax:
		if p.has_meta("pinned"):
			p.position = cam + Vector2(0, layer_y)
			p.scale = Vector2.ONE * maxf(v.x / SCREEN.x, v.y / SCREEN.y)   # 宽屏/全屏: 背板等比放大盖满视口 (16:10 下恒为 1)
			continue
		var bsize: Vector2 = p.get_meta("size")
		var k := Vector2(
			(bsize.x - v.x) / maxf(1, msize.x - v.x) if msize.x > v.x else 0.0,
			(bsize.y - v.y) / maxf(1, msize.y - v.y) if msize.y > v.y else 0.0)
		p.position = cam - cam * k + Vector2(0, layer_y)


## 战阵存录: 回合、图层、地图物件、镜头、单位
func snapshot() -> Dictionary:
	var o1 := {}
	for j in objs1:
		var a: AnimPlayer = objs1[j]
		o1[str(j)] = {"visible": a.visible, "playing": a.playing, "frame": a.frame, "dir": a.dir, "x": a.position.x, "y": a.position.y}
	return {"turn": turn, "layers": layer_list, "cam": [cam.x, cam.y], "objs1": o1,
		"units": units.map(func(u): return u.snapshot()), "ctl": ctl.snapshot()}


## 校验战阵存录里的战场快照 (restore 之前; 手改/损坏的存录不能让战场场景脚本报错): 通过返回 "", 否则返回提示文字
static func validate_snapshot(d: Variant) -> String:
	var bad := UiStrings.t("save.bad_battle")
	if not d is Dictionary:
		return bad
	var num := func(v): return (v is int or v is float) and is_finite(float(v))
	if not num.call(d.get("turn")) or not d.get("layers") is Array or not (d["layers"] as Array).all(num):
		return bad
	if not (d.get("cam") is Array and d["cam"].size() == 2 and (d["cam"] as Array).all(num)):
		return bad
	if not d.get("objs1") is Dictionary:
		return bad
	for k in d["objs1"]:
		var o = d["objs1"][k]
		if not (String(k).is_valid_int() and o is Dictionary and num.call(o.get("x")) and num.call(o.get("y")) and num.call(o.get("frame"))
				and o.get("visible") is bool and o.get("playing") is bool and o.get("dir") is String):
			return bad
	if not d.get("units") is Array:
		return bad
	for u in d["units"]:
		if not (u is Dictionary and u.get("shown") is bool and num.call(u.get("dir")) and u.get("st") is Dictionary):
			return bad
	if not (d.get("ctl") is Dictionary and d["ctl"].get("map_events") is Array):
		return bad
	return ""


## 把存录里一个地图物件的状态套到动画节点 a 上: 位置、可见、播放中 / 停在某帧 / 帧 -1 (从没画过帧, 什么都不画)
static func apply_obj_snapshot(a, o: Dictionary) -> void:
	a.position = Vector2(o["x"], o["y"])
	a.visible = o["visible"]
	if String(o["dir"]) == "":
		return
	if o["playing"]:
		a.play(o["dir"])
	elif int(o["frame"]) >= 0:
		a.show_frame(o["dir"], int(o["frame"]))
	else:
		a.dir = o["dir"]   # 帧 -1 = 从没画过帧 (物件「可见」但无内容, 如第 3 幕的事件人物): 不能当第 0 帧画, 否则读档后背景上冒出一堆人物贴图


func restore(d: Dictionary) -> void:
	turn = int(d["turn"])
	for id in layer_list.duplicate():
		unshow_layer(id)
	for id in d["layers"]:
		show_layer(int(id))
	for k in d["objs1"]:
		var j := int(k)
		var o: Dictionary = d["objs1"][k]
		var a: AnimPlayer = objs1.get(j)
		if a == null:
			a = AnimPlayer.new()
			a.play_sound = false
			world.add_child(a)
			objs1[j] = a
		apply_obj_snapshot(a, o)
	for i in mini(units.size(), d["units"].size()):
		units[i].restore(d["units"][i])
	cam = Vector2(d["cam"][0], d["cam"][1])


## 确定性回归的战场状态 (engine/test/regress_log.gd): 回合、随机数、未触发的地图事件、全部单位
func regress_state() -> Dictionary:
	var ev: Array = ctl.flow.map_events.keys()
	ev.sort()
	return {"stage": st.n, "turn": turn, "rng": ctl.rules.ctx.rng.get_state(), "map_events": ev,
		"units": units.map(func(u): return {"shown": u.shown, "summon_flag": u.summon_flag, "taken": u.taken, "st": u.st.to_dict()})}


## 关卡结束: 把我方主角的成长写回 Game.state.party
func save_party() -> void:
	for u in units:  # 战斗结束: 还活着的召唤物把未装备物品倒进行囊
		u.dump_items_to_bag()
	var best := {}  # 同一主角可能在 MAN 里出现多次 (分身/剧情用), 取成长最多的那个
	for u in units:
		var uid := int(u.man["unit_id"])
		if Content.is_hero(uid) and u.camp == 0:
			if not best.has(uid) or u.lv * 1000 + u.exp > best[uid].lv * 1000 + best[uid].exp:
				best[uid] = u
	for uid in best:
		gc.state.party[uid] = best[uid].to_party()


# ---------------- 图层 ----------------

## 重制版 GameBattleManager.showLayer: 加载该 id 的底图 (L0) 与物件 (L1), 并成为当前图层
func show_layer(id: int) -> void:
	# 只含远景图的图层 (如第零幕的云海 map00-3) 不是独立场景, 叠在当前场景后面
	var only_bg := not layer_list.is_empty()
	for l in st.layers0:
		if int(l["id"]) == id and _is_main_map(l):
			only_bg = false
	layer_list.append(id)
	if not only_bg:
		layer_y = id * BattleStage.LAYER_GAP
	print("  图层 %d 加载, 仅远景=%s, 当前 y=%d" % [id, only_bg, layer_y])
	if layer_list.size() == 1:
		move_camera_to_cell(0, 0)
	for j in st.layers0.size():
		var l: Dictionary = st.layers0[j]
		if int(l["id"]) != id or objs0.has(j):
			continue
		var bg_anim := st.bg_anim(l)
		if bg_anim != "":
			var a := AnimPlayer.new()
			a.position = Vector2(0, layer_y)
			world.add_child(a)
			a.play(bg_anim)
			objs0[j] = a
			# 动画远景 (第 19 幕云海 Eanm_09, 尺寸参数 0x0) 是 320x200 一屏大的背板: 钉在画面上不随镜头走 (以前钉在世界原点,
			# 镜头到龙身那半边就看不到云, 龙身后面是一片黑)。两份循环错开 320 正好首尾相接, 贴图右/下是透明留白,
			# 线性过滤会在接缝处混进透明, 露一条黑细线: 每份只取 320x200 内容并按区域夹边
			if not _is_main_map(l):
				a.z_index = -20
				a.clip_to = SCREEN
				a.set_meta("pinned", true)
				_parallax.append(a)
		else:
			var spr := Sprite2D.new()
			spr.centered = false
			var t := Assets.tex(st.bg_image(l))
			spr.texture = t["texture"]
			spr.scale = Vector2.ONE * float(t["scale"])
			spr.texture_filter = TextureSource.filter_for(t["hd"])
			spr.position = Vector2(0, layer_y)
			spr.z_index = -10
			world.add_child(spr)
			objs0[j] = spr
			if not _is_main_map(l):
				spr.z_index = -20
				spr.set_meta("size", Vector2(t["texture"].get_size()) * float(t["scale"]))
				_parallax.append(spr)
			elif not layer_size.has(id):
				layer_size[id] = Vector2(t["texture"].get_size()) * float(t["scale"])
	for j in st.layers1.size():
		var o: Dictionary = st.layers1[j]
		if int(o["id"]) != id:
			continue
		var a := AnimPlayer.new()
		a.play_sound = false
		a.position = Vector2(o["x"], int(o["y"]) + layer_y)
		world.add_child(a)
		objs1[j] = a
		var vis := int(o["visible"]) == 0
		if int(o["effect"]) != -1:
			vis = vis and gc.state.get_data(int(o["effect"])) > 0
		var dir := st.obj_anim(o)
		if not vis:
			a.dir = dir
			continue
		if int(o["pause"]) == 2:
			a.show_frame(dir, 0)
		else:
			a.play(dir)


func unshow_layer(id: int) -> void:
	layer_list.erase(id)
	for j in st.layers0.size():
		if int(st.layers0[j]["id"]) == id and objs0.has(j):
			objs0[j].queue_free()
			objs0.erase(j)
	for j in st.layers1.size():
		if int(st.layers1[j]["id"]) == id and objs1.has(j):
			objs1[j].queue_free()
			objs1.erase(j)
	_parallax = _parallax.filter(func(p): return is_instance_valid(p) and not p.is_queued_for_deletion())
	if not layer_list.is_empty():
		layer_y = _current_layer() * BattleStage.LAYER_GAP


## L0 的尺寸参数为 10x8 (一屏) 的是场景主图, 其他 (如 2x2) 是远景
static func _is_main_map(l: Dictionary) -> bool:
	return int(l["u4"]) == 10 and int(l["u5"]) == 8


func _current_layer() -> int:
	for i in range(layer_list.size() - 1, -1, -1):
		if layer_size.has(layer_list[i]):
			return layer_list[i]
	return layer_list[-1] if not layer_list.is_empty() else 1


## 0x1E: 效果参数为 s1 的物件, s2=0 隐藏, 否则播放 (pause=0) 或显示第 0 帧
func show_effect_parm(s1: int, s2: int) -> void:
	for j in objs1:
		var o: Dictionary = st.layers1[j]
		if int(o["effect"]) != s1:
			continue
		var a: AnimPlayer = objs1[j]
		if s2 == 0:
			a.visible = false
		else:
			a.visible = true
			if int(o["pause"]) == 0:
				a.play(a.dir)
			else:
				a.show_frame(a.dir, 0)


## 0x25: 显示参数为 id 的地图物件 (重制版 showEffect(id, s)): 已加载则播放 (pause=0) 或显示第 0 帧, 未加载则在镜头处创建
func show_effect(id: int) -> void:
	for j in st.layers1.size():
		var o: Dictionary = st.layers1[j]
		if int(o["parm"]) != id:
			continue
		var dir := st.obj_anim(o)
		var a: AnimPlayer = objs1.get(j)
		if a == null:
			a = AnimPlayer.new()
			a.play_sound = false
			a.position = orig_cam() + Vector2(0, layer_y)
			world.add_child(a)
			objs1[j] = a
		a.dir = dir
		a.visible = true
		if int(o["pause"]) == 0:
			a.play(dir)
		else:
			a.show_frame(dir, 0)


## 0x26: 隐藏参数为 id 的地图物件
func unshow_effect(id: int) -> void:
	for j in st.layers1.size():
		if int(st.layers1[j]["parm"]) == id and objs1.has(j):
			objs1[j].visible = false
			objs1[j].playing = false


## 剧情「播放一次」的地图物件 (如第 8 幕朱慎攻击法阵) 的动画帧带音效 (Eanm 的 s0~sN.wav), 播的时候要出声; 平时静置/循环的物件仍静音
## (否则每圈都响)。开声音, 播完 (finished) 再关回去
static func one_shot_sound(a) -> void:
	a.play_sound = true
	a.finished.connect(func(): a.play_sound = false, CONNECT_ONE_SHOT)


## 单帧 (from==to) 的 obj_play: 显示该帧并播这一帧的声音 (同一帧已经显示着不重复播)
static func single_frame_sound(a, frame: int) -> void:
	a.play_sound = true
	a.show_frame(a.dir, frame)
	a.play_sound = false


## 0x28: 播放一次参数为 id 的地图物件 [frame, end] (重制版 playOnceEffect), 等第一个播完
func play_once_effect(id: int, frame: int, end_frame: int) -> void:
	var waiting: AnimPlayer = null
	for j in st.layers1.size():
		var o: Dictionary = st.layers1[j]
		if int(o["parm"]) != id or not objs1.has(j):
			continue
		var a: AnimPlayer = objs1[j]
		# effect 变量只管画不画 (为 0 不画), 不管播不播: 原版 obj_play 的帧推进、发声、阻塞照常 (0x4212 绘制循环只看变量决定画不画;
		# 第 8 幕朱慎攻击法阵前脚本先把变量 1 置 0 再 obj_play obj0 —— 原先整段跳过, 法阵音效丢了; 审计 2026-10-12, 差异)
		a.visible = int(o["effect"]) == -1 or gc.state.get_data(int(o["effect"])) != 0
		if frame < 0:
			if int(o["pause"]) == 0:
				a.show_frame(a.dir, maxi(end_frame, 0))
			else:
				one_shot_sound(a)
				a.play(a.dir, 0, -1, false)
				if waiting == null:
					waiting = a
		elif frame == end_frame:
			single_frame_sound(a, end_frame)   # from==to 的单帧: 原版开头就播该帧声音
		else:
			one_shot_sound(a)
			a.play(a.dir, frame, end_frame + 1, false)
			if waiting == null:
				waiting = a
	if waiting:
		await waiting.finished
		waiting.show_frame(waiting.dir, waiting.end_frame - 1)


# ---------------- 镜头 ----------------

## 可见的地图区域大小 (原版像素) = 逻辑画面; 第一版 16:10 恒为 320x200。
## 触摸界面 (keep_side_margins) 左右留边给虚拟键, 地图只占安全区宽度 (纵向仍随画面)
func view() -> Vector2:
	var s: Vector2 = ScreenLayout.size
	return Vector2(SCREEN.x, s.y) if ScreenLayout.keep_side_margins else s


## 镜头夹紧: cam ∈ [0, 地图 − view]; 地图某一维比 view 小时这一维居中 (cam 为负, 两边露出黑底)
func _clamp_cam(p: Vector2) -> Vector2:
	var v := view()
	var size: Vector2 = layer_size.get(_current_layer(), SCREEN)
	var out := p
	for ax in 2:
		if size[ax] <= v[ax]:  # 比原版画面还小的地图照原版从 0 起 (16:10 下与原版一致), 宽出来的部分两边平分
			out[ax] = -(v[ax] - maxf(size[ax], SCREEN[ax])) / 2.0
		else:
			out[ax] = clampf(p[ax], 0.0, size[ax] - v[ax])
	return out


## 剧情镜头 (0x07/0x08/0x3E): 原版 Camera 不夹地图, 目标 = (格*30-10, 格*24-4) 原样 (实测, 越界处画黑;
## 数据里 760 条镜头指令有 200 条越出夹紧范围几个像素~十几像素)。地图比视口小的轴仍按 _clamp_cam 居中
func _script_cam(p: Vector2) -> Vector2:
	var v := view()
	var size: Vector2 = layer_size.get(_current_layer(), SCREEN)
	var c := _clamp_cam(p)
	var out := p
	for ax in 2:
		if size[ax] <= v[ax]:
			out[ax] = c[ax]
	return out


## 原版镜头位置 (按 320x200 求) 换到当前视口: 让原版想看的区域仍在画面中间
func _orig_to_view(p: Vector2) -> Vector2:
	return p - (view() - SCREEN) / 2.0


## 当前视口里与原版 320x200 镜头对应的左上角 (剧情动画、物件按原版镜头摆放)
func orig_cam() -> Vector2:
	return cam + (view() - SCREEN) / 2.0


## 当前图层在 world 里的矩形 (地图尺寸, 没有记录时按一屏)
func layer_rect() -> Rect2:
	return Rect2(Vector2(0, layer_y), layer_size.get(_current_layer(), SCREEN))


func _cell_px(x: int, y: int) -> Vector2:
	return Vector2(x * BattleStage.CELL_W, y * BattleStage.CELL_H)


## 0x07: 视口左上角移到格子 (x, y) (立即)
func move_camera_to_cell(x: int, y: int) -> void:
	cam = _script_cam(_orig_to_view(_cell_px(x, y) - cam_offset()))
	_stop_cam()


## 打断正在进行的平移: 仍要发 camera_arrived, 否则在等平移结束的剧情 (0x08)、跟随 (follow_cell) 永远等不到而卡死
func _stop_cam() -> void:
	if _cam_moving:
		_cam_moving = false
		camera_arrived.emit()


## 平移速度来自剧情脚本 (s16) 或演出表: 0/负数会让 move_toward 永不到达或反向走, camera_arrived 永远不发, 剧情卡死。至少 1 像素/秒
static func _valid_cam_speed(v: Vector2) -> Vector2:
	return Vector2(maxf(v.x, 1.0), maxf(v.y, 1.0))


## 0x08: 以 map.camera_offset.pan_speed (sx*5+20, sy*5+20) 像素/秒 平移到格子 (x, y)
func pan_camera_to_cell(x: int, y: int, sx: int, sy: int) -> void:
	_cam_target = _script_cam(_orig_to_view(_cell_px(x, y) - cam_offset()))
	_cam_speed = _valid_cam_speed(UiLayout.vec_of("map.camera_offset", "pan_speed", {"sx": sx, "sy": sy}))
	if cam.is_equal_approx(_cam_target):
		return
	_cam_moving = true
	await camera_arrived


## 演出镜头: 平移到原版镜头位置 p (320x200 视口左上角, 如 FxPlace.center_cam), 换到当前视口并夹在地图内; speed 像素/秒
func pan_camera_to(p: Vector2, speed: Vector2) -> void:
	_cam_target = _clamp_cam(_orig_to_view(p))
	_cam_speed = _valid_cam_speed(speed)
	if cam.is_equal_approx(_cam_target):
		_stop_cam()  # 已在目标: 若还有平移在等 camera_arrived, 要把它放行 (不能只清标志)
		return
	_cam_moving = true
	await camera_arrived


## 触摸拖动卷动地图 (统一输入层 DRAG): 镜头平移 d (原版像素), 夹在地图内
func scroll_camera(d: Vector2) -> void:
	_stop_cam()
	cam = _clamp_cam(cam + d)


## 让镜头跟随某个格子 (说话、移动时), 格子不在可视范围内才移动
func follow_cell(x: int, y: int) -> void:
	var p := _cell_px(x, y)
	var v := view()
	var cell := _cell_px(1, 1)
	var m := UiLayout.num("map.camera_offset", "follow_margin")
	var rect := Rect2(cam + cell * m, v - cell * m - cell * m - cell)  # 可见区四边各缩 m 格, 再扣一格 (格左上角判定)
	if rect.has_point(p):
		return
	_cam_target = _clamp_cam(p - v / 2 + cell / 2)
	_cam_speed = UiLayout.vec("map.camera_offset", "follow_speed")
	_cam_moving = true
	await camera_arrived


# ---------------- 单位与光标 ----------------

func unit(i: int) -> BattleUnit:
	return units[i] if i >= 0 and i < units.size() else null


## 0x17 / 开场: 出场参数为 parm 的单位现身 (重制版 GameBattleUnitManager.showUnits)
func show_units(parm: int, _check: int) -> void:
	for i in st.man.size():
		var ep: Array = st.man[i]["event_parm"]
		if int(ep[0]) != parm:
			continue
		var u: BattleUnit = units[i]
		var p: Dictionary = st.xy[i] if i < st.xy.size() else {"x": u.cx, "y": u.cy}  # XY 表比 MAN 短 (第 12 关)
		var c := _free_cell(Vector2i(int(p["x"]), int(p["y"])), u)  # 被占用时找最近的空格 (重制版 findNearPos)
		u.set_cell(c.x, c.y)
		u.alive = true
		u.show_unit(BattleUnit.Dir.SOUTH)


func _occupied(c: Vector2i, except: BattleUnit) -> bool:
	for o in units:
		if o != except and o.shown and o.alive and o.cx == c.x and o.cy == c.y:
			return true
	return false


func _free_cell(c: Vector2i, u: BattleUnit) -> Vector2i:
	if not _occupied(c, u):
		return c
	var seen := {c: true}
	var q: Array = [c]
	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if seen.has(n) or st.cell(n.x, n.y).is_empty():
				continue
			seen[n] = true
			if int(st.cell(n.x, n.y)["move"]) < 7 and not _occupied(n, u):
				return n
			q.append(n)
	return c


var _cursor_cell := Vector2i(-1, -1)  # 光标所在格 (隐藏后仍保留, 原版光标对象常驻)
var _cursor_area := 0                 # 光标形状: 选法术/道具落点时 = 效果范围 (0 单格, 1~3 菱形 3x3/5x5/7x7, Misc/Cursor 的 4 组帧)
var _cursor_shown_area := -1          # 光标动画当前播的那一组


func show_cursor(x: int, y: int) -> void:
	_cursor_cell = Vector2i(x, y)
	cursor.visible = true
	var sp := UiLayout.sprite("map.cursor")
	cursor.position = FxPlace.at_cell(Vector2i(x, y), String(sp.get("convention", "fx")))  # 光标与演出同一约定
	if not cursor.playing or _cursor_shown_area != _cursor_area:
		var first := int(sp.get("frame", 0)) + _cursor_area * int(sp.get("area_stride", 0))
		var count := int(sp.get("end", -1)) - int(sp.get("frame", 0))
		cursor.play(String(sp.get("anim", "")), first, first + count if count > 0 else -1)
		_cursor_shown_area = _cursor_area


## 光标形状 (效果范围 area; 超出帧组数的夹到最大一组); 光标可见时马上换
func set_cursor_area(area: int) -> void:
	var stride := int(UiLayout.sprite("map.cursor").get("area_stride", 0))
	var a := clampi(area, 0, 3) if stride > 0 else 0
	if a == _cursor_area:
		return
	_cursor_area = a
	if cursor.visible and _cursor_cell.x >= 0:
		show_cursor(_cursor_cell.x, _cursor_cell.y)


func hide_cursor() -> void:
	cursor.visible = false


## 玩家操作阶段: 我方回合、光标可操作、没有剧情/对白在跑、战斗没结束 (战场辅助显示, 如格子坐标, 只在这时出现)
func in_player_phase() -> bool:
	var inp = ctl.flow.input if ctl != null and ctl.flow != null else null
	return inp != null and inp.active and not inp.busy and not vm.running and not ctl.over and cursor.visible


## 光标所在格 (光标不可见时 (-1,-1)); 格子坐标标签用
func cursor_cell() -> Vector2i:
	return _cursor_cell if cursor.visible else Vector2i(-1, -1)


## 剧情对白把光标送到单位格 (实测 2026-10-05): slide=cursor 参数为 1 时光标每帧沿对角走 1 格 (+ 状态机),
## 走完下一帧才开对白; 否则 立即逐格走完 (先横后竖), 不等。每走一步按 的边缘规则卷镜头:
## 光标走到可见 10x8 格的最边一列/行 (且不是地图边) 就把镜头卷 1 格 (30x24 像素), 所以镜头停在离边 1 格处, 不是平滑平移、也不等镜头。
func story_cursor_to(x: int, y: int, slide: bool) -> void:
	var c := _cursor_cell if _cursor_cell.x >= 0 else Vector2i(x, y)
	_stop_cam()
	if slide:
		while c != Vector2i(x, y):
			if c.x != x:
				c.x += signi(x - c.x)
				_cursor_edge_scroll(0, c)
			if c.y != y:
				c.y += signi(y - c.y)
				_cursor_edge_scroll(1, c)
			show_cursor(c.x, c.y)
			await SceneGuard.wait(self, 1 / 25.0)
		await SceneGuard.wait(self, 1 / 25.0)
	else:
		while c.x != x:
			c.x += signi(x - c.x)
			_cursor_edge_scroll(0, c)
		while c.y != y:
			c.y += signi(y - c.y)
			_cursor_edge_scroll(1, c)
		show_cursor(x, y)
		await SceneGuard.wait(self, 1 / 25.0)


## 的边缘判定 (轴 ax: 0 横 1 竖): 光标格相对镜头格的偏移为 0 (左/上缘) 或 可见格数-1 (右/下缘), 且光标不在地图边, 镜头卷 1 格
func _cursor_edge_scroll(ax: int, c: Vector2i) -> void:
	var cell := Vector2(BattleStage.CELL_W, BattleStage.CELL_H)
	var o := cam_offset()
	var n := int(view()[ax] / cell[ax])
	var msz := int(layer_size.get(_current_layer(), SCREEN)[ax] / cell[ax])
	var off := c[ax] - floori((cam[ax] + o[ax]) / cell[ax])
	if off == 0 and c[ax] != 0:
		cam[ax] -= cell[ax]
	elif off == n - 1 and c[ax] != msz - 1:
		cam[ax] += cell[ax]


## 寻路: 按地形和移动类型 (data/terrain.json) 找最少步数路径, 走不通时忽略地形 (同重制版的"飞行"回退)
func find_path(u: BattleUnit, tx: int, ty: int) -> Array:
	var costs: Dictionary = Content.terrain(u.move_type)["cost"]
	var path := _bfs(Vector2i(u.cx, u.cy), Vector2i(tx, ty), func(c: Vector2i):
		var cell := st.cell(c.x, c.y)
		return not cell.is_empty() and costs.get(str(cell["move"])) != null)
	if path.is_empty():
		# 起点可能在地图外 (第 10 关我方从右侧图外走进来), 允许在边界外几格内走
		path = _bfs(Vector2i(u.cx, u.cy), Vector2i(tx, ty), func(c: Vector2i):
			return c.x >= -8 and c.y >= -8 and c.x < st.width + 8 and c.y < st.height + 8)
	return path


func _bfs(from: Vector2i, to: Vector2i, ok: Callable) -> Array:
	if from == to:
		return []
	var prev := {from: from}
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == to:
			var path: Array = []
			while c != from:
				path.push_front(c)
				c = prev[c]
			return path
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not prev.has(n) and (n == to or ok.call(n)):
				prev[n] = c
				q.append(n)
	return []


# ---------------- 演出动画 (Eanm) ----------------

## 0x18: 把 Eanm_<name> 登记为事件动画 id
func add_animation(id: int, name: int) -> void:
	if anims.has(id):
		anims[id].queue_free()
	var a := AnimPlayer.new()
	a.dir = st.event_anim(name)
	a.visible = false
	a.z_index = 20
	a.set_meta("follow_unit", last_unit_id)
	last_unit_id = -1
	world.add_child(a)
	anims[id] = a


## 0x19: 播放事件动画 [frame, end_frame]; frame=-1 播完整段; frame=end 只显示该帧
func play_animation(id: int, frame: int, end_frame: int) -> void:
	if not anims.has(id):
		return
	var a: AnimPlayer = anims[id]
	a.visible = true
	var fu: int = a.get_meta("follow_unit", -1)
	if fu >= 0 and unit(fu):
		var u := unit(fu)
		a.position = _cell_px(u.cx, u.cy) - SCREEN / 2 + Vector2(0, layer_y)
	else:
		a.position = orig_cam() + Vector2(0, layer_y)
	if frame < 0:
		a.play(a.dir, 0, -1, false)
		FullscreenCover.attach(a)   # 满屏的剧情动画: 宽屏/全屏下框外盖黑 (播放后才读得到帧数据)
		await a.finished
	elif frame == end_frame:
		a.show_frame(a.dir, end_frame)
		FullscreenCover.attach(a)
	else:
		a.play(a.dir, frame, end_frame + 1, false)
		FullscreenCover.attach(a)
		await a.finished
		a.show_frame(a.dir, end_frame)


func clear_animation(id: int) -> void:
	if anims.has(id):
		anims[id].visible = false
		anims[id].playing = false


# ---------------- 黑场 / 白场 / 标题卡 / 视频 / 音乐 ----------------

## 黑场淡入淡出, 时长单位为秒, 限制在 1~10 (重制版 GameDefine.getTimeBlack)
var _black_tw: Tween

func fade_black(to: float, t: int) -> void:
	if _black_tw and _black_tw.is_valid():
		_black_tw.kill()  # 新的淡入淡出取代旧的, 否则较长的旧动画会在最后把画面盖黑
	var tw := create_tween()
	_black_tw = tw
	tw.tween_property(_black, "color:a", to, clampf(t, 1, 10))
	await tw.finished


## 0x04: 关卡标题卡 Tanm_NN (淡入 0.5 秒, 停留, 淡出 0.3 秒)
func show_title_card() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 45
	ScreenLayout.bind_layer(layer, ScreenLayout.SAFE)
	add_child(layer)
	var back := ColorRect.new()   # 宽屏/全屏时标题卡 (320x200) 比窗口小: 先铺一整屏黑色再画卡, 随卡一起淡入淡出
	back.color = Color.BLACK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.modulate.a = 0
	layer.add_child(back)
	cover(back)
	var root := Node2D.new()
	root.scale = Vector2.ONE * Assets.SCALE
	root.modulate.a = 0
	layer.add_child(root)
	var card := AnimPlayer.new()
	card.show_frame(st.title_card, 0)
	root.add_child(card)
	var tw_in := create_tween().set_parallel()
	tw_in.tween_property(root, "modulate:a", 1.0, 0.5)
	tw_in.tween_property(back, "modulate:a", 1.0, 0.5)
	await tw_in.finished
	await SceneGuard.wait(self, 2.5)
	var tw_out := create_tween().set_parallel()
	tw_out.tween_property(root, "modulate:a", 0.0, 0.3)
	tw_out.tween_property(back, "modulate:a", 0.0, 0.3)
	await tw_out.finished
	layer.queue_free()


func play_movie(num: int) -> void:
	stop_all_music()
	var name := ThemeAssets.f("movie", [num])
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var m: Control = MovieScene.create([name], func(): pass)
	layer.add_child(m)
	await m.done
	layer.queue_free()


func play_music(ch: int, num: int) -> void:
	music.play(ch, num)


func load_music(ch: int, num: int) -> void:
	music.load_track(ch, num)


func start_music(ch: int, fade: int) -> void:
	music.start(ch, fade)


func close_music(ch: int) -> void:
	music.close(ch)


func pause_music(ch: int, paused: bool) -> void:
	music.pause(ch, paused)


func _exit_tree() -> void:
	music.release()


func stop_all_music() -> void:
	music.stop_all()

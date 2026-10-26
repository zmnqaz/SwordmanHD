# SPDX-License-Identifier: GPL-3.0-only
extends Node2D
## RPG 城镇场景 (参照重制版 GameRPGManager / GameRPGMovement / GameSceneRPG):
##   地图 + 物件 (L1 中 u5=0 且 u3=-1 的循环播放) + 主角 Rpg/Rpgman;
##   方向键逐格行走 (格子 walk=false 不能走), 走到 step 事件格触发事件; 面向 talk 事件格按确认触发对话;
##   鼠标左键/触摸点格子: 寻路走过去, 点到有 talk 事件的格子则走到旁边并面向它触发; 取消键打开物品管理界面。
##   输入经统一输入层 (InputRouter), 见 ui_action()。
## 锚点: 地图画面按安全区居中 (加宽后地图自然多显示两边; 镜头边界按宽屏重算见 docs/架构设计.md「锚点界面」), 黑幕铺满全屏。
## 入口: TownPosition 0 = 从关卡来 (Pos[0]), 1 = 从营地/别的场景来 (Pos[1])。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal camera_arrived

var SCREEN: Vector2 = UiLayout.base_size()  # 原版画面大小 (布局表 base_size)
## 城镇行走: 每格固定 0.4 秒 (10 tick, 四个方向相同; 原版 实测: 按住方向键时逻辑格每 0.40 秒前进一格, 左右上下一致,
## 重制版 getMoveSpeed(2) = 100 像素/秒会让横向 0.30 秒/格、纵向 0.24 秒/格, 比原版快)
const STEP_TIME := 0.4
var _seg_goal := Vector2.INF   # 当前一格的目标点与速度 (进入每一格时按剩余距离 / STEP_TIME 算)
var _seg_speed := 0.0
const DIRS := {BattleUnit.Dir.SOUTH: Vector2i(0, 1), BattleUnit.Dir.WEST: Vector2i(-1, 0),
	BattleUnit.Dir.NORTH: Vector2i(0, -1), BattleUnit.Dir.EAST: Vector2i(1, 0)}

var st: RpgStage
var entry := 0
var vm: RpgVM
var world: Node2D
var hero: AnimPlayer
var hx := 0
var hy := 0
var hdir := BattleUnit.Dir.SOUTH
var cam := Vector2.ZERO
var map_size := SCREEN
var msgbox: MsgBox
var choice: ChoiceBox
var shop: ShopUI
var anims := {}          # 事件动画 "id id2" -> AnimPlayer
var objs1 := {}
var _path: Array = []
var _moving := false
var _busy := false       # 事件执行中, 屏蔽操作
var _black: ColorRect
var _screen_mask: RpgScreenMask   # 整屏事件动画的宽屏留边遮罩 (见 _refresh_screen_mask)
var music := SceneMusic.new(self)  # 音乐通道
var _cam_target := Vector2.ZERO
var _cam_speed := Vector2.ZERO
var _cam_moving := false


static func create(n: int, entry_pos: int) -> Node2D:
	var s: Node2D = (load("res://engine/rpg/rpg_scene.gd") as GDScript).new()
	s.st = RpgStage.load_stage(n)
	s.entry = entry_pos
	return s


func _ready() -> void:
	scale = Vector2.ONE * Assets.SCALE
	# 宽屏扩展视野 (docs/架构设计.md 6.5): 地图从屏幕左上角起画, 视口 = 逻辑画面 (view()); 16:10 下 view = 320x200, 与原版逐像素相同。
	# 界面 (对白/选择/商店) 都是自带 CanvasLayer 的锚点界面, 不受场景根位置影响
	ScreenLayout.bind_node(self, ScreenLayout.Anchor.TOP_LEFT)
	ScreenLayout.changed.connect(_on_view_changed)
	world = Node2D.new()
	add_child(world)
	var t := Assets.tex(st.map_rel)
	var map := Sprite2D.new()
	map.centered = false
	map.texture = t["texture"]
	map.scale = Vector2.ONE * float(t["scale"])
	map.texture_filter = TextureSource.filter_for(t["hd"])
	map.z_index = -10
	world.add_child(map)
	map_size = Vector2(t["texture"].get_size()) * float(t["scale"])
	for j in st.layers1.size():
		var o: Dictionary = st.layers1[j]
		if int(o["id"]) != 1:
			continue
		var a := AnimPlayer.new()
		a.play_sound = false
		a.cull_offscreen = true  # 城镇物件/NPC: 屏外不取帧 (显存)
		a.position = Vector2(o["x"], o["y"])
		a.z_index = int(o["y"] / FxPlace.CELL.y)
		world.add_child(a)
		var d := st.obj_anim(o)
		a.dir = d
		objs1[j] = a
		if int(o["u5"]) == 0 and int(o["u3"]) == -1 and Assets.exists(d + "/anim.json"):
			a.play(d)
	hero = AnimPlayer.new()
	hero.play_sound = false
	world.add_child(hero)
	var p: Dictionary = st.pos[mini(entry, st.pos.size() - 1)]
	_place_hero(int(p["x"]), int(p["y"]), int(p["dir"]))
	_follow(true)
	_screen_mask = RpgScreenMask.new()
	world.add_child(_screen_mask)
	var fx := CanvasLayer.new()
	fx.layer = 40
	add_child(fx)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.size = SCREEN * Assets.SCALE
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(_black)
	ScreenLayout.cover(_black, 2048.0)
	msgbox = MsgBox.new()
	add_child(msgbox)
	choice = ChoiceBox.new()
	choice.cancel_means_no = false   # 城镇剧情选择框: Esc 无反应 (原版实测)
	add_child(choice)
	shop = ShopUI.new()
	add_child(shop)
	vm = RpgVM.new(self)
	add_child(vm)
	InputRouter.push(self)
	play_music(0, int(p["music"]))
	print("RPG 场景 %s: 地图 %s, 入口 %d (%d,%d)" % [st.dir, st.map_rel, entry, hx, hy])
	RegressLog.provide("town", regress_state)
	tree_exiting.connect(func(): RegressLog.drop("town", self))
	RegressLog.checkpoint("town_enter", {"town": st.n, "entry": entry})
	_auto_walk.call_deferred()
	_prefetch_town.call_deferred()


## 预取: 场景载入后, 把城镇里循环播放的物件/NPC 的全部贴图交给 Assets 慢慢载入 (磁盘缓存命中) 或烘焙好, 离主角近的排前面 ——
## 走到哪都不用现烘焙, 不会走到一半卡一下 (2026-10-20: 大城镇/客栈全部动画帧有一两千张, 现烘焙每张约 7ms)。限流在 Assets.prefetch_list
func _prefetch_town() -> void:
	var items: Array = []   # [到主角的距离, 贴图相对路径]
	var seen := {}
	for j in objs1:
		var a = objs1[j]   # 不写类型: engine/ 不新增对组装层 AnimPlayer 的引用 (test_engine_deps)
		if not a.playing:
			continue
		var dist: float = a.position.distance_to(hero.position)
		for i in (a.data["textures"] as Array).size():
			var rel := "%s/t%d.png" % [a.data["dir"], i]
			if not seen.has(rel):
				seen[rel] = true
				items.append([dist, rel])
	items.sort_custom(func(x, y): return x[0] < y[0])
	Assets.prefetch_list(items.map(func(x): return x[1]))


## 测试: --walk=x,y 让主角自动走到某格并触发事件; --auto-exit 自动走向出城 (事件含 0x28/0x29) 的踩踏格;
## --walk-all 走查 (仓库外的开发脚本): 依次走到每个事件格并触发, 报告走不到/走不完/事件卡住的
func _auto_walk() -> void:
	for kv in gc.debug.town_walk:   # 按命令行顺序
		var arg: String = kv[1]
		match String(kv[0]):
			"run_event":  # 测试: 按序执行事件 (逗号分隔); 完成后记 events_done 检查点 (没有切场景时用来收尾); --town-event 只对城镇生效 (连跑到战斗时不会误入战场的 --run-event)
				for x in arg.split(","):
					await _run(int(x))
				await get_tree().create_timer(5.0).timeout  # 出城/切场景是延后执行的: 等它发生, 5 秒后还在本场景才算「没有离开」
				RegressLog.checkpoint("events_done", {"town": st.n})
			"walk":
				var v := arg.split(",")
				walk_to(Vector2i(int(v[0]), int(v[1])))
			"auto_exit":
				_auto_exit()
			"walk_all":
				_walk_all()


const SCENE_OPS := [0x26, 0x28, 0x29, 0x33]   # 切换场景 / 出城 / 营地 / 出城

func _event_has(i: int, ops: Array) -> bool:
	if i <= 0 or i >= st.events.size():
		return false
	for c in st.events[i]:
		if int(c["type"]) in ops:
			return true
	return false


## 离主角最近的、事件编号满足 want 的格子 (踩踏或对话), 走不到的跳过
func _nearest_event_cell(want: Callable) -> Vector2i:
	var here := Vector2i(hx, hy)
	var best := Vector2i(-1, -1)
	for y in st.height:
		for x in st.width:
			var c := st.cell(x, y)
			for e in [int(c["step"]), int(c["talk"])]:
				if e > 0 and want.call(e) and (best.x < 0 or BattleRules.manhattan(here, Vector2i(x, y)) < BattleRules.manhattan(here, best)):
					best = Vector2i(x, y)
	return best


func _exit_cell() -> Vector2i:
	var exits := {}
	for want in [0x28, 0x33]:  # 优先直接出城的事件; 不走营地 (0x29), 否则会在城镇和营地之间来回
		for i in st.events.size():
			if _event_has(i, [want]):
				exits[i] = true
		if not exits.is_empty():
			break
	if exits.is_empty():  # 本城镇没有出口: 走向通往别的场景 (不是刚来的那个) 的事件
		for i in st.events.size():
			for c in st.events[i]:
				if int(c["type"]) == 0x26 and c["data"].decode_s16(0) != gc.prev_rpg:
					exits[i] = true
	return _nearest_event_cell(func(e): return exits.has(e))


## 测试 --auto-exit: 走向出口; 出口被剧情挡住 (事件执行完仍在本场景) 时, 依次去触发还没触发过的 NPC/事件, 再回出口
func _auto_exit() -> void:
	for req in gc.town_talks:   # 测试: 先谈的 NPC 事件 (--town-talk=) (谈 times 次, 每次走到它那一格触发)
		for k in int(req.get("times", 1)):
			var tc := _nearest_event_cell(func(e): return e == int(req["event"]))
			if tc.x < 0:
				break
			print("自动对话 -> ", tc, " 事件 ", int(req["event"]), " 第 ", k + 1, " 次")
			walk_to(tc)
			if not await _wait_idle():
				return
	var tried := {}
	var passes := 0
	for round in 200:
		var best := _exit_cell()
		print("自动出城 -> ", best)
		if best.x < 0:
			return
		walk_to(best)
		if not await _wait_idle():
			return
		var want := func(e): return not tried.has(e) and not _event_has(e, SCENE_OPS)
		var nxt := _nearest_event_cell(want)
		if nxt.x < 0 and passes < 3:  # 剧情有先后 (如必须先问甲再问乙), 全部试过仍出不去就再来一轮
			passes += 1
			tried.clear()
			nxt = _nearest_event_cell(want)
		if nxt.x < 0:
			print("自动出城 -> (-1, -1) 出口被挡且没有可触发的事件")
			return
		var c := st.cell(nxt.x, nxt.y)
		tried[int(c["step"])] = true
		tried[int(c["talk"])] = true
		print("自动探索 -> ", nxt, " 事件 ", int(c["talk"]) if int(c["talk"]) > 0 else int(c["step"]))
		walk_to(nxt)
		if not await _wait_idle():
			return


## 测试 --walk-all: 主角用寻路依次走到每个 NPC/事件格 (对话格走到旁边并面向它) 触发事件, 每个限时;
## 会离开场景或要等玩家选择的事件 (换场景/出城/营地/选择框/商店) 只检查寻路走得到, 不触发。最后打印汇总并退出
const WAIT_OPS := [0x27, 0x2E]

func _walk_all() -> void:
	var targets := {}  # 事件号 -> [格子]
	for y in st.height:
		for x in st.width:
			var c := st.cell(x, y)
			for e in [int(c["step"]), int(c["talk"])]:
				if e > 0:
					targets.get_or_add(e, []).append(Vector2i(x, y))
	var bad: Array = []
	var start := Vector2i(hx, hy)
	for e in targets:
		var cells: Array = targets[e]
		var kind := "对话" if int(st.cell(cells[0].x, cells[0].y)["talk"]) == e else "踩踏"
		var goal := Vector2i(-1, -1)
		var via_step := false
		for avoid in [true, false]:  # 取不踩中途踩踏格就走得到的一格; 只能踩着剧情格过去的另报
			for t in cells:
				var goals: Array = [t] if kind == "踩踏" else _talk_spots(t)
				if Vector2i(hx, hy) in goals or not st.find_path(Vector2i(hx, hy), goals, avoid).is_empty():
					goal = t
					break
			if goal.x >= 0:
				via_step = not avoid
				break
		if goal.x < 0:  # 离开场景的事件走不到才算问题; 其余 (柜台/墙后的摆设 NPC) 只提示
			if _event_has(e, SCENE_OPS):
				bad.append("%s事件%d %s 离开场景的事件走不到" % [kind, e, cells.slice(0, 3)])
			else:
				print("  走查提示: %s事件%d %s 走不到" % [kind, e, cells.slice(0, 3)])
			continue
		if via_step:
			print("  走查: %s事件%d %s 要踩过别的事件格才到得了, 不走" % [kind, e, goal])
			continue
		if _event_has(e, SCENE_OPS + WAIT_OPS):
			continue
		walk_to(goal)
		var ok := false
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 60000 / Engine.time_scale:
			await get_tree().process_frame
			if not gc.flow.is_current(self):
				break
			if not _moving and not _busy and not _overlay_open():
				ok = true
				break
		if not gc.flow.is_current(self):
			bad.append("%s事件%d %s 意外离开了场景" % [kind, e, goal])
			break
		if not ok:
			bad.append("%s事件%d %s 走/执行超时 (主角在 %s, 行走中=%s 事件中=%s)" % [kind, e, goal, Vector2i(hx, hy), _moving, _busy])
			break
	print("走查 城镇 %d: 事件 %d 个, 起点 %s, 问题 %d" % [st.n, targets.size(), start, bad.size()])
	for b in bad:
		print("  走查问题: ", b)
	get_tree().quit()


## 等主角走完、事件跑完; 场景已切换则返回 false
func _wait_idle() -> bool:
	for i in 25 * 300:
		await get_tree().process_frame
		if not gc.flow.is_current(self) or is_queued_for_deletion():
			return false
		if i > 5 and not _moving and not _busy and not _overlay_open():
			for k in 45:  # 出城/切换场景先淡出约 1 秒, 等它真正切走
				await get_tree().process_frame
				if not gc.flow.is_current(self):
					return false
			return gc.flow.is_current(self) and not is_queued_for_deletion()
	return false


# ---------------- 主角 ----------------

func _place_hero(x: int, y: int, d: int) -> void:
	hx = x
	hy = y
	hero.position = FxPlace.at_cell(Vector2i(x, y), "object")  # 城镇人物按物件约定
	hero.z_index = y
	_hero_act(false, d)


## 重制版 playAnimationRPG: 站立 = dir*站立帧数, 行走 = 站立帧数*4 + dir*行走帧数
func _hero_act(moving: bool, d: int) -> void:
	hdir = d
	var data := Assets.anim(ThemeAssets.p("rpg.hero"))
	var c: Array = data["action_counts"]
	var stand := maxi(1, int(c[0]))
	var move := maxi(1, int(c[1]))
	var s := stand * 4 + d * move if moving else d * stand
	var e := s + (move if moving else stand)
	if moving:
		# 行走: 每走一格 (10 tick) 重新走一轮行走帧, 每帧 2 tick, 走完停在末帧到下一格; 帧上的脚步声随之触发
		# (原版 实测: 钩 PlaySfx, 每格第 2/6 tick 各一声 s0/s1, 与动画数据的帧 1、3 对应)
		hero.play_sound = true
		hero.tick_override = 2
		hero.play(ThemeAssets.p("rpg.hero"), s, e, false)
		return
	hero.play_sound = false
	hero.tick_override = 0
	if hero.dir == ThemeAssets.p("rpg.hero") and hero.start_frame == s and hero.playing:
		return
	hero.play(ThemeAssets.p("rpg.hero"), s, e)


func _process(delta: float) -> void:
	if _cam_moving:
		cam.x = move_toward(cam.x, _cam_target.x, _cam_speed.x * delta)
		cam.y = move_toward(cam.y, _cam_target.y, _cam_speed.y * delta)
		if cam.is_equal_approx(_cam_target):
			_cam_moving = false
			camera_arrived.emit()
	if _moving:
		var target: Vector2i = _path[0]
		var goal := FxPlace.at_cell(target, "object")
		if goal != _seg_goal:
			_seg_goal = goal
			_seg_speed = hero.position.distance_to(goal) / STEP_TIME
		hero.position = hero.position.move_toward(goal, _seg_speed * delta)
		hero.z_index = int((hero.position.y - FxPlace.offset("object").y) / FxPlace.CELL.y)
		if hero.position.is_equal_approx(goal):
			hx = target.x
			hy = target.y
			_path.pop_front()
			var step := int(st.cell(hx, hy).get("step", 0))
			if step > 0:
				_path.clear()
				_moving = false
				_hero_act(false, hdir)
				_run(step)
			elif _path.is_empty():
				_moving = false
				_hero_act(false, hdir)
				_after_walk()
			else:
				_face_next()
		if not _cam_moving:
			_follow(false)
	elif not _busy and not _overlay_open() and InputRouter.top() == self:
		var hd := InputRouter.held_dir_by_priority(RpgStage.KEY_PRIORITY)  # 按住连续行走; 同时按多键固定 上>下>左>右
		for d in DIRS:
			if DIRS[d] == hd:
				_step(d)
	world.position = -RpgStage.snap_camera(cam, _display_mult())


## 窗口里 1 个原版像素占几个物理像素 (同 ScreenLayout.display_mult 的算法, 这里直接用场景自己的窗口和原版画面尺寸, 不多引用 autoload)
func _display_mult() -> float:
	var win := Vector2(get_window().size)
	return minf(win.x / SCREEN.x, win.y / SCREEN.y)


func _overlay_open() -> bool:
	return msgbox.visible or choice.visible or shop.visible or _items != null


func _step(d: int) -> void:
	var n: Vector2i = Vector2i(hx, hy) + DIRS[d]
	if not st.can_step(hx, hy, d):
		_hero_act(false, d)  # 被挡: 只转向 (原版同)
		return
	_path = [n]
	_moving = true
	_hero_act(true, d)


func _face_next() -> void:
	var n: Vector2i = _path[0]
	var dv := n - Vector2i(hx, hy)
	for d in DIRS:
		if DIRS[d] == dv:
			_hero_act(true, d)


var _talk_after := -1

## 鼠标/测试: 寻路走到目标格; 目标是 talk 事件格时走到相邻格并面向它
func walk_to(target: Vector2i) -> void:
	_talk_after = -1
	var tc := st.cell(target.x, target.y)
	if tc.is_empty():
		return
	var goals: Array = [target]
	if int(tc["talk"]) > 0:
		_talk_after = int(tc["talk"])
		goals = _talk_spots(target)
	var path := _bfs(Vector2i(hx, hy), goals)
	if path.is_empty() and Vector2i(hx, hy) not in goals:
		return
	set_meta("talk_target", target)
	_path = path
	if _path.is_empty():
		_after_walk()
		return
	_moving = true
	_face_next()


## 和对话格 t 说话时可站的相邻格: 不站到踩踏事件格上 (站上去会先触发它, 如出口的「确定要离城吗」), 都是踩踏格才退而求其次
func _talk_spots(t: Vector2i) -> Array:
	var all: Array = RpgStage.DIRS4.map(func(d): return t + d)
	var plain := all.filter(func(c): return int(st.cell(c.x, c.y).get("step", 0)) <= 0)
	return plain if not plain.is_empty() else all


func _after_walk() -> void:
	if _talk_after > 0 and has_meta("talk_target"):
		var t: Vector2i = get_meta("talk_target")
		var dv := t - Vector2i(hx, hy)
		for d in DIRS:
			if DIRS[d] == dv:
				_hero_act(false, d)
		var e := _talk_after
		_talk_after = -1
		_run(e)


## 优先绕开中途的踩踏事件格 (门口、出口), 绕不开再直走
func _bfs(from: Vector2i, goals: Array) -> Array:
	var p := st.find_path(from, goals, true)
	return p if not p.is_empty() else st.find_path(from, goals, false)


## 统一输入层 (城镇在界面栈底; 对话框、选择框、商店打开时在它上面):
##   确认 = 调查/对话面朝的格子; 鼠标/触摸点按 = 寻路走过去 (点到 talk 格走到旁边并对话);
##   取消 / 菜单 = 打开物品管理界面 (原版 GameItemUI, 与营地「囊内乾坤」同一界面, 4.1);
##   拖动 (触摸) = 不处理 (镜头跟随主角)。
func ui_action(a: UiAction) -> bool:
	if _items:
		var k := a.camp_key()
		if k != "" and not (a.echo and not a.is_dir()):
			_items.key(k)
		return true
	if _busy or _moving or _overlay_open() or a.echo:
		return true
	if a.is_confirm():
		if a.hit is Vector2i:  # 指针点按的格 (ui_hits)
			walk_to(a.hit)
		else:
			var n: Vector2i = Vector2i(hx, hy) + DIRS[hdir]
			var t := int(st.cell(n.x, n.y).get("talk", 0))
			if t > 0:
				_run(t)
	elif a.is_cancel() or a.kind == UiAction.MENU:
		_open_items()
	return true


## 指针 (engine/ui/ui_hit.gd): 物品管理界面打开时交给它; 否则地图格子是命中区, 点按 = 确认并带上格子 (ui_action 里寻路走过去)
func ui_pointer_target() -> Object:
	if _items:
		return _items
	return null if _busy or _moving or _overlay_open() else self


func ui_hits() -> Array:
	return [UiHit.area(Rect2(-cam, map_size), Vector2i.ZERO, self, UiAction.CONFIRM, FxPlace.CELL)]


## 物品管理界面 (囊内乾坤): 关闭后回到行走
var _items: CampItemWindow
var _items_ui: UiLayer

func _open_items() -> void:
	_items_ui = UiLayer.new(48)
	add_child(_items_ui)
	_items = CampItemWindow.new(CampInventory.new())
	_items_ui.add(_items)
	_items.open()
	await _items.closed
	_items_ui.queue_free()
	_items_ui = null
	_items = null


func _run(id: int) -> void:
	_busy = true
	await vm.run(id)
	_busy = false
	RegressLog.checkpoint("town_event", {"town": st.n, "event": id})


## 确定性回归的城镇状态 (engine/test/regress_log.gd)
func regress_state() -> Dictionary:
	return {"town": st.n, "pos": [hx, hy], "dir": hdir}


# ---------------- 镜头 ----------------

## 可见的地图区域 = 逻辑画面 (原版像素); 16:10 恒为 320x200。触摸界面 (keep_side_margins) 左右留边给虚拟键, 只占安全区宽度
func view() -> Vector2:
	var s: Vector2 = ScreenLayout.size
	return Vector2(SCREEN.x, s.y) if ScreenLayout.keep_side_margins else s


## 镜头夹紧: cam ∈ [0, 地图 − view]; 地图某一维不比 view 大时这一维不滚动, 地图相对原版画面居中 (cam 为负, 两边露出底)
func _clamp(p: Vector2) -> Vector2:
	var v := view()
	var out := p
	for ax in 2:
		if map_size[ax] <= v[ax]:
			out[ax] = -(v[ax] - maxf(map_size[ax], SCREEN[ax])) / 2.0
		else:
			out[ax] = clampf(p[ax], 0.0, map_size[ax] - v[ax])
	return out


## 原版镜头位置 (按 320x200 求) 换到当前视口: 让原版想看的区域仍在画面中间
func _orig_to_view(p: Vector2) -> Vector2:
	return p - (view() - SCREEN) / 2.0


## 当前视口里与原版 320x200 镜头对应的左上角 (全屏事件动画按原版镜头摆放)
func orig_cam() -> Vector2:
	return cam + (view() - SCREEN) / 2.0


## 视口大小变了 (切窗口/全屏/画面比例): 镜头重新夹紧并回到主角 (平移事件进行中只夹紧)
func _on_view_changed() -> void:
	if hero == null:
		return
	if _cam_moving:
		cam = _clamp(cam)
		_cam_target = _clamp(_cam_target)
	else:
		_follow(true)
	world.position = -RpgStage.snap_camera(cam, _display_mult())
	for a in anims.values():   # 全屏事件动画跟着新的原版画面位置
		if a.visible:
			a.position = orig_cam()
	_refresh_screen_mask()


func _follow(instant: bool) -> void:
	var c := hero.position - FxPlace.offset("object") + FxPlace.CELL / 2 - view() / 2  # 主角格中心对准画面中心
	var t := _clamp(c)
	if instant:
		cam = t
	else:
		cam = cam.lerp(t, 0.2)


## 0x04 (-> Camera, 2026-10-05 实测): 图层 1 左上角平移到 (x*30-10, y*24-4) 像素 (布局表 map.camera_offset),
## 每帧走 (sx, sy) 像素, 不夹在地图内 (越界处原版画黑); 到位同帧完成。已在目标处也占 1 帧。
func pan_camera(x: int, y: int, sx: int, sy: int) -> void:
	_cam_target = _orig_to_view(Vector2(x, y) * FxPlace.CELL - UiLayout.at("map.camera_offset"))
	_cam_speed = UiLayout.vec_of("map.camera_offset", "pan_speed", {"sx": sx, "sy": sy})
	if cam.is_equal_approx(_cam_target):
		await get_tree().create_timer(1 / 25.0).timeout
		return
	_cam_moving = true
	await camera_arrived


# ---------------- 事件动画 / 黑场 / 音乐 ----------------

func add_animation(id: int, id2: int) -> void:
	var key := "%d %d" % [id, id2]
	if anims.has(key):
		anims[key].queue_free()
		anims.erase(key)
		_refresh_screen_mask()
	for o in st.layers1:
		if int(o["id"]) == id and int(o["parm"]) == id2:
			var a := AnimPlayer.new()
			a.dir = st.obj_anim(o)
			a.visible = false
			a.z_index = 100
			world.add_child(a)
			anims[key] = a
			return


## 整屏事件动画 (如客栈房间, 包围盒盖住整个 320x200) 显示期间, 在原版画面四周铺黑: 原版画面之外没有别的东西,
## 宽屏 / 全屏时否则两侧会露出下面的城镇地图 (2026-10-12 用户报告: 客栈休息剧情)。只有局部动画时不遮, 地图照常可见
func _refresh_screen_mask() -> void:
	var full := false
	for a in anims.values():
		if a.visible and a.covers_window(SCREEN):
			full = true
			break
	_screen_mask.visible = full
	_screen_mask.window = Rect2(orig_cam(), SCREEN)


func play_animation(id: int, id2: int, frame: int, end_frame: int) -> void:
	var key := "%d %d" % [id, id2]
	if not anims.has(key):
		return
	var a: AnimPlayer = anims[key]
	a.visible = true
	a.position = orig_cam()
	if frame < 0:
		a.play(a.dir, 0, -1, false)
		_refresh_screen_mask()   # 动画数据载入之后才知道是不是整屏图
		await a.finished
	elif frame == end_frame:
		a.show_frame(a.dir, end_frame)
		_refresh_screen_mask()
	else:
		a.play(a.dir, frame, end_frame + 1, false)
		_refresh_screen_mask()
		await a.finished


func clear_animation(id: int, id2: int) -> void:
	var key := "%d %d" % [id, id2]
	if anims.has(key):
		anims[key].visible = false
		_refresh_screen_mask()


## 0x06 渐黑 / 0x07 渐亮 (实测): 亮度 16->0 / 0->16 每 (delay+1) 帧 ±2 共 8 级,
## 阶梯式; 阻塞到完成 (最后多 1 帧判完成); 渐亮完成后遮罩关闭。
func fade_light(l0: int, l1: int, delay: int) -> void:
	var l := l0
	_black.color.a = clampf(1.0 - l / 16.0, 0, 1)
	while l != l1:
		await get_tree().create_timer((delay + 1) / 25.0).timeout
		l = mini(l + 2, l1) if l < l1 else maxi(l - 2, l1)
		_black.color.a = clampf(1.0 - l / 16.0, 0, 1)
	await get_tree().create_timer(1 / 25.0).timeout


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

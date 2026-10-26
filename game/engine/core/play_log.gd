# SPDX-License-Identifier: GPL-3.0-only
class_name PlayLog
extends Node
## 通关录像: 记录玩家从启动 (标题画面) 到通关的全部操作, 之后可原样回放。
##
## 原理: 所有键盘/鼠标/触摸/手柄输入都先翻译成 UiAction 再交给界面栈 (InputRouter.dispatch, 会发 dispatched 信号),
## 这里订阅该信号, 把每个动作连同「录像时钟」(游戏时间, 秒) 存进 JSON; 战斗随机数种子平时取当前时间 (BattleRules.battle_seed),
## 录像里按顺序记下每次实际用的种子, 回放时原样取回, 所以命中/闪避/暴击与当时完全一致。
## 回放: 按录像时钟把同样的动作送回 InputRouter.dispatch; 界面忙 (动画/过场) 时当时收不到的动作回放时也一样收不到, 与原样对应。
##   速度 N 倍: Engine.time_scale = N (录像时钟用缩放后的 delta, 相对时序不变); 回放中可用 set_speed 随时调 (档位 SPEED_STEPS)。
## 对不上检测: 每回合开头 (战斗) 记一个检查点 (关号/回合/我方总血量), 回放时逐个比对, 对不上打印一次警告 (之后仍继续放)。
##
## 用法:
##   录制: 默认开 (有窗口时; 设定 record_play=false 或 --no-record-play 关闭); --record-play=<路径> 指定文件, 缺省
##         user://replays/play_<日期时间>.json (退出时、每 10 秒自动保存; 窗口大小/语言/手柄预设一并记下)。
##   回放: --replay-play=<文件> [--replay-speed=N]   (从标题画面开始, 用的是同一套内容, 不要同时手动操作)
##         菜单: 设定面板「录像回放」(engine/ui/replay_panel.gd) 选一份录像, 进程内切到回放 (Game.start_replay)。
##   回放期间存档写 REPLAY_SAVE_DIR 沙盒 (回放里的存档操作不覆盖真存档), 放完 / 停止恢复; 模态浮层开着时回放时间冻结。
## 限制: 依赖游戏逻辑只由输入和战斗随机数决定 (现状如此); 鼠标/触摸动作带视口坐标, 回放窗口大小应与录制时相同 (不同会警告)。

const VERSION := 1
const AUTOSAVE_SEC := 10.0
const HISTORY_EXT := ".replay"   # 存档旁边的录像历史文件 (zstd 压缩的 JSON), 见 begin_save
const SPEED_STEPS := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]   # 菜单里的倍速档位 (命令行 --replay-speed 不受限)
const REPLAY_SAVE_DIR := "user://replay_saves"          # 回放期间的存档沙盒: 回放里的「存档」操作写这里, 不碰玩家真存档

signal replay_finished
signal start_replaced(kind: String)   # 录像被迫改成从某个没有录像历史的存档开始 (不再是整场): 界面弹提示

static var current: PlayLog = null

var mode := ""            # "record" | "replay"
var path := ""
var speed := 1.0
var _t := 0.0
var _events: Array = []
var _seeds: Array = []    # 录制: 每场战斗实际用的种子; 回放: 待取队列
var _seed_i := 0
var _cps: Array = []      # 检查点 [{t, tag, v}]
var _idx := 0
var _cp_i := 0
var _since_save := 0.0
var _save_task := -1       # 自动存盘的线程池任务 (-1 = 没有在写的)
var _saved_sig := -1       # 上次完整存盘时各列表的总长度 + 时间: 关窗时 WM_CLOSE_REQUEST / _exit_tree / PREDELETE 会连着调三次 save(), 内容没变就不再重写
var _saved_ms := 0
var _warned := false
var _real_save_dir := ""   # 回放期间被替换掉的真实存档目录 (空 = 没替换)
var _meta := {}
var _finished := false
var _marks := {}          # 录制: 存档键 -> {events, seeds, cps, t} 存档那一刻录像各列表的长度 (读档时剪回这里)
var _base: Dictionary = {}   # 录像起点的存档内容 (录像开始前存的档被读入时: 录像从这个存档状态开始, 之前的全部省掉)
var _base_kind := ""
var router: Object = null          # 输入层 (由 Game 注入 InputRouter; 单元测试换成自己的)
var _seg: Dictionary = {}          # 当前这一幕的录制段 {stage, base, base_kind, ev0, seeds0, cps0, t0}: 通关时导出成单幕战斗录像
var _save_id := ""         # begin_save() 发出、等 note_save 落盘的存档 id
var _pending_reseed := false   # 刚读了战阵存录: 重建战斗时抽的新种子要记在 load 事件上 (回放不重建战斗, 到这个点直接换种子)
static var bag_sort_hook := Callable()   # 回放到「整理行囊」事件时调的回调 (组装层登记: 攻略面板的整理行囊在模态浮层里不进输入录像, 但它改了行囊顺序, 之后按格下标的操作要对得上, 所以单独记一条事件)
static var reseed_hook := Callable()   # 当前战斗的换种子回调 (BattleRules 创建时登记)


static func start_from_args() -> PlayLog:
	var d := DebugArgs.current()
	if d.replay_play != "":
		return open_replay(d.replay_play, d.replay_speed)
	if not recording_wanted():
		return null
	var p2 := PlayLog.new()
	p2._begin_record(d.record_play)
	return p2


## 这次运行要不要录像: 默认有窗口时录, 自动测试/代打/回归 (--autoplay* / --regress* / --fast / --press / --scene=) 与 --no-record-play 不录,
## 显式 --record-play=<路径> 一定录。启动与「回放放完 / 结束后继续录」共用
static func recording_wanted() -> bool:
	var d := DebugArgs.current()
	if d.no_record_play:
		return false
	return d.record_play != "" or (DisplayServer.get_name() != "headless" and not d.test_run)


## 回放放完后接着手动玩: 把放过的整份录像 (操作/战斗种子/检查点/起点/时钟) 当历史, 新开一份录制接着录。
## 以前放完就不再录, 之后存的档没有录像历史, 下次读那个档录像就被迫改成「从该存档开始」(用户反馈: 回放不是从开头开始)。
## 返回的节点还没挂进场景树 (调用方设 router 后 add_child); 新文件名自动取, 不覆盖被放的录像
func continuation() -> PlayLog:
	var l := PlayLog.new()
	var want := DebugArgs.current().record_play
	l._begin_record("" if want == path else want)
	l._meta = _meta.duplicate(true)
	l._events = _events.duplicate(true)
	l._seeds = _seeds.duplicate()
	l._cps = _cps.duplicate(true)
	l._base = _base.duplicate(true)
	l._base_kind = _base_kind
	l._t = _t
	return l


## 结束回放回到标题后重新开始录 (进度已清空, 同刚启动): 标记从标题起录, 回放它时直接进标题画面 (录像时钟不含 logo 动画)
static func fresh() -> PlayLog:
	var l := PlayLog.new()
	l._begin_record("")
	l._meta["title_start"] = true
	return l


## 正在回放的录像是不是从标题画面起录的 (fresh 录的): 是 -> 回放不放 logo / 标题动画, 直接进标题
static func title_start() -> bool:
	return current != null and current.mode == "replay" and bool(current._meta.get("title_start", false))


## 打开一份录像准备回放 (还没挂进场景树, 调用方设 router 后 add_child; 读不了 / 版本不对返回 null)。命令行与菜单入口共用
static func open_replay(p: String, spd: float) -> PlayLog:
	var l := PlayLog.new()
	if l._load(p, spd):
		return l
	l.free()
	return null


## 现在是否在回放 (没放完)
static func replaying() -> bool:
	return current != null and current.mode == "replay" and not current._finished


## 停掉当前的录制 / 回放并释放节点: 录制中的先存盘; 回放中的还原倍速和存档目录
static func stop_current() -> void:
	var p := current
	if p == null:
		return
	if p.mode == "record":
		p.save()
	elif not p._finished:
		print("通关录像: 回放被停止")
	p._release()
	if p.is_inside_tree():
		p.get_parent().remove_child(p)
		p.queue_free()
	else:
		p.free()


## 回放中调倍速 (夹在 SPEED_STEPS 的最小~最大之间); 没在回放时什么都不做
static func set_speed(s: float) -> void:
	var p := current
	if p == null or p.mode != "replay" or p._finished:
		return
	p.speed = clampf(s, SPEED_STEPS[0], SPEED_STEPS[-1])
	p._apply_time_scale()
	print("通关录像: 回放速度 ", speed_text(p.speed))


## 档位里挪一档 (d = ±1, 到头停住); cur 不在档位上先取最近的一档
static func step_speed(cur: float, d: int) -> float:
	var at := 0
	for i in SPEED_STEPS.size():
		if absf(SPEED_STEPS[i] - cur) < absf(SPEED_STEPS[at] - cur):
			at = i
	return SPEED_STEPS[clampi(at + d, 0, SPEED_STEPS.size() - 1)]


## 倍速的显示文字: ×2 / ×0.5
static func speed_text(s: float) -> String:
	var t := String.num(s, 2)
	if "." in t:
		t = t.rstrip("0").rstrip(".")
	return "×" + t


func _overlay_up() -> bool:
	return router != null and router.has_method("overlay_open") and router.overlay_open()


## 回放的时间流速: 模态浮层 (设定面板等) 开着时冻结 (录像时钟与游戏一起停, 事件不会落进浮层), 否则按当前倍速
func _apply_time_scale() -> void:
	Engine.time_scale = 0.0 if _overlay_up() else speed


## 回放期间存档改写到沙盒目录 (先清空, 免得上次回放的残留被读到)
func _enter_save_sandbox() -> void:
	_real_save_dir = GameSaves.base_dir
	DirAccess.make_dir_recursive_absolute(REPLAY_SAVE_DIR)
	for f in DirAccess.get_files_at(REPLAY_SAVE_DIR):
		DirAccess.remove_absolute(REPLAY_SAVE_DIR.path_join(f))
	GameSaves.base_dir = REPLAY_SAVE_DIR


func _lock_input(on: bool) -> void:
	if router != null:
		router.set("replay_lock", on)


## 回放收尾 (放完 / 被停掉): 倍速 1x、存档目录还原、不再占着 current
func _release() -> void:
	if mode == "replay":
		_lock_input(false)
		Engine.time_scale = 1.0
		if _real_save_dir != "":
			GameSaves.base_dir = _real_save_dir
			_real_save_dir = ""
	reseed_hook = Callable()
	if current == self:
		current = null


func _begin_record(p: String) -> void:
	mode = "record"
	if p == "":
		DirAccess.make_dir_recursive_absolute("user://replays")
		var d := Time.get_datetime_dict_from_system()
		p = "user://replays/play_%04d%02d%02d_%02d%02d%02d.json" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	path = p
	_meta = _snapshot_meta()
	print("通关录像: 开始录制 -> ", path)


func _snapshot_meta() -> Dictionary:
	var vp := Vector2i(1280, 720)
	var win := Engine.get_main_loop() as SceneTree
	if win != null and win.root != null:
		vp = Vector2i(win.root.size)
	return {"version": VERSION, "viewport": [vp.x, vp.y], "time": Time.get_datetime_string_from_system(), "args": Array(DebugArgs.current().raw)}


func _load(p: String, spd: float) -> bool:
	var j = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (j is Dictionary) or int(j.get("version", 0)) != VERSION:
		printerr("通关录像: 无法读取或版本不对: ", p)
		return false
	mode = "replay"
	path = p
	speed = spd
	_events = j.get("events", [])
	_seeds = j.get("seeds", [])
	_cps = j.get("checkpoints", [])
	_meta = j.get("meta", {})
	_base = j.get("base", {})
	_base_kind = String(j.get("base_kind", ""))
	print("通关录像: 回放 %s (%d 个操作, %d 场战斗, %.0f 秒), 速度 x%.1f" % [p, _events.size(), _seeds.size(), float(j.get("duration", 0.0)), speed])
	return true


func _ready() -> void:
	current = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	if mode == "record":
		if router != null:
			router.dispatched.connect(_on_dispatched)
	elif mode == "replay":
		_enter_save_sandbox()
		_lock_input(true)   # 回放期间屏蔽真实输入, 免得混进指令流
		Engine.time_scale = speed
		var vp: Array = _meta.get("viewport", [])
		if is_inside_tree() and vp.size() == 2:
			var now := get_tree().root.size
			if int(vp[0]) != now.x or int(vp[1]) != now.y:
				push_warning("通关录像: 窗口大小 %s 与录制时 %s 不同, 鼠标/触摸动作的坐标可能对不上" % [str(now), str(vp)])


func _on_dispatched(a: UiAction) -> void:
	if _finished:
		return
	if router != null and router.has_method("overlay_open") and router.overlay_open():
		return   # 设定 / 攻略等模态浮层里的操作不影响游戏: 不录 (回放时没有浮层, 录了会落到游戏里)
	var e := {"t": snappedf(_t, 0.001), "k": a.kind}
	if a.echo:
		e["e"] = 1
	if a.source != "key":
		e["s"] = a.source
	if a.has_pos():
		e["p"] = [snappedf(a.pos.x, 0.1), snappedf(a.pos.y, 0.1)]
	if a.delta != Vector2.ZERO:
		e["d"] = [snappedf(a.delta.x, 0.1), snappedf(a.delta.y, 0.1)]
	_events.append(e)


func _process(delta: float) -> void:
	_t += delta
	if mode == "record":
		_since_save += delta
		if _since_save >= AUTOSAVE_SEC:
			_since_save = 0.0
			_autosave()
	elif mode == "replay":
		_apply_time_scale()
		while _idx < _events.size() and float(_events[_idx]["t"]) <= _t:
			_play(_events[_idx])
			_idx += 1
		if _idx >= _events.size() and not _finished:
			_finished = true
			print("通关录像: 回放结束 (%d 个操作)" % _events.size())
			_release()
			replay_finished.emit()
			if is_inside_tree():
				queue_free()


func _play(e: Dictionary) -> void:
	if e.has("bag_sort"):
		if bag_sort_hook.is_valid():
			bag_sort_hook.call()
		return
	if e.has("load"):
		if e.has("seed") and reseed_hook.is_valid():
			reseed_hook.call(int(e["seed"]))   # 读战阵存录会换新种子: 回放到这个点也换成当时的
		return   # 读档动作本身不重现 (状态本来就一致)
	var a := UiAction.new(int(e["k"]), String(e.get("s", "key")), Vector2.INF, int(e.get("e", 0)) == 1)
	if e.has("p"):
		a.pos = Vector2(float(e["p"][0]), float(e["p"][1]))
	if e.has("d"):
		a.delta = Vector2(float(e["d"][0]), float(e["d"][1]))
	if router != null:
		router.dispatch(a)


## 录像要存的内容 (一个字典)。shallow = 给后台线程用的快照: 事件/检查点/种子列表浅拷贝 (元素字典录进去之后不再改, 只有读战阵存录时给最后一个 load 事件补 seed,
## 所以最后几个事件深拷贝), 主线程之后继续往原列表追加不会影响正在序列化的快照
func _save_dict(shallow: bool) -> Dictionary:
	var ev: Array = _events
	var cps: Array = _cps
	var seeds: Array = _seeds
	var meta: Dictionary = _meta
	if shallow:
		var keep := maxi(0, _events.size() - 4)
		ev = _events.slice(0, keep)
		ev.append_array(_events.slice(keep).map(func(e): return e.duplicate(true)))
		cps = _cps.duplicate(false)
		seeds = _seeds.duplicate()
		meta = _meta.duplicate(true)
	var j := {"version": VERSION, "meta": meta, "duration": snappedf(_t, 0.01), "seeds": seeds, "checkpoints": cps, "events": ev}
	if not _base.is_empty():
		j["base"] = _base   # 只在读档时整体换掉, 不原地修改
		j["base_kind"] = _base_kind
	return j


func _list_sig() -> int:
	return _events.size() * 1000003 + _cps.size() * 1009 + _seeds.size()


## 自动存盘 (每 AUTOSAVE_SEC 秒): 放到工作线程。录像越长 JSON 越大 (实测 30 万个操作约 7MB, 序列化 300ms, 在主线程上每 10 秒一次就是越玩越明显的周期性顿帧)
func _autosave() -> void:
	if mode != "record" or path == "":
		return
	if _save_task >= 0:
		if not WorkerThreadPool.is_task_completed(_save_task):
			return   # 上一次还没写完: 下个周期再说
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	_save_task = WorkerThreadPool.add_task(_write_json.bind(path, _save_dict(true)), false, "playlog autosave")


func _write_json(file: String, j: Dictionary) -> void:   # 工作线程
	var txt := JSON.stringify(j)
	var f := FileAccess.open(file + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()
	DirAccess.rename_absolute(file + ".tmp", file)


func _wait_save() -> void:
	if _save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1


## 立刻完整存盘 (主线程, 等后台那次写完再写)。关窗时会连着被调三次 (见 _saved_sig): 内容没变且刚存过就跳过
func save() -> void:
	if mode != "record" or path == "":
		return
	_wait_save()
	var sig := _list_sig()
	if sig == _saved_sig and Time.get_ticks_msec() - _saved_ms < 3000 and FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_save_dict(false)))
	_saved_sig = sig
	_saved_ms = Time.get_ticks_msec()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if mode == "record" and not _finished:
			save()


func _exit_tree() -> void:
	_wait_save()   # 线程池任务必须等待完成 (退出时释放回调会崩)
	if mode == "record":
		save()
	if current == self:
		current = null


## 战斗随机数种子: 录制时记下, 回放时取回当时那场用的 (BattleRules.battle_seed 调用)
static func seed_for_battle(fresh: int) -> int:
	var p := current
	if p == null:
		return fresh
	if p.mode == "record":
		if p._pending_reseed and not p._events.is_empty() and p._events[-1].has("load"):
			p._events[-1]["seed"] = fresh   # 读战阵存录重建的战斗: 种子记在 load 事件上
			p._pending_reseed = false
			return fresh
		p._seeds.append(fresh)
		return fresh
	if p.mode == "replay":
		if p._seed_i < p._seeds.size():
			var s := int(p._seeds[p._seed_i])
			p._seed_i += 1
			return s
		push_warning("通关录像: 回放里没有更多战斗种子了 (用新的)")
	return fresh


## 检查点 (战斗每回合开头等): 录制时记下, 回放时比对, 对不上警告一次
static func checkpoint(tag: String, value: int) -> void:
	var p := current
	if p == null:
		return
	if p.mode == "record":
		p._cps.append({"t": snappedf(p._t, 0.01), "tag": tag, "v": value})
	elif p.mode == "replay":
		if p._cp_i < p._cps.size():
			var c: Dictionary = p._cps[p._cp_i]
			p._cp_i += 1
			if String(c["tag"]) != tag or int(c["v"]) != value:
				if not p._warned:
					p._warned = true
					push_warning("通关录像: 回放与录制对不上 (第 %d 个检查点 %s: 录制 %s=%d, 现在 %s=%d); 之后的画面可能不同" % [p._cp_i, str(c["tag"]), str(c["tag"]), int(c["v"]), tag, value])


## 存档要带的录像 id (GameSaves 写存档前调用): 录像中返回一个新 id (写进存档), 没在录像返回 "" (存档不带历史)。
## 下一个 note_save 凭它把「到这个存档为止的录像」存成存档旁边的历史文件, 以后另一次启动读这个存档时能接上 (整场录像)
static func begin_save() -> String:
	var p := current
	if p == null or p.mode != "record":
		return ""
	p._save_id = "%d-%d" % [Time.get_unix_time_from_system() * 1000, randi()]
	return p._save_id


## 攻略面板「整理行囊」成功整理了 (位置有变) 时调: 录一条事件, 回放到这里再整理一次 (见 bag_sort_hook)。
## 整理在模态浮层里做 (浮层里的输入不录), 但它改了行囊顺序, 之后在行囊/商店/炼化窗口里按格下标选物品的录像操作靠它对得上
static func note_bag_sort() -> void:
	var p := current
	if p == null or p.mode != "record" or p._finished:
		return
	p._events.append({"t": snappedf(p._t, 0.001), "bag_sort": 1})


## 存档钩子 (GameSaves 的四个入口调用): kind = "slot" (营地/城镇存档位) 或 "battle" (战阵存录), key = 位号;
## save_path = 存档文件路径: 给了就把录像历史 (到此为止的操作/种子/检查点/起点) 压缩存成 <save_path>.replay, 带 begin_save 发的 id
static func note_save(kind: String, key: int, save_path := "") -> void:
	var p := current
	if p == null or p.mode != "record":
		return
	p._marks["%s:%d" % [kind, key]] = {"events": p._events.size(), "seeds": p._seeds.size(), "cps": p._cps.size(), "t": p._t}
	if save_path != "" and p._save_id != "":
		p._write_history(save_path + HISTORY_EXT, p._save_id)
	p._save_id = ""


func _write_history(hp: String, id: String) -> void:
	var f := FileAccess.open_compressed(hp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	var j := {"version": VERSION, "id": id, "t": _t, "seeds": _seeds, "checkpoints": _cps, "events": _events}
	if not _base.is_empty():
		j["base"] = _base
		j["base_kind"] = _base_kind
	f.store_string(JSON.stringify(j))
	f.close()


## 读存档旁边的录像历史: id 对得上才返回 (存档被别的存档覆盖、历史文件缺了/坏了都返回 {})
static func _read_history(save_path: String, id: String) -> Dictionary:
	if id == "" or save_path == "" or not FileAccess.file_exists(save_path + HISTORY_EXT):
		return {}
	var f := FileAccess.open_compressed(save_path + HISTORY_EXT, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	f.close()
	if not (j is Dictionary) or int(j.get("version", 0)) != VERSION or String(j.get("id", "")) != id:
		return {}
	return j


## 读档: 存档是本次录像中存下的 -> 把存档之后被放弃的操作/种子/检查点剪掉, 并插一个「换种子」事件 (读档重建战斗会重新抽种子, 见 battle_seed);
## 存档不是本次录像存的 (录像开始之前的老档) -> 清空录像, 以这个存档的内容作为录像起点 (data = 存档读入后的内容)
static func note_load(kind: String, key: int, data: Dictionary, save_path := "") -> void:
	var p := current
	if p == null or p.mode != "record":
		return
	var k := "%s:%d" % [kind, key]
	if p._marks.has(k):
		var m: Dictionary = p._marks[k]
		if not p._seg.is_empty() and int(m["events"]) < int(p._seg["ev0"]):
			p._seg = {}   # 读的是这一幕开战之前的档: 本幕录像作废 (之后重新进关会重新开始记)
		p._events.resize(int(m["events"]))
		p._seeds.resize(int(m["seeds"]))
		p._cps.resize(int(m["cps"]))
		p._t = float(m["t"])
		print("通关录像: 读档 %s, 剪掉存档之后被放弃的部分 (保留 %d 个操作)" % [k, p._events.size()])
	else:
		var gd: Dictionary = data["game"] if kind == "battle" and data.get("game") is Dictionary else data
		var h := _read_history(save_path, String(gd.get("replay_id", "")))
		p._marks.clear()
		p._seg = {}
		if not h.is_empty():
			# 另一次启动存的档, 旁边有它的录像历史: 接上, 录像仍是从游戏开头到现在的整场
			p._events = h.get("events", [])
			p._seeds = h.get("seeds", [])
			p._cps = h.get("checkpoints", [])
			p._t = float(h.get("t", 0.0))
			p._base = h.get("base", {})
			p._base_kind = String(h.get("base_kind", ""))
			if kind == "battle":   # 单幕录像的起点接在历史之后
				p._seg = {"stage": int(data["game"].get("stage", -1)), "base": data, "base_kind": "battle", "ev0": p._events.size(), "seeds0": p._seeds.size(), "cps0": p._cps.size(), "t0": p._t}
			print("通关录像: 读入之前启动存的档 %s, 接上它的录像历史 (%d 个操作), 继续录整场" % [k, p._events.size()])
		else:
			p._events.clear()
			p._seeds.clear()
			p._cps.clear()
			p._t = 0.0
			p._base = data
			p._base_kind = kind
			if kind == "battle":   # 老的战阵存录: 本幕录像从这个战场快照开始 (之前的部分没有记录)
				p._seg = {"stage": int(data["game"].get("stage", -1)), "base": data, "base_kind": "battle", "ev0": 0, "seeds0": 0, "cps0": 0, "t0": 0.0}
			print("通关录像: 读入录像开始前的存档 %s (没有录像历史), 录像改为从这个存档开始" % k)
	p._events.append({"t": snappedf(p._t, 0.001), "load": k})
	p._pending_reseed = kind == "battle"   # 回放到这里: 标记点 (读档后下一次取种子是新的; 见 seed_for_battle)


## 回放时: 处理 load 事件 (什么都不用做, 只是标记; 种子队列已按剪辑后的顺序排好)


## 回放起点: 录像是从某个存档开始的 (录像开始前的老档被读入) -> {kind, data}; 否则 {}
static func replay_base() -> Dictionary:
	var p := current
	if p == null or p.mode != "replay" or p._base.is_empty():
		return {}
	return {"kind": p._base_kind, "data": p._base}


## 一幕开战 (Game._battle_scene, 新开战而不是读战阵存录时): 记下这一幕开始的游戏状态作为本幕录像的起点
static func stage_begin(stage: int, base: Dictionary) -> void:
	var p := current
	if p == null or p.mode != "record":
		return
	p._seg = {"stage": stage, "base": base.duplicate(true), "base_kind": "stage_start", "ev0": p._events.size(), "seeds0": p._seeds.size(), "cps0": p._cps.size(), "t0": p._t}


## 一幕打完 (战斗结束, 胜利): 导出「这一幕从开始到通关」的战斗录像, 中途读档放弃的部分已经剪掉; 失败不导出
static func stage_end(stage: int, won: bool) -> void:
	var p := current
	if p == null or p.mode != "record" or p._seg.is_empty():
		return
	var seg: Dictionary = p._seg
	p._seg = {}
	if not won or int(seg["stage"]) != stage:
		return
	var t0: float = float(seg["t0"])
	var evs: Array = []
	for e in p._events.slice(int(seg["ev0"])):
		var c: Dictionary = e.duplicate(true)
		c["t"] = snappedf(maxf(0.0, float(c["t"]) - t0), 0.001)
		evs.append(c)
	var cps: Array = []
	for c0 in p._cps.slice(int(seg["cps0"])):
		var c1: Dictionary = c0.duplicate(true)
		c1["t"] = snappedf(maxf(0.0, float(c1["t"]) - t0), 0.01)
		cps.append(c1)
	var j := {"version": VERSION, "kind": "stage", "stage": stage, "meta": p._meta, "duration": snappedf(p._t - t0, 0.01),
		"base": seg["base"], "base_kind": seg["base_kind"], "seeds": p._seeds.slice(int(seg["seeds0"])), "checkpoints": cps, "events": evs}
	var dir := p.path.get_base_dir() if p.path != "" else "user://replays"
	DirAccess.make_dir_recursive_absolute(dir)
	var d := Time.get_datetime_dict_from_system()
	var out := "%s/stage_%02d_%04d%02d%02d_%02d%02d%02d.json" % [dir, stage, d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(j))
		print("通关录像: 第 %d 幕通关, 单幕战斗录像已存 -> %s (%d 个操作)" % [stage, out, evs.size()])


## 回放起点是存档/某幕开战前时: 场景建好后把录像时钟归零 (录像里的时间是从这个起点算起的)
static func rebase_clock() -> void:
	var p := current
	if p != null and p.mode == "replay":
		p._t = 0.0
		p._idx = 0

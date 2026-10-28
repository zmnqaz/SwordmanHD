# SPDX-License-Identifier: GPL-3.0-only
extends Node
## 场景流程 (autoload "Game"): 片头 Logo -> 标题动画 -> 标题菜单 -> 新游戏 (第 0 关)。
## 命令行 (-- 之后): --skip-movies 跳过片头; --scene=title|stage0 直接进入某个场景。

const MovieScene := preload("res://scripts/movie_scene.gd")
const TitleScene := preload("res://scripts/title_scene.gd")
const NoticeScene := preload("res://scripts/notice_scene.gd")
const BattleScene := preload("res://engine/battle/battle_scene.gd")

var current: Node
var load_failures := 0  # 场景加载失败 (内容包缺文件) 回标题的次数, 测试用
var ctx := GameContext.current()  # 运行上下文 (engine/core/game_context.gd): 引擎经它读状态/开关/场景流转, 这里的同名属性只是转发
var state: GameState:  # 全局进度 (可序列化, engine/core/game_state.gd); 存档见 engine/core/game_saves.gd
	get: return ctx.state
	set(v): ctx.state = v
var battle_resume: Dictionary:  # 非空时 BattleScene 按此恢复战场, 跳过开场事件 (戰陣重現)
	get: return ctx.battle_resume
	set(v): ctx.battle_resume = v
var cur_rpg: int:
	get: return ctx.cur_rpg
	set(v): ctx.cur_rpg = v
var prev_rpg: int:
	get: return ctx.prev_rpg
	set(v): ctx.prev_rpg = v
const RpgScene := preload("res://engine/rpg/rpg_scene.gd")
const CampScene := preload("res://engine/camp/camp_scene.gd")
var _fade: ColorRect
var skip_movies: bool:
	get: return ctx.skip_movies
	set(v): ctx.skip_movies = v
var fast: bool:      # 测试用: 跳过视频, 对白快速翻页
	get: return ctx.fast
	set(v): ctx.fast = v
var autoplay: bool:  # 测试用: 我方回合也由 AI 操作
	get: return ctx.autoplay
	set(v): ctx.autoplay = v
var god: bool:       # 测试用: 我方不受伤害 (自动通关回归测试)
	get: return ctx.god
	set(v): ctx.god = v
var skip_dialog: bool:  # 调试: 跳过对白 (--skip-dialog, 运行时 F3 切换; 按住 Ctrl 快进)
	get: return ctx.skip_dialog
	set(v): ctx.skip_dialog = v


func _init() -> void:
	ctx.flow = GameFlow.new(self)


# ---------------- 设置 (user://settings.json): 音乐/音效音量 0~10, 画质 hd/orig ----------------

const SETTINGS_PATH := "user://settings.json"
## 设定项定义/缺省/校验在 engine/settings/settings_schema.gd; 另有 tex 贴图倍数 / fullscreen / win 窗口大小
var settings: Dictionary:
	get: return ctx.settings
	set(v): ctx.settings = v
var _cmd_tex_mult := 0     # 命令行 --tex-mult (设定「贴图精度」为自动时沿用)
var _applied_win := 1280   # 已应用的窗口大小档 / 全屏 (只在变化时改窗口, 不动命令行/--aspect 设好的窗口)
var _applied_full := false


func _init_audio() -> void:
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	var r := SaveFile.load_file(SETTINGS_PATH, "settings")
	_cmd_tex_mult = Assets.tex_mult
	var ov: Dictionary = ctx.debug.cli_overrides.duplicate()   # 截图/对照/测试用的临时值 (--gfx=orig / --font= / --lang= 等): 进覆盖层 (校验同设定文件), 不写进设定文件
	SettingsSchema.load_layers(ctx, r.data if r.ok and r.data is Dictionary else {}, ov)
	apply_settings()


func apply_settings() -> void:
	for b in [["Music", "music"], ["SFX", "sfx"]]:
		var i := AudioServer.get_bus_index(b[0])
		var v := int(settings[b[1]])
		AudioServer.set_bus_mute(i, v <= 0)
		AudioServer.set_bus_volume_db(i, linear_to_db(v / 10.0) if v > 0 else -80.0)
	var tex := _cmd_tex_mult if settings["tex"] == "auto" else int(settings["tex"])
	if Assets.gfx != settings["gfx"] or Assets.tex_mult != tex:
		Assets.gfx = settings["gfx"]
		Assets.tex_mult = tex
		Assets.clear_cache()
	var fs := String(settings.get("face_style", "hk"))
	if Assets.face_style != fs:   # 头像风格: 清贴图缓存, 下一次显示头像就读新风格
		Assets.face_style = fs
		Assets.clear_cache()
	Content.set_lang(String(settings["lang"]))  # 简体/繁体: 数据表、对白、界面文案按语言叠加层重建, 下个画面生效
	Assets.set_font(String(settings["font"]))  # 未知/缺失的字体 id 已在 sanitize 回退缺省
	InputRouter.set_pad(String(settings["pad_preset"]), settings["pad_map"])  # 手柄预设与逐键覆盖即时生效
	InputRouter.set_keys(settings["key_map"])  # 键盘逐键覆盖即时生效
	ctx.settings_applied.emit()
	ScreenLayout.set_aspect_mode(String(settings["aspect"]))  # 画面比例即时生效
	_apply_window()


## 全屏 / 窗口大小: 只在设定变化时动窗口 (不动命令行 / --aspect 设好的窗口), 实际操作在 ScreenLayout.apply_window (单一来源)
func _apply_window() -> void:
	var full := int(settings["fullscreen"]) == 1
	var w := int(settings["win"])
	if w == 0:   # 自动: 屏幕可用区域放得下的最大档
		w = SettingsSchema.auto_win(DisplayServer.screen_get_usable_rect().size)
	if full == _applied_full and (full or w == _applied_win):
		return
	_applied_full = full
	_applied_win = w
	ScreenLayout.apply_window(full, SettingsSchema.win_size(w))


## F10: 任何画面打开设定 (标题菜单保持原版四项; 战场系统菜单里也有「設定」)
var _settings_open := false

## F10 / F3 由统一输入层 (engine/input/input_router.gd) 发出信号
func _toggle_skip_dialog() -> void:  # 调试: 跳过对白开关
	if _settings_open:  # 设定面板是模态的
		return
	skip_dialog = not skip_dialog
	_toast(UiStrings.t("ui.skip_dialog", [UiStrings.t("common.on" if skip_dialog else "common.off")]))


func _open_settings() -> void:
	if _settings_open or GuidePanel.is_open():   # 攻略面板开着: 先关它 (都是模态浮层, 叠开会让输入落到被盖住的那层)
		return
	_settings_open = true
	var sp := SettingsPanel.new()
	add_child(sp)  # 挂在 Game 下而不是当前场景: 打开期间场景被切走也不会连面板一起释放 (否则 open() 永远等不到 closed, F10 就死了)
	await sp.open()
	_settings_open = false


## 屏幕上方短暂提示 (复刻新增, 布局表 toast.top: 位置/框/字号/颜色/描边/停留与淡出时长)
func _toast(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	ScreenLayout.bind_layer(layer, UiLayout.anchor("toast.top", ScreenLayout.Anchor.TOP))
	add_child(layer)
	var tx := UiLayout.text("toast.top")
	var l := make_label(text, UiLayout.pos("toast.top"), float(tx.get("size", 11)), UiLayout.color(tx.get("color")), HORIZONTAL_ALIGNMENT_CENTER, bool(tx.get("bold", true)))
	l.size = UiLayout.size_of("toast.top") * Assets.SCALE
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY  # 长提示 (内容包不兼容等) 自动折行
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", int(tx.get("outline", 8)))
	layer.add_child(l)
	var tw := create_tween()
	tw.tween_interval(UiLayout.num("toast.top", "life", 1.2))
	tw.tween_property(l, "modulate:a", 0.0, UiLayout.num("toast.top", "fade", 0.4))
	tw.tween_callback(layer.queue_free)


func save_settings() -> void:
	# 保留文件里别的键 (如内容包的 "mods")
	var d = SaveFile.read_json(SETTINGS_PATH)
	if not d is Dictionary:
		d = {}
	d.merge(ctx.settings_saved, true)   # 只写持久层: 命令行等覆盖值不落盘
	SaveFile.write_json(SETTINGS_PATH, SaveFile.stamp(d, "settings"))


## 启动自检: 缺必需资源 (common_assets.pck / common_story.pck, 开发版是原版目录/内容包) 时给出清楚的提示并干净退出,
## 不要一路报几十条错再段错误 (发布版缺 common_assets.pck 时实测会 segfault)。返回提示文字, 空 = 正常
func resource_error() -> String:
	var packed := Platform.is_exported()
	if not Assets.has_index():   # 资源包该放哪按平台不同, 提示文字由 ResPacks 给
		return ResPacks.missing_hint()
	if not Assets.image_packs_ok():   # 只装了 common_assets 公用素材: 头像/地图等图在 hd_images.pck (高清) 或 classic_images.pck (原版画质) 里
		return ResPacks.missing_img_hint()
	if Content.stage_count() <= 0:
		return "找不到游戏内容包 common_story.pck (原版剧情与数值)。请把它放进游戏目录的 resource 文件夹, 它与 common_assets.pck 由同一工具生成。" if packed \
			else "内容包里没有任何关卡 (game/content/tdj 缺失? 见 docs/内容格式.md)。"
	return ""


func _ready() -> void:
	boot_error = resource_error()
	if boot_error != "":
		printerr("启动失败: " + boot_error)
		if Platform.is_mobile():
			add_child(BootErrorScreen.make(boot_error))   # 手机上 OS.alert 不阻塞 (iOS 没有), 立刻退出就是「闪退」: 不退出, 提示画在屏幕上
		elif DisplayServer.get_name() != "headless":
			OS.alert(boot_error, "SwordmanHD")
		return  # 桌面的退出放在 boot() 里做 (autoload 的 _ready 阶段调 quit 会被吞掉)
	get_tree().auto_accept_quit = false   # 点窗口关闭按钮: 自己处理, 先藏窗口再退 (见 _fast_quit)
	_init_audio()
	var play_log := PlayLog.start_from_args()   # 通关录像: 默认录制玩家全程操作; --replay-play=<文件> 回放 (engine/core/play_log.gd)
	if play_log != null:
		_attach_play_log(play_log)
	InputRouter.settings_requested.connect(_open_settings)
	InputRouter.skip_dialog_toggled.connect(_toggle_skip_dialog)
	InputRouter.guide_requested.connect(func(): GuidePanel.toggle(self, ctx, InputRouter))   # F4 攻略 (挂在 Game 下, 切场景不连带释放)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	ScreenLayout.cover(_fade)  # 全屏黑幕 (锚点 STRETCH)
	var dbg := UiDebugOverlay.from_args(ctx.debug.raw)  # 布局校对: --layout-debug / --overlay=<原版截图>
	if dbg:
		add_child(dbg)
	skip_movies = ctx.debug.skip_movies
	fast = ctx.debug.fast
	autoplay = ctx.debug.autoplay
	god = ctx.debug.god
	skip_dialog = ctx.debug.skip_dialog
	for e in ctx.debug.state_edits:   # 测试: 按命令行顺序改进度
		var v: String = e[1]
		match String(e[0]):
			"give":  # --give=物品编号,... 放入行囊
				for x in v.split(","):
					state.add_item(int(x))
			"set_var":  # --set-var=变量号:值,... 预设剧情变量 (如第 3 幕买云芝 = 87:1; 分支验证 仓库外的开发脚本)
				for kv in v.split(","):
					state.set_data(int(kv.get_slice(":", 0)), int(kv.get_slice(":", 1)))
			"gold":  # --gold= 起始金钱
				state.gold = int(v)
	skip_movies = skip_movies or fast
	RegressLog.provide("game", state.regress_state)


var boot_error := ""   # 非空 = 启动自检失败: 桌面已安排退出, 手机留着提示屏 (见 resource_error / BootErrorScreen)


func boot() -> void:
	if boot_error != "":
		if not Platform.is_mobile():   # 手机上留着提示屏, 由用户自己退出 (见 BootErrorScreen)
			get_tree().quit(2)
		return
	if ctx.debug.replay_switch != "":   # 测试: 正常启动 1 秒后经菜单回放同一入口切到回放 (headless 验证 start_replay)
		get_tree().create_timer(1.0).timeout.connect(func(): start_replay(ctx.debug.replay_switch, ctx.debug.replay_speed))
	GameSaves.stage_limit = Content.stage_count()
	for n in ctx.debug.load_slots:  # 测试: --load=N 先读入第 N 个存档位的数据 (不切换场景)
		GameSaves.load_slot(state, int(n) - 1)
	if _enter_replay_base():   # 通关录像回放: 录像从某个存档开始 (与菜单回放共用)
		return
	if ctx.debug.load_battle:  # 测试: 直接读战阵存录 (标题「戰陣重現」)
		if await load_battle():
			return
	ctx.town_talks.append_array(ctx.debug.town_talks.duplicate(true))   # 调试: --town-talk=事件号:次数 (配合 --scene=rpgN --auto-exit)
	if ctx.debug.scene != "":
		return enter_test_scene(ctx.debug.scene)
	_enter_title_flow()


## 挂上录像节点 (录制或回放): 接输入层; 录制时读入没有历史的存档要提示; 回放放完提示并接着录 (之后存的档要带录像历史, 否则下次读档录像就不是整场)
func _attach_play_log(p: PlayLog) -> void:
	p.router = InputRouter
	PlayLog.bag_sort_hook = func(): CampInventory.resort_bag(ctx)   # 回放到「整理行囊」事件时照做 (录制时在攻略面板里整理的)
	if p.mode == "replay":
		p.replay_finished.connect(_on_replay_finished.bind(p))
	else:
		p.start_replaced.connect(func(_k): _toast(UiStrings.t("ui.replay_not_full")))
	add_child(p)


func _on_replay_finished(p: PlayLog) -> void:
	_toast(UiStrings.t("replay.finished"))
	if PlayLog.recording_wanted():
		_attach_play_log(p.continuation())


## 回放录像从某个存档开始 (战阵存录 / 单幕开战前 / 营地存档) -> 先读入它并进对应场景, 返回 true; 录像从标题开始返回 false
func _enter_replay_base() -> bool:
	var pbase := PlayLog.replay_base()
	if pbase.is_empty():
		return false
	if String(pbase["kind"]) == "battle":
		state.apply_dict(pbase["data"]["game"])
		battle_resume = pbase["data"]["battle"]
		goto(_battle_scene(state.stage))
	elif String(pbase["kind"]) == "stage_start":   # 单幕战斗录像: 从这一幕开战前的状态重新进战场
		state.apply_dict(pbase["data"])
		goto(_battle_scene(state.stage))
	else:
		state.apply_dict(pbase["data"])
		goto(CampScene.new())
	PlayLog.rebase_clock()
	return true


## 正常启动的起点: [版权声明] -> logo 动画 -> 标题动画 -> 标题 (跳过动画时直接标题)。录像时钟从这里起算, 所以回放也必须走同一段;
## 结束回放后重新录的录像 (PlayLog.fresh) 是从标题画面起录的, 回放它直接进标题
func _enter_title_flow() -> void:
	if skip_movies or PlayLog.title_start():
		goto(TitleScene.new())
	elif NoticeScene.needed(PlayLog.current != null and PlayLog.current.mode == "replay"):   # 每次启动先让玩家同意版权声明, 不同意就退出
		goto(NoticeScene.create(_play_intro, quit_game))
	else:
		_play_intro()


func _play_intro() -> void:
	goto(MovieScene.create([ThemeAssets.p("movie.logo"), ThemeAssets.p("movie.title")], func(): goto(TitleScene.new())))


## --scene= 名字的编号是否在内容包范围内: 越界返回提示文字, 否则 ""
static func scene_range_error(name: String) -> String:
	for kv in [["stage", Content.stage_count()], ["rpg", Content.town_count()]]:
		if name.begins_with(kv[0]) and name.trim_prefix(kv[0]).is_valid_int():
			var n := int(name.trim_prefix(kv[0]))
			if kv[1] > 0 and (n < 0 or n >= kv[1]):
				return "场景 %s 超出内容包范围 (共 %d 个), 进标题" % [name, kv[1]]
	return ""


## 测试: 直接进入某个场景 (--scene=名字; 猴子测试换场景也用它)。名字: title | ui_gallery | campN (当作第 N 关结束后的营地) | rpgN | stageN
func enter_test_scene(name: String) -> void:
	var bad := scene_range_error(name)
	if bad != "":  # 越界编号: 以前每帧报断言, 现在提示一次回标题
		push_warning(bad)
		return goto(TitleScene.new())
	if name == "title":
		return goto(TitleScene.new())
	if name == "ui_gallery":  # 原版样式界面组件展示 (game/engine/ui/gallery.gd)
		return goto(load("res://engine/ui/gallery.gd").new())
	if name.begins_with("camp"):
		state.stage = int(name.trim_prefix("camp"))
		state.next_stage = state.stage + 1
		state.camp_no = state.stage
		return goto(CampScene.new())
	if name.begins_with("rpg"):
		return goto(_rpg_scene(int(name.trim_prefix("rpg")), 0))
	if name.begins_with("stage"):
		state.stage = int(name.trim_prefix("stage"))
		return goto(_battle_scene(state.stage))
	push_warning("未知场景 %s, 进标题" % name)
	goto(TitleScene.new())


func goto(scene: Node) -> void:
	if current:
		current.queue_free()
		Assets.begin_scene()  # 新场景 _ready 里用到的缓存项记新代; 旧场景释放后只清旧代 (见 Assets.begin_scene)
		Assets.sweep.call_deferred()
	current = scene
	ctx.in_battle = scene is BattleScene   # 攻略面板选默认章用
	if "gc" in scene:  # 场景/组件的运行上下文显式交给它 (引擎不直接引用 Game)
		scene.gc = ctx
	get_tree().root.get_node("Main").add_child(scene)


## 建战场/城镇场景; 内容包缺文件 (mod 少关卡、数据损坏) 时不进场景: 报错 + 提示后返回标题场景 (场景流转的统一失败通路)
func _battle_scene(n: int) -> Node:
	if battle_resume.is_empty():
		PlayLog.stage_begin(n, state.to_dict())   # 通关录像: 这一幕的起点状态 (单幕战斗录像从这里开始)
	var err := Content.stage_error(n)
	return BattleScene.create(n) if err == "" else _failed_to_title(err)


func _rpg_scene(n: int, entry: int) -> Node:
	var err := Content.town_error(n)
	return RpgScene.create(n, entry) if err == "" else _failed_to_title(err)


func _failed_to_title(err: String) -> Node:
	push_error("场景加载失败, 回标题: " + err)
	battle_resume = {}  # 读档恢复到一半失败: 不留着恢复数据
	_toast(UiStrings.t("ui.load_failed"))
	load_failures += 1
	return TitleScene.new()


## 退出游戏 (标题「退出」)。猴子测试把它拦下来 (block_quit), 免得随机输入把测试进程关掉
var block_quit := false


func quit_game() -> void:
	if block_quit:
		print("拦截退出 (block_quit)")
		return
	_fast_quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_fast_quit()


## 退出: 先把窗口收起来再走正常退出流程。真实显卡上销毁上千张 6 倍贴图和生成用的视口要好几秒, 窗口一直挂着像卡死
## (用户 2026-10-20 反馈「点击关闭要很多秒才关掉」); 收起来后进程在后台收尾, 录像存档等退出通知照常走。
## 主窗口不能 visible = false (引擎报 "Can't change visibility of main window", 窗口也不会藏), 用最小化代替; 只在桌面系统做
func _fast_quit() -> void:
	if Platform.is_ios():
		# iOS 上 SceneTree.quit() 只停渲染、进程不退 (苹果也不让 App 自己退出), 标题「回返太虚」点了没反应。
		# 自签 App 没有这个限制: 先把录像存盘 (正常退出路径靠退出通知存, 这里走不到), 再直接结束本进程
		if PlayLog.current != null:
			PlayLog.current.save()
		OS.kill(OS.get_process_id())
		return
	if DisplayServer.get_name() != "headless" and OS.has_feature("pc"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	get_tree().quit()


var _replay_busy := false


## 回到「新启动」的进度 (菜单回放 / 结束回放用): 清进度与场景记号, 保留 state 对象 (RegressLog 已绑它)
func _reset_progress() -> void:
	state.reset(0)
	battle_resume = {}
	cur_rpg = -1
	prev_rpg = -1


## 菜单回放 (设定面板「录像回放」选定录像, 经 SceneFlow.start_replay 调来): 进程内切到回放, 起点与启动时的 --replay-play 完全相同。
## 录像读不了只提示, 当前游戏与录制都不动。回放期间存档写沙盒目录 (PlayLog), 不碰真实存档; 放完停在终点状态, 可接着手动玩 (接着录, 见 _on_replay_finished)
func start_replay(path: String, speed: float) -> bool:
	if _replay_busy:
		return false
	var p := PlayLog.open_replay(path, speed)
	if p == null:
		_toast(UiStrings.t("replay.failed"))
		return false
	_replay_busy = true
	await fade_out(0.4)
	PlayLog.stop_current()   # 正在录的先存盘释放
	_reset_progress()
	_attach_play_log(p)
	if not _enter_replay_base():
		_enter_title_flow()
	await fade_in(0.4)
	_replay_busy = false
	return true


## 结束回放回标题 (设定面板回放中的「结束回放」)。进度清空同刚启动, 重新录一份 (从标题画面起录, 见 PlayLog.fresh)
func stop_replay() -> void:
	if _replay_busy:
		return
	_replay_busy = true
	await fade_out(0.4)
	PlayLog.stop_current()
	_reset_progress()
	if PlayLog.recording_wanted():
		_attach_play_log(PlayLog.fresh())
	goto(TitleScene.new())
	await fade_in(0.4)
	_replay_busy = false


func new_game() -> void:
	await fade_out(0.5)
	var st: Dictionary = Content.start()   # 起点由内容包 manifest.start 决定; 缺省 = tdj: 第 0 关、5 两 、无开场过场
	state.reset(int(st["gold"]))
	if int(st["movie"]) >= 0 and not skip_movies and Assets.movie_exists(ThemeAssets.f("movie", [int(st["movie"])])):
		var m: Control = MovieScene.create([ThemeAssets.f("movie", [int(st["movie"])])], func(): pass)
		var played := [false]
		m.done.connect(func(): played[0] = true)
		goto(m)
		await fade_in(0.5)
		while not played[0]:
			await get_tree().process_frame
		await fade_out(0.5)
	if st["kind"] == "town":
		prev_rpg = cur_rpg
		cur_rpg = int(st["id"])
		goto(_rpg_scene(int(st["id"]), int(st["entry"])))
	else:
		state.stage = int(st["id"])
		goto(_battle_scene(int(st["id"])))
	await fade_in(0.5)


## 事件 0x02: 关卡结束。town>=0 进入 RPG 场景, 否则 camp>=0 进入营地, 否则直接开始 next 关
func stage_over(town: int, camp: int, next: int) -> void:
	print("关卡结束: town=%d camp=%d next=%d" % [town, camp, next])
	if current and current.has_method("save_party"):
		current.save_party()
	state.next_stage = next
	RegressLog.checkpoint("stage_end", {"stage": state.stage, "town": town, "camp": camp, "next": next})
	if town >= 0:
		await goto_rpg(town, 0)
	elif camp >= 0:
		await goto_camp(camp)
	else:
		await goto_battle(next)


## 进营地 CAMPnn: n 来自关卡结束 0x02 的 camp 参数或城镇脚本 0x29 的 p0 (记为进度值), 不是当前关卡号
func goto_camp(n: int) -> void:
	state.camp_no = n
	await fade_out(1.0)
	goto(CampScene.new())
	await fade_in(0.8)


## 营地离开 (CAMPNN.DAT 的 Town>=0 回城镇入口 1, 否则进入下一关)
func leave_camp(town: int, town_pos: int) -> void:
	RegressLog.checkpoint("camp_leave", {"camp": state.camp_no, "town": town})
	if town >= 0:
		await goto_rpg(town, town_pos)
	else:
		await goto_battle(state.next_stage)


# ---------------- 存档 (数据读写在 engine/core/game_saves.gd, 这里只管提示与读档后的场景切换) ----------------

func save_game(slot := 0) -> void:
	if GameSaves.save_slot(state, slot):
		print("已存档 ", ProjectSettings.globalize_path(GameSaves.slot_path(slot)))
	else:
		_toast(UiStrings.t("ui.save_failed"))


func save_battle(snapshot: Dictionary) -> void:
	if GameSaves.save_battle(state, snapshot):
		print("已存戰陣 ", ProjectSettings.globalize_path(GameSaves.battle_path()))
	else:
		_toast(UiStrings.t("ui.save_battle_failed"))


func load_battle() -> bool:
	var r := GameSaves.load_battle(state, BattleScene.validate_snapshot)
	if not r.ok:
		if r.error != "":
			_toast(r.error)
		return false
	battle_resume = r.battle
	await fade_out(0.8)
	goto(_battle_scene(state.stage))
	await fade_in(0.8)
	if r.warning != "":  # 内容包版本有差异但可读: 读入后提示
		_toast(r.warning)
	return true


func load_game(slot := 0) -> bool:
	var r := GameSaves.load_slot(state, slot)
	if not r.ok:
		if not r.missing:
			_toast(r.error)
		return false
	await fade_out(0.8)
	goto(CampScene.new())
	await fade_in(0.8)
	if r.warning != "":
		_toast(r.warning)
	return true


func goto_rpg(n: int, entry: int) -> void:
	prev_rpg = cur_rpg
	cur_rpg = n
	await fade_out(1.0)
	goto(_rpg_scene(n, entry))
	await fade_in(0.8)


func goto_battle(n: int) -> void:
	await fade_out(1.0)
	state.stage = n
	goto(_battle_scene(n))
	await fade_in(0.8)


## 结局: 淡出回标题 (0x54, 或 结局过场后脚本结束)
func ending() -> void:
	print("结局: 回到标题")
	RegressLog.checkpoint("ending", {"stage": state.stage})
	await fade_out(2.0)
	goto(TitleScene.new())
	await fade_in(1.0)


## 战败: 播放 Misc/GAMEOVER 动画, 然后回到标题
func game_over() -> void:
	RegressLog.checkpoint("game_over", {"stage": state.stage})
	await fade_out(1.0)
	var root := Node2D.new()
	root.scale = Vector2.ONE * Assets.SCALE
	ScreenLayout.bind_node(root, ScreenLayout.SAFE)
	var a := AnimPlayer.new()
	root.add_child(a)
	goto(root)
	a.play(ThemeAssets.p("ui.gameover"), 0, -1, false)
	await fade_in(0.5)
	if a.playing:  # 动画比淡入短 (或缺动画) 时 finished 已经发过, 再等会永远卡在这
		await a.finished
	await get_tree().create_timer(1.5).timeout
	await fade_out(1.0)
	goto(TitleScene.new())


func fade_out(dur: float) -> void:
	await get_tree().create_tween().tween_property(_fade, "color:a", 1.0, dur).finished


func fade_in(dur: float) -> void:
	await get_tree().create_tween().tween_property(_fade, "color:a", 0.0, dur).finished


## 原版坐标 (320x200) 的文字 (实现在 UiText.make_label)
func make_label(text: String, pos: Vector2, size: float, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, bold := false) -> Label:
	return UiText.make_label(text, pos, size, color, align, bold)

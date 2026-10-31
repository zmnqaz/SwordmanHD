# SPDX-License-Identifier: GPL-3.0-only
class_name DebugArgs
extends RefCounted
## 命令行调试/测试参数 (Godot 命令行 `--` 之后的部分) 的唯一解析处: 启动时解析一次, 放进 GameContext.debug,
## 引擎只读这里的字段, 不再自己调 OS.get_cmdline_user_args() (闸门见 tests/test_engine_deps.gd)。
## 没有 GameContext 的地方 (autoload 的 _ready、静态工具) 用 DebugArgs.current() 取同一份。
## 单元测试可 DebugArgs.parse(["--x", ...]) 构造独立一份。
## 规则层 (engine/rules) 不读本类: 需要的开关由战场层注入 (如 AI.trace_cands)。

static var _current: DebugArgs

var raw := PackedStringArray()   # 原样参数 (给 RegressLog.setup / UiDebugOverlay.from_args / 通关录像的元数据)

# ---- 运行开关 (组装层写进 GameContext 同名字段, 运行中可改) ----
var fast := false           # --fast: 跳过视频, 对白快速翻页
var skip_movies := false    # --skip-movies
var skip_dialog := false    # --skip-dialog
var god := false            # --god: 我方不受伤害 (自动通关回归)
var autoplay := false       # --autoplay: 我方回合也由 AI 操作
var cli_overrides := {}      # 设定覆盖层 (不写盘): --gfx=orig / --font= / --aspect-mode= / --lang= / --show-hidden= / --coord= / --face-style=

# ---- 启动与资源 ----
var packs := ""             # --packs=<目录>: 从这里挂资源包 (ResPacks)
var bundled := ""           # --bundled=<目录>: 桌面上模拟「整包」(目录里有 manifest.json + resource/ + mod/, 见 ResPacks.bundled_dir), 测试用
var content_main := ""      # --content=<包 id>: 主内容包
var mods = null             # --mods=a,b: 叠加的内容包 (null = 没给, 用设定文件里的)
var assets_root := ""       # --assets=<目录>
var original := ""          # --original=<原版目录>
var gfx_orig := false       # --gfx=orig
var tex_mult := -1          # --tex-mult=N (-1 = 没给)
var tex_budget_mb := -1     # --tex-budget=MB
var tex_budget_max_mb := -1 # --tex-budget-max=MB (预算自适应放大的上限, 0 = 不放大)
var no_hq := false          # --no-hq
var hq_timeout_s := -1.0    # --hq-timeout=秒
var hq_codec := "auto"       # --hq-codec=auto|off|bptc|astc|etc2 (6 倍烘焙结果的 GPU 压缩格式)
var hq_scale := 0           # --hq-scale=0|3|4|6 像素画类烘焙倍数 (0 = 自动: 手机按屏幕分辨率选 3/4/6, 电脑 6)
var hq_cache_mb := -1       # --hq-cache-mb=N 磁盘缓存上限 (MB, 0 = 不用磁盘缓存, -1 = 按平台)
var hq_break := false       # --hq-break: 故意用坏着色器, 验证自动回退
var max_tex := -1           # --max-tex=N
var sysfont := false        # --sysfont
var aspect := 0.0           # --aspect=W:H (启动窗口比例; 0 = 没给)
var touch := false          # --touch: 模拟触屏

# ---- 场景入口与进度 ----
var scene := ""             # --scene=title|stageN|rpgN|campN|ui_gallery (第一个)
var load_slots: Array = []  # --load=N (依次读入存档位数据, 不切场景)
var load_battle := false    # --load-battle: 直接读战阵存录
var state_edits: Array = [] # 按参数顺序 [种类, 值]: give (--give=物品,...) / set_var (--set-var=变量:值,...) / gold (--gold=)
var town_talks: Array = []  # --town-talk=事件:次数 -> [{event, times}]
var choose: Array = []      # --choose=1,0,...: 剧情选择框依次的答案 (true = 是)

# ---- 通关录像 ----
var replay_play := ""       # --replay-play=<文件>
var record_play := ""       # --record-play=<文件>
var replay_speed := 1.0     # --replay-speed=N (>= 0.1)
var exp_mult := 1.0         # --exp-mult=N: 战斗经验乘 N (测试用: 直接触发升级看升级演出; 缺省 1 = 原版)
var replay_switch := ""     # --replay-switch=<文件>: 测试, 启动 1 秒后经菜单回放同一入口 (Game.start_replay) 切到回放
var no_record_play := false # --no-record-play
var test_run := false       # 自动测试/代打/回归运行 (默认不录像)

# ---- 战场测试钩子 ----
var rng_seed = null         # --seed=N: 战斗随机数种子 (null = 没给, 用时间种子)
var ai_trace := false       # --ai-trace: 对照打印 AI 决定/阶段末状态
var ai_cands := false       # --ai-cands: 另打印 AI 每个候选 (注入 AI.trace_cands)
var autoplay_loot := false  # --autoplay-loot: 代打无事可做时先去拿宝物
var idle_player := false    # --idle-player: 我方全员原地待機
var battle_stats := false   # --battle-stats: 战斗统计 (不挂机器人也开)
var probe_battle_save: Array = []   # --probe-battle-save=<回合>:save|check
var warp: Array = []        # --warp=unit_id:x,y
var wait_at: Array = []     # --wait-at=unit_id:x,y
var hp_unit: Array = []     # --hp-unit=unit_id|all:体力 (测试回合: 体力上限与当前体力都设, 只改我方)
var unit_edit: Array = []   # --unit=unit_id:{json}
var cast: Array = []        # --cast=技能[@x;y],...
var cast_as: Array = []     # --cast-as=敌方unit_id:技能号 (测试回合: 该敌方单位对我方第一个单位施放, 走真实演出)
var inject: Array = []      # 开场注入 (剧情分支验证), 按参数顺序 [种类, 值]: set_turn / place / equip / hp_cur (--hp-cur=单位下标:当前体力) / kill / run_event
var run_event := ""         # --run-event=... (战场开场注入与城镇共用; 最后一个)
var town_walk: Array = []   # 城镇测试, 按参数顺序 [种类, 值]: run_event (--run-event / --town-event) / walk (--walk=x,y) / auto_exit / walk_all
var camp_hold_space := false
var ui_page := 0            # --ui-page=N (界面组件展示)
var ui_hold := false
var banner_side := 1        # --banner-side=
var banner_turn := 1        # --banner-turn=
var sfx_log := false        # --sfx-log


## 本进程的命令行参数 (第一次调用时解析)
static func current() -> DebugArgs:
	if _current == null:
		_current = parse(OS.get_cmdline_user_args())
	return _current


static func parse(args: PackedStringArray) -> DebugArgs:
	var d := DebugArgs.new()
	d._parse(args)
	return d


## 原样参数里是否有某个开关 (给测试机器人等组装层以外的使用者; 引擎请读字段)
func has(flag: String) -> bool:
	return flag in raw


func _parse(args: PackedStringArray) -> void:
	raw = args
	for a in args:
		if a.begins_with("--autoplay") or a.begins_with("--regress") or a == "--fast" or a.begins_with("--press") or a.begins_with("--scene="):
			test_run = true
		match a:
			"--fast": fast = true
			"--skip-movies": skip_movies = true
			"--skip-dialog": skip_dialog = true
			"--god": god = true
			"--autoplay": autoplay = true
			"--gfx=orig":
				gfx_orig = true
				cli_overrides["gfx"] = "orig"
			"--no-hq": no_hq = true
			"--hq-break": hq_break = true
			"--sysfont": sysfont = true
			"--touch": touch = true
			"--load-battle": load_battle = true
			"--no-record-play": no_record_play = true
			"--ai-trace": ai_trace = true
			"--ai-cands": ai_cands = true
			"--autoplay-loot": autoplay_loot = true
			"--idle-player": idle_player = true
			"--battle-stats": battle_stats = true
			"--camp-hold-space": camp_hold_space = true
			"--ui-hold": ui_hold = true
			"--sfx-log": sfx_log = true
			"--auto-exit": town_walk.append(["auto_exit", ""])
			"--walk-all": town_walk.append(["walk_all", ""])
			_:
				_parse_value(a)


## 带值的参数 (--键=值)
func _parse_value(a: String) -> void:
	var at := a.find("=")
	if not a.begins_with("--") or at < 0:
		return
	var k := a.substr(0, at + 1)
	var v := a.substr(at + 1)
	match k:
		"--font=": cli_overrides["font"] = v   # 临时换字体 (UiFonts 清单里的 id)
		"--aspect-mode=": cli_overrides["aspect"] = v   # 临时指定画面比例 auto|keep
		"--lang=": cli_overrides["lang"] = v   # 临时指定语言 hans|hant
		"--show-hidden=": cli_overrides["show_hidden"] = int(v)   # 临时开关隐藏宝箱显示 0|1
		"--coord=": cli_overrides["coord"] = int(v)   # 临时开关格子坐标 0|1
		"--face-style=": cli_overrides["face_style"] = v   # 临时指定头像风格 classic|hk (hk 需要 mod/face_hk.pck, 或 TDJ_FACE_HK 指到目录)
		"--packs=": packs = v
		"--bundled=": bundled = v
		"--content=": content_main = v
		"--mods=": mods = Array(v.split(",", false))
		"--assets=": assets_root = v
		"--original=": original = v
		"--tex-mult=": tex_mult = int(v)   # "auto" -> 0
		"--tex-budget=": tex_budget_mb = int(v)
		"--tex-budget-max=": tex_budget_max_mb = int(v)
		"--hq-timeout=": hq_timeout_s = float(v)
		"--hq-codec=": hq_codec = v
		"--hq-cache-mb=": hq_cache_mb = int(v)
		"--hq-scale=": hq_scale = int(v)
		"--max-tex=": max_tex = int(v)
		"--aspect=":
			var wh := v.split(":")
			if wh.size() == 2 and float(wh[1]) > 0:
				aspect = float(wh[0]) / float(wh[1])
		"--scene=":
			if scene == "":
				scene = v
		"--load=": load_slots.append(int(v))
		"--give=": state_edits.append(["give", v])
		"--set-var=": state_edits.append(["set_var", v])
		"--gold=": state_edits.append(["gold", v])
		"--town-talk=":
			var tt := v.split(":")
			town_talks.append({"event": int(tt[0]), "times": int(tt[1])})
		"--choose=":
			for x in v.split(","):
				choose.append(int(x) != 0)
		"--replay-play=": replay_play = v
		"--record-play=": record_play = v
		"--replay-speed=": replay_speed = maxf(0.1, float(v))
		"--exp-mult=": exp_mult = maxf(1.0, float(v))
		"--replay-switch=": replay_switch = v
		"--seed=":
			if v.is_valid_int():
				if rng_seed == null:   # 第一个有效的为准
					rng_seed = int(v)
			else:
				push_error("--seed=%s 不是整数, 忽略 (用随机种子)" % v)
		"--probe-battle-save=": probe_battle_save.append(v)
		"--warp=": warp.append(v)
		"--wait-at=": wait_at.append(v)
		"--hp-unit=": hp_unit.append(v)
		"--unit=": unit_edit.append(v)
		"--cast=": cast.append(v)
		"--cast-as=": cast_as.append(v)
		"--set-turn=": inject.append(["set_turn", v])
		"--place=": inject.append(["place", v])
		"--equip=": inject.append(["equip", v])
		"--teach=": inject.append(["teach", v])
		"--hp-cur=": inject.append(["hp_cur", v])
		"--kill=": inject.append(["kill", v])
		"--hp=":
			push_error("--hp= 已拆成 --hp-cur=单位下标:当前体力 (开场注入) 与 --hp-unit=unit_id|all:体力 (测试回合改上限+当前), 忽略")
		"--run-event=":
			inject.append(["run_event", v])
			run_event = v
			town_walk.append(["run_event", v])
		"--town-event=": town_walk.append(["run_event", v])
		"--walk=": town_walk.append(["walk", v])
		"--ui-page=": ui_page = int(v)
		"--banner-side=": banner_side = int(v)
		"--banner-turn=": banner_turn = int(v)

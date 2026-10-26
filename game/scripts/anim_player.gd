# SPDX-License-Identifier: GPL-3.0-only
class_name AnimPlayer
extends Node2D
## 播放一段 anim.json 动画 (原版 SAF)。坐标为原版像素, 由父节点统一放大。
## 帧时长 = 0.04 * (1 + time) 秒 (与重制版一致)。部件按 type 选混合方式:
##   0 普通; 1 半透明 (影子等: 不透明度 = p8/16, p10=16 时按重制版 p8*0.05); 2~6 发光 (type=2 且 p10=0 按普通); 7 暗部遮罩。

signal finished
var _missing := false
signal frame_shown(f: int)

const TICK := 0.04
const EPS := 1e-6   # 累加 0.04 的浮点误差 (0.72 累出 0.7199999) 不能让帧切换晚一个 tick: 固定 25 帧/秒下与原版整数 tick 一致
static var LOG_SFX := DebugArgs.current().sfx_log
const SCREEN_BLEND := preload("res://shaders/screen_blend.gdshader")
const DARK_MASK := preload("res://shaders/dark_mask.gdshader")
const RED_TINT := preload("res://shaders/red_tint.gdshader")

var dir := ""
## 红色版: 把动画里的蓝白色换成红色 (隐藏宝箱的闪光), 其余 (帧、节奏、混合方式) 与原动画相同。要在 play() 之前设
var recolor_red := false
var clip_to := Vector2.ZERO   # 非零: 每个部件只取贴图左上这么大一块 (原版像素), 边缘不向透明留白取样 (满屏背板首尾相接处不露黑线)
var data := {}
var start_frame := 0
var end_frame := 0
var loop := true
var playing := false
var frame := -1
var play_sound := true
## >0: 每帧固定这么多 tick (忽略帧自带的 time)。城镇主角行走: 原版 实测每步 (10 tick) 重新走一轮 4 帧、每帧 2 tick (脚步声在每步的第 2、6 tick)
var tick_override := 0
var cull_offscreen := false  # 屏外只推进时间不换帧 (不取贴图): 城镇里全部 NPC/物件循环播放会把整个目录的帧都载入显存; 只用于不依赖 frame_shown/声音的动画
var other: AnimPlayer   # 部件 tex=null 时按 ref 引用它的帧 (近景攻击动画里画被打的一方)
var _time := 0.0
var sfx_count := 0        # 本节点触发过的音效次数 (测试/验收用)
var _abs_prev := 0        # 本次播放已处理到的「绝对帧序」(循环动画每圈累加), 帧被卡顿跳过时用它补播中间有声音的帧
var _durs: Array[float] = []
var _total := 0.0         # _durs 之和 (play 时算好, 不在每帧重算)
var _sprites: Array[Sprite2D] = []


## 播放 [start, end) 帧; end<0 表示到最后一帧
func play(anim_dir: String, start := 0, end := -1, looped := true) -> void:
	if not Assets.exists(anim_dir + "/anim.json"):  # 个别单位缺动画 (如第 31 关 man116 没有近景 misc)
		push_warning("没有动画 " + anim_dir)
		dir = anim_dir
		playing = false
		_missing = true
		visible = false
		finished.emit.call_deferred()
		return
	if _missing:
		_missing = false
		visible = true
	dir = anim_dir
	data = Assets.anim(anim_dir)
	var n: int = data["frames"].size()
	start_frame = clampi(start, 0, n - 1)
	end_frame = n if end < 0 else clampi(end, start_frame + 1, n)
	loop = looped
	_durs.clear()
	_total = 0.0
	for i in range(start_frame, end_frame):
		_durs.append(TICK * (tick_override if tick_override > 0 else 1 + maxi(0, int(data["frames"][i]["time"]))))
		_total += _durs[-1]
	_time = 0.0
	_abs_prev = 0
	playing = true
	frame = -1
	_show(start_frame)


## 只显示某一帧, 不播放
func show_frame(anim_dir: String, f: int) -> void:
	dir = anim_dir
	data = Assets.anim(anim_dir)
	playing = false
	frame = -1
	_show(f)


func _process(delta: float) -> void:
	if not playing:
		return
	_time += delta
	var total := _total
	var t := _time
	var count := _durs.size()
	var cycles := 0
	if t >= total - EPS:
		if not loop:
			_catch_up_sounds(count)   # 卡顿一次跨过了末尾的帧: 没进过的有声帧也要响 (原版每个进入的帧必响)
			playing = false
			finished.emit()
			return
		cycles = int(t / total)
		t = fmod(t, total)
	var i := 0
	while i < _durs.size() - 1 and t >= _durs[i] - EPS:
		t -= _durs[i]
		i += 1
	_catch_up_sounds(cycles * count + i)
	if cull_offscreen and start_frame + i != frame and not _near_screen():
		return  # 回到屏内时 frame 与时间对不上, 自然补一次 _show
	_show(start_frame + i)


## 帧推进一次跨过多帧 (卡顿: 首次贴图生成、着色器、加载) 时, 被跨过的帧显示不了, 但它们的音效不能丢:
## 原版固定 25 tick 逐帧推进, 区间内每个进入的帧都发声。abs_i = 这一刻的绝对帧序 (循环动画每圈累加); 循环动画最多补最近一圈
func _catch_up_sounds(abs_i: int) -> void:
	var count := _durs.size()
	if abs_i <= _abs_prev:
		return
	if play_sound and abs_i - _abs_prev > 1:
		for k in range(maxi(_abs_prev + 1, abs_i - count + 1), abs_i):
			_sound_only(start_frame + k % count)
	_abs_prev = abs_i


func _sound_only(f: int) -> void:
	var snd := int(data["frames"][clampi(f, 0, data["frames"].size() - 1)]["sound"])
	if snd >= 0:
		_play_sound(snd)


## 动画全部帧所有部件的包围盒 (相对节点原点, 原版像素); 算一次存在动画数据里
func _anim_bounds() -> Rect2:
	return bounds_of(data)


## 动画数据 (Assets.anim) 的包围盒; 算一次存在数据里
static func bounds_of(d: Dictionary) -> Rect2:
	if not d.has("_bounds"):
		var r := Rect2()
		var first := true
		for fr in d["frames"]:
			for p in fr["parts"]:
				if p["tex"] == null:
					continue
				var t: Dictionary = d["textures"][int(p["tex"])]
				var pr := Rect2(float(p["x"]), float(p["y"]), float(t["w"]), float(t["h"]))
				r = pr if first else r.merge(pr)
				first = false
		d["_bounds"] = r
	return d["_bounds"]


## 动画是不是整屏画面: 包围盒盖住整个原版画面 (window_size = 320x200, 留 1 像素余量)。
## 城镇事件里的整屏图 (客栈房间、会面) 与叠在别的画面上的局部动画靠它区分
static func data_covers_window(d: Dictionary, window_size: Vector2) -> bool:
	return bounds_of(d).grow(1.0).encloses(Rect2(Vector2.ZERO, window_size))


## 当前载入的动画是不是整屏画面 (还没载入动画数据 = 否); 场景只问这一句, 不碰动画数据
func covers_window(window_size: Vector2) -> bool:
	return data.has("frames") and data_covers_window(data, window_size)


## 动画包围盒是否与视口相交 (留 2 个原版像素余量)。屏外的动画换帧会白白载入/生成贴图
func _near_screen() -> bool:
	var xf := get_global_transform_with_canvas()
	var sc := xf.get_scale()
	var b := _anim_bounds()
	var r := Rect2(xf.origin + b.position * sc, b.size * sc).abs().grow(2.0 * absf(sc.x))
	return r.intersects(get_viewport().get_visible_rect())


func _show(f: int) -> void:
	f = clampi(f, 0, data["frames"].size() - 1)  # 事件脚本偶有越界帧号 (如第 12 关物件 10)
	if f == frame:
		return
	frame = f
	var fr: Dictionary = data["frames"][f]
	var parts: Array = fr["parts"].filter(func(p): return p["tex"] != null or (other != null and p.has("ref")))
	while _sprites.size() < parts.size():
		var s := Sprite2D.new()
		s.centered = false
		add_child(s)
		_sprites.append(s)
	for i in _sprites.size():
		_sprites[i].visible = i < parts.size()
	for i in parts.size():
		_setup(_sprites[i], parts[i])
	if play_sound and int(fr["sound"]) >= 0:
		_play_sound(int(fr["sound"]))
	frame_shown.emit(f)


func _setup(s: Sprite2D, p: Dictionary) -> void:
	if p["tex"] == null:  # 引用另一个动画第 ref 帧的第一个部件 (重制版 otherGameAnimation)
		var od: Dictionary = other.data
		var ri: int = int(p["ref"])
		if ri >= od["frames"].size() or od["frames"][ri]["parts"].is_empty():
			ri = 1
		var op: Dictionary = od["frames"][ri]["parts"][0]
		p = {"tex": op["tex"], "x": p["x"], "y": p["y"], "type": op["type"], "p8": op["p8"], "p10": op["p10"], "_dir": od["dir"]}
	var t := Assets.tex("%s/t%d.png" % [p.get("_dir", data["dir"]), int(p["tex"])])
	s.texture = t["texture"]
	s.scale = Vector2.ONE * float(t["scale"])
	s.position = Vector2(p["x"], p["y"])
	s.texture_filter = TextureSource.filter_for(t["hd"])
	s.region_enabled = clip_to != Vector2.ZERO
	if s.region_enabled:
		s.region_rect = Rect2(Vector2.ZERO, clip_to / s.scale)
		s.region_filter_clip_enabled = true
	var type: int = p["type"]
	var k := minf(int(p["p8"]) * 0.05, 1.0) if int(p["p10"]) == 16 else 1.0
	if type == 2 and int(p["p10"]) == 0:
		type = 0
	s.modulate = Color(1, 1, 1, 1)
	s.material = null
	if recolor_red and type <= 1:   # 红色版: 普通部件也换红 (发光部件在下面的混合材质里换)
		s.material = _red_material()
	if type == 1 and int(p["p10"]) != 16:
		# 原版实测: 人物脚下影子 (type 1, p8=8) 是半透明的, 地面透出约一半 (B4 近景对照); 重制版按不透明画成纯黑
		s.modulate.a = clampf(int(p["p8"]) / 16.0, 0.0, 1.0)
	elif type <= 1:
		s.modulate.a = k
	elif type == 7:
		s.material = _material(DARK_MASK, 1.0)
	else:
		s.material = _material(SCREEN_BLEND, k, recolor_red)


static var _mats := {}

static func _material(shader: Shader, k: float, red := false) -> ShaderMaterial:
	var key := "%s:%.2f:%s" % [shader.resource_path, k, red]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("strength", k)
		if red:
			m.set_shader_parameter("red", true)
		_mats[key] = m
	return _mats[key]


## 红色版的普通 (非混合) 部件材质
static func _red_material() -> ShaderMaterial:
	if not _mats.has("red_tint"):
		var m := ShaderMaterial.new()
		m.shader = RED_TINT
		_mats["red_tint"] = m
	return _mats["red_tint"]


func _play_sound(i: int) -> void:
	sfx_count += 1
	var sounds: Array = data["sounds"]
	if i >= sounds.size():
		return
	# 原版声部池: 最多 12 个叠加播放, 不打断已在播的, 满了丢弃 (SfxPool)
	var ok := SfxPool.play(Assets.sound("%s/%s" % [data["dir"], sounds[i]["file"]]))
	if LOG_SFX:  # 验收: --sfx-log 打印每次音效触发 (进程帧号/动画/帧/文件), 与原版 PlaySfx 钩子记录对照
		print("SFXLOG f=%d anim=%s frame=%d sound=%s played=%s" % [Engine.get_process_frames(), data["dir"], frame, sounds[i]["file"], ok])

# SPDX-License-Identifier: GPL-3.0-only
class_name BattleMapView
extends Node2D
## 全图小地图「地圖」(系统菜单第 2 项, 2.8; 原版 CMapViewer, 素材 Misc/MAP_VIE)。
## 原版实测 + 对照原版 (Swordman.; 窗口版 1.3 同逻辑, 地址 字段), 记录
##   - 面板 MAP_VIE 第 0 帧 (168x127) 固定在画面 (78,42) (窗口坐标 (0x6c,0x42) 减缓冲区原点 (30,24)), 不居中。
##   - 缩略图 = 第 17 + 关卡号 帧, 每格 3 像素; 可视区为面板内 (3,8) 起 162x111。
##     缩略图比可视区窄/矮时该方向居中 ((162-w)/2+3, (111-h)/2+8), 否则从左上角 (卷动 0,0) 开始, 不对准光标。
##   - 单位标记: 在场单位每个 3x3 方块 (格 x3, y3), 我方蓝 0x1f、我方 AI 友军 (字段) 绿 0x3e0、敌方红 0x7c00 (RGB555),
##     加色混合, 强度 4~16 (/16) 每 3 帧 ±2 来回呼吸。
##   - 卷动: 按住方向键每帧 (40 ms) 3 像素, 没有连发延迟 (GetAsyncKeyState); 到边不动。
##   - 可卷方向在面板外侧显示小箭头 (第 1/5/9/13 帧起 4 帧循环, 每 5 帧换一帧): 上 (80,-11) 下 (80,128) 左 (-9,60) 右 (170,60)。
##   - 打开: 5 帧从左 16 像素滑入并淡入; 关闭 (确认或取消) 反过来 5 帧滑出淡出 (84,16,8,4,2,0)。
## 坐标、帧号与参数全部取自内容包布局表 ui_theme/layout.json 的 mapview.* (load_cfg), 换游戏改表即可。

const TICK := 0.04

var cfg := {}
var scroll_pos := Vector2.ZERO
var thumb_size := Vector2.ZERO
var pulse := 0
var closing := false

var _base := Vector2.ZERO
var _clip: Control
var _map: Node2D
var _dots: Array[ColorRect] = []
var _dot_color: Array[Color] = []
var _arrows: Array[UiPanel] = []
var _arrow_phase := 0
var _arrow_wait := 0
var _pulse_up := true
var _pulse_wait := 0
var _anim: Array = []     # 正在播的 [slide, alpha] 序列
var _anim_i := 0
var _t := 0.0


## stage: 关卡号; dots: [[Vector2i 格, 阵营 0 我方 / 1 敌方 / 2 友军], ...]; _focus 保留参数 (原版不对准光标)
func _init(stage: int, _map_cells: Vector2i, dots: Array, _focus := Vector2i.ZERO) -> void:
	cfg = BattleMapView.load_cfg()
	_base = cfg["pos"]
	position = _base
	add_child(UiLayout.tag_panel(UiPanel.new(cfg["anim"], int(cfg["panel_frame"])), "mapview.panel"))
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.position = cfg["view_pos"]
	_clip.size = cfg["view_size"]
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_map = Node2D.new()
	_clip.add_child(_map)
	var f := int(cfg["thumb_frame"]) + stage
	if f < Assets.anim(cfg["anim"])["frames"].size():
		var r := UiPanel.frame_rect(cfg["anim"], f)
		var mini := UiPanel.new(cfg["anim"], f)
		mini.position = -r.position
		_map.add_child(mini)
		thumb_size = r.size
	var cell := float(cfg["cell"])
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for d in dots:
		var side := int(d[1])
		var dot := ColorRect.new()
		dot.size = Vector2.ONE * float(cfg["dot_size"])
		dot.position = Vector2(d[0]) * cell
		dot.material = add_mat
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map.add_child(dot)
		_dots.append(dot)
		_dot_color.append(cfg["dot_colors"][side] if side < cfg["dot_colors"].size() else Color.WHITE)
	pulse = int(cfg["pulse"][0])
	_arrow_wait = int(cfg["arrow_ticks"]) - 1
	for i in 4:
		var a := UiPanel.new(cfg["anim"], int(cfg["arrow_frame"][i]))
		a.position = cfg["arrow_pos"][i]
		add_child(a)
		_arrows.append(a)
	_apply()
	_apply_pulse()


## 布局表 mapview.* -> 参数
static func load_cfg() -> Dictionary:
	var c := {}
	c["anim"] = String(UiLayout.sprite("mapview.panel").get("anim", ""))
	c["pos"] = UiLayout.at("mapview.panel")
	c["panel_frame"] = UiLayout.frame("mapview.panel")
	c["view_pos"] = UiLayout.at("mapview.viewport")
	c["view_size"] = UiLayout.size_of("mapview.viewport")
	c["thumb_frame"] = int(UiLayout.num("mapview.thumb", "frame_base"))
	c["cell"] = int(UiLayout.num("mapview.thumb", "cell"))
	var ar := UiLayout.el("mapview.arrows")
	c["arrow_pos"] = []
	c["arrow_frame"] = []
	for k in ["up", "down", "left", "right"]:
		var at: Array = ar.get("at", {}).get(k, [0, 0])
		c["arrow_pos"].append(Vector2(at[0], at[1]))
		c["arrow_frame"].append(int(ar.get("frames", {}).get(k, 0)))
	c["arrow_frames"] = int(ar.get("cycle_frames", 1))
	c["arrow_ticks"] = int(ar.get("cycle_ticks", 1))
	var dt := UiLayout.el("mapview.dots")
	c["dot_size"] = int(dt.get("size", 1))
	c["dot_colors"] = []
	for k in ["player", "enemy", "ally"]:
		c["dot_colors"].append(UiLayout.color(dt.get("colors", {}).get(k, "#ffffff")))
	var pu: Dictionary = dt.get("pulse", {})
	c["pulse"] = [int(pu.get("start", 16)), int(pu.get("min", 16)), int(pu.get("max", 16)),
		int(pu.get("step", 0)), int(pu.get("ticks", 1)), int(pu.get("full", 16))]
	c["scroll_step"] = int(UiLayout.num("mapview.scroll", "step"))
	var mo := UiLayout.el("mapview.motion")
	for k in ["open_slide", "open_alpha", "close_slide", "close_alpha"]:
		c[k] = mo.get(k, [])
	return c


## 打开动画 (WindowState 加入界面后调用)
func open() -> void:
	_play(cfg["open_slide"], cfg["open_alpha"])


## 关闭: 播完滑出淡出后自行释放 (WindowState.exit 调用, 状态已经出栈)
func dismiss() -> void:
	closing = true
	_play(cfg["close_slide"], cfg["close_alpha"])


func _play(slide: Array, alpha: Array) -> void:
	_anim = []
	for i in mini(slide.size(), alpha.size()):
		_anim.append([float(slide[i]), float(alpha[i]) / 16.0])
	_anim_i = 0
	_step_anim()


func _step_anim() -> void:
	if _anim_i < _anim.size():
		position = _base - Vector2(_anim[_anim_i][0], 0)
		modulate.a = _anim[_anim_i][1]
		_anim_i += 1
		return
	_anim = []
	position = _base
	modulate.a = 1.0
	if closing:
		queue_free()


## 卷动一步 (方向键按下; 按住时 _tick 每帧调用)。到边夹紧
func scroll(d: Vector2i) -> void:
	scroll_pos += Vector2(d) * float(cfg["scroll_step"])
	_apply()


## 触摸拖动 (原版像素)
func drag(delta: Vector2) -> void:
	scroll_pos -= delta
	_apply()


func max_scroll() -> Vector2:
	return (thumb_size - _clip.size).max(Vector2.ZERO)


func _apply() -> void:
	var view: Vector2 = _clip.size
	scroll_pos = scroll_pos.clamp(Vector2.ZERO, max_scroll())
	var off := Vector2.ZERO
	for ax in 2:
		off[ax] = floorf((view[ax] - thumb_size[ax]) / 2) if thumb_size[ax] < view[ax] else -scroll_pos[ax]
	_map.position = off
	var m := max_scroll()
	_arrows[0].visible = scroll_pos.y > 0
	_arrows[1].visible = scroll_pos.y < m.y
	_arrows[2].visible = scroll_pos.x > 0
	_arrows[3].visible = scroll_pos.x < m.x


func _apply_pulse() -> void:
	var k := float(pulse) / float(cfg["pulse"][5])
	for i in _dots.size():
		var c := _dot_color[i]
		_dots[i].color = Color(c.r * k, c.g * k, c.b * k, 1.0)


## 原版时钟 (40 ms) 一拍: 开关动画、箭头循环、标记呼吸、按住方向卷动
func _tick() -> void:
	if not _anim.is_empty():
		_step_anim()
		if closing:
			return
	if _arrow_wait <= 0:
		_arrow_phase = (_arrow_phase + 1) % int(cfg["arrow_frames"])
		_arrow_wait = int(cfg["arrow_ticks"]) - 1
		for i in 4:
			_arrows[i].set_frame(cfg["anim"], int(cfg["arrow_frame"][i]) + _arrow_phase)
	else:
		_arrow_wait -= 1
	var pu: Array = cfg["pulse"]
	if _pulse_wait <= 0:
		_pulse_wait = int(pu[4]) - 1
		pulse += int(pu[3]) if _pulse_up else -int(pu[3])
		if pulse > int(pu[2]):
			pulse = int(pu[2]) - int(pu[3])
			_pulse_up = false
		elif pulse < int(pu[1]):
			pulse = int(pu[1]) + int(pu[3])
			_pulse_up = true
		_apply_pulse()
	else:
		_pulse_wait -= 1
	if not closing:
		var hd := InputRouter.held_dir() if is_inside_tree() else Vector2i.ZERO
		if hd != Vector2i.ZERO:
			scroll(hd)


func _process(delta: float) -> void:
	_t += delta
	while _t >= TICK:
		_t -= TICK
		_tick()
		if not is_instance_valid(self) or is_queued_for_deletion():
			return

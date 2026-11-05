# SPDX-License-Identifier: GPL-3.0-only
extends CanvasLayer
## 手机虚拟键 (只在 Android/iOS 或 --touch 时由 InputRouter 创建并显示; 桌面永不显示)。手游式操作盘 (参考王者荣耀一类的 HUD):
##   左下: 圆形摇杆 (底盘 + 随手指的圆钮, 取主方向四向; 方向键语义同键盘, 按住连发由 InputRouter 处理);
##     设定「触屏键样式」(touch_pad) 选十字键时换成十字键 (同位置同大小): 手指在哪条臂上就是哪个方向, 落进两臂之间的斜角保持原方向 (圆形摇杆容易斜着输入, 2026-11-03 网友反馈)。
##     两种样式对 InputRouter 一样是 STICK 键 + stick_dir, 只是判方向的规则和画法不同
##   右下: 两个一样大的圆键「确认 / 取消」, 确认在右下角, 取消在它左边 (拇指不用挪位置就够得到; 2026-10-25 去掉了没用的「菜单」键和「查看」键 — 查看用长按, 见 TouchGestures)
##   (翻页没有键: 营地列表等左右快滑翻页, 见 TouchGestures)
##   右上角: 小圆「隐/显」钮 (缺省隐藏整套键), 点一下隐藏/显示整套键 (隐藏后只剩它和左边的「设置」「加速」钮, 看地图不挡), 三钮一样大; 「设置」钮打开设定面板 (分辨率/简繁体/画质等);
##     「加速」钮 (快进图标) 弹出加速档位菜单, 选一档即生效 (游戏速度, 见 GameSpeed)
## 样式: 半透明深色圆底 + 金色描边, 各键描边色不同 (确认金 / 取消红), 字用游戏字体、米色加深色描边; 按下变亮并缩小一点。
##   不透明度 ALPHA, 闲置 IDLE_SEC 秒后降到 IDLE_ALPHA, 一碰就恢复。尺寸全按画面高度的比例算, 手机/平板/桌面 --touch 通用。
##   刘海屏: 取系统给的安全区边距 (DisplayServer.get_display_safe_area), 键组往里缩。
## 另外保留直接点按选格/点菜单 (TouchGestures), 比重制版只有虚拟手柄更方便。
## 本节点不读输入: InputRouter 调 hit(视口坐标) 得到键的动作, 按下/松开当作按键处理; 摇杆是 STICK, 手指在底盘上拖动时
## InputRouter 反复调 stick_dir(视口坐标) 得到当前方向 (UiAction.UP/DOWN/LEFT/RIGHT 或 NONE); press()/release() 只管外观。
## 编辑模式 (begin_edit, 设定「触屏键位置」经 TouchLayoutPanel 进入; 2026-11-04 用户要求, 参考别的移植版的同类界面): 整套键全显示, 每个键 (含摇杆、右上角小钮) 外面画虚线边界,
##   单独拖到哪就放哪; 可用区域 (安全区) 画虚线框; 一条可拖动的工具条: 提示「拖动…」、透明度滑条、大小滑条、复位、完成。
##   编辑中 InputRouter 把触摸全交给 edit_touch, 不当按键; 完成 (end_edit) 发 edit_finished(布局), 由面板存进设定 touch_layout。
##   布局 (位置比例 / 透明度 / 大小) 的数据与校验见 TouchLayout。

## 开关钮的动作 (不是 UiAction): 切换显示
const TOGGLE := -100
## 设置钮的动作 (不是 UiAction): 打开设定面板 (桌面是 F10; 触屏没有键盘, 分辨率/简繁体/画质等只能从这里进), 操作盘隐藏时也能点
const SETTINGS := -102
## 加速钮的动作 (不是 UiAction): 弹出加速档位菜单 (手机没有键盘, 游戏速度原来只能在设定面板里调), 和设置钮一样操作盘隐藏时也能点
const SPEED := -103
## 摇杆的「键」(命中摇杆底盘): 不是 UiAction, 方向由 stick_dir 给
const STICK := -101
## 键 -> TouchLayout 里的键名 (存位置用)
const NAME_OF := {STICK: "stick", UiAction.CONFIRM: "confirm", UiAction.CANCEL: "cancel", TOGGLE: "toggle", SETTINGS: "settings", SPEED: "speed"}

## 缺省不显示整套键 (2026-10-07 用户觉得虚拟键不好用: 点位置/点图标/长按/点菜单外已能操作); 隐藏时只剩「显」与「设置」两个小钮
const DEFAULT_SHOWN := false
const IDLE_ALPHA := 0.38       # 闲置时的不透明度 (设定的不透明度更低时取设定值); 不透明度本身在设定 touch_layout.alpha
const IDLE_SEC := 3.0
const FADE := 0.25

## 各部件尺寸 (占画面高度的比例)
const MARGIN := 0.045           # 距屏幕边 (桌面 --touch)
const EDGE := 0.10              # 手机上距屏幕边更远: 曲面屏边缘防误触 / 系统返回手势会吞掉贴边的触摸 (魅族 20 Pro 上设置钮、摇杆按不出来)
const STICK_R := 0.155          # 摇杆底盘半径
const KNOB_RATIO := 0.42        # 圆钮半径 / 底盘半径
const KNOB_TRAVEL := 0.55       # 圆钮最大偏移 / 底盘半径
const DEAD := 0.28              # 死区 / 底盘半径
const DPAD_ARM := 0.62          # 十字键臂宽 / 底盘半径 (臂长到底盘边)
const DPAD_DEAD := 0.2          # 十字键中心无方向区 / 底盘半径
const BTN_R := 0.095            # 确认 / 取消两个键的半径 (一样大)
const TOGGLE_R := 0.036         # 开关钮半径
const GAP := 0.014              # 键间空隙
const HIT_SCALE := 1.12         # 命中区比外观大一点 (拇指不精确)

const GOLD := Color(0.94, 0.78, 0.40)
const CREAM := Color(1.0, 0.94, 0.78)
const DARK := Color(0.05, 0.03, 0.02)
const COLORS := {
	UiAction.CONFIRM: Color(0.96, 0.76, 0.30), UiAction.CANCEL: Color(0.90, 0.38, 0.32),
	TOGGLE: Color(0.94, 0.88, 0.70), SETTINGS: Color(0.62, 0.84, 0.52), SPEED: Color(0.55, 0.78, 0.92),
}

## 编辑模式工具条 (占画面高度的比例)
const BAR_FONT := 0.032         # 字号
const BAR_SLIDER := 0.2         # 滑条长
const BAR_Y := 0.3              # 工具条中心在可用区域里的竖直位置 (不挡右上角小钮和下面的拇指区; 挡住了可以拖开)

signal edit_finished(layout: Dictionary)

## 方向键样式 (设定「触屏键样式」touch_pad 的值)
const STYLE_STICK := "stick"
const STYLE_DPAD := "dpad"

var shown := DEFAULT_SHOWN   # 整套键是否显示; 缺省隐藏, 靠点按/手势操作, 要用点「显」
var _pad: Node2D
var _keys: Array = []          # [{kind, c: 视口坐标中心, r: 半径}] (_layout 算)
var _pressed := {}             # 键 -> 是否按着
var _stick_c := Vector2.ZERO
var _stick_r := 0.0
var _knob := Vector2.ZERO      # 圆钮相对底盘中心的偏移
var _stick_dir := UiAction.NONE
var _style := STYLE_STICK
var _fast := false             # 上次画加速钮时是否在加速 (变了就重画)
var _idle := 0.0
var _tw: Tween
var _cfg := TouchLayout.defaults()   # 当前布局 (设定 touch_layout; 编辑中是正在改的那份)
var _bounds := Rect2()         # 窗口边缘 (视口坐标, 见 window_bounds)
var _area := Rect2()           # 可用区域 = 窗口去掉系统安全区; 键位置按它的比例存

## 编辑模式
var editing := false
var _edit_cv: Node2D           # 虚线边界与工具条 (不随键的不透明度变淡)
var _dim: Node2D               # 编辑时压暗游戏画面 (提示现在是摆键, 不是在玩)
var _edit_drag := {}           # 手指 -> {what: key/bar/alpha/size/button/none, ...}
var _bar := Rect2()            # 工具条 (视口坐标)
var _bar_off := Vector2.ZERO   # 工具条被拖开的偏移 (只在本次编辑里有效)
var _bar_items: Array = []     # [{type: text/slider/button, id, rect, text}]
var _bar_fs := 16


## 画布: 本节点自己不画, 交给这个 Node2D 的 _draw
class _Paint:
	extends Node2D
	var owner_pad
	var mode := 0   # 0 = 键, 1 = 编辑层 (边界与工具条, 在键之上), 2 = 编辑时的暗底 (在键之下)

	func _draw() -> void:
		match mode:
			1: owner_pad._paint_edit(self)
			2: self.draw_rect(owner_pad._bounds, Color(0.0, 0.0, 0.0, 0.35))
			_: owner_pad._paint(self)


func _init() -> void:
	layer = 110
	_dim = _Paint.new()
	_dim.owner_pad = self
	_dim.mode = 2
	_dim.visible = false
	add_child(_dim)
	_pad = _Paint.new()
	_pad.owner_pad = self
	add_child(_pad)
	_pad.modulate.a = _alpha() if shown else _idle_alpha()
	_edit_cv = _Paint.new()
	_edit_cv.owner_pad = self
	_edit_cv.mode = 1
	_edit_cv.visible = false
	add_child(_edit_cv)


func _ready() -> void:
	_apply_style()
	var gc := GameContext.current()
	if not gc.settings_applied.is_connected(_apply_style):
		gc.settings_applied.connect(_apply_style)
	_layout()
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_layout):
		vp.size_changed.connect(_layout)
	if not ScreenLayout.changed.is_connected(_layout):
		ScreenLayout.changed.connect(_layout)


## 跟随设定 touch_pad / touch_layout (设定面板里改了立刻换); 编辑中不动正在改的布局
func _apply_style() -> void:
	var st: Dictionary = GameContext.current().settings
	set_style(String(st.get("touch_pad", STYLE_STICK)))
	if not editing:
		set_layout(st.get("touch_layout"))


## 换布局 (TouchLayout 格式, 会先校验): 重排并按新的不透明度显示
func set_layout(v) -> void:
	_cfg = TouchLayout.sanitize(v)
	_set_alpha(_alpha() if shown else _idle_alpha(), false)
	if is_inside_tree():
		_layout()


func layout_config() -> Dictionary:
	return _cfg.duplicate(true)


## 不透明度: 设定值; 闲置 (或整套键隐藏) 时取 IDLE_ALPHA, 设定的更低就取设定值
func _alpha() -> float:
	return float(_cfg["alpha"]) / 100.0


func _idle_alpha() -> float:
	return minf(IDLE_ALPHA, _alpha())


func set_style(style: String) -> void:
	style = STYLE_DPAD if style == STYLE_DPAD else STYLE_STICK
	if style == _style:
		return
	_style = style
	stick_release()


func style() -> String:
	return _style


# ---------------------------------------------------------------- 布局

## 窗口边缘在视口坐标里的范围: 视口 (逻辑画面) 按 min(窗宽/视口宽, 窗高/视口高) 缩放后居中放进窗口, 比窗口窄的方向留黑边;
## 虚拟键按窗口边缘排 (键贴窗口边而不是贴逻辑画面边, 窗口模式 / 平板 4:3 留黑边时也在拇指够得到的位置)。画面比窗口窄时范围比视口大, 键画在黑边里
static func window_bounds(vp: Rect2, win: Vector2) -> Rect2:
	if vp.size.x <= 0.0 or vp.size.y <= 0.0 or win.x <= 0.0 or win.y <= 0.0:
		return vp
	var sz := win / minf(win.x / vp.size.x, win.y / vp.size.y)
	return Rect2(vp.get_center() - sz / 2.0, sz)


## 系统安全区 (刘海 / 圆角 / 系统栏, 屏幕像素坐标) 落进窗口 (屏幕坐标里 win_pos / win_size) 的四边内缩, 视口单位: [左, 上, 右, 下]。
## 只算窗口真正被占到的部分: 窗口模式下系统栏已在窗口之外, 不能再扣一次 (旧算法按整屏比例换算, 窗口比屏幕小时键组偏)。s = 窗口像素 / 视口单位
static func window_insets(sa: Rect2, win_pos: Vector2, win_size: Vector2, s: float) -> Array:
	if sa.size.x <= 0.0 or sa.size.y <= 0.0 or s <= 0.0:
		return [0.0, 0.0, 0.0, 0.0]
	return [maxf(sa.position.x - win_pos.x, 0.0) / s, maxf(sa.position.y - win_pos.y, 0.0) / s,
		maxf(win_pos.x + win_size.x - sa.end.x, 0.0) / s, maxf(win_pos.y + win_size.y - sa.end.y, 0.0) / s]


## 当前窗口里的安全区内缩 (视口单位); 桌面和取不到时全 0
func _insets(bounds: Rect2) -> Array:
	if not Platform.is_mobile():
		return [0.0, 0.0, 0.0, 0.0]
	var win := get_window()
	var ws := Vector2(win.size)
	if ws.x <= 0.0 or bounds.size.x <= 0.0:
		return [0.0, 0.0, 0.0, 0.0]
	return window_insets(Rect2(DisplayServer.get_display_safe_area()), Vector2(win.position), ws, ws.x / bounds.size.x)


func _layout() -> void:
	var vr := get_viewport().get_visible_rect()
	var h := vr.size.y
	var bounds := window_bounds(vr, Vector2(get_window().size)) if Platform.is_mobile() else vr
	var ins := _insets(bounds)
	_bounds = bounds
	_area = Rect2(bounds.position + Vector2(float(ins[0]), float(ins[1])),
		bounds.size - Vector2(float(ins[0]) + float(ins[2]), float(ins[1]) + float(ins[3])))
	var m := (EDGE if Platform.is_mobile() else MARGIN) * h
	var left: float = _area.position.x + m
	var right: float = _area.end.x - m
	var bottom: float = _area.end.y - m
	var s := float(_cfg["size"]) / 100.0   # 设定的大小: 各键半径与间距一起缩放
	_keys.clear()
	# 摇杆
	_stick_r = STICK_R * h * s
	_stick_c = _place(STICK, Vector2(left + _stick_r, bottom - _stick_r), _stick_r)
	# 确认 / 取消: 两个一样大的圆键 (确认在右下角, 取消在它正左)
	var rb := BTN_R * h * s
	var a_c := Vector2(right - rb, bottom - rb)
	_keys.append({"kind": UiAction.CONFIRM, "c": _place(UiAction.CONFIRM, a_c, rb), "r": rb})
	var d := rb * 2.0 + GAP * h * s
	_keys.append({"kind": UiAction.CANCEL, "c": _place(UiAction.CANCEL, a_c + Vector2(-d, 0.0), rb), "r": rb})
	# 右上角两个小钮 (大小一样, 都按「显」钮的半径): 最右「显/隐」, 左边「设置」; 不占摇杆和确认键的拇指区, 操作盘隐藏时仍在
	var rt := TOGGLE_R * h * s
	var top: float = _area.position.y + m
	var tc := Vector2(right - rt, top + rt)
	_keys.append({"kind": TOGGLE, "c": _place(TOGGLE, tc, rt), "r": rt})
	var step := Vector2(rt * 2.0 + GAP * h * s, 0.0)
	_keys.append({"kind": SETTINGS, "c": _place(SETTINGS, tc - step, rt), "r": rt})
	_keys.append({"kind": SPEED, "c": _place(SPEED, tc - step * 2.0, rt), "r": rt})   # 加速钮放在设置钮左边
	if editing:
		_layout_bar(h)
	_pad.queue_redraw()
	_edit_cv.queue_redraw()
	_dim.queue_redraw()


## 键的中心: 布局里存了位置 (比例) 用它, 否则用缺省排法 def; 都夹在可用区域里 (整个键不出界)
func _place(kind: int, def: Vector2, r: float) -> Vector2:
	var p = _cfg["pos"].get(NAME_OF[kind])
	return _clamp_in_area(def if p == null else _area.position + Vector2(p[0], p[1]) * _area.size, r)


func _clamp_in_area(c: Vector2, r: float) -> Vector2:
	var lo := _area.position + Vector2(r, r)
	var hi := (_area.end - Vector2(r, r)).max(lo)
	return c.clamp(lo, hi)


## 键列表 (测试与调试用): [{kind, c, r}]
func keys() -> Array:
	return _keys


# ---------------------------------------------------------------- 外观

## 键上与工具条的字体 (游戏字体)
static func _font() -> Font:
	return Assets.font(true)


func _paint(cv: Node2D) -> void:
	var font := _font()
	if shown or editing:
		if _style == STYLE_DPAD:
			_paint_dpad(cv)
		else:
			_paint_stick(cv)
	for k in _keys:
		var kind: int = k["kind"]
		if not shown and not editing and not _always(kind):
			continue
		_paint_button(cv, font, kind, k["c"], k["r"])


func _paint_stick(cv: Node2D) -> void:
	var c := _stick_c
	var r := _stick_r
	var down: bool = _pressed.get(STICK, false)
	cv.draw_circle(c, r, Color(DARK, 0.34))
	cv.draw_arc(c, r, 0.0, TAU, 64, Color(GOLD, 0.75), maxf(2.0, r * 0.035), true)
	cv.draw_arc(c, r * 0.58, 0.0, TAU, 48, Color(GOLD, 0.25), maxf(1.0, r * 0.02), true)
	# 四个方向小三角 (当前方向亮起)
	var dirs := {UiAction.UP: Vector2.UP, UiAction.DOWN: Vector2.DOWN, UiAction.LEFT: Vector2.LEFT, UiAction.RIGHT: Vector2.RIGHT}
	for k in dirs:
		var dv: Vector2 = dirs[k]
		var on: bool = _stick_dir == k
		cv.draw_colored_polygon(_triangle(c + dv * r * 0.78, dv, r * 0.12), Color(GOLD if on else CREAM, 1.0 if on else 0.55))
	# 圆钮
	var kc := c + _knob
	var kr := r * KNOB_RATIO
	cv.draw_circle(kc, kr, Color(0.96, 0.78, 0.42, 0.62 if down else 0.42))
	cv.draw_arc(kc, kr, 0.0, TAU, 40, Color(GOLD, 0.95), maxf(2.0, r * 0.03), true)


## 十字键: 横竖两条臂 (圆角) 叠成十字, 每臂一个朝外的小三角; 按着的那条臂变亮
func _paint_dpad(cv: Node2D) -> void:
	var c := _stick_c
	var r := _stick_r
	var w := r * DPAD_ARM
	var line := maxf(2.0, r * 0.035)
	var dirs := {UiAction.UP: Vector2.UP, UiAction.DOWN: Vector2.DOWN, UiAction.LEFT: Vector2.LEFT, UiAction.RIGHT: Vector2.RIGHT}
	var outline := PackedVector2Array()
	for p in [Vector2(-0.5, -1), Vector2(0.5, -1), Vector2(0.5, -0.5), Vector2(1, -0.5), Vector2(1, 0.5), Vector2(0.5, 0.5),
			Vector2(0.5, 1), Vector2(-0.5, 1), Vector2(-0.5, 0.5), Vector2(-1, 0.5), Vector2(-1, -0.5), Vector2(-0.5, -0.5)]:
		outline.append(c + Vector2(p.x * (w if absf(p.x) == 0.5 else r), p.y * (w if absf(p.y) == 0.5 else r)))
	cv.draw_colored_polygon(outline, Color(DARK, 0.42))
	for k in dirs:
		var dv: Vector2 = dirs[k]
		var on: bool = _stick_dir == k
		if on:   # 按着的臂: 臂上 (中心方块以外) 铺亮色
			var a := c + dv * w * 0.5
			var b := c + dv * r
			var side := Vector2(-dv.y, dv.x) * w * 0.5
			cv.draw_colored_polygon(PackedVector2Array([a + side, b + side, b - side, a - side]), Color(GOLD, 0.6))
		cv.draw_colored_polygon(_triangle(c + dv * r * 0.72, dv, r * 0.12), Color(GOLD if on else CREAM, 1.0 if on else 0.6))
	var closed := outline.duplicate()
	closed.append(outline[0])
	cv.draw_polyline(closed, Color(GOLD, 0.75), line, true)
	cv.draw_circle(c, w * 0.22, Color(GOLD, 0.25))


func _paint_button(cv: Node2D, font: Font, kind: int, c: Vector2, r: float) -> void:
	var down: bool = _pressed.get(kind, false)
	var col: Color = COLORS.get(kind, GOLD)
	var rr := r * (0.92 if down else 1.0)
	cv.draw_circle(c, rr, Color(col.r * 0.28, col.g * 0.2, col.b * 0.12, 0.72 if down else 0.5))
	cv.draw_arc(c, rr, 0.0, TAU, 48, Color(col, 1.0 if down else 0.9), maxf(2.0, r * 0.07), true)
	cv.draw_arc(c, rr * 0.82, 0.0, TAU, 40, Color(col, 0.28), maxf(1.0, r * 0.03), true)
	if kind == SETTINGS:
		_icon_gear(cv, c, rr * 0.62)
	elif kind == SPEED:
		_icon_fast(cv, c, rr * 0.62, GameSpeed.factor > 1.0)
	elif kind == TOGGLE:
		_icon_pad(cv, c, rr * 0.62, shown)
	else:
		_label(cv, font, _text_of(kind), c, rr, kind == UiAction.CONFIRM)


## 齿轮图标 (设置钮): 八个齿的米色齿轮 + 中间镂空
func _icon_gear(cv: Node2D, c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		for da in [[-0.30, 0.78], [-0.17, 1.0], [0.17, 1.0], [0.30, 0.78]]:
			pts.append(c + Vector2.from_angle(a + da[0]) * r * da[1])
	cv.draw_colored_polygon(pts, CREAM)
	cv.draw_circle(c, r * 0.38, Color(DARK, 0.92))


## 加速图标 (加速钮): 两个并排朝右的三角 (快进); 当前已在加速 (倍数 > 1) 时染成亮色提醒
func _icon_fast(cv: Node2D, c: Vector2, r: float, on: bool) -> void:
	var col := Color(COLORS[SPEED].lerp(Color.WHITE, 0.35), 1.0) if on else CREAM
	for dx in [-0.5, 0.45]:
		cv.draw_colored_polygon(_triangle(c + Vector2(r * dx, 0.0), Vector2.RIGHT, r * 0.62), col)


## 手柄图标 (显/隐钮): 机身 + 左十字键 + 右两个按键; 整套键正显示时加一道斜线 (点一下隐藏)
func _icon_pad(cv: Node2D, c: Vector2, r: float, slashed: bool) -> void:
	var w := r * 1.15
	var h := r * 0.62
	cv.draw_rect(Rect2(c.x - w, c.y - h, w * 2.0, h * 2.0), CREAM)
	cv.draw_circle(c + Vector2(-w, 0.0), h, CREAM)
	cv.draw_circle(c + Vector2(w, 0.0), h, CREAM)
	var d := Color(DARK, 0.92)
	var u := r * 0.17
	var dc := c + Vector2(-w * 0.55, 0.0)
	cv.draw_rect(Rect2(dc.x - u * 2.2, dc.y - u * 0.8, u * 4.4, u * 1.6), d)
	cv.draw_rect(Rect2(dc.x - u * 0.8, dc.y - u * 2.2, u * 1.6, u * 4.4), d)
	cv.draw_circle(c + Vector2(w * 0.45, u * 0.9), u * 1.15, d)
	cv.draw_circle(c + Vector2(w * 0.8, -u * 0.9), u * 1.15, d)
	if slashed:
		cv.draw_line(c + Vector2(-w, h * 1.4), c + Vector2(w, -h * 1.4), Color(DARK, 0.95), maxf(3.0, r * 0.26))
		cv.draw_line(c + Vector2(-w, h * 1.4), c + Vector2(w, -h * 1.4), Color(COLORS[TOGGLE], 1.0), maxf(1.5, r * 0.13))

## 操作盘隐藏时仍显示、仍能点的小钮: 显/隐、设置、加速
static func _always(kind: int) -> bool:
	return kind == TOGGLE or kind == SETTINGS or kind == SPEED


## 键上的字: 确认/取消两字, 开关钮一字 (隐藏时显示「显」)
func _text_of(kind: int) -> String:
	match kind:
		UiAction.CONFIRM: return UiStrings.t("touch.confirm")
		UiAction.CANCEL: return UiStrings.t("touch.cancel")
		TOGGLE: return UiStrings.t("touch.hide" if shown else "touch.show")
		SETTINGS: return UiStrings.t("touch.settings")
	return ""


func _label(cv: Node2D, font: Font, text: String, c: Vector2, r: float, big: bool) -> void:
	var n := maxi(1, text.length())
	var size := int(r * (0.78 if n == 1 else (0.62 if big else 0.56)))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(c.x - w / 2.0, c.y + size * 0.34)
	cv.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, size / 6), Color(DARK, 0.9))
	cv.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, CREAM)


## 朝 dir 的等腰三角 (尖在前), 中心 c, 大小 s
static func _triangle(c: Vector2, dir: Vector2, s: float) -> PackedVector2Array:
	var side := Vector2(-dir.y, dir.x)
	return PackedVector2Array([c + dir * s, c - dir * s * 0.6 + side * s * 0.9, c - dir * s * 0.6 - side * s * 0.9])


func _process(delta: float) -> void:
	var fast := GameSpeed.factor > 1.0
	if fast != _fast:   # 加速钮的图标随当前是否在加速换色
		_fast = fast
		_pad.queue_redraw()
	if not visible or not shown or editing:
		return
	var real_dt := GameSpeed.real_delta(delta)   # 无操作变淡: 真实时间
	_idle += real_dt
	if _idle >= IDLE_SEC and _idle - real_dt < IDLE_SEC:
		_set_alpha(_idle_alpha(), true)


func _set_alpha(a: float, animate: bool) -> void:
	if _tw:
		_tw.kill()
	if not animate:
		_pad.modulate.a = a
		return
	_tw = create_tween()
	_tw.tween_property(_pad, "modulate:a", a, FADE)


## 有触摸: 恢复不透明度
func touched() -> void:
	_idle = 0.0
	if _pad.modulate.a < _alpha() - 0.01 and shown:
		_set_alpha(_alpha(), true)


## 显示/隐藏整套键 (隐藏后只剩开关钮)
func toggle() -> void:
	shown = not shown
	_idle = 0.0
	_set_alpha(_alpha() if shown else _idle_alpha(), true)
	_pad.queue_redraw()


## 按下 / 松开某键的外观 (变亮并缩小一点)
func press(kind: int, on: bool) -> void:
	_pressed[kind] = on
	_pad.queue_redraw()


# ---------------------------------------------------------------- 命中与摇杆

## 视口坐标 p 落在哪个键上: 返回 UiAction 动作 / TOGGLE / STICK, 没有为 UiAction.NONE。隐藏时只有开关钮有效
func hit(p: Vector2) -> int:
	if not visible:
		return UiAction.NONE
	for k in _keys:
		if not shown and not _always(int(k["kind"])):
			continue
		if p.distance_to(k["c"]) <= float(k["r"]) * HIT_SCALE:
			return int(k["kind"])
	if shown and p.distance_to(_stick_c) <= _stick_r * 1.25:
		return STICK
	return UiAction.NONE


## 手指在 p: 更新圆钮并返回摇杆当前方向 (UiAction.UP/DOWN/LEFT/RIGHT, 在死区内为 NONE)。取主方向, 斜着推时带一点粘滞 (换方向要多推 25%)。
## 十字键样式见 _dpad_dir
func stick_dir(p: Vector2) -> int:
	var v := p - _stick_c
	if _style == STYLE_DPAD:
		_stick_dir = _dpad_dir(v)
		_pad.queue_redraw()
		return _stick_dir
	_knob = v.limit_length(_stick_r * KNOB_TRAVEL)
	var d := UiAction.NONE
	if v.length() >= _stick_r * DEAD:
		var horiz: bool = absf(v.x) >= absf(v.y)
		if _stick_dir != UiAction.NONE:   # 粘滞: 当前方向的轴只要没被另一轴超过 1.25 倍就保持
			var cur_horiz: bool = _stick_dir in [UiAction.LEFT, UiAction.RIGHT]
			var along := absf(v.x) if cur_horiz else absf(v.y)
			var across := absf(v.y) if cur_horiz else absf(v.x)
			horiz = cur_horiz if across <= along * 1.25 else not cur_horiz
		d = (UiAction.RIGHT if v.x > 0 else UiAction.LEFT) if horiz else (UiAction.DOWN if v.y > 0 else UiAction.UP)
	_stick_dir = d
	_pad.queue_redraw()
	return d


## 十字键判方向 (v = 手指相对中心): 中心小区无方向; 落在竖臂的宽度里 (|x| <= 臂宽/2) 就是上 / 下, 横臂里就是左 / 右;
## 两臂之间的斜角 (两个都不满足) 保持当前方向 (刚按下就落在斜角时取主方向), 所以拇指斜着滑不会在两个方向间跳
func _dpad_dir(v: Vector2) -> int:
	var half := _stick_r * DPAD_ARM * 0.5
	if v.length() < _stick_r * DPAD_DEAD:
		return UiAction.NONE
	var vert := absf(v.x) <= half
	var horiz := absf(v.y) <= half
	if not vert and not horiz:
		if _stick_dir != UiAction.NONE:
			return _stick_dir
		horiz = absf(v.x) >= absf(v.y)
	elif vert and horiz:   # 中心方块里 (死区外): 取主方向
		horiz = absf(v.x) >= absf(v.y)
	if horiz:
		return UiAction.RIGHT if v.x > 0 else UiAction.LEFT
	return UiAction.DOWN if v.y > 0 else UiAction.UP


## 手指离开摇杆: 圆钮回中
func stick_release() -> void:
	_knob = Vector2.ZERO
	_stick_dir = UiAction.NONE
	_pressed[STICK] = false
	_pad.queue_redraw()


# ---------------------------------------------------------------- 编辑模式 (拖动改位置)

## 进入编辑: 整套键全显示 (不管当前隐不隐藏), 按设定的不透明度显示 (不闲置变淡), 画边界与工具条
func begin_edit() -> void:
	if editing:
		return
	stick_release()
	_pressed.clear()
	_cfg = TouchLayout.sanitize(GameContext.current().settings.get("touch_layout"))
	editing = true
	_edit_drag.clear()
	_bar_off = Vector2.ZERO
	_edit_cv.visible = true
	_dim.visible = true
	_set_alpha(_alpha(), false)
	_layout()


## 完成: 退出编辑, 整套键显示出来 (刚摆好要用), 发 edit_finished(布局)
func end_edit() -> void:
	if not editing:
		return
	editing = false
	_edit_drag.clear()
	_edit_cv.visible = false
	_dim.visible = false
	shown = true
	_idle = 0.0
	_set_alpha(_alpha(), false)
	_layout()
	edit_finished.emit(layout_config())


## 复位: 位置、不透明度、大小都回缺省 (还在编辑里, 点完成才存)
func reset_layout() -> void:
	_cfg = TouchLayout.defaults()
	_set_alpha(_alpha(), false)
	_layout()


## 编辑中的一个触摸事件 (InputRouter 转来; moved = 拖动)。按下时决定这根手指拖什么: 工具条上的滑条 / 按钮 > 键 > 工具条空白处 (拖工具条);
## 按钮在松开时还在按钮上才生效
func edit_touch(index: int, pos: Vector2, pressed: bool, moved: bool) -> void:
	if not editing:
		return
	if moved:
		var d: Dictionary = _edit_drag.get(index, {})
		match String(d.get("what", "")):
			"key":
				_move_key(int(d["kind"]), pos - d["off"])
			"bar":
				_bar_off = d["start_off"] + (pos - d["start"])
				_layout()
			"alpha", "size":
				_slide(String(d["what"]), pos)
		return
	if pressed:
		var w := edit_hit(pos)
		_edit_drag[index] = w
		if w["what"] == "alpha" or w["what"] == "size":
			_slide(String(w["what"]), pos)
		_edit_cv.queue_redraw()
		return
	var d: Dictionary = _edit_drag.get(index, {})
	_edit_drag.erase(index)
	_edit_cv.queue_redraw()
	if d.get("what") == "button" and (d["rect"] as Rect2).grow(_bar_fs * 0.5).has_point(pos):
		if d["id"] == "reset":
			reset_layout()
		elif d["id"] == "done":
			end_edit()


## 编辑中 p 落在什么上: {what: alpha/size (滑条) / button (id, rect) / key (kind, off = p - 键中心) / bar (start, start_off) / none}
func edit_hit(p: Vector2) -> Dictionary:
	for it in _bar_items:
		var r: Rect2 = it["rect"]
		if it["type"] == "slider" and r.grow_individual(_bar_fs * 0.6, _bar_fs, _bar_fs * 0.6, _bar_fs).has_point(p):
			return {"what": it["id"]}
		if it["type"] == "button" and r.has_point(p):
			return {"what": "button", "id": it["id"], "rect": r}
	for i in range(_keys.size() - 1, -1, -1):
		var k: Dictionary = _keys[i]
		if p.distance_to(k["c"]) <= float(k["r"]) * HIT_SCALE:
			return {"what": "key", "kind": int(k["kind"]), "off": p - k["c"]}
	if p.distance_to(_stick_c) <= _stick_r * 1.25:
		return {"what": "key", "kind": STICK, "off": p - _stick_c}
	if _bar.has_point(p):
		return {"what": "bar", "start": p, "start_off": _bar_off}
	return {"what": "none"}


## 把键 kind 的中心挪到 c (夹在可用区域里), 存成比例位置
func _move_key(kind: int, c: Vector2) -> void:
	var r := _stick_r
	for k in _keys:
		if int(k["kind"]) == kind:
			r = float(k["r"])
	c = _clamp_in_area(c, r)
	_cfg["pos"][NAME_OF[kind]] = [(c.x - _area.position.x) / maxf(_area.size.x, 1.0), (c.y - _area.position.y) / maxf(_area.size.y, 1.0)]
	_layout()


## 滑条 (alpha / size) 拖到 p: 按横向位置取值, 立即生效
func _slide(id: String, p: Vector2) -> void:
	for it in _bar_items:
		if it["type"] == "slider" and it["id"] == id:
			var r: Rect2 = it["rect"]
			var t := clampf((p.x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
			var rng := _slider_range(id)
			var v := roundi(lerpf(rng.x, rng.y, t))
			if v != int(_cfg[id]):
				_cfg[id] = v
				if id == "alpha":
					_set_alpha(_alpha(), false)
				_layout()
			return


static func _slider_range(id: String) -> Vector2:
	if id == "alpha":
		return Vector2(TouchLayout.ALPHA_MIN, 100)
	return Vector2(TouchLayout.SIZE_MIN, TouchLayout.SIZE_MAX)


## 工具条排版: 提示 | 透明度 [滑条] | 大小 [滑条] | 复位 | 完成; 一行放不下 (窄屏) 就把提示单放一行。
## 缺省在可用区域上部居中 (BAR_Y), 加上被拖开的偏移, 夹在窗口里
func _layout_bar(h: float) -> void:
	var font := _font()
	var fs := maxi(10, int(h * BAR_FONT))
	_bar_fs = fs
	var gap := fs * 0.8
	var pad := fs * 0.8
	var bh := fs * 2.0
	var row_h := fs * 2.6
	var sl := h * BAR_SLIDER
	var tw := func(t: String) -> float: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var hint := UiStrings.t("touch.edit.hint")
	var bw := maxf(tw.call(UiStrings.t("touch.edit.reset")), tw.call(UiStrings.t("touch.edit.done"))) + fs * 1.6
	# 控件那一行: [类型, id, 宽, 文字]
	var ctl: Array = [["text", "", tw.call(UiStrings.t("touch.edit.alpha")), UiStrings.t("touch.edit.alpha")], ["slider", "alpha", sl, ""],
		["text", "", tw.call(UiStrings.t("touch.edit.size")), UiStrings.t("touch.edit.size")], ["slider", "size", sl, ""],
		["button", "reset", bw, UiStrings.t("touch.edit.reset")], ["button", "done", bw, UiStrings.t("touch.edit.done")]]
	var cw := 0.0
	for c in ctl:
		cw += float(c[2]) + gap * (1.5 if c[0] == "slider" else 1.0)
	cw -= gap
	var hw: float = tw.call(hint)
	var one_row := hw + gap * 2.0 + cw + pad * 2.0 <= _bounds.size.x * 0.96
	var rows: Array = [[["text", "", hw, hint]] + ctl] if one_row else [[["text", "", hw, hint]], ctl]
	var width := 0.0
	for row in rows:
		var w := -gap
		for c in row:
			w += float(c[2]) + gap * (1.5 if c[0] == "slider" else 1.0)
		width = maxf(width, w)
	var size := Vector2(width + pad * 2.0, row_h * rows.size() + pad * 0.6)
	var center := Vector2(_area.get_center().x, _area.position.y + _area.size.y * BAR_Y) + _bar_off
	var lo := _bounds.position + size / 2.0
	center = center.clamp(lo, (_bounds.end - size / 2.0).max(lo))
	_bar = Rect2(center - size / 2.0, size)
	_bar_items.clear()
	var y := _bar.position.y + pad * 0.3
	for row in rows:
		var w := -gap
		for c in row:
			w += float(c[2]) + gap * (1.5 if c[0] == "slider" else 1.0)
		var x := _bar.position.x + (size.x - w) / 2.0
		var cy := y + row_h / 2.0
		for c in row:
			var cwid := float(c[2])
			var hgt := bh if c[0] == "button" else (fs * 0.5 if c[0] == "slider" else float(fs))
			_bar_items.append({"type": c[0], "id": c[1], "text": c[3], "rect": Rect2(x, cy - hgt / 2.0, cwid, hgt)})
			x += cwid + gap * (1.5 if c[0] == "slider" else 1.0)
		y += row_h


## 编辑层: 窗口变暗 + 可用区域虚线框, 每个键的虚线边界 (拖着的那个亮色实线), 工具条
func _paint_edit(cv: Node2D) -> void:
	var font := _font()
	var line := maxf(1.5, _bar_fs * 0.1)
	cv.draw_rect(_area.grow(-line), Color(CREAM, 0.45), false, line)
	var held := {}
	for d in _edit_drag.values():
		if d.get("what") == "key":
			held[int(d["kind"])] = true
	var rings: Array = [[STICK, _stick_c, _stick_r]]
	for k in _keys:
		rings.append([int(k["kind"]), k["c"], float(k["r"])])
	for rg in rings:
		var c: Vector2 = rg[1]
		var r: float = float(rg[2]) * HIT_SCALE
		if held.has(int(rg[0])):
			cv.draw_arc(c, r, 0.0, TAU, 64, Color(GOLD, 1.0), line * 1.6, true)
		else:
			_dashed_circle(cv, c, r, Color(CREAM, 0.85), line)
	# 工具条
	cv.draw_rect(_bar, Color(DARK, 0.82))
	cv.draw_rect(_bar, Color(GOLD, 0.7), false, line)
	var fs := _bar_fs
	for it in _bar_items:
		var r: Rect2 = it["rect"]
		match String(it["type"]):
			"text":
				_bar_text(cv, font, String(it["text"]), Vector2(r.position.x, r.get_center().y), fs, CREAM)
			"slider":
				var rng := _slider_range(String(it["id"]))
				var t := clampf((float(_cfg[it["id"]]) - rng.x) / (rng.y - rng.x), 0.0, 1.0)
				var y := r.get_center().y
				var kx := r.position.x + r.size.x * t
				cv.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(CREAM, 0.55), r.size.y, true)
				cv.draw_line(Vector2(r.position.x, y), Vector2(kx, y), Color(GOLD, 0.95), r.size.y, true)
				cv.draw_circle(Vector2(kx, y), fs * 0.55, CREAM)
				cv.draw_arc(Vector2(kx, y), fs * 0.55, 0.0, TAU, 24, Color(GOLD, 1.0), line, true)
			"button":
				var down := false
				for d in _edit_drag.values():
					down = down or (d.get("what") == "button" and d.get("id") == it["id"])
				cv.draw_rect(r, Color(0.30, 0.20, 0.10, 0.95) if down else Color(0.16, 0.10, 0.06, 0.92))
				cv.draw_rect(r, Color(GOLD, 1.0 if down else 0.8), false, line)
				var w := font.get_string_size(String(it["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				_bar_text(cv, font, String(it["text"]), Vector2(r.get_center().x - w / 2.0, r.get_center().y), fs, CREAM)


## 一行字: 左端 x、竖直中线 y 在 p
func _bar_text(cv: Node2D, font: Font, text: String, p: Vector2, size: int, col: Color) -> void:
	var pos := Vector2(p.x, p.y + size * 0.34)
	cv.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 6), Color(DARK, 0.9))
	cv.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## 虚线圆 (键的边界): 每段弧长约 3 倍线宽, 空一样长
static func _dashed_circle(cv: Node2D, c: Vector2, r: float, col: Color, width: float) -> void:
	var n := clampi(int(TAU * r / (width * 6.0)), 8, 64)
	for i in n:
		var a := TAU * i / n
		cv.draw_arc(c, r, a, a + TAU / n * 0.5, 6, col, width, true)

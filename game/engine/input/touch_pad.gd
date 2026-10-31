# SPDX-License-Identifier: GPL-3.0-only
extends CanvasLayer
## 手机虚拟键 (只在 Android/iOS 或 --touch 时由 InputRouter 创建并显示; 桌面永不显示)。手游式操作盘 (参考王者荣耀一类的 HUD):
##   左下: 圆形摇杆 (底盘 + 随手指的圆钮, 取主方向四向; 方向键语义同键盘, 按住连发由 InputRouter 处理)
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

## 开关钮的动作 (不是 UiAction): 切换显示
const TOGGLE := -100
## 设置钮的动作 (不是 UiAction): 打开设定面板 (桌面是 F10; 触屏没有键盘, 分辨率/简繁体/画质等只能从这里进), 操作盘隐藏时也能点
const SETTINGS := -102
## 加速钮的动作 (不是 UiAction): 弹出加速档位菜单 (手机没有键盘, 游戏速度原来只能在设定面板里调), 和设置钮一样操作盘隐藏时也能点
const SPEED := -103
## 摇杆的「键」(命中摇杆底盘): 不是 UiAction, 方向由 stick_dir 给
const STICK := -101

## 缺省不显示整套键 (2026-10-07 用户觉得虚拟键不好用: 点位置/点图标/长按/点菜单外已能操作); 隐藏时只剩「显」与「设置」两个小钮
const DEFAULT_SHOWN := false
const ALPHA := 0.9
const IDLE_ALPHA := 0.38
const IDLE_SEC := 3.0
const FADE := 0.25

## 各部件尺寸 (占画面高度的比例)
const MARGIN := 0.045           # 距屏幕边 (桌面 --touch)
const EDGE := 0.10              # 手机上距屏幕边更远: 曲面屏边缘防误触 / 系统返回手势会吞掉贴边的触摸 (魅族 20 Pro 上设置钮、摇杆按不出来)
const STICK_R := 0.155          # 摇杆底盘半径
const KNOB_RATIO := 0.42        # 圆钮半径 / 底盘半径
const KNOB_TRAVEL := 0.55       # 圆钮最大偏移 / 底盘半径
const DEAD := 0.28              # 死区 / 底盘半径
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

var shown := DEFAULT_SHOWN   # 整套键是否显示; 缺省隐藏, 靠点按/手势操作, 要用点「显」
var _pad: Node2D
var _keys: Array = []          # [{kind, c: 视口坐标中心, r: 半径}] (_layout 算)
var _pressed := {}             # 键 -> 是否按着
var _stick_c := Vector2.ZERO
var _stick_r := 0.0
var _knob := Vector2.ZERO      # 圆钮相对底盘中心的偏移
var _stick_dir := UiAction.NONE
var _fast := false             # 上次画加速钮时是否在加速 (变了就重画)
var _idle := 0.0
var _tw: Tween


## 画布: 本节点自己不画, 交给这个 Node2D 的 _draw
class _Paint:
	extends Node2D
	var owner_pad

	func _draw() -> void:
		owner_pad._paint(self)


func _init() -> void:
	layer = 110
	_pad = _Paint.new()
	_pad.owner_pad = self
	add_child(_pad)
	_pad.modulate.a = ALPHA if shown else IDLE_ALPHA


func _ready() -> void:
	_layout()
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_layout):
		vp.size_changed.connect(_layout)
	if not ScreenLayout.changed.is_connected(_layout):
		ScreenLayout.changed.connect(_layout)


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
	var m := (EDGE if Platform.is_mobile() else MARGIN) * h
	var left: float = bounds.position.x + float(ins[0]) + m
	var right: float = bounds.end.x - float(ins[2]) - m
	var bottom: float = bounds.end.y - float(ins[3]) - m
	_keys.clear()
	# 摇杆
	_stick_r = STICK_R * h
	_stick_c = Vector2(left + _stick_r, bottom - _stick_r)
	# 确认 / 取消: 两个一样大的圆键 (确认在右下角, 取消在它正左)
	var rb := BTN_R * h
	var a_c := Vector2(right - rb, bottom - rb)
	_keys.append({"kind": UiAction.CONFIRM, "c": a_c, "r": rb})
	var d := rb * 2.0 + GAP * h
	_keys.append({"kind": UiAction.CANCEL, "c": a_c + Vector2(-d, 0.0), "r": rb})
	# 右上角两个小钮 (大小一样, 都按「显」钮的半径): 最右「显/隐」, 左边「设置」; 不占摇杆和确认键的拇指区, 操作盘隐藏时仍在
	var rt := TOGGLE_R * h
	var top: float = bounds.position.y + float(ins[1]) + m
	var tc := Vector2(right - rt, top + rt)
	_keys.append({"kind": TOGGLE, "c": tc, "r": rt})
	var step := Vector2(rt * 2.0 + GAP * h, 0.0)
	_keys.append({"kind": SETTINGS, "c": tc - step, "r": rt})
	_keys.append({"kind": SPEED, "c": tc - step * 2.0, "r": rt})   # 加速钮放在设置钮左边
	_pad.queue_redraw()


## 键列表 (测试与调试用): [{kind, c, r}]
func keys() -> Array:
	return _keys


# ---------------------------------------------------------------- 外观

func _paint(cv: Node2D) -> void:
	var font := Assets.font(true)
	if shown:
		_paint_stick(cv)
	for k in _keys:
		var kind: int = k["kind"]
		if not shown and not _always(kind):
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
	if not visible or not shown:
		return
	_idle += delta
	if _idle >= IDLE_SEC and _idle - delta < IDLE_SEC:
		_set_alpha(IDLE_ALPHA, true)


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
	if _pad.modulate.a < ALPHA - 0.01 and shown:
		_set_alpha(ALPHA, true)


## 显示/隐藏整套键 (隐藏后只剩开关钮)
func toggle() -> void:
	shown = not shown
	_idle = 0.0
	_set_alpha(ALPHA if shown else IDLE_ALPHA, true)
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


## 手指在 p: 更新圆钮并返回摇杆当前方向 (UiAction.UP/DOWN/LEFT/RIGHT, 在死区内为 NONE)。取主方向, 斜着推时带一点粘滞 (换方向要多推 25%)
func stick_dir(p: Vector2) -> int:
	var v := p - _stick_c
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


## 手指离开摇杆: 圆钮回中
func stick_release() -> void:
	_knob = Vector2.ZERO
	_stick_dir = UiAction.NONE
	_pressed[STICK] = false
	_pad.queue_redraw()

# SPDX-License-Identifier: GPL-3.0-only
extends Node
## 屏幕布局服务 (autoload "ScreenLayout"), 为第二版真宽屏「扩展视野」准备的锚点界面基础。见 docs/架构设计.md「锚点界面」。
##
## 概念:
##   逻辑画面 size: 视口可见大小 / Assets.SCALE。第一版 stretch aspect=keep, 恒为 320x200;
##     aspect=expand 时随窗口比例加宽/加高 (16:9 → 356x200, 4:3 → 320x240)。
##   安全区 safe_rect: 原版 320x200 画面, 在逻辑画面里居中。
##   锚点 Anchor: 原版坐标以安全区为基准, 按锚点贴到对应屏幕边。
##     例: 原版 (24,20) 的营地菜单用 TOP_LEFT → 仍在 (24,20); 对话框用 BOTTOM → 水平居中、贴底。
##     STRETCH 为全屏拉伸 (黑幕、淡入淡出), 位置 0、大小 = 整个逻辑画面。
##   offset(anchor) = 该锚点下「原版坐标 → 画面坐标」的平移量 (逻辑像素, 已按物理像素取整)。
##
## 接入方式 (都会在视口大小变化时自动重新定位, 并给节点打 meta "ui_anchor" 供嵌套的锚点节点求相对偏移):
##   UiLayer.add(node, anchor)        放大根节点下的组件, 外包一层锚点节点 (默认取 node.ui_anchor, 没有就 CENTER)
##   wrap(node, anchor) / anchor_node(anchor)  放大 (×SCALE) 坐标系下包一层锚点节点 (ui_anchor.gd);
##                                    可嵌套 (自动扣掉外层锚点的偏移)
##   bind_layer(canvas_layer, anchor) 自带 CanvasLayer 的界面 (文字 Label 用 1280x800 像素坐标): 设 layer.offset
##   bind_node(node, anchor)          挂在屏幕原点的场景根 (Node2D/Control, 屏幕像素坐标): 设 position
##   cover(control)                   让 ColorRect 等铺满整个屏幕 (STRETCH)
##
## 画面比例 (设定「画面比例」, aspect_mode): "auto" 自适应 (缺省) = 窗口/全屏宽于 16:10 时逻辑画面横向加宽 (16:9 → 356x200, 21:9 → 约 467x200),
##   窄于 16:10 (4:3 等) 退化为上下留黑边 (画面仍 320x200); "keep" 原版 16:10, 任何窗口比例都留黑边。靠切换根窗口 content_scale_aspect 实现 (EXPAND / KEEP)。
## 调试: 启动参数 --aspect=16:9 | 4:3 | 21:9 (或任意 W:H) 按比例设窗口 (宽于 16:10 时高 800、加宽; 窄于 16:10 时宽 1280、加高),
##   用来预览; 画面是否加宽由 aspect_mode 决定。--aspect-mode=keep|auto 临时指定画面比例模式 (见 Game)。

signal changed

const AnchorNode := preload("res://engine/ui/ui_anchor.gd")

enum Anchor { TOP_LEFT, TOP, TOP_RIGHT, LEFT, CENTER, RIGHT, BOTTOM_LEFT, BOTTOM, BOTTOM_RIGHT, STRETCH }

## 安全区居中 (默认锚点)
const SAFE := Anchor.CENTER
const ORIGINAL := Vector2(320, 200)
const NAMES := ["左上", "上中", "右上", "左中", "中", "右中", "左下", "下中", "右下", "全屏拉伸"]

## 逻辑画面大小 (原版像素)
var size := ORIGINAL
## 原版 320x200 安全区 (逻辑画面里居中)
var safe_rect := Rect2(Vector2.ZERO, ORIGINAL)
## 调试用画面比例 (--aspect), 0 = 不改窗口大小
var aspect := 0.0
## 画面比例模式: "auto" 自适应 / "keep" 原版 16:10 (设定 aspect, 见 Game.apply_settings)
var aspect_mode := "auto"

## 最小窗口 (非全屏时不能拖得更小): 1280x800 = 4 倍显示倍数, 恰好用 hd4x (docs/分辨率增强.md「最小分辨率」)
const MIN_WINDOW := Vector2i(1280, 800)


## 桌面 (Windows / Linux / macOS) 窗口与任务栏图标: 用自制的 icon_pc.png。project.godot 的 config/icon 是手游美术图标 (app_icon.png),
## Godot 会拿它当窗口图标, 所以桌面启动时换回 icon_pc.png (2026-10-31 玩家: PC 版图标不该跟着手游图标变)
const DESKTOP_ICON := "res://assets/icon_pc.png"


static func desktop_icon_image() -> Image:
	var t = load(DESKTOP_ICON)
	if not (t is Texture2D):
		return null
	var img: Image = (t as Texture2D).get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Platform.is_mobile():
		var icon := desktop_icon_image()
		if icon != null:
			DisplayServer.set_icon(icon)
	if DebugArgs.current().aspect > 0:   # --aspect=W:H
		aspect = DebugArgs.current().aspect
	var win := get_window()
	win.min_size = MIN_WINDOW
	if aspect > 0:
		_apply_aspect()
	get_viewport().size_changed.connect(_update)
	win.size_changed.connect(_refresh_content_aspect)
	_refresh_content_aspect()
	add_child(load("res://engine/ui/margin_backdrop.gd").new())  # 宽屏留边的装饰底


func _apply_aspect() -> void:
	var win := get_window()
	var s := window_size_for(Vector2i(ORIGINAL * Assets.SCALE))
	win.size = s
	print("ScreenLayout: --aspect 预览, 窗口 %dx%d" % [s.x, s.y])


## 画面比例模式 (设定「画面比例」): 即时生效
func set_aspect_mode(mode: String) -> void:
	if mode == aspect_mode:
		return
	aspect_mode = mode
	_refresh_content_aspect()


## 逻辑画面是否随窗口加宽: 自适应且窗口比 16:10 宽 (窄的退化为留上下黑边, 不加高)
static func widens(win: Vector2i, mode: String) -> bool:
	return mode == "auto" and win.x * 10 > win.y * 16


func _refresh_content_aspect() -> void:
	var win := get_window()
	var want := Window.CONTENT_SCALE_ASPECT_EXPAND if widens(win.size, aspect_mode) else Window.CONTENT_SCALE_ASPECT_KEEP
	if win.content_scale_aspect != want:
		win.content_scale_aspect = want
	_update()


# ---------------------------------------------------------------- 窗口 / 显示倍数 (单一来源)
# 窗口大小、全屏、鼠标坐标换算都经过根窗口 (Window 节点): 设置窗口只能用 Window.size / Window.mode,
# 直接调 DisplayServer.window_set_size 会让 Window 节点保留旧尺寸, stretch 变换 (画面缩放、黑边、鼠标命中) 跟着错。

## 16:10 基准窗口 (像素, 某档窗口大小) 按当前画面比例 (--aspect) 换算: 比 16:10 宽则高不变加宽, 窄则宽不变加高;
## 取整到原版像素的整数倍, 逻辑画面才是整数。没有 --aspect 时原样返回
func window_size_for(base: Vector2i) -> Vector2i:
	var s := base
	if aspect > 0.0:
		var q := maxi(base.x / int(ORIGINAL.x), 1)  # 一个原版像素占多少窗口像素
		if aspect >= float(base.x) / base.y:
			s.x = int(round(base.y * aspect / q)) * q
		else:
			s.y = int(round(base.x / aspect / q)) * q
	return Vector2i(maxi(s.x, MIN_WINDOW.x), maxi(s.y, MIN_WINDOW.y))


## 窗口放不下可用屏幕区域时等比缩小 (保持画面比例), 否则原样
static func fit_size(sz: Vector2i, usable: Vector2i) -> Vector2i:
	if usable.x <= 0 or usable.y <= 0 or (sz.x <= usable.x and sz.y <= usable.y):
		return sz
	var k := minf(float(usable.x) / sz.x, float(usable.y) / sz.y)
	return Vector2i(maxi(int(floor(sz.x * k)), 1), maxi(int(floor(sz.y * k)), 1))


## 窗口左上角: 在可用区域 usable 里居中 (放不下时贴左上, 标题栏不出屏)
static func center_pos(sz: Vector2i, usable: Rect2i) -> Vector2i:
	return usable.position + Vector2i(maxi((usable.size.x - sz.x) / 2, 0), maxi((usable.size.y - sz.y) / 2, 0))


## 显示倍数: 窗口里 1 个原版像素占多少物理像素。canvas_items 的缩放系数 = min(窗口宽 / 视口宽, 窗口高 / 视口高) (keep / expand 都是),
## 视口基准 1280x800 (= 320x200 x SCALE)。贴图倍数据此选 (Assets.tex)
static func display_mult_of(win: Vector2) -> float:
	var base := ORIGINAL * Assets.SCALE
	return Assets.SCALE * minf(win.x / base.x, win.y / base.y)


func display_mult() -> float:
	return display_mult_of(Vector2(get_window().size))


var _win_job := 0
const WIN_SETTLE_MSEC := 800

## 设置全屏 / 窗口大小 (base 为 16:10 基准尺寸, 按 --aspect 换算; 窗口模式下夹到屏幕可用区域并居中)。无头测试没有真窗口, 跳过。
## 窗口管理器处理模式切换是异步的 (退出全屏后过一会儿会把窗口还原成进全屏前的位置/尺寸), 所以设好后按真实时间盯一小段,
## 尺寸被改走就重设 (用真实时间而不是帧数: --fixed-fps 下帧跑得比时钟快)
func apply_window(full: bool, base: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_win_job += 1
	var job := _win_job
	var win := get_window()
	if full:
		win.mode = Window.MODE_FULLSCREEN
		return
	if win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED
	if Platform.is_mobile():   # 手机的「窗口模式」只是显示系统栏: 窗口大小 / 位置归系统管, 不能设成 1280x800 (会缩在屏幕一角, 画面偏) (2026-10-31 网友反馈)
		return
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var sz := fit_size(window_size_for(base), usable.size)
	sz = Vector2i(maxi(sz.x, MIN_WINDOW.x), maxi(sz.y, MIN_WINDOW.y))  # 屏幕太小也不低于最小窗口
	var t0 := Time.get_ticks_msec()
	while job == _win_job and Time.get_ticks_msec() - t0 < WIN_SETTLE_MSEC:
		if win.mode == Window.MODE_WINDOWED and win.size != sz:
			win.size = sz
			win.position = center_pos(sz, usable)
		await get_tree().process_frame


func _update() -> void:
	var s := get_viewport().get_visible_rect().size / Assets.SCALE
	if s.is_equal_approx(size):
		return
	size = s
	safe_rect = Rect2(_snap((size - ORIGINAL) / 2.0), ORIGINAL)
	changed.emit()


## 取整到物理像素 (1/SCALE 原版像素), 保证放大后贴图仍对齐像素
static func _snap(v: Vector2) -> Vector2:
	return (v * Assets.SCALE).round() / Assets.SCALE


## 该锚点下 原版坐标 → 画面坐标 的平移 (逻辑像素)。安全区之外多出的宽高按锚点分到两边。
## keep_side_margins (触摸界面, InputRouter 设置): 左右留边留给虚拟键, 贴左/右边的界面改为贴安全区的左/右边 (横向一律居中)
func offset(anchor: int) -> Vector2:
	if anchor == Anchor.STRETCH or anchor < 0:
		return Vector2.ZERO
	var extra := size - ORIGINAL
	var hx := 1 if keep_side_margins else anchor % 3
	return _snap(Vector2(extra.x * hx, extra.y * floori(anchor / 3.0)) * 0.5)


## 触摸界面: 左右留边留给虚拟键 (见 offset)
var keep_side_margins := false:
	set(v):
		if v != keep_side_margins:
			keep_side_margins = v
			changed.emit()


## 同 offset, 单位为屏幕像素 (1280x800 坐标)
func px_offset(anchor: int) -> Vector2:
	return (offset(anchor) * Assets.SCALE).round()


## 原版坐标 → 当前画面坐标
func to_screen(p: Vector2, anchor: int = SAFE) -> Vector2:
	return p + offset(anchor)


## 当前画面坐标 → 原版坐标 (鼠标点击换算)
func to_original(p: Vector2, anchor: int = SAFE) -> Vector2:
	return p - offset(anchor)


## 全屏拉伸的缩放 (逻辑画面 / 320x200)
func stretch_scale() -> Vector2:
	return size / ORIGINAL


## 宽屏两侧镜像铺满 (不留黑边): 在 parent (场景根或界面层) 末尾加一个边缘镜像层, 把安全区里画好的画面镜像到两侧。
## 只给「只画安全区」的场景 / 界面用 (标题、营地、店内); 自己铺满全屏的场景 (战场、城镇) 与视频不用
## z: 画在哪一层 (缺省很大 = 盖在整个场景之后画, 镜像全部内容; 传 0 则只镜像在它之前加入的兄弟节点, 如整页底图)
func mirror_edges(parent: Node, z := 4000) -> void:
	var m: Control = load("res://engine/ui/edge_mirror.gd").new()
	m.z_index = z
	parent.add_child(m)


## 节点所在坐标系的锚点: 找最近的带 meta "ui_anchor" 的祖先 (不越过 CanvasLayer), 没有返回 −1 (屏幕原点)
static func frame_anchor(node: Node) -> int:
	var n := node.get_parent() if node else null
	while n:
		if n.has_meta("ui_anchor"):
			return int(n.get_meta("ui_anchor"))
		if n is CanvasLayer:  # 图层不继承父节点的变换, 到此为止
			return -1
		n = n.get_parent()
	return -1


## 新建一个锚点节点 (Node2D, 放大 SCALE 倍的坐标系下用), 子节点用原版坐标
func anchor_node(anchor: int = SAFE) -> Node2D:
	return AnchorNode.new(anchor)


## 把 node 包进一个锚点节点 (node 已有父节点时就地替换, 保持兄弟顺序), 返回锚点节点; 之后可改其 anchor 属性
func wrap(node: Node, anchor: int) -> Node2D:
	var w := anchor_node(anchor)
	var p := node.get_parent()
	if p:
		var i := node.get_index()
		p.add_child(w)  # 先加再移, 免得外层锚点节点变空被删
		p.move_child(w, i)
		p.remove_child(node)
	w.add_child(node)
	return w


## node 在树里时跟随 changed 调用 apply (进树时立即调用一次)
func track(node: Node, apply: Callable) -> void:
	var on := func() -> void:
		if not changed.is_connected(apply):
			changed.connect(apply)
		apply.call()
	var off := func() -> void:
		if changed.is_connected(apply):
			changed.disconnect(apply)
	node.tree_entered.connect(on)
	node.tree_exiting.connect(off)
	if node.is_inside_tree():
		on.call()


## 自带 CanvasLayer 的界面: 整层按锚点平移 (STRETCH 则整层缩放到全屏)
func bind_layer(layer: CanvasLayer, anchor: int) -> void:
	layer.set_meta("ui_anchor", anchor)
	track(layer, _apply_layer.bind(layer, anchor))


func _apply_layer(layer: CanvasLayer, anchor: int) -> void:
	layer.offset = px_offset(anchor)
	layer.scale = stretch_scale() if anchor == Anchor.STRETCH else Vector2.ONE


## 挂在屏幕原点的场景根 (Node2D 或 Control, 屏幕像素坐标; 子节点多为放大 SCALE 倍的原版坐标)
func bind_node(node: CanvasItem, anchor: int) -> void:
	node.set_meta("ui_anchor", anchor)
	track(node, _apply_node.bind(node, anchor))


func _apply_node(node: CanvasItem, anchor: int) -> void:
	node.set("position", px_offset(anchor))


## Control (黑幕、淡入淡出等) 铺满整个屏幕, 不论它挂在哪个坐标系下。
## margin > 0: 四边各多铺 margin 逻辑像素 —— 纯色遮罩 (黑白场、剧情红屏、压暗) 用它, 窗口 / 全屏 / 宽屏切换时 (视口尺寸的信号和内容缩放
## 的更新顺序不保证) 即使一时没重算, 或实际窗口比量到的大, 也不会露出边 (用户 2026-10-12: 宽屏全屏下剧情红屏盖不满)。
## 要按屏幕大小排版内容的 (如 EdgeMirror) 保持 margin = 0
func cover(c: Control, margin := 0.0) -> void:
	track(c, _apply_cover.bind(c, margin))


func _apply_cover(c: Control, margin := 0.0) -> void:
	var p := c.get_parent()
	var inv := Transform2D.IDENTITY
	if p is CanvasItem:
		inv = p.get_global_transform_with_canvas().affine_inverse()
	elif p is CanvasLayer:  # 直接挂在 CanvasLayer 下: 扣掉层的偏移/缩放 (bind_layer 的安全区偏移), 否则宽屏左边留一条不盖
		var l := p as CanvasLayer
		if l.has_meta("ui_anchor"):
			_apply_layer(l, int(l.get_meta("ui_anchor")))
		inv = l.get_final_transform().affine_inverse()
	var r := get_viewport().get_visible_rect().grow(margin)
	c.position = inv * r.position
	c.size = inv.basis_xform(r.size)

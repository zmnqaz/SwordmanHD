# SPDX-License-Identifier: GPL-3.0-only
class_name CampUi
extends RefCounted
## 营地界面公用: 颜色、带描边的文字、字模数字、数值条、按键名。坐标一律原版 320x200 像素 (放在 UiLayer.root 下)。
##
## 文字 (字体绘制, 参数 flags=5): 先在 (−1,0)、(+1,0) 用 0x7730 画一遍 (左右各 1 像素浅色光边), 再用主色画字形。
## 营地菜单、栏名、问句框、存读档文字都这样画。颜色均为 RGB555:
##   0x59a5 (181,107,41) 主色; 0x7730 (239,206,132) 光边; 0x6080 人名/体态物品名红色; 0x6acd 菜单禁用项; 0x64a5 选中框。
##
## 原版一个时钟周期 TICK = 40 毫秒 (timeSetEvent 周期 0x28, 窗口版)。
## 按键: 页面类都不读输入, 由 camp_scene 把输入翻译成 key(名字) 传入:
##   up down left right accept cancel tab page_up page_down space space_up
## 指针: 页面只声明命中矩形 (ui_hits / ui_select, 协议见 engine/ui/ui_hit.gd), 悬停/点按由输入层换算成选中项与上面的按键。

const TICK := 0.04
const MAIN := UiText.BROWN
const HALO := Color8(239, 206, 132)
const RED := Color8(198, 33, 0)
const DISABLED := Color8(214, 181, 107)
const BOX := Color8(206, 41, 41)
## 非焦点栏整体压暗到 14/16 (等级 14)
const DIM := Color(14.0 / 16.0, 14.0 / 16.0, 14.0 / 16.0)
## 不可选的行约 25% 不透明 (4:12 混合)
const FAINT := 0.25
## 滑入偏移 (/ 等都是 16,8,4,2,0)
const SLIDE := [16, 8, 4, 2, 0]


static func c555(v: int) -> Color:
	return UiLayout.c555(v)


## 给节点下所有贴图设同一材质 (UiPanel 的贴图在 AnimPlayer 的子节点里)
static func set_material_deep(n: Node, m: Material) -> void:
	for c in n.get_children():
		if c is Sprite2D:
			c.material = m
		set_material_deep(c, m)


## 排版宽度 (原版按字节算, 一个汉字 12 像素; 见 UiText.measure)
static func text_w(s: String) -> float:
	return UiText.measure(s, 12.0)


## 原版 printf 风格右对齐
## 列表 Q/E (page_up/page_down) 翻页: 选中项一次跳 行数-1 格 (原版 Up1/Down1, 商店/物品窗 MAX_SLOT-1 = 7, GameRPGInput.cs:482-492),
## 夹在 [0, n-1]; 顶行由各窗口的 _rebuild 按「选中项可见」调整。dir: +1 下翻, −1 上翻
static func page_jump(sel: int, n: int, rows: int, dir: int) -> int:
	return clampi(sel + dir * (rows - 1), 0, maxi(0, n - 1))


static func fmt(v: int, width: int) -> String:
	var s := str(v)
	if s.length() > width:
		return "?".repeat(width)
	return " ".repeat(width - s.length()) + s


## 带左右光边的文字 (原版 flags=5, 统一排版见 UiText)。halo=false 时为单色 (flags=0)
class Text:
	extends UiText
	var halo := true:
		set(v):
			halo = v
			flags = 5 if v else 0

	func _init(t := "", c := UiText.BROWN, pos := Vector2.ZERO, with_halo := true) -> void:
		super(t, 12.0, c, pos)
		halo = with_halo


## 数值条: 长 len、高 h; 最右 4 像素依次为 colors[3]..colors[0] 的渐变, 其余填 colors[4]
class Bar:
	extends Node2D
	var colors: Array = []
	var length := 0:
		set(v):
			length = v
			queue_redraw()
	var height := 2

	func _init(cols: Array, pos: Vector2, h: int) -> void:
		colors = cols.map(func(v): return CampUi.c555(v))
		position = pos
		height = h

	func _draw() -> void:
		if length <= 0:
			return
		var body := maxi(0, length - 4)
		draw_rect(Rect2(0, 0, body, height), colors[4])
		for k in range(body, length):
			draw_rect(Rect2(k, 0, 1, height), colors[clampi(3 - (k - body), 0, 3)])


## 1 像素空心框, (x,y)~(x+w-1,y+h-1)
class Box:
	extends Node2D
	var size := Vector2.ZERO:
		set(v):
			size = v
			queue_redraw()
	var color := CampUi.BOX

	func _draw() -> void:
		draw_rect(Rect2(0, 0, size.x, 1), color)
		draw_rect(Rect2(0, size.y - 1, size.x, 1), color)
		draw_rect(Rect2(0, 0, 1, size.y), color)
		draw_rect(Rect2(size.x - 1, 0, 1, size.y), color)


## 按 tick 数循环帧的计时器: 每 every 个 tick 前进一格, 共 n 格
class Cycle:
	extends RefCounted
	var every := 1
	var n := 1
	var phase := 0
	var _t := 0.0

	func _init(every_ticks: int, count: int) -> void:
		every = every_ticks
		n = count

	## 返回 phase 是否变了
	func step(delta: float) -> bool:
		_t += delta
		var d := CampUi.TICK * every
		if _t < d:
			return false
		while _t >= d:
			_t -= d
			phase = (phase + 1) % n
		return true

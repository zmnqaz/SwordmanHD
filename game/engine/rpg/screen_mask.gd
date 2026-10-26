# SPDX-License-Identifier: GPL-3.0-only
class_name RpgScreenMask
extends Node2D
## 城镇整屏事件动画的留边遮罩: 这类动画 (如第 7 镇客栈房间) 原版整幅铺满 320x200 画面, 画面之外没有任何东西;
## 宽屏 / 全屏时视口比 320x200 宽, 动画只摆在原版镜头位置, 两侧会露出下面的城镇地图。
## 在 window (原版画面在世界里的位置) 四周铺黑, 画在整屏动画 (z 100) 之下、其余世界内容 (主角/NPC) 之上; 动画自己超出 window 的部分照常盖在黑上。
## 16:10 下视口 = window, 遮罩画在屏外, 不影响画面。

const REACH := 4096.0   # 向外铺多远 (大于任何视口)

var window := Rect2():
	set(v):
		window = v
		queue_redraw()


func _init() -> void:
	z_index = 99
	visible = false


## window 外围的四块矩形 (左右两块带上下延伸, 上下两块只在 window 宽度内), 互不重叠
static func rects(win: Rect2, reach: float = REACH) -> Array[Rect2]:
	var tall := win.size.y + 2.0 * reach
	return [
		Rect2(win.position.x - reach, win.position.y - reach, reach, tall),
		Rect2(win.end.x, win.position.y - reach, reach, tall),
		Rect2(win.position.x, win.position.y - reach, win.size.x, reach),
		Rect2(win.position.x, win.end.y, win.size.x, reach),
	]


func _draw() -> void:
	for r in rects(window):
		draw_rect(r, Color.BLACK)

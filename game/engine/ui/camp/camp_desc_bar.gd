# SPDX-License-Identifier: GPL-3.0-only
class_name CampDescBar
extends Node2D
## 物品说明栏 CItemMessageBox (Misc/ITEM_MB 第 0 帧 300x48): 屏幕 (20,164) (缓冲区 (0x32,0xbc))。
## 文字两行, 起点 (12,5)、(12,17), 每行最多 42 字节 = 21 个汉字。整句一次显示: 设文字 (文字, 逐字) 支持逐字 (tick 每 tick 一字),
## 但全部 6 个调用点 (物品说明, 问句与提示 /) 传的都是 0, 原版从不逐字。
## 打开时自左滑入 16,8,4,2,0。确认问句 (「是否要丟棄此物品？」等) 也写在这里。
## 坐标、每行字数取布局表 camp.desc.*。
## 复刻新增: 末行在 split_x 两侧各一个点按区 (买入数量行: 数字左边 = 减, 右边 = 加; qty_hits)。

var _lines: Array[UiText] = []
var _pos := Vector2.ZERO


func _init() -> void:
	var bg := UiLayout.panel("camp.desc.panel")
	_pos = bg.position
	position = _pos
	bg.position = Vector2.ZERO
	add_child(bg)
	for k in int(UiLayout.val("camp.desc.text", "repeat", {}).get("count", 2)):
		var t := UiText.make("camp.desc.text", "", k)
		add_child(t)
		_lines.append(t)


func open() -> Tween:
	return UiSlide.run(self, _pos, Vector2.LEFT, UiSlide.camp_offsets(), true)


## s: 文字 (按每行字数折行, \n 强制换行)
func set_text(s: String) -> void:
	var ls := UiText.wrap_chars(s, int(UiLayout.text("camp.desc.text").get("wrap_chars", 21)))
	for k in _lines.size():
		_lines[k].text = ls[k] if k < ls.size() else ""


## 末行文字里前缀 prefix 之后紧跟 mid 时, mid 中点的 x (说明栏局部坐标): 字体不一定等宽, 按实际字宽量
func text_x(prefix: String, mid: String) -> float:
	return _lines[_lines.size() - 1].position.x + UiText.measure(prefix) + UiText.measure(mid) / 2.0


## 末行以 split_x 为界的两个点按区 (说明栏局部坐标, 原版像素): 左边 = left_action, 右边 = right_action (买入数量 减 / 加)
func qty_hits(split_x: float, left_action: int, right_action: int) -> Array:
	var y := _lines[_lines.size() - 1].position.y - 1.0
	var sz := Vector2(300, 48)   # ITEM_MB 第 0 帧
	for c in get_children():
		if c is UiPanel:
			sz = (c as UiPanel).size()
			break
	var w := sz.x
	var h := sz.y
	return [UiHit.area(Rect2(0, y, split_x, h - y), null, self, left_action),
		UiHit.area(Rect2(split_x, y, w - split_x, h - y), null, self, right_action)]

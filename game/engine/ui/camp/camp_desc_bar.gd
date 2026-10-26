# SPDX-License-Identifier: GPL-3.0-only
class_name CampDescBar
extends Node2D
## 物品说明栏 CItemMessageBox (Misc/ITEM_MB 第 0 帧 300x48): 屏幕 (20,164) (缓冲区 (0x32,0xbc))。
## 文字两行, 起点 (12,5)、(12,17), 每行最多 42 字节 = 21 个汉字, 逐字显示 (每 tick 一字, /)。
## 打开时自左滑入 16,8,4,2,0。确认问句 (「是否要丟棄此物品？」等) 也写在这里。
## 坐标、每行字数取布局表 camp.desc.*。

var _lines: Array[UiText] = []
var _shown := 0.0
var _total := 0
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
	return UiSlide.run(self, _pos, Vector2.LEFT, CampUi.SLIDE, true)


func set_text(s: String, typing := true) -> void:
	var ls := UiText.wrap_chars(s, int(UiLayout.text("camp.desc.text").get("wrap_chars", 21)))
	_total = 0
	for k in _lines.size():
		_lines[k].text = ls[k] if k < ls.size() else ""
		_total += _lines[k].text.length()
	_shown = 0.0 if typing else float(_total)
	_apply()


func _process(delta: float) -> void:
	if _shown < _total:
		_shown = minf(_total, _shown + delta / CampUi.TICK)
		_apply()


func _apply() -> void:
	var left := int(_shown)
	for t in _lines:
		var n := t.text.length()
		t.visible_chars = clampi(left, 0, n)
		left -= n

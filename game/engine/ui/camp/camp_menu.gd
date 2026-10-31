# SPDX-License-Identifier: GPL-3.0-only
class_name CampMenu
extends Node2D
## 营地主菜单 CCampMenu (素材 Misc/CAMP_MEN):
##   面板第 0 帧, 缓冲区坐标 (0x36,0x2c) = 屏幕 (24,20);
##   7 项文字, 每项在面板内 (15, 10+12i), flags=5 (主色 + 左右光边);
##   选中项左侧箭头: 第 1/2 帧每 4 tick 交替, 在 (3, 10+12i);
##   打开时自左滑入 16,8,4,2,0 并淡入。
## 坐标取自布局表 camp.menu.* (缺省为上面的原版值)。
## 按键: ↑/← 减 1、↓/→ 加 1, 首尾循环; 确认选中; 取消 = 准备出发 (由 camp_scene 弹问句)。

signal chosen(index: int)
signal cancelled

## 锚点: 原版贴左上角 (UiLayer.add 时读取)
var ui_anchor := ScreenLayout.Anchor.TOP_LEFT
const COUNT := 7  # 菜单项数; 各项文字取自文案表 camp.menu.item.<i> (内容包 text/ui.json), 序号含义由 camp_scene 处理

var selected := 0
var _arrow: UiPanel
var _cyc := CampUi.Cycle.new(4, 2)


var _pos := Vector2.ZERO


func _init() -> void:
	ui_anchor = UiLayout.anchor("camp.menu.panel", ScreenLayout.Anchor.TOP_LEFT)
	var bg := UiLayout.panel("camp.menu.panel")
	_pos = bg.position
	bg.position = Vector2.ZERO
	position = _pos
	add_child(bg)
	for i in COUNT:
		add_child(UiText.make("camp.menu.item", item_text(i), i))
	_arrow = UiLayout.panel("camp.menu.arrow")
	add_child(_arrow)
	_place_arrow()


static func item_text(i: int) -> String:
	return UiStrings.t("camp.menu.item.%d" % i)


func open() -> Tween:
	return UiSlide.run(self, _pos, Vector2.LEFT, CampUi.SLIDE, true)


func close() -> Tween:
	return UiSlide.run(self, _pos, Vector2.LEFT, CampUi.SLIDE, false)


func _process(delta: float) -> void:
	if _cyc.step(delta):
		_arrow.set_frame(_arrow.anim_dir, UiLayout.frame("camp.menu.arrow") + _cyc.phase)


func _place_arrow() -> void:
	_arrow.position = UiLayout.at("camp.menu.arrow", selected)


## 指针 (engine/ui/ui_hit.gd): 每项一行 (箭头 + 文字, 布局 camp.menu.hit: 面板内 (2, 9+12i) 起, 宽 = 文字宽 + size.x, 高 size.y)
func ui_hits() -> Array:
	var out: Array = []
	for i in COUNT:
		var r := UiLayout.rect("camp.menu.hit", i)
		r.size.x += CampUi.text_w(item_text(i))
		out.append(UiHit.area(r, i))
	return out


func ui_select(i) -> void:
	if i != selected:
		selected = i
		_place_arrow()


func key(k: String) -> void:
	match k:
		"up", "left":
			selected = posmod(selected - 1, COUNT)
			_place_arrow()
		"down", "right":
			selected = posmod(selected + 1, COUNT)
			_place_arrow()
		"accept":
			chosen.emit(selected)
		"cancel":
			cancelled.emit()

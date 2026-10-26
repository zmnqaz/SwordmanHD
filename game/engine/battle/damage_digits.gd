# SPDX-License-Identifier: GPL-3.0-only
class_name DamageDigits
extends Node2D
## 伤害/回复数字 (生成, 逐周期推进, 绘制): 各字计数从 0,-1,-2.. 起错开 1 周期,
## 第一个字到 16 时全部对齐到 16; 0~15 跳动 (dy 表), 16~29 每周期上移 1 并淡出; 全部到 30 结束。
## 近景 (closeup.damage.left / right) 与地图法术结果 (map.damage, 格 cx cy) 共用: 字模 Misc/Fig_misc 帧 4 红 (伤害) / 5 蓝 (回复),
## 内容「＋－〇一二三四五六七八九」, 每格 8x7。地图上的位置与时间表 = 原版 逐帧录像 (2026-10-13)。
signal done

const TICK := 0.04  ## 1 周期 = 40 ms (同 AnimPlayer / SceneShow)
const TICKS := 30   ## 一组数字从出现到消失的周期数 (第 16 周期全部对齐, 再 14 周期上移淡出)

var bounce: Array = []
var step := 8
var cell := Vector2.ZERO  # 字模格
var text := ""
var heal := false
var frame_index := 4      # Fig_misc 帧号: 4 红 | 5 蓝
var counters: Array[int] = []
var _t := 0.0
var _tex := {}


## id: 布局表 digits 条目 (中心、字模帧 "红|蓝"、步进、最多字数); vars: 位置公式里的变量 (地图数字用 cx cy = 格); 跳动表 closeup.damage.bounce
func _init(t: String, id: String, blue := false, vars := {}) -> void:
	var d := UiLayout.digits(id)
	step = int(d.get("step", 8))
	cell = UiLayout._vec(d.get("cell"), Vector2.ZERO)
	text = t.left(int(d.get("max_len", 8)))
	heal = blue
	var center := UiLayout.at(id, 0, vars)
	position = Vector2(center.x - text.length() * step / 2, center.y)
	for i in text.length():
		counters.append(-i)
	bounce = UiLayout.val("closeup.damage.bounce", "offsets", [])
	var fr: PackedStringArray = String(d.get("frame", "4|5")).split("|")
	var which := mini(1 if blue else 0, fr.size() - 1)
	frame_index = int(fr[which])
	_tex = UiPanel.frame_texture(String(d.get("anim", "")), frame_index)


## 一组数字从出现到消失的秒数 (调用方据此等它演完)
static func seconds() -> float:
	return TICKS * TICK


## 第 k 周期的 (竖向偏移, 不透明度): 未轮到 (k<0) 与已结束 (k>=30) 不画; 0~15 跳动表; 16~29 每周期上移 1, 每 2 周期淡 1/8
static func dy_alpha(k: int, bounce_table: Array) -> Vector2:
	if k < 0 or k >= TICKS:
		return Vector2(0, 0)
	if k < 16:
		return Vector2(float(bounce_table[k]) if k < bounce_table.size() else 0.0, 1.0)
	return Vector2(-(k - 15), (14 - 2 * ((k - 16) / 2)) / 16.0)


func _process(delta: float) -> void:
	_t += delta
	while _t >= TICK:
		_t -= TICK
		for i in counters.size():
			counters[i] += 1
		if counters[0] == 16:
			for i in counters.size():
				counters[i] = 16
		queue_redraw()
		if counters.all(func(c): return c >= TICKS):
			set_process(false)
			done.emit()
			return


func _draw() -> void:
	if _tex.is_empty():
		return
	var sc := float(_tex["scale"])
	var tex: Texture2D = _tex["texture"]
	texture_filter = TextureSource.filter_for(_tex["hd"])
	for i in text.length():
		var c := text[i]
		var g := 0 if c == "+" else (1 if c == "-" else int(c) + 2)
		var o := dy_alpha(counters[i], bounce)
		if o.y <= 0.0:
			continue
		draw_texture_rect_region(tex, Rect2(Vector2(step * i, o.x) + Vector2(_tex["offset"]), cell), Rect2(Vector2(cell.x * g, 0) / sc, cell / sc), Color(1, 1, 1, o.y))

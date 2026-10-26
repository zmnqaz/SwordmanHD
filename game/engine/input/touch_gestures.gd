# SPDX-License-Identifier: GPL-3.0-only
class_name TouchGestures
extends RefCounted
## 触摸手势识别 (纯逻辑, 时间由调用方传入, 便于无头测试)。产出 UiAction (source = "touch"):
##   点按 (按下到松开 < 移动阈值, 未到长按) = CONFIRM(pos)        「点哪选哪」
##   长按 LONG_PRESS 秒不动                    = INFO(pos), 松开时 INFO_UP
##   拖动 (移动超过阈值)                       = 每次移动 DRAG(pos, delta)   卷动地图/列表
##   快速横向滑动 (松开时判定)                 = 左滑 PAGE_DOWN / 右滑 PAGE_UP  翻页
##   双指点按 (第二指按下, 都没怎么动)         = CANCEL
## 坐标为视口像素 (1280x800 基准), 阈值按此设定。

const LONG_PRESS := 0.5
const MOVE_THRESHOLD := 24.0       # 视口像素 (原版 6 像素)
const SWIPE_MIN_DX := 120.0
const SWIPE_MAX_TIME := 0.35

var _down := {}            # 手指 index -> 当前坐标
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _t0 := 0.0
var _primary := -1
var _dragging := false
var _long_fired := false
var _multi := false        # 本次手势出现过第二指
var _multi_moved := false


func is_active() -> bool:
	return not _down.is_empty()


func touch_down(index: int, pos: Vector2, now: float) -> Array:
	_down[index] = pos
	if _down.size() == 1:
		_primary = index
		_start = pos
		_last = pos
		_t0 = now
		_dragging = false
		_long_fired = false
		_multi = false
		_multi_moved = false
	else:
		_multi = true
	return []


func touch_move(index: int, pos: Vector2, _now: float) -> Array:
	if not _down.has(index):
		return []
	var prev: Vector2 = _down[index]
	_down[index] = pos
	if _multi:
		if pos.distance_to(_start) > MOVE_THRESHOLD * 2:
			_multi_moved = true
		return []
	if index != _primary or _long_fired:
		return []
	if not _dragging and pos.distance_to(_start) > MOVE_THRESHOLD:
		_dragging = true
		prev = _start
	if not _dragging:
		return []
	_last = pos
	var a := UiAction.new(UiAction.DRAG, "touch", pos)
	a.delta = pos - prev
	return [a]


func touch_up(index: int, pos: Vector2, now: float) -> Array:
	if not _down.has(index):
		return []
	_down.erase(index)
	var out: Array = []
	if _multi:
		if _down.is_empty():
			if not _multi_moved:
				out.append(UiAction.new(UiAction.CANCEL, "touch"))
			_reset()
		return out
	if index != _primary:
		return out
	if _long_fired:
		out.append(UiAction.new(UiAction.INFO_UP, "touch", pos))
	elif _dragging:
		var d := pos - _start
		if now - _t0 <= SWIPE_MAX_TIME and absf(d.x) >= SWIPE_MIN_DX and absf(d.x) > 2.0 * absf(d.y):
			out.append(UiAction.new(UiAction.PAGE_DOWN if d.x < 0 else UiAction.PAGE_UP, "touch", pos))
	else:
		out.append(UiAction.new(UiAction.CONFIRM, "touch", pos))
	_reset()
	return out


## 时间推进: 长按到点发 INFO
func tick(now: float) -> Array:
	if _down.size() != 1 or _multi or _dragging or _long_fired:
		return []
	if now - _t0 >= LONG_PRESS:
		_long_fired = true
		return [UiAction.new(UiAction.INFO, "touch", _down[_primary])]
	return []


func _reset() -> void:
	_down.clear()
	_primary = -1
	_dragging = false
	_long_fired = false
	_multi = false
	_multi_moved = false

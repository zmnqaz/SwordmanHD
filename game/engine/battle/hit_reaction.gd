# SPDX-License-Identifier: GPL-3.0-only
class_name HitReaction
extends RefCounted
## 近景被打方的反应 (一侧一个), 按原版逐 tick 复刻 (差异; 静态观察 S2, 地址为 clean13 运行时):
##   命中帧 (idx, time+1):
##     - 未命中 / 格挡 (AB 系 NNNab): 姿势 0 = misc 帧 0, 每次都经 (0) 把翻转清 0 —— **一直是帧 0, 不交替**;
##     - 普通 / 会心 / 连击 (A 系 NNNa): 姿势 1 = misc 帧 1; 还在受击姿势里再被命中 (hit ≠ 4) 时翻转 [字段] → 帧 2, 再一次回帧 1;
##       新进姿势 翻转清 0;
##     - 位移: hit=1 起 3 步序列 (每 tick 一步, 合计 0, 从当前偏移重新开始), hit=2 偏移 += (6,4), hit=3 偏移 += ±(3,2) 交替, hit=4 只设姿势;
##     - 等待 [字段] = 该命中帧的 time+1 tick, 等完才走位移 (计时非 0 时不进步进器)。
##   步进器 / 归零 (每 tick, 守方不可见时不走): 3 步走完后每 tick x 向 0 靠 6、y 靠 4;
##     姿势 1 一进归零分支就回待机, 姿势 0 等偏移全 0 才回待机。
##   原版逐帧实测对照 (measured_basic.json, 001a 每对命中帧相隔 3 tick): 1 → 2 → 推开 (模板没匹配上记 −1) → 2 → 约 11 tick 回待机。

enum { IDLE = -1, GUARD = 0, HURT = 1 }

const STEPS := {false: [Vector2(-12, -8), Vector2(9, 6), Vector2(3, 2)], true: [Vector2(-9, -6), Vector2(6, 4), Vector2(3, 2)]}   # A / AB 系, 左侧 (右侧取反)
const RETURN := Vector2(6, 4)   # 归零每 tick 的步长

var left := false      # 左侧单位 (位移方向: 左侧向左上被推开, 右侧取反)
var pose := IDLE
var flip := 0
var wait := 0
var step := -1         # 3 步序列下标 (−1 = 不在序列里, 走归零)
var ab := false
var offset := Vector2.ZERO
var _alt := 0          # hit=3 的交替


func _init(is_left: bool) -> void:
	left = is_left


## misc 帧 (IDLE 时 −1 = 该回待机)
func frame() -> int:
	return -1 if pose == IDLE else pose + flip


## 命中帧: hit 1..4 (其它无反应), time = 攻击动画这一帧的 time, is_ab = 未命中 / 格挡
func hit(h: int, time: int, is_ab: bool) -> void:
	if h < 1 or h > 4:
		return
	ab = is_ab
	if is_ab:
		pose = GUARD
		flip = 0
	elif pose == HURT:
		if h != 4:
			flip = 1 - flip
	else:
		pose = HURT
		flip = 0
	var sg := -1.0 if left else 1.0
	match h:
		1:
			step = 0
		2:
			offset += RETURN * sg
		3:
			offset += Vector2(3, 2) * sg * (1.0 if _alt % 2 == 0 else -1.0)
			_alt += 1
	wait = time + 1


## 走一 tick; visible = 守方此刻是否可见 (不可见时整个不走, (a))。返回是否还在反应中
func tick(visible := true) -> bool:
	if pose == IDLE and offset == Vector2.ZERO:
		return false
	if not visible:
		return true
	if wait > 0:
		wait -= 1
		return true
	if step >= 0:
		offset += STEPS[ab][step] * (1.0 if left else -1.0)
		step += 1
		if step >= 3:
			step = -1
		return true
	if pose == HURT:
		pose = IDLE   # 姿势 1 一进归零分支就回待机
	offset.x = move_toward(offset.x, 0.0, RETURN.x)
	offset.y = move_toward(offset.y, 0.0, RETURN.y)
	if pose == GUARD and offset == Vector2.ZERO:
		pose = IDLE
	return pose != IDLE or offset != Vector2.ZERO


## 打断 (攻击动画放完 / 结算): 立即回待机、位移归零
func reset() -> void:
	pose = IDLE
	flip = 0
	wait = 0
	step = -1
	offset = Vector2.ZERO

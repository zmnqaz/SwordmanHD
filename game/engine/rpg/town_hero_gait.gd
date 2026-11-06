# SPDX-License-Identifier: GPL-3.0-only
class_name TownHeroGait
extends RefCounted
## 城镇主角走路的节拍 (原版 Windows 原生逐 tick 实测: 读主角状态 + PrintWindow 逐帧模板匹配)。
##   - 城镇主角精灵 (Rpg/Rpgman.saf) 只有站立 + 行走帧, 文件头里的起步 7 / 收步 7 帧没有数据: 城镇没有「提 / 放剑匣」。
##   - 每格 10 tick。行走帧 0 在第 0 tick, 帧 1 在第 1 tick, 帧 2 在第 3 tick, 帧 3 在第 5 tick 起停到格末 (1/2/2/5 tick)。
##   - 位置不是匀速滑过, 而是随帧分三段跳: 帧 0 / 1 / 2 / 3 时主角在格内的偏移 = 0 / 1/3 / 2/3 / 满格 (竖向 8 像素一段, 横向 10 像素一段)。
##   - 松键停下: 行走末帧再停 3 tick 才换站立; 站立每帧 2 tick (战场站立是 3 tick, 城镇不同)。
## 纯计时状态机, 不碰节点: RpgScene 每帧 advance, 取 position 与 take_frames() 去摆主角 (AnimPlayer 自己的计时只能每帧同长, 排不出 1/2/2/5)。

const TICK := 0.04
const STEP_TICKS := 10          # 一格的 tick 数
const SETTLE_TICKS := 3         # 停下后行走末帧多停几个 tick
const STAND_TICKS := 2          # 站立每帧 tick 数
const STAND_RESUME_FRAME := 4   # 走完停下后站立从段内第 4 帧接着播 (原版站立帧序走路时清零、停下后从 4 续 实测)
const EPS := 1e-6               # 累加 0.04 的浮点误差
## 「点按只走一格」的真实时间门槛 (秒): 同一次按下, 走完第一格后要按满这么久才接着走下一格 (见 may_chain)。
##   原版 1 倍速一格 0.4 秒, 到格边界还按着才连走, 所以点按 < 0.4 秒只走一格; 游戏加速 N 倍后一格只要 0.4 / N 真实秒 (3 倍 0.133),
##   手指还没抬起 (人手点按约 0.1~0.2 秒) 就到格边界了, 会多走一格。门槛按真实时间算: 1 倍速 (一格 0.4 > 门槛) 完全不起作用, 加速时点按 (< 门槛) 只走一格,
##   按住的人在第一格后多停一小会儿 (门槛 - 一格用时) 再连走, 之后每格都已超过门槛, 不再受限。
const HOLD_GATE := 0.25

var smooth := false             # 位置匀速滑动 (WalkStyle.SMOOTH); false = 随行走帧分段跳 (原版)
var n := 4                      # 行走帧数 (动作组 1 的帧数)
var position := Vector2.ZERO    # 当前该摆的位置 (advance 后读)
var carry := 0.0                # 上一格超出的时间, 带进「接着走」的下一格, 逐格节拍不随帧率累积误差
var _frame := 0                 # 已排队的行走帧序 (0..n-1)
var _queue: Array[int] = []     # 还没显示的行走帧序 (卡顿跨过多帧时逐帧显示, 带音效的帧 = 脚步声才不会漏)
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0                   # 本格已走时间
var _tail := 0.0                # >0: 停下后还要保持行走末帧的剩余时间
var _tail_dir := 0


func _init(walk_frames := 4) -> void:
	n = maxi(1, walk_frames)


## 第 tick 个 tick (0 起) 显示的行走帧序: 0, 1, 1, 2, 2, 3, 3, ... (末帧停到格末)
static func frame_at(tick: int, frames: int) -> int:
	if tick <= 0 or frames <= 1:
		return 0
	if frames > 5:   # 帧太多 (2 tick 一帧排不下一格): 平均摊到 10 tick, 末帧仍在格末前到位 (原版只有 4 帧, 此分支是为别的游戏兜底)
		return mini(frames - 1, tick * frames / STEP_TICKS)
	return mini(frames - 1, (tick + 1) / 2)


## 第 tick 个 tick 主角在本格内的位置比例 (0..1): 随行走帧分段, 帧 k 时 = k / (frames-1)
static func fraction_at(tick: int, frames: int) -> float:
	if frames <= 1:
		return clampf(float(tick) / STEP_TICKS, 0.0, 1.0)
	return float(frame_at(tick, frames)) / float(frames - 1)


## 到格边界 (或停着) 时, 按住的方向要不要接着走。
##   new_press: 这是一次新的按下 (这次按下还没起过步): 立刻走一格 (按下即走, 同原版)。
##   否则是「第一格走完了, 键还按着」: 真实按住时长 held_real 要 >= HOLD_GATE 才算按住 (点按就停)。
static func may_chain(new_press: bool, held_real: float) -> bool:
	return new_press or held_real >= HOLD_GATE


## 要起步走了 (一格开始前调用): 取消待站立, 立刻排上行走帧 0
func face_walk() -> void:
	_tail = 0.0
	_frame = 0
	_queue = [0]


## 开始走一格: 从 from 到 to; 上一格的余量带进来
func begin(from: Vector2, to: Vector2) -> void:
	_from = from
	_to = to
	_t = minf(carry, STEP_TICKS * TICK - EPS)
	carry = 0.0
	_tail = 0.0
	_apply()


## 推进 delta 秒; 走满一格返回 true (位置已在 to, 余量留在 carry)
func advance(delta: float) -> bool:
	_t += delta
	if _t >= STEP_TICKS * TICK - EPS:
		carry = maxf(0.0, _t - STEP_TICKS * TICK)
		_t = STEP_TICKS * TICK
		_apply()
		position = _to
		return true
	_apply()
	return false


func _apply() -> void:
	var tick := int(_t / TICK + EPS)
	var k := frame_at(tick, n)
	while _frame < k:
		_frame += 1
		_queue.append(_frame)
	position = _from.lerp(_to, clampf(_t / (STEP_TICKS * TICK), 0.0, 1.0) if smooth else fraction_at(tick, n))


## 取走还没显示的行走帧序 (按顺序逐个显示)
func take_frames() -> Array[int]:
	var q := _queue
	_queue = []
	return q


## 走完一段路停下: 行走末帧再保持 SETTLE_TICKS 个 tick, 然后 update_tail 返回朝向让场景换站立
func settle(d: int) -> void:
	_tail = SETTLE_TICKS * TICK
	_tail_dir = d


## 立刻站立 (被挡转向、对话转身、放置) 时取消还没到点的收尾
func cancel_tail() -> void:
	_tail = 0.0


## 每个没在走路的帧调用一次。余量只给「接着走」的下一帧用, 站着过了一帧就作废 (否则很久以后的起步会被抢跑)。
## 收尾到点返回待站立的朝向, 否则 -1
func update_tail(delta: float) -> int:
	carry = 0.0
	if _tail <= 0.0:
		return -1
	_tail -= delta
	if _tail <= EPS:
		_tail = 0.0
		return _tail_dir
	return -1

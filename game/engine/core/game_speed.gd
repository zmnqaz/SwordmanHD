# SPDX-License-Identifier: GPL-3.0-only
class_name GameSpeed
extends RefCounted
## 游戏速度 (设定「游戏速度」game_speed, 复刻新增): 整个游戏的时间流速, 1.0~5.0 倍, 设定里存 10~50 的整数 (十分之一倍, 避开浮点比较)。
## 做法: Engine.time_scale = 倍数 —— 动画 / 对白逐字 / 移动 / 计时器 / 过场淡入淡出的 delta 都按倍数放大, 游戏逻辑本来就按 delta 推进, 所以不用逐处改。
##   不变的: 音乐音效仍按原速播放 (Engine.time_scale 不管音频), 视频过场按原速。
## 录像: 录像时钟用缩放后的 delta (见 PlayLog), 加速时录的也是游戏时间, 平速回放一致; 回放时 time_scale 归回放自己管 (PlayLog.speed),
##   这里的倍数只记下, 回放结束 (PlayLog._release) 还原。默认 1.0 = 与原版一致, 回归基线不受影响。

const MIN_TENTHS := 10
const MAX_TENTHS := 50

## 当前倍数 (设定里的值 / 10)
static var factor := 1.0


## 设定值 (10~20, 越界夹住) -> 倍数, 并立即生效
static func set_tenths(v: int) -> void:
	factor = float(clampi(v, MIN_TENTHS, MAX_TENTHS)) / 10.0
	apply()


## 没在回放时把倍数交给引擎 (回放中由回放控制 time_scale)
static func apply() -> void:
	if not PlayLog.replaying():
		Engine.time_scale = factor

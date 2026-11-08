# SPDX-License-Identifier: GPL-3.0-only
class_name GameSpeed
extends RefCounted
## 游戏速度 (设定「游戏速度」game_speed, 复刻新增): 整个游戏的时间流速, 1.0~5.0 倍, 设定里存 10~50 的整数 (十分之一倍, 避开浮点比较)。
## 做法: Engine.time_scale = 倍数 —— 动画 / 对白逐字 / 移动 / 计时器 / 过场淡入淡出的 delta 都按倍数放大, 游戏逻辑本来就按 delta 推进, 所以不用逐处改。
##   不变的: 音乐音效仍按原速播放 (Engine.time_scale 不管音频); 视频过场按原速 (视频播放器的 delta 会被放大, MovieScene 每帧按倍数反向补偿);
##   剧情里的整屏过场动画 (幕间标题卡、客栈休息等) 播放期间 hold_normal 临时回到 1 倍 (用户 2026-11-08: 过场动画没必要快)。
## 录像: 录像时钟用缩放后的 delta (见 PlayLog), 加速时录的也是游戏时间, 平速回放一致; 回放时 time_scale 归回放自己管 (PlayLog.speed),
##   这里的倍数只记下, 回放结束 (PlayLog._release) 还原。默认 1.0 = 与原版一致, 回归基线不受影响。

const MIN_TENTHS := 10
const MAX_TENTHS := 50

## 当前倍数 (设定里的值 / 10)
static var factor := 1.0

## 正在播的整屏过场动画 (实例 id -> [离树回调, 隐藏回调]): 非空时按 1 倍
static var _holds := {}


## 设定值 (10~20, 越界夹住) -> 倍数, 并立即生效
static func set_tenths(v: int) -> void:
	factor = float(clampi(v, MIN_TENTHS, MAX_TENTHS)) / 10.0
	apply()


## 没在回放时把倍数交给引擎 (回放中由回放控制 time_scale); 有过场动画在播时为 1 倍
static func apply() -> void:
	if not PlayLog.replaying():
		Engine.time_scale = target()


## 不在回放时引擎该用的倍数
static func target() -> float:
	return 1.0 if not _holds.is_empty() else factor


## 过场动画 node 播放期间按原速; 播完调 release。不靠「播完」一条路: 节点离开场景树 (换场景、释放) 或被隐藏 (剧情清掉 / 跳过)
## 也自动放开, 免得动画被打断后没发 finished, 速度一直卡在 1 倍
static func hold_normal(node: Node) -> void:
	var id := node.get_instance_id()
	if _holds.has(id):
		return
	var on_exit := release.bind(node)
	var on_vis := _on_hidden.bind(node)
	_holds[id] = [on_exit, on_vis]
	node.tree_exiting.connect(on_exit)
	if node is CanvasItem:
		(node as CanvasItem).visibility_changed.connect(on_vis)
	apply()


static func release(node: Node) -> void:
	var cbs: Variant = _holds.get(node.get_instance_id())
	if cbs == null:
		return
	_holds.erase(node.get_instance_id())
	if node.tree_exiting.is_connected(cbs[0]):
		node.tree_exiting.disconnect(cbs[0])
	if node is CanvasItem and (node as CanvasItem).visibility_changed.is_connected(cbs[1]):
		(node as CanvasItem).visibility_changed.disconnect(cbs[1])
	apply()


static func _on_hidden(node: Node) -> void:
	if not (node as CanvasItem).visible:
		release(node)


## 把 _process 收到的 delta (已被 Engine.time_scale 放大) 还原成真实经过的秒数。
## 人手操作的节拍 (按住连发、点按 / 长按判定、防误触窗口、改键等待、按住转点按的判断) 用它; 演出 / 动画 / 逐字 / 移动用游戏时间 (原 delta)。
## time_scale = 0 (回放暂停) 时没有真实推进的意义, 返回 0。
static func real_delta(delta: float) -> float:
	return delta / Engine.time_scale if Engine.time_scale > 0.001 else 0.0

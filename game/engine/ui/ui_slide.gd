# SPDX-License-Identifier: GPL-3.0-only
class_name UiSlide
extends RefCounted
## 原版界面块的「滑入 + 淡入」: 每个时钟周期 (TICK) 换一档偏移, 同时混合比例 a:b 从 4:12 起每档 a+2、b-2 (满 16),
## 走完各档后不透明显示。收起时倒过来。
##   (信息条, /): 偏移 = 16,8,4,2,0, 左块向左偏、右块向右偏。
##   (法术/物品列表): 偏移 8,4,2,0, 列表从左、说明栏从右滑入 (~)。
## TODO: 原版一个时钟周期的长度未查 (暂按动画帧 0.04 秒)。

const TICK := 0.04
const BRI_OFFSETS := [16, 8, 4, 2, 0]
const LIST_OFFSETS := [8, 4, 2, 0]


## 让 node 从 base + dir*offset 滑到 base 并淡入 (opening=true), 或反向滑出并淡出后隐藏。返回 Tween (可 await finished)。
static func run(node: Node2D, base: Vector2, dir: Vector2, offsets: Array, opening := true) -> Tween:
	var steps: Array = []
	for k in offsets.size():
		steps.append([float(offsets[k]), (4.0 + 2.0 * k) / 16.0])
	if not opening:
		steps.reverse()
	cancel(node)  # 同节点重入: 旧 tween 未走完会继续改位置/透明度并把 visible 拉回 (如选目标后立刻确认攻击, hide_info 被滑入覆盖, 死单位的信息条一直挂着)
	var tw := node.create_tween()
	node.set_meta(TWEEN_META, tw)
	node.visible = true
	_apply(node, base, dir, steps[0])
	for k in range(1, steps.size()):
		tw.tween_interval(TICK)
		tw.tween_callback(_apply.bind(node, base, dir, steps[k]))
	tw.tween_interval(TICK)
	tw.tween_callback(_finish.bind(node, base, opening))
	return tw


const TWEEN_META := "ui_slide_tween"


## 取消该节点进行中的滑动。不直接 kill: 有的调用方 await 旧 tween 的 finished (list_menu.close),
## kill 不发 finished 会把人家吊死 —— 改为推演到终点, finished 照常发出, 节点先停到旧动画终点再由新动画接管。
static func cancel(node: Node2D) -> void:
	if node.has_meta(TWEEN_META):
		var tw: Tween = node.get_meta(TWEEN_META)
		if tw != null and tw.is_valid():
			tw.custom_step(999.0)
		node.remove_meta(TWEEN_META)


static func is_sliding(node: Node2D) -> bool:
	return node.has_meta(TWEEN_META) and (node.get_meta(TWEEN_META) as Tween) != null \
			and (node.get_meta(TWEEN_META) as Tween).is_valid()


static func _finish(node: Node2D, base: Vector2, opening: bool) -> void:
	node.position = base
	node.modulate.a = 1.0
	node.visible = opening


static func _apply(node: Node2D, base: Vector2, dir: Vector2, step: Array) -> void:
	node.position = base + dir * float(step[0])
	node.modulate.a = float(step[1])

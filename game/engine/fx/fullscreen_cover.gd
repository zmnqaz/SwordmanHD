# SPDX-License-Identifier: GPL-3.0-only
class_name FullscreenCover
extends RefCounted
## 满屏演出动画在宽屏 / 全屏下的黑边: 原版演出帧 (剧情动画、满屏红色大招等) 按 320x200 整屏画, 窗口比 16:10 宽 / 高时
## (全屏、16:9、21:9) 画面外面会露出地图。动画一播就在它的 320x200 屏幕框外面盖一圈黑色 (四块大矩形, 挂在动画节点下、画在动画帧之下),
## 框里仍是动画自己的像素 (半透明帧不会被黑底压暗), 动画播完随节点释放。
## 判断「满屏」: 动画某帧不透明外框 ≥ 300x180 (原版屏幕 320x200 的 94% / 90%); 小动画 (法术光效、单位动作) 不加。

const SCREEN := Vector2(320, 200)
const FULL_MIN := Vector2(300, 180)
const BIG := 8192.0
const CHECKS := 4   # 名义满屏的帧里最多量几帧不透明外框

static var _cache := {}   # 动画目录 -> 是否满屏


## 动画 a (AnimPlayer, 已 play / show_frame 过, data 已载入) 是否有满屏帧, 结果按目录缓存。
## 先用部件的名义外框 (数据里的偏移 + 贴图宽高, 很便宜) 筛出可能满屏的帧, 再对最多 CHECKS 帧量不透明外框 (UiPanel.frame_rect, 要扫贴图)
static func is_fullscreen(a) -> bool:
	var k: String = String(a.dir).to_lower()
	if _cache.has(k):
		return _cache[k]
	var yes := false
	if not a.data.is_empty():
		var cands: Array = []
		var frames: Array = a.data["frames"]
		for f in frames.size():
			var x0 := 1e9
			var y0 := 1e9
			var x1 := -1e9
			var y1 := -1e9
			for p in frames[f]["parts"]:
				if p["tex"] == null:
					continue
				var t: Dictionary = a.data["textures"][int(p["tex"])]
				x0 = minf(x0, float(p["x"]))
				y0 = minf(y0, float(p["y"]))
				x1 = maxf(x1, float(p["x"]) + float(t.get("w", 0)))
				y1 = maxf(y1, float(p["y"]) + float(t.get("h", 0)))
			if x1 - x0 >= FULL_MIN.x and y1 - y0 >= FULL_MIN.y:
				cands.append(f)
		for i in mini(CHECKS, cands.size()):
			var f: int = cands[i * (cands.size() - 1) / maxi(1, mini(CHECKS, cands.size()) - 1)] if cands.size() > 1 else cands[0]
			var r := UiPanel.frame_rect(a.dir, f)
			if r.size.x >= FULL_MIN.x and r.size.y >= FULL_MIN.y:
				yes = true
				break
	_cache[k] = yes
	return yes


## 给动画节点 a (帧坐标原点 = 屏幕左上角的演出动画) 加屏幕框外的黑边; 不是满屏动画什么都不做; 每个节点只加一次。返回是否加了
static func attach(a) -> bool:
	if a.has_meta("fullscreen_cover") or not is_fullscreen(a):
		return false
	a.set_meta("fullscreen_cover", true)
	for r in [Rect2(-BIG, -BIG, BIG, 2 * BIG + SCREEN.y),                      # 左
			Rect2(SCREEN.x, -BIG, BIG, 2 * BIG + SCREEN.y),                    # 右
			Rect2(0, -BIG, SCREEN.x, BIG),                                      # 上
			Rect2(0, SCREEN.y, SCREEN.x, BIG)]:                                 # 下
		var c := ColorRect.new()
		c.color = Color.BLACK
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = r.position
		c.size = r.size
		c.z_index = -1   # 画在动画帧下面 (相对动画节点)
		a.add_child(c)
	return true

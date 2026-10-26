# SPDX-License-Identifier: GPL-3.0-only
extends CanvasGroup
## 场景演出 (通用): 进出一个「画面场景」(商店店面、营地背景等整屏动画背景) 的统一机制, 演出全部由内容数据配置。
## 配置 spec (内容包记录里的 show / background_show 字段, 见 docs/内容格式.md):
##   anim      动画目录 (必填)
##   base      底图帧号, 一直画在最下面; -1 / 缺省 = 没有底图
##   intro     开场段 [起始帧, 帧数], 进场时播一次; 缺省 = 没有开场
##   loop      待机段 [起始帧, 帧数], 开场之后循环; 帧数 -1 = 到最后一帧; 缺省 = 没有待机 (停在开场最后一帧)
##   fade_in   渐入档位 (x/16 不透明, 每档 fade_tick 个时钟), 走完后不透明; 缺省 = 直接出现
##   fade_out  渐出档位, 走完后隐藏; 缺省 = 直接消失
##   fade_tick 每档的时钟数 (1 tick = 40 ms), 缺省 1
##   via_black 进出都经过黑场: 进场先把下面的画面按 fade_in 档位渐黑, 黑场停 black_hold[0] 个时钟, 再把店面从黑渐入;
##             退场先把店面渐出到黑, 停 black_hold[1] 个时钟, 再把下面的画面从黑渐入。黑幕 (整屏黑矩形) 须由调用方垫在最底下
##             (作为本节点第一个子节点, 见 ShopUI), 它与店面一起组成渐变的整体。缺省 = 画面直接叠在下面的场景上交叉渐变 (营地背景)
##   black_hold 黑场停留时钟数 [进场, 退场], 缺省 [0, 0]
## 原版实测 (40 ms 间隔录像, §商店进出时序): 城镇进店 = 城镇渐黑 7 档 x 2 tick → 黑场约 4 tick →
##   店面渐入 7 档 x 2 tick → 开场动画 120 tick → 物品窗; 退店 = 物品窗渐隐 7 tick → 店面渐黑 7 档 x 2 tick → 黑场约 6 tick → 城镇渐入 7 档 x 2 tick。
## 用法: add_child(show); await show.enter() (渐入 + 开场播完才返回, 期间调用方不接受操作); ...; await show.leave()
## 整个演出画在一个 CanvasGroup 里, 渐入渐出是把整幅画面与下面的场景混合 (原版对整个缓冲区按 x/16 混合), 不会透出底图。
## 原版依据 (商店外壳 窗口版):, 时钟, 绘制, 载入:
##   状态 1 渐入: 每 2 tick 一档, 混合比 = 2,4,...,14 (/16), 渐出倒序取; 混合区域为整个 320x200 画面; 状态 2 播开场 (动作 0, 从第 1 帧起 count[0] 帧);
##   之后打开物品窗 (CItemProcessor) 并循环待机 (从 count[0]+2 帧起 count[1] 帧); 物品窗关闭后状态 4 渐出 (同表倒序)。

signal intro_done

const TICK := 0.04

var spec: Dictionary
var _content: Node2D     # 底图 + 动画 (via_black 时单独渐入渐出)
var _base: AnimPlayer
var _anim: AnimPlayer


func _init(show_spec: Dictionary) -> void:
	spec = show_spec


## 演出时间线 (单位 tick = 40 ms; 每档 fade_tick 个 tick), 供测试与文档核对原版实测:
##   进场 = [城镇渐黑, 黑场, 店面渐入, 开场动画]; 退场 = [物品窗渐隐, 店面渐黑, 黑场, 城镇渐入]
## 开场动画 = 开场段每帧 (1 + time) tick (AnimPlayer 同式, frames = 动画的 frames 数组, 缺省 = 不算)。非 via_black 时没有「城镇渐黑/黑场」。
static func timeline(show_spec: Dictionary, frames := []) -> Dictionary:
	var step := maxi(1, int(show_spec.get("fade_tick", 1)))
	var fin: int = show_spec.get("fade_in", []).size() * step
	var fout: int = show_spec.get("fade_out", []).size() * step
	var hold: Array = show_spec.get("black_hold", [0, 0])
	var black: bool = bool(show_spec.get("via_black", false))
	var intro := 0
	var iv = show_spec.get("intro")
	if iv is Array and iv.size() == 2 and not frames.is_empty():
		for i in range(int(iv[0]), int(iv[0]) + int(iv[1])):
			intro += 1 + maxi(0, int(frames[i]["time"]))
	var ui := int(show_spec.get("ui_fade_out", []).size()) * maxi(1, int(show_spec.get("ui_fade_tick", 1)))
	return {"enter": [fin if black else 0, int(hold[0]) if black else 0, fin, intro],
		"leave": [ui, fout, int(hold[1]) if black else 0, fout if black else 0]}


## spec 是否可用 (动画存在)
static func valid(show_spec) -> bool:
	return show_spec is Dictionary and show_spec.get("anim") != null and Assets.exists(String(show_spec["anim"]) + "/anim.json")


func _ready() -> void:
	var dir := String(spec["anim"])
	_content = Node2D.new()
	add_child(_content)
	var base := int(spec.get("base", -1)) if spec.get("base") != null else -1
	if base >= 0:
		_base = AnimPlayer.new()
		_base.show_frame(dir, base)
		_content.add_child(_base)
	_anim = AnimPlayer.new()
	_content.add_child(_anim)


func via_black() -> bool:
	return bool(spec.get("via_black", false))


func _hold(i: int) -> void:
	var h = spec.get("black_hold", [0, 0])
	var n: int = int(h[i]) if h is Array and h.size() > i else 0
	if n > 0:
		await get_tree().create_timer(TICK * n).timeout


## 进场: 渐入, 同时 (原版是渐入之后) 播开场段; 都完成后返回并开始待机循环
func enter(fast := false) -> void:
	var dir := String(spec["anim"])
	var intro = spec.get("intro")
	if fast:
		_start_loop()
		self_modulate.a = 1.0
		_content.modulate.a = 1.0
		intro_done.emit()
		return
	if via_black():
		_content.visible = false
		await _fade(self, "self_modulate", spec.get("fade_in", []), true)  # 下面的画面渐黑
		await _hold(0)
		_content.visible = true
		await _fade(_content, "modulate", spec.get("fade_in", []), true)  # 店面从黑渐入
	else:
		await _fade(self, "self_modulate", spec.get("fade_in", []), true)
	if intro is Array and intro.size() == 2 and int(intro[1]) > 0:
		_anim.play(dir, int(intro[0]), int(intro[0]) + int(intro[1]), false)
		await _anim.finished
	_start_loop()
	intro_done.emit()


## 退场: 渐出后隐藏
func leave(fast := false) -> void:
	if not fast:
		if via_black():
			await _fade(_content, "modulate", spec.get("fade_out", []), false)  # 店面渐黑
			await _hold(1)
		await _fade(self, "self_modulate", spec.get("fade_out", []), false)  # 黑幕退去, 下面的画面从黑渐入 (via_black) / 交叉渐出
	visible = false


func _start_loop() -> void:
	var dir := String(spec["anim"])
	var lp = spec.get("loop")
	if lp is Array and lp.size() == 2:
		var n := int(lp[1])
		_anim.play(dir, int(lp[0]), -1 if n < 0 else int(lp[0]) + n, true)
	elif _anim.dir == "":  # 没有开场也没有待机: 只有底图
		_anim.visible = false


## 按档位表 (x/16 不透明度, 每档 fade_tick 个时钟) 改 node 的 prop (Color 属性) 的 alpha, 走完置 1 (opening) 或 0
func _fade(node: CanvasItem, prop: String, levels, opening: bool) -> void:
	var step := maxi(1, int(spec.get("fade_tick", 1)))
	var c: Color = node.get(prop)
	if levels is Array:
		for v in levels:
			c.a = float(v) / 16.0
			node.set(prop, c)
			visible = true
			await get_tree().create_timer(TICK * step).timeout
	c.a = 1.0 if opening else 0.0
	node.set(prop, c)

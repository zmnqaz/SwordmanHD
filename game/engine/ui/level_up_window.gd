# SPDX-License-Identifier: GPL-3.0-only
class_name UiLevelUp
extends Node2D
## 「位階上升」属性对比窗 (原版; 在近景或地图上, 「獲得N歷練值./位階提昇！」头像对话之后):
##   窗体整张是 Misc/Maplup 第 0 帧 (底色、边框、标题、位/体/術、五项属性图标、「+」、下方「技」栏都在贴图里),
##   原版只往上画: 每行「旧值」「新值」两串字模数字 (Maplup 第 1 帧) 与第一个新学法术名 (flags=5)。
##   窗口位置按帧外框居中 ((320-w)/2, (200-h)/2) → (114,36)。确认或取消关闭。
##   新学法术只画第一个 (flags=5 光边, 2026-10-05 实测对照); 与原版的差别 (未改): 窗口直接出现 (原版自左滑入并淡入, 布局表 levelup.window.motion 填了才滑入)。
## 坐标、帧号、格式、各行对应的属性全部在布局表 levelup.*, 这里只填数据。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal closed

var _done := false
var _win: UiPanel


## before / after: {lv, hp_max, mp_max, stats{str int avg vit luk}}; learned: 新习得法术名
func _init(before: Dictionary, after: Dictionary, learned: Array) -> void:
	_win = UiLayout.panel("levelup.window")
	add_child(_win)
	_row("levelup.lv", before.get("lv", 0), after.get("lv", 0))
	_row("levelup.hp", before.get("hp_max", 0), after.get("hp_max", 0))
	_row("levelup.mp", before.get("mp_max", 0), after.get("mp_max", 0))
	var keys: Array = UiLayout.val("levelup.stats", "keys", [])
	for i in keys.size():
		_row("levelup.stats", before.get("stats", {}).get(keys[i], 0), after.get("stats", {}).get(keys[i], 0), i)
	if not learned.is_empty():
		_win.add_child(UiText.make("levelup.skill_text", String(learned[0])))  # 原版只画第一个新学法术


## 窗体自左滑入并淡入 (初始化滑动状态, = 16,8,4,2,0, 与信息条同一套 UiSlide); 要进了场景树才能建 tween
func _ready() -> void:
	var m := _motion()
	if m.has("offsets"):
		UiSlide.run(_win, _win.position, Vector2.LEFT, m["offsets"], true)


func _motion() -> Dictionary:
	return UiLayout.motion(String(UiLayout.val("levelup.window", "motion", "")))


## 一行: 旧值、新值 (pos 写 "旧x|新x", which 0/1)
func _row(id: String, old: Variant, new: Variant, i := 0) -> void:
	_win.add_child(UiLayout.number(id, int(old), i, {"which": 0}))
	_win.add_child(UiLayout.number(id, int(new), i, {"which": 1}))


## 显示到确认/取消 (自动测试 --fast 与代打下自动关闭)
func run() -> void:
	InputRouter.push(self)
	if gc.fast or gc.autoplay:
		get_tree().create_timer(0.6 if gc.fast else 1.5).timeout.connect(_close)
	await closed
	InputRouter.pop(self)


func ui_action(a: UiAction) -> bool:
	if not a.echo and (a.is_confirm() or a.is_cancel()):
		_close()
	return true


func _close() -> void:
	if _done:
		return
	_done = true
	var m := _motion()
	if m.has("offsets") and is_inside_tree():  # 关窗倒着滑出并淡出
		await UiSlide.run(_win, _win.position, Vector2.LEFT, m["offsets"], false).finished
	closed.emit()

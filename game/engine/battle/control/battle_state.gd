# SPDX-License-Identifier: GPL-3.0-only
class_name BattleState
extends RefCounted
## 玩家操作状态机的一个状态 (一个画面 = 一个状态, docs/架构设计.md「界面状态」)。BattleInput 维护状态栈, 只有栈顶收动作。
## 两类状态:
##   光标类 (cursor_mode = true): 光标在地图上自由移动 —— 方向键 (按住连发)、鼠标悬停、触摸拖动卷图、查看 (Info) 由 BattleInput 统一处理;
##     确认 / 取消 / 菜单交给 confirm() / cancel() / on_menu()。指针: 地图格子是命中区 (BattleInput.ui_hits), 悬停 = 光标跟随, 点按 = 光标移到该格再 confirm()。
##   界面类: 菜单、列表、窗口, 动作全部交给 on_action()。菜单与列表按原版不连发 (忽略 echo)。
## 取消键的退回路径写在各状态里, 不靠全局判断。

var c  # BattleInput
var cursor_mode := false


## 入栈
func enter() -> void:
	pass


## 出栈 (清理自己的界面)
func exit() -> void:
	pass


## 上层状态出栈后回到本状态
func resume() -> void:
	pass


func confirm() -> void:
	pass


func cancel() -> void:
	pass


func on_menu() -> void:
	pass


## F2: 返回 true = 本状态处理了 (战场空闲光标态打开战场地图)
func on_f2() -> bool:
	return false


## 界面类状态的动作
func on_action(_a: UiAction) -> void:
	pass


## 指针 (engine/ui/ui_hit.gd): 界面类状态接收指针的组件, 默认是它的 menu / list (UiIconMenu / UiListMenu 自带命中矩形);
## 悬停/点按由输入层换算成选中项 + 确认, 状态本身只处理键盘语义的动作。没有组件返回 null (点按照常作为确认交给 on_action)
func pointer_target() -> Object:
	for k in ["menu", "list"]:
		var n = get(k) if k in self else null
		if n is CanvasItem and is_instance_valid(n) and n.visible:
			return n
	return null


## 方向 -> 原版图标菜单的增减: Up/Right +1, Down/Left −1
static func menu_step(a: UiAction) -> int:
	return 1 if a.kind in [UiAction.UP, UiAction.RIGHT] else -1

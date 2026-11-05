# SPDX-License-Identifier: GPL-3.0-only
class_name TouchLayoutPanel
extends CanvasLayer
## 「触屏键位置」(设定 → 控制器设置里的动作行打开; 2026-11-04 用户要求): 让虚拟键 (engine/input/touch_pad.gd) 进编辑模式,
## 每个键单独拖动, 工具条调透明度 / 大小、复位、完成; 画面和工具条都由 TouchPad 自己画, 触摸由 InputRouter 直接转给它。
## 本面板只占住输入栈 (下层界面不响应键) 并在结束后存盘: 点「完成」, 或键盘 / 手柄的确认、取消键 (安卓返回) 都算完成, 保留看到的样子
## (想回原样点「复位」)。结果经 SettingsSchema.set_value 存进 touch_layout。

var gc: GameContext
var router   # 统一输入层, 由设定面板传入; 测试可换成独立实例

signal closed(save: bool)

var _pad: Node


func open() -> bool:
	layer = 56
	_pad = router.touch_pad() if router != null and router.has_method("touch_pad") else null
	if _pad == null:
		return false
	router.push(self, true)
	_pad.begin_edit()
	var cfg: Dictionary = await _pad.edit_finished
	router.pop(self)
	SettingsSchema.set_value(gc, "touch_layout", cfg)
	closed.emit(true)
	queue_free()
	return true


func ui_action(a: UiAction) -> bool:
	if a.echo:
		return true
	if (a.is_cancel() or a.is_confirm()) and _pad != null:
		_pad.end_edit()
	return true

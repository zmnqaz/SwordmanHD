# SPDX-License-Identifier: GPL-3.0-only
class_name KeyMapPanel
extends PadMapPanel
## 键盘按键设置 (设定面板「键盘按键设置」行打开的模态子面板, 设计见 docs/设计_输入映射与战场辅助.md §7)。
## 版面与操作同手柄的 PadMapPanel (继承它, 只换动作表、取值与捕获来源): 每个逻辑动作一行 (行名 = 动作名, 值 = 当前主键),
## 之后「恢复默认」「完成」两个按钮。
##   上下选行   确认 = 开始改键 (「按下按键…」, 之后第一个可绑定的键即绑定; Esc / 5 秒无输入放弃)
##   能绑 Shift+键 (如 Shift+Tab); 方向键、Esc、F10 固定不可绑; 改绑只换主键, 原版键位等别名保留。
## 绑定只存与默认主键不同的项 (settings["key_map"], 稀疏), 每次绑定即时生效并存盘 (SettingsSchema.set_value → InputRouter.set_keys)。


func _init() -> void:
	_n = KeyMap.ACTIONS.size()


func actions() -> Array:
	return KeyMap.ACTIONS


func txt() -> String:
	return "key"


## 动作 e 当前的主键名 (改过的加 *; 同键还被别的动作用着的加 !, 提醒会一起触发)
func value_text(e: int) -> String:
	var a: String = KeyMap.ACTIONS[e]
	var ov: Dictionary = gc.settings["key_map"]
	var eff := KeyMap.effective(ov)
	var k := int(eff[a][0])
	var t := KeyMap.key_name(k)
	if ov.has(a):
		t += " *"
	if _shared(a, k):
		t += " !"
	return t


## 键 k 是否还被别的动作占着 (同键的动作会一起触发)
func _shared(a: String, k: int) -> bool:
	var names: Array = KeyMap.resolve(gc.settings["key_map"]).get(k, [])
	for n in names:
		if n != a:
			return true
	return false


func begin() -> void:
	_saved = (gc.settings["key_map"] as Dictionary).duplicate()


## 把动作 action 的主键绑到 k: 与默认主键相同则删覆盖项; 整个字典替换 (不原地改, 取消时按拷贝还原)
func bind(action: String, k: int) -> void:
	var m: Dictionary = (gc.settings["key_map"] as Dictionary).duplicate()
	if k == int(KeyMap.DEFAULTS[action][0]):
		m.erase(action)
	else:
		m[action] = k
	SettingsSchema.set_value(gc, "key_map", m)


func reset_all() -> void:
	SettingsSchema.set_value(gc, "key_map", {})


func cancel_changes() -> void:
	SettingsSchema.set_value(gc, "key_map", _saved.duplicate())


# ---------------------------------------------------------------- 改键

func start_capture(action: String) -> void:
	_capturing = action
	_cap_t = 0.0
	router.key_capture = Callable(self, "_on_captured")


func end_capture() -> void:
	_capturing = ""
	router.key_capture = Callable()


func _on_captured(k: int) -> void:
	if _capturing == "":
		return
	if not KeyMap.is_bindable(k):
		return   # 方向键 / F10 / 带 Ctrl·Alt 的组合: 不能绑, 继续等下一个键
	bind(_capturing, k)
	end_capture()
	if is_inside_tree():
		_update()

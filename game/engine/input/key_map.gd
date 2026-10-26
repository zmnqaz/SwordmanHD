# SPDX-License-Identifier: GPL-3.0-only
class_name KeyMap
extends RefCounted
## 键盘映射 (纯数据逻辑, 无节点依赖): 逻辑动作 <- 键盘按键, 与手柄的 PadMap 对称。InputRouter 按它翻译键盘事件,
## 设定面板的「键盘按键设置」(engine/ui/key_map_panel.gd) 改的也是它。设计见 docs/设计_输入映射与战场辅助.md §7。
##
## 键值 = Godot 的 keycode, 可带 Shift (KEY_MASK_SHIFT, 如 Shift+Tab); Ctrl / Alt / Meta 不参与绑定
## (Ctrl 留给「按住快进对白」)。每个动作有一串默认键: 第一个是「主键」(设定面板里显示和改绑的那个), 其余是别名 (原版键位、
## 备用键), 改绑只换主键, 别名保留, 免得把自己锁在外面。
## 方向 (↑↓←→ / WASD) 与取消键 Esc 固定, 不可改绑; F10 永远是设定的备用键 (回放锁里也靠它), 不能被别的动作占用。
## 两个动作可以共用一个键 (用户自己绑的; 如把 settings 和 map 绑到同一个键: 都触发), 各界面只接收自己用得上的动作。

## 可绑定的动作, 顺序 = 面板里的顺序 = 同键多动作时的派发顺序
const ACTIONS := ["confirm", "cancel", "info", "page_up", "page_down", "switch", "select",
	"map", "settings", "skip_dialog", "guide"]

const SHIFT := KEY_MASK_SHIFT
const CODE_MASK := KEY_CODE_MASK

## 动作 -> [主键, 别名...] (原版键位 1.1; 扩展项: WASD 之外的 Q/E、C、M、F1、F2、F3)
## 没有「游戏菜单」键: 战场空地确认 / 城镇取消本来就能开菜单, 键盘上再占一个键没用 (2026-10-25 用户去掉; 手柄 Y / 触屏「菜单」键仍走 UiAction.MENU)
const DEFAULTS := {
	"confirm": [KEY_ENTER, KEY_KP_ENTER],
	"cancel": [KEY_ESCAPE, KEY_C, KEY_BACK, KEY_DELETE],
	"info": [KEY_F],
	"page_up": [KEY_Q, KEY_PAGEUP],
	"page_down": [KEY_E, KEY_PAGEDOWN],
	"switch": [KEY_TAB],
	"select": [KEY_SPACE],
	"map": [KEY_M],
	"settings": [KEY_F1, KEY_F10],
	"skip_dialog": [KEY_F3],
	"guide": [KEY_F2, KEY_F4],
}

## 固定的方向键 (不在 DEFAULTS 里, 也不可改绑)
const DIRS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_S, KEY_A, KEY_D]
## 不可绑定的键 (不含修饰键本身): 方向键、Esc (取消, 改键时也是「放弃」)、F10 (设定面板的固定热键)
const RESERVED := [KEY_ESCAPE, KEY_F10, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_S, KEY_A, KEY_D]
const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]


## 动作 -> [键...]: 默认键, 覆盖项换掉主键 (别名保留, 与新主键重复的别名去掉)。未知动作名忽略
static func effective(overrides: Dictionary) -> Dictionary:
	var out := {}
	for a in ACTIONS:
		var keys: Array = (DEFAULTS[a] as Array).duplicate()
		if overrides.has(a):
			keys[0] = int(overrides[a])
			var seen := []
			for k in keys:
				if not (k in seen):
					seen.append(k)
			keys = seen
		out[a] = keys
	return out


## 键 -> [动作名...] (按 ACTIONS 顺序)
static func resolve(overrides: Dictionary) -> Dictionary:
	var out := {}
	var eff := effective(overrides)
	for a in ACTIONS:
		for k in eff[a]:
			if not out.has(k):
				out[k] = []
			out[k].append(a)
	return out


## 一个键盘事件在映射表里对应的动作: 先按「键 + Shift」找, 找不到再按单独的键找 (Ctrl+Enter 仍是确认, 没绑 Shift+X 时 Shift+X = X)
static func lookup(table: Dictionary, e: InputEventKey) -> Array:
	if e.shift_pressed:
		var with_shift: int = e.keycode | SHIFT
		if table.has(with_shift):
			return table[with_shift]
	return table.get(int(e.keycode), [])


## 能绑定的键: 带 Shift 或不带修饰, 单键不是方向 / Esc / F10 / 修饰键本身 / 未知键
static func is_bindable(k: int) -> bool:
	var base := k & CODE_MASK
	if k & ~(CODE_MASK | SHIFT) != 0:
		return false   # 带了 Ctrl / Alt / Meta
	return base > 0 and base != KEY_UNKNOWN and not (base in RESERVED) and not (base in MODIFIERS)


## 把设定文件里读回的值校正成稀疏覆盖项 {动作名: 键值}: 丢掉未知动作、非整数 (JSON 的 5.0 算 5)、不可绑定的键、与默认主键相同的项
static func sanitize(map) -> Dictionary:
	var out := {}
	if map is Dictionary:
		for a in map:
			if not (a is String and DEFAULTS.has(a)):
				continue
			var v = map[a]
			if not (v is int or v is float) or float(v) != floorf(float(v)):
				continue
			var k := int(v)
			if is_bindable(k) and k != int(DEFAULTS[a][0]):
				out[a] = k
	return out


## 键名 (含 Shift+), 给面板显示用
static func key_name(k: int) -> String:
	return OS.get_keycode_string(k)


## 主键名 (面板里显示的值)
static func primary_name(action: String, overrides: Dictionary) -> String:
	return key_name(int(effective(overrides)[action][0]))

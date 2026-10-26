# SPDX-License-Identifier: GPL-3.0-only
class_name PadMap
extends RefCounted
## 手柄映射 (纯数据逻辑, 无节点依赖): 逻辑动作 <- 手柄按键。预设 + 逐动作覆盖项, InputRouter 按它翻译手柄事件,
## 设定面板的「手柄按键设置」(engine/ui/pad_map_panel.gd) 改的也是它。设计见 docs/设计_输入映射与战场辅助.md §2。
##
## 键号 = Godot 的 JoyButton; 扳机是轴不是键, 用虚拟键号 TRIGGER_L / TRIGGER_R (JOY_BUTTON_MAX 起, 轴过阈值时 InputRouter 当按键处理)。
## 十字键与左摇杆方向固定为方向动作, 不可改绑。
## 两个动作可以共用一个键 (用户自己绑的; 各界面只接收自己用得上的动作, 栈顶不处理就往下传, 互不串)。

const TRIGGER_L := JOY_BUTTON_MAX
const TRIGGER_R := JOY_BUTTON_MAX + 1
const TRIGGER_ON := 0.5     # 轴值达到它算按下
const TRIGGER_OFF := 0.3    # 降到它算松开 (迟滞, 免得在阈值上抖)

## 可绑定的动作, 顺序 = 面板里的顺序 = 同键多动作时的派发顺序
const ACTIONS := ["confirm", "cancel", "info", "menu", "page_up", "page_down", "switch",
	"select", "map", "settings", "skip_dialog"]

const PRESETS := {
	"std": {
		"confirm": JOY_BUTTON_A, "cancel": JOY_BUTTON_B, "info": JOY_BUTTON_X, "menu": JOY_BUTTON_Y,
		"page_up": JOY_BUTTON_LEFT_SHOULDER, "page_down": JOY_BUTTON_RIGHT_SHOULDER,
		"switch": TRIGGER_L,
		"select": JOY_BUTTON_RIGHT_STICK, "map": JOY_BUTTON_BACK, "settings": JOY_BUTTON_START,
		"skip_dialog": JOY_BUTTON_LEFT_STICK,
	},
	# A/B 对调: 右键确认、下键取消 (任天堂手柄习惯, 也是原版重制版的布局)
	"swap": {
		"confirm": JOY_BUTTON_B, "cancel": JOY_BUTTON_A, "info": JOY_BUTTON_X, "menu": JOY_BUTTON_Y,
		"page_up": JOY_BUTTON_LEFT_SHOULDER, "page_down": JOY_BUTTON_RIGHT_SHOULDER,
		"switch": TRIGGER_L,
		"select": JOY_BUTTON_RIGHT_STICK, "map": JOY_BUTTON_BACK, "settings": JOY_BUTTON_START,
		"skip_dialog": JOY_BUTTON_LEFT_STICK,
	},
}
const DEFAULT_PRESET := "std"

const NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	TRIGGER_L: "LT", TRIGGER_R: "RT",
}
## 不可绑定的键: 十字键 (固定为方向)
const FIXED := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]


static func preset_map(preset: String) -> Dictionary:
	return (PRESETS.get(preset, PRESETS[DEFAULT_PRESET]) as Dictionary).duplicate()


## 动作 -> 键: 预设叠加覆盖项 (未知动作名忽略)
static func effective(preset: String, overrides: Dictionary) -> Dictionary:
	var m := preset_map(preset)
	for a in overrides:
		if m.has(a):
			m[a] = int(overrides[a])
	return m


## 键 -> [动作名...] (按 ACTIONS 顺序)
static func resolve(preset: String, overrides: Dictionary) -> Dictionary:
	var m := effective(preset, overrides)
	var out := {}
	for a in ACTIONS:
		var b: int = m[a]
		if not out.has(b):
			out[b] = []
		out[b].append(a)
	return out


## 能绑定的键: 0 ~ TRIGGER_R 之间且不是十字键
static func is_bindable(b: int) -> bool:
	return b >= 0 and b <= TRIGGER_R and not (b in FIXED)


## 把设定文件里读回的值校正成合法的 {preset, map}: 预设不认回退标准; 覆盖项丢掉未知动作、非整数 (JSON 的 5.0 算 5)、
## 不可绑定的键、与预设相同的项 (只存差异)
static func sanitize(preset, map) -> Dictionary:
	var p: String = preset if (preset is String and PRESETS.has(preset)) else DEFAULT_PRESET
	var out := {}
	if map is Dictionary:
		var base := preset_map(p)
		for a in map:
			if not (a is String and base.has(a)):
				continue
			var v = map[a]
			if not (v is int or v is float) or float(v) != floorf(float(v)):
				continue
			var b := int(v)
			if is_bindable(b) and b != base[a]:
				out[a] = b
	return {"preset": p, "map": out}


## 扳机轴 -> 按下/松开 (带迟滞); on = 当前是否已按下
static func trigger_on(on: bool, v: float) -> bool:
	if on:
		return v > TRIGGER_OFF
	return v >= TRIGGER_ON


## 键名: 按 Xbox 命名; joy_name (Input.get_joy_name) 是 PlayStation / Nintendo 手柄时, 面部键后附上机身上的符号 (位置相同, 名字不同)
static func button_name(b: int, joy_name := "") -> String:
	var base: String = NAMES.get(b, UiStrings.t("pad.key_n", [b]))
	var j := joy_name.to_lower()
	if j.contains("ps") or j.contains("dual") or j.contains("playstation"):
		var ps := {JOY_BUTTON_A: "×", JOY_BUTTON_B: "○", JOY_BUTTON_X: "□", JOY_BUTTON_Y: "△"}
		if ps.has(b):
			return "%s(%s)" % [base, ps[b]]
	elif j.contains("nintendo") or j.contains("switch") or j.contains("joy-con") or j.contains("pro controller"):
		var nin := {JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X"}
		if nin.has(b):
			return "%s(%s)" % [base, nin[b]]
	return base

# SPDX-License-Identifier: GPL-3.0-only
class_name UiAction
extends RefCounted
## 统一输入层的「动作」。键盘、鼠标、触摸、手柄都只产生动作,
## 界面与场景只处理动作, 不直接读按键 (见 engine/input/input_router.gd)。
##
## 原版逻辑键: 方向 ×4、确认、取消、查看 (Info)、上/下翻页 (Up1/Down1)。
## 扩展: MENU (屏幕「菜单」按钮 / M 键: 战场打开系统菜单, 城镇打开物品)、POINT (鼠标悬停: 只移动光标/选中项, 不确认)、
##       DRAG (触摸拖动: 卷动地图/列表)、SWITCH (Tab / 手柄 LT: 营地/商店双栏切换焦点)、
##       SELECT / SELECT_UP (空格按下/松开: 营地、战场物品列表按住 = 装备效果预览, 原版 GetAsyncKeyState; 其他画面等同确认)、
##       INFO_UP (查看键 / 触摸长按松开: 同一个预览的松开)。
## (2026-10-25 按用户要求删掉了原版小键盘 + / − 的「选目标跳转」TARGET_NEXT / TARGET_PREV, 空格保留。)
## 指针来源的动作带屏幕坐标 pos (视口像素, 1280x800 基准); 点按 = 确认且「点哪选哪」: 接收方先把选中项移到 pos 处再确认。

enum { NONE, UP, DOWN, LEFT, RIGHT, CONFIRM, CANCEL, INFO, MENU, PAGE_UP, PAGE_DOWN,
	POINT, DRAG, SWITCH, SELECT, SELECT_UP, INFO_UP }

const NAMES := ["none", "up", "down", "left", "right", "confirm", "cancel", "info", "menu", "page_up", "page_down",
	"point", "drag", "switch", "select", "select_up", "info_up"]
const DIRS := {UP: Vector2i(0, -1), DOWN: Vector2i(0, 1), LEFT: Vector2i(-1, 0), RIGHT: Vector2i(1, 0)}

var kind := NONE
## 按住方向键 0.5 秒后的连发 (原版 GameBattleInput.cs:150-167)。菜单、列表按原版不连发, 应忽略 echo
var echo := false
## 屏幕坐标 (视口像素); 非指针来源为 Vector2.INF
var pos := Vector2.INF
## DRAG 的位移 (视口像素)
var delta := Vector2.ZERO
## key / mouse / touch / pad / button (屏幕按钮) / test
var source := "key"
## 指针命中区的选项 index (InputRouter 按组件的命中矩形算出, engine/ui/ui_hit.gd); 没命中为 null。
## 点按命中后交给界面的动作不带坐标 (选中项已移到指针处, 界面按键盘语义处理), 但带着 hit
var hit: Variant = null


func _init(k := NONE, src := "key", p := Vector2.INF, is_echo := false) -> void:
	kind = k
	source = src
	pos = p
	echo = is_echo


static func of(k: int, src := "test", p := Vector2.INF) -> UiAction:
	return UiAction.new(k, src, p)


func is_dir() -> bool:
	return DIRS.has(kind)


## 方向 (格): 上 (0,-1) 下 (0,1) 左 (-1,0) 右 (1,0); 非方向为 0
func dir() -> Vector2i:
	return DIRS.get(kind, Vector2i.ZERO)


## 确认类: CONFIRM, 以及在不区分空格的画面里的 SELECT
func is_confirm() -> bool:
	return kind == CONFIRM or kind == SELECT


func is_cancel() -> bool:
	return kind == CANCEL


func has_pos() -> bool:
	return pos != Vector2.INF


func name() -> String:
	return NAMES[kind]


## 营地 / 商店页面的按键名 (engine/ui/camp/camp_ui.gd: up down left right accept cancel tab page_up page_down space space_up)。
## 查看键 / 触摸长按 = 按住预览 (space), 松开 = space_up。其他动作返回 ""
func camp_key() -> String:
	match kind:
		UP: return "up"
		DOWN: return "down"
		LEFT: return "left"
		RIGHT: return "right"
		CONFIRM: return "accept"
		CANCEL: return "cancel"
		SWITCH: return "tab"
		PAGE_UP: return "page_up"
		PAGE_DOWN: return "page_down"
		SELECT, INFO: return "space"
		SELECT_UP, INFO_UP: return "space_up"
	return ""


func _to_string() -> String:
	return "%s%s%s" % [name(), "(echo)" if echo else "", "@%s" % pos if has_pos() else ""]

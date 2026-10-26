# SPDX-License-Identifier: GPL-3.0-only
class_name SystemSubState
extends BattleState
## 系统菜单的子菜单, 叠在变灰的系统菜单之上:
##   存讀 (2.9, Sys_int 第 16/20/24/28 帧): 0 存档 / 1 读档 / 2 情報 / 3 结束游戏 (回标题)。
##     存档、读档、结束游戏先关两级菜单再弹确认框 (默认「是」, 文本 .MSG 第 0~8 句); 情報打开战场情报; 没有战阵存录时读档变暗。
##   設定 (声音): 音乐、音效两个开关图标 (开 36/40, 关 44/48 帧); 确认立即切换并保存设置, 关闭子菜单。
##     关 = 音量 0, 开 = 恢复关之前的音量 (没有就取设定缺省), 见 SettingsSchema.toggle_volume。
##   取消: 关子菜单, 系统菜单恢复。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

enum { SAVE_LOAD, SOUND }

var kind := SAVE_LOAD
var parent: UiIconMenu
var menu: UiIconMenu


func _init(k: int, sys_menu: UiIconMenu) -> void:
	kind = k
	parent = sys_menu


func enter() -> void:
	if kind == SAVE_LOAD:  # 存档项: 我方有人行动后变灰; 读档项: 无战阵存录时变灰
		menu = c.ui.sub_menu(parent, "sysmenu.sl_icons", [c.rules.can_save_battle(), GameSaves.has_battle_save(), true, true], 0)
	else:
		menu = c.ui.sub_menu(parent, "sysmenu.sound", [], 0, _sound_frames())


static func _sound_frames() -> Array:
	var s: Dictionary = GameContext.current().settings
	var on := [int(s["music"]) > 0, int(s["sfx"]) > 0]
	var f_on := UiIconMenu.frames_of("sysmenu.sound", "frames")
	var f_off := UiIconMenu.frames_of("sysmenu.sound", "frames_off")
	return [f_on[0] if on[0] else f_off[0], f_on[1] if on[1] else f_off[1]]


func exit() -> void:
	if is_instance_valid(menu):
		menu.queue_free()


func on_action(a: UiAction) -> void:
	if a.echo and not a.is_dir():  # 方向键按住 0.2 秒一格 (原版实测); 确认/取消不连发
		return
	if a.is_dir():
		menu.move(menu_step(a))
	elif a.is_confirm():
		var k := menu.confirm()
		if k < 0:
			return
		if kind == SOUND:
			_toggle(k)
		else:
			_save_load(k)
	elif a.is_cancel():
		c.pop()


func _toggle(k: int) -> void:
	SettingsSchema.toggle_volume(gc, ["music", "sfx"][k])
	c.pop()


## 存档/读档/情報/结束游戏: 关两级菜单后由 BattleInput 执行 (本状态已出栈, 不在这里 await)
func _save_load(k: int) -> void:
	c.system_command(k)

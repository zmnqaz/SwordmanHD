# SPDX-License-Identifier: GPL-3.0-only
class_name SaveLocationPanel
extends SettingsPanel
## 「存档位置」面板 (2026-11-06 用户要求; 存档 / 回放放哪见 UserPaths, 搬迁见 SaveRelocate):
##   设定面板「存档位置」行打开 (settings 模式), 或 Windows / Linux 导出版启动时旧位置有存档 / 选过的位置失效时由标题画面弹出 (startup 模式)。
## 继承 SettingsPanel 的框架 (压暗底、面板、行文字、说明栏), 照 ReplayPanel 只换条目。条目 (按平台 / 情形增减):
##   搬到游戏文件夹 (推荐)  —— Windows / Linux 导出版; 游戏文件夹写不进去或已经在那里则灰显 (选中时说明原因)
##   选择其它文件夹        —— 同上; 系统原生选目录对话框 (不支持时用 Godot 的 FileDialog), 选完做可写测试
##   打开存档文件夹        —— 电脑 (OS.shell_open); 手机没有文件管理器可开, 不列 (说明栏照样显示路径)
##   先不动 / 返回         —— startup: 记下当前位置 (以后不再弹); settings: 回到设定面板
## 说明栏: 选中条目的说明 / 不能用的原因 / 上一次操作的结果; 条目下方一块 (布局表 savelocation.where) 放启动时为什么弹、当前位置与备份文件夹的完整路径。
## 键盘 / 手柄: 上下选、确认执行、取消 = 先不动 / 返回; 只有选目录那一步要用鼠标。

const E_GAME := "game"
const E_PICK := "pick"
const E_OPEN := "open"
const E_KEEP := "keep"

var startup := false   # true = 启动时弹出 (发现旧存档 / 位置失效)
var _entries: Array = []
var _msg := ""          # 上一次操作的结果 (成功 / 失败原因), 显示在说明栏第一行
var _busy := false      # 正在选目录 / 搬迁: 不响应按键
var _where: UiText      # 当前位置的完整路径 (布局表 savelocation.where: 条目下方的空行区; 说明栏只有两行放不下)
var _backup := ""       # 这次搬迁旧文件的备份文件夹 (显示在 _where 里)
var _blocked := {}      # blocked() 结果缓存: 它会实际写测试文件, 不能每次刷新界面都跑 (搬迁后清空)


func total() -> int:
	return _entries.size()


func _ready() -> void:
	super._ready()
	layer = 55   # 压在设定面板 (54) 之上


## 打开并等到关闭; 返回 true = 位置变了 (或 startup 时做出了选择)
func open() -> bool:
	_entries = entries(startup)
	_n = _entries.size()
	_sel = 0
	while _sel < _n - 1 and _blk(_entries[_sel]) != "":   # 光标落在第一个能用的条目 (游戏文件夹写不进去时跳到「选择其它文件夹」)
		_sel += 1
	_body = PadMapPanel.Body.new()
	_build("savelocation.title", "savelocation.hint")
	_where = UiText.make("savelocation.where", "")
	_origin.add_child(_where)
	_update()
	router.push(self, true)
	var changed: bool = await closed
	router.pop(self)
	queue_free()
	return changed


## 条目列表 (测试用 static)
static func entries(at_startup: bool) -> Array:
	var out := []
	if UserPaths.relocatable():
		out.append(E_GAME)
		out.append(E_PICK)
	if not Platform.is_mobile():
		out.append(E_OPEN)
	out.append(E_KEEP)
	return out


## 条目能不能执行; 不能时返回原因文字键 ("" = 能)
static func blocked(e: String) -> String:
	if e == E_GAME:
		if UserPaths.mode() == "game":
			return "savelocation.game.already"
		if not UserPaths.writable(UserPaths.exe_dir()):
			return "savelocation.game.readonly"
	return ""


func _blk(e: String) -> String:
	if not _blocked.has(e):
		_blocked[e] = blocked(e)
	return _blocked[e]


## 说明栏的「发现旧存档 / 位置失效」那一句 (startup 模式开头)
static func situation_text() -> String:
	if UserPaths.problem != "":
		return UiStrings.t("savelocation.problem." + UserPaths.problem)
	var c := SaveRelocate.count(UserPaths.dirs_for(UserPaths.mode(), UserPaths.custom_path()))
	return UiStrings.t("savelocation.found") % [c.saves, c.replays]


## 搬到 (mode, path), 结果写进 _msg
func _move_to(m: String, path := "") -> void:
	var src := UserPaths.dirs_for(UserPaths.mode(), UserPaths.custom_path())
	var r := SaveRelocate.relocate(src, UserPaths.dirs_for(m, path), func(): return UserPaths.save_choice(m, path))
	_msg = result_text(r)
	_blocked.clear()
	if r.ok:
		_closed_changed = true
		_backup = String(r.backup)


## 搬迁结果 -> 给玩家看的一句
static func result_text(r: Dictionary) -> String:
	if r.ok:
		return UiStrings.t("savelocation.done") % int(r.copied) if String(r.backup) != "" else UiStrings.t("savelocation.done_nobackup")
	var code := String(r.error)
	var arg := ""
	if code.contains(":"):
		arg = code.get_slice(":", 1)
		code = code.get_slice(":", 0)
	var t := UiStrings.t("savelocation." + code)
	return t % arg if t.contains("%s") else t


var _closed_changed := false


func _pick_folder() -> void:
	_busy = true
	var start := UserPaths.shown(UserPaths.save_dir()).get_base_dir()
	var picked := ""
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var done := [false, ""]
		DisplayServer.file_dialog_show(UiStrings.t("savelocation.pick.title"), start, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(),
			func(ok: bool, paths: PackedStringArray, _f: int): done[0] = true; done[1] = paths[0] if ok and paths.size() > 0 else "")
		while not done[0] and is_inside_tree():
			await get_tree().process_frame
		picked = done[1]
	else:
		var fd := FileDialog.new()
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		fd.current_dir = start
		fd.title = UiStrings.t("savelocation.pick.title")
		get_parent().add_child(fd)
		fd.popup_centered_ratio(0.7)
		var res := [false, ""]
		fd.dir_selected.connect(func(d): res[0] = true; res[1] = d)
		fd.canceled.connect(func(): res[0] = true)
		while not res[0] and is_inside_tree():
			await get_tree().process_frame
		fd.queue_free()
		picked = res[1]
	_busy = false
	if picked == "":
		return
	if not UserPaths.writable(picked):
		_msg = UiStrings.t("savelocation.pick.readonly")
		return
	_move_to("custom", picked)


func _run(e: String) -> void:
	_msg = ""
	var why := _blk(e)
	if why != "":
		_msg = UiStrings.t(why)
		return
	match e:
		E_GAME:
			_move_to("game")
		E_PICK:
			await _pick_folder()
		E_OPEN:
			DirAccess.make_dir_recursive_absolute(UserPaths.save_dir())
			OS.shell_open(UserPaths.shown(UserPaths.save_dir()))
		E_KEEP:
			_close_keep()
			return
	if is_inside_tree():
		_update()


## 先不动 / 返回: startup 时记下当前位置 (玩家知道了, 以后不再弹)
func _close_keep() -> void:
	if startup:
		UserPaths.save_choice(UserPaths.mode(), UserPaths.custom_path())
	closed.emit(_closed_changed or startup)


func _update() -> void:
	_scroll_to_sel()
	var sel_c := UiLayout.color("settings.sel_color", Color8(255, 224, 116))
	var dim_c := UiLayout.color("settings.dim_color", Color8(170, 160, 140))
	for s in _vis:
		var e := _top + s
		var on := e < _entries.size()
		_rows[s].visible = on
		_values[s].visible = on
		_buttons[s].visible = false
		if not on:
			continue
		var key: String = _entries[e]
		_rows[s].text = UiStrings.t("savelocation.%s.label" % (key if not (key == E_KEEP and not startup) else "done"))
		_values[s].text = UiStrings.t("savelocation.game.value") if key == E_GAME and _blk(key) == "" else ""
		var c := sel_c if e == _sel else dim_c
		if _blk(key) != "":
			c = c.darkened(0.45)
		_rows[s].color = c
		_values[s].color = c
	var lines := []
	if _msg != "":
		lines.append(_msg)
	elif _sel < _entries.size():
		var key2: String = _entries[_sel]
		var b := _blk(key2)
		lines.append(UiStrings.t(b) if b != "" else UiStrings.t("savelocation.%s.desc" % (key2 if not (key2 == E_KEEP and not startup) else "done")))
	_desc.text = "\n".join(lines)
	_where.text = UiStrings.t("savelocation.current") % UserPaths.shown(UserPaths.save_dir())
	if startup and _backup == "":
		_where.text = situation_text() + "\n" + _where.text   # 启动时先说为什么弹 (发现旧存档 / 位置失效)
	if _backup != "":
		_where.text += "\n" + UiStrings.t("savelocation.backup") % _backup
	_body.queue_redraw()


func ui_hits() -> Array:
	var out: Array = []
	var rr := UiLayout.rect("settings.row", 0)
	var vr := UiLayout.rect("settings.value", 0)
	var pad := UiLayout.num("settings.hit", "pad", 4)
	for s in _vis:
		var e := _top + s
		if e >= total():
			break
		var y := UiLayout.at("settings.row", s).y - 1.0
		var x0 := rr.position.x - pad
		out.append(UiHit.area(Rect2(x0, y, vr.position.x + vr.size.x + 16.0 - x0, rr.size.y), e, _origin))
	return out


func ui_select(i) -> void:
	_sel = int(i)
	_msg = ""
	_update()


func ui_outside_action() -> int:
	return UiAction.NONE if startup else UiAction.CANCEL   # 启动时点外面不当选择


func ui_action(a: UiAction) -> bool:
	if a.echo or _busy:
		return true
	match a.kind:
		UiAction.DOWN:
			_sel = posmod(_sel + 1, total())
			_msg = ""
		UiAction.UP:
			_sel = posmod(_sel - 1, total())
			_msg = ""
		UiAction.CONFIRM, UiAction.SELECT:
			_run(_entries[_sel])
			return true
		UiAction.CANCEL, UiAction.MENU:
			_close_keep()
			return true
		_:
			return true
	_update()
	return true

# SPDX-License-Identifier: GPL-3.0-only
class_name ReplayPanel
extends SettingsPanel
## 录像回放列表 (设定面板「录像回放」行打开的模态子面板)。
## 继承 SettingsPanel: 共用框架 (压暗底、面板、行/值/按钮文字、滚动列表) 与 settings.* 布局表元素, 照 PadMapPanel 只换条目:
## 每份录像一行 (行名 = 整场游玩 / 第 N 幕, 值 = 日期时间, 都只从文件名派生, 不读文件), 之后「速度」「返回」两个按钮 (_n = 录像数)。
##   上下选录像   左右调倍速 (0.5 / 1 / 2 / 4 / 8 / 16)   确认 = 回放选中的录像   取消 / 右键 / 点面板外 / 「返回」 = 回到设定面板
##   「速度」按钮: 确认循环切换。选中某份录像时才解析它的 JSON, 底部显示时长与操作数 (结果缓存); 读不了的录像确认无效。
## 选定后 closed(true), 调用方 (SettingsPanel._activate) 读 chosen_path / chosen_speed 交给 SceneFlow.start_replay; 其余 closed(false)。

const DIR := "user://replays"

var chosen_path := ""
var chosen_speed := 1.0
var _dir := DIR
var _files: Array = []           # 文件名, 新的在前
var _info: Dictionary = {}       # 文件名 -> info_text 缓存
var _speed := 1.0


## 目录下的录像文件名 (.json), 按文件名倒序: 同类里新的在前 (时间戳在名字里)
static func list_files(dir: String = DIR) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):   # 还没录过像: 目录不存在 (get_files_at 会打印引擎错误)
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	out.reverse()
	return out


## 文件名 -> [行名, 日期时间]; 不认识的名字原样当行名
static func label_of(file_name: String) -> Array:
	var re := RegEx.create_from_string("^(play|stage_(\\d+))_(\\d{4})(\\d{2})(\\d{2})_(\\d{2})(\\d{2})\\d{2}\\.json$")
	var m := re.search(file_name)
	if m == null:
		return [file_name, ""]
	var kind := UiStrings.t("replay.kind.play") if m.get_string(1) == "play" else UiStrings.t("replay.kind.stage") % int(m.get_string(2))
	return [kind, "%s-%s-%s %s:%s" % [m.get_string(3), m.get_string(4), m.get_string(5), m.get_string(6), m.get_string(7)]]


func _init() -> void:
	_n = 0


## 扫描目录建条目 (open 时调; 测试可指定目录)
func load_files(dir: String = DIR) -> void:
	_dir = dir
	_files = list_files(dir)
	_info.clear()
	_n = _files.size()
	_sel = 0
	_top = 0


## 第 e 份录像的底部说明: 「时长 m:ss · N 个操作」, 读不了 / 版本不对是「无法读取」(解析一次后缓存)
func info_text(e: int) -> String:
	var name: String = _files[e]
	if _info.has(name):
		return _info[name]
	var js := JSON.new()   # 不用 JSON.parse_string: 坏文件会让引擎打印解析错误
	var j = js.data if js.parse(FileAccess.get_file_as_string(_dir.path_join(name))) == OK else null
	var t := UiStrings.t("replay.bad")
	if j is Dictionary and int(j.get("version", 0)) == PlayLog.VERSION:
		var evs = j.get("events", [])
		var sec := int(float(j.get("duration", 0.0)))
		t = UiStrings.t("replay.info") % ["%d:%02d" % [sec / 60, sec % 60], (evs as Array).size() if evs is Array else 0, _start_text(j)]
	_info[name] = t
	return t


## 录像的起点说明: 整场从标题开始; 读了没有录像历史的老档则从那个存档开始; 单幕录像从这一幕开战前开始
static func _start_text(j: Dictionary) -> String:
	var base = j.get("base", {})
	var kind := String(j.get("base_kind", ""))
	if j.get("kind", "") == "stage":
		return UiStrings.t("replay.start.stage") if kind in ["", "stage_start"] else UiStrings.t("replay.start.battle")
	if not (base is Dictionary) or (base as Dictionary).is_empty():
		return UiStrings.t("replay.start.full")
	return UiStrings.t("replay.start.battle") if kind == "battle" else UiStrings.t("replay.start.slot")


func _readable(e: int) -> bool:
	return info_text(e) != UiStrings.t("replay.bad")


func _cycle_speed() -> void:
	_speed = PlayLog.step_speed(_speed, 1) if _speed < PlayLog.SPEED_STEPS[-1] else PlayLog.SPEED_STEPS[0]


func _choose(e: int) -> void:
	if not _readable(e):
		return
	chosen_path = _dir.path_join(_files[e])
	chosen_speed = _speed
	closed.emit(true)


# ---------------------------------------------------------------- 界面

func _ready() -> void:
	super._ready()
	layer = 55   # 压在设定面板 (54) 之上


## 打开并等到关闭 (返回 true = 选定了录像, 见 chosen_path / chosen_speed)
func open() -> bool:
	load_files(_dir)
	_body = PadMapPanel.Body.new()   # 通用底图 (面板底、选中行光标、滚动 ▲▼), 不带设定行的音量格
	_build("replay.title", "replay.hint")
	_update()
	router.push(self, true)
	var chosen: bool = await closed
	router.pop(self)
	queue_free()
	return chosen


func _update() -> void:
	_scroll_to_sel()
	var sel_c := UiLayout.color("settings.sel_color", Color8(255, 224, 116))
	var dim_c := UiLayout.color("settings.dim_color", Color8(170, 160, 140))
	for s in _vis:
		var e := _top + s
		var is_btn := e >= _n and e < total()
		var is_row := e < _n
		_rows[s].visible = is_row
		_values[s].visible = is_row
		_buttons[s].visible = is_btn
		var c := sel_c if e == _sel else dim_c
		if is_btn:
			_buttons[s].text = (UiStrings.t("replay.button.speed") % PlayLog.speed_text(_speed)) if e == _n else UiStrings.t("replay.button.done")
			_buttons[s].color = c
		elif is_row:
			var lv := label_of(_files[e])
			_rows[s].text = lv[0]
			_values[s].text = lv[1]
			_rows[s].color = c
			_values[s].color = c
	if _n == 0:
		_desc.text = UiStrings.t("replay.empty")
	elif _sel < _n:
		_desc.text = info_text(_sel)
	else:
		_desc.text = UiStrings.t("replay.desc.speed" if _sel == _n else "replay.desc.done")
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
	_update()


func ui_outside_action() -> int:
	return UiAction.CANCEL   # 点面板外 = 返回设定面板 (没有可丢的改动)


func ui_action(a: UiAction) -> bool:
	if a.echo:
		return true
	match a.kind:
		UiAction.DOWN: _sel = posmod(_sel + 1, total())
		UiAction.UP: _sel = posmod(_sel - 1, total())
		UiAction.LEFT, UiAction.PAGE_UP: _speed = PlayLog.step_speed(_speed, -1)
		UiAction.RIGHT, UiAction.PAGE_DOWN: _speed = PlayLog.step_speed(_speed, 1)
		UiAction.CONFIRM, UiAction.SELECT:
			if _sel < _n:
				_choose(_sel)
			elif _sel == _n:
				_cycle_speed()
			else:
				closed.emit(false)
		UiAction.CANCEL: closed.emit(false)
	if is_inside_tree():
		_update()
	return true

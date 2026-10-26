# SPDX-License-Identifier: GPL-3.0-only
class_name UiIconMenu
extends Node2D
## Man_int 图标横排菜单 (行动菜单、物品子菜单、系统菜单同理可用 Sys_int)。
## 每个图标占 4 帧 (基帧 b: b..b+3 为呼吸动画); 选中项循环播放 [b, b+4), 其余显示基帧。
## 禁用项显示 disabled_frames 里给的帧 (行动菜单: 爆發 20、法術 24, 2.4), 不能被选中。
## 方向: move(+1/-1), 夹紧在两端, 不循环 (原版 Up/Right +1, Down/Left -1, 由调用方映射)。
## 按键由调用方传入: move() / confirm() / cancel(); 本组件不读输入。

signal confirmed(index: int)
signal cancelled

## 行动菜单: 爆發 法術 攻擊 物品 待機 (Man_int 第 0/4/8/12/16 帧); 禁用时爆發换第 20 帧、法術换第 24 帧。
## 战场按布局表 (actionmenu.icons 等, 见 setup_id) 取帧; 这两个常量只给展示画面/测试用
const ACTION_FRAMES := [0, 4, 8, 12, 16]
const ACTION_DISABLED := {0: 20, 1: 24}
## 物品子菜单: 使用 交給 裝備 丟棄 (第 28/32/36/40 帧)
const ITEM_FRAMES := [28, 32, 36, 40]

var anim_dir := ThemeAssets.p("ui.menu_icons")
var frames: Array = []
var disabled_frames := {}
var enabled: Array = []
var selected := 0
## 图标间距 (原版像素): setup() 按 metrics() 由素材帧算出 (Man_int = 25); 布局表 actionmenu.step 可覆盖
var step := 25.0
## 图标在本菜单里的起点 (原版第一个图标左边留 gap; 扣掉帧自带的偏移)
var origin := Vector2.ZERO
## 变灰: 物品子菜单打开时, 行动菜单 enable(false) 显示在下层。TODO: 原版变灰的画法未查, 暂按调暗。
var dimmed := false:
	set(v):
		dimmed = v
		modulate = UiLayout.color(UiLayout.val("actionmenu.dim", "color", [1, 1, 1])) if v else Color.WHITE
		_refresh()
var _icons: Array[UiPanel] = []
var _gap := 0
var _h := 0.0
## 静止帧宽 W0 (子菜单位移公式用)
var w0 := 0


## 由素材帧算排版量 (原版, 帧外框按原版 1 倍):
##   W0/H0 = 第 0 帧 (静止) 外框, W2/H2 = 第 2 帧 (呼吸最大) 外框; gap = (W2 - W0)/2;
##   菜单宽 = n*W0 + (n+1)*gap (原版写死 n = 5), 高 = H2; 第 k 个图标静止帧画在 x = gap + k*(W0+gap)。
## 返回 {step, gap, w0, h, origin}; origin = 第 0 个图标节点的位置 (扣掉第 0 帧自带的偏移, 呼吸帧靠帧偏移自己居中)
static func metrics(dir := ThemeAssets.p("ui.menu_icons")) -> Dictionary:
	var r0 := UiPanel.frame_rect(dir, 0)
	var r2 := UiPanel.frame_rect(dir, 2)
	var w0 := int(r0.size.x)
	var gap := (int(r2.size.x) - w0) / 2
	var h := int(r2.size.y)
	var oy := (h - int(r0.size.y)) / 2
	return {"step": w0 + gap, "gap": gap, "w0": w0, "h": h,
		"origin": Vector2(gap - int(r0.position.x), oy - int(r0.position.y))}


## 按布局表菜单元素建: sprite {anim, frames: 各图标基帧, disabled: {序号: 禁用帧}}; enabled 缺省全可用
func setup_id(id: String, is_enabled: Array = [], sel := -1, frames_override: Array = []) -> void:
	var sp := UiLayout.sprite(id)
	var dis := {}
	var d = sp.get("disabled", {})
	for k in (d if d is Dictionary else {}):
		dis[int(k)] = int(d[k])
	var fr: Array = frames_override if not frames_override.is_empty() else sp.get("frames", [])
	setup(fr.map(func(x): return int(x)), is_enabled, dis, sel, String(sp.get("anim", ThemeAssets.p("ui.menu_icons"))))
	set_meta("ui_layout_id", id)


## 布局表菜单元素的帧表 (sprite 下的某个键, 如 frames / sound_on)
static func frames_of(id: String, key := "frames") -> Array:
	return UiLayout.sprite(id).get(key, []).map(func(x): return int(x))


## frames: 各图标基帧; enabled: 各项是否可用 (缺省全可用); sel<0 选第一个可用项
func setup(icon_frames: Array, is_enabled: Array = [], disabled := {}, sel := -1, dir := ThemeAssets.p("ui.menu_icons")) -> void:
	anim_dir = dir
	frames = icon_frames.duplicate()
	disabled_frames = disabled
	enabled = is_enabled.duplicate() if not is_enabled.is_empty() else frames.map(func(_f): return true)
	for c in _icons:
		remove_child(c)
		c.queue_free()
	_icons.clear()
	var m := metrics(dir)
	step = float(UiLayout.val("actionmenu.step", "value", m["step"]))
	origin = m["origin"]
	_gap = m["gap"]
	_h = m["h"]
	w0 = int(m["w0"])
	for k in frames.size():
		var p := UiPanel.new()
		p.position = origin + Vector2(step * k, 0)
		add_child(p)
		_icons.append(p)
	selected = sel if sel >= 0 else 0
	_clamp_selection()
	_refresh()


## 指针 (engine/ui/ui_hit.gd): 可用的图标; 变灰 (下层菜单) 时不响应
func ui_hits() -> Array:
	var out: Array = []
	if dimmed:
		return out
	for k in frames.size():
		if enabled[k]:
			out.append(UiHit.area(Rect2(Vector2(step * k + _gap * 0.5, 0), Vector2(step, _h)), k))
	return out


func ui_select(k) -> void:
	if k != selected:
		select(k)


## 菜单总宽 (原版像素) = n*W0 + (n+1)*gap (图标 0 前、各图标间、最后一个后各留 gap)
func width() -> float:
	return step * frames.size() + _gap


## 菜单高 (第 2 帧外框高)
func height() -> float:
	return _h


## d = +1 / -1; 遇到禁用项跳过, **到头循环** (最左再按左回到最右, 反之亦然)。返回选中项是否变了 (只有一个可用项时不动)。
## 原版是夹紧不循环; 2026-10-07 用户实机反馈「按左回不到最右边」不方便, 有意改成循环
func move(d: int) -> bool:
	if d == 0 or dimmed or frames.is_empty():
		return false
	var n := frames.size()
	var k := selected
	for _i in n:
		k = posmod(k + signi(d), n)
		if enabled[k]:
			if k == selected:
				return false
			selected = k
			_refresh()
			return true
	return false


func select(k: int) -> void:
	selected = clampi(k, 0, frames.size() - 1)
	_clamp_selection()
	_refresh()


## 确认: 返回选中项并发出 confirmed (禁用项不会被选中)
func confirm() -> int:
	if dimmed or frames.is_empty() or not enabled[selected]:
		return -1
	confirmed.emit(selected)
	return selected


func cancel() -> void:
	cancelled.emit()


## 原版 select(): 选中项落在禁用项上时夹到最小可用项
func _clamp_selection() -> void:
	if frames.is_empty() or enabled[selected]:
		return
	for k in frames.size():
		if enabled[k]:
			selected = k
			return


func _refresh() -> void:
	for k in _icons.size():
		var p := _icons[k]
		var base: int = frames[k] if enabled[k] else int(disabled_frames.get(k, frames[k]))
		if k == selected and enabled[k] and not dimmed:
			p.play(anim_dir, base, base + 4)
		else:
			p.set_frame(anim_dir, base)


## 行动菜单在单位旁边的位置 (地图坐标, 原版像素), 唯一实现。原版 (屏幕缓冲区坐标, 边框 30,24):
##   镜头格 cc = (卷动 x + 10)/30, cr = (卷动 y + 4)/24; col = 单位格 x - cc, row = 单位格 y - cr;
##   x = col*30 - w/2 + 0x37, y = row*24 - h + 0x34; col = 0 时 x+30, col = 9 (最右一整列) 时 x-30。
##   减边框 (30,24) 得屏幕坐标 x = col*30 - w/2 + 25, y = row*24 - h + 28。原版镜头总是按格对齐 (卷动 = 格*30 - 10、格*24 - 4,
##   移镜 0x07 与跟随都按格走, 复刻 BattleScene.CAM_OFFSET), 此时 cc*30 = 卷动 + 10, 公式化为相对单位格:
##     x = 格x*30 - w/2 + 25 - 10 (= 以格为中心), y = 格y*24 - h + 28 - 4 (= 格顶下 3)。
##   复刻镜头可停在任意像素 (平滑跟随、宽屏夹紧), 所以按相对格的形式放, 不随镜头余数漂移; 只用镜头判断是否在首/末列。
##   参数在布局表 actionmenu.pos.params (x, y, edge_shift, cam_round), 换游戏改表。
## 复刻补充: 最右一整列 = 可见宽 (view.x - cam_round.x*2)/30 - 1 (320 时 = 9); 结果夹在可见区内 (宽屏/地图边不出界)。
static func place_near(cell: Vector2i, cam: Vector2, view: Vector2, w: float, h: float) -> Vector2:
	var pr: Dictionary = UiLayout.val("actionmenu.pos", "params", {})
	var ox := int(pr.get("x", 25))
	var oy := int(pr.get("y", 28))
	var shift := int(pr.get("edge_shift", 30))
	var cr: Array = pr.get("cam_round", [10, 4])
	var col := cell.x - floori((cam.x + float(cr[0])) / 30.0)
	var last := int((view.x - float(cr[0]) * 2.0) / 30.0) - 1
	var x := cell.x * 30 - int(cr[0]) - int(w) / 2 + ox
	var y := cell.y * 24 - int(cr[1]) - int(h) + oy
	if col == 0:
		x += shift
	elif col == last:
		x -= shift
	var p := Vector2(x, y)
	p.x = clampf(p.x, cam.x, maxf(cam.x, cam.x + view.x - w))
	p.y = clampf(p.y, cam.y, maxf(cam.y, cam.y + view.y - h))
	return p.floor()

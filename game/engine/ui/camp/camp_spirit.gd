# SPDX-License-Identifier: GPL-3.0-only
class_name CampSpirit
extends Node2D
## 五魂化蘊 (素材 Misc/SP_REV), 坐标与原版截图核对:
##   面板 第 0 帧在 (88,44) (缓冲区 (0x76,0x44)); 打开/换人时自左滑入 16,8,4,2,0。
##   人名标签: x = 5 + (48−宽)/2, y = 4, flags=5。
##   魂力: 剩余 %3d 在 (39,24), 总数 %3d 在 (70,24), 第 2 帧字模。
##   每魂 k: 值 = 原值 + 本次加点; 柱 第 min(级,9)+4 帧在 (19+28k, 46), 级 = (值−1)/10, 级 ≤ 0 不画;
##     数值 %3d 竖排 (步进 6) 在 (25+28k, 67), 本次加过点的用第 3 帧 (绿), 否则第 2 帧; 本次加点 %2d 在 (7+28k, 85), 前导空格不画 (是画空白格, 见布局表 camp.spirit.added 的 note)
##     (加过点时也是绿色, 截图核对)。问「要結束魂力調整嗎？」时面板收起 (截图核对)。
##   分配模式: 选中魂的上箭头 第 22~24 帧在 (11+28·sel, 36), 下箭头 第 25~27 帧在 (11+28·sel, 94), 每 5 tick 换帧;
##     描边 第 1 帧叠在面板上呼吸发亮。
##   浏览模式且两人以上: 左右箭头 第 14~17 帧在屏幕 (78,100)、第 18~21 帧在 (239,100), 每 5 tick 换帧。
## 复刻新增: 查看键 (F / 手柄 X / 触屏长按) 或空格 = 打开当前这个人的「五魂」攻略页 (技能习得条件与五魂规划), 看完关掉回到这里。
## 按键: 浏览模式 ←/→ 换人 (循环)、确认进入分配、取消问「要結束魂力調整嗎？」(默认✗), 是则写回并退出;
##   分配模式 ↑ 加一点、↓ 减一点 (只能减本次加的)、←/→ 换魂 (循环)、确认或取消回浏览模式。
## 坐标、帧号取布局表 camp.spirit.* (每魂序号 k; 绿/普通字模用 which = 1/0)。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal closed
signal guide_requested(uid: int)   # 查看键 / 空格: 要打开这个人的「五魂」攻略页 (营地场景接, 攻略章 id = spirit_<单位号>)

const UnitState = preload("res://engine/rules/unit_state.gd")
const Growth = preload("res://engine/rules/growth.gd")
const AttrNames = preload("res://engine/rules/attr_names.gd")
const NAMES := AttrNames.SPIRIT

var uids: Array = []
var who := 0
var allocating := false
var msel := 0
## 每人本次加点 {uid: [5 个]} 与开始时的点数 {uid: n}
var added := {}
var total := {}
var question: CampAsk.Question
var _panel: Node2D
var _glow: UiPanel
var _up: UiPanel
var _down: UiPanel
var _al: UiPanel
var _ar: UiPanel
var _cyc3 := CampUi.Cycle.new(5, 3)
var _cyc4 := CampUi.Cycle.new(5, 4)
var _glow_t := 0.0
var _pos := Vector2.ZERO


func _init(party: Array) -> void:
	uids = party
	for uid in uids:
		added[uid] = [0, 0, 0, 0, 0]
		total[uid] = int(gc.state.party_of(uid).get("spirit_points", 0))
	_panel = Node2D.new()
	_pos = UiLayout.at("camp.spirit.panel")
	_panel.position = _pos
	add_child(_panel)
	_al = UiLayout.panel("camp.spirit.swap_left")
	_ar = UiLayout.panel("camp.spirit.swap_right")
	add_child(_al)
	add_child(_ar)
	_build()


func open() -> void:
	UiSlide.run(_panel, _pos, Vector2.LEFT, CampUi.SLIDE, true)


func _remaining(uid: int) -> int:
	var n: int = total[uid]
	for v in added[uid]:
		n -= v
	return n


func _value(uid: int, k: int) -> int:
	return int(gc.state.party_of(uid).get("spirit", {}).get(NAMES[k], 0)) + added[uid][k]


func _build() -> void:
	for c in _panel.get_children():
		_panel.remove_child(c)
		c.queue_free()
	var uid: int = uids[who]
	var bg := UiLayout.panel("camp.spirit.panel")
	bg.position = Vector2.ZERO
	_panel.add_child(bg)
	_glow = UiLayout.panel("camp.spirit.glow")
	_glow.visible = allocating
	_panel.add_child(_glow)
	_panel.add_child(UiText.make("camp.spirit.name", CampInventory.unit_name(uid)))
	_panel.add_child(UiLayout.number("camp.spirit.points", _remaining(uid), 0))
	_panel.add_child(UiLayout.number("camp.spirit.points", total[uid], 1))
	for k in 5:
		var v := _value(uid, k)
		var lv := (v - 1) / 10
		if lv > 0:
			var b := UiLayout.panel("camp.spirit.bar", k)
			b.set_frame(b.anim_dir, b.frame + mini(lv, 9))
			_panel.add_child(b)
		var a: int = added[uid][k]
		var g := {"which": 1 if a > 0 else 0}
		_panel.add_child(UiLayout.number("camp.spirit.value", v, k, g))
		_panel.add_child(UiLayout.number("camp.spirit.added", a, k, g))
	_up = UiLayout.panel("camp.spirit.alloc_up", msel)
	_down = UiLayout.panel("camp.spirit.alloc_down", msel)
	_up.visible = allocating
	_down.visible = allocating
	_panel.add_child(_up)
	_panel.add_child(_down)
	_al.visible = not allocating and uids.size() > 1
	_ar.visible = _al.visible


func _process(delta: float) -> void:
	if _cyc3.step(delta) and allocating:
		_up.set_frame(_up.anim_dir, UiLayout.frame("camp.spirit.alloc_up") + _cyc3.phase)
		_down.set_frame(_down.anim_dir, UiLayout.frame("camp.spirit.alloc_down") + _cyc3.phase)
	if _cyc4.step(delta):
		_al.set_frame(_al.anim_dir, UiLayout.frame("camp.spirit.swap_left") + _cyc4.phase)
		_ar.set_frame(_ar.anim_dir, UiLayout.frame("camp.spirit.swap_right") + _cyc4.phase)
	if allocating and _glow:  # 描边呼吸: 强度 16↔32, 每 3 tick 变 2; 这里用透明度近似
		_glow_t += delta
		_glow.modulate.a = 0.5 + 0.5 * absf(sin(_glow_t * PI / (CampUi.TICK * 24)))


## 指针 (engine/ui/ui_hit.gd):
##   浏览: 点左右箭头 = 换人, 点面板 = 进入分配 (同确认)。
##   分配: 悬停某魂的柱 = 选中该魂 (同 ←/→); 点它的上/下箭头 = 加/减一点 (同 ↑/↓, 滚轮也是); 点面板外 = 分配结束 (同确认)。
##   问句打开时交给它的是/否框。
func ui_pointer_target() -> Object:
	return question if question else self


func ui_hits() -> Array:
	var out: Array = []
	if allocating:
		var g := UiLayout.num("camp.spirit.hit.arrow", "grow", 2)
		for k in 5:
			for pair in [["camp.spirit.alloc_up", UiAction.UP], ["camp.spirit.alloc_down", UiAction.DOWN]]:
				var fr := UiPanel.frame_rect(String(UiLayout.sprite(pair[0]).get("anim", "")), UiLayout.frame(pair[0])).grow(g)
				out.append(UiHit.area(Rect2(fr.position + UiLayout.at(pair[0], k), fr.size), k, _panel, pair[1]))
		for k in 5:
			out.append(UiHit.area(UiLayout.rect("camp.spirit.hit.column", k), k, _panel, UiAction.NONE))
		out.append(UiHit.area(_bg_rect(), null, _panel, UiAction.NONE))
		return out
	if uids.size() > 1:
		var g2 := UiLayout.num("camp.spirit.hit.swap", "grow", 3)
		out.append(UiHit.area(UiPanel.frame_rect(_al.anim_dir, _al.frame).grow(g2), null, _al, UiAction.LEFT))
		out.append(UiHit.area(UiPanel.frame_rect(_ar.anim_dir, _ar.frame).grow(g2), null, _ar, UiAction.RIGHT))
	out.append(UiHit.area(_bg_rect(), null, _panel))
	return out


func _bg_rect() -> Rect2:
	return UiPanel.frame_rect(String(UiLayout.sprite("camp.spirit.panel").get("anim", "")), UiLayout.frame("camp.spirit.panel"))


## 分配模式下选中第 k 魂
func ui_select(k) -> void:
	if allocating and k != msel:
		msel = k
		_build()


func ui_outside_action() -> int:
	return UiAction.CONFIRM if allocating else UiAction.NONE


## 按住 ←/→ 换人 (非加点状态) 的连发间隔: 同体态观览, 15 帧 = 0.6 秒 (实测); 加点状态下 ←/→ 选魂是 5 帧
const SWITCH_REPEAT := 15 * 0.04


func repeat_interval(kind: int) -> float:
	if kind in [UiAction.LEFT, UiAction.RIGHT] and not allocating and question == null:
		return SWITCH_REPEAT
	return KeyRepeat.REPEAT


func key(k: String) -> void:
	if question:
		question.key(k)
		return
	var uid: int = uids[who]
	if k == "space":
		guide_requested.emit(uid)
		return
	if allocating:
		match k:
			"up":
				if Growth.spirit_can_inc(_remaining(uid), _value(uid, msel) - int(added[uid][msel]), CampInventory.params().spirit_add_limit):  # 只比【原值】, 原版漏洞
					added[uid][msel] += 1
			"down":
				if added[uid][msel] > 0:
					added[uid][msel] -= 1
			"left":
				msel = posmod(msel - 1, 5)
			"right":
				msel = posmod(msel + 1, 5)
			"accept", "cancel":
				allocating = false
		_build()
		return
	match k:
		"left", "right":
			if uids.size() > 1:
				who = posmod(who + (1 if k == "right" else -1), uids.size())
				_build()
				open()
		"accept":
			allocating = true
			msel = 0
			_build()
		"cancel":
			_show_panel(false)
			question = CampAsk.Question.new(UiStrings.t("camp.spirit.ask_end"))
			add_child(question)
			question.done.connect(_on_question)


func _on_question(yes: bool) -> void:
	question.queue_free()
	question = null
	if not yes:
		_show_panel(true)
		return
	apply()
	closed.emit()


func _show_panel(on: bool) -> void:
	if on:
		_build()
		open()
	else:
		_panel.visible = false
		_al.visible = false
		_ar.visible = false


## 写回: 加点计入五魂, 扣掉点数
func apply() -> void:
	for uid in uids:
		var g: Dictionary = gc.state.party[uid]
		var n := 0
		for k in 5:
			var a: int = added[uid][k]
			if a > 0:
				g["spirit"][NAMES[k]] = int(g["spirit"].get(NAMES[k], 0)) + a
				n += a
		g["spirit_points"] = int(g.get("spirit_points", 0)) - n
		added[uid] = [0, 0, 0, 0, 0]

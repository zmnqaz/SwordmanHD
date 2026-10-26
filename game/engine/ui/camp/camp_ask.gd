# SPDX-License-Identifier: GPL-3.0-only
class_name CampAsk
extends RefCounted
## 是/否框与问句框。


## 是/否框 (Misc/Sqw_int): 帧 = sel*11 + phase, sel 0 为○ (是)、1 为✗ (否); phase 0~10 每 3 tick 前进。
## ←/→ 切换, 确认返回 sel, 取消在允许时返回 −1。打开时自上而下滑入 16,8,4,2,0 并淡入。
## 营地里各处默认都是✗ (参数 5 = 1)。
class YesNo:
	extends Node2D
	signal done(yes: bool)
	static var DIR: String:
		get:
			return ThemeAssets.p("camp.ask")
	var sel := 1
	var allow_cancel := true
	var _panel: UiPanel
	var _cyc := CampUi.Cycle.new(3, 11)
	var _base := Vector2.ZERO

	## 按布局元素建 (pos 可含公式变量 vars, 如 r 行号 / s 档位), 父坐标由调用方加 (offset)
	static func make(id: String, vars := {}, offset := Vector2.ZERO, default_yes := false) -> YesNo:
		var y := YesNo.new(offset + UiLayout.at(id, 0, vars), default_yes)
		UiLayout.tag(y, id, UiPanel.frame_rect(DIR, 0))
		return y

	func _init(pos: Vector2, default_yes := false) -> void:
		_base = pos
		position = pos
		sel = 0 if default_yes else 1
		_panel = UiPanel.new(DIR, sel * 11)
		add_child(_panel)

	func _ready() -> void:
		UiSlide.run(self, _base, Vector2.UP, CampUi.SLIDE, true)

	func _process(delta: float) -> void:
		if _cyc.step(delta):
			_panel.set_frame(DIR, sel * 11 + _cyc.phase)

	## 指针 (engine/ui/ui_hit.gd): 框的左半是○ (是)、右半是✗ (否)
	func ui_hits() -> Array:
		var r := UiPanel.frame_rect(DIR, sel * 11)
		var half := r.size * Vector2(0.5, 1.0)  # 左半○、右半✗
		return [UiHit.area(Rect2(r.position, half), 0), UiHit.area(Rect2(r.position + Vector2(half.x, 0), half), 1)]

	func ui_select(i) -> void:
		if i != sel:
			sel = i
			_panel.set_frame(DIR, sel * 11 + _cyc.phase)

	func key(k: String) -> void:
		match k:
			"left", "right":
				sel = 1 - sel
				_panel.set_frame(DIR, sel * 11 + _cyc.phase)
			"accept":
				done.emit(sel == 0)
			"cancel":
				if allow_cancel:
					done.emit(false)


## 问句框 CFloatMsgBox (Misc/FLOAT_MB 第 0 帧, –): 在 (86,84), 自左滑入 16,8,4,2,0。
## 文字按 20 字节 (10 个汉字) 折成两行, x=12; 一行时 y=11, 两行时 y=5 / 17。
## 是/否框在问句框 + (128,24) 即 (214,108)。营地里的问句都是立即显示 (不逐字)、默认✗、可取消。
## 坐标取布局表 camp.ask.* (text 的 y 写 "11|5+12*k": 一行 / 两行)。
class Question:
	extends Node2D
	signal done(yes: bool)
	var yes_no: YesNo
	var _box: Node2D
	var _pos := Vector2.ZERO

	func _init(text: String, default_yes := false) -> void:
		_box = box(text)
		_pos = _box.position
		add_child(_box)
		yes_no = YesNo.make("camp.ask.yesno", {}, _pos, default_yes)
		add_child(yes_no)
		yes_no.done.connect(func(y): done.emit(y))

	## 问句框底图 + 折行文字 (布局表 camp.ask.box / camp.ask.text), 问句框与浮动提示框共用
	static func box(text: String) -> UiPanel:
		var b := UiLayout.panel("camp.ask.box")
		var lines := UiText.wrap_width(text, float(UiLayout.text("camp.ask.text").get("wrap_bytes", 20)) * 6.0)
		for k in lines.size():
			b.add_child(UiText.make("camp.ask.text", lines[k], k, {"which": 0 if lines.size() == 1 else 1}))
		return b

	func _ready() -> void:
		UiSlide.run(_box, _pos, Vector2.LEFT, CampUi.SLIDE, true)

	func key(k: String) -> void:
		yes_no.key(k)

	## 指针交给是/否框
	func ui_pointer_target() -> Object:
		return yes_no


## 浮动提示框 (CFloatMsgBox 不带是/否, 文字 + 停留 tick 数): 同问句框的位置与文字排版, 自左滑入, 停留 secs 秒后发 closed。
## 停留期间不收输入 (原版是定时关闭, 没有按键处理); 调用方在 closed 之前忽略按键即可。
class Notice:
	extends Node2D
	signal closed
	var secs := 2.0
	var _box: Node2D

	func _init(text: String, stay_secs: float) -> void:
		secs = stay_secs
		_box = Question.box(text)
		add_child(_box)

	func _ready() -> void:
		UiSlide.run(_box, UiLayout.at("camp.ask.box"), Vector2.LEFT, CampUi.SLIDE, true)
		if secs <= 0.0:
			closed.emit.call_deferred()
		else:
			get_tree().create_timer(secs).timeout.connect(func(): closed.emit())

# SPDX-License-Identifier: GPL-3.0-only
extends Node2D
## F10 设定面板的底图层 (settings_panel.gd): 底板、边框、选中行光标、音量格、值两侧的小三角。
## 坐标与颜色全部取自布局表 settings.* (原点 = 面板左上角, 原版像素)。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

var panel: Node


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, UiLayout.size_of("settings.panel"))
	draw_rect(r, UiLayout.color(UiLayout.val("settings.panel", "color"), Color(0.04, 0.02, 0.01, 0.96)))
	var bc := UiLayout.color(UiLayout.val("settings.panel", "border"), Color8(150, 112, 52))
	draw_rect(r.grow(-0.5), bc, false, 1.0)
	draw_rect(r.grow(-2.5), Color(bc, 0.35), false, 1.0)
	var sel: int = panel._sel
	var n: int = panel._n
	var top: int = panel._top
	var vis: int = panel._vis
	var total: int = panel.total()
	var sel_slot: int = panel.slot_of(sel)
	if sel_slot >= 0:
		draw_rect(Rect2(UiLayout.at("settings.cursor", sel_slot), UiLayout.size_of("settings.cursor")),
			UiLayout.color(UiLayout.val("settings.cursor", "color")))
	var on := UiLayout.color(UiLayout.val("settings.bar", "color"))
	var off := UiLayout.color(UiLayout.val("settings.bar", "color_off"))
	var seg := UiLayout.size_of("settings.bar")
	var row_step := UiLayout.step("settings.row")
	var ac := UiLayout.color(UiLayout.val("settings.arrow", "color"))
	for s in vis:
		var e := top + s
		if e >= n:
			break
		var r2: Dictionary = SettingsSchema.shown_rows()[e]
		if r2["kind"] == "volume":
			var v := int(gc.settings[r2["key"]])
			for k in 10:
				draw_rect(Rect2(UiLayout.at("settings.bar", k) + row_step * s, seg), on if k < v else off)
		if e == sel and r2["kind"] != "action":  # 选中项值两侧的三角: 可调整的方向 (音量到头一侧变暗)
			var ar := UiLayout.size_of("settings.arrow")
			var y := UiLayout.at("settings.arrow", 0).y + row_step.y * s
			var lx := UiLayout.at("settings.arrow", 0).x
			var vr := UiLayout.rect("settings.value", 0)
			var rx := vr.position.x + vr.size.x + (vr.position.x - lx - ar.x)
			var can_l := true
			var can_r := true
			if r2["kind"] == "volume":
				can_l = int(gc.settings[r2["key"]]) > 0
				can_r = int(gc.settings[r2["key"]]) < 10
			draw_colored_polygon(PackedVector2Array([Vector2(lx + ar.x, y), Vector2(lx + ar.x, y + ar.y), Vector2(lx, y + ar.y / 2)]),
				ac if can_l else Color(ac, 0.25))
			draw_colored_polygon(PackedVector2Array([Vector2(rx, y), Vector2(rx, y + ar.y), Vector2(rx + ar.x, y + ar.y / 2)]),
				ac if can_r else Color(ac, 0.25))
	# 列表比版面长: 过长的一侧在面板右缘画 ▲ / ▼ 提示 (还能往上/下滚)
	var rr := UiLayout.rect("settings.row", 0)
	var cx := UiLayout.size_of("settings.panel").x - 8.0
	if top > 0:
		var y0 := rr.position.y + 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 3, y0 + 4), Vector2(cx + 3, y0 + 4), Vector2(cx, y0)]), ac)
	if top + vis < total:
		var y1 := UiLayout.at("settings.row", vis - 1).y + rr.size.y - 1.0
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 3, y1 - 4), Vector2(cx + 3, y1 - 4), Vector2(cx, y1)]), ac)

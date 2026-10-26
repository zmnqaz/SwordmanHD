# SPDX-License-Identifier: GPL-3.0-only
class_name UiTurnBanner
extends Node2D
## 回合横幅 (布局表 turn_banner.*): Misc/Cha_tur 陽之陣 (我方) / 陰之陣 (敌方) 帧段 (sprite.frames), 部件自带屏幕坐标。
## 底条是 type 7 (正片叠底, shaders/dark_mask.gdshader), 定格后整条滑出下沿 (turn_banner.exit)。
## 回合数「其N」(第 0 帧 其, 1~9 一~九, 10 十) 在 turn_banner.digits (重复步进 = 字距), 自右滑入 (turn_banner.digits.slide)。
## 放在 UI 层的 CENTER 锚点下; play() 播完返回, 调用方自己 queue_free。战场 (BattleView.banner) 与展示页 (gallery) 共用。


func play(side: int, turn: int) -> void:
	var a := AnimPlayer.new()
	a.play_sound = false
	a.position = UiLayout.at("turn_banner.anim")
	add_child(a)
	var sp := UiLayout.sprite("turn_banner.anim")
	var seg: Array = sp.get("frames", [[12, 27], [28, 43]])[clampi(side, 0, 1)]
	a.play(String(sp.get("anim", ThemeAssets.p("battle.turn_banner"))), int(seg[0]), int(seg[1]), false)
	var nums := Node2D.new()
	add_child(nums)
	var glyphs := glyphs_of(turn)
	var dir := String(UiLayout.sprite("turn_banner.digits").get("anim", ThemeAssets.p("battle.turn_banner")))
	var nodes: Array = []
	for i in glyphs.size():
		var n := AnimPlayer.new()
		n.show_frame(dir, glyphs[i])
		n.position = UiLayout.at("turn_banner.digits", i)
		nums.add_child(n)
		nodes.append(n)
	_slide_digits(nodes)
	await a.finished
	# 状态 3 停 hold_frames 帧, 状态 4 整条 (底条与数字) 按 dy_table 每 step_frames 帧一档下移 (原版, 25 帧/秒)
	var ex := UiLayout.el("turn_banner.exit")
	await _frames(int(ex.get("hold_frames", 12)) + 1)
	var base_y := position.y
	for dy in ex.get("dy_table", []):
		position.y = base_y + float(dy)
		await _frames(int(ex.get("step_frames", 2)))


## 「其N」自右滑入并变深: 每 slide_frames 帧一档 [dx, dy, 混合权重/16], 档数用完后不透明停在起点
func _slide_digits(nodes: Array) -> void:
	var spec := UiLayout.el("turn_banner.digits")
	var rows: Array = spec.get("slide", [])
	var frames := int(spec.get("slide_frames", 3))
	var base: Array = nodes.map(func(n): return n.position)
	for r in rows:
		for i in nodes.size():
			nodes[i].position = base[i] + Vector2(float(r[0]), float(r[1]))
			nodes[i].modulate.a = float(r[2]) / 16.0
		await _frames(frames)
	for i in nodes.size():
		nodes[i].position = base[i]
		nodes[i].modulate.a = 1.0


func _frames(n: int) -> void:
	await get_tree().create_timer(n / 25.0).timeout


## 回合数的字形帧: 「其」 + 回合 <=10: [N]; 11~19: [十, 个位]; >=20: [十位, 十, 个位 (非 0)]
static func glyphs_of(turn: int) -> Array:
	var glyphs := [0]
	if turn / 10 > 1:
		glyphs.append(turn / 10)
	if turn / 10 > 0:
		glyphs.append(10)
	if turn % 10 > 0:
		glyphs.append(turn % 10)
	return glyphs

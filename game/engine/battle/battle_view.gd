# SPDX-License-Identifier: GPL-3.0-only
class_name BattleView
extends Node
## 战场地图上的表现 (只管画, 不做规则判断, 不读输入):
##   范围格 (移动/敌方移动/攻击)、目标身上的伤害/回复数字、格上的结果动画 (MAN_RES / Maplup)、已行动变灰、转身、回合横幅、
##   光标 (BattleScene.cursor) 与信息条 (UiInfoBar, 原版)。
## 坐标: 地图上的节点挂在 BattleScene.units_node 下 (原版像素, 随镜头); 屏幕上的挂在 BattleUi 的 UiLayer 下。

const U = preload("res://engine/rules/unit_state.gd")

## 范围格: 纯色方块, 画在人物下面, 近乎不透明且不闪 (原版实测: 地板 (60,33,16) 叠加后 (153,33,198);
## 差异_第1幕_移动范围颜色.png 两次纹理拟合地板透出率都约 13%, 叠加色 ≈(167,33,225) @ 0.87)。
## 我方移动范围品红紫 (蓝紫色 #8a3cf0 是叠加后的观感); 敌方移动范围、攻击/施法范围红色 (重制版 GameBattleUnitMovement)
const RANGE_MOVE := Color8(167, 33, 225)
const RANGE_ENEMY := Color(1.0, 0.0, 0.0)
const RANGE_ATTACK := Color(1.0, 0.0, 0.0)
const RANGE_ALPHA := 0.87

var bs
var ui: BattleUi
var _range_node: Node2D


func _init(scene, battle_ui: BattleUi) -> void:
	bs = scene
	ui = battle_ui


func _ready() -> void:
	_range_node = Node2D.new()
	_range_node.z_index = -2  # 在人物和光标下面
	bs.units_node.add_child(_range_node)


# ---------------- 范围 ----------------

func show_range(cells: Array, tint: Color) -> void:
	clear_range()
	var cell := Vector2(BattleStage.CELL_W, BattleStage.CELL_H)
	for c in cells:
		var r := ColorRect.new()
		r.position = Vector2(c) * cell
		r.size = cell
		r.color = Color(tint, 1.0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_range_node.add_child(r)
	_range_node.modulate.a = RANGE_ALPHA  # 原版不闪, 旧实现的 0.25~0.5 呼吸动画删掉


func clear_range() -> void:
	for c in _range_node.get_children():
		_range_node.remove_child(c)
		c.queue_free()


func range_cells() -> Array:
	return _range_node.get_children().map(func(r): return Vector2i(int(r.position.x) / BattleStage.CELL_W, int(r.position.y) / BattleStage.CELL_H))


# ---------------- 光标与信息条 ----------------

func show_cursor(c: Vector2i) -> void:
	bs.show_cursor(c.x, c.y)


func hide_cursor() -> void:
	bs.hide_cursor()


## 光标形状 = 当前法术/道具的效果范围 (0 单格); 选目标状态进出时设
func set_cursor_area(area: int) -> void:
	bs.set_cursor_area(area)


## 格子相对画面左上角的行 (原版: 行 > 4 时信息条放顶端)
func screen_row(c: Vector2i) -> int:
	var h := BattleStage.CELL_H
	return int(floor((c.y * h - bs.cam.y + h / 2) / float(h)))


## 光标停在单位上: 显示信息条左右两块 (原版 onCursorMoveOver, 2.1 / §5-20); u 为空则隐藏。
## 触摸界面 (手机) 固定放顶端, 给底部的虚拟键让位 (重制版 GameBattleUserRightUI.cs:42 移动端 top = true)
func show_info(u: BattleUnit, at: Vector2i) -> void:
	if u == null:
		ui.info.hide_bar()
		return
	ui.info.show_unit(unit_info(u), UiInfoBar.top_for_row(screen_row(at)) or InputRouter.touch_mode, true)


func hide_info() -> void:
	ui.info.hide_bar()


## UiInfoBar 的单位数据
static func unit_info(u: BattleUnit) -> Dictionary:
	return {"name": u.name_text, "hp": u.hp, "hp_max": u.hp_max, "mp": u.mp, "mp_max": u.mp_max,
		"move": u.move_now, "move_max": u.move_max, "attack": u.attack, "defence": u.defence, "lv": u.lv, "exp": u.exp,
		"buffs": [u.has_status(U.ST_ATK_UP), u.has_status(U.ST_DEF_UP), u.has_status(U.ST_TECH_UP), u.has_status(U.ST_HASTE)]}


# ---------------- 单位外观 ----------------

## 本阶段已行动 / 不能行动的单位画成灰色 (麻痺、冰結的我方单位一开始就不能选中);
## 阶段结束后 (acted_fx 关) 不再灰, 返召之咒 (acted 置回) 也不灰
func shade(u: BattleUnit, can_start: bool) -> void:
	var grey: bool = (u.acted and u.acted_fx) or (u.controllable and not u.acted and not can_start)
	u.modulate = UiLayout.color("map.unit.acted_grey") if grey else Color.WHITE
	if grey:
		u.anim.playing = false
	elif u.alive and u.shown:
		u.play_act(BattleUnit.Act.STAND, u.dir)


func retint() -> void:
	for o in bs.units:
		if o.shown:
			o._tint()


func face(u: BattleUnit, t: BattleUnit) -> void:
	var dx := t.cx - u.cx
	var dy := t.cy - u.cy
	var d := BattleUnit.Dir.EAST if dx > 0 else BattleUnit.Dir.WEST
	if absi(dy) > absi(dx):
		d = BattleUnit.Dir.SOUTH if dy > 0 else BattleUnit.Dir.NORTH
	u.play_act(BattleUnit.Act.STAND, d)


# ---------------- 伤害/回复数字与结果动画 ----------------

## 法术结果的伤害/回复数字 (布局表 map.damage): 原版法术命中/回复后在目标格上弹数字 (红伤害 / 蓝回复, 与近景同一套字模与跳动表),
## 不受「伤害飘字」设定控制。挂在人物层、随镜头走; 返回节点, 调用方可等它的 done 信号 (约 1.2 秒)。
func digits(u: BattleUnit, value: int, heal: bool) -> DamageDigits:
	var n := DamageDigits.new(str(maxi(0, value)), "map.damage", heal, {"cx": u.cx, "cy": u.cy})
	n.z_index = 60
	bs.units_node.add_child(n)
	n.done.connect(n.queue_free)
	return n


## 在单位身上播放一段结果动画 (MAN_RES / Maplup); wait 时等它结束。放置按演出表 result 段 (约定 unit, 锚在单位, FxPlace)
## tick > 0: 每帧固定这么多 tick (忽略帧表 time; 状态解除动画实测每帧 0.12 秒 = 3 tick)
## sound: 出不出声 (缺省跟 wait: 等它播完的那个出声); 多目标同时放时只有第一个出声, 但等的是最长的那个
func res_anim(u: BattleUnit, dir: String, start: int, end: int, wait := true, tick := 0, sound = null) -> void:
	var r := CastFx.section("result")
	var a := spawn_fx(dir, FxPlace.at_pixel(u.position, String(r.get("convention", "unit"))), start, end, 60, wait if sound == null else bool(sound), tick)
	if wait:
		await a.finished


## 地图演出动画 (法术、招式、施法光效) 在格 at 按约定 conv 播放 [start, end) 帧并等结束 (FxPlace: 格 + 约定偏移)
## snap_cam: 满屏的动画 (整幅 320x200 画面, 如绝技 SM / S) 摆在实际镜头的屏幕原点而不是格子上: 原版就是「镜头到位后在屏幕 (0,0) 画」,
## 目标格靠近地图边、镜头被夹在地图内时, 按格摆会和实际画面错开, 框外那圈黑 (FullscreenCover) 就露在一侧 (2026-10-29 用户: 电射星驰左边一块黑)
func map_anim(dir: String, at: Vector2i, start := 0, end := -1, conv := "fx", snap_cam := false) -> void:
	var a := spawn_fx(dir, FxPlace.at_cell(at, conv), start, end, 50, true, 0, snap_cam)
	await a.finished


## 在地图坐标 pos 放一个演出动画并开始播放, 播完自动释放
func spawn_fx(dir: String, pos: Vector2, start := 0, end := -1, z := 50, sound := true, tick := 0, snap_cam := false) -> AnimPlayer:
	var a := AnimPlayer.new()
	a.play_sound = sound
	a.tick_override = tick
	a.position = pos
	a.z_index = z
	bs.units_node.add_child(a)
	a.play(dir, start, end, false)
	a.finished.connect(a.queue_free)
	if FullscreenCover.attach(a) and snap_cam:   # 满屏的演出动画: 宽屏/全屏下框外盖黑; 要求贴镜头的就摆到实际镜头的屏幕原点
		a.position = bs.orig_cam()
	return a


# ---------------- 施法: 镜头、法术名横幅、压暗、施法光效 (演出表 fx/cast.json, 布局 ui_theme/layout.json) ----------------

## 原版 (状态机): 镜头移到施法者 -> 压暗 + 法术名横幅 (Misc/Mag_misc 第 0 帧, 滑入, 37 tick 后滑出)
## + 施法光效 (Mag_misc 第 1 帧起, 约定 fx 锚在施法者) -> 镜头移到落点 -> 法术动画 (cast_fx)。返回 cast_end() 要收掉的节点。
func cast_begin(u: BattleUnit, skill_name: String) -> Array:
	await cast_camera(Vector2i(u.cx, u.cy))
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, float(CastFx.section("dim").get("alpha", 0.6875)))
	var cover: Rect2 = bs.layer_rect().grow_individual(bs.view().x, bs.view().y, bs.view().x, bs.view().y)
	dim.position = cover.position  # 盖住整个当前图层再外扩一屏 (镜头随后还要移到落点)
	dim.size = cover.size
	dim.z_index = 5  # 只压暗地图与地图物件; 人物 (units_node z 10) 不压暗 (实测人物亮度不变, 施法者摆施法姿势)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bs.world.add_child(dim)
	u.play_act(BattleUnit.Act.CAST, u.dir)
	var banner := cast_banner(skill_name)
	var au := CastFx.section("aura")
	var at := Vector2i(u.cx, u.cy)
	await map_anim(String(au.get("anim", ThemeAssets.p("fx.magic_misc"))), at, int(au.get("start", 1)), int(au.get("end", -1)), String(au.get("convention", "fx")))
	return [banner, dim, u]


## 演出镜头: 原版把格移到 320x200 画面中央 (FxPlace.center_cam), 复刻再换到当前视口并夹在地图内
func cast_camera(c: Vector2i) -> void:
	var cam_cfg := CastFx.section("camera")
	if not bool(cam_cfg.get("center", true)):
		await bs.follow_cell(c.x, c.y)
		return
	var sp: Array = cam_cfg.get("speed", [750, 600])
	await bs.pan_camera_to(FxPlace.center_cam(c), Vector2(float(sp[0]), float(sp[1])))


## 法术/绝技的地图演出 (动画、约定、锚点由 CastFx.for_skill 从演出表与技能记录解析)
func cast_fx(fx: Dictionary, caster: BattleUnit, target: Vector2i) -> void:
	var dir := String(fx.get("anim", ""))
	var movie := String(fx.get("movie", ""))
	var has_anim := dir != "" and Assets.exists(dir + "/anim.json")
	if movie == "" and not has_anim:
		# 原版数据缺口 (如 Sprite/man223/223s 原版本来就没有), 原版缺文件时静默跳过演出 -> 只记 verbose 日志, 不报 warning
		print_verbose("技能演出动画不存在 (原版数据缺口, 跳过): " + dir)
		return
	var at := target if String(fx.get("anchor", "target")) == "target" else Vector2i(caster.cx, caster.cy)
	await cast_camera(at)
	if movie != "":  # 状态 4: 镜头到落点后先放全屏视频 (Esc 可跳过, 回车不可), 再进 的法术动画
		await Cutscene.play_file(self, movie, fx.get("movie_skip", ["cancel"]))
	if not has_anim:
		return
	# hide_caster_on_self: 落点就是施放者自己的格 (射程 0, 如旋刃卷岚 / 日轮神剑) 时才藏: 这类演出文件 (NNN-nS) 自己把施放者画在画面中央的原位,
	# 不藏地图上的人会重影; 落点在别处时演出画在落点, 施放者留在原地, 不能藏 (②, 文件内容为证, 未实机核对)
	var hide := bool(fx.get("hide_caster", false)) or (bool(fx.get("hide_caster_on_self", false)) and at == Vector2i(caster.cx, caster.cy))
	if hide:
		caster.visible = false
	var own := {BattleUnit.Dir.SOUTH: 2, BattleUnit.Dir.WEST: 3, BattleUnit.Dir.NORTH: 0, BattleUnit.Dir.EAST: 1}.get(caster.dir, 2) as int
	var seg := CastFx.direction_segment(Assets.anim(dir), CastFx.direction_variant(Vector2i(caster.cx, caster.cy), target, own))   # 按方向分 4 段的动画只放一段
	await map_anim(dir, at, seg.x, seg.y, String(fx.get("convention", "fx")), String(fx.get("convention", "fx")) == "fx")
	if hide:
		caster.visible = true


## 法术名横幅: 布局 layout.json map.cast_banner (位置 ((320-w)/2, (200-h)>>3), w/h = 第 0 帧原版 1 倍外框 93x21)
## 与 map.cast_banner.text (flags=5 主色 + 光边, x = 46 - 字节数*3, y = 5)。动作按演出表 banner 段。
## host: 挂到这个节点下 (近景战斗的 _ui, 原版坐标) 而不是战场界面层; 近景里放物理绝技也有同一块横幅 (FIG_MISC 第 2 帧 =
## MAG_MISC 第 0 帧同图, 位置 (113,22) 同, 滑入/保持 37 tick/滑出同), 播完自己释放
func cast_banner(skill_name: String, host: Node2D = null, hold_ticks := -1) -> Node2D:
	var bc := CastFx.section("banner")
	if hold_ticks >= 0:   # 近景回来后的第二次横幅: 滑入就滑出, 不停留 (原版 连拍, 电射星驰 9.0~9.3 s)
		bc = bc.duplicate()
		bc["hold_ticks"] = hold_ticks
	var id := String(bc.get("element", "map.cast_banner"))
	var panel := UiLayout.panel(id)  # 位置按帧外框公式 ((320-w)/2, (200-h)>>3)
	var pos := panel.position
	panel.position = Vector2.ZERO
	var root := Node2D.new()  # 横幅 + 文字整体滑动/淡入
	root.add_child(panel)
	root.add_child(UiText.make(id + ".text", skill_name))
	var holder := Node2D.new()
	holder.position = pos
	holder.add_child(root)
	if host != null:
		host.add_child(holder)
	else:
		ui.layer.add(holder, UiLayout.anchor(id, ScreenLayout.Anchor.TOP))
	_banner_motion(root, bc, holder if host != null else null)
	return holder


func _banner_motion(root: Node2D, bc: Dictionary, free_after: Node = null) -> void:
	var tick: float = UiSlide.TICK
	var tw := root.create_tween()
	var seq_in: Dictionary = bc.get("in", {})
	var n_in := _banner_steps(tw, root, seq_in, tick)
	tw.tween_callback(_banner_step.bind(root, 0.0, 16.0))
	tw.tween_interval(tick * maxi(0, int(bc.get("hold_ticks", 37)) - n_in))
	_banner_steps(tw, root, bc.get("out", {}), tick)
	tw.tween_callback(root.hide)
	if free_after != null:
		tw.tween_callback(free_after.queue_free)


## 逐 tick 的 (位移, 混合/16) 表 -> Tween 步骤, 返回步数
func _banner_steps(tw: Tween, root: Node2D, seq: Dictionary, tick: float) -> int:
	var dys: Array = seq.get("dy", [])
	var als: Array = seq.get("alpha16", [])
	for i in dys.size():
		tw.tween_callback(_banner_step.bind(root, float(dys[i]), float(als[i]) if i < als.size() else 16.0))
		tw.tween_interval(tick)
	return dys.size()


func _banner_step(root: Node2D, dy: float, a16: float) -> void:
	root.position.y = dy
	root.modulate.a = a16 / 16.0


const SCREEN_W := 320
const SCREEN_H := 200

## 收掉横幅, 施法者回到站立; 压暗 (nodes 里的 ColorRect) 留着, 由 cast_fade_out 在结果动画之后渐亮 (原版 连拍: 压暗一直保持到结果动画结束, 之后约 0.6 秒渐亮, 再出经验框)
func cast_end(nodes: Array) -> void:
	for n in nodes:
		if n is BattleUnit:
			if n.alive and n.shown:
				n.play_act(BattleUnit.Act.STAND, n.dir)
		elif is_instance_valid(n) and not n is ColorRect:
			n.queue_free()


## 压暗渐亮并收掉 (阶梯式, 同原版)
func cast_fade_out(nodes: Array, sec := 0.6) -> void:
	for n in nodes:
		if is_instance_valid(n) and n is ColorRect:   # 先判有效: cast_end 已把横幅等节点 queue_free, 对已释放的实例做 is 会报脚本错误并中断整个施放流程
			var rect: ColorRect = n
			var tw: Tween = rect.create_tween()
			tw.tween_property(rect, "color:a", 0.0, sec)
			tw.tween_callback(rect.queue_free)
	await bs.get_tree().create_timer(sec).timeout


# ---------------- 回合横幅 ----------------

## 回合横幅 (布局表 turn_banner.*): Misc/Cha_tur 陽之陣 (我方) / 陰之陣 (敌方) 帧段 (sprite.frames), 部件自带屏幕坐标。锚点 CENTER。
## 底条是 type 7 (正片叠底, shaders/dark_mask.gdshader), 定格后整条滑出下沿 (turn_banner.exit)。
## 回合数「其N」(第 0 帧 其, 1~9 一~九, 10 十) 在 turn_banner.digits (重复步进 = 字距), 淡入 fade_sec
func banner(side: int, turn: int) -> void:
	var root := UiTurnBanner.new()
	ui.layer.add(root, UiLayout.anchor("turn_banner.anim"))
	await root.play(side, turn)
	root.queue_free()


## 回合数的字形帧: 「其」 + 回合 <=10: [N]; 11~19: [十, 个位]; >=20: [十位, 十, 个位 (非 0)]
static func turn_glyphs(turn: int) -> Array:
	return UiTurnBanner.glyphs_of(turn)

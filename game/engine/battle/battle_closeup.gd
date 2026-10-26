# SPDX-License-Identifier: GPL-3.0-only
class_name BattleCloseup
extends CanvasLayer
## 近景战斗画面 (移植重制版 GameBattleAttackUI 的普通攻击流程, 坐标为 320x200):
##   底: 本关 FLOOR_NN 第 floor 帧 (被攻击格的 DTL Floor); 我方永远在右, 敌方永远在左;
##   两侧各放单位的 NNNmisc 动画 (待机 = 第 6+站立帧数 起; 受击 1~3; 格挡 0~1);
##   攻击方播放 NNNa (命中) / NNNab (被格挡), 其中 hit>0 的帧触发守方受击, 部件 ref 引用守方 misc 的帧;
##   会心/连击先播 Misc/Sp000l|r 光效; 会心命中时白闪 0.05 秒; 击杀时守方变白淡出 0.8 秒 (原版实测)。
##   开场 0.5 秒由 2 倍缩回并淡入, 结束反向。信息栏/体力条/伤害数字按原版, 见下方「信息栏与伤害数字」。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

var bs
var _root: Node2D        # 以屏幕中心为原点缩放
var _stage: Node2D
var _black: ColorRect
var _white: ColorRect
var _red: ColorRect      # 格挡 (红闪避): 整个画面闪红约 0.3 秒, 伤害数字不变色 (原版实测 第 3 路)
var _sides := {}         # "left"/"right" -> {unit, misc: AnimPlayer, dir, panel: InfoPanel}
var _ui: Node2D
var _text: Node2D        # 不缩放的文字层


func _init(scene) -> void:
	bs = scene
	layer = 35
	visible = false


func _ready() -> void:
	ScreenLayout.bind_layer(self, ScreenLayout.SAFE)  # 近景画面按安全区居中, 黑底铺满
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.size = UiLayout.base_size() * Assets.SCALE
	add_child(_black)
	ScreenLayout.cover(_black, 2048.0)
	_root = Node2D.new()
	var center := UiLayout.at("closeup.zoom")  # 缩放中心
	_root.position = center * Assets.SCALE
	add_child(_root)
	_stage = Node2D.new()
	_stage.scale = Vector2.ONE * Assets.SCALE
	_stage.position = -center * Assets.SCALE
	_root.add_child(_stage)
	_white = ColorRect.new()
	_white.color = UiLayout.color(UiLayout.val("closeup.flash.white", "color", [1, 1, 1]))
	_white.size = UiLayout.base_size() * Assets.SCALE
	_white.visible = false
	add_child(_white)
	ScreenLayout.cover(_white, 2048.0)
	_red = ColorRect.new()
	_red.color = UiLayout.color(UiLayout.val("closeup.flash.red", "color", [1, 0, 0]))
	_red.size = UiLayout.base_size() * Assets.SCALE
	_red.visible = false
	add_child(_red)
	ScreenLayout.cover(_red, 2048.0)
	_ui = Node2D.new()
	_ui.scale = Vector2.ONE * Assets.SCALE
	add_child(_ui)
	_text = Node2D.new()
	add_child(_text)


static func misc_dir(u: BattleUnit) -> String:
	var s := int(u.info["sprite"])
	return ThemeAssets.f("unit_misc", [s, s])


static func idle_frame(data: Dictionary) -> Vector2i:
	var c: Array = data["action_counts"]
	var f := 6 + (int(c[0]) if int(c[0]) > 0 else 1)
	return Vector2i(f, f + maxi(1, int(c[1])))


## 打开画面: a 攻击 t; 返回后可多次 strike, 最后 close
func open(a: BattleUnit, t: BattleUnit) -> void:
	for c in _stage.get_children():
		c.queue_free()
	for c in _ui.get_children():
		c.queue_free()
	for c in _text.get_children():
		c.queue_free()
	_sides.clear()
	var floor_dir: String = bs.st.battle_floor
	if floor_dir != "" and Assets.exists(floor_dir + "/anim.json"):
		var fl := AnimPlayer.new()
		var cell: Dictionary = bs.st.cell(t.cx, t.cy)
		var fd := Assets.anim(floor_dir)
		fl.show_frame(floor_dir, clampi(int(cell.get("floor", 0)), 0, fd["frames"].size() - 1))
		_stage.add_child(fl)
	for u in [a, t]:
		var side := "left" if u.camp == 1 else "right"
		if _sides.has(side):  # 同阵营互打 (理论上不会), 退回按攻守分边
			side = "left" if u == t else "right"
		var m := AnimPlayer.new()
		m.play_sound = false
		_stage.add_child(m)
		var md := misc_dir(u)
		if Assets.exists(md + "/anim.json"):
			var r := idle_frame(Assets.anim(md))
			m.play(md, r.x, r.y)
		_sides[side] = {"unit": u, "misc": m, "dir": md}
		_build_info(side, u)
	visible = true
	var z := UiLayout.el("closeup.zoom")
	_root.scale = Vector2.ONE * float(z.get("scale", 1))
	_root.modulate.a = float(z.get("alpha", 1))
	var tw := create_tween().set_parallel()
	tw.tween_property(_root, "scale", Vector2.ONE, float(z.get("sec", 0)))
	tw.tween_property(_root, "modulate:a", 1.0, float(z.get("sec", 0)))
	await tw.finished


func close() -> void:
	var z := UiLayout.el("closeup.zoom")
	var tw := create_tween().set_parallel()
	tw.tween_property(_root, "scale", Vector2.ONE * float(z.get("scale", 1)), float(z.get("sec", 0)))
	tw.tween_property(_root, "modulate:a", 0.0, float(z.get("sec", 0)))
	await tw.finished
	visible = false


func _side_of(u: BattleUnit) -> String:
	return "left" if _sides.has("left") and _sides["left"]["unit"] == u else "right"


## 攻击方 a 对 d 的一次出手; results 为 BattleRules.strike 的结果, 伤害已由调用方算好但尚未扣除
## skill_name: 物理绝技的技能名, 近景里和闪光同一刻起在顶部出一块技能名横幅 (敌我一样); 普攻/反击为空
## vampire: 武器吸血 (附加类型 0) 命中时的吸血量, -1 = 没触发; 触发了 (吸到 0 也算) 在最后一击的伤害数字之后放吸血表现 (见 _vampire)
## digits: 守方弹不弹伤害数字 (物理绝技的结果记录不带伤害数值标志 (Skills.shows_damage) 时近景里也不弹, 如摄魂鬼触, 实测)
func strike(a: BattleUnit, d: BattleUnit, results: Array, skill_anim := "", skill_name := "", vampire := -1, digits := true) -> void:
	var asd: Dictionary = _sides[_side_of(a)]
	var dsd: Dictionary = _sides[_side_of(d)]
	var kind: String = results[0]["kind"]
	var sp := int(a.info["sprite"])
	var atk_dir := ThemeAssets.f("unit_attack", [sp, sp, "ab" if kind in ["miss", "guard"] else "a"])
	if skill_anim != "" and Assets.exists(skill_anim + "/anim.json"):
		atk_dir = skill_anim
	if skill_name != "":
		bs.ctl.view.cast_banner(skill_name, _ui)
	if kind in ["critical", "double"] or skill_anim != "":
		var fx := AnimPlayer.new()
		_stage.add_child(fx)
		fx.play(ThemeAssets.f("cast_flash", ["l" if _side_of(a) == "left" else "r"]), 0, -1, false)
		await fx.finished
		fx.queue_free()
	for i in results.size():
		await _play_attack(a, d, asd, dsd, atk_dir, results[i], vampire, i == results.size() - 1, digits)
		if int(dsd["panel"].shown) <= 0:
			break  # 已击杀: 不演剩余命中 (连击第一下致死不再打空气, 2026-10-06 用户实测)


## vamp: 吸血量 (-1 没触发); 只在最后一击后演, 致死的一击也算最后一击 (打死了后面的不演, 吸血跟在致死那一击后面)
func _play_attack(a: BattleUnit, d: BattleUnit, asd: Dictionary, dsd: Dictionary, atk_dir: String, r: Dictionary, vamp := -1, last := true, digits := true) -> void:
	r = r.duplicate()
	if gc.god and d.camp != 1:
		r["damage"] = 0
	var dmisc: AnimPlayer = dsd["misc"]
	var amisc: AnimPlayer = asd["misc"]
	var panel: InfoPanel = dsd["panel"]
	var hp_before := int(panel.shown)
	# 伤害数字与扣血量都用完整伤害值, 不封顶为当前血量 (体力条 hit() 自行截到 0); 数字取
	# 结算记录的伤害 (存未截断值), 04_伤害.md §2.1
	var dmg := int(r["damage"])
	var hp_after := maxi(0, hp_before - dmg)
	var drain := vamp if (last or hp_after <= 0) else -1   # 本击后要演的吸血
	if not Assets.exists(atk_dir + "/anim.json"):
		panel.hit(dmg, hp_after > 0)
		panel.set_hp(hp_after)
		await _jump(dsd, dmg, digits)
		if drain >= 0:
			await _vampire(asd, drain)
		return
	var atk := AnimPlayer.new()
	atk.other = dmisc
	_stage.add_child(atk)
	amisc.visible = false
	var data := Assets.anim(atk_dir)
	var c: Array = data["action_counts"]
	var hits := 0
	for i in data["frames"].size():
		if int(data["frames"][i]["hit"]) > 0:
			hits += 1
	var on_frame := func(f: int):
		var hide_def := int(c[1]) > 0 and f >= int(c[1]) and f < int(c[2])
		dmisc.visible = not hide_def
		if int(data["frames"][f]["hit"]) > 0:
			if r["kind"] in ["miss", "guard"]:  # 闪避/格挡: 守方格挡姿势
				dmisc.play(dsd["dir"], 0, 1)
				if not r.get("flash", {}).is_empty():
					_flash_red(r["flash"])
			else:
				dmisc.play(dsd["dir"], 1, 3)
				if r["kind"] == "critical":
					_flash()
			if dmg > 0:  # 每个命中帧扣 伤害/命中帧数, 并白闪体力条
				panel.hit(float(dmg) / maxi(1, hits), hp_after > 0)
	atk.frame_shown.connect(on_frame)
	atk.play(atk_dir, 0, -1, false)
	await atk.finished
	atk.queue_free()
	amisc.visible = true
	dmisc.visible = true
	var ia := idle_frame(amisc.data) if not amisc.data.is_empty() else Vector2i(0, 1)
	amisc.play(asd["dir"], ia.x, ia.y)
	panel.set_hp(hp_after)
	if hp_after <= 0:
		await _jump(dsd, dmg, digits)
		await _kill(dmisc)
		if drain >= 0:
			await _vampire(asd, drain)   # 先演倒下再吸血 (状态 7 死亡淡出 -> 状态 8/9, 实测: 淡出放完光环才出)
	else:
		var idl := idle_frame(dmisc.data)
		dmisc.play(dsd["dir"], idl.x, idl.y)
		# 伤害数字只看结算值: 命中/会心/格挡/闪避都走这里, 闪避就是红字「0」(原版实测); 不出「閃避」之类的文字
		await _jump(dsd, dmg, digits)
		if drain >= 0:
			await _vampire(asd, drain)


## 武器吸血的表现 (原版近景状态 8 / 9, 实测 2026-10-18, 差异): 命中且触发吸血就放, 吸到 0 (攻方满血) 一样放:
##   伤害数字 (或守方倒下淡出) 放完 delay 秒后, 攻击方身上放特效 Misc/Sp001r (攻方在右) / Sp001l (攻方在左) —— 近景构造里 "MISC\\SP%03dR/L.SAF" 按
##   武器附加特效号 (吸血 = 1) 载入的红色收拢光环 (8 帧 x 2 tick = 0.64 秒, 首帧淡入); 光环放完 digit_delay 秒后弹蓝色吸血量数字,
##   攻方体力条与数字同时按每周期 2% 上限涨上去 (InfoPanel.heal); 数字放完才往下 (敌方反击在这之后)
func _vampire(asd: Dictionary, amount: int) -> void:
	var cfg: Dictionary = UiLayout.el("closeup.vampire")
	var left: bool = asd == _sides.get("left")
	var panel: InfoPanel = asd["panel"]
	await create_tween().tween_interval(float(cfg.get("delay", 0.0))).finished
	var ring = asd["misc"].get_script().new()   # 同攻击方 misc 的播放器类 (引擎层不直接写 AnimPlayer 类名, 见 test_engine_deps)
	_stage.add_child(ring)
	ring.play(ThemeAssets.p(String(cfg.get("anim_left" if left else "anim", "battle.vampire_fx"))), 0, -1, false)
	await ring.finished
	ring.queue_free()
	await create_tween().tween_interval(float(cfg.get("digit_delay", 0.0))).finished
	panel.heal(amount)
	var n := DamageDigits.new(str(amount), "closeup.damage.left" if left else "closeup.damage.right", true)
	_ui.add_child(n)
	await n.done
	n.queue_free()


func _flash() -> void:
	_white.visible = true
	await SceneGuard.wait(self, UiLayout.num("closeup.flash.white", "sec", 0.05))
	_white.visible = false


## 格挡 (红闪避): 全屏叠加 flash.color, flash.sec 秒内线性褪到透明 (规则引擎 Attack.guard_flash 给出颜色与时长)。
## 守方表现与普通闪避相同 (格挡姿势 misc 第 0~1 帧), 照常扣血、出伤害数字 (不变红), 没有文字
func _flash_red(fl: Dictionary) -> void:
	_red.color = Color(fl.get("color", Color.RED), UiLayout.color(UiLayout.val("closeup.flash.red", "color", [1, 0, 0])).a)
	_red.visible = true
	var tw := create_tween()
	tw.tween_property(_red, "color:a", 0.0, float(fl.get("sec", 0.3)))
	await tw.finished
	_red.visible = false


func _kill(m: AnimPlayer) -> void:
	m.playing = false
	m.modulate = Color(4, 4, 4, 1)
	await create_tween().tween_property(m, "modulate:a", 0.0, 0.6).finished   # 淡出 0.6 秒 (实测: 守方倒下 1.96~2.56 s)


# ---------------- 信息栏与伤害数字 ----------------
# 依据原版; 坐标取自布局表 closeup.* (缺省为原版值):
#   信息栏 = Fig_misc 第 0 帧 (左下, 敌方) / 第 1 帧 (右上, 我方), 有效区 104x26, 屏幕位置 (0,174) / (216,0)
#   名字 12 号统一排版 (UiText), 栏内 (1,1) / (56,1), 色 0x7772, 左右各 1 像素 0x842 描边 (样式 5, 布局 text_styles.edge5)
#   体力条最长 100 像素、高 2 (栏内 y=14~15), 左栏从 x=2 向右长, 右栏从 x=101 向左长
#   体力数字 Fig_misc 第 3 帧字模 (8x7, 步进 7): 当前 "%4d" 在 x=4/36, 上限 "%d" 在 x=39/71, y=18
#   每次命中扣 伤害/命中帧数 (立即), 红色残条每周期追 2% 上限; 命中时白闪 2 周期:
#     调 (栏内 (1,13)-(102,16), 白 0x7fff, = (10,12),(6,12)): 用 建的
#     比例表 T_k[c] = c*k/16, 结果 = 底色*12/16 + 白*10/16 (第 1 周期) / 白*6/16 (第 2 周期), 饱和相加。布局 closeup.hpbar.flash
#   攻击动画放完后弹伤害数字 (Fig_misc 第 4 帧红字, 只有数字无正负号), 中心 (117,77) 左方 / (213,123) 右方

class InfoPanel:
	extends Node2D
	var right := false
	var unit_name := ""
	var hp_max := 1
	var shown := 0.0      # 原版 字段: 当前显示的体力 (数字与黄条)
	var trail := 0.0      # 原版 字段: 红色残条
	var flash := -1       # 原版 字段/字段: 命中白闪的周期
	var rise_to := -1.0   # >= 0: 体力正在涨向这个值 (heal)
	var _t := 0.0
	var _side := "left"
	var _size := Vector2.ZERO   # 有效区 (四角定界点不画)
	var _panel := {}
	var _flash_add: Node2D  # 白闪的加色层 (饱和相加, BLEND_ADD)
	var _flash_rect := Rect2()
	var _flash_keep := 16.0
	var _flash_add16: Array = []
	var _bar_pos := Vector2.ZERO   # 体力条起点 (左栏左端 / 右栏右端)
	var _bar_size := Vector2.ZERO  # 最长、高
	var _bar_grow := 1             # +1 向右长, -1 向左长
	var _bar_tip: Array = []       # 尖头渐变色 (最外端起)
	var _bar_body := Color.WHITE
	var _trail_color := Color.RED
	var _hp: UiNumber
	var _hp_max: UiNumber

	func _init(r: bool, nm: String, hp: int, mx: int) -> void:
		right = r
		unit_name = nm
		hp_max = maxi(1, mx)
		shown = hp
		trail = hp
		_side = "right" if r else "left"
		var pid := "closeup.panel." + _side
		position = UiLayout.at(pid)
		_size = UiLayout.size_of(pid)
		UiLayout.tag(self, pid, Rect2(Vector2.ZERO, _size))
		_panel = UiPanel.frame_texture(String(UiLayout.sprite(pid)["anim"]), UiLayout.frame(pid))
		add_child(UiText.make("closeup.name." + _side, nm))
		var bid := "closeup.hpbar." + _side
		_bar_pos = UiLayout.at(bid)
		_bar_size = UiLayout.size_of(bid)
		_bar_grow = -1 if String(UiLayout.val(bid, "bar", {}).get("grow", "right")) == "left" else 1
		var cols: Array = UiLayout.data().get("colors", {}).get("closeup.hpbar", {}).get("rgb", [])
		_bar_tip = cols.slice(0, cols.size() - 1).map(func(c): return UiLayout.color(c))
		_bar_body = UiLayout.color(cols[-1]) if not cols.is_empty() else Color.WHITE
		_trail_color = UiLayout.color("closeup.hpbar_trail")
		var fl: Dictionary = UiLayout.el("closeup.hpbar.flash")
		_flash_rect = UiLayout.rect("closeup.hpbar.flash")
		var bl: Dictionary = fl.get("blend", {})
		_flash_keep = float(bl.get("dst16", 16))
		_flash_add16 = bl.get("add16", [])
		_flash_add = Node2D.new()
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_flash_add.material = m
		_flash_add.draw.connect(_draw_flash_add)
		add_child(_flash_add)
		_hp = UiLayout.number("closeup.hp." + _side)
		_hp_max = UiLayout.number("closeup.hp_max." + _side)
		add_child(_hp)
		add_child(_hp_max)
		_refresh_numbers()

	func _draw_flash_add() -> void:
		if flash >= 0 and flash < _flash_add16.size():
			var k := float(_flash_add16[flash]) / 16.0
			_flash_add.draw_rect(_flash_rect, Color(k, k, k))

	## 一次命中: 立即扣 amount, 红条留在原处慢慢追; keep_one: 不致死的攻击最少留 1
	func hit(amount: float, keep_one: bool) -> void:
		shown = maxf(0.0, shown - amount)
		if rise_to >= 0.0:   # 吸血的体力还在涨时被打: 涨的终点跟着降, 继续涨 (原版: 反击命中后黄条接着涨)
			rise_to = maxf(shown, rise_to - amount)
		if keep_one and int(shown) == 0:
			shown = 1.0
		flash = 0
		_refresh_numbers()
		queue_redraw()
		_flash_add.queue_redraw()

	func set_hp(v: int) -> void:
		shown = v
		trail = maxf(trail, shown)
		rise_to = -1.0
		_refresh_numbers()
		queue_redraw()

	## 吸血 / 回复: 体力 (数字与黄条) 每周期涨 2% 上限, 涨到 shown+amount (把 字段 设成 字段+量; 原版 逐帧: 上限 71 时每周期约 1.4)
	func heal(amount: int) -> void:
		rise_to = minf(float(hp_max), shown + amount)

	## 当前 %4d、上限 %d, 超过 9999 写 "????"
	func _refresh_numbers() -> void:
		_hp.text = UiDigits.fmt(int(shown), UiLayout.fmt_width("closeup.hp." + _side, 4))
		_hp_max.text = "????" if hp_max > 9999 else str(hp_max)

	func _process(delta: float) -> void:
		_t += delta
		while _t >= AnimPlayer.TICK:
			_t -= AnimPlayer.TICK
			if rise_to >= 0.0:
				shown = minf(rise_to, shown + 2.0 * hp_max * 0.01)
				trail = shown
				if shown >= rise_to:
					rise_to = -1.0
				_refresh_numbers()
				queue_redraw()
			elif trail > shown:
				trail = maxf(shown, trail - 2.0 * hp_max * 0.01)
				queue_redraw()
			elif trail < shown:
				trail = shown
			if flash >= 0:
				flash += 1
				if flash >= _flash_add16.size():
					flash = -1
				queue_redraw()
				_flash_add.queue_redraw()

	func _len(v: float) -> int:
		return int(v / hp_max * _bar_size.x)

	## 从条的起点数第 a~b 个像素 (含两端), 按生长方向换算成栏内 x
	func _seg(a: int, b: int, c: Color) -> void:
		if b < a:
			return
		var x1 := _bar_pos.x + a if _bar_grow > 0 else _bar_pos.x - b
		draw_rect(Rect2(x1, _bar_pos.y, b - a + 1, _bar_size.y), c)

	func _draw() -> void:
		if not _panel.is_empty():
			var sc := float(_panel["scale"])
			var tex: Texture2D = _panel["texture"]
			texture_filter = TextureSource.filter_for(_panel["hd"])
			# 有效区 _size, 四角是 SAF 的定界点 (不画)
			var w := _size.x
			var h := _size.y
			var e := 1.0  # 定界点 1 像素
			for r in [Rect2(0, e, w, h - e - e), Rect2(e, 0, w - e - e, e), Rect2(e, h - e, w - e - e, e)]:
				draw_texture_rect_region(tex, r, Rect2(r.position / sc, r.size / sc))
		var lt := _len(trail)
		if trail != shown and lt > 0:
			_seg(0, lt - 1, _trail_color)
		# 生长端 4 像素是渐变尖头 (最外端最暗), 其余亮黄
		var l := _len(shown)
		var tip := mini(_bar_tip.size(), l)
		_seg(0, l - 1 - tip, _bar_body)
		for i in tip:
			_seg(l - 1 - i, l - 1 - i, _bar_tip[i])
		if flash >= 0:  # 白闪第一步: 底色 * dst16/16 (加色层随后叠白)
			draw_rect(_flash_rect, Color(0, 0, 0, 1.0 - _flash_keep / 16.0))


func _build_info(side: String, u: BattleUnit) -> void:
	var p := InfoPanel.new(side == "right", u.name_text, u.hp, u.hp_max)
	_ui.add_child(p)
	_sides[side]["panel"] = p


## 攻击放完后在守方身上弹伤害数字并等它结束
func _jump(sd: Dictionary, dmg: int, digits := true) -> void:
	if not digits:
		return
	var left: bool = sd == _sides.get("left")
	var n := DamageDigits.new(str(dmg), "closeup.damage.left" if left else "closeup.damage.right")
	_ui.add_child(n)
	await n.done
	n.queue_free()



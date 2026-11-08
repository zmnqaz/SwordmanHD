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
var _stage: Node2D       # 人物 / 特效层
var _bgm: Node2D         # 背景层 (本关 FLOOR 底图); 震屏时永远跟着震
var _bgg: Node2D         # 背景残影层 (unk4 bit0 时震屏中在「上一级偏移」处半透明再画一遍)
var _stage_base := Vector2.ZERO   # _stage 的静止位置 (震屏在它上面加偏移)
var _shake_id := 0   # 震屏的编号
var _black: ColorRect
var _tint_top: ColorRect   # 色闪 级 4: 盖住所有东西 (含人物 / 特效), 加色
var _tint_mid: ColorRect   # 色闪 级 1 / 3: 背景之上、人物之下, 加色
var _tint_id := {3: 0, 4: 0}   # 各层色闪的编号 (新一次色闪作废旧的)
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
	_stage_base = _stage.position
	_root.add_child(_stage)
	for n in ["_bgm", "_bgg"]:   # 背景层与人物层同一坐标系, 排在人物层之下
		var bg := Node2D.new()
		bg.scale = _stage.scale
		bg.position = _stage_base
		_root.add_child(bg)
		set(n, bg)
	_root.move_child(_bgm, 0)
	_root.move_child(_bgg, 1)   # 残影在背景之上
	_bgg.visible = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_tint_top = ColorRect.new()
	_tint_top.size = UiLayout.base_size() * Assets.SCALE
	_tint_top.material = add
	_tint_top.visible = false
	add_child(_tint_top)
	ScreenLayout.cover(_tint_top, 2048.0)
	_tint_mid = ColorRect.new()
	_tint_mid.size = UiLayout.base_size() * Assets.SCALE
	_tint_mid.position = _stage_base
	_tint_mid.material = add
	_tint_mid.visible = false
	_root.add_child(_tint_mid)
	_root.move_child(_tint_mid, 2)   # 背景 (0) / 残影 (1) 之后, 人物层之前
	_ui = Node2D.new()
	_ui.scale = Vector2.ONE * Assets.SCALE
	add_child(_ui)
	_text = Node2D.new()
	add_child(_text)


static func anim_exists(dir: String) -> bool:
	return Assets.exists(dir + "/anim.json")


static func misc_dir(u: BattleUnit) -> String:
	var s := int(u.info["sprite"])
	return ThemeAssets.f("unit_misc", [s, s])


## 单位在近景里会用到的动画目录 (待机/受击 misc + 普攻命中 a / 被闪被挡 ab), 预取与预热用 (近景攻击动画一套上百张贴图, 现载入会卡)
static func unit_anims(u: BattleUnit) -> Array:
	var s := int(u.info["sprite"])
	return [misc_dir(u), ThemeAssets.f("unit_attack", [s, s, "a"]), ThemeAssets.f("unit_attack", [s, s, "ab"])]


## 开战后在后台预取场上各单位的近景动画 (我方排前面), 第一次出手不用现载入; 中途出场的单位靠 open 开场的同步预热
static func prefetch_units(units: Array) -> void:
	var dirs: Array = []
	for u in units.filter(func(x): return x.camp == 0) + units.filter(func(x): return x.camp != 0):
		dirs += unit_anims(u)
	_load_anims(dirs, false)


## now: 立即载入 (近景开场画面静止时); 否则后台预取
static func _load_anims(dirs: Array, now: bool) -> void:
	Assets.load_anims(dirs, now)


## 被打方反应 (姿势 + 位移, 原版逐 tick 复刻, 见 HitReaction; 差异): 每侧一个, 命中帧调 _react, 一个 tick 循环驱动到回待机。
## 取代原先的固定 1 → 2 → 1 → 2 受击摆动 (12 tick)、格挡帧 0 交替 (初版)、命中帧当场起位移
var _reacts := {}        # 守方 misc 播放器的 instance id -> HitReaction
var _react_frame := {}   # instance id -> 当前摆着的反应帧 (−1 = 待机)


func _react(dmisc, dir: String, left: bool, h: int, time: int, ab: bool) -> void:   # dmisc 是 AnimPlayer
	var id: int = dmisc.get_instance_id()
	var r: HitReaction = _reacts.get(id)
	if r == null:
		r = HitReaction.new(left)
		_reacts[id] = r
	var running := r.pose != HitReaction.IDLE or r.offset != Vector2.ZERO
	r.hit(h, time, ab)
	_react_apply(dmisc, dir, r)
	if not running:
		_react_loop(dmisc, dir, r)


func _react_loop(dmisc, dir: String, r: HitReaction) -> void:
	while true:
		await get_tree().create_timer(1 / 25.0).timeout
		if not is_instance_valid(dmisc) or not is_inside_tree():
			return
		var going := r.tick(dmisc.visible)
		_react_apply(dmisc, dir, r)
		if not going:
			return


func _react_apply(dmisc, dir: String, r: HitReaction) -> void:
	dmisc.position = r.offset
	var id: int = dmisc.get_instance_id()
	var f := r.frame()
	if int(_react_frame.get(id, -1)) == f:
		return
	_react_frame[id] = f
	if f >= 0:
		dmisc.play(dir, f, f + 1)
	elif not dmisc.data.is_empty():   # 个别单位没有近景 misc 动画: 没有待机可回
		var idl := idle_frame(dmisc.data)
		dmisc.start_at = 1   # 原版实测: 受击后回到待机的第 2 帧 (不是第 1 帧), 之后仍按 3 tick 一帧
		dmisc.play(dir, idl.x, idl.y)


## 攻击动画放完 / 结算: 所有反应立即作废、位移归零 (之后调用方自己摆待机 / 倒下)
func _react_reset_all() -> void:
	for id in _reacts:
		(_reacts[id] as HitReaction).reset()
		var m = instance_from_id(id)
		if is_instance_valid(m):
			m.position = Vector2.ZERO
	_react_frame.clear()


## 命中震屏 (原版 cfigthe 读内存查表, 静态观察 第 3 节): 逐级偏移 (原版像素), 每级 2 tick;
## 命中帧头 shake=0 或 >12 不震; 与命中与否无关 (未命中 / 格挡也震); 相邻震屏帧后者打断前者从头来。播放时前面还有 2 tick 的零偏移 (见 _shake)。
## **方向** = (shake-1)/3 取整: 0 上, 1 下, 2 左上, 3 右下; **幅度序列** = (shake-1)%3: 0 → 3,2,1 (6 tick), 1 → 6,4,2,1 (8 tick), 2 → 12,6,4,1 (8 tick)。
## 旧的窗口实测 (5/6/9/11 记成 6,5,3,1) 是背景条带上主层 + 50% 残影层互相关的平均, 以读表为准。
## 作用对象 (unk4): 背景永远震; 人物 / 攻击动画层仅 bit1 (2, 3) 时跟着震; bit0 (1, 3) 时背景在「上一级偏移」处再叠一层 50% 残影 (第一级残影在 0)。
static func shake_offsets(shake: int, _unk4 := 0) -> Array:
	if shake <= 0 or shake > 12:
		return []
	var amps: Array = [[3, 2, 1], [6, 4, 2, 1], [12, 6, 4, 1]][(shake - 1) % 3]
	var d: Vector2 = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, 1)][(shake - 1) / 3]
	var out := []
	for n in amps:
		out.append(d * float(n))
	return out


const SHAKE_STEP := 0.08   # 每级 2 tick
const DIGIT_LEAD := 0.12   # 回待机到伤害数字弹出 3 tick


func _shake(shake: int, unk4: int) -> void:
	_shake_id += 1
	var id := _shake_id
	var offs := shake_offsets(shake)
	var k := _stage.scale   # 偏移是原版像素, 节点位置在放大后的坐标里 (倍数 = Assets.SCALE)
	var steps := offs.size() + (1 if unk4 & 1 else 0)   # 残影层比主层晚一级结束 (Windows 直读: 残影变量比主层晚 2 tick)
	for i in steps:
		var o: Vector2 = offs[i] if i < offs.size() else Vector2.ZERO   # 主层从命中帧那个 tick 就开始偏移 (没有零前导)
		_bgm.position = _stage_base + o * k
		if unk4 & 2:
			_stage.position = _stage_base + o * k
		if unk4 & 1:
			_bgg.visible = true
			_bgg.position = _stage_base + (offs[i - 1] if i > 0 else Vector2.ZERO) * k
		await get_tree().create_timer(SHAKE_STEP).timeout
		if id != _shake_id or not is_inside_tree():
			return
	_bgm.position = _stage_base
	_stage.position = _stage_base
	_bgg.visible = false


static func idle_frame(data: Dictionary) -> Vector2i:
	var c: Array = data["action_counts"]
	var f := 6 + (int(c[0]) if int(c[0]) > 0 else 1)
	return Vector2i(f, f + maxi(1, int(c[1])))


## 守方 misc 能不能挂到攻击动画上 (攻击动画 ref 部件画守方 + 命中窗口 c[1]..c[2] 藏守方本体)。原版近景初始化:
##   [字段] = 守方 misc 头计数 [2] != 0; 为 1 时 挂空 ((0, 0), 绘制 没有 other 就跳过 ref 部件),
##   也不在命中窗口里藏守方 —— 心脏 / 魔神等大体型 (misc 是整屏大图、原点 (0,0)) 一直用自己的 misc 帧站在原位受击。
##   复刻原先一律挂上, 心脏的 330x216 整屏图被画到 ref 部件的 (106,57) / (99,59), 画面整块错位乱跳 (玩家反馈第 33 幕飞星神剑打心脏)
static func defender_attaches(misc_data: Dictionary) -> bool:
	var c: Array = misc_data.get("action_counts", [])
	return c.size() < 3 or int(c[2]) == 0


## 打开画面: a 攻击 t; 返回后可多次 strike, 最后 close
## t = null: 施放者单人近景 (battle_type 2 绝技, 见 cast_solo), 底图取 at 格 (没给就取施放者所在格)
## hide_target: 远程技能 (battle_ranged = 1, 如无方飞剑) 从开场起守方就不在画面里, 命中帧才出现 (见 strike 的 ranged), 否则放大淡入和闪光期间守方先露脸再消失
## extra_anims: 这次还会放的其他动画 (技能出手 / 单人近景), 与双方普攻动画一起在开场前预热
func open(a: BattleUnit, t: BattleUnit, at := Vector2i(-1, -1), hide_target := false, extra_anims: Array = []) -> void:
	# 开场先把这次要放的动画贴图全部载入: 原版确认后地图本来就静止 3 tick (见下), 卡在这里看不出; 放到攻击动画中途现载入会一次跨过多帧
	var warm: Array = extra_anims + [ThemeAssets.f("cast_flash", ["l"]), ThemeAssets.f("cast_flash", ["r"])]
	for u in [a, t]:
		if u != null:
			warm += unit_anims(u)
	_load_anims(warm, true)
	for c in _stage.get_children() + _bgm.get_children() + _bgg.get_children():
		c.queue_free()
	_shake_id += 1   # 上一次近景没震完的收尾作废, 各层回原位
	_bgm.position = _stage_base
	_bgg.position = _stage_base
	_bgg.visible = false
	_stage.position = _stage_base
	for c in _ui.get_children():
		c.queue_free()
	for c in _text.get_children():
		c.queue_free()
	_sides.clear()
	var floor_dir: String = bs.st.battle_floor
	if floor_dir != "" and anim_exists(floor_dir):
		var fl := AnimPlayer.new()
		var cell: Dictionary = bs.st.cell(at.x, at.y) if at.x >= 0 else (bs.st.cell(t.cx, t.cy) if t != null else bs.st.cell(a.cx, a.cy))
		var fd := Assets.anim(floor_dir)
		var ff := clampi(int(cell.get("floor", 0)), 0, fd["frames"].size() - 1)
		fl.show_frame(floor_dir, ff)
		_bgm.add_child(fl)
		_bgg.add_child(fl.duplicate())   # 残影层: 同一张底图
		_bgg.modulate.a = 0.5
	for u in [a, t]:
		if u == null:
			continue
		var side := "left" if u.camp == 1 else "right"
		if _sides.has(side):  # 同阵营互打 (理论上不会), 退回按攻守分边
			side = "left" if u == t else "right"
		var m := AnimPlayer.new()
		m.play_sound = false
		_stage.add_child(m)
		var md := misc_dir(u)
		if anim_exists(md):
			var r := idle_frame(Assets.anim(md))
			m.play(md, r.x, r.y)
		_sides[side] = {"unit": u, "misc": m, "dir": md, "ranged": int(u.info.get("attack_type", 0)) == 1}   # ranged: 本侧出手是远程 (strike 时按实际出手改写, 见 exp_pose)
		_build_info(side, u)
		m.visible = not (hide_target and u == t)
	var z := UiLayout.el("closeup.zoom")
	# 原版实测 (U5): 确认后先 3 tick 地图不变, 再 7 tick 地图 -> 近景交叉淡入 (开场带 1.175 倍 -> 1 倍缩放), 稳定 2 tick 后攻击动画才开始
	_root.scale = Vector2.ONE * float(z.get("scale", 1))
	_root.modulate.a = float(z.get("alpha", 1))
	_black.modulate.a = float(z.get("alpha", 1))
	visible = true
	if float(z.get("lead", 0.0)) > 0.0:
		visible = false
		await create_tween().tween_interval(float(z["lead"])).finished
		visible = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_root, "scale", Vector2.ONE, float(z.get("sec", 0)))
	tw.tween_property(_root, "modulate:a", 1.0, float(z.get("sec", 0)))
	tw.tween_property(_black, "modulate:a", 1.0, float(z.get("sec", 0)))
	await tw.finished
	if float(z.get("settle", 0.0)) > 0.0:
		await create_tween().tween_interval(float(z["settle"])).finished


## 闭场: 7 tick 交叉淡出回地图, 不缩放 (原版实测 U5)
func close() -> void:
	var z := UiLayout.el("closeup.zoom")
	var tw := create_tween().set_parallel()
	tw.tween_property(_root, "modulate:a", 0.0, float(z.get("sec", 0)))
	tw.tween_property(_black, "modulate:a", 0.0, float(z.get("sec", 0)))
	await tw.finished
	visible = false
	_black.modulate.a = 1.0


func _side_of(u: BattleUnit) -> String:
	return "left" if _sides.has("left") and _sides["left"]["unit"] == u else "right"


## 攻击方 a 对 d 的一次出手; results 为 BattleRules.strike 的结果, 伤害已由调用方算好但尚未扣除
## skill_name: 物理绝技的技能名, 近景里和闪光同一刻起在顶部出一块技能名横幅 (敌我一样); 普攻/反击为空
## vampire: 武器吸血 (附加类型 0) 命中时的吸血量 / 摄魂鬼触的术力实涨量 (Skills.closeup_drain), -1 = 没触发; 触发了 (吸到 0 也算) 在最后一击的伤害数字之后放吸血表现 (见 _vampire)
## digits: 守方弹不弹伤害数字 (物理绝技的结果记录不带伤害数值标志 (Skills.shows_damage) 时近景里也不弹, 如摄魂鬼触, 实测)
## vampire_hp: 吸取表现的蓝数字是否同时把攻方体力条涨上去 (武器吸血 true; 摄魂鬼触吸的是术力, 近景信息栏只有体力, 条不动)
func strike(a: BattleUnit, d: BattleUnit, results: Array, skill_anim := "", skill_name := "", vampire := -1, digits := true, ranged := false, vampire_hp := true) -> void:
	var asd: Dictionary = _sides[_side_of(a)]
	var dsd: Dictionary = _sides[_side_of(d)]
	var kind: String = results[0]["kind"]
	var sp := int(a.info["sprite"])
	var atk_dir := ThemeAssets.f("unit_attack", [sp, sp, "ab" if kind in ["miss", "guard"] else "a"])
	if skill_anim != "" and anim_exists(skill_anim):
		atk_dir = skill_anim
	asd["ranged"] = ranged
	asd["misc"].visible = true   # 上一击是对方的远程攻击时本方被藏着 (见 _play_attack 末尾), 轮到本方出手 (如反击) 先现身
	if ranged:
		dsd["misc"].visible = false   # 调用方没在 open 时藏 (hide_target) 也兜住: 闪光期间守方不露脸
	else:
		dsd["misc"].visible = true
	if skill_name != "":
		bs.ctl.view.cast_banner(skill_name, _ui)
	# Sp000: 原版种类 3 4 5 7 8 9 (会心 / 连击, 含被格挡的) 与技能都放; 复刻原先只看 "critical" / "double", 格挡 + 会心 / 连击漏放
	if kind in ["critical", "double"] or bool(results[0].get("crit", false)) or results.size() > 1 or skill_anim != "":
		var fx := AnimPlayer.new()
		_stage.add_child(fx)
		fx.play(ThemeAssets.f("cast_flash", ["l" if _side_of(a) == "left" else "r"]), 0, -1, false)
		if skill_name != "":
			# 带技能名横幅时 Sp000 不挡出手: 原版近景状态 3 起 Sp000 并置阻塞标志 [+9], 但横幅滑入一结束 就无条件清掉 [+9],
			# 于是 Sp000 放到第 3 帧时攻击动画已经开始, 光效叠在出手上继续放完。原版 直读近景对象 (破魔杵): Sp000 第 0 帧 tick 12、
			# 横幅滑入完 tick 17 清 [+9]、tick 18 进出手状态 5, Sp000 放到 tick 31; 摄魂鬼触同样 6 tick 后出手。会心 / 连击没有横幅, 照旧等 Sp000 放完
			fx.finished.connect(fx.queue_free)
			await create_tween().tween_interval(UiSlide.TICK * banner_in_ticks()).finished
		else:
			await fx.finished
			fx.queue_free()
			await create_tween().tween_interval(UiSlide.TICK).finished   # 光效放完空 1 tick 才出手 (原版实测 U5: Sp000 11..29, 31 出手)
	# 连击 (原版近景准备): 每遍扣 [字段] = 总伤 / 2, 数字也读它 —— 两遍放完只弹一次, 数值是**每遍**的伤害;
	# 第一遍就致死也照放第二遍 (实测 U4 combokill: 体力 1 的敌人两遍 31~89 / 91~149 都放, 182 才渐隐; 差异)
	var real_total := 0
	for r in results:
		real_total += int(r["damage"])
	real_total = int(results[0].get("total", real_total))   # 连击结果带真实总伤 (BattleRules.strike_kinds)
	if gc.god and d.camp != 1:
		real_total = 0
	var hp_final := maxi(0, (dsd["panel"] as InfoPanel).hp_exact - real_total)
	for i in results.size():
		if i > 0:
			await create_tween().tween_interval(UiSlide.TICK).finished   # 两遍之间空 1 tick (原版 实测: 回待机 99, 100 再出手)
		await _play_attack(a, d, asd, dsd, atk_dir, results[i], vampire, i == results.size() - 1, digits, ranged, int(results[-1]["damage"]), vampire_hp, hp_final)


## 技能名横幅滑入的 tick 数 (演出表 banner.in 的步数, 原版 5 步 + 判到 0 的那一 tick = 6): 横幅滑入结束时原版清近景阻塞标志, 见 strike
static func banner_in_ticks() -> int:
	return maxi(1, (CastFx.section("banner").get("in", {}).get("dy", []) as Array).size())


## 近景里弹经验框前的站位 (原版近景状态 0x13): 右侧 (玩家) 单位挣到经验时先把它显示出来 ([字段] = 1),
##   它这次出手是远程 ([字段] == 1) 再把左侧单位藏起来 ([字段] = 0) —— 即镜头回到远程出手的第一段 (攻方一侧, 守方不在)。
##   原版 直读 (真胤破魔杵): 伤害数字期间攻方藏、守方在, 经验框那一刻起攻方现身、守方消失, 直到近景关闭。没挣经验不动
func exp_pose(u: BattleUnit) -> void:
	if not visible or not _sides.has("right") or _sides["right"]["unit"] != u:
		return
	_sides["right"]["misc"].visible = true
	if bool(_sides["right"].get("ranged", false)) and _sides.has("left"):
		_sides["left"]["misc"].visible = false


## 施放者单人近景 (battle_type 2 绝技, 如电射星驰: 殷剑平放下剑匣、御剑, 随后才转到地图放全屏特效): 闪光 + 施放者的 NNN[-n]s 动画, 没有守方、没有伤害; 原版这里没有技能名横幅 (的横幅标志传 0, 调用方传空名)
## (结果在回到地图后由 SM 演出和结果动画给)。skill_anim 缺文件就什么都不放。原版依据: ③ (分 2 = 近景 + 地图 SM)
func cast_solo(a: BattleUnit, skill_anim: String, skill_name: String) -> void:
	if not anim_exists(skill_anim):
		return
	var asd: Dictionary = _sides[_side_of(a)]
	var amisc = asd["misc"]
	if skill_name != "":
		bs.ctl.view.cast_banner(skill_name, _ui)
	var fx = amisc.get_script().new()   # 同施放者 misc 的播放器类 (引擎层不直接写 AnimPlayer 类名, 见 test_engine_deps)
	_stage.add_child(fx)
	fx.play(ThemeAssets.f("cast_flash", ["l" if _side_of(a) == "left" else "r"]), 0, -1, false)
	await fx.finished
	fx.queue_free()
	var atk = amisc.get_script().new()
	_stage.add_child(atk)
	amisc.visible = false
	atk.play(skill_anim, 0, -1, false)
	await atk.finished
	atk.queue_free()
	amisc.visible = true
	var ia := idle_frame(amisc.data) if not amisc.data.is_empty() else Vector2i(0, 1)
	amisc.play(asd["dir"], ia.x, ia.y)


## vamp: 吸血量 (-1 没触发); 只在最后一遍后演
## digit_total: 连击两遍放完后伤害数字只弹一次 (原版实测 U4: 数字和渐隐只在两遍都放完后各出一次), 数值是每遍的伤害 (原版 [字段])
## hp_final: 这次出手结算后的真实体力 (−1 = 按本遍伤害算); 倒下只在最后一遍后按它判, 体力条保留 1 点也按它 (原版 [字段] 在开近景时定)
func _play_attack(a: BattleUnit, d: BattleUnit, asd: Dictionary, dsd: Dictionary, atk_dir: String, r: Dictionary, vamp := -1, last := true, digits := true, ranged := false, digit_total := -1, vamp_hp := true, hp_final := -1) -> void:
	r = r.duplicate()
	if gc.god and d.camp != 1:
		r["damage"] = 0
	var dmisc: AnimPlayer = dsd["misc"]
	var amisc: AnimPlayer = asd["misc"]
	var panel: InfoPanel = dsd["panel"]
	var hp_before := panel.hp_exact   # 结算用的真实体力 (显示的 shown 是原版 32 位浮点逐命中帧扣的, 可能比它少 1, 见 InfoPanel.hit)
	# 伤害数字与扣血量都用完整伤害值, 不封顶为当前血量 (体力条 hit() 自行截到 0); 数字取
	# 结算记录的伤害 (存未截断值), 04_伤害.md §2.1
	var dmg := int(r["damage"])
	var hp_after := maxi(0, hp_before - dmg)
	if hp_final >= 0 and last:
		hp_after = hp_final
	var survives := hp_after > 0 if hp_final < 0 else hp_final > 0
	var dies := last and hp_after <= 0
	var drain := vamp if last else -1   # 本击后要演的吸血
	var show_digits := digits and last   # 连击: 数字只在最后一遍弹一次
	var digit_value := 0 if (gc.god and d.camp != 1) else (digit_total if digit_total >= 0 else dmg)
	if not anim_exists(atk_dir):
		dmisc.visible = true   # 远程技能开场藏了守方, 没有攻击动画 (没有命中帧去放它出来) 就直接现身
		panel.hit(dmg, survives)
		panel.set_hp(hp_after)
		await _jump(dsd, digit_value, show_digits)
		if drain >= 0:
			await _vampire(asd, drain, vamp_hp)
		return
	var atk := AnimPlayer.new()
	var attach := defender_attaches(dmisc.data)
	if attach:
		atk.other = dmisc   # 攻击动画的 ref 部件画守方; 大体型 (见 defender_attaches) 不挂, ref 部件不画
	_stage.add_child(atk)
	amisc.visible = false
	var data := Assets.anim(atk_dir)
	var c: Array = data["action_counts"]
	var hits := 0
	for i in data["frames"].size():
		if int(data["frames"][i]["hit"]) > 0:
			hits += 1
	# 远程 (技能表 battle_ranged = 1 如无方飞剑 / 破魔杵, 或远程单位的普攻): 出手一侧那段守方不在画面里 (用户 2026-10-29 指出无方飞剑发剑气时画面里不该有怪)
	var hide_until := ranged_hide_until(data) if ranged else -1
	var on_frame := func(f: int):
		var hide_def := (attach and int(c[1]) > 0 and f >= int(c[1]) and f < int(c[2])) or f < hide_until
		dmisc.visible = not hide_def
		var cc := color_code(int(data["frames"][f]["color"]))   # 帧头的 color 字段: 近景色闪 (与命中结果无关, 每个有 color 的帧都触发)
		if not cc.is_empty():
			_color_flash(int(cc[0]), int(cc[1]))
		if int(data["frames"][f]["shake"]) > 0:   # 帧头的震动字段: 命中震屏 (原版逐帧实测, 见 shake_offsets)
			_shake(int(data["frames"][f]["shake"]), int(data["frames"][f]["unk4"]))
		if int(data["frames"][f]["hit"]) > 0:
			var ab: bool = r["kind"] in ["miss", "guard"]
			_react(dmisc, dsd["dir"], _side_of(d) == "left", int(data["frames"][f]["hit"]), int(data["frames"][f]["time"]), ab)   # 姿势 + 位移 (HitReaction)
			if ab:  # 闪避/格挡
				if r.get("crit", false):   # 格挡 + 会心 = 白闪 (原版 kind 7 / 9 只走白闪块, 不红)
					_flash()
				elif not r.get("flash", {}).is_empty():
					_flash_red(r["flash"])
			elif r["kind"] == "critical":
				_flash()
			# (本侧) / (对侧): 每个命中帧扣 伤害/命中帧数; 体力条白闪 在扣血判断之外, 闪避 0 伤也闪
			panel.hit(float(dmg) / maxi(1, hits), survives)
	atk.frame_shown.connect(on_frame)
	atk.play(atk_dir, 0, -1, false)
	await atk.finished
	_react_reset_all()   # 还没收的受击 / 格挡反应作废 (下面直接回待机 / 倒下)
	atk.queue_free()
	# 远程攻击 (攻击动画第二段已切到守方一侧, 攻方不再画): 放完后攻方继续不露面, 伤害数字 / 倒下都在守方这边演 (玩家 2026-11-03 指出远程怪在扣血时又冒出来);
	# 之后若有反击, strike 开头会让出手方现身
	amisc.visible = not ranged
	dmisc.visible = true
	var ia := idle_frame(amisc.data) if not amisc.data.is_empty() else Vector2i(0, 1)
	amisc.play(asd["dir"], ia.x, ia.y)
	panel.hp_exact = hp_after   # 显示不对齐到真实值: 原版近景体力 (字段) 只在开近景时写, 命中帧按 伤害/帧数 的 32 位浮点扣, "%4d" 取整显示
	if dies:
		await _jump(dsd, digit_value, show_digits)
		await _kill(dmisc)
		if drain >= 0:
			await _vampire(asd, drain, vamp_hp)   # 先演倒下再吸血 (状态 7 死亡淡出 -> 状态 8/9, 实测: 淡出放完光环才出)
	else:
		var idl := idle_frame(dmisc.data)
		dmisc.play(dsd["dir"], idl.x, idl.y)
		# 伤害数字只看结算值: 命中/会心/格挡/闪避都走这里, 闪避就是红字「0」(原版实测); 不出「閃避」之类的文字
		await _jump(dsd, digit_value, show_digits)
		if drain >= 0:
			await _vampire(asd, drain, vamp_hp)


## 远程出手时守方藏到第几帧 (不含): 动画 action_counts[0] 是「攻方一侧」那段的帧数 (远程动画才有, 之后切到守方一侧), 有就藏到它;
## 没有 (0) 才退回第一个命中帧。原版破魔杵 (真胤 006s, [15, 45, 69]) 第 15 帧切到守方一侧红幕时守方就现身 (实测 ④),
## 第 44 帧才命中; 复刻原先一律藏到第一个命中帧, 整段红幕守方都不在 (玩家 2026-11-06 反馈「发破魔杵时对方人不见了」)。
## 其它远程动画这段末尾与第一个命中帧只差 0~5 帧 (001s 38/39、230a 11/13、234a 25/26、242s 10/15)
static func ranged_hide_until(data: Dictionary) -> int:
	var c: Array = data.get("action_counts", [])
	if not c.is_empty() and int(c[0]) > 0:
		return int(c[0])
	var frames: Array = data.get("frames", [])
	for i in frames.size():
		if int(frames[i]["hit"]) > 0:
			return i
	return -1


## 武器吸血的表现 (原版近景状态 8 / 9, 实测 2026-10-18, 差异): 命中且触发吸血就放, 吸到 0 (攻方满血) 一样放:
##   伤害数字 (或守方倒下淡出) 放完 delay 秒后, 攻击方身上放特效 Misc/Sp001r (攻方在右) / Sp001l (攻方在左) —— 近景构造里 "MISC\\SP%03dR/L.SAF" 按
##   武器附加特效号 (吸血 = 1) 载入的红色收拢光环 (8 帧 x 2 tick = 0.64 秒, 首帧淡入); 光环放完 digit_delay 秒后弹蓝色吸血量数字,
##   攻方体力条与数字同时按每周期 2% 上限涨上去 (InfoPanel.heal); 数字放完才往下 (敌方反击在这之后)
## heal_hp = false: 只放光环和蓝数字, 体力条不动 (摄魂鬼触吸术)
func _vampire(asd: Dictionary, amount: int, heal_hp := true) -> void:
	asd["misc"].visible = true   # 远程攻击后攻方被藏着 (_play_attack), 吸血光环在它身上放要露面
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
	if heal_hp:
		panel.heal(amount)
	var n := DamageDigits.new(str(amount), "closeup.damage.left" if left else "closeup.damage.right", true)
	_ui.add_child(n)
	await n.done
	n.queue_free()


## 升级演出 (原版近景状态 0x12 / 0x13, 起): u 升级了, 主攻和反击都演完之后 u 做「握拳升级」动作 + 身上放升级光环 Misc/Ftlup_r,
##   两样同一 tick 开始, 只等光环放完就往下 (经验框; 光环结束 清阻塞标志, 握拳不等):
##   - 握拳 = u 自己 NNNmisc 动画的「动作 0」: 第 6 帧起共 action_counts[0] 帧 (主角 10 帧、第 13 帧响音效; 待机在它后面, 见 idle_frame; 没有这段的单位不做动作);
##     放到最后一帧就**定住** (动作 3 的步进: 到尾停在 end-1, 不回待机), 经验框、升级属性框、关近景都保持这个姿势 (资深玩家反馈「升级 → 保持 → 弹出升级」);
##   - 光环 = Ftlup_r (13 帧 x 3 tick, 屏幕坐标, 第 0 / 1 帧各响一个音效)。
##   先后顺序: 反击之后 (状态 0x0a 无反击直接到 0x12); 以上为静态对照原版, 没有 原版 逐帧实测
func level_up_fx(u = null) -> void:
	var cfg: Dictionary = UiLayout.el("closeup.levelup")
	var side: Dictionary = _sides.get("right" if u == null else _side_of(u), {})
	if side.is_empty():
		return
	if float(cfg.get("delay", 0.0)) > 0.0:
		await create_tween().tween_interval(float(cfg["delay"])).finished
	var m = side["misc"]
	m.visible = true   # 远程攻击后攻方被藏着 (_play_attack), 升级演出要露面
	var md: String = side["dir"]
	var pose := 0
	if anim_exists(md):
		pose = int(m.data["action_counts"][0])   # misc 播放器 open() 时已载入这份动画
	if pose > 0:
		m.play_sound = true   # 握拳动作自带的声音 (主角第 13 帧)
		m.play(md, 6, 6 + pose, false)
	var ring = m.get_script().new()   # 同 _vampire: 用攻方 misc 的播放器类
	_stage.add_child(ring)
	ring.play(ThemeAssets.p(String(cfg.get("anim", "battle.levelup_fx"))), 0, -1, false)
	if pose > 0:   # 握拳不循环, 放完停在最后一帧 (不回待机); 只在放完后关掉它的声音
		m.finished.connect(func(): m.play_sound = false, CONNECT_ONE_SHOT)
	await ring.finished
	ring.queue_free()


## 色闪 (原版 cfigthe / 步进; 静态观察 + Windows 直读状态确认): 命中 / 帧头 color 触发, 8 tick 阶梯加色,
## 权重逐 tick = layout closeup.flash.steps.add16 (12,12,8,8,6,6,4,4 /16)。level: 1~3 = 背景之上人物之下, 4 = 盖住一切 (级 2 没有绘制代码读, 不可见)。
## unit = 色号 1..7: 白 红 绿 蓝 黄 品红 青 (RGB555 0x7FFF 0x7C00 0x03E0 0x001F 0x7FE0 0x7C1F 0x03FF)。
const FLASH_COLORS := [Color(1, 1, 1), Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 1, 0), Color(1, 0, 1), Color(0, 1, 1)]


## 帧头 color 值 -> [级, 色号]; 0 / 级 2 (11~20) / 个位 0, 8, 9 无效返回空
static func color_code(c: int) -> Array:
	if c <= 0:
		return []
	var level := mini((c - 1) / 10 + 1, 4) if c <= 30 else 4
	var unit := (c - 1) % 10 + 1 if c <= 30 else c - 30
	if level == 2 or unit < 1 or unit > FLASH_COLORS.size():
		return []
	return [level, unit]


func _color_flash(level: int, unit: int) -> void:
	var layer := 4 if level == 4 else 3
	var rect: ColorRect = _tint_top if layer == 4 else _tint_mid
	_tint_id[layer] += 1
	var id: int = _tint_id[layer]
	var steps: Array = UiLayout.val("closeup.flash.steps", "add16", [12, 12, 8, 8, 6, 6, 4, 4])
	var tick := float(UiLayout.num("closeup.flash.steps", "tick", 0.04))
	rect.visible = true
	for w in steps:
		rect.color = (FLASH_COLORS[unit - 1] as Color) * (float(w) / 16.0)
		await get_tree().create_timer(tick).timeout
		if id != _tint_id[layer] or not is_inside_tree():
			return
	rect.visible = false


## 会心白闪 (kind 3 / 5 / 7 / 9) / 格挡红闪 (kind 6 / 8): 命中帧起 8 tick, 级 4
func _flash() -> void:
	_color_flash(4, 1)


func _flash_red(_fl := {}) -> void:
	_color_flash(4, 2)


## 致死渐隐: 数字放完后定格, 16 tick 线性淡出 (原版实测 U4: 亮度约 0.92 -> 0.05 近似线性, 没有大于 1 的过曝帧; 旧的 4 倍过曝是推测)
func _kill(m: AnimPlayer) -> void:
	m.playing = false
	await create_tween().tween_property(m, "modulate:a", 0.0, 16 * 0.04).finished


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
	var shown := 0.0      # 原版 字段: 当前显示的体力 (数字与黄条), 32 位浮点
	var hp_exact := 0     # 真实体力 (整数, 判倒下 / 留 1 用; shown 可能因浮点逐帧扣比它少 1)
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
		hp_exact = hp
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
	## 每个命中帧 shown -= 伤害/命中帧数, 都是 32 位浮点 (fsub / fstp dword), 显示 "%4d" 截断;
	## 例 体力 100 受 10 伤 3 帧: 96.666664 → 93.33333 → 89.99999 显示 89 (资深玩家反馈「差 1 血」, 差异)
	func hit(amount: float, keep_one: bool) -> void:
		shown = _f32(maxf(0.0, _f32(shown) - _f32(amount)))
		if rise_to >= 0.0:   # 吸血的体力还在涨时被打: 涨的终点跟着降, 继续涨 (原版: 反击命中后黄条接着涨)
			rise_to = maxf(shown, rise_to - amount)
		if keep_one and int(shown) == 0:
			shown = 1.0
		flash = 0
		_refresh_numbers()
		queue_redraw()
		_flash_add.queue_redraw()

	static func _f32(x: float) -> float:
		return PackedFloat32Array([x])[0]

	func set_hp(v: int) -> void:
		shown = v
		hp_exact = v
		trail = maxf(trail, shown)
		rise_to = -1.0
		_refresh_numbers()
		queue_redraw()

	## 吸血 / 回复: 体力 (数字与黄条) 每周期涨 2% 上限, 涨到 shown+amount (把 字段 设成 字段+量; 原版 逐帧: 上限 71 时每周期约 1.4)
	func heal(amount: int) -> void:
		rise_to = minf(float(hp_max), shown + amount)
		hp_exact = mini(hp_max, hp_exact + amount)

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
	await create_tween().tween_interval(DIGIT_LEAD).finished   # 攻击放完回待机后 3 tick 数字才弹 (原版实测 U4)
	var left: bool = sd == _sides.get("left")
	var n := DamageDigits.new(str(dmg), "closeup.damage.left" if left else "closeup.damage.right")
	_ui.add_child(n)
	await n.done
	n.queue_free()



# SPDX-License-Identifier: GPL-3.0-only
class_name BattleUnit
extends Node2D
## 战场上的一个单位 (MAN_NN.DAT 的一条)。坐标为格子, 绘制在 格子*30x24 + 人物约定 FxPlace.offset("unit")。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal move_finished
## 带镜头跟随的走路 (walk 的 follow) 每开始走一格发一次: 这一格的目的格与走完它要的秒数 (BattleScene 按边缘规则卷镜头)
signal step_begin(cell: Vector2i, seconds: float)

enum Dir { SOUTH, WEST, NORTH, EAST }   # 原版动画方向顺序
enum Act { STAND, MOVE, MOVE_START, MOVE_END, WIN, CAST }

const UnitState = preload("res://engine/rules/unit_state.gd")
const AttrNames = preload("res://engine/rules/attr_names.gd")
const Stats = preload("res://engine/rules/stats.gd")
const Movement = preload("res://engine/rules/movement.gd")
const ItemRules = preload("res://engine/rules/items.gd")
const Inventory = preload("res://engine/rules/inventory.gd")

var index := 0          # 单位编号 (MAN 里的下标) = st.uid
var man: Dictionary     # 关卡配置
var info: Dictionary    # data/units.json 的单位模板
## 规则状态 (engine/rules/unit_state.gd): 战斗数值、状态、移动点、AI 全在这里, 下面的属性都是它的别名
var st = UnitState.new()
var ctx                 # 规则上下文 (BattleRules.ctx), 用于显示派生值
var dir := Dir.SOUTH
var act := Act.STAND
var shown := false
var summon_flag := -1   # 召唤物: 召唤标志剧情变量号 (103~106), 死亡时清 0
var taken: Array = []   # 剧情 0x53 收走的装备 (关卡结束时从主角 10 格里去掉)
var anim: AnimPlayer
var _anim_dir := ""
var sprite_override := -1   # >= 0: 顶替精灵号 (测试用, --teach=单位:技能@精灵; 让我方角色放妖怪专属技能的演出, 随战阵存录保存)
var _path: Array = []
## 走路的三段 (原版实测, Win10 原生逐帧): 确认移动后先原地播「起步」(殷剑平提起剑匣, 11 帧), 播完才开始走; 到格后播「收步」(放下剑匣),
## 播完才算走完 (行动菜单这时才弹)。起步 / 走路 / 收步每帧都是 2 tick (0.08 秒; 原版逐帧实测: 走路每帧单位前进 10 像素), 站立才是 3 tick。精灵没有起步 / 收步动作 (action_counts[2] / [3] 为 0, 绝大多数单位) 就跳过这一段
enum Phase { NONE, START, END }
const PHASE_TICKS := 2   # 起步 / 走路 / 收步的每帧 tick 数
const STAND_TICKS := 3   # 站立每帧 tick 数 (战场精灵一律 3)
const TICK := 0.04       # 原版逻辑 tick (25 Hz)
## 全局时钟 (所有单位共用, 每帧只加一次): 原版战场单位站立换帧落在全局 tick % 3 == 1 的网格上 (1300 / 1300 次实测, 所有单位同相),
## 回站立后第一帧恒为帧 1, 按回站立那一刻的 tick % 3 显示 1 / 2 tick 或直接跳到第 2 帧显示 3 tick (实测 F, 53 次移动)
static var _clock := 0.0
static var _clock_frame := -1
const WALK_STEPS := 3    # 走一格分几步跳 (每个行走帧跳 1/3 格, 原版实测位置随帧跳而不是匀速滑)
var _phase := Phase.NONE
var _phase_id := 0   # 每次换动作加一: 起步 / 收步的完成回调带着编号, 被别的动作打断后作废
var _speed := 100.0

var cx: int:
	get: return st.x
	set(v): st.x = v
var cy: int:
	get: return st.y
	set(v): st.y = v
var alive: bool:
	get: return st.alive
	set(v): st.alive = v
var acted: bool:
	get: return st.acted
	set(v): st.acted = v
## 「已行动」灰色外观 (原版单位效果 4): 行动结束时打开, 本阵营阶段结束时连同 字段=0 一起关掉
## (友军 / 玩家 / 敌方), 所以别的阵营行动时不显示灰色
var acted_fx := false
var lv: int:
	get: return st.lv
	set(v): st.lv = v
var hp: int:
	get: return st.hp
	set(v): st.hp = v
var hp_max: int:
	get: return st.hp_max
	set(v): st.hp_max = v
var mp: int:
	get: return st.mp
	set(v): st.mp = v
var mp_max: int:
	get: return st.mp_max
	set(v): st.mp_max = v
var exp: int:
	get: return st.xp
	set(v): st.xp = v
var stats: Dictionary:
	get: return st.stats
	set(v): st.stats = v
var skills: Array:
	get: return st.skills
var spirit_points: int:
	get: return st.spirit_points
var summoned: bool:
	get: return st.summon
## 五魂 {迅: n, ...} (存档 / 营地格式)
var spirit: Dictionary:
	get:
		var d := {}
		for i in 5:
			d[AttrNames.SPIRIT[i]] = int(st.spirit[i])
		return d
## 装备 {weapon/armor/accessory: 物品编号 或 null} (只读副本; 改用 equip_item / unequip)
var gear: Dictionary:
	get: return {"weapon": _n(st.weapon), "armor": _n(st.armor), "accessory": _n(st.accessory)}


static func _n(id: int) -> Variant:
	return null if id < 0 else id


static func _id(v) -> int:
	return -1 if v == null else int(v)


static func create(i: int, m: Dictionary, x: int, y: int, rules_ctx) -> BattleUnit:
	var u := BattleUnit.new()
	u.index = i
	u.man = m
	u.ctx = rules_ctx
	u.info = Content.unit_at(int(m["unit_id"]))
	var spr := int(u.info["sprite"])
	u._anim_dir = ThemeAssets.f("unit_anim", [spr, spr])
	u.anim = AnimPlayer.new()
	u.anim.play_sound = false
	u.anim.position = FxPlace.offset("unit")  # 战场人物约定 (-142,-110),
	u.add_child(u.anim)
	u.visible = false
	u._init_stats()
	u.set_cell(x, y)
	return u


## 建规则状态: 主角取存档成长 / party_init.json, 其他单位按 Man_base + MAN 加值
func _init_stats() -> void:
	var uid := int(man["unit_id"])
	var side := 1 if int(info["camp"]) == 1 else 0
	var hp_sub := 0
	var mp_sub := 0
	if Content.is_hero(uid) and not gc.state.party_of(uid).is_empty():  # 我方主角: 继承之前关卡的成长
		var g: Dictionary = gc.state.party_of(uid)
		st = UnitState.new()
		st.lv = int(g["lv"])
		st.xp = int(g["exp"])
		st.hp_max = int(g["hp_max"])
		st.mp_max = int(g["mp_max"])
		for k in g["stats"]:
			st.stats[k] = int(g["stats"][k])
		st.weapon = _id(g["gear"]["weapon"])
		st.armor = _id(g["gear"]["armor"])
		st.accessory = _id(g["gear"]["accessory"])
		st.skills = g.get("skills", []).map(func(x): return int(x))
		var sp: Dictionary = g.get("spirit", {})
		for k in 5:
			st.spirit[k] = int(sp.get(AttrNames.SPIRIT[k], 0))
		st.spirit_points = int(g.get("spirit_points", 0))
		st.items = ItemRules.unit_slots(g.get("items", []), g["gear"])  # 本人 10 格 (装备占格); 战斗只用它, 公共行囊不进战场
	elif Content.is_hero(uid):  # 我方主角: 初始状态 (内容包 party_init 表)
		var p: Dictionary = Content.party_init(uid)
		st = UnitState.from_party_init(p)
		gc.state.seeded[uid] = true  # 初始随身物品 (含装备) 就在本人 10 格里 (原版 KMAN_STA 初始物品; 旧存档此处曾把消耗品放进行囊)
	else:  # 敌方/NPC: 模板 + 成长 x 等级 + 关卡加值
		var plus := {"hp": int(man["hp_add"]), "mp": int(man["mp_add"])}
		hp_sub = int(man["hp_sub"])
		mp_sub = int(man["mp_sub"])
		for k in AttrNames.STAT_KEYS:
			plus[k] = int(man[k])
		st = Stats.make_enemy(info, int(man["lv"]), plus, side)
		st.weapon = _id(man["weapon"])
		st.armor = _id(man["armor"])
		st.accessory = _id(man["accessory"])
		st.items = man.get("items", []).filter(func(x): return x != null and int(x) >= 0).map(func(x): return int(x))
		st.skills = man.get("skills", []).map(func(x): return int(x))
		var sp: Dictionary = man.get("spirit", {})
		for k in 5:
			st.spirit[k] = int(sp.get(AttrNames.SPIRIT[k], 0))
	st.uid = index
	st.unit_id = uid
	st.name = String(info["name"])
	st.side = side
	st.move_base = int(info["move"])
	st.move_type = int(info["move_type"])
	st.mag_opp_id = int(info["attribute_defence_id"])
	st.annihilation_exempt = int(info.get("defence_type", 0)) != 0
	st.kill_event = int(man.get("kill_event", -1))
	# hp_sub/mp_sub 只减当前值, 上限不变 [当前 = 上限 - sub]; 至少留 1 点 HP
	st.hp = maxi(1, st.hp_max - hp_sub)
	st.mp = maxi(0, st.mp_max - mp_sub)
	st.alive = true
	var t: Array = man.get("ai_target", [0, 0])
	set_ai(int(man["ai"]), int(t[0]), int(t[1]))
	# 友军 NPC 标志 字段 = MAN event_parm[1] (MAN+0x50 -> 单位+0xac); 回合流程按它而不是 AI 类型分阶段:
	# 阵营 0 且 字段≠0 在友军阶段由 AI 行动, 字段=0 在我方阶段由玩家操作, AI 类型不参
	var ep: Array = man.get("event_parm", [0, 0])
	st.npc_ally = st.side == 0 and not st.summon and ep.size() > 1 and int(ep[1]) != 0


## AI 类型与目标 (MAN.ai / 剧情 0x2F, 原版只写 字段/字段/字段, 不碰 字段)
func set_ai(t: int, p1: int, p2: int) -> void:
	st.ai = t
	st.ai_target = [p1, p2]


## 友军 NPC 标志 (剧情 0x44: 只写 字段)
func set_npc(on: bool) -> void:
	st.npc_ally = on


## 战阵存录: 单位状态快照 / 恢复
func snapshot() -> Dictionary:
	var d := {"dir": dir, "shown": shown, "summon_flag": summon_flag, "st": st.to_dict()}
	if sprite_override >= 0:
		d["sprite"] = sprite_override
	return d


## 顶替精灵号 (人物动画、近景、技能演出都按它取文件); info 是内容包里共享的字典, 先复制再改
func override_sprite(spr: int) -> void:
	sprite_override = spr
	info = info.duplicate()
	info["sprite"] = spr
	_anim_dir = ThemeAssets.f("unit_anim", [spr, spr])
	if shown:
		play_act(Act.STAND, dir)


func restore(d: Dictionary) -> void:
	if d.has("st"):
		st = UnitState.new()
		st.from_dict(d["st"])
	summon_flag = int(d.get("summon_flag", -1))
	if d.has("sprite"):
		override_sprite(int(d["sprite"]))
	set_cell(cx, cy)
	if d["shown"] and alive:
		show_unit(int(d["dir"]))
	else:
		hide_unit()
	_tint()


## 召唤: 属性 = 施术者 x 模板百分比 (engine/rules/stats.gd make_summon), 当回合即可行动
func summon_from(c: BattleUnit) -> void:
	var s = Stats.make_summon(ctx, c.st, info)
	for k in ["lv", "hp", "hp_max", "mp", "mp_max", "summon", "items", "move_base", "move_type", "mag_opp_id"]:
		st.set(k, s.get(k))
	st.stats = s.stats.duplicate()
	st.side = c.st.side
	st.status = 0
	st.status_r = {}
	st.status_k = {}
	st.burst_reserve = 0
	st.alive = true
	set_ai(-1, 0, 0)
	Movement.begin_phase(ctx, st)
	# 召唤当回合的移动点 [先算 字段 = (move + avg/25), 再调 缩放属性, 所以 avg 用的是预置单位缩放**前**的
	# 基础值; 施术者 avg 300 时式鬼 mv=26 (=22+100/25), 而不是 22+300/25=34]。下个阶段起按缩放后的 avg
	var m0: int = int(info.get("move", 20)) + int(info.get("avg", 0)) / 25
	st.move_cap = m0
	st.move_left = m0


## 事件 0x40/0x49: 按物品类型替换武器/护具/饰物。 在本人 10 格里找「当前该槽装备的物品编号」所在的第一格,
## **原位改写**成新物品并设装备位; 找不到 (旧装备不在 10 格里) 什么也不做; 饰物槽空 (-1) 时放进第一个空格, 没有空格不做。
## 不去重 (同编号可有两件, 与原版一致)。物品栏顺序因此与旧实现 (删旧、追加到末尾) 不同。
func equip_item(id: int) -> void:
	var it: Dictionary = Content.item_at(id)
	var slot: String = {1: "weapon", 2: "armor", 3: "accessory"}.get(int(it["type"]), "")
	if slot == "":
		return
	var old: int = st.get(slot)
	if old < 0:
		if slot != "accessory" or st.items.size() >= 10:
			return
		st.items.append(id)
	else:
		var k: int = st.items.find(old)
		if k < 0:
			return
		st.items[k] = id
	st.set(slot, id)


## 召唤物离场/死亡/战斗结束: 未装备的物品倒进公共行囊; 非召唤物不动
func dump_items_to_bag() -> void:
	if not summoned:
		return
	for id in Inventory.dump_unequipped(st):
		gc.state.add_item(id)


func unequip(slot: String) -> void:
	var old: int = st.get(slot)
	st.set(slot, -1)
	st.items.erase(old)
	taken.append(old)


## 关卡结束时写回主角成长
func to_party() -> Dictionary:
	var d := {"lv": lv, "exp": exp, "hp_max": hp_max, "mp_max": mp_max, "stats": stats.duplicate(), "gear": gear,
		"skills": skills.duplicate(), "spirit": spirit, "spirit_points": spirit_points}
	d["items"] = ItemRules.unit_slots(st.items, gear)  # 10 格 (装备占格) 写回, 战斗中的取用/给予/拾取都在 st.items 上
	return d


var name_text: String:
	get: return info["name"]


var _fx: UnitStatusFx
var _true_pos := Vector2.ZERO   # 走路时的连续位置 (position 是它按行走帧量化后的显示位置)
var _seg_from := Vector2.ZERO   # 当前这一格的起点
var _follow := false            # 本次走路要镜头跟随 (walk 的 follow)
var _phases := true             # 本次走路放起步 / 收步 (walk 的 phases)
var _frame_ticks := PHASE_TICKS # 本次走路每帧 tick 数 (walk 的 frame_ticks)
var _step_sent := false         # 当前这一格已发过 step_begin
var _shadow: Sprite2D   # 脚下影子 (UnitShadow), 在 anim 之下


func has_status(bit: int) -> bool:
	return st.has_status(bit)


func _tint() -> void:
	var tints: Dictionary = UiLayout.val("map.unit.status_tint", "colors", {})  # 布局表 map.unit.status_tint (原版重绘色的实测均值)
	var c := Color.WHITE
	if has_status(UnitState.ST_FREEZE) and tints.has("freeze"):
		c = UiLayout.color(tints["freeze"])
	elif has_status(UnitState.ST_POISON) and tints.has("poison"):
		c = UiLayout.color(tints["poison"])
	if has_status(UnitState.ST_PHANTOM):
		c.a = float(UiLayout.val("map.unit.status_tint", "phantom_alpha", 0.5))
	anim.modulate = c
	if _fx == null:
		_fx = UnitStatusFx.new()
		add_child(_fx)
		_fx.setup(self)
	_fx.refresh(st.status)   # 状态叠层 (Man_eff) / 麻痹抖动 / 狂暴脉动


## 显示用攻/防 (信息条): 装备 + 属性, 攻擊/護禦提昇 x1.2, 狂暴 攻x2 防/2
var attack: int:
	get:
		var p = ctx.params
		var v: int = Stats.atk(ctx, st)
		if has_status(UnitState.ST_ATK_UP):
			v = v * p.atk_up_num / p.atk_up_den
		if has_status(UnitState.ST_BERSERK):
			v *= p.berserk_atk_mult
		return v
var defence: int:
	get:
		var p = ctx.params
		var v: int = Stats.def(ctx, st)
		if has_status(UnitState.ST_DEF_UP):
			v = v * p.def_up_num / p.def_up_den
		if has_status(UnitState.ST_BERSERK):
			v /= p.berserk_def_div
		return v
## 信息条「移」: 当前移动点 (字段) 与爆發保留点 (字段); 还没开始过阶段时按上限算
var move_now: int:
	get: return Movement.cur_points(st) if st.move_cap > 0 else Movement.move_cap(ctx, st)
var move_max: int:
	get: return st.burst_reserve
var ai: int:
	get: return st.ai
## 玩家操作的单位 (阵营 0、非友军 NPC)
var controllable: bool:
	get: return st.side == 0 and not st.npc_ally
## 互为敌人: 阵营 0 (我方/友军) vs 阵营 1
func hostile(o: BattleUnit) -> bool:
	return st.side != o.st.side


var camp: int:
	get: return int(info["camp"])  # 0 我方, 1 敌方, 2 友军 (见 data/units.json camp_name)


func set_cell(x: int, y: int) -> void:
	cx = x
	cy = y
	position = Vector2(x * BattleStage.CELL_W, y * BattleStage.CELL_H)


func show_unit(d := Dir.SOUTH) -> void:
	shown = true
	visible = true
	modulate = Color.WHITE
	if anim != null:
		anim.modulate = Color.WHITE   # 死亡渐隐只淡本体 (fade_out), 重新出场要还原
	play_act(Act.STAND, d)


func hide_unit() -> void:
	shown = false
	visible = false


## 死亡渐隐: 原版 16 tick (0.64 秒, 静态观察 S5), 只淡人物本体; 脚下影子满强度保持到单位整体移除 (复刻原先整个节点 alpha 淡出, 影子一起淡)。
## 原版是加色过曝再淡出 (权重 2.0 -> 0.125), 渲染器单次混合最高 1.0, 这里只做 16 tick 线性淡出
const FADE_OUT_SECS := 16 * TICK


func fade_out() -> void:
	shown = false
	var tw := create_tween()
	tw.tween_property(anim if anim != null else self, "modulate:a", 0.0, FADE_OUT_SECS)
	await tw.finished
	visible = false


## 重制版 GameAnimation.playAnimationBattle 的帧范围
## 战场小人动画目录 (单位详情窗里非主角单位拿它画动图)
func sprite_dir() -> String:
	return _anim_dir


func play_act(a: int, d: int) -> void:
	_phase_id += 1   # 别的动作打断了起步 / 收步: 旧回调作废
	_phase = Phase.NONE
	_play_act(a, d)


## 精灵有没有这一段动作: 2 = 起步, 3 = 收步 (action_counts 下标)
func _has_group(g: int) -> bool:
	var c: Array = _anim_data().get("action_counts", [])
	return c.size() > 3 and int(c[g]) > 1   # 原版每组第 0 帧不显示, 只剩 1 帧的等于没有; 没有行走帧的精灵 (如 014 / 150) 照样有起步收步 (实测)


## 本单位的动画数据; 没有动画目录 (测试里的空壳单位) 给空字典, 调用方按「没有这一段」处理
func _anim_data() -> Dictionary:
	return Assets.anim(_anim_dir) if _anim_dir != "" else {}


## 在移动中: 有路没走完, 或在播起步 / 收步 (剧情等单位「走完」要连收步一起等)
func is_moving() -> bool:
	return not _path.is_empty() or _phase != Phase.NONE


## 脚下影子 (原版实测每个单位都有, 精灵数据里没有: 见 UnitShadow); 建一次, 放在 anim 之下, 跟格子走 (不跟精灵)
func _ensure_shadow(data: Dictionary) -> void:
	if _shadow != null or anim == null or not UnitShadow.has_picture(data):
		return
	_shadow = Sprite2D.new()
	_shadow.texture = UnitShadow.texture()
	_shadow.scale = Vector2.ONE / float(UnitShadow.SUPERSAMPLE)   # 贴图是放大倍数的高分辨率版, 缩回原版像素大小
	_shadow.modulate = Color(1, 1, 1, UnitShadow.ALPHA)
	_shadow.position = UnitShadow.CENTER   # 单位节点原点 = 格子左上
	add_child(_shadow)
	move_child(_shadow, 0)
	# 原版绘制单位: 当前显示帧没有部件时整个跳过, 影子也不画 (静态观察 S6)
	anim.frame_shown.connect(func(f: int):
		var fr: Array = anim.data.get("frames", [])
		_shadow.visible = f >= fr.size() or not (fr[f]["parts"] as Array).is_empty())


func _step_dir(to: Vector2i) -> int:
	var goal := Vector2(to.x * BattleStage.CELL_W, to.y * BattleStage.CELL_H)
	if position.x != goal.x:
		return Dir.EAST if goal.x > position.x else Dir.WEST
	if position.y != goal.y:
		return Dir.SOUTH if goal.y > position.y else Dir.NORTH
	return dir


func _play_act(a: int, d: int, at := 0) -> void:
	act = a
	dir = d
	var data := _anim_data()
	if data.is_empty():
		return
	_ensure_shadow(data)
	var c: Array = data["action_counts"]
	var stand := int(c[0])
	var move := int(c[1])
	var mstart := int(c[2])
	var win := int(c[4])
	var base := 2 + (win if win > 0 else 1)
	var size := 0
	var idx := base
	match a:
		Act.STAND:
			size = stand
			idx = base + d * size
		Act.MOVE:
			size = move
			idx = base + stand * 4 + d * size
			if move <= 0:   # 没有行走帧: 走路时固定显示行走组起点那一帧 (原版实测 014 / 150 / 209 等), 不播站立
				size = 1
		Act.MOVE_START:
			size = mstart
			idx = base + move * 4 + stand * 4 + d * size
		Act.MOVE_END:
			size = int(c[3])
			idx = base + (move + stand + mstart) * 4 + d * size
		Act.WIN:   # 没有胜利帧的精灵 (204 / 163 等) 固定显示帧 2 (空帧: 单位不画, 影子也不画; 原版实测 补 4 V1), 不退回站立
			size = win if win > 0 else 1
			idx = 2
		Act.CAST:  # 施法姿势: 第 0~1 帧 (把施法者动作设为 0; 实测殷剑平举剑面向画面); 这两帧是空帧的精灵 (204 / 231 / 236 等)
			size = 2   # 原版照播空帧: 法术演出期间 (150~275 tick) 身体和影子都不画 (补 4 V1)
			idx = 0
	if size <= 0:   # 起步 / 收步 / 胜利没有这一组 (调用方有 _has_group 守着, 这里兜底), 按站立
		size = maxi(stand, 1)
		idx = base + d * size
	anim.play_sound = true   # 原版每次推进帧 取到有效的帧声音就 PlaySfx, 与动作无关 (对照原版: 动作只决定帧号, 声音在跳转表之后无条件取): 行走脚步 / 起步 / 收步 (出刀 收刀 提放剑匣) / 站立 (赤炼鬼等) / 胜利 都响
	if a == Act.MOVE_START or a == Act.MOVE_END:   # 起步 / 收步: 第 0 帧不显示, 放第 1..n-1 帧 (原版实测总长 2*(n-1) tick)
		idx += 1
		size -= 1
	# 起步 / 走路 / 收步每帧 2 tick, 站立每帧 3 tick, 都与帧自带的 time 无关 (原版实测 107 个战场精灵); 其余 (胜利 / 施法) 仍按帧自带的 time
	anim.tick_override = _frame_ticks if a == Act.MOVE or a == Act.MOVE_START or a == Act.MOVE_END else (STAND_TICKS if a == Act.STAND or a == Act.CAST or a == Act.WIN else 0)   # 施法 / 胜利帧也是每 3 tick 一帧 (实测 补 4 V1)
	anim.start_at = at
	if a == Act.STAND:   # 回站立: 从帧 1 起, 相位对到全局网格 (已「播过」的时间 = 2 / 3 / 1 tick (tick%3 = 0 / 1 / 2) + 本 tick 内已过的零头)
		anim.start_at = 1
		var tk := int(_clock / TICK + 1e-6)
		anim.start_skew = float([2, 3, 1][tk % 3]) * TICK + (_clock - tk * TICK)
	anim.play(_anim_dir, idx, idx + size, a != Act.WIN and a != Act.MOVE_START and a != Act.MOVE_END)


## 沿路径一格一格移动 (先横后纵), 速度为原版像素/秒。
## follow: 每走一格发 step_begin, 镜头按边缘规则跟着卷 (原版战场走路对象 / tick 每格都判, 我方移动与 AI 行动都用它, 差异)
## phases: 放起步 / 收步 (剧情走路 0x0F / 0x11 由指令头 +2 决定: 原版剧情走路对象 第 2 参数 [esi] = 1 才放动作 4 / 5, 差异)
## frame_ticks: 起步 / 走路 / 收步每帧 tick 数 (剧情走路对象每 速度+1 tick 才推进一帧, 我方 / AI = PHASE_TICKS)
func walk(path: Array, speed: float, follow := false, phases := true, frame_ticks := PHASE_TICKS) -> void:
	_path = path.duplicate()
	_speed = speed
	_follow = follow
	_phases = phases
	_frame_ticks = frame_ticks
	_step_sent = false
	_true_pos = position
	_seg_from = position
	_phase_id += 1
	_phase = Phase.NONE
	if shown:   # 在场标志只由出场指令 (0x0B/0x17/0x4C) 与敌我出场流程置位; 走路指令 0x0F/0x11 只改坐标
		visible = true
	if _path.is_empty():
		move_finished.emit()
		return
	if _phases and _has_group(2):   # 起步: 原地先播 (朝第一步的方向), 播完才开始走
		_begin_phase(Phase.START, Act.MOVE_START, _step_dir(_path[0]))


## 进入起步 / 收步阶段: 播一遍对应动作, 播完回调 (编号对不上说明被别的动作打断了, 什么都不做)
func _begin_phase(ph: Phase, a: int, d: int) -> void:
	_phase_id += 1
	_phase = ph
	_play_act(a, d)
	var id := _phase_id
	anim.finished.connect(func():
		if id != _phase_id or _phase != ph:
			return
		_phase = Phase.NONE
		if ph == Phase.START:
			_play_act(Act.MOVE, dir, 1)   # 起步完了开始走 (位置没动过), 行走帧从第 1 帧起
		else:
			_play_act(Act.STAND, dir)
			move_finished.emit(), CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	if Engine.get_process_frames() != _clock_frame:
		_clock_frame = Engine.get_process_frames()
		_clock += delta
	if _path.is_empty() or _phase != Phase.NONE:
		return
	# 每格先横后纵; 用精确比较判断到格 (move_toward 在剩余距离不超过步长时正好落在目标上),
	# 不设「差多少算到」的死区: 原先 |差| <= 0.01 不再移动、又要 is_equal_approx 才算到格,
	# 帧长不整除格宽时 (非 25 帧/秒, 如 60/144Hz 显示器) 会停在差 0.00x 像素处永远走不完,
	# 剧情行走 (0x0F/0x11)、AI 与我方移动都在等 move_finished, 于是整段剧情/回合卡死。
	# 本帧走到格后剩余的时间接着走下一格, 速度不受帧率影响。
	# 按「每格用时」走 (原版实测: 横竖每格同样的时间, 见 BattleStage.UNIT_WALK_SPEED): 横向 _speed 像素/秒, 竖向按 CELL_H/CELL_W 折算。
	var left := delta
	while left > 1e-9 and not _path.is_empty():
		var target: Vector2i = _path[0]
		var goal := Vector2(target.x * BattleStage.CELL_W, target.y * BattleStage.CELL_H)
		if _follow and not _step_sent:
			_step_sent = true
			step_begin.emit(target, float(BattleStage.CELL_W) / _speed)   # 横竖每格同样的时间
		var nd := dir
		if _true_pos.x != goal.x:
			nd = Dir.EAST if goal.x > _true_pos.x else Dir.WEST
			var m := minf(_speed * left, absf(goal.x - _true_pos.x))
			_true_pos.x = move_toward(_true_pos.x, goal.x, m)
			left -= m / _speed
		elif _true_pos.y != goal.y:
			nd = Dir.SOUTH if goal.y > _true_pos.y else Dir.NORTH
			var vy := _speed * float(BattleStage.CELL_H) / float(BattleStage.CELL_W)
			var m := minf(vy * left, absf(goal.y - _true_pos.y))
			_true_pos.y = move_toward(_true_pos.y, goal.y, m)
			left -= m / vy
		if nd != dir or act != Act.MOVE:
			# 起步后第一帧是行走帧 1; 转弯 (同一段路中途换方向) 帧号接着走不重来
			_play_act(Act.MOVE, nd, 1 if act != Act.MOVE else maxi(anim.frame - anim.start_frame, 0))
		if _true_pos == goal:
			position = goal
			_seg_from = goal
			cx = target.x
			cy = target.y
			_path.pop_front()
			_step_sent = false
			if _path.is_empty():
				if _phases and _has_group(3):   # 收步: 到格后播, 播完才发 move_finished
					_begin_phase(Phase.END, Act.MOVE_END, dir)
					anim.delay_start(delta - left)   # 子动画本帧还要按整帧 delta 推进, 到格之前走掉的那部分不算收步的
				else:
					play_act(Act.STAND, dir)
					move_finished.emit()
		else:
			position = _true_pos if WalkStyle.smooth() else _stepped(goal)   # WalkStyle 内置开关: 平滑 / 原版步进


## 走路中的显示位置: 一格分 WALK_STEPS 步, 每个行走帧到来时跳一步 (原版实测: 横向每帧 +10、竖向每帧 +8 原版像素, 不是匀速滑动);
## 本格第 k 帧的位置 = 本格起点 + k/WALK_STEPS 格, 最后一帧正好到格
func _stepped(goal: Vector2) -> Vector2:
	var off := _true_pos - _seg_from
	var span := goal - _seg_from
	var len := maxf(absf(span.x), absf(span.y))
	if len <= 0.0:
		return _true_pos
	var k := mini(int(maxf(absf(off.x), absf(off.y)) / len * WALK_STEPS) + 1, WALK_STEPS)
	return _seg_from + span * (float(k) / WALK_STEPS)

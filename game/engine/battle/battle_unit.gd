# SPDX-License-Identifier: GPL-3.0-only
class_name BattleUnit
extends Node2D
## 战场上的一个单位 (MAN_NN.DAT 的一条)。坐标为格子, 绘制在 格子*30x24 + 人物约定 FxPlace.offset("unit")。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal move_finished

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
var _path: Array = []
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
		var plus := {"hp": int(man["hp_add"]) - int(man["hp_sub"]), "mp": int(man["mp_add"]) - int(man["mp_sub"])}
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
	st.hp = st.hp_max
	st.mp = st.mp_max
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
	return {"dir": dir, "shown": shown, "summon_flag": summon_flag, "st": st.to_dict()}


func restore(d: Dictionary) -> void:
	if d.has("st"):
		st = UnitState.new()
		st.from_dict(d["st"])
	summon_flag = int(d.get("summon_flag", -1))
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
	play_act(Act.STAND, d)


func hide_unit() -> void:
	shown = false
	visible = false


func fade_out() -> void:
	shown = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	await tw.finished
	visible = false


## 重制版 GameAnimation.playAnimationBattle 的帧范围
## 战场小人动画目录 (单位详情窗里非主角单位拿它画动图)
func sprite_dir() -> String:
	return _anim_dir


func play_act(a: int, d: int) -> void:
	act = a
	dir = d
	var data := Assets.anim(_anim_dir)
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
		Act.MOVE_START:
			size = mstart
			idx = base + move * 4 + stand * 4 + d * size
		Act.WIN:
			size = win
			idx = 2
		Act.CAST:  # 施法姿势: 第 0~1 帧 (把施法者动作设为 0; 实测殷剑平举剑面向画面); 没有这两帧的按站立
			if not data["frames"][0]["parts"].filter(func(p): return p["tex"] != null).is_empty():
				size = 2
				idx = 0
	if size <= 0:
		size = maxi(stand, 1)
		idx = base + d * size
	anim.play_sound = a == Act.MOVE   # 只有行走帧带脚步声 (-> PlaySfx, 实测; 站立/出手近景声另走近景动画)
	anim.play(_anim_dir, idx, idx + size, a != Act.WIN)


## 沿路径一格一格移动 (先横后纵), 速度为原版像素/秒
func walk(path: Array, speed: float) -> void:
	_path = path.duplicate()
	_speed = speed
	if shown:   # 在场标志只由出场指令 (0x0B/0x17/0x4C) 与敌我出场流程置位; 走路指令 0x0F/0x11 只改坐标
		visible = true
	if _path.is_empty():
		move_finished.emit()


func _process(delta: float) -> void:
	if _path.is_empty():
		return
	# 每格先横后纵; 用精确比较判断到格 (move_toward 在剩余距离不超过步长时正好落在目标上),
	# 不设「差多少算到」的死区: 原先 |差| <= 0.01 不再移动、又要 is_equal_approx 才算到格,
	# 帧长不整除格宽时 (非 25 帧/秒, 如 60/144Hz 显示器) 会停在差 0.00x 像素处永远走不完,
	# 剧情行走 (0x0F/0x11)、AI 与我方移动都在等 move_finished, 于是整段剧情/回合卡死。
	# 本帧走到格后剩余的步长接着走下一格, 速度不受帧率影响。
	var step := _speed * delta
	while step > 0.0 and not _path.is_empty():
		var target: Vector2i = _path[0]
		var goal := Vector2(target.x * BattleStage.CELL_W, target.y * BattleStage.CELL_H)
		var nd := dir
		if position.x != goal.x:
			nd = Dir.EAST if goal.x > position.x else Dir.WEST
			var m := minf(step, absf(goal.x - position.x))
			position.x = move_toward(position.x, goal.x, step)
			step -= m
		elif position.y != goal.y:
			nd = Dir.SOUTH if goal.y > position.y else Dir.NORTH
			var m := minf(step, absf(goal.y - position.y))
			position.y = move_toward(position.y, goal.y, step)
			step -= m
		if nd != dir or act != Act.MOVE:
			play_act(Act.MOVE, nd)
		if position == goal:
			cx = target.x
			cy = target.y
			_path.pop_front()
			if _path.is_empty():
				play_act(Act.STAND, dir)
				move_finished.emit()

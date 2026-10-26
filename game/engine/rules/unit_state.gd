# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 单位运行时状态: 纯数据, 不依赖节点, 可 to_dict()/from_dict() 序列化 (战阵存录、存档、测试)。
## 字段对应原版的单位记录。

# ---- 状态位 ----
const ST_ATK_UP := 0x1        # 攻擊提昇
const ST_DEF_UP := 0x2        # 護禦提昇
const ST_TECH_UP := 0x4       # 技法提昇
const ST_HASTE := 0x8         # 速敏提昇
const ST_GUARD_SKILL := 0x10  # 對技全禦
const ST_GUARD_SPELL := 0x20  # 對術全禦
const ST_BERSERK := 0x40      # 狂暴
const ST_PARALYZE := 0x80     # 麻痺
const ST_UNUSED_100 := 0x100  # 无名, 找不到置位代码
const ST_BIND := 0x200        # 地縛
const ST_SEAL := 0x400        # 封咒
const ST_PHANTOM := 0x800     # 幻影
const ST_POISON := 0x1000     # 中毒
const ST_FREEZE := 0x2000     # 冰結
## 状态位 -> 原版名称 (仅作位表遍历与文档; 界面上的显示名在界面文案表 battle.status.<位>, 简/繁见 docs/设计_繁简切换.md)
const STATUS_NAMES := {
	0x1: "攻擊提昇", 0x2: "護禦提昇", 0x4: "技法提昇", 0x8: "速敏提昇",
	0x10: "對技全禦", 0x20: "對術全禦", 0x40: "狂暴", 0x80: "麻痺",
	0x200: "地縛", 0x400: "封咒", 0x800: "幻影", 0x1000: "中毒", 0x2000: "冰結",
}
## AI 类型枚举 (单位模板 ai / 剧情 0x2F); 与 data/enums.json 的 "ai" 同号, 行为由 ai.gd 实现 (内容包只能选用)
const AI_IDLE := 0     # 原地待机
const AI_ACTIVE := 1   # 主动出击 (其余未知值同此)
const AI_PASSIVE := 2  # 消极 (被打后转主动)
const AI_FOLLOW := 3   # 向指定单位移动
const AI_GOTO := 4     # 向指定坐标移动
const AttrNames = preload("res://engine/rules/attr_names.gd")

# ---- 身份 ----
var uid: int = -1             # MAN 表下标 (战场内唯一); 行动顺序按它
var unit_id: int = -1         # Man_base 编号 (units.json id)
var name: String = ""
var side: int = 0             # 阵营 +6: 0 我方 (含友军 NPC、召唤物), 1 敌方
var npc_ally: bool = false    # 字段=1 友军 NPC (AI 控制, 不得经验)
var summon: bool = false      # 字段≠0 召唤物 (不得经验)

# ---- 等级经验 ----
var lv: int = 1               # 字段
var base_lv: int = 0          # 字段, 敌人 Man_base.base_lv; 有效等级 = lv + base_lv
var xp: int = 0               # 历练值 (0..499), 序列化键 "exp"
var base_exp: int = 0         # 字段, 被击败时给出的基础经验

# ---- 属性 ----
var hp: int = 1
var hp_max: int = 1
var mp: int = 0
var mp_max: int = 0
var stats := {"str": 0, "int": 0, "avg": 0, "vit": 0, "luk": 0}   # 字段..字段
var spirit := [0, 0, 0, 0, 0]  # 五魂 迅烈神魔魂 字段..字段
var spirit_points: int = 0     # 未分配五魂点 字段

# ---- 移动 ----
var move_base: int = 20       # Man_base.move
var move_type: int = 0        # Man_base.move_type (TER_EFF 行)
var mag_opp_id: int = 0       # Man_base.attribute_defence_id (MAG_OPP 抗性表行)
var x: int = 0
var y: int = 0
var move_cap: int = 0         # 字段 本阶段移动上限 (含保留点)
var move_left: int = 0        # 当前剩余移动点 (含保留点)
var burst_reserve: int = 0    # 字段 爆發保留点
var burst_fresh: bool = false # 本阶段刚爆發 (行动结束时不清保留点)
var moved: bool = false       # 本阶段已移动 (咒术不可用)
var acted: bool = false       # 本阶段已行动
var released: int = 0         # 本次行动里被打破的状态位 (冰結受击解除), 战场演出读后清 0 (模式 3 的「解除」演出)
var extra_action: bool = false # 字段 再行动标志 (返召之咒)
var ai_passed: bool = false   # 本阶段 AI 已轮到过 (含「不移动也不出手」的单位); 只给 AI 估价用, 不入存档, 阶段开始清除

# ---- 装备与物品 (物品编号, -1 = 无) ----
var weapon: int = -1
var armor: int = -1
var accessory: int = -1
var items: Array = []         # 物品栏 10 格 (含装备中的), 物品编号
var skills: Array = []        # 技能栏 10 格, 技能编号

# ---- 状态 ----
var status: int = 0           # 字段 位掩码
var status_r := {}            # 位 -> 剩余值 R
var status_k := {}            # 位 -> 扣减值 K

# ---- AI ----
var ai: int = -1              # 字段: -1 玩家, 0 不动, 1 主动, 2 被动, 3 跟随, 4 前往坐标
var ai_target := [0, 0]       # 字段 / 字段
var alive: bool = true        # 在场 (字段 == 1)
var kill_event: int = -1      # 字段 被击倒时执行的事件号; -1 = 无
var annihilation_exempt: bool = false  # 字段 = Man_base[40], 不计入「全灭」(只有齐祀 uid85)


func get_stat(key: String) -> int:
	return int(stats.get(key, 0))


func set_stat(key: String, v: int) -> void:
	stats[key] = v


func eff_lv() -> int:
	return lv + base_lv


func pos() -> Vector2i:
	return Vector2i(x, y)


func set_pos(c: Vector2i) -> void:
	x = c.x
	y = c.y


func has_status(bit: int) -> bool:
	return (status & bit) != 0


func is_player_controlled() -> bool:
	return side == 0 and not npc_ally and ai == -1


## 只有阵营 0、非友军 NPC、非召唤物得经验
func gains_exp() -> bool:
	return side == 0 and not npc_ally and not summon


func hostile_to(other) -> bool:
	return side != other.side


func duplicate_state():
	var u = get_script().new()
	u.from_dict(to_dict())
	return u


func to_dict() -> Dictionary:
	var sr := {}
	for b in status_r:
		sr[str(b)] = status_r[b]
	var sk := {}
	for b in status_k:
		sk[str(b)] = status_k[b]
	return {
		"uid": uid, "unit_id": unit_id, "name": name, "side": side, "npc_ally": npc_ally, "summon": summon,
		"lv": lv, "base_lv": base_lv, "exp": xp, "base_exp": base_exp,
		"hp": hp, "hp_max": hp_max, "mp": mp, "mp_max": mp_max,
		"stats": stats.duplicate(), "spirit": spirit.duplicate(), "spirit_points": spirit_points,
		"move_base": move_base, "move_type": move_type, "mag_opp_id": mag_opp_id,
		"x": x, "y": y, "move_cap": move_cap, "move_left": move_left,
		"burst_reserve": burst_reserve, "burst_fresh": burst_fresh,
		"moved": moved, "acted": acted, "extra_action": extra_action,
		"weapon": weapon, "armor": armor, "accessory": accessory,
		"items": items.duplicate(), "skills": skills.duplicate(),
		"status": status, "status_r": sr, "status_k": sk,
		"ai": ai, "ai_target": ai_target.duplicate(), "alive": alive,
		"kill_event": kill_event, "annihilation_exempt": annihilation_exempt,
	}


func from_dict(d: Dictionary):
	for k in d:
		match k:
			"stats":
				stats = {}
				for sk in d[k]:
					stats[sk] = int(d[k][sk])
			"spirit", "items", "skills", "ai_target":
				var arr := []
				for v in d[k]:
					arr.append(int(v))
				set(k, arr)
			"status_r", "status_k":
				var m := {}
				for b in d[k]:
					m[int(b)] = int(d[k][b])
				set(k, m)
			"name":
				name = str(d[k])
			"exp":
				xp = int(d[k])
			"npc_ally", "summon", "burst_fresh", "moved", "acted", "extra_action", "alive", "annihilation_exempt":
				set(k, bool(d[k]))
			_:
				if k in self:
					set(k, int(d[k]))
	return self


## 由 party_init.json 一条记录建主角。base_def = units.json 对应记录 (取 move / move_type / 抗性表)。
static func from_party_init(rec: Dictionary, base_def: Dictionary = {}):
	var u = load("res://engine/rules/unit_state.gd").new()
	u.unit_id = int(rec.get("unit_id", -1))
	u.name = str(rec.get("name", ""))
	u.side = 0
	u.ai = -1
	u.lv = int(rec.get("lv", 1))
	u.xp = int(rec.get("exp", 0))
	u.hp = int(rec.get("hp", 1))
	u.hp_max = u.hp
	u.mp = int(rec.get("mp", 0))
	u.mp_max = u.mp
	for k in AttrNames.STAT_KEYS:
		u.stats[k] = int(rec.get(k, 0))
	var sp: Dictionary = rec.get("spirit", {})
	for i in 5:
		u.spirit[i] = int(sp.get(AttrNames.SPIRIT[i], 0))
	u.spirit_points = int(rec.get("spirit_points", 0))
	u.weapon = -1 if rec.get("weapon") == null else int(rec["weapon"])
	u.armor = -1 if rec.get("armor") == null else int(rec["armor"])
	u.accessory = -1 if rec.get("accessory") == null else int(rec["accessory"])
	for it in rec.get("items", []):
		u.items.append(int(it))
	for s in rec.get("skills", []):
		u.skills.append(int(s))
	if not base_def.is_empty():
		u.move_base = int(base_def.get("move", 20))
		u.move_type = int(base_def.get("move_type", 0))
		u.mag_opp_id = int(base_def.get("attribute_defence_id", 0))
	return u

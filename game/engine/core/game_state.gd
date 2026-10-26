# SPDX-License-Identifier: GPL-3.0-only
class_name GameState
extends RefCounted
## 一局游戏的可序列化状态 (全局进度): 剧情变量、金钱、公共行囊、关卡进度、主角成长。
## 只有数据与对数据的操作, 不碰场景/界面/文件; 存读档见 game_saves.gd, 场景流转见 scripts/game.gd (autoload Game, 持有 Game.state)。

var game_data := {}   # 剧情变量 (重制版 GameUserData.gameData), 事件脚本读写
var gold := 0         # 金钱 (两); 重制版新游戏为 0
var bag: Array = []   # 公共行囊 (物品编号, 容量 params.bag_capacity); 只在营地/商店/炼化, 战斗不可用; 每人 10 格在 party[uid].items
var stage := 0
var next_stage := 0
var camp_no := -1     # 进度值: 当前营地编号 CAMPnn (原版全局 字段, 存档头第一个字段), 由关卡结束 0x02 的 camp 参数或城镇 0x29 p0 设定
var seeded := {}      # 已初次登场的主角 (存档 v1 时代: 已把随身消耗品放进行囊; 现随身物品一直在本人 party[uid].items)
var party := {}       # 主角成长 (单位编号 0~9 -> {lv, exp, hp_max, mp_max, stats, gear}), 关卡之间保留
var gsf_raw := ""     # 外部工具导入存档时附带的原始数据 (base64); 游戏不读, 只随存档带着; "" = 没有


const ROSTER_OUT := 1000  # 0x4F 离队标志在 game_data 里的键基址: ROSTER_OUT + 角色号, 1 = 不在队 (剧情变量只用 0~127)


## 角色是否在队 (原版名册 字段 在队标志, 0x4F set_member 改它; 营地/商店的人物栏只列在队的; 没有标志 = 在队)。
## 名册里「有记录但不在队」的人 (第 8 关后的不净散人、第 14~16 关的上官远、第 15 关没救成的夏侯仪、第 26~28 关的封寒月):
## 复刻的 party 字典仍留着他们的成长与随身物品, 只是不在营地/商店的人物栏里
func in_team(uid: int) -> bool:
	return get_data(ROSTER_OUT + uid) == 0


func get_data(id: int) -> int:
	return game_data.get(id, 0)


func set_data(id: int, v: int) -> void:
	game_data[id] = v


func add_item(id: int) -> void:
	bag.append(id)


func has_item(id: int) -> bool:
	return id in bag


func party_of(uid: int) -> Dictionary:
	return party.get(uid, {})


## 新游戏: 清空进度 (stage 回第 0 关; 其余不变量保持默认)
func reset(start_gold := 0) -> void:
	game_data.clear()
	gold = start_gold   # 原版新游戏金钱 5: 调用方传 params.initial_gold
	bag.clear()
	party.clear()
	seeded.clear()
	gsf_raw = ""
	stage = 0
	next_stage = 0
	camp_no = -1   # 读过档再开新游戏时不带上旧档的进度值


## 存档用字典 (JSON 友好; 键名即存档格式, 改动要升 SaveFile.VERSION 并写迁移)
## 可选字段 gsf_raw 只在非空时写 (普通存档字典与以前一字不差; 加可选字段不升版本, 旧版引擎读到会忽略)
func to_dict() -> Dictionary:
	var d := {"stage": stage, "next_stage": next_stage, "camp": camp_no, "gold": gold, "bag": bag,
		"game_data": game_data, "party": party, "seeded": seeded.keys()}
	if gsf_raw != "":
		d["gsf_raw"] = gsf_raw
	return d


## 存档字典的字段表 (键名 -> 类型); 加字段只改这里 (并按 to_dict 的注释升 SaveFile.VERSION 写迁移)。
## 类型: num 有限数 / str 字符串 / dict 字典 / nums 数字数组 / numdict 键为整数的 {整数键: 数字} / dicts 值为字典、键为整数的字典
const SAVE_FIELDS := {
	"stage": "num", "next_stage": "num", "gold": "num", "camp": "num",
	"bag": "nums", "game_data": "numdict", "seeded": "nums", "party": "dicts",
	"time": "str", "where": "str", "gsf_raw": "str",
}
## 必需字段 (其余可缺: 旧档没有 camp/seeded/time/where, 普通存档没有 gsf_raw); 缺哪个由 missing_field 报给玩家
const SAVE_REQUIRED := ["stage", "next_stage", "gold", "bag", "game_data", "party"]
## 每个主角记录 party[uid] 里出现就必须合法的字段
const PARTY_FIELDS := {"lv": "num", "exp": "num", "hp_max": "num", "mp_max": "num", "gear": "dict", "stats": "dict", "items": "nums"}


## 第一个缺失的必需字段名, 都在返回 ""
static func missing_field(d: Dictionary) -> String:
	for k in SAVE_REQUIRED:
		if not d.has(k):
			return k
	return ""


## 校验存档字典的结构与类型 (apply_dict 之前调用): 通过返回 "", 否则返回给玩家看的提示。
## JSON 可以被截断/手改/写坏成任意形状, 读档与存档位摘要 (slot_info) 不能因此脚本报错或读成半截状态。
static func validate_dict(d: Dictionary) -> String:
	var bad := "存档损坏, 无法读取"
	for k in SAVE_REQUIRED:
		if not d.has(k):
			return bad
	for k in SAVE_FIELDS:
		if d.has(k) and not _type_ok(d[k], SAVE_FIELDS[k]):
			return bad
	for k in d["party"]:
		for n in PARTY_FIELDS:
			if d["party"][k].has(n) and not _type_ok(d["party"][k][n], PARTY_FIELDS[n]):
				return bad
	return ""


static func _type_ok(v, t: String) -> bool:
	match t:
		"num":
			return _num(v)
		"str":
			return v is String
		"dict":
			return v is Dictionary
		"nums":
			return v is Array and (v as Array).all(_num)
		"numdict":
			return v is Dictionary and (v as Dictionary).keys().all(func(k): return _int_key(k) and _num(v[k]))
		"dicts":
			return v is Dictionary and (v as Dictionary).keys().all(func(k): return _int_key(k) and v[k] is Dictionary)
	return false


static func _num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))


static func _int_key(k) -> bool:
	return (k is int) or (k is String and (k as String).is_valid_int())


## 从存档字典恢复 (JSON 读回的数字是 float, 这里转回 int)
func apply_dict(d: Dictionary) -> void:
	stage = int(d["stage"])
	next_stage = int(d["next_stage"])
	camp_no = int(d.get("camp", stage))   # 旧存档没有: 按关卡号
	gold = int(d["gold"])
	bag = d["bag"].map(func(x): return int(x))
	game_data.clear()
	for k in d["game_data"]:
		game_data[int(k)] = int(d["game_data"][k])
	seeded.clear()
	for k in d.get("seeded", []):
		seeded[int(k)] = true
	party.clear()
	for k in d["party"]:
		party[int(k)] = d["party"][k]
	gsf_raw = String(d.get("gsf_raw", ""))   # 缺 = 清空 (读普通存档不能带着上一个导入档的原始字节)


## 确定性回归的全局状态 (engine/test/regress_log.gd): 进度、金钱、行囊、剧情变量、主角成长
func regress_state() -> Dictionary:
	var sd: Array = seeded.keys()
	sd.sort()
	return {"stage": stage, "next_stage": next_stage, "camp": camp_no, "gold": gold, "bag": bag,
		"vars": game_data, "party": party, "seeded": sd}

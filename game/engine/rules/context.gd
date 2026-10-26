# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 规则上下文: 参数 + 随机数 + 只读数据表。各规则模块的静态函数第一个参数都是它。
## 数据表格式与 data/*.json (原版导出) 相同; 内容包可换成自己的表。

const Params = preload("res://engine/rules/params.gd")
const Rng = preload("res://engine/rules/rng.gd")

const ATTR_KEYS := ["雷", "火", "冰", "幻", "光", "暗"]   # 属性编号 0..5; 6 = 治疗

var params
var rng
var items := {}      # 物品编号 -> items.json 记录
var skills := {}     # 技能编号 -> skills.json 记录
var mag_opp := []    # MAG_OPP 抗性表: 行 -> [雷,火,冰,幻,光,暗] (attribute_defense.json)
var levelup := {}    # unit_id -> levelup.json 记录 (成长与习得表)
var units := {}      # unit_id -> units.json 记录 (Man_base)


func _init(p = null, r = null) -> void:
	params = p if p != null else Params.new()
	rng = r if r != null else Rng.new(1)


func item(id: int) -> Dictionary:
	if id < 0:
		return {}
	return items.get(id, {})


func skill(id: int) -> Dictionary:
	return skills.get(id, {})


## MAG_OPP[表][属性] (百分比; 100 = 正常, 0 = 免疫)。属性 6 (治疗) 或缺表时返回 100。
func mag_opp_value(table: int, attribute: int) -> int:
	if attribute < 0 or attribute > 5 or table < 0 or table >= mag_opp.size():
		return 100
	return int(mag_opp[table][attribute])


## 读入记录数组 (运行时由内容包 Content 提供, 已按改动包合并); 不是数组的跳过。空字典 (表中空位) 忽略。
func load_records(item_recs, skill_recs, attr_recs, levelup_recs, unit_recs) -> void:
	if item_recs is Array:
		for rec in item_recs:
			if rec.has("id"):
				items[int(rec["id"])] = rec
	if skill_recs is Array:
		for rec in skill_recs:
			if rec.has("id"):
				skills[int(rec["id"])] = rec
	if attr_recs is Array:
		mag_opp = []
		for rec in attr_recs:
			var row := []
			for k in ATTR_KEYS:
				row.append(int(rec["values"].get(k, 100)))
			mag_opp.append(row)
	if levelup_recs is Array:
		for rec in levelup_recs:
			levelup[int(rec["unit_id"])] = rec
	if unit_recs is Array:
		for rec in unit_recs:
			if rec.has("id"):
				units[int(rec["id"])] = rec


# SPDX-License-Identifier: GPL-3.0-only
class_name BattleStats
extends RefCounted
## 每关战斗统计 (测试/评测用, --battle-stats 时开启): 每人 经验/升级/输出伤害/击杀/承伤/治疗/用的道具,
## 本关得到的东西 (宝箱 + 击杀掉落) 对照「本关应有战利品」。战斗结束时打印「【统计】」行 + 一行 STATS_JSON (机器可读)。
## 只读: 不改任何规则状态; 挂在 BattleFlow.stats, 由 BattleActions / BattleFlow 在结算点调用。

var enabled := GameContext.current().debug.battle_stats
var bs
var rules
var people := {}       # 单位下标 -> 统计字典
var loot_plan := []    # 本关应有战利品 [{kind: chest/drop, key, desc, got}]
var got_other := []    # 不在计划里的获得 (如击杀合并的金钱)
var result := ""
var turns := 0
var deaths: Array = []   # 主角阵亡 [{turn, name, killer}] (BattleFlow.resolve_deaths 里 death() 记)
var _reported := false
static var attempt := 0   # 本进程内第几次进入战斗 (含战败重试)


## 检查点读回时带回开战以来的累计统计 (否则读回后的统计只剩检查点之后的一段)
func export_state() -> Dictionary:
	return {"people": people.duplicate(true), "loot": loot_plan.duplicate(true)}


func begin(scene, battle_rules) -> void:
	if not enabled:
		return
	bs = scene
	rules = battle_rules
	attempt += 1
	_reported = false
	people.clear()
	loot_plan.clear()
	got_other.clear()
	result = ""
	deaths.clear()
	for u in bs.units:
		if u.camp != 1 and (u.controllable or u.st.npc_ally):
			_person(u)
	var me: Dictionary = bs.ctl.map_events
	for e in me:
		var m: Dictionary = me[e]
		if int(m.get("type", -1)) == 1 and int(m.get("item_type", 0)) in [1, 2]:
			var desc := ("金钱%d两" % int(m["item1"])) if int(m["item_type"]) == 2 else _item_name(int(m["item1"]))
			loot_plan.append({"kind": "宝箱", "key": int(e), "desc": desc + ("(隐藏)" if int(m.get("show", 0)) == -1 else ""), "got": false})
	for u in bs.units:
		if u.camp == 1:
			var t := int(u.man.get("kill_get_type", -1))
			if t == 0 or t == 1:
				var p := int(u.man.get("kill_get_parm", 0))
				loot_plan.append({"kind": "掉落", "key": u.index, "desc": ("金钱%d两" % p) if t == 0 else _item_name(p), "from": u.name_text, "got": false})


func _item_name(id: int) -> String:
	return String(rules.ctx.item(id).get("name", "物品%d" % id))


func _person(u) -> Dictionary:
	if not people.has(u.index):
		people[u.index] = {"name": u.name_text, "lv0": u.lv, "exp0": u.exp, "lv": u.lv, "exp_gain": 0, "levels": 0, "attacks": 0, "hits": 0,
			"dmg": 0, "dmg_skill": 0, "kills": 0, "taken": 0, "heal": 0, "casts": {}, "items": {}, "got": [], "learned": [], "friendly_fire": 0, "npc": u.st.npc_ally}
	return people[u.index]


## 普攻 / 反击一段
func strike(a, d, r: Dictionary, ap: Dictionary, _e: int) -> void:
	if not enabled:
		return
	var pa := _person(a) if a.camp != 1 else {}
	var pd := _person(d) if d.camp != 1 else {}
	var hit: bool = int(r.result) != 0
	if not pa.is_empty():
		pa["attacks"] += 1
		if hit:
			pa["hits"] += 1
			pa["dmg"] += int(r.damage)
			if ap.get("killed", false) and d.camp == 1:
				pa["kills"] += 1
	if not pd.is_empty() and hit:
		pd["taken"] += int(r.damage)


func exp_gain(u, e: int, levels: int, learned: Array) -> void:
	if not enabled or u.camp == 1:
		return
	var p := _person(u)
	p["exp_gain"] += e
	p["levels"] += levels
	p["lv"] = u.lv
	p["learned"].append_array(learned)


## 法术 / 绝技 / 发动技能的道具: res = Skills.resolve 结果
func cast(u, sk: Dictionary, res: Dictionary, item_id: int) -> void:
	if not enabled or u.camp == 1:
		return
	var p := _person(u)
	var nm := String(sk.get("name", "?"))
	p["casts"][nm] = int(p["casts"].get(nm, 0)) + 1
	if item_id >= 0:
		var iname := _item_name(item_id)
		p["items"][iname] = int(p["items"].get(iname, 0)) + 1
	for r in res.get("targets", []):
		var t = r.unit
		if t == null:
			continue
		var dmg := int(r.get("damage", 0))
		if t.camp == 1:
			if dmg > 0 and r.get("hit", true) and not r.get("invalid", false):
				p["dmg_skill"] += dmg
				p["dmg"] += dmg
			if r.get("killed", false):
				p["kills"] += 1
		else:
			if dmg > 0 and t != u:
				p["friendly_fire"] += dmg
			p["heal"] += maxi(0, int(r.get("healed", 0))) + maxi(0, -dmg)
			if t.controllable and dmg > 0:
				_person(t)["taken"] += dmg


func item(u, item_id: int, out: Dictionary) -> void:
	if not enabled or u.camp == 1:
		return
	var p := _person(u)
	var nm := _item_name(item_id)
	p["items"][nm] = int(p["items"].get(nm, 0)) + 1
	for r in out.get("res", {}).get("targets", []):
		p["heal"] += maxi(0, int(r.get("healed", 0)))


func treasure(u, event_id: int, desc: String) -> void:
	if not enabled:
		return
	_person(u)["got"].append(desc)
	for l in loot_plan:
		if l["kind"] == "宝箱" and l["key"] == event_id:
			l["got"] = true


func drop(killer, dead_index: int, desc: String) -> void:
	if not enabled:
		return
	_person(killer)["got"].append(desc)
	for l in loot_plan:
		if l["kind"] == "掉落" and l["key"] == dead_index:
			l["got"] = true
			return


## 主角阵亡 (BattleFlow.resolve_deaths 调用)
func death(turn: int, uname: String, killer: String) -> void:
	if enabled:
		deaths.append({"turn": turn, "name": uname, "killer": killer})


## 战斗结束时的剩余血量比 (打分用): foe = 敌方存活单位 hp 合计 / 敌方全体 hp_max 合计 (胜则 0);
## mine = 我方主角 hp 合计 / hp_max 合计 (阵亡的按 0)
func _hp_left() -> Dictionary:
	var fh := 0.0
	var fm := 0.0
	var mh := 0.0
	var mm := 0.0
	for u in bs.units:
		var mx := float(maxi(u.hp_max, 0))
		if u.camp == 1:
			fm += mx
			if u.alive and u.shown:
				fh += float(maxi(u.hp, 0))
		elif u.controllable and GameContext.current().content.is_hero(int(u.man["unit_id"])):
			mm += mx
			if u.alive:
				mh += float(maxi(u.hp, 0))
	var foe := fh / fm if fm > 0.0 else 0.0
	if result != "lose":
		foe = 0.0
	return {"foe": foe, "mine": mh / mm if mm > 0.0 else 0.0}


func report() -> void:
	if not enabled or bs == null or _reported:
		return
	_reported = true
	turns = bs.turn
	var lines: Array = []
	lines.append("【统计】第 %d 关 %s  结果: %s  回合: %d  (本局第 %d 次进入战斗)" % [bs.st.n, bs.st.name, {"": "胜(剧情通关)", "win": "胜", "lose": "败"}.get(result, result), turns, attempt])
	var js := {"stage": bs.st.n, "attempt": attempt, "result": result, "turns": turns, "people": [], "loot": [], "deaths": deaths.duplicate(true)}
	var hl := _hp_left()
	js["foe_hp_left"] = snappedf(hl.foe, 0.0001)
	js["mine_hp_left"] = snappedf(hl.mine, 0.0001)
	for idx in people:
		var p: Dictionary = people[idx]
		if p["attacks"] == 0 and p["exp_gain"] == 0 and p["taken"] == 0 and p["casts"].is_empty() and p["items"].is_empty():
			continue   # 剧情替身 (如第 2 幕过场用的封寒月) 不列
		var casts := ", ".join(p["casts"].keys().map(func(k): return "%s×%d" % [k, p["casts"][k]]))
		var items := ", ".join(p["items"].keys().map(func(k): return "%s×%d" % [k, p["items"][k]]))
		lines.append("  %s%s: 等级 %d→%d (升%d级)  经验 +%d  输出伤害 %d (普攻/反击 %d + 技能 %d, 命中 %d/%d 次)  击杀 %d  承伤 %d  治疗 %d%s" % [p["name"], "(友军)" if p["npc"] else "",
			p["lv0"], p["lv"], p["levels"], p["exp_gain"], p["dmg"], p["dmg"] - p["dmg_skill"], p["dmg_skill"], p["hits"], p["attacks"], p["kills"], p["taken"], p["heal"],
			("  误伤友军 %d" % p["friendly_fire"]) if p["friendly_fire"] > 0 else ""])
		lines.append("      技能: %s   用道具: %s   习得: %s   获得: %s" % [casts if casts != "" else "无", items if items != "" else "无",
			",".join(p["learned"]) if not p["learned"].is_empty() else "无", ", ".join(p["got"]) if not p["got"].is_empty() else "无"])
		var q: Dictionary = p.duplicate(true)
		q["uid"] = idx
		js["people"].append(q)
	var n_got := 0
	var chest_tot := 0
	var chest_got := 0
	for l in loot_plan:
		if l["got"]:
			n_got += 1
		if l["kind"] == "宝箱":
			chest_tot += 1
			if l["got"]:
				chest_got += 1
	lines.append("  本关战利品: 共 %d 项 (宝箱 %d + 击杀掉落 %d), 实得 %d 项 (宝箱 %d/%d)" % [loot_plan.size(), chest_tot, loot_plan.size() - chest_tot, n_got, chest_got, chest_tot])
	for l in loot_plan:
		lines.append("    [%s] %s %s%s" % ["√" if l["got"] else "×", l["kind"], l["desc"], (" ← " + String(l["from"])) if l.has("from") else ""])
		js["loot"].append(l)
	for ln in lines:
		print(ln)
	print("STATS_JSON " + JSON.stringify(js))

# SPDX-License-Identifier: GPL-3.0-only
class_name BattleActions
extends Node
## 行动的结算与演出调度 (玩家与 AI 共用): 普攻交换、法术/绝技、道具、召唤、经验与升级提示。
## 规则全部经 BattleRules (engine/rules) 计算; 这里只安排演出顺序: 近景战斗 (BattleCloseup)、地图动画与飘字 (BattleView)、
## 经验对话与「位階上升」窗 (近景画面里)。结算后的死亡与胜负交给 BattleFlow.resolve_deaths()。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

const Skills = preload("res://engine/rules/skills.gd")
const Items = preload("res://engine/rules/items.gd")
const U = preload("res://engine/rules/unit_state.gd")

var bs
var rules: BattleRules
var view: BattleView
var ui: BattleUi
var closeup: BattleCloseup
var flow  # BattleFlow (死亡处理、击杀者登记)
var _exp_events: Array = []     # 本次行动的经验与升级 (近景里依次显示)
var _pending_exp: Array = []    # 本次战斗各次出手挣到的经验 [[单位, 经验]], 战斗即将结束时统一结算 (_settle_exp)


func _init(scene, battle_rules: BattleRules, battle_view: BattleView, battle_ui: BattleUi, battle_closeup: BattleCloseup) -> void:
	bs = scene
	rules = battle_rules
	view = battle_view
	ui = battle_ui
	closeup = battle_closeup


# ================= 普攻 (03) =================

## 主攻, 守方能反击则反击一次 (BattleRules.exchange -> engine/rules/attack.gd), 在近景战斗画面里演出; 之后死亡处理与胜负
func attack(a: BattleUnit, t: BattleUnit) -> void:
	# 剧情变量 100 = 攻击者, 101 = 被攻击者 (玩家与 AI 都写); 反击不改写。第 8、22 关剧情读它
	gc.state.set_data(100, a.index)
	gc.state.set_data(101, t.index)
	view.face(a, t)
	view.face(t, a)
	view.hide_info()
	_pending_exp = []   # 上一场没结算完 (中途被打断) 的残留不带进这一场
	await closeup.open(a, t)
	var rec := rules.exchange(a, t)
	await closeup.strike(a, t, _kinds(rec.main), "", "", _vampire_of(rec.main_apply))
	_after_strike(a, t, rec.main, rec.main_apply, int(rec.exp_attacker))
	if rec.counter != null:
		await SceneGuard.wait(self, 0.2)
		await closeup.strike(t, a, _kinds(rec.counter), "", "", _vampire_of(rec.counter_apply))
		_after_strike(t, a, rec.counter, rec.counter_apply, int(rec.exp_defender))
	_settle_exp()   # 战斗即将结束: 先结算经验 (死了的拿不到), 才知道有没有升级 -> 升级演出 -> 经验框 (玩家反馈)
	await _level_fx(a)
	if rec.counter != null:
		await _level_fx(t)
	await show_exp()
	await closeup.close()
	view.retint()
	await flow.flush_releases()   # 冰結被打碎: 回到地图后放解除动画与说明框 (实测)
	await flow.resolve_deaths()


## 一次出手的武器吸血量 (近景表现用): 没触发吸血 -1, 触发了就是吸到的量 (可为 0)
static func _vampire_of(ap: Dictionary) -> int:
	return int(ap.get("vampire", 0)) if ap.get("vampire_hit", false) else -1


## 近景演出用的每段结果; 格挡 (红闪避) 带全屏闪色 flash (规则引擎 Attack.guard_flash)
func _kinds(r: Dictionary) -> Array:
	var ks := BattleRules.strike_kinds(r)
	var fl := rules.guard_flash(r)
	for k in ks:
		k["flash"] = fl
	return ks


## 一方出手之后: 击杀者、武器附加、吸血、经验 (原版近景里没有文字提示, 状态与吸血只改数值/颜色, 不飘字)
func _after_strike(a: BattleUnit, d: BattleUnit, r: Dictionary, ap: Dictionary, e: int) -> void:
	print("  %s%s -> %s: %s 伤害 %d%s 剩余 %d/%d 经验 %d" % ["反击 " if r.get("counter", false) else "", a.name_text, d.name_text,
		["未中", "命中", "格挡"][int(r.result)] + (" 会心" if r.crit else "") + (" 连击" if r["double"] else ""), int(r.damage),
		" 击杀" if ap.get("killed", false) else "", d.hp, d.hp_max, e])
	if ap.get("killed", false):
		flow.note_killer(d, a)  # kill_get: 普攻 (含反击) 的击杀者
	flow.stats.strike(a, d, r, ap, e)
	if e > 0:
		_pending_exp.append([a, e])   # 不立刻加: 战斗结束时 (_settle_exp) 还活着才给, 升级也在那时才发现


# ================= 经验与升级 (08) =================

## 战斗即将结束时结算本次战斗挣到的经验: 只给还活着的单位 (主攻挣了经验却被反击打死的拿不到, 没有经验框也没有升级); 加完才知道升没升级
func _settle_exp() -> void:
	var pend := _pending_exp
	_pending_exp = []
	for p in pend:
		if p[0].hp > 0:
			gain_exp(p[0], int(p[1]))


## 加经验 (500 升一级, 成长 / 五魂点 / 习得都在 engine/rules/growth.gd), 记下升级前后的数值供「位階上升」窗显示
func gain_exp(u: BattleUnit, e: int) -> void:
	var before := growth_snapshot(u)
	var ups := rules.gain_exp(u, e)
	var learned: Array = []
	var nlv := 0
	for r in ups:
		nlv += int(r.levels)
		for sid in r.learned:
			learned.append(String(rules.skill(int(sid))["name"]))
	flow.stats.exp_gain(u, e, nlv, learned)
	_exp_events.append({"unit": u, "exp": e, "levels": nlv, "before": before, "after": growth_snapshot(u), "learned": learned})


## u 这次出手升级了: 全部出手演完之后 (经验框之前) 在近景里放升级演出 (握拳 + 光环 + 音效) (原版近景状态 0x12, 见 BattleCloseup.level_up_fx); 每个升级事件只放一次, 只对玩家操作的单位 (我方在近景右侧)
func _level_fx(u) -> void:   # u: BattleUnit (无类型: 测试里换桩)
	if not u.controllable or u.hp <= 0:   # 还活着才有升级演出 (主攻升了级却被反击打死: 不演; 玩家反馈)
		return
	for ev in _exp_events:
		if ev.unit == u and int(ev.levels) > 0 and not bool(ev.get("fx", false)):
			ev["fx"] = true
			await closeup.level_up_fx(u)
			return


## 地图上放法术升级了: 在大地图上放升级光旋 (Misc/Maplup 第 2~14 帧, 帧 2/3 带声音, 见 BattleView.level_up_fx), 随后才弹经验框 (玩家反馈: 法术升级要在大地图上显示, 不进近景)
func _map_level_fx(u) -> void:   # u: BattleUnit (无类型: 测试里换桩)
	if not u.controllable or u.hp <= 0:
		return
	for ev in _exp_events:
		if ev.unit == u and int(ev.levels) > 0 and not bool(ev.get("fx", false)):
			ev["fx"] = true
			await view.level_up_fx(u)
			return


static func growth_snapshot(u: BattleUnit) -> Dictionary:
	return {"lv": u.lv, "hp_max": u.hp_max, "mp_max": u.mp_max, "stats": u.stats.duplicate()}


## 经验提示 (原版): 我方 (玩家操作的) 单位得到经验时, 在当前画面 (近景或地图) 上
##   头像对话框「獲得N歷練值.」(升级时加一行「位階提昇！」, 文本 MLEVPRO.MSG = 内容包 system_text exp_gain),
##   升级时再弹「位階上升」属性对比窗。其他单位只记数值不提示。
func show_exp() -> void:
	var evs := _exp_events
	_exp_events = []
	var texts: Array = Content.system_text("exp_gain")
	for ev in evs:
		var u: BattleUnit = ev.unit
		if not u.controllable:
			continue
		var up: bool = int(ev.levels) > 0
		var t := UiStrings.t("battle.exp.gain", [int(ev.exp)])
		var gi := 1 if up else 0
		if gi < texts.size() and not texts[gi].is_empty():
			t = String(texts[gi][0]).replace("{0}", str(int(ev.exp)))
		print("经验: %s +%d%s 帧%d" % [u.name_text, int(ev.exp), " 升级" if up else "", RegressLog.log_frame])
		await bs.msgbox.show_text(face_of(u), 0, 0, t)
		if up:
			var lay := UiLayer.new(48)  # 在近景 (35) 与对话框 (50) 之间
			add_child(lay)
			var w := UiLevelUp.new(ev.before, ev.after, ev.learned)
			lay.add(w, ScreenLayout.Anchor.CENTER)
			await w.run()
			lay.queue_free()


## 单位的对话头像 (只有主角有, 其他单位 -1)。原版战斗头像取 Man_Face 第 unit_id 帧, 对应剧情用的 FACE{n}: 大多 n = unit_id+1,
##   但 2 上官远 = FACE04、3 紫枫 = FACE03 (对调, 实测 2026-10-11), 所以走布局表 battle.face.by_unit, 缺表/越界回退 unit_id+1
static func face_of(u) -> int:  # u: BattleUnit (无类型: 只读 man)
	var uid := int(u.man["unit_id"])
	if not Content.is_hero(uid):
		return -1
	var by_unit = UiLayout.val("battle.face", "by_unit", [])
	if by_unit is Array and uid >= 0 and uid < by_unit.size():
		return int(by_unit[uid])
	return uid + 1


## 交給提示 (「身上物品太多了…」「放弃给予物品.」「取得X.」) 用的头像。原版实测 (原版 第 1 幕档 + 第 0 幕档):
##   满格提示、放弃提示 = 给出者 (行动单位) 的头像, 不论目标是主角还是友军 NPC;
##   「取得X.」(X = 给出的物品, 对方满格互换时也是它) = 接收者 (目标) 的头像, 目标没有头像 (友军 NPC 应奉仁) 时用给出者的。
## kind: "full" | "cancel" | "got"; 头像号 -1 = 没有
static func give_face(kind: String, giver_face: int, target_face: int) -> int:
	if kind == "got" and target_face >= 0:
		return target_face
	return giver_face


# ================= 法术 / 绝技 (07) =================

## 施放: 结算 (BattleRules.cast -> engine/rules/skills.gd) + 演出 (物理绝技单体进近景; battle_type 2 先施放者单人近景再转地图; 其余在地图上播 Magic 动画) -> 阵亡与胜负。
## item_id >= 0: 道具发动的技能 (扣道具不扣技能消耗, 不给经验)
func cast(u: BattleUnit, sk: Dictionary, c: Vector2i, item_id := -1) -> void:
	print("施放 %s -> %s (%s)" % [sk["name"], c, u.name_text])
	var t0 := Engine.get_process_frames()
	gc.state.set_data(100, u.index)  # 剧情变量 100 = 行动者, 101 = -1 (法术; 道具)
	gc.state.set_data(101, -1)
	view.hide_cursor()
	view.hide_info()
	var hit_units := rules.affected(u, sk, c)
	var res := {}
	var spr := int(u.info["sprite"])
	var bspr := int(sk["battle_sprite"])
	if Skills.is_physical(sk) and int(sk["battle_type"]) == 0 and hit_units.size() == 1 and hit_units[0] != u:
		var t: BattleUnit = hit_units[0]
		view.face(u, t)
		await closeup.open(u, t, Vector2i(-1, -1), int(sk.get("battle_ranged", 0)) == 1)
		res = _resolve_cast(u, sk, c, item_id)
		var r: Dictionary = res.targets[0] if not res.targets.is_empty() else {"hit": false, "invalid": true, "damage": 0, "guard": false}
		var kind := "miss" if r.invalid or not r.hit else ("guard" if r.guard else "hit")
		var atk := ThemeAssets.f("unit_attack_alt", [spr, spr, ("-%d" % bspr) if bspr > 0 else ""])
		await closeup.strike(u, t, [{"kind": kind, "damage": maxi(0, int(r.damage))}], atk, String(sk["name"]), -1, Skills.closeup_digits(sk, r), int(sk.get("battle_ranged", 0)) == 1)
		if int(res.exp) > 0:
			gain_exp(u, int(res.exp))
			await _level_fx(u)
		await show_exp()
		await closeup.close()
		await _cast_results(u, sk, res, false)   # 近景关闭后目标身上仍按结果码放地图结果动画, 不弹数字 (静态)
	else:
		res = _resolve_cast(u, sk, c, item_id)
		var intro: Array = await view.cast_begin(u, String(sk["name"]))  # 镜头到施法者 + 压暗 + 法术名横幅 + 施法光效
		if Skills.has_solo_closeup(sk):   # 近景 + 地图 SM (③): 地图前奏之后进施放者单人近景 (放下剑匣等), 回地图闪一下技能名横幅再放全屏特效
			# 原版 连拍 (2026-10-29, 殷剑平电射星驰): 2.5~4.1 s 地图前奏 (压暗 + 横幅 + 光圈) -> 4.4~8.9 s 近景 (无横幅无守方) -> 9.0~9.3 s 地图上横幅滑入即滑出 -> 9.4 s 起 SM
			await closeup.open(u, null, c)
			await closeup.cast_solo(u, ThemeAssets.f("unit_attack_alt", [spr, spr, ("-%d" % bspr) if bspr > 0 else ""]), "")   # 近景无技能名横幅: 调近景初始化 传 0 (横幅标志 [字段]), 类型 0 传 1
			await closeup.close()
			view.cast_banner(String(sk["name"]), null, 0)
			await SceneGuard.wait(self, 0.4)
		# 法术动画 / 地图演出绝技 (battle_type 1: NNN[-n]S, 2: NNN[-n]SM): 动画、约定、锚点见演出表 fx/cast.json
		await view.cast_fx(CastFx.for_skill(sk, spr), u, c)
		view.cast_end(intro)
		if res.summon:
			view.cast_fade_out(intro, 0.0)
			await summon(u, sk, c)
			return
		await _cast_results(u, sk, res, true)
		await view.cast_fade_out(intro)   # 压暗保持到结果动画之后, 再渐亮 (④)
		if int(res.exp) > 0:
			gain_exp(u, int(res.exp))
			await _map_level_fx(u)
		print("演出到经验 %d 帧" % (Engine.get_process_frames() - t0))   # 演出对照用 (tools/qa 的耗时表读它)
		await show_exp()
	await SceneGuard.wait(self, 0.6)
	view.retint()
	await flow.flush_releases()
	await flow.resolve_deaths()


func _resolve_cast(u: BattleUnit, sk: Dictionary, c: Vector2i, item_id: int) -> Dictionary:
	var res: Dictionary = rules.use_item(u, item_id, c).res if item_id >= 0 else rules.cast(u, sk, c)
	flow.stats.cast(u, sk, res, item_id)
	return res


## 每个目标的结果演出计划 (原版按技能结算写的结果码分派: 动画 字节, 数字 字节; 布局表 map.result_fx,
## 码的含义见 Skills.result_code; 实测 2026-10-18, 差异):
##   码 0 (未命中 / 无效 / 抵抗) = 什么都没有 (没有动画, 也没有「〇」); 其余按码选 MAN_RES 一段; 目标被这一击打死时增益/状态类码退成命中段
##   红数字 = 带伤害数值的结果 (Skills.shows_damage), 值为负 (属性吸收) 画成蓝色; 蓝数字 = 治疗 / 全复 / 术力恢复, 满值时 0 也弹
## 返回 [{unit, frames: [起, 止) 或 [] (不放动画), digit: {value, heal} 或 {} (不弹数字)}], 没有任何演出的目标不在里面
static func result_plan(sk: Dictionary, res: Dictionary) -> Array:
	var d: Dictionary = UiLayout.el("map.result_fx")
	var physical := Skills.is_physical(sk)
	var plan: Array = []
	for r in res.targets:
		var t: BattleUnit = r.unit
		var code := int(r.get("code", 0))
		if t == null or code == 0:
			continue
		var e := {"unit": t, "frames": [], "digit": {}}
		var mode = d.get("code_mode", {}).get(str(code))
		if mode != null:
			if bool(r.killed) and _listed(d.get("dead_fallback", []), code):
				mode = 0
			var seg: Array = d.get("modes", [])[int(mode)]
			e["frames"] = [int(seg[0]), int(seg[1])]
		if _listed(d.get("blue", []), code):
			e["digit"] = {"value": maxi(0, int(r.get("amount", 0))), "heal": true}
		elif _listed(d.get("red", []), code) and Skills.shows_damage(sk, physical):
			e["digit"] = {"value": absi(int(r.damage)), "heal": int(r.damage) < 0}
		if not e["frames"].is_empty() or not e["digit"].is_empty():
			plan.append(e)
	return plan


## 布局表里的整数表 (JSON 读进来是浮点) 里有没有这个码
static func _listed(list: Array, code: int) -> bool:
	return list.any(func(x): return int(x) == code)


## 播放结果演出: 各目标同时放结果动画 (只有第一个出声, 等最长的一段), 播完同时弹数字, 再等数字弹完 (约 1.2 秒); 只有动画没有数字 (状态类) 停 0.5 秒;
## 没有任何结果 (全落空) 就什么都不等 (实测未命中时法术动画一结束镜头就恢复)。digits = false: 近景绝技回到地图后只放动画, 数字近景里已经弹过
func _cast_results(u: BattleUnit, sk: Dictionary, res: Dictionary, digits: bool) -> void:
	var plan := result_plan(sk, res)
	if plan.is_empty():
		return
	var dir := ThemeAssets.p("battle.result_fx")
	var anims: Array = plan.filter(func(e): return not e.frames.is_empty())
	var longest := 0
	for i in anims.size():
		if anims[i].frames[1] - anims[i].frames[0] > anims[longest].frames[1] - anims[longest].frames[0]:
			longest = i
	for i in anims.size():
		var f: Array = anims[i].frames
		if i != longest:
			view.res_anim(anims[i].unit, dir, f[0], f[1], false, 0, i == 0)
	if not anims.is_empty():
		var f: Array = anims[longest].frames
		await view.res_anim(anims[longest].unit, dir, f[0], f[1], true, 0, longest == 0)
	var shown := false
	for e in plan:
		if digits and not e.digit.is_empty():
			view.digits(e.unit, int(e.digit.value), bool(e.digit.heal))
			shown = true
	for r in res.targets:
		if r.killed and r.unit != null:
			flow.note_killer(r.unit, u)  # kill_get: 法术击杀, 施法者是玩家单位才掉落
	await SceneGuard.wait(self, DamageDigits.seconds() if shown else 0.5)


## 召唤: 激活本关预置的同编号隐藏单位, 放到落点, 置召唤标志变量; 当回合即可行动
func summon(u: BattleUnit, sk: Dictionary, c: Vector2i) -> void:
	var su := rules.summon_candidate(sk)
	if su == null:
		return
	su.summon_from(u)
	su.set_cell(c.x, c.y)
	su.summon_flag = Skills.summon_flag_var(rules.ctx, sk)   # 取技能记录自己的 rate10 (103), 不是物品覆盖值
	gc.state.set_data(su.summon_flag, 1)
	su.show_unit(BattleUnit.Dir.SOUTH)
	view.shade(su, rules.can_start_action(su))
	await SceneGuard.wait(self, 0.6)


# ================= 道具 =================

## 道具使用的结果动画区间 (Misc/MAN_RES, 布局表 map.item_fx): 上限提升 (effect 5~11) 弧形旋风 + 白光 18~31, 其余 (回血/回术力/解状态) 紫色火花 46~59。
## 原版实测: 七种上限提升道具全是 18~31, 不是 60~80 (那段后面带星芒碎片, 原版没有)
static func item_fx_range(eff: int) -> Array:
	var d: Dictionary = UiLayout.el("map.item_fx")
	var seg: Array = d.get("limit", [18, 32]) if eff >= int(d.get("limit_from", 5)) and eff <= int(d.get("limit_to", 11)) else d.get("other", [46, 60])
	return [int(seg[0]), int(seg[1])]


## 这种道具效果弹不弹数字: 回血 / 回术力 / 上限提升无条件弹 (值 0 也弹, 字节 + 实测满血金创药仍弹「〇」), 解毒/解麻/解封咒不弹
static func item_has_number(eff: int) -> bool:
	return eff >= 0 and (eff < 2 or eff > 4)


## 道具对一个目标的「增加量」: 回血 / 回术力 / 上限提升的数值 (蓝数字显示它), 解状态是 0 (没有数字)
static func item_amount(r: Dictionary) -> int:
	return maxi(int(r.get("healed", 0)), maxi(int(r.get("mp", 0)), int(r.get("raised", 0))))


## 使用道具 (玩家与 AI 共用): 回复/解状态/上限提升直接结算; 发动技能的道具走 cast
func use_item(u: BattleUnit, item_id: int, c: Vector2i) -> void:
	var sk := Items.skill_of(rules.ctx, item_id)
	if not sk.is_empty():
		await cast(u, sk, c, item_id)
		return
	gc.state.set_data(100, u.index)  # 剧情变量 100 = 行动者, 101 = -1 (道具)
	gc.state.set_data(101, -1)
	view.hide_cursor()
	view.hide_info()
	var eff := int(Items.use_rec(rules.ctx, item_id).get("effect", -1))
	var out := rules.use_item(u, item_id, c)
	flow.stats.item(u, item_id, out)
	await bs.follow_cell(c.x, c.y)
	var seg := item_fx_range(eff)
	var dir := ThemeAssets.p("battle.result_fx")
	for i in range(1, out.res.targets.size()):   # 多目标同时放, 只有第一个出声、等它播完
		view.res_anim(out.res.targets[i].unit, dir, seg[0], seg[1], false)
	if not out.res.targets.is_empty():
		await view.res_anim(out.res.targets[0].unit, dir, seg[0], seg[1], true)
	var shown := false
	for r in out.res.targets:   # 动画播完立刻弹蓝数字 = 增加的量 (回血 / 回术力 / 上限提升, 满值时 0 也弹; 解状态没有数字), 实测
		if item_has_number(eff):
			view.digits(r.unit, item_amount(r), true)
			shown = true
	if shown:
		await SceneGuard.wait(self, DamageDigits.seconds())
	view.retint()
	await SceneGuard.wait(self, 0.6)

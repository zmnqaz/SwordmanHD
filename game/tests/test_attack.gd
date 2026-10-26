# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 03 攻击判定 + 普攻伤害 (第 0 幕 殷剑平 vs 夜魑, 网友数据 实测)
const REQUIRES_TEST := {
	"test_guard_rate_direction": ["data"],
	"test_hit_rate_stage0": ["data"],
	"test_lethal_damage_not_capped": ["data"],
	"test_no_weapon_cannot_counter": ["data"],
	"test_stage0_damage_and_guard": ["data"],
	"test_strike_order_and_miss": ["data"]
}  # 个别方法的依赖 (同上)

const Attack = preload("res://engine/rules/attack.gd")
const Damage = preload("res://engine/rules/damage.gd")


func _yin(c):
	var f = FileAccess.open(data_dir().path_join("party_init.json"), FileAccess.READ)
	var party: Array = JSON.parse_string(f.get_as_text())
	var u = U.from_party_init(party[0], c.units[0])
	u.set_pos(Vector2i(5, 5))
	return u


func _yechi(c):
	var e = Stats.make_enemy(c.units[18], 1)
	e.weapon = 256   # 利爪
	e.armor = 302    # 鳞皮
	e.set_pos(Vector2i(6, 5))
	return e


## 命中: 殷→夜魑 86%、夜魑→殷 89% (贴吧龙吟公式与实测)
func test_hit_rate_stage0():
	var c = ctx_data()
	var y = _yin(c)
	var e = _yechi(c)
	eq(Attack.hit_rate(c, y, e), 86, "殷→夜魑")
	eq(Attack.hit_rate(c, e, y), 89, "夜魑→殷")


## 格挡率 = 5 + (守Luk - 攻Luk)/10: 殷攻夜魑 6, 夜魑攻殷 4 (预期 A)
func test_guard_rate_direction():
	var c = ctx_data()
	var y = _yin(c)
	var e = _yechi(c)
	eq(Attack.guard_rate(c, y, e), 6)
	eq(Attack.guard_rate(c, e, y), 4)
	var c2 = ctx_data(null, {"guard_def_minus_atk": false})
	eq(Attack.guard_rate(c2, y, e), 5, "龙吟式 6 + (18-34)/10 (截断)")


## 状态: 全禦/幻影 → 0, 狂暴 → 100; clamp
func test_hit_rate_status():
	var c = ctx_scripted()
	var a = unit({"luk": 0})
	var d = unit({"luk": 400})
	eq(Attack.hit_rate(c, a, d), 0, "下限 0")
	d.status = U.ST_BERSERK
	eq(Attack.hit_rate(c, a, d), 100, "打狂暴必中")
	d.status = U.ST_GUARD_SKILL | U.ST_BERSERK
	eq(Attack.hit_rate(c, a, d), 0, "對技全禦优先")
	d.status = U.ST_PHANTOM
	eq(Attack.hit_rate(c, a, d), 0, "幻影")


## /3.3 会心、连击只看武器+饰物 (护具不计), 狂暴会心 ×1.5
func test_crit_double_equipment_only():
	var c = ctx_scripted()
	add_item(c, 1, {"critical": 10, "double": 7})
	add_item(c, 2, {"critical": 50, "double": 50})   # 护具: 不计
	add_item(c, 3, {"critical": 5, "double": 3})
	var a = unit({"weapon": 1, "armor": 2, "accessory": 3, "luk": 300})
	eq(Attack.crit_rate(c, a), 15)
	eq(Attack.double_rate(c, a), 10)
	a.status = U.ST_BERSERK
	eq(Attack.crit_rate(c, a), 22, "int(15×1.5)")


## 第 0 幕: 殷普攻夜魑 22, 被格挡 9 = 22/2 - 24/10 (网友数据 #4)
func test_stage0_damage_and_guard():
	var c = ctx_data(ScriptedRng.new([0]))   # 运气除数 10+0 → 18/10 = 1
	var y = _yin(c)
	var e = _yechi(c)
	var raw: int = Damage.phys_damage(c, y, e, false)
	eq(raw, 44 - 23 + 1, "ATK44 - DEF23 + Luk18/10")
	eq(Damage.strike_damage(c, raw, false, false, e), 22)
	eq(Damage.strike_damage(c, raw, false, true, e), 9, "格挡 22/2 - 2")
	# 夜魑打殷: 70 - 27 + 34/(10..20) → 44..46 (实测 45)
	var c2 = ctx_data(ScriptedRng.new([2]))   # 除数 12 → 2
	eq(Damage.phys_damage(c2, e, y, false), 45, "夜魑→殷 45")


## 保底: 伤害不足 1 按 1; 连击在保底之后 ×2; 格挡后再保底 1
func test_min_damage_rules():
	var c = ctx_scripted()
	var weak = unit({"str": 1, "luk": 0})
	var tank = unit({"vit": 400})
	eq(Damage.phys_damage(c, weak, tank, false), 0, "函数本身 >= 0")
	eq(Damage.strike_damage(c, 0, false, false, tank), 1, "命中保底 1")
	eq(Damage.strike_damage(c, 0, true, false, tank), 2, "保底后连击 ×2")
	eq(Damage.strike_damage(c, 0, false, true, tank), 1, "格挡保底 1")
	eq(Damage.strike_damage(c, 100, true, true, tank), 60, "连击 200 → 格挡 100 - 40")


## 会心 = 守方防御再减半; 攻升 ×1.2, 护禦 ×1.2, 狂暴 攻×2 防/2
func test_phys_damage_modifiers():
	var c = ctx_scripted()
	var a = unit({"str": 100, "luk": 0})
	var d = unit({"vit": 100})          # DEF 50
	eq(Damage.phys_damage(c, a, d, false), 50)
	eq(Damage.phys_damage(c, a, d, true), 75, "会心: 100 - 25")
	a.status = U.ST_ATK_UP
	eq(Damage.phys_damage(c, a, d, false), 70, "120 - 50")
	a.status = 0
	d.status = U.ST_DEF_UP
	eq(Damage.phys_damage(c, a, d, false), 40, "100 - 60")
	d.status = U.ST_BERSERK
	a.status = U.ST_BERSERK
	eq(Damage.phys_damage(c, a, d, false), 175, "200 - 25")
	# 运气项 Luk/(10+rand%11): 除数 10..20
	var b = unit({"str": 100, "luk": 40})
	eq(Damage.phys_damage(ctx_scripted([0]), b, d, false), 175 - 75 + 4 - 100 + 25 + 0 if false else 100 - 25 + 4, "Luk40/10")
	eq(Damage.phys_damage(ctx_scripted([10]), b, d, false), 100 - 25 + 2, "Luk40/20")
	eq(Damage.phys_damage(ctx_scripted(), b, d, false, true), 100 - 25 + 2, "AI 估算 Luk/15")


## 判定顺序: 命中 → 会心 → 连击 → 伤害随机 → 格挡 → 附加; 未命中只取 1 个随机数
func test_strike_order_and_miss():
	var c = ctx_data(ScriptedRng.new([86]))   # 86 >= 86 → 未命中
	var y = _yin(c)
	var e = _yechi(c)
	var r := Attack.strike(c, y, e)
	eq(r.result, Attack.Result.MISS)
	eq(r.damage, 0)
	eq(c.rng.used, 1, "未命中只取一次随机数")
	# 命中(0) 会心(0<3) 连击(0<3) 运气除数(0→10) 格挡(99 不中)
	var c2 = ctx_data(ScriptedRng.new([0, 0, 0, 0, 99]))
	r = Attack.strike(c2, _yin(c2), _yechi(c2))
	eq(r.result, Attack.Result.HIT)
	check(r.crit and r["double"], "会心+连击")
	# 会心: DEF 23/2=11 → 44-11+1 = 34, 连击 ×2 = 68
	eq(r.damage, 68)
	# 会心 + 连击 + 格挡 同时出现: 68/2 - 2 = 32
	var c3 = ctx_data(ScriptedRng.new([0, 0, 0, 0, 5]))
	r = Attack.strike(c3, _yin(c3), _yechi(c3))
	eq(r.result, Attack.Result.GUARD)
	eq(r.damage, 32)


## 致死一击: 记录里的伤害是完整值 (不封顶为当前 HP), 显示与经验都读它 [存未截断值]
func test_lethal_damage_not_capped():
	var c = ctx_data(ScriptedRng.new([0, 99, 99, 0, 99]))
	var y = _yin(c)
	var e = _yechi(c)
	e.hp = 5
	var r := Attack.strike(c, y, e)
	check(r.damage > 5, "伤害超过剩余 HP")
	var out := Attack.apply_strike(c, y, e, r)
	check(out.killed and e.hp == 0, "致死, HP 归 0")


## 射程 (min 为开区间下限)
func test_range_rules():
	var o := Vector2i(10, 10)
	eq(Attack.range_cells(o, {"type": 0, "min": -1, "max": 1}).size(), 4, "普通武器 4 格")
	check(not Attack.in_range(o, o, {"type": 0, "min": -1, "max": 1}), "-1 排除自身")
	eq(Attack.range_cells(o, {"type": 0, "min": -1, "max": 2}).size(), 12, "千幻流光 1~2")
	var dark := {"type": 0, "min": 2, "max": 4}
	check(not Attack.in_range(o, o + Vector2i(2, 0), dark), "暗器 min2 不含距离 2")
	check(Attack.in_range(o, o + Vector2i(2, 1), dark), "距离 3")
	check(Attack.in_range(o, o + Vector2i(0, 4), dark), "距离 4")
	var ring := {"type": 0, "min": 4, "max": 9}
	check(not Attack.in_range(o, o + Vector2i(4, 0), ring) and Attack.in_range(o, o + Vector2i(5, 0), ring), "光輪斬 5~9")
	var heal := {"type": 0, "min": 0, "max": 4}
	check(Attack.in_range(o, o, heal), "min 0 含自身")
	eq(Attack.range_cells(o, {"type": 0, "min": 0, "max": 0}), [o], "0/0 = 自身")
	eq(Attack.range_cells(o, {"type": 0, "min": 3, "max": 3}), [o], "空集且 min≠-1 → 回退自身")
	var line := {"type": 1, "min": 0, "max": 5}
	eq(Attack.range_cells(o, line).size(), 21, "直线 0/5: 中心 + 4×5")
	eq(Attack.range_cells(o, {"type": 1, "min": -1, "max": 3}).size(), 12, "直线 -1/3 不含中心")


## 反击: 麻痺/冰結/保留点/射程外 不反击; 只反击一次
func test_counter_conditions():
	var c = ctx_scripted()
	add_item(c, 49, {})   # 普通武器 射程 -1/1 (无武器单位射程只有自身格)
	var a = unit({})
	var d = unit({"side": 1, "weapon": 49})
	a.set_pos(Vector2i(0, 0))
	d.set_pos(Vector2i(1, 0))
	check(Attack.can_counter(c, d, a), "相邻可反击")
	d.status = U.ST_PARALYZE
	check(not Attack.can_counter(c, d, a), "麻痺")
	d.status = U.ST_FREEZE
	check(not Attack.can_counter(c, d, a), "冰結")
	d.status = 0
	d.burst_reserve = 10
	check(not Attack.can_counter(c, d, a), "爆發保留点")
	d.burst_reserve = 0
	a.set_pos(Vector2i(4, 0))
	check(not Attack.can_counter(c, d, a), "射程外")
	add_item(c, 50, {"attack_range": {"type": 0, "area": 0, "min": 2, "max": 4}})
	d.weapon = 50
	check(Attack.can_counter(c, d, a), "暗器 3 格可反击")
	a.set_pos(Vector2i(2, 0))
	check(not Attack.can_counter(c, d, a), "暗器 1 格不能反击")


## 冰結: 受到伤害即解除 → 第一次打不被反击, 第二次被反击
func test_exchange_freeze_breaks():
	var c = ctx_scripted()
	add_item(c, 1, {"hit": 100})
	var a = unit({"str": 60, "weapon": 1})
	var d = unit({"side": 1, "weapon": 1})
	a.set_pos(Vector2i(0, 0))
	d.set_pos(Vector2i(1, 0))
	d.status = U.ST_FREEZE
	d.status_r = {U.ST_FREEZE: 1}
	d.status_k = {U.ST_FREEZE: 1}
	var rec := Attack.exchange(c, a, d)
	check(rec.counter == null, "第一次打冰結单位不被反击")
	check(not d.has_status(U.ST_FREEZE), "受伤后冰結已解")
	rec = Attack.exchange(c, a, d)
	check(rec.counter != null, "第二次被反击")


## 武器附加: 吸血 dmg/3; 只在未格挡时; 饰物的附加字段无效
func test_weapon_vampire():
	var c = ctx_scripted([0, 99, 99, 0, 99, 0])   # 命中, 不会心, 不连击, 运气, 不格挡, 附加成功
	add_item(c, 27, {"attack": 50, "hit": 100, "attack_add": {"type": 0, "ratio": 100, "time": 0, "cost": 0}})
	var a = unit({"weapon": 27, "str": 50, "luk": 0, "hp": 10})
	var d = unit({"side": 1, "vit": 0, "luk": 0})
	var r := Attack.strike(c, a, d)
	eq(r.damage, 100)
	check(r.add, "附加触发")
	var ap := Attack.apply_strike(c, a, d, r)
	eq(ap.vampire, 33, "吸血 100/3")
	eq(a.hp, 43)
	var c2 = ctx_scripted()
	add_item(c2, 180, {"attack_add": {"type": 0, "ratio": 20, "time": 0, "cost": 0}})
	var b = unit({"accessory": 180})
	eq(Attack.add_rate(c2, b, d), 0, "煉血珠 (饰物) 吸血无效")


## exchange 的 post_strike 钩子 (战场 --god 用): 在 strike 之后、apply 之前可改结果
func test_exchange_post_strike_hook():
	var c = ctx_data()
	var a = unit({"side": 0, "uid": 1, "str": 50})
	var d = unit({"side": 1, "uid": 2, "hp": 100, "hp_max": 100})
	a.set_pos(Vector2i(0, 0))
	d.set_pos(Vector2i(1, 0))
	var calls := []
	var rec := Attack.exchange(c, a, d, func(x, y, r):
		calls.append([x.uid, y.uid])
		if x == a:
			r.result = Attack.Result.MISS
			r.damage = 0)
	check(calls.size() >= 1 and calls[0] == [1, 2], "钩子按 (攻方, 守方) 调用")
	eq(rec.main.damage, 0, "钩子改了结果, apply 用改后的")
	eq(d.hp, 100, "未受伤")


## 毒/麻/封武器附加触发时, 原版 strike 内先后调 R 函数 与 K 函数, 各取 1 次随机数
## (原版 对照: 同种子 8 次取数, 旧实现 7 次); 估价时不取; 与目标是否被打死无关
func test_weapon_status_add_draws_two_rands():
	var c = ctx_scripted()
	add_item(c, 190, {"hit": 100, "attack_add": {"type": 1, "ratio": 100, "time": 200, "cost": 100}})
	var a = unit({"weapon": 190, "str": 50, "luk": 0})
	var d = unit({"vit": 0, "luk": 0, "hp": 1, "hp_max": 1})
	c.rng.queue = [0, 99, 99, 0, 99, 0]   # 命中 会心否 连击否 运气 格挡否 附加触发
	var r := Attack.strike(c, a, d)
	check(r.add, "附加触发")
	eq(c.rng.used, 8, "6 次判定 + R + K")
	Attack.apply_strike(c, a, d, r)
	eq(c.rng.used, 8, "apply 不再取随机数 (目标已死也一样)")
	var c2 = ctx_scripted()
	c2.items = c.items
	c2.rng.queue = [0, 99, 99, 99, 0]   # 估价无运气项取数
	Attack.strike(c2, a, d, false, true)
	eq(c2.rng.used, 5, "估价: 运气项固定, R/K 不取随机数 (只剩 5 次判定)")


## 无武器单位: 原版读物品 -1 (全 0 记录) 得射程菱形 min0/max0 = 只有自身格, 邻格守方无武器时不反击 (原版 对照 5/5)
func test_no_weapon_cannot_counter():
	var c = ctx_data()
	var a = unit({"weapon": 0})
	var d = unit({"weapon": -1})
	a.set_pos(Vector2i(5, 5))
	d.set_pos(Vector2i(5, 6))
	check(not Attack.can_counter(c, d, a), "无武器不反击")
	d.weapon = 0
	check(Attack.can_counter(c, d, a), "有武器邻格反击")


## 近景吸血表现看「触发」不看吸到多少 (实测: 满血吸 0 也放光环、弹蓝〇); 没触发 (未命中/格挡/没抽到附加) 不放
func test_vampire_trigger_flag_even_at_zero():
	var c = ctx_scripted([0, 99, 99, 0, 99, 0])
	add_item(c, 27, {"attack": 50, "hit": 100, "attack_add": {"type": 0, "ratio": 100, "time": 0, "cost": 0}})
	var a = unit({"weapon": 27, "str": 50, "luk": 0, "hp": 71, "hp_max": 71})
	var d = unit({"side": 1, "vit": 0, "luk": 0})
	var r := Attack.strike(c, a, d)
	var ap := Attack.apply_strike(c, a, d, r)
	eq(ap.vampire, 0, "满血吸 0")
	check(ap.get("vampire_hit", false), "但吸血触发了")
	eq(BattleActions._vampire_of(ap), 0, "近景要演 (量 0)")
	var miss := Attack.apply_strike(c, a, d, {"result": Attack.Result.MISS, "damage": 0, "add": false})
	check(not miss.get("vampire_hit", false), "未命中不触发")
	eq(BattleActions._vampire_of(miss), -1, "近景不演")


## 吸血 = min(伤害, 目标受击前剩余 HP)/3 (致命一击只吸目标剩余血量的 1/3)
func test_vampire_uses_target_remaining_hp():
	var c = ctx_scripted()
	add_item(c, 191, {"hit": 100, "attack_add": {"type": 0, "ratio": 100, "time": 0, "cost": 0}})
	var a = unit({"weapon": 191, "str": 200, "luk": 0, "hp": 1, "hp_max": 500})
	var d = unit({"vit": 0, "luk": 0, "hp": 30, "hp_max": 30})
	c.rng.queue = [0, 99, 99, 0, 99, 0]
	var r := Attack.strike(c, a, d)
	check(r.damage > 30, "伤害远超目标剩余血量")
	var ap := Attack.apply_strike(c, a, d, r)
	eq(ap.vampire, 10, "30/3, 不是 伤害/3")

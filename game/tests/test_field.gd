# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 原版实测定案回归。
## 每个用例的数字直接取自实测记录。
const REQUIRES_TEST := {
	"test_t02_burst_no_def_drop": ["data"],
	"test_t05_t06_no_effect_spells": ["data"],
	"test_t07_weapon_status_counter_only": ["data"],
	"test_t08_type4_mult_is_target_x": ["data"],
	"test_t08_zijin_add4": ["data"],
	"test_t09_tianrui_mp": ["data"],
	"test_t10_recall_cannot_act": ["data"],
	"test_t17_self_destruct_threshold": ["data"],
	"test_t24_stage3_wave2_dead_event": ["content"],
	"test_t25_unmoved_ai_skips_map_event": ["content"],
	"test_t32_freeze_measured": ["data"]
}  # 个别方法的依赖 (同上)

const Movement = preload("res://engine/rules/movement.gd")
const Attack = preload("res://engine/rules/attack.gd")
const Damage = preload("res://engine/rules/damage.gd")
const Status = preload("res://engine/rules/status.gd")
const Skills = preload("res://engine/rules/skills.gd")
const Growth = preload("res://engine/rules/growth.gd")
const Exp = preload("res://engine/rules/exp.gd")
const Flow = preload("res://engine/rules/flow.gd")
const Items = preload("res://engine/rules/items.gd")


func _yin(c):
	var f = FileAccess.open(data_dir().path_join("party_init.json"), FileAccess.READ)
	var party: Array = JSON.parse_string(f.get_as_text())
	var u = U.from_party_init(party[0], c.units[0])
	u.set_pos(Vector2i(5, 5))
	return u


## 格挡 = clamp(5 + (守Luk - 攻Luk)/10): 夜魑 L34→NPC L154 17; NPC→夜魑 0; NPC 改 Luk0 后 8 / 2
func test_t01_guard_measured():
	var c = ctx_scripted()
	var yechi = unit({"luk": 34})
	var npc = unit({"luk": 154})
	var npc0 = unit({"luk": 0})
	eq(Attack.guard_rate(c, yechi, npc), 17)
	eq(Attack.guard_rate(c, npc, yechi), 0)
	eq(Attack.guard_rate(c, npc0, yechi), 8, "Luk0 攻 Luk34")
	eq(Attack.guard_rate(c, yechi, npc0), 2, "Luk34 攻 Luk0")


## 爆發不降防: 殷剑平 (Vit 24) 爆發中 / 未爆發 DEF 都是 27
func test_t02_burst_no_def_drop():
	var c = ctx_data()
	var y = _yin(c)
	eq(Stats.def(c, y), 27, "未爆發")
	y.burst_reserve = 23
	eq(Stats.def(c, y), 27, "爆發中")


## 速敏: m = 23 + 296/25 = 34 → int(34×1.5) = 51; 爆發 51 → 下回合 1a=51 1c=51 1e=102; 移动消耗 5 → 1c=46, 1a=51
func test_t29_haste_reserve_measured():
	var c = ctx_scripted()
	var u = unit({"move_base": 23, "avg": 296})
	u.status = U.ST_HASTE
	Movement.begin_phase(c, u)
	eq(u.move_cap, 51, "无保留点: 字段 = 字段 = 51")
	check(Movement.burst(c, u), "原地爆發")
	eq(u.burst_reserve, 51)
	Movement.begin_phase(c, u)
	eq([Movement.cur_points(u), u.burst_reserve, u.move_cap], [51, 51, 102], "不是 int((34+51)×1.5)=127")
	Movement.spend(u, 5)
	u.moved = true
	eq([Movement.cur_points(u), u.burst_reserve], [51, 46], "移动先扣保留点")
	# 移动过就不能爆發 (1a + 1c != 1e)
	check(not Movement.can_burst(c, u), "移动后爆發灰")


## 连续爆發: 第二回合菜单可选; 再爆發后 1a=0 1c=23 1e=46; 第三回合仍 23/23/46 (不累积)
func test_t30_burst_again_not_accumulate():
	var c = ctx_scripted()
	var u = unit({"move_base": 23, "avg": 0})
	Movement.begin_phase(c, u)
	Movement.burst(c, u)
	Movement.begin_phase(c, u)
	eq([Movement.cur_points(u), u.burst_reserve, u.move_cap], [23, 23, 46])
	check(Movement.can_burst(c, u), "带保留点未移动: 可选")
	Movement.burst(c, u)
	eq([Movement.cur_points(u), u.burst_reserve], [0, 23], "保留点被当前移动点覆盖")
	Movement.begin_phase(c, u)
	eq([Movement.cur_points(u), u.burst_reserve, u.move_cap], [23, 23, 46], "第三回合不是 1c=46")
	var c2 = ctx_scripted([], {"burst_accumulate": true})
	var v = unit({"move_base": 23, "avg": 0})
	Movement.begin_phase(c2, v)
	Movement.burst(c2, v)
	Movement.begin_phase(c2, v)
	Movement.burst(c2, v)
	eq(v.burst_reserve, 46, "魔改开关: 累积")


## 武器附加毒/麻/封: 主攻 R=0<K 永不生效; 反击以 R=K=0 施加, 目标阵营下一阶段开始即解除
func test_t07_weapon_status_counter_only():
	var c = ctx_data()
	var a = unit({"weapon": 92, "luk": 20})   # 搜魂攫魄爪 麻痹 ratio 200
	var d = unit({"side": 1, "luk": 20, "int": 30, "hp": 60000, "hp_max": 60000})
	# 命中 0 / 不会心 99 / 不连击 99 / 运气 0 / 不格挡 99 / 附加 0 / K 的 rand 0
	c.rng = ScriptedRng.new([0, 99, 99, 0, 99, 0, 0])
	var r := Attack.strike(c, a, d)
	check(r.add, "附加判定成功")
	var ap := Attack.apply_strike(c, a, d, r)
	eq(ap.status_applied, 0, "主攻: 抵抗")
	check(not d.has_status(U.ST_PARALYZE))
	c.rng = ScriptedRng.new([0, 99, 99, 0, 99, 0, 0])
	var r2 := Attack.strike(c, a, d, true)
	var ap2 := Attack.apply_strike(c, a, d, r2)
	eq(ap2.status_applied, U.ST_PARALYZE, "反击: 施加")
	eq([d.status_r[U.ST_PARALYZE], d.status_k[U.ST_PARALYZE]], [0, 0], "R=K=0")
	check(not Attack.can_counter(c, d, a), "本阶段内不能反击")
	Status.phase_tick(c, d)
	check(not d.has_status(U.ST_PARALYZE), "目标阵营下一阶段开始解除")
	# 魔改: R=time K=cost 主攻也生效
	var c2 = ctx_data(ScriptedRng.new([0, 99, 99, 0, 99, 0]), {"weapon_status_mode": "custom"})
	var d2 = unit({"side": 1, "luk": 20, "hp": 60000, "hp_max": 60000})
	var r3 := Attack.strike(c2, a, d2)
	Attack.apply_strike(c2, a, d2, r3)
	eq(d2.status_r.get(U.ST_PARALYZE, -1), 100, "custom: R=time")


## 紫金劍 type 4: 触发时伤害 ×19/100 (298→56, 271→51, 280→53), 不附加状态
func test_t08_zijin_add4():
	var c = ctx_data()
	var a = unit({"weapon": 6, "luk": 999})
	var d = unit({"side": 1, "luk": 0})
	eq(Attack.add_rate(c, a, d), 99, "ratio 0 + 999/10 → 99")
	# 原版 实测的 298→56 等 = 倍率 19 = 当时目标格 x=19 (w1 对照: 倍率其实是目标格 x, 见 Attack.type4_mult)
	eq([Attack.add4_damage(c, a, d, 298, 19), Attack.add4_damage(c, a, d, 271, 19), Attack.add4_damage(c, a, d, 280, 19)], [56, 51, 53])
	c.rng = ScriptedRng.new([0, 99, 99, 0, 99, 0])
	var r := Attack.strike(c, a, d, false, false, 19)
	var raw: int = Damage.phys_damage(ctx_data(ScriptedRng.new([0])), a, d, false)
	check(r.add and r.add_type == 4)
	eq(r.damage, maxi(1, raw) * 19 / 100, "本次伤害被替换 (玩家光标路径, 倍率 = 目标格 x)")
	var ap := Attack.apply_strike(c, a, d, r)
	eq(ap.status_applied, 0)
	eq(d.status, 0, "不地缚")


## 天瑞仙舞: 目标 MP 1000→1050, 移动点 40 不变; 施术者 -50 MP
func test_t09_tianrui_mp():
	var c = ctx_data()
	var sk: Dictionary = c.skill(55)
	var caster = unit({"mp": 500, "mp_max": 500})
	caster.move_left = 60
	var t = unit({"mp": 1000, "mp_max": 2000})
	t.move_left = 40
	check(Skills.can_use(c, caster, sk))
	Skills.consume(c, caster, sk)
	Skills.resolve(c, caster, sk, [t])
	eq(t.mp, 1050)
	eq(t.move_left, 40, "不回移动力")
	eq(caster.mp, 450)


## 返召之咒: 只置可行动标志, 已行动单位移动点为 0 → 不能再行动
func test_t10_recall_cannot_act():
	var c = ctx_data()
	var sk: Dictionary = c.skill(41)
	var t = unit({"move_base": 20})
	Movement.begin_phase(c, t)
	check(Movement.can_start_action(t), "阶段开始可行动")
	Movement.end_action(t)
	eq(t.move_left, 0, "行动结束 字段 清 0")
	Skills.resolve(c, unit({"mp": 300}), sk, [t])
	check(t.extra_action and not t.acted, "字段 = 1")
	check(not Movement.can_start_action(t), "移动点 0: 连原地格都不能确认")
	var c2 = ctx_data(null, {"recall_resets_move": true})
	var t2 = unit({"move_base": 20})
	Movement.begin_phase(c2, t2)
	Movement.end_action(t2)
	Skills.resolve(c2, unit({"mp": 300}), sk, [t2])
	check(Movement.can_start_action(t2), "魔改: 完整再行动")


## 冥幻之陣 / 幽冥返召、遁地神行: 只扣 MP, 无任何状态与移动类型变化
func test_t05_t06_no_effect_spells():
	var c = ctx_data()
	for sid in [63, 36, 37]:
		var sk: Dictionary = c.skill(sid)
		var caster = unit({"mp": 1000, "mp_max": 1000})
		var t = unit({"move_type": 0})
		Skills.consume(c, caster, sk)
		var r := Skills.resolve(c, caster, sk, [t])
		eq(caster.mp, 1000 - int(sk["mp_cost"]), "%d 扣 MP" % sid)
		eq([t.status, t.move_type, t.status_r.size()], [0, 0, 0], "%d 无效果" % sid)
		eq(r.exp, 0)
	eq([int(c.skill(63)["mp_cost"]), int(c.skill(36)["mp_cost"]), int(c.skill(37)["mp_cost"])], [500, 100, 70])


## 自爆: HPmax 1005 时 HP 503 不可用、502 可用; 还要剩余移动点 >= move_cost 30
func test_t17_self_destruct_threshold():
	var c = ctx_data()
	var sk: Dictionary = c.skill(70)
	var u = unit({"hp_max": 1005, "hp": 503, "side": 1})
	u.move_left = 30
	check(not Skills.can_use(c, u, sk), "503 > 502")
	u.hp = 502
	check(Skills.can_use(c, u, sk), "502 可用")
	u.move_left = 29
	check(not Skills.can_use(c, u, sk), "移动点 29 < 30")


## 冰結: 几率 rate10 - 2×目标魂 (天霜雪舞 80, 魂 20 → 40; rand 19 冰結); R=K=1;
## 受击即解 (伤害 0 也解); 目标阵营下一阶段开始解除
func test_t32_freeze_measured():
	var c = ctx_data()
	var sk: Dictionary = c.skill(16)
	eq(int(sk["rate10"]), 80)
	var caster = unit({"int": 0, "luk": 0})
	var t = unit({"side": 1, "hp": 5000, "hp_max": 5000, "luk": 0})
	t.spirit = [0, 0, 0, 0, 20]
	# 命中 0 / P 的随机 0 / 冰結 19
	c.rng = ScriptedRng.new([0, 0, 19])
	Skills.resolve(c, caster, sk, [t])
	check(t.has_status(U.ST_FREEZE), "19 < 40 冰結")
	eq([t.status_r[U.ST_FREEZE], t.status_k[U.ST_FREEZE]], [1, 1])
	var t2 = unit({"side": 1, "hp": 5000, "hp_max": 5000, "luk": 0})
	t2.spirit = [0, 0, 0, 0, 20]
	c.rng = ScriptedRng.new([0, 0, 40])
	Skills.resolve(c, caster, sk, [t2])
	check(not t2.has_status(U.ST_FREEZE), "40 不 < 40")
	Damage.apply_damage(t, 0)
	check(not t.has_status(U.ST_FREEZE), "伤害 0 的命中也解冰")
	Status.apply(t, U.ST_FREEZE, 1, 1)
	Status.phase_tick(c, t)
	check(not t.has_status(U.ST_FREEZE), "阶段开始 R 1→0 移除")


## 成长随机项 0..N 都会出现: Str N+1=4 取到 0,1,2,3
func test_t03_growth_remainders():
	var c = ctx_scripted([0, 1, 2, 3])
	var seen := []
	for i in 4:
		seen.append(Growth._rand_term(c, 3))
	eq(seen, [0, 1, 2, 3])


## T34 HPmax/MPmax 无上限, u16 回绕: 65530 升级 +15 → 9
func test_t34_hp_wrap():
	var c = ctx_scripted()
	eq(Growth.add_u16(c, 65530, 15), 9)
	eq(Growth.add_u16(ctx_scripted([], {"hp_mp_u16_wrap": false}), 65530, 15), 65535, "自定: 封顶")
	var u = unit({"lv": 10, "vit": 10, "int": 10, "hp": 65530, "hp_max": 65530, "mp": 65530, "mp_max": 65530})
	Growth.level_up(c, u, {"hp_rand": 0, "mp_rand": 0})
	eq(u.hp_max, (65530 + 3) & 0xFFFF, "回绕")
	eq(u.hp, 65530, "当前 HP 不变 (大于上限)")


## 祝福 K 用目标 Int: 目标 Int 80, rate10 100 → 68 (÷5) / 80 (÷8)
func test_t11_bless_k_target_int():
	var t = unit({"int": 80})
	eq(Status.bless_k(ctx_scripted([0]), t, 100), 68)
	eq(Status.bless_k(ctx_scripted([3]), t, 100), 80)


## 两佰块 (base_exp 1, 有效等级 91): lv79 杀 → 2 (d 截到 10, k=2); lv86 杀 → 1 (k=1.75)
## 截断: base 7, 有效等级 78, lv79 (k=0.81) → 5.67 实得 5
func test_t20_t27_exp_truncation():
	var c = ctx_scripted()
	var e91 = unit({"side": 1, "lv": 90, "base_lv": 1, "base_exp": 1})
	eq(Exp.kill_exp(c, unit({"lv": 79}), e91), 2)
	eq(Exp.kill_exp(c, unit({"lv": 86}), e91), 1)
	var e78 = unit({"side": 1, "lv": 77, "base_lv": 1, "base_exp": 7})
	eq(Exp.kill_exp(c, unit({"lv": 79}), e78), 5, "截断, 不是 round 的 6")


## 第 0 幕 1 级殷剑平击杀夜魑 (有效等级 6, base 170, k=1.75): 297 (旧代码 255)
func test_stage0_lv1_kill_297():
	var c = ctx_scripted()
	var e = unit({"side": 1, "lv": 6, "base_exp": 170, "hp_max": 89})
	eq(Exp.kill_exp(c, unit({"lv": 1}), e), 297)
	eq(Exp.attack_exp(c, unit({"lv": 1}), e, true, 22, false), 73)


## 参数默认值 = 实测
func test_t21_t22_params():
	var p = Params.new()
	eq(p.bag_capacity, 512)
	eq(p.initial_gold, 5)
	eq(p.equip_costs_action, false)
	eq(p.turn_limit, 100)


func _content_json(rel: String):
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/tdj/" + rel))


## 战斗中装备/丢弃不耗行动: 燕明蓉换装后 字段 仍为 1、移动点 49 不变, 可再次进道具菜单, 待機才结束
func test_t12_equip_discard_keeps_action():
	var c = ctx_scripted()
	var u = unit({"move_cap": 49, "move_left": 49})
	for i in 3:   # 装备、再装备、丢弃: 可连续多次
		check(not Items.after_equip_or_discard(c, u), "第 %d 次不结束行动" % i)
	check(not u.acted, "字段 仍为 1")
	eq(Movement.cur_points(u), 49, "移动点不变, 仍显示完整移动范围")
	check(Movement.can_start_action(u), "之后仍可移动、出手")
	Movement.end_action(u)   # 待機
	check(u.acted)
	var m = ctx_scripted([], {"equip_costs_action": true})
	var v = unit({"move_cap": 49, "move_left": 49})
	check(Items.after_equip_or_discard(m, v), "魔改开关: 装备结束行动")
	check(v.acted)


## 悲剧结局: 结局过场播完、脚本 END 无出口指令 → 原版停黑屏 (""), 复刻修补默认回标题
func test_t18_ending_return_title():
	var c = ctx_scripted()
	eq(c.params.fix_ending_return_title, true, "修补默认开")
	eq(Flow.script_end_exit(c, true, false), "title")
	eq(Flow.script_end_exit(c, true, true), "", "脚本自己发了出口指令 (0x54/STAGE_OVER) 照指令走")
	eq(Flow.script_end_exit(c, false, false), "", "普通事件结束不回标题")
	var o = ctx_scripted([], {"fix_ending_return_title": false})
	eq(Flow.script_end_exit(o, true, false), "", "原版: 黑屏, 战斗后台空转")


## 第 3 关第二波 (出场组 2: u14~16, u21~24) 只由 e5 SHOW_UNITS 登场, 而 e5 没有任何触发来源 → 永不出现
func test_t24_stage3_wave2_dead_event():
	var st: Dictionary = _content_json("stages/03/stage.json")
	var us: Array = _content_json("stages/03/units.json")
	var srcs := Flow.event_sources(st, us)
	eq(srcs, [0, 1, 2, 4, 6], "TEVT e1 / JUDGE 2,0,4 / kill_event 0,6 / MEVT 全是宝箱")
	check(not srcs.has(5), "e5 死代码")
	var wave2 := []
	for u in us:
		if int(u.event_parm[0]) == 2:
			wave2.append(int(u.index))
	eq(wave2, [14, 15, 16, 21, 22, 23, 24])


## 第 20 关石座 mevt1 (12,6) parm1 = 5 (只认友军 NPC 停留):
##   正常走到 → 触发 e5; 转 NPC 时已站在石座 (AI 不移动) → 不检查, 永不触发 (剧情卡在 var9 = 1)
func test_t25_unmoved_ai_skips_map_event():
	var st: Dictionary = _content_json("stages/20/stage.json")
	var mp: Dictionary = _content_json("stages/20/map.json")
	var recs := {}
	for m in st.map_events:
		recs[int(m.index)] = {"type": int(m.type), "parm1": int(m.trigger), "parm2": int(m.event)}
	var at := func(cell: Vector2i) -> Dictionary:
		return recs.get(int(mp.event[cell.y][cell.x]), {})
	eq(at.call(Vector2i(12, 6)), {"type": 0, "parm1": 5, "parm2": 5})
	var feng = unit({"side": 0, "npc_ally": true, "ai": 4, "ai_target": [12, 6]})
	feng.set_pos(Vector2i(12, 6))
	eq(Flow.map_event_hit(at, [Vector2i(12, 6)], feng, true), {}, "AI 没移动: 不检查")
	eq(Flow.map_event_hit(at, [], feng, true), {})
	eq(Flow.map_event_hit(at, [Vector2i(12, 8), Vector2i(12, 7), Vector2i(12, 6)], feng, true).get("parm2"), 5,
		"移动到石座: 触发 e5")
	eq(Flow.map_event_hit(at, [Vector2i(12, 7), Vector2i(12, 6), Vector2i(11, 6)], feng, true), {},
		"parm1 5 只算停留, 途经不算")
	var pc = unit({"side": 0})
	pc.set_pos(Vector2i(12, 6))
	eq(Flow.map_event_hit(at, [], pc, false), {}, "玩家单位不是 parm1 5 的触发者")
	var any := func(_cell: Vector2i) -> Dictionary:
		return {"type": 0, "parm1": 4, "parm2": 9}
	eq(Flow.map_event_hit(any, [], pc, false).get("parm2"), 9, "玩家没移动: 查脚下格, 按停留")
	eq(Flow.map_event_hit(any, [Vector2i(12, 6)], feng, true), {}, "AI 没移动: 任何 parm1 都不查")


## 红闪避: 格挡时全屏红色闪光约 0.3 秒, 伤害数字不变红; 未格挡无闪光
func test_t31_guard_screen_flash():
	var c = ctx_scripted()
	var f := Attack.guard_flash(c, {"result": Attack.Result.GUARD, "damage": 9})
	eq(f.get("color"), Color8(255, 0, 0))
	near(f.get("sec", 0.0), 0.3, 0.001)
	eq(Attack.guard_flash(c, {"result": Attack.Result.HIT, "damage": 22}), {}, "不格挡: 无红色")
	eq(Attack.guard_flash(c, {"result": Attack.Result.MISS}), {})
	eq(Attack.guard_flash(ctx_scripted([], {"guard_flash_sec": 0}), {"result": Attack.Result.GUARD}), {}, "可关闭")


## 对照原版: type 4 且属性 −1 的未初始化倍率 = 光标目标格 x;
## 殷剑平(Str200,紫金劍) 打 夜魑 (Luk 0) 目标 x=21: 基础伤害 289~292 → 实际 60 (倍率 21)
func test_t08_type4_mult_is_target_x():
	var c = ctx_data()
	var a = unit({"weapon": 6, "luk": 50})
	var d = unit({"side": 1})
	for base in [289, 290, 291, 292]:
		eq(Attack.add4_damage(c, a, d, base, Attack.type4_mult(c, false, 21)), base * 21 / 100, "x=21")
	eq(Attack.add4_damage(c, a, d, 290, Attack.type4_mult(c, false, 21)), 60, "实测 60")
	eq(Attack.type4_mult(c, true, 21), 1, "AI 估价: 倍率 1")
	eq(Attack.type4_mult(c, false, -1), 0, "敌方发起的反击: 堆指针 (不可复现), 取 0 → 伤害下限 1")
	# exchange: 玩家一侧发起 → ui_x = 守方 x
	var ally = unit({"weapon": 6, "luk": 999, "x": 3, "y": 3})
	var foe = unit({"side": 1, "luk": 0, "x": 4, "y": 3})
	c.rng = ScriptedRng.new([0, 99, 99, 0, 99, 0])
	var r := Attack.strike(c, ally, foe, false, false, foe.x)
	check(r.add_type == 4 or r.result != Attack.Result.HIT, "strike 能走到 type 4 分支")

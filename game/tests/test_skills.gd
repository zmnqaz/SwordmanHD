# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 07 绝技与咒术 (用原版 skills.json)
const REQUIRES_TEST := {
	"test_bless_fixed_rk": ["data"],
	"test_can_use_conditions": ["data"],
	"test_curse_and_boss_immunity": ["data"],
	"test_holy_and_mp_restore": ["data"],
	"test_ice_freeze": ["data"],
	"test_ice_freeze_roll_drawn_even_if_target_dies": ["data"],
	"test_item_skill_overrides": ["data"],
	"test_line_skill_hits_whole_direction": ["data"],
	"test_mo_tian_jiang_lin_no_effect": ["data"],
	"test_ot1_drain_skipped_when_guarded": ["data"],
	"test_physical_consumes_move": ["data"],
	"test_physical_skill_guard_and_mult": ["data"],
	"test_physical_skill_invalid_even_for_friendly": ["data"],
	"test_self_destruct_condition": ["data"],
	"test_skill_exp_and_item_source": ["data"],
	"test_spell_hit": ["data"],
	"test_summon_flag": ["data"],
	"test_summon_flag_var_is_skill_record_rate10": ["data"]
}  # 个别方法的依赖 (同上)

const Skills = preload("res://engine/rules/skills.gd")
const Movement = preload("res://engine/rules/movement.gd")
const Status = preload("res://engine/rules/status.gd")


## 魔天降臨 (25 号, +0=0, rt=-1): 扣 25 MP, 无任何效果, 无经验 (原版 bug 保留)
func test_mo_tian_jiang_lin_no_effect():
	var c = ctx_data()
	var sk: Dictionary = c.skill(25)
	eq([int(sk["move_attack_type"]), int(sk["result_type"]), int(sk["other_type"]), int(sk["other_effect"])], [0, -1, 2, 7], "数据: 咒术 + ot2 oe7")
	var caster = unit({"mp": 100, "mp_max": 100, "lv": 30})
	var t = unit({"side": 1, "mp": 80, "mp_max": 200, "hp": 500, "hp_max": 500, "base_exp": 100, "lv": 30})
	check(Skills.can_use(c, caster, sk))
	Skills.consume(c, caster, sk)
	var r := Skills.resolve(c, caster, sk, [t])
	eq(caster.mp, 75, "扣 25 MP")
	eq(t.mp, 80, "目标 MP 不变")
	eq(t.hp, 500, "无伤害")
	eq(r.exp, 0, "无经验")
	# 魔改开关: 走绝技分支 ot2 oe7 吸术 min(MP, MPmax/10)
	var c2 = ctx_data(null, {"fix_mo_tian": true})
	var t2 = unit({"side": 1, "mp": 80, "mp_max": 200})
	var caster2 = unit({"mp": 0, "mp_max": 100})
	Skills.resolve(c2, caster2, sk, [t2])
	eq(t2.mp, 60, "修复后吸 20")
	eq(caster2.mp, 20)


## 使用条件: 封咒禁全部 (含绝技); MP; 咒术移动后不可; 绝技看剩余移动点
func test_can_use_conditions():
	var c = ctx_data()
	var fire: Dictionary = c.skill(6)     # 離火神訣 咒术 MP 10
	var sword: Dictionary = c.skill(42)   # 無方飛劍 绝技 MP 20 move_cost 24
	var u = unit({"mp": 50, "mp_max": 50})
	u.move_left = 30
	check(Skills.can_use(c, u, fire))
	check(Skills.can_use(c, u, sword))
	u.moved = true
	check(not Skills.can_use(c, u, fire), "咒术移动后不可用")
	check(Skills.can_use(c, u, sword), "绝技移动后可用")
	u.move_left = 23
	check(not Skills.can_use(c, u, sword), "移动点 23 < 24")
	u.move_left = 30
	u.status = U.ST_SEAL
	check(not Skills.can_use(c, u, sword), "封咒也禁绝技")
	u.status = 0
	u.mp = 19
	check(not Skills.can_use(c, u, sword), "MP 不足")


## 绝技消耗 move_cost, 先扣保留点 (網易號「69 点放不出 70」)
func test_physical_consumes_move():
	var c = ctx_data()
	var sk: Dictionary = c.skill(42)
	var u = unit({"mp": 50})
	u.move_left = 40
	u.burst_reserve = 10
	Skills.consume(c, u, sk)
	eq(u.mp, 30)
	eq(u.move_left, 16)
	eq(u.burst_reserve, 0, "先扣保留点")


## 自爆: HP <= HPmax/2 才可用; 施术者死亡
func test_self_destruct_condition():
	var c = ctx_data()
	var sk: Dictionary = c.skill(70)
	var u = unit({"hp": 51, "hp_max": 100, "mp": 0})
	u.move_left = 40
	check(not Skills.can_use(c, u, sk), "HP 51/100 不可")
	u.hp = 50
	check(Skills.can_use(c, u, sk), "HP 50/100 可")
	var t = unit({"side": 1, "hp": 1000, "hp_max": 1000, "mag_opp_id": 0})
	var r := Skills.resolve(c, u, sk, [t])
	check(r.caster_died and not u.alive, "自爆后死亡")
	eq(t.hp, 1000 - 25 * c.mag_opp_value(0, 1) / 100)


## 召唤: 标志变量 != 0 不可再召唤 (每种一只)
func test_summon_flag():
	var c = ctx_data()
	var sk: Dictionary = c.skill(40)   # 式鬼召喚 rate10 = 103
	var u = unit({"mp": 100})
	check(Skills.can_use(c, u, sk, {103: 0}))
	check(not Skills.can_use(c, u, sk, {103: 1}), "式鬼已在场")
	var r := Skills.resolve(c, u, sk, [])
	check(r.summon, "交给调用方放置召唤物")


## 冰系命中后判冰結: rate10 - 2×目标魂; R=K=1
func test_ice_freeze():
	var c = ctx_data(ScriptedRng.new([0, 0, 59]))   # 命中, P 随机项 0, 冰結判定 59
	var sk: Dictionary = c.skill(16)   # 天霜雪舞 rate10 80
	var caster = unit({"int": 100, "luk": 20})
	var t = unit({"side": 1, "hp": 5000, "hp_max": 5000, "luk": 20})
	t.spirit = [0, 50, 0, 50, 10]      # 魂 10 → 几率 60
	var r := Skills.resolve(c, caster, sk, [t])
	check(r.targets[0].hit)
	check(t.has_status(U.ST_FREEZE), "59 < 60 冰結")
	eq(t.status_r[U.ST_FREEZE], 1)
	var c2 = ctx_data(ScriptedRng.new([0, 0, 60]))
	var t2 = unit({"side": 1, "hp": 5000, "hp_max": 5000, "luk": 20})
	t2.spirit = [0, 50, 0, 50, 10]
	Skills.resolve(c2, caster, sk, [t2])
	check(not t2.has_status(U.ST_FREEZE), "60 不冰結")


## 咒术命中: 幻影 0, 對術全禦 0 (绝技查對技全禦), 狂暴 100, rate6 + 运差/4
func test_spell_hit():
	var c = ctx_data()
	var fire: Dictionary = c.skill(6)   # rate6 95
	var a = unit({"luk": 20})
	var t = unit({"side": 1, "luk": 60})
	eq(Skills.spell_hit(c, a, t, fire), 85)
	t.status = U.ST_GUARD_SPELL
	eq(Skills.spell_hit(c, a, t, fire), 0)
	t.status = U.ST_GUARD_SKILL
	eq(Skills.spell_hit(c, a, t, fire), 85, "咒术不看對技全禦")
	t.status = U.ST_BERSERK
	eq(Skills.spell_hit(c, a, t, fire), 100)
	eq(Skills.spell_hit(c, a, unit({"luk": 0}), c.skill(20)), 100, "光系 rate6 250 必中")


## 绝技: 幻影/對技全禦 无效; ot1 格挡只 /2 (无 Vit/10、无保底), 倍率在格挡之后
func test_physical_skill_guard_and_mult():
	var c = ctx_data(ScriptedRng.new([0, 0]))   # 运气除数 10, 格挡判定 0 → 格挡 (率 5)
	var sk: Dictionary = c.skill(43)   # 電射星馳 ot1 oe0 (×2)
	var a = unit({"str": 61, "luk": 0})
	var t = unit({"side": 1, "vit": 100, "luk": 0, "hp": 999, "hp_max": 999})   # DEF 50
	var r := Skills.resolve(c, a, sk, [t])
	check(r.targets[0].guard, "格挡")
	eq(r.targets[0].damage, (61 - 50) / 2 * 2, "11/2=5 再 ×2 = 10")
	var c2 = ctx_data(ScriptedRng.new([0, 0]))
	var weak = unit({"str": 1, "luk": 0})
	var t2 = unit({"side": 1, "vit": 100, "hp": 999, "hp_max": 999})
	var r2 := Skills.resolve(c2, weak, sk, [t2])
	eq(r2.targets[0].damage, 0, "绝技无保底, 可为 0")
	t2.status = U.ST_PHANTOM
	var r3 := Skills.resolve(ctx_data(), a, sk, [t2])
	check(r3.targets[0].invalid, "幻影 → 无效")


## 祝福 eff5~7: R=power K=rate10 → 無方變幻 200/100 两次结算; 不動之界 300/100 三次
func test_bless_fixed_rk():
	var c = ctx_data()
	var t = unit({})
	Skills.resolve(c, unit({}), c.skill(35), [t])
	check(t.has_status(U.ST_PHANTOM))
	eq([t.status_r[U.ST_PHANTOM], t.status_k[U.ST_PHANTOM]], [200, 100])
	var t2 = unit({})
	Skills.resolve(c, unit({}), c.skill(39), [t2])
	eq(t2.status & 0xf, 0xf, "攻防技速")
	eq(Status.duration_ticks(t2.status_r[U.ST_ATK_UP], t2.status_k[U.ST_ATK_UP]), 3)
	var t3 = unit({})
	Skills.resolve(c, unit({}), c.skill(44), [t3])
	check(t3.has_status(U.ST_GUARD_SKILL), "日輪神劍 R=K=0 也能施加")


## 诅咒: 命中后 R = 咒术伤害公式 (含 MAG_OPP[幻]); 幻抗 0 → R=0 → 不施加 (表现为 Boss 免疫)
func test_curse_and_boss_immunity():
	var c = ctx_data()
	c.mag_opp = [[100, 100, 100, 100, 100, 100], [100, 100, 100, 0, 100, 100]]
	var sk: Dictionary = c.skill(34)   # 奪魄鬼咒 rt4 eff9 麻痺, rate6 50
	var caster = unit({"int": 100, "luk": 200})
	var t = unit({"side": 1, "luk": 0, "int": 0})
	Skills.resolve(c, caster, sk, [t])
	check(t.has_status(U.ST_PARALYZE), "普通目标麻痺")
	add_item(c, 60, {})   # 护具 (无护具单位的抗性表固定行 0)
	var boss = unit({"side": 1, "luk": 0, "mag_opp_id": 1, "armor": 60, "hp": 50000, "hp_max": 50000})
	Skills.resolve(c, caster, sk, [boss])
	check(not boss.has_status(U.ST_PARALYZE), "幻抗 0 → 不施加 (没有 HP>=2500 判定)")


## 天護靈燁: 全复 + 解麻/缚/封/毒, 不解冰結; 天瑞仙舞: 回 MP
func test_holy_and_mp_restore():
	var c = ctx_data()
	var t = unit({"hp": 1, "hp_max": 300, "mp": 0, "mp_max": 200})
	t.status = U.ST_POISON | U.ST_FREEZE | U.ST_SEAL
	Skills.resolve(c, unit({}), c.skill(94), [t])
	eq(t.hp, 300)
	eq(t.status, U.ST_FREEZE)
	Skills.resolve(c, unit({}), c.skill(55), [t])
	eq(t.mp, 50, "天瑞仙舞 +50 术力")


## 伤害技能经验与道具发动不给经验
func test_skill_exp_and_item_source():
	var c = ctx_data(ScriptedRng.new([0], 0))
	var sk: Dictionary = c.skill(6)
	var caster = unit({"int": 300, "lv": 25})
	var mk = func(): return unit({"side": 1, "lv": 20, "base_exp": 150, "hp": 10, "hp_max": 100, "luk": 0})
	var r := Skills.resolve(c, caster, sk, [mk.call(), mk.call()])
	eq(r.exp, 55, "离火杀 2 只 = 37 + 18")
	var r2 := Skills.resolve(c, caster, sk, [mk.call()], {"from_item": true})
	eq(r2.exp, 0, "道具发动不给经验")
	var bless := Skills.resolve(c, caster, c.skill(28), [unit({})])
	eq(bless.exp, 0, "祝福不给经验")


## 直线型 (50 剛烈破 type1 0/5): 选一个方向, 该方向射程内的格全部受影响
func test_line_skill_hits_whole_direction():
	var c = ctx_data()
	var sk: Dictionary = c.skill(50)
	var b = Board.new(12, 12)
	var caster = unit({"x": 2, "y": 5})
	var t1 = unit({"side": 1, "x": 4, "y": 5})
	var t2 = unit({"side": 1, "x": 7, "y": 5})
	var t3 = unit({"side": 1, "x": 2, "y": 3})
	for u in [caster, t1, t2, t3]:
		b.add_unit(u)
	eq(Skills.targets_in_area(b, caster, sk, Vector2i(3, 5)), [t1, t2], "向东: 距 1~5 的格全中")
	eq(Skills.targets_in_area(b, caster, sk, Vector2i(2, 4)), [t3], "向北")


## / §8 道具发动技能: power、rate10 换成物品 字段 / 字段 (剑魂石·紫 → 剑雄召唤, 单位 11, 标志变量 104)
func test_item_skill_overrides():
	var c = ctx_data()
	var sk: Dictionary = preload("res://engine/rules/items.gd").skill_of(c, 217)
	eq(int(sk["id"]), 95)
	eq(int(sk["power"]), 11)
	eq(int(sk["rate10"]), 104)
	check(not Skills.can_use(c, unit({"mp": 99}), sk, {104: 1}), "召唤物在场时不可再召")


## MAG_OPP 行号: 默认单位自己的行; 无护具读到全 0 记录 → 行 0; 护具 字段 ≠ -1 时用护具的值
func test_mag_row_rules():
	var c = ctx_scripted()
	add_item(c, 61, {})
	add_item(c, 62, {"unknown33": 5})
	var u = unit({"mag_opp_id": 7, "armor": 61})
	eq(Stats.mag_row(c, u), 7, "有护具 → 单位自己的行")
	u.armor = -1
	eq(Stats.mag_row(c, u), 0, "无护具 → 行 0 (对照原版: 任何单位表都按行 0 结算)")
	u.armor = 62
	eq(Stats.mag_row(c, u), 5, "护具记录指定抗性行")


## 冰系咒术: 冰結判定的随机数照取, 即使目标已被打死 (原版结算先于扣血; 对照 106 技能同种子随机数消耗全等)
func test_ice_freeze_roll_drawn_even_if_target_dies():
	var c = ctx_data(ScriptedRng.new([0, 99, 99, 99]))
	var caster = unit({"int": 100, "luk": 200})
	var t = unit({"side": 1, "hp": 1, "hp_max": 1, "luk": 0})
	var sk: Dictionary = c.skill(19)   # 玄凛冰煞
	var before: int = c.rng.used
	Skills.resolve(c, caster, sk, [t])
	check(not t.alive, "目标被打死")
	eq(c.rng.used - before, 3, "命中 + 威力随机 + 冰結判定")


## 物理绝技 (ot0/ot1/幻月神劍) 对幻影 / 對技全禦目标一律无效, 不分敌我; 地縛 (ot2 oe8) 不预判, 照取命中随机数
func test_physical_skill_invalid_even_for_friendly():
	var c = ctx_data(ScriptedRng.new([]))
	var caster = unit({"str": 100, "luk": 100, "side": 0})
	var ally = unit({"side": 0, "status": U.ST_GUARD_SKILL})
	var res: Dictionary = Skills.resolve(c, caster, c.skill(42), [ally])   # 無方飛劍 ot0
	check(res.targets[0].invalid, "友方带對技全禦也无效")
	eq(c.rng.used, 0, "无效不取随机数")
	var foe = unit({"side": 1, "status": U.ST_PHANTOM})
	var res2: Dictionary = Skills.resolve(c, caster, c.skill(78), [foe])   # 鬼縛之陣 地縛
	check(not res2.targets[0].invalid and not res2.targets[0].hit, "地縛走诅咒流程: 命中率 0")
	eq(c.rng.used, 1, "取 1 次命中随机数")


## 攝魂鬼觸 (ot1 oe6 吸术): 被格挡时不判吸术 (不取命中随机数、不吸 MP); 对照原版 40 个种子, 格挡的全部少取 1 次且不吸
func test_ot1_drain_skipped_when_guarded():
	var c = ctx_data(ScriptedRng.new([0, 0]))   # 第 1 个值: 格挡判定 0 < 格挡率 → 格挡
	var caster = unit({"str": 100, "luk": 0, "mp": 0, "mp_max": 500})
	var t = unit({"side": 1, "luk": 400, "mp": 300, "mp_max": 500, "hp": 999, "hp_max": 999})
	var res: Dictionary = Skills.resolve(c, caster, c.skill(66), [t])
	check(res.targets[0].guard, "被格挡")
	eq(res.targets[0].mp_drained, 0, "格挡不吸术")
	eq(t.mp, 300)
	eq(c.rng.used, 2, "威力随机 + 格挡判定, 无吸术命中判定")


## w1 实机: 剑魂石‧紫召唤后 var103=1 (不是物品覆盖值 104), 四种召唤共用标志 103
func test_summon_flag_var_is_skill_record_rate10():
	var c = ctx_data()
	var sk: Dictionary = preload("res://engine/rules/items.gd").skill_of(c, 217)
	eq(int(sk["rate10"]), 104, "物品覆盖值仍是 104 (用于状态 K)")
	eq(Skills.summon_flag_var(c, sk), 103, "置位的标志变量取技能记录自己的 rate10")
	eq(Skills.summon_flag_var(c, c.skill(40)), 103, "式鬼同为 103")

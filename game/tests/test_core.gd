# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 随机数、参数、数据模型
const REQUIRES_TEST := {
	"test_enemy_stats": ["data"],
	"test_party_init_and_derived": ["data"]
}  # 个别方法的依赖 (同上)


## MSVC rand: srand(1) 后前几个值是 41, 18467, 6334, 26500, 19169 (CRT 公知序列)
func test_msvc_rand_sequence():
	var r = Rng.new(1)
	eq([r.rand(), r.rand(), r.rand(), r.rand(), r.rand()], [41, 18467, 6334, 26500, 19169], "MSVC rand 序列")


func test_rng_reproducible():
	var a = Rng.new(777)
	var b = Rng.new(777)
	var sa := []
	var sb := []
	for i in 20:
		sa.append(a.mod(100))
		sb.append(b.mod(100))
	eq(sa, sb, "同种子同序列")


func test_scripted_rng():
	var r = ScriptedRng.new([5, 99], 7)
	eq(r.mod(100), 5)
	eq(r.mod(100), 99)
	eq(r.mod(100), 7, "队列用完后取 fallback")


func test_params_defaults_and_override():
	var p = Params.new()
	eq(p.stat_cap, 500, "属性上限 500 ")
	eq(p.exp_per_level, 500)
	eq(p.terrain_move_cost(0, 0), 5, "步行0 类别0 = 5 ")
	eq(p.terrain_move_cost(0, 10), 4, "类别 10 消耗 4")
	eq(p.terrain_move_cost(7, 7), 0x7FFF, "步行7 类别7 不可通过")
	eq(p.terrain_move_cost(4, 7), 12, "飞行4 类别7 = 12")
	var q = Params.new({"stat_cap": 999, "growth_mode": "max"})
	eq(q.stat_cap, 999, "内容包覆盖")
	eq(q.growth_mode, "max")
	var d: Dictionary = q.to_dict()
	eq(d["stat_cap"], 999, "to_dict")
	check(d.has("terrain_cost"), "to_dict 含表")


func test_unit_state_roundtrip():
	var u = unit({"name": "测试", "lv": 12, "str": 77})
	u.spirit = [1, 2, 3, 4, 5]
	u.items = [0, 99, 220]
	u.skills = [6, 7]
	u.status = U.ST_POISON | U.ST_ATK_UP
	u.status_r = {U.ST_POISON: 100, U.ST_ATK_UP: 200}
	u.status_k = {U.ST_POISON: 100, U.ST_ATK_UP: 60}
	u.xp = 321
	var d: Dictionary = u.to_dict()
	var json := JSON.stringify(d)
	var back = U.new().from_dict(JSON.parse_string(json))
	eq(back.to_dict(), d, "经 JSON 往返后一致")
	eq(back.status_r[U.ST_ATK_UP], 200, "状态 R 键还原为 int")
	eq(back.xp, 321)
	eq(back.get_stat("str"), 77)


func test_party_init_and_derived():
	var c = ctx_data()
	var f = FileAccess.open(data_dir().path_join("party_init.json"), FileAccess.READ)
	var party: Array = JSON.parse_string(f.get_as_text())
	var yin = U.from_party_init(party[0], c.units[0])
	eq(yin.unit_id, 0)
	eq(yin.move_base, 23, "殷剑平基础移动 23 ")
	# ATK = Str + 武器攻; DEF = 护具防 + Vit/2
	eq(Stats.atk(c, yin), 20 + 24, "殷 ATK = 20 + 長劍 24")
	eq(Stats.def(c, yin), 15 + 24 / 2, "殷 DEF = 軟革裏衣 15 + Vit 24/2")
	eq(Stats.mov_base(c, yin), 23 + 22 / 25, "MOV = 23 + Avg/25")
	# 主角基础移动 (网友数据 实测 = units.json)
	# 殷23、封21、上官26、鲜于23、紫枫20、燕22、真胤25、韩25、夏侯23 (按 units.json 编号 0..8 排列)
	var expect := [23, 21, 26, 20, 23, 25, 25, 22, 23]
	var got := []
	for i in 9:
		got.append(int(c.units[i]["move"]))
	eq(got, expect, "九人基础移动")


## 敌人属性 = 基础 + 成长 × lv; 第 0 幕夜魑 lv1
func test_enemy_stats():
	var c = ctx_data()
	var e = Stats.make_enemy(c.units[18], 1)
	eq(e.hp_max, 89, "夜魑 HP 80+9")
	eq(e.get_stat("luk"), 34, "夜魑 Luk 34 (网友数据)")
	eq(e.get_stat("vit"), 24)
	eq(e.eff_lv(), 6, "有效等级 = lv + base_lv")


## 召唤物: 施术者值 × 百分比 / 100, 属性封顶 500
func test_summon_stats():
	var c = ctx_scripted()
	var caster = unit({"lv": 30, "hp_max": 400, "mp_max": 200, "str": 450, "int": 100})
	var s = Stats.make_summon(c, caster, {"id": 10, "hp": 50, "mp": 100, "str": 150, "int": 50, "avg": 100, "vit": 100, "luk": 100, "move": 25})
	eq(s.hp_max, 200)
	eq(s.get_stat("str"), 500, "450×150% 封顶 500")
	eq(s.get_stat("int"), 50)
	eq(s.lv, 30)
	check(s.summon and not s.gains_exp(), "召唤物不得经验")


## 规则参数可被内容包覆盖: 基础包无 rules.json = 原版默认; 改动包 rules.json 后加载者覆盖前者
func test_params_from_packs():
	var base := "user://test_packs/base"
	var mod1 := "user://test_packs/mod1"
	var mod2 := "user://test_packs/mod2"
	for d in [base, mod1, mod2]:
		DirAccess.make_dir_recursive_absolute(d)
		if FileAccess.file_exists(d.path_join("rules.json")):
			DirAccess.remove_absolute(d.path_join("rules.json"))
	var f = FileAccess.open(mod1.path_join("rules.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": "tdj-rules/1", "params": {"bag_capacity": 999, "turn_limit": 50, "skill_ot1_mult": [3, 4, 5]}}))
	f.close()
	f = FileAccess.open(mod2.path_join("rules.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"turn_limit": 70, "recall_resets_move": true}))
	f.close()
	var p0 = ContentDB.params_from_dirs([base])
	eq(p0.to_dict(), Params.new().to_dict(), "原版包 = 默认值")
	var p = ContentDB.params_from_dirs([base, mod1, mod2])
	eq(p.bag_capacity, 999)
	eq(p.turn_limit, 70, "后加载的改动包覆盖")
	eq(typeof(p.turn_limit), TYPE_INT, "JSON 数字转回 int")
	eq(p.skill_ot1_mult, [3, 4, 5])
	eq(p.recall_resets_move, true)
	eq(p.initial_gold, 5, "未覆盖的保持原版")

# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 单位状态外观 (engine/battle/unit_status_fx.gd, 布局表 map.unit.status_fx): 表里的帧区间都在 Man_eff 里、掩码对得上状态位、
## 原版实测的几段 (封咒 45~86 等) 没被改坏。用户 2026-10-12 「被封了没有封了状态」。
const REQUIRES := ["original"]

const US = preload("res://engine/rules/unit_state.gd")
const Status = preload("res://engine/rules/status.gd")


func _entries() -> Array:
	return UiLayout.val("map.unit.status_fx", "entries", [])


func test_entries_inside_man_eff():
	var n: int = Assets.anim(ThemeAssets.p("battle.status_fx"))["frames"].size()
	check(n >= 175, "Man_eff 有帧 (%d)" % n)
	for e in _entries():
		check(int(e["base"]) + int(e["period"]) <= n, "段 %s 在 %d 帧内" % [e, n])
		check(int(e["mask"]) > 0 and int(e["period"]) > 0, "掩码/周期有效")
		check(String(e.get("layer", "above")) in ["above", "below", "split"], "层次合法")


func test_measured_segments():
	var by := {}
	for e in _entries():
		by[int(e["mask"])] = by.get(int(e["mask"]), []) + [e]
	var seal: Dictionary = by[US.ST_SEAL][0]
	eq([int(seal["base"]), int(seal["period"]), seal["layer"]], [45, 42, "above"], "封咒: 帧 45~86, 贴图之上 (原版实测)")
	var boost: Array = by[0xF]
	eq(boost.size(), 2, "增益: 脚下光环 + 头侧火花两段")
	eq([int(boost[0]["base"]), boost[0]["layer"], int(boost[1]["base"]), boost[1]["layer"]], [1, "below", 23, "above"])
	var ward: Dictionary = by[0x10][0]
	eq([int(ward["base"]), ward["layer"], int(ward["front"])], [109, "split", 10], "對技全禦: 前后各半")
	check(by.has(0x20) and by.has(US.ST_BIND) and by.has(US.ST_FREEZE), "對術全禦 / 地縛 / 冰結 都有")


## 着色参数 = 的调用参数 (2026-11-06 对照原版): 中毒 源*12 + 绿 0x3e0*6, 冰結 源*12 + 0xc77*16, 幻影 源*8 + 底*12, 狂暴 红 0x7c00*6 + 底*12
func test_tint_table():
	var d: Dictionary = UiLayout.el("map.unit.status_tint")
	eq([d.poison.col, int(d.poison.col_k), int(d.poison.src_k)], ["0x03e0", 6, 12])
	eq([d.freeze.col, int(d.freeze.col_k), int(d.freeze.src_k)], ["0x0c77", 16, 12])
	eq([int(d.phantom.src_k), int(d.phantom.dst_keep)], [8, 12])
	eq([d.berserk.col, int(d.berserk.col_k), int(d.berserk.dst_keep), int(d.berserk.width_max)], ["0x7c00", 6, 12, 6])
	check(UnitStatusFx.status_material(US.ST_SEAL | US.ST_PARALYZE) == null, "封咒/麻痹不着色 (原版是叠层/抖动)")
	var m: ShaderMaterial = UnitStatusFx.status_material(US.ST_POISON)
	eq([m.get_shader_parameter("tint1_src_k"), m.get_shader_parameter("tint1_col_k")], [0.75, 0.375], "中毒: 源 x0.75 + 绿 x0.375")
	eq(m.get_shader_parameter("tint1_col"), Vector3(0, 1, 0))
	check(not m.get_shader_parameter("tint2_on") and not m.get_shader_parameter("ghost"))
	var g: ShaderMaterial = UnitStatusFx.status_material(US.ST_PHANTOM | US.ST_FREEZE)
	eq([g.get_shader_parameter("ghost_src"), g.get_shader_parameter("ghost_keep")], [0.5, 0.75], "幻影: 源 x0.5 + 底 x0.75 (比底亮)")
	eq(g.get_shader_parameter("tint2_col_k"), 1.0, "冰結: 色权重 16 -> 1.0")


## 原版权重表 (填): t = min(31, floor(v*K/16)) 去最低位; 连续公式会偏亮 (白 x0.75: 22 而不是 23.25)
func test_weight_table_quantized():
	eq(UnitStatusFx.t555(31, 12), 22, "白 x0.75 = 23.25 -> 23 -> 偶数 22")
	eq(UnitStatusFx.t555(31, 6), 10, "纯绿 x0.375 = 11.6 -> 11 -> 10")
	eq(UnitStatusFx.t555(23, 16), 22, "冰結色蓝 23 x1.0 -> 偶数 22")
	eq(UnitStatusFx.t555(3, 16), 2)
	eq(UnitStatusFx.t555(31, 13), 22, "k 取 k>>1 档: 13 同 12")
	eq(UnitStatusFx.blend555(31, 12, 31, 6), 31, "中毒白袍绿通道 22 + 10 = 32 封顶 31")
	eq(UnitStatusFx.blend555(20, 12, 0, 6), 14, "暗部: 20 x0.75 = 15 -> 14, 绿项 0")
	for v in 32:
		for k in [0, 2, 6, 8, 12, 16, 32]:
			var t := UnitStatusFx.t555(v, k)
			check(t % 2 == 0 and t <= 30 and t <= v * k / 16, "偶数、不超过连续值、不超过 30 (v=%d k=%d)" % [v, k])


## 狂暴光晕宽度 (往返): 0,2,4,6,4,2,0,2,...
func test_berserk_width_pingpong():
	var w := 0
	var down := false
	var seq := [w]
	for i in 8:
		var r := UnitStatusFx.berserk_step(w, down, 0, 6, 2)
		w = r[0]
		down = r[1]
		seq.append(w)
	eq(seq, [0, 2, 4, 6, 4, 2, 0, 2, 4])


func _unit() -> BattleUnit:
	var u := BattleUnit.new()
	u.anim = AnimPlayer.new()
	u.anim.play_sound = false
	u.anim.position = FxPlace.offset("unit")
	u.add_child(u.anim)
	u.st = US.new()
	return u


func test_status_bits_show_overlays_and_tint():
	var u := _unit()
	u.st.status = US.ST_SEAL
	u._tint()
	var active := u._fx._entries.filter(func(en): return en.active)
	eq(active.size(), 1, "封咒: 只有封咒环一段")
	eq(int(active[0].def["base"]), 45)
	eq(u.anim.modulate, Color.WHITE, "封咒不改贴图颜色")
	u.st.status = US.ST_POISON | 0x1
	u._tint()
	eq(u._fx._entries.filter(func(en): return en.active).size(), 2, "攻击提升: 光环 + 火花两段")
	check(u.anim.status_material != null and u.anim.status_material.get_shader_parameter("tint1_on"), "中毒: 人物贴图套着色材质")
	u.st.status = 0
	u._tint()
	eq(u._fx._entries.filter(func(en): return en.active).size(), 0, "状态没了: 叠层全隐")
	eq(u.anim.modulate, Color.WHITE)
	check(u.anim.status_material == null, "状态没了: 着色材质还原")
	u.st.status = US.ST_BERSERK
	u._tint()
	check(u._fx._bz_player != null, "狂暴: 有红色光晕层")
	u._fx._process(0.12)
	check(u._fx._bz_mat.get_shader_parameter("width") != null, "光晕按宽度 w 放大 (不是外扩半径)")
	u.st.status = 0
	u._tint()
	check(u._fx._bz_player == null, "狂暴解除: 光晕层删掉")
	u.shown = true   # 在场且活着才在解除时恢复动画
	u.st.alive = true
	u.anim.playing = true
	u.st.status = US.ST_PARALYZE
	u._tint()
	check(u._fx._jitter, "麻痹: 贴图抖动")
	check(not u.anim.playing, "麻痹: 人物定格不换帧 ")
	var xs := {}
	for i in 30:
		u._fx._process(0.12)
		xs[u.anim.position.x - FxPlace.offset("unit").x] = true
		check(not u.anim.playing, "摇晃期间一直定格")
	check(xs.size() >= 2, "每 0.12 秒都在动: %s" % str(xs.keys()))
	u.st.status = 0
	u._tint()
	check(not u._fx._jitter and u.anim.position.x == FxPlace.offset("unit").x, "抖动停了, 位置复原")
	check(u.anim.playing, "麻痹解除: 动画恢复")
	u.st.status = US.ST_FREEZE
	u._tint()
	check(not u.anim.playing and not u._fx._jitter, "冰結: 定格但不抖 (原版 字段 跳过换帧)")
	u.anim.playing = true   # 别处 (阶段开始播站立) 又开了动画
	u._fx._process(BattleUnit.TICK)
	check(not u.anim.playing, "冰結期间压回定格")
	eq(u.anim.position.x, FxPlace.offset("unit").x, "冰結不偏移")
	u.st.status = 0
	u._tint()
	check(u.anim.playing, "冰結解除: 动画恢复")
	u.free()


## 麻痹摇晃: r1=1 换边, r1=0 偏着回中 / 在中间随机去一边 —— 每一步都和上一步不同
func test_paralyze_jitter_step():
	eq(UnitStatusFx.jitter_step(-1, 1, 0), 1, "左 → 右")
	eq(UnitStatusFx.jitter_step(1, 1, 0), -1, "右 → 左")
	eq(UnitStatusFx.jitter_step(0, 1, 1), -1, "中 → 左 (r1=1)")
	eq(UnitStatusFx.jitter_step(1, 0, 0), 0, "偏着 → 回中")
	eq(UnitStatusFx.jitter_step(-1, 0, 1), 0)
	eq(UnitStatusFx.jitter_step(0, 0, 1), -1, "中 → 随机一边")
	eq(UnitStatusFx.jitter_step(0, 0, 0), 1)
	for off in [-1, 0, 1]:
		for r1 in 2:
			for r2 in 2:
				var n := UnitStatusFx.jitter_step(off, r1, r2)
				check(n != off and absi(n) <= 1, "从不停在原位、只在 -1..1: %d -> %d" % [off, n])


## 状态到期: 阶段开始 R-=K 到 0 时单位身上放 MAN_RES 一段, 区间按到期位选 (状态 9 / 模式 5、6)
func test_release_range():
	eq(UnitStatusFx.release_range(US.ST_SEAL), [81, 99], "封咒到期 = 负面段 81~98 (用户 2026-10-17 报告「解除时直接没了」)")
	for b in [US.ST_PARALYZE, US.ST_BIND, US.ST_POISON, US.ST_FREEZE]:
		eq(UnitStatusFx.release_range(b), [81, 99], "麻痹/地縛/中毒/冰結到期 = 负面段")
	for b in [0x1, 0x2, 0x4, 0x8, 0x10, 0x20, US.ST_BERSERK, US.ST_PHANTOM]:
		eq(UnitStatusFx.release_range(b), [60, 81], "增益/全禦/狂暴/幻影到期 = 正面段 60~80")
	eq(UnitStatusFx.release_range(US.ST_SEAL | 0x1), [60, 81], "同时到期正负混合: 有正面位就用正面段 (的计数标志)")


func test_release_range_inside_man_res():
	var n: int = Assets.anim(ThemeAssets.p("battle.result_fx"))["frames"].size()
	for m in [US.ST_SEAL, 0x1]:
		var r := UnitStatusFx.release_range(m)
		check(r[0] < r[1] and r[1] <= n, "区间 %s 在 MAN_RES %d 帧内" % [r, n])


## 解除框的文案: 每个状态位都有一句「XX的状态解除了.」(原版字符串, 13 条), 帧段与每帧 3 tick 来自布局表
func test_release_texts_and_params():
	for b in US.STATUS_NAMES:
		var k := "battle.release.%d" % int(b)
		check(UiStrings.has(k), "有文案 " + k)
		check(UiStrings.t(k).ends_with("的状态解除了."), "格式: " + UiStrings.t(k))
	eq(UiStrings.t("battle.release.1024"), "封咒的状态解除了.", "封咒")
	eq(UnitStatusFx.freeze_break_range(), [32, 46], "冰結被打碎: 帧 32~45 (实测 14 帧)")
	eq(int(UiLayout.val("map.unit.expire_fx", "tick", 0)), 3, "解除动画每帧 3 tick = 0.12 秒 (实测, 不看帧表 time)")
	var d: Dictionary = UiLayout.el("dialog.release")
	eq([int(d["lines_per_page"]), int(d["chars_per_sec"]), float(d["auto_last_sec"])], [4, 25, 2.0], "解除框: 4 行一页 / 25 字每秒 / 末页停 2 秒")


## 冰結受击解除记在 released 位, 战场演出读它; 阶段到期 (phase_tick) 另走 expired, 不记 released
func test_freeze_break_marks_released():
	var u = unit({})
	Status.apply(u, US.ST_FREEZE, 5, 1)
	Status.on_damaged(u, 3)
	check(not u.has_status(US.ST_FREEZE), "冰結解除了")
	eq(u.released, US.ST_FREEZE, "released 记下冰結")
	var v = unit({})
	Status.apply(v, US.ST_FREEZE, 1, 1)
	Status.phase_tick(ctx_data(), v)
	check(not v.has_status(US.ST_FREEZE), "到期解除了")
	eq(v.released, 0, "到期不走 released")


## 中毒扣血的命中动画 (实测): MAN_RES 帧 2~9 (8 帧, 0.96 秒), 在 MAN_RES 帧数内
func test_poison_range():
	eq(UnitStatusFx.poison_range(), [2, 10], "中毒命中动画 = MAN_RES 帧 2~9 (模式 0)")
	var n: int = Assets.anim(ThemeAssets.p("battle.result_fx"))["frames"].size()
	check(UnitStatusFx.poison_range()[1] <= n, "在 MAN_RES %d 帧内" % n)

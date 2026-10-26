# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 主角升级、成长、技能习得、五魂化蘊 (规格, 06)。
## table = levelup.json 的一条: {hp_rand, mp_rand, str:{base,rand}, int:…, avg:…, vit:…, luk:…, skills:[{lv, spirit_request, skill_id}]}

const U = preload("res://engine/rules/unit_state.gd")
const AttrNames = preload("res://engine/rules/attr_names.gd")


## 随机项: random = rand()%(N+1) 均匀 0..N; max = N (最大成长补丁); min = 0
static func _rand_term(ctx, n: int) -> int:
	if n < 0:   # 数据错 (levelup 表 rand 为负): rand()%(n+1) 会除零或取负余数; 按 0 处理 (仍抽一次数, 不打乱后续随机序列)
		push_error("成长表随机项 rand=%d 无效 (须 >= 0), 按 0 处理" % n)
		n = 0
	match ctx.params.growth_mode:
		"max":
			return n
		"min":
			return 0
		_:
			return ctx.rng.mod(n + 1)


## 升一级 (= 一批 1 级)
static func level_up(ctx, u, table: Dictionary) -> Dictionary:
	return level_up_batch(ctx, u, table, 1)


## 一次结算 n 级 [循环 + 应用; 原版实测对照 exp/A: 种子 12345 连升 5 级逐项一致]
##   逐级循环里只累加增量, 单位本身到循环结束才改, 所以:
##   - HPmax += 3 + (Vit-lv)/35 + rand%(hp_rand+1); MPmax 同理 (Int): 整批用【批前】的 lv/Vit/Int, 不随每级更新
##   - 五项: 累计增量封顶 (属性+累计 > 500 则累计 = 500 - 属性), 与逐级 min(500) 等价
##   - 抽数顺序每级: Str Int Avg Vit Luk HP MP
##   五魂点 +2/级; 当前 HP/MP 不变; 习得在批末按【批末等级】判定一次
## 返回 {levels, gains:{str..luk,hp,mp 为整批合计}, learned:[skill_id]}
static func level_up_batch(ctx, u, table: Dictionary, n: int) -> Dictionary:
	var p = ctx.params
	var old_lv: int = u.lv
	var old_vit: int = u.get_stat("vit")
	var old_int: int = u.get_stat("int")
	var gains := {}
	for k in AttrNames.STAT_KEYS:
		gains[k] = 0
	var dhp := 0
	var dmp := 0
	for _i in n:
		for k in AttrNames.STAT_KEYS:
			var g: Dictionary = table.get(k, {"base": 0, "rand": 0})
			var before: int = u.get_stat(k)
			gains[k] += int(g.get("base", 0)) + _rand_term(ctx, int(g.get("rand", 0)))
			if before + gains[k] > p.stat_cap:
				gains[k] = p.stat_cap - before
		dhp += p.hp_grow_const + (old_vit - old_lv) / p.grow_attr_div + _rand_term(ctx, int(table.get("hp_rand", 0)))
		dmp += p.mp_grow_const + (old_int - old_lv) / p.grow_attr_div + _rand_term(ctx, int(table.get("mp_rand", 0)))
	for k in AttrNames.STAT_KEYS:
		u.set_stat(k, u.get_stat(k) + gains[k])
	u.hp_max = add_u16(ctx, u.hp_max, dhp)
	u.mp_max = add_u16(ctx, u.mp_max, dmp)
	if p.hp_cap > 0:
		u.hp_max = mini(u.hp_max, p.hp_cap)
	if p.mp_cap > 0:
		u.mp_max = mini(u.mp_max, p.mp_cap)
	gains["hp"] = dhp
	gains["mp"] = dmp
	u.spirit_points += p.spirit_points_per_level * n
	u.lv += n
	var learned := learn_skills(ctx, u, table.get("skills", []))
	return {"levels": n, "gains": gains, "learned": learned}


## HPmax/MPmax 16 位加: 原版无上限、超 65535 回绕
## (65530 + 15 → 9); 当前 HP/MP 不变 (可大于上限)。参数 hp_mp_u16_wrap=false 时封顶 65535
static func add_u16(ctx, v: int, delta: int) -> int:
	var r: int = v + delta
	if ctx.params.hp_mp_u16_wrap:
		return r & 0xFFFF
	return clampi(r, 0, 0xFFFF)


## 升级时习得 [后半 判定 + 应用]
## 判定 (按表顺序逐行): 末级等级 >= 行等级, 五魂达标 (req>0: 魂>=req; req<0: 魂<=-req; 0 不限), 且该技能不在单位当前 10 格里
##   (只和【升级前】的技能栏比, 同批里表内重复的技能不互相去重)。通过的行就是「习得」列表 (升级窗显示它们, 不管栏满不满)。
## 应用: 逐个填进技能栏【第一个空位 (-1)】, 栏里没有空位就丢弃 (升级窗仍会写「习得」)。
##   正常游玩技能栏是紧凑的 (无空洞), 此时「第一个空位」= 追加; 有空洞时才可见区别 (原版实测 w2 growth 矩阵 2361 例)。
## 只在升级时调用 (营地加五魂不立即学会, 开战时不判定)。返回习得列表 (含放不下的)
static func learn_skills(ctx, u, entries: Array) -> Array:
	var learned := []
	var before: Array = u.skills.duplicate()
	for e in entries:
		var sid = e.get("skill_id", -1)
		if sid == null or int(sid) < 0:
			continue
		if u.lv < int(e.get("lv", 0)):
			continue
		var ok := true
		var req = _spirit_req(e.get("spirit_request", {}), sid)
		for i in 5:
			var r: int
			if req is Dictionary:
				r = int(req.get(AttrNames.SPIRIT[i], 0))
			else:
				r = int(req[i])
			if r > 0 and u.spirit[i] < r:
				ok = false
			elif r < 0 and u.spirit[i] > -r:
				ok = false
		if not ok:
			continue
		if before.has(int(sid)):
			continue
		learned.append(int(sid))
	for sid in learned:
		var slot: int = u.skills.find(-1)
		if slot >= 0:
			u.skills[slot] = sid
		elif u.skills.size() < ctx.params.skill_slots:
			u.skills.append(sid)
	return learned


## 获得经验 [原版实测对照 exp/A B C]: xp += amount; n = xp / 500; n > 0 则 xp -= 500n;
## 再封顶 n = min(n, 99 - lv) (封顶只影响级数, 多出的 500n 已扣掉)。
## 满级后经验不丢弃: 继续累加, 只有 >= 500 时按 500 的倍数扣掉 (实测 lv99 exp 300 +1 = 301)。
## 返回 [] (没升级) 或 [一批结算结果 {levels, gains, learned}]
static func gain_exp(ctx, u, amount: int, table: Dictionary) -> Array:
	var p = ctx.params
	u.xp += amount
	var n: int = u.xp / p.exp_per_level
	if n <= 0:
		return []
	u.xp -= n * p.exp_per_level
	n = mini(n, p.level_cap - u.lv)
	if n <= 0:
		return []
	return [level_up_batch(ctx, u, table, n)]


## 五魂化蘊 (营地)。
## 一次界面会话: begin → add/sub → commit。上限只拿【原值】比较 (原值 98 可加到 100 以上, 原版漏洞照做)
class SpiritSession:
	var unit
	var v0: Array
	var add := [0, 0, 0, 0, 0]
	var pts: int
	var limit: int

	func _init(u, add_limit: int = 100) -> void:
		unit = u
		v0 = u.spirit.duplicate()
		pts = u.spirit_points
		limit = add_limit

	## pts > 0 且 原值 < 100
	func inc(i: int) -> bool:
		if pts > 0 and v0[i] < limit:  # 同 spirit_can_inc
			add[i] += 1
			pts -= 1
			return true
		return false

	## 只能退本次加的
	func dec(i: int) -> bool:
		if add[i] > 0:
			add[i] -= 1
			pts += 1
			return true
		return false

	## 确认结束 → 写回
	func commit() -> void:
		for i in 5:
			unit.spirit[i] = v0[i] + add[i]
		unit.spirit_points = pts


## 加点条件 : 剩余点 > 0 且【原值】< 上限 (本次已加的不计, 所以原值 98 可加到 100 以上)
static func spirit_can_inc(pts_left: int, v0: int, limit: int = 100) -> bool:
	return pts_left > 0 and v0 < limit


static func spirit_session(ctx, u) -> SpiritSession:
	return SpiritSession.new(u, ctx.params.spirit_add_limit)


## 习得条件 spirit_request: 字典 {五魂名: 值} 或 5 项数组。数组不足 5 项 / 类型不对 (内容包数据错) 时报错, 缺项按 0 (不限)
static func _spirit_req(req, sid):
	if req is Dictionary or (req is Array and req.size() >= 5):
		return req
	push_error("技能 %s 的习得条件 spirit_request 应为 5 项数组或字典: %s, 缺项按 0" % [str(sid), str(req)])
	var out := [0, 0, 0, 0, 0]
	if req is Array:
		for i in req.size():
			out[i] = req[i]
	return out

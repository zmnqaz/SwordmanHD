# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 经验 (历练值)。

## d = clamp(lv(目标) - lv(自身), -10, 10); 有效等级 = 字段 + 字段
static func level_diff(ctx, self_u, target) -> int:
	var c: int = ctx.params.exp_level_clamp
	return clampi(target.eff_lv() - self_u.eff_lv(), -c, c)


## 二次曲线 k: d>=0: 2 - x², x = 0.1×(10-d); d<0: x², x = 0.1×(d+10)
## 常数 0.1 是 float32, 所以 k 比精确值略偏 —— 截断后正好复现实测 (见 params.exp_curve_step)
static func curve_k(ctx, d: int, cube: bool = false) -> float:
	var c: int = ctx.params.exp_level_clamp
	d = clampi(d, -c, c)
	var m: int = (c - d) if d >= 0 else (d + c)
	var x: float = float(m) * ctx.params.exp_curve_step
	var pw: float = x * x * (x if cube else 1.0)
	return (2.0 - pw) if d >= 0 else pw


## _ftol: 向零截断
static func _ftol(v: float) -> int:
	return int(v)


## 击杀经验 = _ftol(base_exp × k), <=0 时置 1
## _ftol RC=11 截断, base 7 × k 0.81 = 5.67 实得 5; 两佰块 base 1 → max(1, 截断 k)
static func kill_exp(ctx, self_u, target) -> int:
	var k: float = curve_k(ctx, level_diff(ctx, self_u, target))
	var e: int = _ftol(float(target.base_exp) * k)
	if e <= 0:
		e = ctx.params.exp_kill_min
	return e


## / §3 普攻、反击经验 (谁的攻击命中谁得; 只有阵营 0 非 NPC 非召唤物得)
##   击杀: kill_exp; 命中未杀: max(1, kill_exp × 伤害 / 目标HPmax) (伤害不截到剩余 HP, 中); 未命中: 0
static func attack_exp(ctx, self_u, target, hit: bool, dmg: int, killed: bool) -> int:
	if not self_u.gains_exp() or not hit:
		return 0
	var ke: int = kill_exp(ctx, self_u, target)
	if killed:
		return ke
	var e: int = ke * dmg / maxi(1, target.hp_max)
	return maxi(ctx.params.exp_hit_min, e)


## float32 舍入。GDScript 的 float 是 double, 经 PackedFloat32Array 往返得到 float32 值。
static func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]


## 技能路径的等级差曲线; 与普攻 (全程扩展精度) 不同:
## x² 先存成 float32、x³ 项也存成 float32, 所以同级 k=1.0 (普攻 0.99999997 → 499)。
##   d>=0: X2 = f32(x×xf), k = 2 - X2, k3 = f32(2 - X2×xf)
##   d<0 : s = x×xf, X2 = f32(s), k = s (不舍入), k3 = f32(X2×xf)
##   x = m×0.1f (m = 10-d 或 d+10, 扩展精度), xf = f32(x)
## 返回 [k, k3]。原版实测对照 (w2 exp 矩阵 639 例) 校准。
static func skill_curve(ctx, d: int) -> Array:
	var c: int = ctx.params.exp_level_clamp
	d = clampi(d, -c, c)
	var m: int = (c - d) if d >= 0 else (d + c)
	var x: float = float(m) * ctx.params.exp_curve_step
	var xf: float = _f32(x)
	if d >= 0:
		var x2f: float = _f32(x * xf)
		return [2.0 - x2f, _f32(2.0 - x2f * xf)]
	var s: float = x * xf
	var x2f2: float = _f32(s)
	return [s, _f32(x2f2 * xf)]


## 技能经验总汇总: 全部目标 e1 都是 -1 (未结算到经验段) → 无;
## 单目标 = e1; 多目标 = 第一个最大 e1 + Σ 其余目标的 e2 (**-1 的目标也参与累加**, 即落空/无效的目标每个扣 1);
## 结果 <= 0 不给。entries 的 e1/e2 = -1 表示该目标没走到经验段。
static func _sum_entries(e1s: Array, e2s: Array) -> int:
	var n: int = e1s.size()
	var any := false
	for v in e1s:
		if v != -1:
			any = true
	if n == 0 or not any:
		return 0
	var total: int
	if n == 1:
		total = e1s[0]
	else:
		var best := 0
		var bv: int = -1
		for i in n:
			if e1s[i] > bv:
				bv = e1s[i]
				best = i
		total = bv
		for i in n:
			if i != best:
				total += e2s[i]
	return maxi(total, 0)


## 伤害技能 (咒术 rt0、物理绝技、自爆) [+; 原版实测 w2 矩阵 639 例]
## entries: 每个目标一项 {target, damage, killed, hp_before, reached}; reached=false (落空/无效/非伤害结果) 的 e1=e2=-1
##   ke1 = max(1, ftol(base_exp × k)), ke2 = max(1, ftol(base_exp × k3))      (技能曲线, 见 skill_curve)
##   击杀 (hp_before - damage <= 0): e1 = ke1, e2 = ke2
##   伤害 < 0 (属性吸收): e1 = e2 = 1;   否则 e = max(1, ke × 伤害 / 目标HPmax) (整数除; 伤害 0 → 1)
static func skill_exp(ctx, caster, entries: Array) -> int:
	if not caster.gains_exp() or entries.is_empty():
		return 0
	var e1s := []
	var e2s := []
	for en in entries:
		if not en.get("reached", true):
			e1s.append(-1)
			e2s.append(-1)
			continue
		var t = en["target"]
		var dmg: int = int(en.get("damage", 0))
		var hp0: int = int(en.get("hp_before", t.hp))
		var kk: Array = skill_curve(ctx, level_diff(ctx, caster, t))
		var ke1: int = maxi(1, _ftol(float(t.base_exp) * kk[0]))
		var ke2: int = maxi(1, _ftol(float(t.base_exp) * kk[1]))
		if hp0 - dmg <= 0:
			e1s.append(ke1)
			e2s.append(ke2)
		elif dmg < 0:
			e1s.append(1)
			e2s.append(1)
		else:
			e1s.append(maxi(1, ke1 * dmg / maxi(1, t.hp_max)))
			e2s.append(maxi(1, ke2 * dmg / maxi(1, t.hp_max)))
	return _sum_entries(e1s, e2s)


## 治疗经验 (单目标)
static func heal_exp(ctx, caster, target, healed: int) -> int:
	return heal_skill_exp(ctx, caster, [{"target": target, "healed": healed}])


## 治疗技能经验 (多目标) [分支, 原版实测 exp/E1~E4 + w2 矩阵]
##   每个目标 (含满血、回复量 0 的): r = f32(实际回复量 / 目标HPmax) (回复量按缺血封顶);
##   e1 = max(1, ftol(k × 200 × r)), e2 = max(1, ftol(k3 × 200 × r)) (技能曲线); 汇总同 _sum_entries
## entries: [{target, healed}]
static func heal_skill_exp(ctx, caster, entries: Array) -> int:
	if not caster.gains_exp() or entries.is_empty():
		return 0
	var e1s := []
	var e2s := []
	for en in entries:
		var t = en["target"]
		var r: float = _f32(float(int(en.get("healed", 0))) / float(maxi(1, t.hp_max)))
		var kk: Array = skill_curve(ctx, level_diff(ctx, caster, t))
		var base: float = float(ctx.params.exp_heal_base)
		e1s.append(maxi(1, _ftol(kk[0] * base * r)))
		e2s.append(maxi(1, _ftol(kk[1] * base * r)))
	return _sum_entries(e1s, e2s)

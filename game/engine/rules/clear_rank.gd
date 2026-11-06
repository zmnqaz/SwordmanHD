# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 过关回合数记录 + 0x56 通关序号 (原版算法的单一来源; 基址 / 区间 / 异或常量都来自 Params, 默认 = 原版)。
##   记录: 战斗销毁时 GD[0x94 + 4*GD.stage] = turn; 此时 GD.stage 已是「下一关」next, 所以记在变量 base + next
##   序号: A~D = 四段 [base+off, 个数] 变量之和, E = (A+B+C+D) xor 常量; 显示按 %X
## 默认 base = 30, 段 = [[0,8],[8,9],[17,8],[25,10]] (变量 30~37、38~46、47~54、55~64), 常量 0xA50712A5。
## 改参数 (params.gd turn_record_base / clear_rank_segments / clear_rank_xor) 必须三者一起考虑: 同一套原版算法。


## 第 next 关的回合数记在哪个变量; -1 = 不记录 (turn_record_base < 0)
static func record_var(params, next_stage: int) -> int:
	var base: int = params.turn_record_base
	return -1 if base < 0 else base + next_stage


## 序号五项 [A, B, C, D, E]; get_var(变量号) -> 值
static func serial(get_var: Callable, params) -> Array:
	var base: int = params.turn_record_base
	var sums: Array = []
	var total := 0
	for seg in params.clear_rank_segments:
		var s := 0
		for i in int(seg[1]):
			s += int(get_var.call(base + int(seg[0]) + i))
		sums.append(s)
		total += s
	sums.append(total ^ int(params.clear_rank_xor))
	return sums


## 过关回合记录之和 (= 序号 A+B+C+D, 已打完各关的回合数之和); -1 = 内容包不记录 (turn_record_base < 0)。
## 只读原版变量: 旧存档 / 原版导入存档没有复刻的总回合字段 (GameState.turns) 时拿它补
static func recorded_turns(get_var: Callable, params) -> int:
	if int(params.turn_record_base) < 0:
		return -1
	var s: Array = serial(get_var, params)
	var total := 0
	for i in s.size() - 1:
		total += int(s[i])
	return total

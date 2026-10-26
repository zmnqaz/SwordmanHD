# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 剧情演出时序/语义 (原版 实测 2026-10-05)
const REQUIRES_TEST := {
	"test_clear_rank_text_in_content": ["content"]
}  # 个别方法的依赖 (同上)

const ClearRank = preload("res://engine/rules/clear_rank.gd")


func test_clear_rank_serial_formula():
	# 变量 30+n = 10+n (n=0..34) -> 四段和与异或校验 (表达式与对照原版一致, 手算值)
	var p = Params.new()
	var sums := ClearRank.serial(func(v): return 10 + (v - 30) if v >= 30 and v <= 64 else 0, p)
	eq(["%X" % sums[0], "%X" % sums[1], "%X" % sums[2], "%X" % sums[3], "%X" % sums[4]],
		["6C", "C6", "F4", "18B", "A5071114"], "序号 A-B-C-D-E")


func test_clear_rank_params_default_and_override():
	var p = Params.new()
	eq([p.turn_record_base, p.clear_rank_segments, p.clear_rank_xor], [30, [[0, 8], [8, 9], [17, 8], [25, 10]], 0xA50712A5], "默认 = 原版")
	eq(ClearRank.record_var(p, 1), 31, "第 0 关打完 next=1 记在变量 31")
	var q = Params.new({"turn_record_base": 60, "clear_rank_segments": [[0, 2]], "clear_rank_xor": 0xFF})
	eq(ClearRank.record_var(q, 3), 63)
	eq(ClearRank.serial(func(v): return v, q), [60 + 61, (60 + 61) ^ 0xFF], "基址整体平移, 区间与常量走参数")
	eq(ClearRank.record_var(Params.new({"turn_record_base": -1}), 3), -1, "-1 不记录")


func test_clear_rank_text_in_content():
	var t: Array = Content.system_text("clear_rank")
	check(not t.is_empty() and t[0].size() == 2, "内容包有通关序号框两段文字")
	if not t.is_empty():
		check(String(t[0][1]).contains("{4}"), "第二段带序号占位")


func test_yield_op_lists_match_original():
	# 战场分派 中「让出帧」的指令 (完成后补 2 帧) 与城镇
	eq(EventVM.YIELD_OPS, [0x04, 0x05, 0x06, 0x08, 0x09, 0x0E, 0x10, 0x12, 0x13, 0x14, 0x16, 0x29, 0x3E, 0x42, 0x54], "战场 yield 指令表")
	eq(RpgVM.YIELD_OPS, [0x01, 0x02, 0x04, 0x05, 0x06, 0x07, 0x09, 0x2E], "城镇 yield 指令表")

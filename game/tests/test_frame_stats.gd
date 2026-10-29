# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 逐帧耗时记录 (engine/core/frame_stats.gd): 统计、环形缓冲只留最近 RING 帧、冻结 / 解冻、画质诊断页显示。


func test_report_stats() -> void:
	FrameStats.reset()
	eq(FrameStats.report()["frames"], 0, "没记录: 0 帧")
	for ms in [10.0, 10.0, 10.0, 30.0, 60.0]:
		FrameStats.record_ms(ms)
	var r := FrameStats.report()
	eq([r["frames"], r["slow"], r["very_slow"]], [5, 2, 1], "帧数 / 超 25 ms / 超 50 ms")
	check(absf(float(r["avg"]) - 24.0) < 0.001, "平均 24 ms")
	eq(r["worst"], 60.0, "最差 60 ms")
	FrameStats.reset()


func test_slow_frames_with_texture_loads() -> void:
	FrameStats.reset()
	FrameStats.record_ms(10.0)
	FrameStats.record_ms(40.0, true)    # 慢帧, 同帧载入了贴图
	FrameStats.record_ms(40.0, false)   # 慢帧, 没载入贴图 (别的原因)
	FrameStats.record_ms(12.0, true)    # 载入了但不慢
	var r := FrameStats.report()
	eq([r["slow"], r["slow_loading"]], [2, 1], "2 个慢帧, 其中 1 个同帧载入了新贴图")
	FrameStats.freeze()
	FrameStats.record_ms(90.0, true)
	eq(FrameStats.report()["slow_loading"], 1, "冻结后统计不变")
	FrameStats.reset()


func test_ring_keeps_only_recent_frames() -> void:
	FrameStats.reset()
	for i in FrameStats.RING + 100:
		FrameStats.record_ms(1.0 if i < 100 else 20.0)
	var f := FrameStats.frames()
	eq(f.size(), FrameStats.RING, "只留最近 RING 帧")
	check(f.all(func(v): return float(v) == 20.0), "最老的 100 帧 (1 ms) 已被挤掉, 顺序按时间")
	FrameStats.reset()


func test_freeze_keeps_gameplay_window() -> void:
	FrameStats.reset()
	for i in 50:
		FrameStats.record_ms(16.0)
	FrameStats.freeze()
	for i in 50:
		FrameStats.record_ms(100.0)   # 之后菜单里的帧
	var r := FrameStats.report()
	eq([r["frames"], r["worst"], r["frozen"]], [50, 16.0, true], "冻结后统计的是冻结那一刻之前的帧")
	FrameStats.unfreeze()
	r = FrameStats.report()
	eq([r["frames"], r["frozen"]], [100, false], "解冻后恢复实时")
	FrameStats.reset()


func test_diag_lines_show_gameplay_frames() -> void:
	FrameStats.reset()
	for i in 20:
		FrameStats.record_ms(12.0)
	FrameStats.record_ms(70.0)
	var txt := "\n".join(DiagPanel.lines())
	check(txt.contains("Gameplay") and txt.contains(">50 ms: 1"), "诊断页有 Gameplay 行, 含超 50 ms 的帧数")
	FrameStats.reset()
	check(not "\n".join(DiagPanel.lines()).contains("Gameplay"), "没记录时不显示这一行")

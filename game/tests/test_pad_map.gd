# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 手柄映射 (engine/input/pad_map.gd): 预设、覆盖项、校验、按键反查、扳机迟滞、键名


func test_std_preset_matches_design():
	var m := PadMap.effective("std", {})
	eq(m["confirm"], JOY_BUTTON_A, "标准: A 确认")
	eq(m["cancel"], JOY_BUTTON_B, "标准: B 取消")
	eq(m["info"], JOY_BUTTON_X)
	eq(m["menu"], JOY_BUTTON_Y)
	eq(m["page_up"], JOY_BUTTON_LEFT_SHOULDER)
	eq(m["page_down"], JOY_BUTTON_RIGHT_SHOULDER)
	eq(m["map"], JOY_BUTTON_BACK, "Back = 战场地图")
	eq(m["settings"], JOY_BUTTON_START, "Start = 设定")
	eq(m["skip_dialog"], JOY_BUTTON_LEFT_STICK)
	eq(m["select"], JOY_BUTTON_RIGHT_STICK)
	eq(m["switch"], PadMap.TRIGGER_L)
	eq(m.size(), PadMap.ACTIONS.size(), "每个动作都有缺省键")


func test_swap_preset_only_swaps_a_and_b():
	var s := PadMap.effective("swap", {})
	var d := PadMap.effective("std", {})
	eq(s["confirm"], JOY_BUTTON_B, "交换: B 确认")
	eq(s["cancel"], JOY_BUTTON_A, "交换: A 取消")
	for a in PadMap.ACTIONS:
		if a != "confirm" and a != "cancel":
			eq(s[a], d[a], "%s 与标准相同" % a)


func test_unknown_preset_falls_back_to_std():
	eq(PadMap.effective("nope", {}), PadMap.effective("std", {}))


func test_overrides_replace_single_actions():
	var m := PadMap.effective("std", {"info": JOY_BUTTON_RIGHT_STICK, "bogus": 3})
	eq(m["info"], JOY_BUTTON_RIGHT_STICK, "覆盖项生效")
	eq(m["confirm"], JOY_BUTTON_A, "其余不变")
	check(not m.has("bogus"), "未知动作名忽略")


func test_resolve_groups_actions_by_button():
	var r := PadMap.resolve("std", {})
	eq(r[JOY_BUTTON_A], ["confirm"])
	eq(r[PadMap.TRIGGER_L], ["switch"], "LT = 营地切栏")
	check(not r.has(PadMap.TRIGGER_R), "RT 没有绑定动作 (选目标跳转已删)")
	var r2 := PadMap.resolve("std", {"menu": JOY_BUTTON_A})
	eq(r2[JOY_BUTTON_A], ["confirm", "menu"], "覆盖后两个动作可共用一键")
	check(not r2.has(JOY_BUTTON_Y), "Y 不再绑定任何动作")


func test_sanitize_drops_dirty_data():
	var s := PadMap.sanitize("swap", {"confirm": 5.0, "cancel": "x", "nope": 1, "info": -3, "menu": 9999, "page_up": 4.5})
	eq(s["preset"], "swap")
	eq(s["map"], {"confirm": 5}, "JSON 读回的 5.0 认作 5; 字符串/负数/越界/小数/未知动作名丢弃")
	eq(PadMap.sanitize("???", {})["preset"], "std", "未知预设回退标准")
	eq(PadMap.sanitize("std", null)["map"], {}, "map 不是字典取空")
	eq(PadMap.sanitize("std", {"confirm": JOY_BUTTON_A})["map"], {}, "与预设相同的覆盖项不存 (稀疏)")


func test_trigger_hysteresis():
	check(not PadMap.trigger_on(false, 0.4), "未过 0.5 不按下")
	check(PadMap.trigger_on(false, 0.5), "达 0.5 按下")
	check(PadMap.trigger_on(true, 0.4), "已按下时 0.3~0.5 之间保持")
	check(not PadMap.trigger_on(true, 0.3), "降到 0.3 松开")
	check(not PadMap.trigger_on(true, 0.0))


func test_button_names():
	eq(PadMap.button_name(JOY_BUTTON_A), "A")
	eq(PadMap.button_name(JOY_BUTTON_LEFT_SHOULDER), "LB")
	eq(PadMap.button_name(PadMap.TRIGGER_R), "RT")
	eq(PadMap.button_name(JOY_BUTTON_RIGHT_STICK), "R3")
	eq(PadMap.button_name(JOY_BUTTON_BACK), "Back")
	eq(PadMap.button_name(77), "键 77", "没有名字的键按序号")


func test_button_names_show_console_symbols():
	eq(PadMap.button_name(JOY_BUTTON_A, "PS5 Controller"), "A(×)", "PlayStation: 下键是 ×")
	eq(PadMap.button_name(JOY_BUTTON_Y, "DualSense Wireless Controller"), "Y(△)")
	eq(PadMap.button_name(JOY_BUTTON_A, "Nintendo Switch Pro Controller"), "A(B)", "任天堂: 下键机身上写 B")
	eq(PadMap.button_name(JOY_BUTTON_LEFT_SHOULDER, "PS5 Controller"), "LB", "非面部键不加括注")
	eq(PadMap.button_name(JOY_BUTTON_A, "Xbox 360 Controller"), "A", "Xbox 不加括注")
	eq(PadMap.button_name(JOY_BUTTON_A), "A", "没有手柄名不加括注")


func test_is_bindable():
	check(PadMap.is_bindable(JOY_BUTTON_A))
	check(PadMap.is_bindable(PadMap.TRIGGER_L))
	check(not PadMap.is_bindable(JOY_BUTTON_DPAD_UP), "十字键固定为方向, 不可改绑")
	check(not PadMap.is_bindable(-1))

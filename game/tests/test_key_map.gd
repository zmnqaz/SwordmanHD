# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 键盘映射 (engine/input/key_map.gd): 默认键位、覆盖项换主键、同键多动作、校验、Shift 组合查表


func _key(code: int, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	return e


func test_defaults_match_design():
	var eff := KeyMap.effective({})
	eq(eff["confirm"], [KEY_ENTER, KEY_KP_ENTER], "确认: Enter / 小键盘 Enter")
	check(not eff.has("menu"), "没有键盘「游戏菜单」键 (战场空地确认 / 城镇取消本来就能开菜单)")
	eq(eff["settings"], [KEY_F1, KEY_F10], "设定: F1, F10 一直同效")
	eq(eff["guide"], [KEY_F2, KEY_F4], "攻略: F2, F4 同效")
	eq(eff["info"], [KEY_F], "查看: F (F1 让给设定)")
	eq(eff["map"], [KEY_M], "战场地图默认 M")
	eq(eff["select"], [KEY_SPACE], "空格 = 装备效果预览 (营地 / 战场物品列表按住; 其他画面同确认)")
	eq(eff["switch"], [KEY_TAB], "切栏 Tab")
	check(not eff.has("target_next") and not eff.has("target_prev"), "没有「选目标跳转」动作 (2026-10-25 删除)")
	eq(eff["cancel"], [KEY_ESCAPE, KEY_C, KEY_BACK, KEY_DELETE], "取消: 原版 Esc / Delete + C + 返回键")
	for a in KeyMap.ACTIONS:
		check(KeyMap.DEFAULTS.has(a) and (KeyMap.DEFAULTS[a] as Array).size() >= 1, "%s 有默认键" % a)


func test_override_replaces_primary_only_and_dedups():
	var eff := KeyMap.effective({"settings": KEY_N, "confirm": KEY_KP_ENTER})
	eq(eff["settings"], [KEY_N, KEY_F10], "主键换掉, 别名 (F10) 保留")
	eq(eff["confirm"], [KEY_KP_ENTER], "新主键与别名重复: 去重")
	eq(KeyMap.effective({"nope": 1})["confirm"], [KEY_ENTER, KEY_KP_ENTER], "未知动作忽略")


func test_resolve_groups_actions_sharing_a_key():
	var t := KeyMap.resolve({})
	eq(t[KEY_TAB], ["switch"], "Tab 只是切栏")
	check(not t.has(KEY_KP_ADD) and not t.has(KEY_KP_SUBTRACT), "小键盘 + / − 不再有动作")
	var t3 := KeyMap.resolve({"settings": KEY_TAB})
	eq(t3[KEY_TAB], ["switch", "settings"], "用户把设定绑到 Tab: 同键两个动作 (按 ACTIONS 顺序)")
	eq(t[KEY_F2], ["guide"], "F2 = 攻略")
	eq(t[KEY_F1], ["settings"], "F1 = 设定")
	eq(t[KEY_F10], ["settings"], "F10 一直是设定")
	var t2 := KeyMap.resolve({"map": KEY_F2})
	eq(t2[KEY_F2], ["map", "guide"], "用户把地图绑到 F2: 同键两个动作都触发 (按 ACTIONS 顺序)")
	check(not t2.has(KEY_M), "旧主键不再有动作")


func test_lookup_falls_back_from_shift_combo_to_bare_key():
	var t := KeyMap.resolve({})
	eq(KeyMap.lookup(t, _key(KEY_TAB)), ["switch"], "Tab")
	var ts := KeyMap.resolve({"map": KEY_TAB | KeyMap.SHIFT})
	eq(KeyMap.lookup(ts, _key(KEY_TAB)), ["switch"], "绑了 Shift+Tab 之后: Tab 仍是切栏")
	eq(KeyMap.lookup(ts, _key(KEY_TAB, true)), ["map"], "绑了 Shift+Tab 之后: Shift+Tab = 地图")
	eq(KeyMap.lookup(t, _key(KEY_TAB, true)), ["switch"], "没绑 Shift+Tab: Shift+Tab 按 Tab 处理")
	eq(KeyMap.lookup(t, _key(KEY_ENTER, true)), ["confirm"], "Shift+Enter 没绑: 按 Enter")
	eq(KeyMap.lookup(t, _key(KEY_Z)), [], "没映射的键")


func test_is_bindable():
	for k in [KEY_Z, KEY_N, KEY_F5, KEY_TAB, KEY_TAB | KeyMap.SHIFT, KEY_COMMA, KEY_PERIOD, KEY_SPACE, KEY_ENTER, KEY_KP_ADD]:
		check(KeyMap.is_bindable(k), "%s 可以绑" % OS.get_keycode_string(k))
	for k in [KEY_UP, KEY_W, KEY_A, KEY_S, KEY_D, KEY_ESCAPE, KEY_F10, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_NONE,
			KEY_Z | KEY_MASK_CTRL, KEY_Z | KEY_MASK_ALT, KEY_Z | KEY_MASK_CTRL | KeyMap.SHIFT]:
		check(not KeyMap.is_bindable(k), "%s 不能绑" % OS.get_keycode_string(k))


func test_sanitize_drops_dirty_data():
	eq(KeyMap.sanitize(null), {}, "非字典")
	eq(KeyMap.sanitize({"map": KEY_N}), {"map": KEY_N}, "合法项保留")
	eq(KeyMap.sanitize({"map": float(KEY_N)}), {"map": KEY_N}, "JSON 读回的浮点整数算整数")
	eq(KeyMap.sanitize({"map": KEY_M}), {}, "与默认主键相同的项不存")
	eq(KeyMap.sanitize({"nope": KEY_N, "map": "N", "settings": 1.5, "info": KEY_UP, "guide": KEY_F10}), {}, "未知动作 / 非整数 / 不可绑定的键丢弃 (含已删的 menu)")


func test_key_names():
	eq(KeyMap.key_name(KEY_F2), "F2", "F2")
	eq(KeyMap.key_name(KEY_TAB | KeyMap.SHIFT), "Shift+Tab", "带 Shift")
	eq(KeyMap.primary_name("map", {}), "M", "主键名")
	eq(KeyMap.primary_name("map", {"map": KEY_N}), "N", "改键后")

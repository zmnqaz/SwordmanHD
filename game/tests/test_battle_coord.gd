# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战场格子坐标 (engine/battle/ui/battle_coord.gd): 文字、标签位置、什么时候显示


func test_cursor_text():
	eq(BattleCoord.cursor_text(Vector2i(12, 7)), "12,7")
	eq(BattleCoord.cursor_text(Vector2i(0, 0)), "0,0")
	eq(BattleCoord.cursor_text(Vector2i(-1, -1)), "", "光标不可见: 没有标签")


func test_shown_only_when_setting_on_and_in_player_phase():
	check(BattleCoord.shown(1, true), "开 + 玩家操作阶段")
	check(not BattleCoord.shown(0, true), "设定关: 不显示")
	check(not BattleCoord.shown(1, false), "剧情/对白/敌方回合等非操作阶段: 不显示")
	check(BattleCoord.shown(1.0, true), "JSON 读回的 1.0 也算开")
	check(not BattleCoord.shown(null, true), "没有该设定: 不显示")


func test_tag_sits_above_cell_and_flips_below_near_top():
	var v := Vector2(320, 200)
	eq(BattleCoord.tag_pos(Vector2i(10, 8), Vector2.ZERO, v, 16.0), Vector2(301.0, 8 * 24 - 8.0 - 3.0), "在格上方")
	eq(BattleCoord.tag_pos(Vector2i(2, 0), Vector2.ZERO, v, 16.0).y, 25.0, "第一行: 上方放不下, 放到格下面 (24+1)")
	eq(BattleCoord.tag_pos(Vector2i(10, 4), Vector2(0, 96), v, 16.0).y, 25.0, "镜头卷到光标在屏幕顶部: 同样放下面")
	check(BattleCoord.tag_pos(Vector2i(10, 4), Vector2.ZERO, v, 16.0).x + 16.0 <= 320.0, "靠右边: 横向夹在画面内")
	eq(BattleCoord.tag_pos(Vector2i(0, 5), Vector2(40, 0), v, 16.0).x, 1.0, "格在画面左外: 夹到 1")

# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## UiNumber.glyph: 字符 -> 字模格号; 高清画质下数字空位不贴空白底纹 (面板自己有底纹, 贴上去会露出方框)


func test_blank_cell_skipped_only_in_hd():
	eq(UiNumber.glyph(" ", "blank", 11, false), 10, "原版画质: 空位照原版贴空白底")
	eq(UiNumber.glyph(" ", "blank", 11, true), -1, "高清: 空位只占位不画")
	eq(UiNumber.glyph(" ", "blank", 10, true), 10, "第 10 格是「?」的字模 (近景) 不动")
	eq(UiNumber.glyph(" ", "gap", 11, false), -1, "gap 照旧只占位")
	eq(UiNumber.glyph("7", "blank", 11, true), 7, "数字照常")
	eq(UiNumber.glyph("/", "blank", 11, true), 13, "斜杠")
	eq(UiNumber.glyph("?", "blank", 11, true), 11, "问号")

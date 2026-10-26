# SPDX-License-Identifier: GPL-3.0-only
class_name BattleBrief
extends Node2D
## 战场情报 (原版 素材 Misc/MIS_BRI; 重制版 GameBattleInformationUI, 2.11):
##   面板第 0 帧居中 (「、」等标点是底图自带的); 标题栏关卡名居中, 胜利条件、失败条件各两行; 底栏 敌 (红) / 我 (蓝) / 友军 (绿) 人数与回合数,
##   数字用第 1 帧字模 (8x7, 步进 7)。确认或取消都关闭。
## 坐标全在布局表 brief.* (2026-10-05 起按对照原版 的原版值, 实测叠合一致: 标题 y5 flags=5、条件 (7,24)(7,38)、人数 (21,113) %02d、回合 (138,113) %03d、条件每行 26 字节共 52 字节)。

var _size := Vector2.ZERO


## brief: 内容包 stage.json 的 briefing {title, win, lose}; counts: [敌, 我, 友军, 回合]
func _init(brief: Dictionary, counts: Array) -> void:
	var panel := UiLayout.panel("brief.panel")
	position = panel.position
	panel.position = Vector2.ZERO
	add_child(panel)
	_size = panel.size()
	var title := String(brief.get("title", ""))
	add_child(UiText.make("brief.title", title, 0, {"w": _size.x, "mw": UiText.measure(title)}))
	add_child(UiText.make("brief.win_label", String(UiLayout.val("brief.win_label", "label", ""))))
	add_child(UiText.make("brief.win_text", _clip("brief.win_text", String(brief.get("win", "")))))
	add_child(UiText.make("brief.lose_label", String(UiLayout.val("brief.lose_label", "label", ""))))
	add_child(UiText.make("brief.lose_text", _clip("brief.lose_text", String(brief.get("lose", "")))))
	for i in mini(3, counts.size()):
		add_child(UiLayout.number("brief.counts", int(counts[i]), i))
	if counts.size() > 3:
		add_child(UiLayout.number("brief.turn", int(counts[3])))


## 原版条件文字最多 max_bytes 字节 (两行), 多出的不画
static func _clip(id: String, s: String) -> String:
	var limit := int(UiLayout.num(id, "max_bytes", 0))
	if limit <= 0:
		return s
	var out := ""
	for ch in s:
		if UiText.bytes(out + ch) > limit:
			break
		out += ch
	return out

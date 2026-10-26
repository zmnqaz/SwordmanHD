# SPDX-License-Identifier: GPL-3.0-only
class_name WindowState
extends BattleState
## 居中的只读窗口:
##   BRIEF 战场情报 (2.11, MIS_BRI): 确认或取消关闭, 回到光标。
##   MAP 全图 (2.8 地圖, MAP_VIE): 方向键按住每帧卷 3 像素 (BattleMapView 自己按住检测, 不用连发), 确认或取消关闭;
##       原版打开时地图光标照常显示 (实测), 关闭有 5 帧滑出动画 (BattleMapView.dismiss)。
##   DETAIL 单位详情 (2.10, Man_pro): 确认翻页 (循环), 取消关闭, 回到打开前的状态。

enum { BRIEF, MAP, DETAIL }

var kind := BRIEF
var unit: BattleUnit
var node: Node2D


func _init(k: int, u: BattleUnit = null) -> void:
	kind = k
	unit = u


func enter() -> void:
	if kind == MAP:
		c.view.show_cursor(c.cur)
	else:
		c.view.hide_cursor()
	c.view.hide_info()
	match kind:
		BRIEF:
			node = BattleBrief.new(Content.stage_info(c.bs.st.n).get("briefing", {}), c.brief_counts())
		MAP:
			node = BattleMapView.new(c.bs.st.n, Vector2i(c.bs.st.width, c.bs.st.height), c.map_dots(), c.cur)
		DETAIL:
			node = BattleUnitDetail.new(unit)
	c.ui.add_center(node)
	if node.has_method("open"):
		node.open()


func exit() -> void:
	if not is_instance_valid(node):
		return
	if node.has_method("dismiss"):
		node.dismiss()
	else:
		node.queue_free()


func on_action(a: UiAction) -> void:
	match kind:
		MAP:
			if a.kind == UiAction.DRAG:
				node.drag(a.delta / Assets.SCALE)
			elif a.echo:
				return
			elif a.is_dir():
				node.scroll(a.dir())
			elif a.is_confirm() or a.is_cancel():
				c.pop()
		DETAIL:
			if a.echo:
				return
			if a.is_confirm():
				node.key("accept")
			elif a.is_cancel():
				c.pop()
		_:
			if not a.echo and (a.is_confirm() or a.is_cancel()):
				c.pop()

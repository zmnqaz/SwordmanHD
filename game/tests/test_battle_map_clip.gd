# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 战场地图层的两个剧情表现 (玩家反馈 2026-11-02, 第 0 幕):
## ① 人物 / 光标所在的地图层裁到当前地图矩形: 殷剑平从图外 x=24 入场时不能在镜头越界露出的黑边里先露出来;
## ② 对白移光标不改光标显示 (/ 只改光标格): 剧情开头 cursor_hide 后对白不出选择框。
const REQUIRES := ["content"]   # 光标动画名来自布局表 (map.cursor)

const BattleSceneScript = preload("res://engine/battle/battle_scene.gd")


## 光标替身: 不读贴图 (本机可能没有原版资源; 缺动画时 AnimPlayer 会自己隐藏, 干扰显示判断); 记下每次播放时的 [显示, 起始帧]
class StubCursor:
	extends AnimPlayer
	var plays: Array = []
	func play(anim_dir: String, _start := 0, _end := -1, _looped := true) -> void:
		dir = anim_dir
		plays.append([visible, _start])
		playing = false   # 不推进帧 (没有帧数据)


## 只搭世界节点 (地图层 / 光标), 不载关卡、不跑开场流程
class BareScene:
	extends "res://engine/battle/battle_scene.gd"
	func _ready() -> void:
		_build_world()


func _scene(map_size: Vector2, layer_id := 3) -> Node2D:
	var bs := BareScene.new()
	bs.st = BattleStage.new()
	bs.st.width = int(map_size.x) / BattleStage.CELL_W
	bs.st.height = int(map_size.y) / BattleStage.CELL_H
	(Engine.get_main_loop() as SceneTree).root.add_child(bs)
	bs.layer_list = [layer_id]
	bs.layer_size[layer_id] = map_size
	bs.layer_y = layer_id * BattleStage.LAYER_GAP
	return bs


func test_map_layer_clipped_to_current_map() -> void:
	var bs := _scene(Vector2(720, 384))   # 第 0 幕 24x16 格
	bs._process(0.0)
	var clip: Control = bs.units_node.get_parent()
	check(clip.clip_contents, "人物层的父节点按矩形裁剪")
	eq(Rect2(clip.position, clip.size), bs.layer_rect(), "裁剪矩形 = 当前地图矩形")
	var off := Vector2(24 * BattleStage.CELL_W, 10 * BattleStage.CELL_H)   # 图外入场格 (24,10)
	check(not Rect2(Vector2.ZERO, clip.size).has_point(off + Vector2(1, 1)), "图外格在裁剪区外 (不画)")
	eq(bs.units_node.global_position, bs.world.global_position + Vector2(0, bs.layer_y) * bs.scale, "人物层仍在图层的纵向位置 (单位坐标不变)")
	bs.layer_size[4] = Vector2(960, 600)   # 换场景 (另一张主图): 裁剪跟着换
	bs.layer_list.append(4)
	bs.layer_y = 4 * BattleStage.LAYER_GAP
	bs._process(0.0)
	eq(Rect2(clip.position, clip.size), Rect2(Vector2(0, bs.layer_y), Vector2(960, 600)), "换图层后裁剪矩形跟随")
	bs.free()


func _stub_cursor(bs) -> StubCursor:
	bs.cursor.free()
	bs.cursor = StubCursor.new()
	bs.units_node.add_child(bs.cursor)
	return bs.cursor


func test_story_cursor_keeps_hidden_cursor_hidden() -> void:
	var bs := _scene(Vector2(720, 384))
	_stub_cursor(bs)
	bs.hide_cursor()
	await bs.story_cursor_to(5, 6, false)
	check(not bs.cursor.visible, "隐藏状态下对白移光标: 仍不显示")
	eq(bs._cursor_cell, Vector2i(5, 6), "光标格照样移到说话单位")
	await bs.story_cursor_to(7, 6, true)
	check(not bs.cursor.visible, "cursor=1 滑过去也不显示")
	eq(bs._cursor_cell, Vector2i(7, 6), "滑到说话单位")
	bs.show_cursor(1, 1)
	await bs.story_cursor_to(3, 2, false)
	check(bs.cursor.visible, "原本显示的光标对白后仍显示")
	eq(bs.cursor_cell(), Vector2i(3, 2), "停在说话单位格")
	bs.free()


## 原版 AI 行动: 出手前光标换成效果范围形状、显示并滑到目标, 停一下再隐藏、放回行动者格
func test_ai_aim_cursor_shows_area_cursor_on_target() -> void:
	var bs := _scene(Vector2(720, 384))
	var cur := _stub_cursor(bs)
	var sp := UiLayout.sprite("map.cursor")
	var area_first := int(sp.get("frame", 0)) + 2 * int(sp.get("area_stride", 0))
	bs.show_cursor(3, 3)
	bs.hide_cursor()   # AI 行动开头光标已隐藏 (状态 1)
	cur.plays.clear()
	await bs.aim_cursor(Vector2i(6, 4), 2, Vector2i(3, 3))
	var aimed := cur.plays.filter(func(p): return p[1] == area_first)
	check(aimed.size() >= 4, "从 (3,3) 滑到 (6,4) 每格一帧, 都是效果范围形状 (area 2)")
	check(aimed.all(func(p): return p[0]), "滑向目标期间光标显示")
	check(not cur.visible, "出手前光标隐藏")
	eq(bs._cursor_cell, Vector2i(3, 3), "光标格放回行动者")
	eq(bs._cursor_area, 0, "形状收回单格")
	bs.reshow_cursor()
	check(cur.visible and bs.cursor_cell() == Vector2i(3, 3), "行动完在行动者格重新显示")
	cur.plays.clear()
	bs.hide_cursor()
	await bs.aim_cursor(Vector2i(3, 3), 1, Vector2i(3, 3))
	check(cur.plays.is_empty() and not cur.visible, "目标就是光标所在格: 不指向 ")
	bs.free()


## AI 单位轮到时光标从当前格滑到单位 (显示, 每 tick 1 格), 到位后隐藏; 走路期间不显示, 光标格改到落点; 行动完在落点重新显示
func test_ai_turn_cursor_slides_then_hides_while_walking() -> void:
	var bs := _scene(Vector2(720, 384))
	var cur := _stub_cursor(bs)
	bs.show_cursor(2, 2)   # 上一单位行动完 光标显示在它的落点
	cur.plays.clear()
	await bs.ai_cursor_begin(Vector2i(5, 3))
	eq(cur.plays.size(), 3, "(2,2) → (5,3) 沿对角每 tick 1 格, 共 3 步")
	check(cur.plays.all(func(p): return p[0]), "滑向单位期间光标显示")
	check(not cur.visible, "到位后隐藏 (行动对象状态 1)")
	eq(bs._cursor_cell, Vector2i(5, 3), "光标格在单位上")
	cur.plays.clear()
	bs.ai_cursor_dest(Vector2i(8, 3))
	check(not cur.visible, "开走时仍隐藏")
	eq(bs._cursor_cell, Vector2i(8, 3), "光标格改到落点 ")
	bs.reshow_cursor()
	check(cur.visible and bs.cursor_cell() == Vector2i(8, 3), "行动完在落点重新显示")
	bs.hide_cursor()   # 剧情藏了光标: 滑动不改显示与否
	cur.plays.clear()
	await bs.ai_cursor_begin(Vector2i(9, 4))
	check(not cur.plays.is_empty() and cur.plays.all(func(p): return not p[0]), "光标原本隐藏时滑动也不显示")
	bs.free()


## 单位走路镜头跟随: 走向可见区最右列 (不是地图最右列) 的一格时镜头随单位卷 1 格, 摊在走这一格的时间里;
## 中间的格、地图边的格不卷
func test_walk_step_into_edge_column_scrolls_one_cell() -> void:
	var bs := _scene(Vector2(1200, 384))   # 40x16 格, 比可见区宽
	var u := BattleUnit.new()
	var n := int(bs.view().x / BattleStage.CELL_W)
	var col0 := floori(BattleSceneScript.cam_offset().x / BattleStage.CELL_W)   # 镜头 0 时可见区最左列
	bs.cam = Vector2.ZERO
	u.cx = col0 + n / 2
	u.cy = 5
	bs._walk_edge_scroll(Vector2i(u.cx + 1, 5), 0.12, u)
	check(not bs._cam_moving, "走向可见区中间的格: 镜头不动")
	u.cx = col0 + n - 2
	bs._walk_edge_scroll(Vector2i(u.cx + 1, 5), 0.12, u)
	check(bs._cam_moving, "走进最右一列: 开始卷")
	eq(bs._cam_target, Vector2(BattleStage.CELL_W, 0), "目标 = 右移 1 格")
	bs._process(0.06)
	check(bs.cam.x > 0.0 and bs.cam.x < BattleStage.CELL_W, "半格时间只卷了一部分 (与单位同速, 不是跳)")
	bs._process(0.07)
	eq(bs.cam, Vector2(BattleStage.CELL_W, 0), "走完这一格正好卷 1 格")
	bs.cam = Vector2((40 - n) * BattleStage.CELL_W, 0)   # 镜头已到地图最右
	u.cx = 38
	bs._walk_edge_scroll(Vector2i(39, 5), 0.12, u)
	check(not bs._cam_moving, "目的格是地图最右列: 不卷")
	u.free()
	bs.free()


## 玩家操作里程序挪光标 (撤销移动等, +): 每 tick 横竖各 1 格滑过去 (可斜走), 镜头逐格边缘卷, 不平移;
## 中途 show_cursor 到别的格打断滑动 (2026-11-08 玩家「走过去后悔返回有缓动」)
func test_slide_cursor_steps_one_cell_per_tick_and_scrolls_by_cells() -> void:
	var bs := _scene(Vector2(1200, 960))
	_stub_cursor(bs)
	var col0 := floori(BattleSceneScript.cam_offset().x / BattleStage.CELL_W)
	var row0 := floori(BattleSceneScript.cam_offset().y / BattleStage.CELL_H)
	bs.cam = Vector2.ZERO
	bs.show_cursor(col0 + 2, row0 + 2)
	var target := Vector2i(col0 + 14, row0 + 4)   # 横 12 格竖 2 格, 终点在可见区外
	bs.slide_cursor_to(target)
	bs.show_cursor(target.x, target.y)   # set_cursor 随后的 show_cursor 不能把它直接放到终点
	check(bs._cursor_cell != target, "滑动开始后光标不会一步跳到终点")
	await bs.get_tree().create_timer(0.05).timeout
	var c1: Vector2i = bs._cursor_cell
	check(c1.x - (col0 + 2) >= 1 and c1.x - (col0 + 2) <= 3 and c1.y - (row0 + 2) >= 1, "第一个 tick 左右横竖各走了 1 格 (斜走): %s" % c1)
	await bs.get_tree().create_timer(0.7).timeout
	eq(bs._cursor_cell, target, "滑到终点")
	check(not bs._cam_moving, "镜头没有平移缓动")
	eq(fmod(bs.cam.x, BattleStage.CELL_W), 0.0, "镜头按整格卷")
	check(bs.cam.x > 0.0, "终点出了可见区: 镜头跟着卷过去")
	bs.slide_cursor_to(Vector2i(col0 + 2, row0 + 2))
	bs.show_cursor(col0 + 20, row0 + 3)   # 别的移动打断
	await bs.get_tree().create_timer(0.1).timeout
	eq(bs._cursor_cell, Vector2i(col0 + 20, row0 + 3), "被打断: 光标直接到新格, 不再滑")
	bs.free()


## 键盘 / 手柄一格一格移光标 (等, 2026-11-08 玩家反馈手感): 进可见区最右 / 最下一列当场卷 1 格 (不缓动), 中间不动, 只看移动的轴
func test_cursor_step_into_edge_scrolls_one_cell_instantly() -> void:
	var bs := _scene(Vector2(1200, 960))   # 40x40 格
	var cw := float(BattleStage.CELL_W)
	var ch := float(BattleStage.CELL_H)
	var n := int(bs.view().x / cw)
	var m := int(bs.view().y / ch)
	var col0 := floori(BattleSceneScript.cam_offset().x / cw)
	var row0 := floori(BattleSceneScript.cam_offset().y / ch)
	bs.cam = Vector2.ZERO
	bs.cursor_step_follow(Vector2i(col0 + 3, row0 + 3), Vector2i(col0 + 4, row0 + 3))
	eq(bs.cam, Vector2.ZERO, "走到可见区中间: 镜头不动")
	bs.cursor_step_follow(Vector2i(col0 + n - 2, row0 + 3), Vector2i(col0 + n - 1, row0 + 3))
	eq(bs.cam, Vector2(cw, 0), "走进最右一列: 当场右卷 1 格")
	check(not bs._cam_moving, "没有缓动 / 平移在跑")
	var c := Vector2i(col0 + n, row0 + m - 2)   # 卷完后它在最右列 (n-1) 上
	bs.cursor_step_follow(c, c + Vector2i(0, 1))
	eq(bs.cam, Vector2(cw, ch), "沿最右列往下走进最下一行: 只卷竖轴 1 格")
	bs.cursor_step_follow(Vector2i(col0 + 30, row0 + 30), Vector2i(col0 + 31, row0 + 30))
	check(bs._cam_moving, "新格不在可见区 (镜头被拖走过): 交给缓动跟随")
	bs.free()


## 地图 630 = 21 格, 可见区 320 = 10.7 格: 镜头贴右边 (310) 时可见区最右列 (19) 还不是地图最右列 (20), 卷 1 格会越界露黑 —— 卷动量限在地图内
## (2026-11-05 网友截图: 灵驹走到右边宝箱, 画面右侧黑一条)
func test_edge_scroll_stays_inside_map() -> void:
	var bs := _scene(Vector2(630, 384))
	var u := BattleUnit.new()
	var max_x: float = 630.0 - bs.view().x
	bs.cam = Vector2(max_x, 0)
	var col := floori((max_x + BattleSceneScript.cam_offset().x) / BattleStage.CELL_W) + int(bs.view().x / BattleStage.CELL_W) - 1   # 可见区最右列
	check(col < 630 / BattleStage.CELL_W - 1, "前提: 这一列不是地图最右列 (%d)" % col)
	u.cx = col - 1
	u.cy = 5
	bs._walk_edge_scroll(Vector2i(col, 5), 0.12, u)
	check(not bs._cam_moving, "镜头已贴地图右边: 走路不卷")
	bs._cursor_edge_scroll(0, Vector2i(col, 5))
	eq(bs.cam.x, max_x, "光标到最右列也不卷出地图")
	bs.cam = Vector2(max_x - 10.0, 0)   # 离地图边不到 1 格: 只卷到地图边
	bs._walk_edge_scroll(Vector2i(floori((max_x - 10.0 + BattleSceneScript.cam_offset().x) / BattleStage.CELL_W) + int(bs.view().x / BattleStage.CELL_W) - 1, 5), 0.12, u)
	eq(bs._cam_target.x, max_x, "不足 1 格: 卷到地图边为止")
	u.free()
	bs.free()

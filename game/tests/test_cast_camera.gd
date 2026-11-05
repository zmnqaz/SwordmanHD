# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 施法演出的镜头与落点 (差异, 玩家反馈 2026-11-05「离火神诀没有在被打十字的中间」):
## 原版演出器 (-> 镜头) 把镜头移到 (col*30-0x91, row*24-0x58) 不夹地图, 再在屏幕 (0,0) 画法术帧,
## 所以帧恒对准落点格; 复刻原先夹镜头 + 满屏动画「贴实际镜头原点」, 落点靠地图边时整幅演出跟着镜头偏离 (第 1 关客栈下沿偏 16 像素)。
const REQUIRES := ["content"]   # 演出表 fx/cast.json、布局表约定

const MAP := Vector2(990, 696)   # 第 1 关客栈 map01 (33x29 格)


class BareScene:
	extends "res://engine/battle/battle_scene.gd"
	func _ready() -> void:
		_build_world()


func _scene() -> Array:
	var bs := BareScene.new()
	bs.st = BattleStage.new()
	bs.st.width = int(MAP.x) / BattleStage.CELL_W
	bs.st.height = int(MAP.y) / BattleStage.CELL_H
	(Engine.get_main_loop() as SceneTree).root.add_child(bs)
	bs.layer_list = [1]
	bs.layer_size[1] = MAP
	var view := BattleView.new(bs, null)
	bs.add_child(view)
	return [bs, view]


## 落点在地图下沿 (第 25 行): 原版镜头 y = 25*24-88 = 512, 越过可夹范围 696-200 = 496 共 16 像素 (越界处画黑); 演出帧原点 = 实际镜头原点 = 格 + fx 约定
func test_cast_camera_not_clamped_and_fx_on_target_cell() -> void:
	var r := _scene()
	var bs = r[0]
	var view: BattleView = r[1]
	var c := Vector2i(16, 25)
	var want := FxPlace.center_cam(c)
	eq(want, Vector2(16 * 30 - 145, 25 * 24 - 88), "原版演出镜头 (col*30-0x91, row*24-0x58)")
	check(want.y > MAP.y - 200, "这个落点的原版镜头越过地图下沿 (夹紧会偏)")
	bs.cam = bs._orig_to_view(want) - Vector2(0, 6)   # 从附近开始平移, 测试不用等太久
	await view.cast_camera(c)
	eq(bs.orig_cam(), want, "施法镜头不夹地图 ")
	var a: Node2D = view.spawn_map_fx("Magic/__missing__/M0", c)
	eq(a.position, FxPlace.at_cell(c, "fx"), "演出帧锚在落点格 + fx 约定")
	eq(a.position, bs.orig_cam(), "= 实际镜头原点 (原版在屏幕 (0,0) 画)")
	eq(a.get_parent(), bs.fx_node, "挂在不裁地图矩形的演出层 (越界的黑底上照样画火圈)")
	check(not bs._map_clip.is_ancestor_of(a), "不在人物层的裁剪节点下")
	bs._process(0.0)
	eq(bs.fx_node.global_position, bs.units_node.global_position, "演出层与人物层同坐标")
	bs.queue_free()   # 在镜头到位信号的回调里, 不能立即 free


## 收尾回到施法前的镜头 (原版演出器状态 8, 字段/字段), 回去的位置夹在地图内; 地图升级光旋的镜头仍夹紧
func test_cast_camera_returns_and_level_up_stays_clamped() -> void:
	var r := _scene()
	var bs = r[0]
	var view: BattleView = r[1]
	var before := Vector2(300, 480)
	bs.cam = bs._orig_to_view(before)
	view._pre_cast_cam = bs.orig_cam()
	var c := Vector2i(16, 25)
	bs.cam = bs._orig_to_view(FxPlace.center_cam(c))
	await view.cast_camera_return()
	eq(bs.orig_cam(), before, "回到施法前镜头")
	bs.cam = bs._orig_to_view(FxPlace.center_cam(c)) - Vector2(0, 30)
	await view.cast_camera(c, true)
	eq(bs.cam.y, MAP.y - bs.view().y, "clamp = true: 夹在地图内")
	bs.queue_free()   # 在镜头到位信号的回调里, 不能立即 free

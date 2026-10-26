# SPDX-License-Identifier: GPL-3.0-only
class_name FxPlace
extends RefCounted
## 演出贴图定位: 地图上一切 SAF 演出 (法术、绝技、施法光效、结果动画、光标) 都按同一条规则放置, 参数全部来自内容数据。
##
## 1. 帧坐标约定 (convention): SAF 部件 (x,y) 画在某个约定的帧坐标里, 约定给出「锚点格左上角 + 偏移 = 帧原点」。
##    数据 ui_theme/layout.json sprite_rules.map_conventions, 原版两种:
##      unit (-142,-110)  战场人物帧 (x*30+子像素-卷动-0x8e, y*24+子像素-卷动-0x6e;
##                        同); 结果动画 MAN_RES 实测与人物同原点
##      object (-142,-106) 地图物件/城镇人物 (宝箱等 LAYER 物件 x*30-0x8e, y*24-0x6a)
##      fx   (-145,-88)   光标与演出剧场 (把镜头移到 (col*30-0x91, row*24-0x58)
##                        后在屏幕 (0,0) 画 Magic/M*.SAF 与 Mag_misc)。实测 (离火神诀, 200 块帝国):
##                        地图对上镜头 (455,1784) = 格 (20,78) 按 0x91/0x58 求的值, 法术帧与屏幕 (0,0) 偏差 ≤1 像素。
## 2. 锚点 (anchor): "target" 落点格 / "caster" 施法者格 / "unit" 受影响单位 (随单位当前像素位置)。
## 3. 世界坐标 = 锚点像素 + 约定偏移, 整数原版像素。部件偏移由 AnimPlayer 按原版像素加上; 贴图倍数 (hd4x/hd6x)
##    只体现在 Sprite2D.scale = 1/倍数, 不参与定位 (hd 贴图尺寸恰为原图 ×4/×6, 已全量核对), 所以换倍数不丢偏移、无取整误差。
## 4. 镜头: 原版演出前把镜头移到让锚点格落在屏幕 (145,88) (不夹紧), 演出帧画在屏幕 (0,0)。复刻把帧挂在地图坐标里随镜头走,
##    镜头被夹在地图内或宽屏时格子不在正中, 演出仍对准格子 (center_cam() 给出原版镜头位置, 由场景换算到视口并夹紧)。
## 新游戏/新技能: 换约定改 layout.json; 某技能用别的动画或锚点, 在技能记录里加 "fx" 字段 (见 fx/cast.json), 不改脚本。

const CELL := Vector2(BattleStage.CELL_W, BattleStage.CELL_H)

static var _conv := {}


## 约定偏移 (格左上角 -> 帧原点)
static func offset(conv: String) -> Vector2:
	if _conv.is_empty():
		_load()
	if not _conv.has(conv):
		push_warning("FxPlace: 布局表 sprite_rules.map_conventions 没有约定 " + conv)
	return _conv.get(conv, Vector2.ZERO)


static func _load() -> void:
	_conv = {}
	var mc: Dictionary = UiLayout.data().get("sprite_rules", {}).get("map_conventions", {})
	for k in mc:
		if mc[k] is Array and mc[k].size() == 2:
			_conv[k] = Vector2(int(mc[k][0]), int(mc[k][1]))


## 内容包 JSON (autoload Content 不在时返回 null, 用默认值)
static func content_json(rel: String) -> Variant:
	var c := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Content")
	return c.json(rel) if c else null


## 测试或换内容包后重读
static func reload() -> void:
	_conv.clear()
	UiLayout.reload()


## 格 c 上按约定 conv 放置时, 动画节点的位置 (地图坐标, 原版像素)
static func at_cell(c: Vector2i, conv: String) -> Vector2:
	return Vector2(c) * CELL + offset(conv)


## 单位当前像素位置 (格左上角, 移动中含插值) 上按约定放置
static func at_pixel(p: Vector2, conv: String) -> Vector2:
	return p.round() + offset(conv)


## 原版演出镜头: 让格 c 落在 fx 约定原点处 (即 320x200 画面中央), 返回 320x200 视口左上角 (地图坐标)
static func center_cam(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL + offset("fx")

# SPDX-License-Identifier: GPL-3.0-only
class_name RpgStage
extends RefCounted
## RPG 场景 (城镇) 配置, 从内容包 towns/NN/ 读取 (Content, docs/内容格式.md §8):
##   town.json: 地图贴图、入口、商店引用、脚本与对白引用; map.json: 格子 (可走、对话事件、踩踏事件); layers.json: NPC 与场景动画。
## 字段沿用 B2 之前解析原版 RPG_NN.DAT 等时的结构 (docs/内容格式.md §13)。共用地图 (原 MAP_FIX 特判) 已由导入工具写进 map_image。
## 原版二进制解析已移到 tests/legacy_original.gd (只给工具与测试用)。

var n := 0
var dir := ""            # 本城资源目录 (只用于日志与缺省动画路径)
var map_rel := ""        # 地图贴图
var layers1: Array = []  # 物件 [{id, parm, x, y, u3, u5, name, anim}]
var width := 0
var height := 0
var cells: Array = []    # [{walk: bool, talk: int, step: int}]
var pos: Array = []      # 入口 [{music, map_x, map_y, x, y, dir}]
var shops: Array = []    # [{id, type, shop, items: [...], keeper_anim, show (SceneShow 配置)}], 下标 = 商店指令的商店号
var events: Array = []   # 剧情脚本 (scripts/town_NN.evs 编译)
var emsg: Array = []


static func load_stage(stage: int) -> RpgStage:
	var s := RpgStage.new()
	s.n = stage
	var info: Dictionary = Content.town_info(stage)
	assert(not info.is_empty(), "内容包里没有城镇 %d" % stage)
	var assets: Dictionary = info.get("assets", {})
	s.dir = String(assets.get("dir", ""))
	s.map_rel = String(assets.get("map_image", ""))
	for o in Content.town_file(stage, "layers.json").get("objects", []):
		var f := String(o["file"])
		s.layers1.append({"id": o["layer"], "parm": o["tag"], "x": o["x"], "y": o["y"], "u3": o["flag_var"], "u5": o["play_mode"],
			"name": f.get_basename() if "." in f else f, "anim": o.get("anim")})
	var mp: Dictionary = Content.town_file(stage, "map.json")
	s.width = int(mp["width"])
	s.height = int(mp["height"])
	for y in s.height:
		for x in s.width:
			s.cells.append({"walk": int(mp["block"][y][x]) == 0, "talk": mp["talk"][y][x], "step": mp["step"][y][x]})
	s.pos = info.get("entries", [])
	for id in info.get("shops", []):
		var sh: Dictionary = ContentDB.ints(Content.shop(String(id)))
		s.shops.append({"id": String(id), "type": sh.get("type", 0), "shop": sh.get("keeper", 0), "items": sh.get("items", []),
			"keeper_anim": sh.get("keeper_anim"), "show": sh.get("show")})
	s.events = Content.events(info.get("script", {}))
	s.emsg = Content.text_groups(String(info.get("text", "")))
	return s


## 物件动画目录
func obj_anim(o: Dictionary) -> String:
	var a = o.get("anim")
	return String(a) if a != null else "%s/%s" % [dir, o["name"]]


func cell(x: int, y: int) -> Dictionary:
	if x < 0 or y < 0 or x >= width or y >= height:
		return {}
	return cells[y * width + x]


func talk(event_id: int, num: int) -> String:
	if event_id < emsg.size() and num >= 0 and num < emsg[event_id].size():
		return emsg[event_id][num]
	return ""


## 主角朝向码 (/写入 [this+0x100]): 0 下 1 左 2 上 3 右, 与 DIRS4 同序
## 按住多个方向键时原版固定优先级 上 > 下 > 左 > 右 (依次查 0x26 0x28 0x25 0x27), 与按下先后无关
const KEY_PRIORITY: Array[int] = [UiAction.UP, UiAction.DOWN, UiAction.LEFT, UiAction.RIGHT]

const DIRS4: Array[Vector2i] = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]


## 镜头位置取整到「物理像素」(mult = 窗口里 1 个原版像素占几个物理像素), 不是取整到原版像素。
## 城镇行走每格 0.4 秒, 横向一格 30 像素 = 75 像素/秒、纵向一格 24 像素 = 60 像素/秒; 60Hz 下纵向正好每帧 1 个原版像素, 取整到原版像素没事,
## 横向每帧 1.25 个, 取整后变成 1、1、1、2 的不均匀步进 —— 横向明显比纵向卡 (用户 2026-10-20 反馈客栈)。取整到物理像素后窗口 4 倍时横向每帧正好 5 个物理像素,
## 6 倍时 7、8 交替 (差 1 个物理像素, 看不出); mult < 1 (无头测试的小窗口) 退回原来的取整到原版像素。
static func snap_camera(p: Vector2, mult: float) -> Vector2:
	if mult < 1.0:
		return p.round()
	return (p * mult).round() / mult


## 原版走路判定: 目标格在地图内且阻挡字节为 0 才走; 否则只转向 (朝向照样改, 一族)
func can_step(x: int, y: int, d: int) -> bool:
	var n: Vector2i = Vector2i(x, y) + DIRS4[d]
	var c := cell(n.x, n.y)
	return not c.is_empty() and c["walk"]


## 从 from 寻路到 goals 中任一格 (只走 walk 格, 不含起点); avoid_steps 时不穿过途中的踩踏事件格。走不到返回 []
func find_path(from: Vector2i, goals: Array, avoid_steps: bool) -> Array:
	var prev := {from: from}
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c in goals and c != from:
			var path: Array = []
			while c != from:
				path.push_front(c)
				c = prev[c]
			return path
		for d in DIRS4:
			var nb: Vector2i = c + d
			var cl := cell(nb.x, nb.y)
			if not prev.has(nb) and not cl.is_empty() and cl["walk"]:
				if avoid_steps and int(cl["step"]) > 0 and not nb in goals:
					continue
				prev[nb] = c
				q.append(nb)
	return []


## 从 from 出发 (不穿过踩踏事件格, 踩上去就触发了) 能到达的全部格子
func reachable(from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c != from and int(cell(c.x, c.y)["step"]) > 0:
			continue
		for d in DIRS4:
			var nb: Vector2i = c + d
			var cl := cell(nb.x, nb.y)
			if not seen.has(nb) and not cl.is_empty() and cl["walk"]:
				seen[nb] = true
				q.append(nb)
	return seen

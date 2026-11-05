# SPDX-License-Identifier: GPL-3.0-only
class_name BattleStage
extends RefCounted
## 战斗关卡的全部配置, 从内容包 stages/NN/ 读取 (Content, docs/内容格式.md §6)。
## 字段沿用 B2 之前解析原版二进制时的结构 (对照见 docs/内容格式.md §13), 战场代码不用改读法;
## 资源路径 (图层底图/物件动画、标题卡、近景地面、事件动画) 直接取内容里写的路径, 不再按原版文件名拼。
## 原版二进制解析已移到 tests/legacy_original.gd (只给工具与测试用)。

const CELL_W := 30
const CELL_H := 24
## 玩家 / AI 移动的走路速度 (横向原版像素/秒): 原版 Win10 原生逐帧实测 (40 次格间隔, 横向平均 0.236 s、竖向 0.237 s): 每格固定 6 tick = 0.24 s, 横竖一样,
## 所以竖向像素速度是横向的 CELL_H/CELL_W 倍 (BattleUnit._process 按「每格用时」走)。之前用 150 像素/秒且横竖等速, 横向快 20%、竖向快 50%
const UNIT_WALK_SPEED := 125.0
## 帧原点约定 (格左上角 + 偏移) 在布局表 sprite_rules.map_conventions: 城镇人物/地图物件 FxPlace.offset("object"), 战场人物 "unit"
const LAYER_GAP := 5000                   # 不同图层在世界里纵向错开的距离 (重制版 layerHeight = id * 5000)

var n := 0
var dir := ""            # 本关资源目录 (只用于日志)
var name := ""
var music := 0
var man: Array = []      # 单位配置 (units.json 去掉坐标), 下标即单位编号
var xy: Array = []       # 单位初始格子 [{id,x,y}], 与 man 同序 (有坐标的那些)
var tevt: Array = []     # 回合事件 [{turn, type, event}], type 0 = 回合开始
var mevt: Array = []     # 地图事件 [{type, parm1, parm2, item_type, item1, item2, show}]
var width := 0           # 地图格数
var height := 0
var cells: Array = []    # [{move, floor, event}], 行优先
var layers0: Array = []  # 图层底图 [{id, z, u4, u5, layer, name, image, anim}]
var layers1: Array = []  # 图层物件 [{id, parm, x, y, effect, pause, delay, visible, name, anim}]
var events: Array = []   # 剧情脚本 (scripts/stage_NN.evs 编译): [[{type, data}, ...], ...]
var emsg: Array = []     # 对白: [[句子...], ...], 组号 = 事件编号
var judge := {"win": [], "lose": []}  # 胜负条件 [{type, id, event}], type 1 全灭 / 2 指定单位
var title_card := ""     # 关卡标题卡动画 (剧情指令 show_title)
var battle_floor := ""   # 近景战斗地面动画, 帧号 = cells[].floor
var event_anims := {}    # 事件动画号 (anim_load file=) -> 动画目录


static func load_stage(stage: int) -> BattleStage:
	var s := BattleStage.new()
	s.n = stage
	var info: Dictionary = Content.stage_info(stage)
	assert(not info.is_empty(), "内容包里没有第 %d 关" % stage)
	var assets: Dictionary = info.get("assets", {})
	s.dir = String(assets.get("dir", ""))
	s.name = String(info.get("name", ""))
	s.music = int(info.get("music", 0))
	s.title_card = String(assets.get("title_card", ""))
	s.battle_floor = String(assets.get("battle_floor", ""))
	for k in assets.get("event_anims", {}):
		s.event_anims[int(k)] = String(assets["event_anims"][k])
	for u in Content.stage_file(stage, "units.json"):
		var m := {}
		for k in u:
			if not String(k).begins_with("_") and not k in ["x", "y", "xy_unit_id"]:
				m[k] = u[k]
		s.man.append(m)
		if u.has("x"):
			s.xy.append({"id": int(u.get("xy_unit_id", u["unit_id"])), "x": int(u["x"]), "y": int(u["y"])})
	for t in info.get("turn_events", []):
		s.tevt.append({"turn": t["turn"], "type": t["timing"], "event": t["event"]})
	for e in info.get("map_events", []):
		s.mevt.append({"type": e["type"], "parm1": e["trigger"], "parm2": e["event"], "item_type": e["item_type"],
			"item1": e["item"], "item2": e["prompt"], "show": e["show"]})
	var mp: Dictionary = Content.stage_file(stage, "map.json")
	s.width = int(mp["width"])
	s.height = int(mp["height"])
	for y in s.height:
		for x in s.width:
			s.cells.append({"move": mp["terrain"][y][x], "floor": mp["floor"][y][x], "event": mp["event"][y][x]})
	var ly: Dictionary = Content.stage_file(stage, "layers.json")
	for b in ly.get("backgrounds", []):
		s.layers0.append({"id": b["layer"], "z": b["z"], "u4": b["view"][0], "u5": b["view"][1], "layer": b["draw_layer"],
			"name": b["file"], "image": b.get("image"), "anim": b.get("anim")})
	for o in ly.get("objects", []):
		s.layers1.append({"id": o["layer"], "parm": o["tag"], "x": o["x"], "y": o["y"], "effect": o["flag_var"],
			"pause": o["play_mode"], "delay": o["delay"], "visible": o["hidden"], "name": o["file"], "anim": o.get("anim")})
	for side in ["win", "lose"]:
		for c in info.get("judge", {}).get(side, []):
			s.judge[side].append({"type": c["type"], "id": c["unit"], "event": c["event"]})
	s.events = Content.events(info.get("script", {}))
	s.emsg = Content.text_groups(String(info.get("text", "")))
	return s


## 物件动画目录 (内容里没写时按原版文件名拼, 原版包都写了)
func obj_anim(o: Dictionary) -> String:
	var a = o.get("anim")
	return String(a) if a != null else "%s/%s" % [dir, String(o["name"]).get_basename()]


## 底图: {"image": 贴图路径} 或 {"anim": 动画目录}
func bg_anim(l: Dictionary) -> String:
	var a = l.get("anim")
	if a != null:
		return String(a)
	return "%s/%s" % [dir, String(l["name"]).get_basename()] if String(l["name"]).to_lower().ends_with(".saf") else ""


func bg_image(l: Dictionary) -> String:
	var i = l.get("image")
	return String(i) if i != null else "%s/%s.png" % [dir, String(l["name"]).get_basename()]


## 开场就一直显示的远景图层 (原版第 4 幕悬崖外的云海 map04-1: Windows 原版实测地图以外画的是这张云海, 随镜头 1/4 速度视差滚动, 复刻原先从不加载它所以悬崖外是黑的):
## 远景图 (尺寸参数不是 10x8) 所在的图层如果既不是主图层 (1)、没有物件、也从来没有被任何事件的「加载图层」(0x23) 指令加载过, 就是与主场景一起常驻的背景;
## 被事件加载的 (第 0 幕云海 map00-3、第 23 幕 map23-2 等) 仍由事件决定何时出现
func auto_bg_layers() -> Array:
	var by_event := {}
	for ev in events:
		for op in ev:
			if int(op["type"]) == 0x23:
				var d: PackedByteArray = op["data"]
				by_event[d.decode_s16(0) if d.size() >= 2 else 0] = true
	var has_objs := {}
	for o in layers1:
		has_objs[int(o["id"])] = true
	var main_ids := {}
	for l in layers0:
		if int(l["u4"]) == 10 and int(l["u5"]) == 8:
			main_ids[int(l["id"])] = true
	var out: Array = []
	for l in layers0:
		var id := int(l["id"])
		if id == 1 or main_ids.has(id) or has_objs.has(id) or by_event.has(id) or id in out:
			continue
		out.append(id)
	return out


## 事件动画号 -> 动画目录 (内容里没有该号时按原版命名 Eanm_NN, 动画不存在时 AnimPlayer 不显示)
func event_anim(file: int) -> String:
	return event_anims.get(file, ThemeAssets.f("event_anim", [dir, file]))


func cell(x: int, y: int) -> Dictionary:
	if x < 0 or y < 0 or x >= width or y >= height:
		return {}
	return cells[y * width + x]


func talk(event_id: int, num: int) -> String:
	if event_id < emsg.size() and num < emsg[event_id].size():
		return emsg[event_id][num]
	return ""

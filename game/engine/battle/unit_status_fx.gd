# SPDX-License-Identifier: GPL-3.0-only
class_name UnitStatusFx
extends Node2D
## 战场单位身上的状态外观 (原版 SetEffect / 绘制, Misc/Man_eff.SAF, 2026-10-12 实测 + 对照原版, 差异):
##   每个状态有一段 Man_eff 帧循环叠在单位身上: 帧 = 基数 + 计数器, 计数器每 3 个游戏 tick (0.12 秒) 加 1, 到周期归零;
##   封咒 = 红色同心圆环 (帧 45~86), 增益 (攻/防/技/速提升四种共用) = 脚下蓝白光环 (1~22, 在贴图之下) + 头侧火花 (23~44),
##   對技全禦 / 對術全禦 / 地縛 / 冰結 各有自己的一段; 画法、层次 (贴图之上 / 之下 / 前后各半)、位置偏移全在布局表 map.unit.status_fx。
##   不用 Man_eff 的几种: 麻痹 = 贴图每 0.12 秒在 {-1,0,+1} 像素里随机抖, 狂暴 = 红色轮廓光晕脉动 (这里用红色调脉动近似),
##   中毒 = 贴图变绿、冰結 = 贴图变蓝、幻影 = 半透明 (这三个是 BattleUnit._tint 按布局表 map.unit.status_tint 着色)。
## 只管叠层与抖动; 状态位变了由 BattleUnit._tint 调 refresh。人物位置同 anim 的偏移 + 表里的 offset (Man_eff 与人物帧同坐标系, y 多 4)。

const U = preload("res://engine/rules/unit_state.gd")

var _unit            # BattleUnit
var _player_script   # AnimPlayer 的脚本 (用 get_script().new() 建节点, 不在 engine 里写出 AnimPlayer 类名)
var _dir := ""
var _tick := 0.12
var _entries: Array = []   # [{def, player, active}]
var _t := 0.0
var _last_c := -1
var _jitter := false
var _berserk := false
var _base_x := 0.0


func setup(unit) -> void:
	_unit = unit
	_player_script = unit.anim.get_script()
	_dir = ThemeAssets.p("battle.status_fx")
	var d: Dictionary = UiLayout.el("map.unit.status_fx")
	_tick = float(d.get("tick", 0.12))
	_base_x = unit.anim.position.x
	position = unit.anim.position + UiLayout.vec("map.unit.status_fx", "offset", Vector2(0, 4))
	for e in d.get("entries", []):
		var p = _player_script.new()
		p.play_sound = false
		add_child(p)
		_entries.append({"def": e, "player": p, "active": false})


## 状态解除 (阶段开始 R-=K 到 0) 时在单位身上放的结果动画区间 [起, 止) (Misc/MAN_RES, 布局表 map.unit.expire_fx, 差异):
## 到期位里有增益/全禦/狂暴/幻影之一用「正面」段, 否则 (麻痹/地縛/封咒/中毒/冰結) 用「负面」段。mask = 到期位的并集。
static func release_range(mask: int) -> Array:
	var d: Dictionary = UiLayout.el("map.unit.expire_fx")
	var seg: Array = d.get("positive", [60, 81]) if (mask & int(d.get("positive_mask", 2175))) != 0 else d.get("negative", [81, 99])
	return [int(seg[0]), int(seg[1])]


## 冰結被打碎 (受击解除) 的动画区间 (模式 3, 实测 14 帧 1.64 秒)
static func freeze_break_range() -> Array:
	var seg: Array = UiLayout.val("map.unit.expire_fx", "freeze_break", [32, 46])
	return [int(seg[0]), int(seg[1])]


## 中毒扣血的命中动画区间 (模式 0 = MAN_RES 帧 2~9, 实测 8 帧 0.96 秒; 布局表 map.unit.poison_fx)
static func poison_range() -> Array:
	var seg: Array = UiLayout.val("map.unit.poison_fx", "frames", [2, 10])
	return [int(seg[0]), int(seg[1])]


## 状态位 -> 显示/隐藏各段叠层, 麻痹抖动与狂暴脉动的开关
func refresh(status: int) -> void:
	for en in _entries:
		var on := (status & int(en.def["mask"])) != 0
		en.active = on
		en.player.visible = on
	_jitter = (status & U.ST_PARALYZE) != 0
	_berserk = (status & U.ST_BERSERK) != 0
	_last_c = -1
	if not _jitter:
		_unit.anim.position.x = _base_x
	set_process(_any())


func _any() -> bool:
	return _jitter or _berserk or _entries.any(func(en): return en.active)


func _process(delta: float) -> void:
	_t += delta
	var c := int(_t / _tick)
	if c == _last_c:
		return
	_last_c = c
	for en in _entries:
		if not en.active:
			continue
		var d: Dictionary = en.def
		var period := int(d["period"])
		var k := c % period
		en.player.show_frame(_dir, int(d["base"]) + k)
		var front := int(d.get("front", -1))   # 前后各半: 计数器 < front 画在贴图前, 其余在贴图后
		var layer := String(d.get("layer", "above"))
		en.player.z_index = (1 if k < front else -1) if layer == "split" else (1 if layer == "above" else -1)
	if _jitter:
		_unit.anim.position.x = _base_x + float(randi_range(-1, 1))
	if _berserk:
		var s := 0.5 + 0.5 * sin(float(c) * 0.5)   # 红色轮廓光晕宽 0..6 像素脉动, 近似成红色调脉动
		var tint := UiLayout.color(UiLayout.val("map.unit.status_fx", "berserk_tint", [1.0, 0.55, 0.55]))
		_unit.anim.modulate = Color.WHITE.lerp(tint, s)

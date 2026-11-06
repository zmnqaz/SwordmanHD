# SPDX-License-Identifier: GPL-3.0-only
class_name UnitStatusFx
extends Node2D
## 战场单位身上的状态外观 (原版 SetEffect / 绘制, Misc/Man_eff.SAF, 2026-10-12 实测 + 对照原版, 差异):
##   每个状态有一段 Man_eff 帧循环叠在单位身上: 帧 = 基数 + 计数器, 计数器每 3 个游戏 tick (0.12 秒) 加 1, 到周期归零 (每种效果各自计数, 上身时从 0 起);
##   封咒 = 红色同心圆环 (帧 45~86), 增益 (攻/防/技/速提升四种共用) = 脚下蓝白光环 (1~22, 在贴图之下) + 头侧火花 (23~44),
##   對技全禦 / 對術全禦 / 地縛 / 冰結 各有自己的一段; 画法、层次 (贴图之上 / 之下 / 前后各半)、位置偏移全在布局表 map.unit.status_fx。
##   人物定格: 麻痹、冰結时人物不换帧 (起换帧前判 字段 麻痹 / 字段 冰結 (SetEffect 效果 2 / 11), 任一置位就跳过; 2026-11-06 对照原版)。
##   不用 Man_eff 的几种: 麻痹 = 再加左右摇晃 (见 jitter_step), 狂暴 = 人物拉伸放大 w (0/2/4/6 往返) 后挖掉人物本身剩下的红色轮廓环, 人物不变红 (unit_berserk.gdshader),
##   中毒 / 冰結 / 幻影 = 人物贴图按原版混色公式着色 (status_material, unit_status.gdshader); 参数全在布局表 map.unit.status_tint (2026-11-06)。
## 只管叠层与抖动; 状态位变了由 BattleUnit._tint 调 refresh。人物位置同 anim 的偏移 + 表里的 offset (Man_eff 与人物帧同坐标系, y 多 4)。

const U = preload("res://engine/rules/unit_state.gd")
const STILL_MASK := U.ST_PARALYZE | U.ST_FREEZE   # 人物定格不换帧的状态
const TINT_MASK := U.ST_POISON | U.ST_FREEZE | U.ST_PHANTOM   # 人物贴图着色的状态
## 有这几种增益时脚下画光环 (Man_eff 1~22) 代替影子 (Man_eff 第 0 帧, type 7 压暗): 二选一, 光环帧里没有影子
const NO_SHADOW_MASK := U.ST_ATK_UP | U.ST_DEF_UP | U.ST_TECH_UP | U.ST_HASTE
const STATUS_SHADER := preload("res://shaders/unit_status.gdshader")
const BERSERK_SHADER := preload("res://shaders/unit_berserk.gdshader")

static var _mats := {}   # 着色材质缓存: 键 = status & TINT_MASK

var _unit            # BattleUnit
var _player_script   # AnimPlayer 的脚本 (用 get_script().new() 建节点, 不在 engine 里写出 AnimPlayer 类名)
var _dir := ""
var _tick := 0.12
var _entries: Array = []   # [{def, player, active}]
var _t := 0.0
var _last_c := -1
var _jitter := false
var _still := false
var _jit_off := 0      # 麻痹摇晃的当前横向偏移 (原版单位对象 字段, 只取 -1 / 0 / +1)
var _berserk := false
var _base_x := 0.0
var _bz_player   # 狂暴光晕: 人物当前帧的一份拷贝, 套 unit_berserk 材质, 画在人物之上
var _bz_mat: ShaderMaterial
var _bz_w := 0       # 光晕宽度 (原版 字段), min..max 每 0.12 秒 ±step 往返
var _bz_down := false


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
		_entries.append({"def": e, "player": p, "active": false, "start": 0})


## 中毒 / 冰結 / 幻影的人物着色材质 (中毒 → 冰結 → 幻影), 都没有返回 null。
## 权重 = 原版权重档 k 的 (k>>1)/8 (AnimPlayer.tint_weight), 颜色 RGB555 (AnimPlayer.rgb555); 参数全在布局表 map.unit.status_tint
static func status_material(status: int) -> Material:
	var key := status & TINT_MASK
	if key == 0:
		return null
	if not _mats.has(key):
		var d: Dictionary = UiLayout.el("map.unit.status_tint")
		var m := ShaderMaterial.new()
		m.shader = STATUS_SHADER
		for pair in [["tint1", "poison", U.ST_POISON], ["tint2", "freeze", U.ST_FREEZE]]:
			var on := (key & int(pair[2])) != 0
			m.set_shader_parameter(pair[0] + "_on", on)
			if on:
				var e: Dictionary = d.get(pair[1], {})
				var c := _rgb555(e.get("col", 0))
				m.set_shader_parameter(pair[0] + "_col", Vector3(c.r, c.g, c.b))
				m.set_shader_parameter(pair[0] + "_col_k", _w(e.get("col_k", 0)))
				m.set_shader_parameter(pair[0] + "_src_k", _w(e.get("src_k", 16)))
		var ghost := (key & U.ST_PHANTOM) != 0
		m.set_shader_parameter("ghost", ghost)
		if ghost:
			var g: Dictionary = d.get("phantom", {})
			m.set_shader_parameter("ghost_src", _w(g.get("src_k", 8)))
			m.set_shader_parameter("ghost_keep", _w(g.get("dst_keep", 8)))
		_mats[key] = m
	return _mats[key]


## 原版权重表一项 (填): 5 位通道 v 乘权重档 k (实际 K = 2*(k>>1)), t = min(31, floor(v*K/16)) 再清最低位 (& 0x7bde);
## 着色器 unit_status / unit_berserk 里的 tw() 与它逐位一致, 这里给测试与文档对照
static func t555(v5: int, k: int) -> int:
	var t := mini(31, v5 * (2 * (maxi(k, 0) >> 1)) / 16)
	return t & ~1


## 一个通道: 源 * T[src_k] + 色 * T[col_k], 超过 31 封顶 (进位位检查)
static func blend555(v5: int, src_k: int, col5: int, col_k: int) -> int:
	return mini(31, t555(v5, src_k) + t555(col5, col_k))


## 原版权重档 -> 权重, 颜色 (十六进制字符串或整数) -> Color: 与演出动画部件同一套 (AnimPlayer.tint_weight / rgb555)
static func _w(k) -> float:
	return float(maxi(int(k), 0) >> 1) / 8.0


static func _rgb555(v) -> Color:
	var u: int = String(v).hex_to_int() if v is String else int(v)
	return Color(((u >> 10) & 31) / 31.0, ((u >> 5) & 31) / 31.0, (u & 31) / 31.0)


## 狂暴光晕宽度往返一步 (字段 = 1 往返模式): 往上加 step 超过 max 就转向、取 max - step; 往下减到小于 min 就转向、取 min + step
static func berserk_step(w: int, down: bool, lo: int, hi: int, step: int) -> Array:
	if not down:
		w += step
		if w > hi:
			return [hi - step, true]
		return [w, false]
	w -= step
	if w < lo:
		return [lo + step, false]
	return [w, true]


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
	var c_now := int(_t / _tick)
	for en in _entries:
		var on := (status & int(en.def["mask"])) != 0
		if on and not en.active:
			en.start = c_now   # 原版 SetEffect 上身时计数器清 0, 从段首帧开始
		en.active = on
		en.player.visible = on
	if _unit.has_method("update_shadow"):
		_unit.update_shadow()   # 有增益: 光环代替影子
	var was_still := _still
	_jitter = (status & U.ST_PARALYZE) != 0
	_still = (status & STILL_MASK) != 0
	var was_bz := _berserk
	_berserk = (status & U.ST_BERSERK) != 0
	if _berserk and not was_bz:
		_bz_w = int(UiLayout.val("map.unit.status_tint", "berserk", {}).get("width_min", 0))   # SetEffect 效果 3: 宽度从 min 起、往上
		_bz_down = false
	_berserk_node(_berserk)
	_last_c = -1
	if not _jitter:
		_jit_off = 0
		_unit.anim.position.x = _base_x
	if _still:
		_unit.anim.playing = false   # 麻痹 / 冰結: 跳过人物换帧, 敌我都定在当前帧
	elif was_still and _unit.alive and _unit.shown:
		_unit.anim.playing = true
	set_process(_any())


## 麻痹摇晃一步 (在每 3 tick = 0.12 秒一次的状态外观块里; 计数 字段 每次清 0 所以每次都走): r1 / r2 = rand()%2。
## r1 = 1: 换到另一边 (原来 -1 → +1, 原来 0 或 +1 → -1); r1 = 0: 偏着就回中, 在中间就随机去一边 (r2 = 1 → -1, 0 → +1)。
## 所以每 0.12 秒都在动、从不停在原位, 看上去是左右摇晃 (以前复刻每 0.12 秒在 -1/0/+1 里均匀取, 常停住不动, 不像摇晃)
static func jitter_step(off: int, r1: int, r2: int) -> int:
	if r1 == 1:
		return 1 if off == -1 else -1
	if off != 0:
		return 0
	return -1 if r2 == 1 else 1


func _any() -> bool:
	return _still or _berserk or _entries.any(func(en): return en.active)


## 狂暴光晕节点: 开 = 建一份人物帧拷贝套光晕材质 (画在人物之上、上层叠层之下), 关 = 删掉
func _berserk_node(on: bool) -> void:
	if not on:
		if _bz_player != null:
			_bz_player.queue_free()
			_bz_player = null
		return
	if _bz_player != null:
		return
	var b: Dictionary = UiLayout.val("map.unit.status_tint", "berserk", {})
	_bz_mat = ShaderMaterial.new()
	_bz_mat.shader = BERSERK_SHADER
	var c := _rgb555(b.get("col", "0x7c00"))
	_bz_mat.set_shader_parameter("col", Vector3(c.r, c.g, c.b))
	_bz_mat.set_shader_parameter("col_k", _w(b.get("col_k", 6)))
	_bz_mat.set_shader_parameter("dst_keep", _w(b.get("dst_keep", 12)))
	_bz_player = _player_script.new()
	_bz_player.play_sound = false
	_bz_player.set_status_material(_bz_mat)
	add_child(_bz_player)
	_sync_berserk()


## 光晕拷贝跟着人物: 同一帧、同一位置 (含麻痹偏移); 放大量按贴图倍数换算 (高清 6 倍时 1 原版像素 = 6 贴图像素)
func _sync_berserk() -> void:
	var a = _unit.anim
	if a.data.is_empty() or a.frame < 0:
		return
	if _bz_player.dir != a.dir or _bz_player.frame != a.frame:
		_bz_player.show_frame(a.dir, a.frame)
	_bz_player.position = a.position - position
	_bz_player.visible = a.visible
	for sp in a.get_children():
		if sp is Sprite2D and sp.visible and sp.scale.x > 0.0:
			_bz_mat.set_shader_parameter("px_per_orig", 1.0 / sp.scale.x)
			break


func _process(delta: float) -> void:
	if _still:
		_unit.anim.playing = false   # 期间别的地方 (阶段开始的 shade / 播站立) 又开了动画也压回去
	if _bz_player != null:
		_sync_berserk()
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
		var k := (c - int(en.start)) % period
		en.player.show_frame(_dir, int(d["base"]) + k)
		var front := int(d.get("front", -1))   # 前后各半: 计数器 < front 画在贴图前, 其余在贴图后
		var layer := String(d.get("layer", "above"))
		en.player.z_index = (1 if k < front else -1) if layer == "split" else (1 if layer == "above" else -1)
	if _jitter:   # 和叠层同一个节拍: 原版状态外观块每 3 tick 走一次 (字段 倒数, 重装值 字段 = 2, 初始化)
		_jit_off = jitter_step(_jit_off, randi() % 2, randi() % 2)
		_unit.anim.position.x = _base_x + float(_jit_off)
	if _berserk:
		var b: Dictionary = UiLayout.val("map.unit.status_tint", "berserk", {})
		_bz_mat.set_shader_parameter("width", float(_bz_w))   # 这一拍画当前宽度, 再走一步 (原版先画后在下一块更新)
		var r := berserk_step(_bz_w, _bz_down, int(b.get("width_min", 0)), int(b.get("width_max", 6)), int(b.get("width_step", 2)))
		_bz_w = r[0]
		_bz_down = r[1]

# SPDX-License-Identifier: GPL-3.0-only
class_name CastFx
extends RefCounted
## 地图施法演出表 (内容包 fx/cast.json): 镜头、压暗、施法光效、法术名横幅动作、各类技能的演出动画与放置约定。
## 放置规则统一由 FxPlace 处理; 这里只把「哪段动画、按哪个约定、锚在谁身上」从数据里解析出来。
## 技能记录可带 "fx": {anim, convention, anchor, hide_caster, hide_caster_on_self} 覆盖 skill 段 (新技能只加数据, 不改脚本)。

const DEFAULT := {
	"camera": {"center": true, "speed": [750, 600], "return": true, "return_speed": [375, 300]},
	"dim": {"alpha": 0.6875},
	"aura": {"anim": "", "start": 1, "end": 18, "convention": "fx", "anchor": "caster"},
	"banner": {"element": "map.cast_banner", "hold_ticks": 37,
		"in": {"dy": [-16, -16, -8, -4, -2, 0], "alpha16": [4, 6, 8, 10, 12, 14]},
		"out": {"dy": [0, 0, 2, 4, 8, 16], "alpha16": [12, 10, 8, 6, 4, 2]}},
	"skill": {"default": {"anim": "", "convention": "fx", "anchor": "target", "hide_caster": false},
		"battle_type": {}},
	"result": {"anim": "", "convention": "unit", "anchor": "unit"},
	"movie": {"path": "", "skip": ["cancel"]},
}

static var _cfg := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = DEFAULT.duplicate(true)
		_cfg["aura"]["anim"] = ThemeAssets.p("fx.magic_misc")  # 动画名来自资源清单 (ui_theme/assets.json), 演出表可再覆盖
		_cfg["result"]["anim"] = ThemeAssets.p("battle.result_fx")
		_cfg["skill"]["default"]["anim"] = ThemeAssets.p("fx.skill_anim")
		var d = FxPlace.content_json("fx/cast.json")
		if d is Dictionary:
			for k in d:
				_cfg[k] = d[k]
	return _cfg


static func reload() -> void:
	_cfg.clear()


static func section(name: String) -> Dictionary:
	return cfg().get(name, {})


## 技能的地图演出: {anim (动画目录), convention, anchor, hide_caster}。spr = 施法者精灵号
static func for_skill(sk: Dictionary, spr: int) -> Dictionary:
	var s: Dictionary = section("skill")
	var out: Dictionary = s.get("default", {}).duplicate()
	var bt := str(int(sk.get("battle_type", -1)))
	var by: Dictionary = s.get("battle_type", {})
	# battle_type 只对绝技 (物理) 有意义: 原版施放入口 先看 skill+0 —— 咒术 (0) 一律走 放 Magic/M<animation_id>,
	# battle_type 完全被忽略; 绝技才按 分近景 / 地图 S / SM。妖氛鬼雾 (88)、幽都玄华 (89)、剑雄/剑雌/灵鼩召唤 (95~97) 是 battle_type=1 的咒术,
	# 复刻原先也按它改播施法者的 NNNs (差异)
	if by.has(bt) and int(sk.get("move_attack_type", 0)) != 0:
		out.merge(by[bt], true)
	if sk.get("fx") is Dictionary:
		out.merge(sk["fx"], true)
	out["anim"] = fill(String(out.get("anim", "")), sk, spr)
	# 技能记录 has_movie (Mag_dat 字段): 落点镜头到位后、法术动画之前先放一段全屏视频 (演出表 movie 段给路径与可跳过的键)
	var mv: Dictionary = section("movie")
	if bool(sk.get("has_movie", false)) and not out.has("movie"):
		out["movie"] = fill(String(mv.get("path", "")), sk, spr)
	out["movie_skip"] = out.get("movie_skip", mv.get("skip", ["cancel"]))
	return out


## 动画路径占位: {anim} {anim3} {spr3} {bspr}
static func fill(tpl: String, sk: Dictionary, spr: int) -> String:
	var anim := int(sk.get("animation_id", 0))
	var bspr := int(sk.get("battle_sprite", 0))
	return tpl.replace("{anim3}", "%03d" % anim).replace("{anim}", str(anim)) \
		.replace("{spr3}", "%03d" % spr).replace("{bspr}", ("-%d" % bspr) if bspr > 0 else "")


## 按施放方向分 4 段的演出动画 (原版仅 004-2SM / 005-1sm / 007-1sm: 帧数 = 4 x action_counts[0], 如韩千秀双环映月月牙) 只放对应那一段 [起, 止);
## 其它动画 (0, -1) = 整段。实测 (2026-10-29, 韩千秀双环映月向上/右/下/左各放一遍, 与 007-1sm 各段按亮部形状比对, 相似度 0.97~1.0): 段号 上 0 / 右 1 / 下 2 / 左 3
static func direction_segment(anim_data: Dictionary, variant: int) -> Vector2i:
	if anim_data.is_empty() or variant < 0 or variant > 3:
		return Vector2i(0, -1)
	var c0 := int(anim_data.get("action_counts", [0])[0])
	if c0 > 0 and anim_data["frames"].size() == 4 * c0:
		return Vector2i(variant * c0, variant * c0 + c0)
	return Vector2i(0, -1)


## 施放方向 (施放者格 c -> 落点格 t) 的段号: 上 0 / 右 1 / 下 2 / 左 3; 同一格 (射程 0) 用 own (施放者当前朝向的段号, 见 variant_of_dir)
static func direction_variant(c: Vector2i, t: Vector2i, own := 2) -> int:
	var d := t - c
	if d == Vector2i.ZERO:
		return own
	if absi(d.y) > absi(d.x):
		return 2 if d.y > 0 else 0
	return 1 if d.x > 0 else 3


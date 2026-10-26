# SPDX-License-Identifier: GPL-3.0-only
class_name UiProfile
extends Node2D
## 體態觀覽 (素材 Misc/Man_pro + Misc/Camp_man), 只读。坐标与原版截图核对:
##   左页 第 0 帧在 (28,16), 右页 第 1 帧 (抗性) / 第 2 帧 (物品、法术) 在 (177,16)。
##   打开时左页自左、右页自右滑入 16,8,4,2,0。
##   确认: 右页在 抗性 → 物品 → 法术 间循环, 换页时右页滑出再滑入; ←/→ 换人 (循环); 取消退出。
##   左页 (页内坐标, 起):
##     人名 (5,11) 红色 0x6080 + 光边; 数字用 Man_pro 第 3 帧字模 (8x7, 步进 7, 空格画空白格);
##     位 %3d (75,13); 歷 %3d (75,26); 移 %2d (17,26), 其后 " 0" (40,26);
##     體 %4d (17,42)/(50,42), 体力条 (18,39) 长 76 高 2 (色); 術 %4d (16,54)/(49,54), 术力条 (18,51) (色);
##     攻 (22,64) 防 (22,76) 咒 (69,64) 行 (69,76) 運 (113,76), 均 %3d;
##     五魂 k=0..4: 柱 x=19+28k, y=87, 帧 = 4 + min(9,(值−1)/10), 值 ≤ 0 不画; 数值 %3d 竖排 (步进 6) 在 (25+28k,108)。
##     人物: Misc/Camp_man, 帧 = 之前各人动作帧数之和 + 当前帧, 每 3 tick 前进; 贴在页内 (−38,−66) + 帧内偏移。
##   右页:
##     抗性页: 攻 (22,10) 防 (22,20) 命中 (79,10) 回避 (79,20) %4d; 六系抗性条 (18, 32+15k) 高 3, 长 min(90, |值|×0.9),
##       正值色、负值; 抗性值 %4d 在 (79, 37+15k)。
##     物品页: 10 行 y = 11+15k: 类型图标 第 28~31 帧在 (14,y), 名字 (28,y) 红色, 装备标记 第 32/33/34 帧在 (89,y)。
##     法术页: 行 y = 10+15k: 名字 (6,y+1), 图标 第 35 帧在 (68,y), 术力 %3d (84,y)、移动消耗 %3d (84,y+7)。
##   左右箭头: 第 36~39 / 40~43 帧, 每 5 tick 换帧, 在 (18,92) / (293,92); 两人以上才显示。
## 以上坐标、帧号、数值条色表都在布局表 camp.profile.* (行序号 k); 战场单位详情 (BattleUnitDetail) 共用同一套元素。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal closed

const AttrNames = preload("res://engine/rules/attr_names.gd")

## 非主角单位的战场小人放在页内的位置: 与主角 Camp_man 立绘的身体部件左上角对齐 (实测 Camp_man 身体部件在页内 (105,16), 战场小人部件自带的相对偏移是 0)
const SPRITE_POS := Vector2(-36, -67)


## 战场单位站立动画 (南向) 的帧范围 [起, 止): 同 BattleUnit.play_act(STAND, SOUTH)
static func stand_range(anim_dir: String) -> Vector2i:
	var data := Assets.anim(anim_dir)
	var c: Array = data["action_counts"]
	var stand := int(c[0])
	var win := int(c[4])
	var base := 2 + (win if win > 0 else 1)
	var size := stand if stand > 0 else 1
	return Vector2i(base, base + size)


## Camp_man 各人 (下标 = 单位号) 的动作帧数: 布局表 camp.profile.portrait.frames; 没有数据 = 不画立绘
static func man_frames() -> Array:
	var f = UiLayout.val("camp.profile.portrait", "frames", [])
	return f.map(func(x): return int(x)) if f is Array else []

var uids: Array = []
var who := 0
var page := 0
var _left: Node2D
var _right: Node2D
var _man: UiPanel
var _sprite: UiPanel   # 非主角单位 (怪物 / NPC) 没有 Camp_man 立绘: 战场详情里循环播放它自己的战场站立动画
var _man_base := 0
var _man_cyc := CampUi.Cycle.new(3, 1)
var _arrow_l: UiPanel
var _arrow_r: UiPanel
var _arrow_cyc := CampUi.Cycle.new(5, 4)


func _init(party: Array) -> void:
	uids = party
	_left = Node2D.new()
	add_child(_left)
	_right = Node2D.new()
	add_child(_right)
	_arrow_l = UiLayout.panel("camp.profile.arrow_left")
	_arrow_r = UiLayout.panel("camp.profile.arrow_right")
	add_child(_arrow_l)
	add_child(_arrow_r)
	_arrow_l.visible = uids.size() > 1
	_arrow_r.visible = uids.size() > 1
	_build()


func open() -> void:
	UiSlide.run(_left, UiLayout.at("camp.profile.left"), Vector2.LEFT, CampUi.SLIDE, true)
	UiSlide.run(_right, UiLayout.at("camp.profile.right"), Vector2.RIGHT, CampUi.SLIDE, true)


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _num(parent: Node, id: String, v: Variant, i := 0, vars := {}) -> void:
	parent.add_child(UiLayout.number(id, v, i, vars))


## 数值条: 布局元素的 pos、size (长 x 高)、bar.colors (RGB555 渐变表); neg = 用 bar.colors_neg
func _bar(parent: Node, id: String, length: int, i := 0, neg := false) -> void:
	var spec: Dictionary = UiLayout.val(id, "bar", {})
	var cols: Array = (spec.get("colors_neg", []) if neg else spec.get("colors", [])).map(func(c): return String(c).hex_to_int())
	var b := CampUi.Bar.new(cols, UiLayout.at(id, i), int(UiLayout.size_of(id).y))
	b.length = length
	parent.add_child(UiLayout.tag(b, id, Rect2(Vector2.ZERO, UiLayout.size_of(id))))


## 面板底图 (位置由调用方的页节点给, 底图在页内 (0,0))
static func _bg(id: String, which := 0) -> UiPanel:
	var p := UiLayout.panel(id, 0, {"which": which})
	p.position = Vector2.ZERO
	return p


func _build() -> void:
	_build_left()
	_build_right()


## 一个人的显示数据 (子类可覆盖, 如战场单位详情 engine/battle/ui/battle_unit_detail.gd):
##   name lv exp move hp hp_max mp mp_max stats{str vit int avg luk} spirit{名: 值} calc{attack defence hit evade res[6]}
##   items[] gear{weapon armor accessory} skills[] man (Camp_man 人物序号, −1 不画)
func unit_data(uid: int) -> Dictionary:
	var g: Dictionary = gc.state.party_of(uid)
	return {"name": CampInventory.unit_name(uid), "lv": int(g.get("lv", 1)), "exp": int(g.get("exp", 0)),
		"move": UiUnitStats.calc(uid)["move"], "hp": int(g.get("hp_max", 0)), "hp_max": int(g.get("hp_max", 0)),
		"mp": int(g.get("mp_max", 0)), "mp_max": int(g.get("mp_max", 0)), "stats": g.get("stats", {}),
		"spirit": g.get("spirit", {}), "calc": UiUnitStats.calc(uid), "items": CampInventory.unit_items(uid),
		"gear": CampInventory.gear_of(uid), "skills": g.get("skills", []), "man": uid if uid < man_frames().size() else -1}


func _build_left() -> void:
	_clear(_left)
	_left.position = UiLayout.at("camp.profile.left")
	var d := unit_data(uids[who])
	var st: Dictionary = d["stats"]
	_left.add_child(_bg("camp.profile.left"))
	var mi: int = d["man"]
	_man = null
	if mi >= 0:
		_man_base = 0
		var frames := man_frames()
		for k in mi:
			_man_base += int(frames[k])
		_man_cyc = CampUi.Cycle.new(3, int(frames[mi]))
		_man = UiLayout.panel("camp.profile.portrait")
		_man.set_frame(_man.anim_dir, _man_base)
		_left.add_child(_man)
		_fix_shadow()
	_sprite = null
	var sd := String(d.get("sprite_dir", ""))
	if mi < 0 and sd != "":   # 怪物: 站立动画 (南向) 循环, 比如夜魑会吐舌头
		_sprite = UiPanel.new("", 0, SPRITE_POS)
		_left.add_child(_sprite)
		var rg := stand_range(sd)
		_sprite.play(sd, rg.x, rg.y, true)
	_left.add_child(UiText.make("camp.profile.name", String(d["name"])))
	_num(_left, "camp.profile.lv_exp", int(d["lv"]), 0)
	_num(_left, "camp.profile.lv_exp", int(d["exp"]), 1)
	_num(_left, "camp.profile.move", int(d["move"]), 0)
	_num(_left, "camp.profile.move", " 0", 1)
	var hp := int(d["hp_max"])
	var mp := int(d["mp_max"])
	_num(_left, "camp.profile.hp", int(d["hp"]), 0)
	_num(_left, "camp.profile.hp", hp, 1)
	_num(_left, "camp.profile.mp", int(d["mp"]), 0)
	_num(_left, "camp.profile.mp", mp, 1)
	var hl := int(UiLayout.size_of("camp.profile.hp_bar").x)
	var ml := int(UiLayout.size_of("camp.profile.mp_bar").x)
	_bar(_left, "camp.profile.hp_bar", (hl * int(d["hp"]) / hp) if hp > 0 else 0)
	_bar(_left, "camp.profile.mp_bar", (ml * int(d["mp"]) / mp) if mp > 0 else 0)
	for k in AttrNames.STAT_DISPLAY.size():
		_num(_left, "camp.profile.stats", int(st.get(AttrNames.STAT_DISPLAY[k], 0)), k)
	var sp: Dictionary = d["spirit"]
	for k in 5:
		var v := int(sp.get(CampSpirit.NAMES[k], 0))
		if v > 0:
			var b := UiLayout.panel("camp.profile.spirit_bar", k)
			b.set_frame(b.anim_dir, b.frame + mini(9, (v - 1) / 10))
			_left.add_child(b)
		_num(_left, "camp.profile.spirit_value", v, k)


func _build_right() -> void:
	_clear(_right)
	_right.position = UiLayout.at("camp.profile.right")
	var d := unit_data(uids[who])
	_right.add_child(_bg("camp.profile.right", 0 if page == 0 else 1))
	match page:
		0:
			var cs: Dictionary = d["calc"]
			var heads := ["attack", "defence", "hit", "evade"]
			for k in heads.size():
				_num(_right, "camp.profile.res.head", cs[heads[k]], k)
			var full := UiLayout.size_of("camp.profile.res.bar").x
			var per := UiLayout.num("camp.profile.res.bar", "per_point", 0.9)
			for k in 6:
				var v: int = cs["res"][k]
				_bar(_right, "camp.profile.res.bar", mini(int(full), int(round(absf(v) * per))), k, v < 0)
				_num(_right, "camp.profile.res.value", v, k)
		1:
			var items: Array = d["items"]
			var gear: Dictionary = d["gear"]
			for k in mini(_rows("camp.profile.item.name"), items.size()):
				var it := CampInventory.item(items[k])
				var ic := UiLayout.panel("camp.profile.item.icon", k)
				ic.set_frame(ic.anim_dir, ic.frame + clampi(int(it["type"]), 0, 3))
				_right.add_child(ic)
				_right.add_child(UiText.make("camp.profile.item.name", String(it["name"]), k))
				for s in 3:
					var gv = gear.get(CampInventory.SLOT_KEYS[s])
					if gv != null and int(gv) == items[k] and items.find(items[k]) == k:
						var eq := UiLayout.panel("camp.profile.item.equip", k)
						eq.set_frame(eq.anim_dir, eq.frame + s)
						_right.add_child(eq)
		2:
			var skills: Array = d["skills"]
			for k in mini(_rows("camp.profile.spell.name"), skills.size()):
				var s: Dictionary = Content.skill_at(int(skills[k]))
				_right.add_child(UiText.make("camp.profile.spell.name", String(s["name"]), k))
				_right.add_child(UiLayout.panel("camp.profile.spell.icon", k))
				_num(_right, "camp.profile.spell.cost", int(s.get("mp_cost", 0)), k, {"iy": 0})
				_num(_right, "camp.profile.spell.cost", int(s.get("move_cost", 0)), k, {"iy": 1})


static func _rows(id: String) -> int:
	return int(UiLayout.val(id, "repeat", {}).get("count", 10))


## Camp_man 每帧第一个部件是脚下阴影 (type 1, p8=8, p10=0); 原版按半透明画 (截图核对), AnimPlayer 只在 p10=16 时才用 p8 做透明度
func _fix_shadow() -> void:
	for c in _man.get_children():
		if c is AnimPlayer and not c._sprites.is_empty():
			c._sprites[0].modulate.a = 0.5


func _process(delta: float) -> void:
	if _man and _man_cyc.step(delta):
		_man.set_frame(_man.anim_dir, _man_base + _man_cyc.phase)
		_fix_shadow()
	if _arrow_cyc.step(delta):
		_arrow_l.set_frame(_arrow_l.anim_dir, UiLayout.frame("camp.profile.arrow_left") + _arrow_cyc.phase)
		_arrow_r.set_frame(_arrow_r.anim_dir, UiLayout.frame("camp.profile.arrow_right") + _arrow_cyc.phase)


## 指针 (engine/ui/ui_hit.gd): 点左右箭头 = 换人 (同 ←/→), 点右页 = 翻页 (同确认)
func ui_hits() -> Array:
	var out: Array = []
	if uids.size() > 1:
		var g := UiLayout.num("camp.profile.hit.arrow", "grow", 3)
		out.append(UiHit.area(UiPanel.frame_rect(_arrow_l.anim_dir, _arrow_l.frame).grow(g), null, _arrow_l, UiAction.LEFT))
		out.append(UiHit.area(UiPanel.frame_rect(_arrow_r.anim_dir, _arrow_r.frame).grow(g), null, _arrow_r, UiAction.RIGHT))
	var rb: UiPanel = _right.get_child(0)
	out.append(UiHit.area(UiPanel.frame_rect(rb.anim_dir, rb.frame), null, _right))
	return out


## 按住 ←/→ 换人的连发间隔: 换人后整页重画动画做完才再读键 (实测 15 帧 = 0.6 秒)
const SWITCH_REPEAT := 15 * 0.04


func repeat_interval(kind: int) -> float:
	return SWITCH_REPEAT if kind in [UiAction.LEFT, UiAction.RIGHT] else KeyRepeat.REPEAT


func key(k: String) -> void:
	match k:
		"left", "right":
			if uids.size() > 1:
				who = posmod(who + (1 if k == "right" else -1), uids.size())
				_build()
				open()
		"accept":
			page = (page + 1) % 3
			_build_right()
			UiSlide.run(_right, UiLayout.at("camp.profile.right"), Vector2.RIGHT, CampUi.SLIDE, true)
		"cancel":
			closed.emit()

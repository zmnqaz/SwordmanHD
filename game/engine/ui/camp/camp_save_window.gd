# SPDX-License-Identifier: GPL-3.0-only
class_name CampSaveWindow
extends Node2D
## 今況記入 / 前歷再續 存读档窗 (素材 Misc/Sfman), 坐标与原版截图核对:
##   背景 第 0 帧在 (0,0); 标题框 第 1 帧在 (3,5), 标题文字在 (20,10) flags=5。
##   5 个档位条: x=3, y=30+33i; 有记录用第 2 帧 (头像画在帧里), 空档位第 3 帧。
##   条内: 关名 (152,4) flags=5; 等级 %3d 用第 4 帧字模在 (125,14); 「MM/DD HH:MM」在 (112,21), 空格只占位不画。
##   选中条: 叠加蓝色 (0x001F) 并按 2,4,…,16,…,4 每 2 tick 一档呼吸; 读档时空档位泛白。
##   打开时全屏由黑渐亮, 档位条单数行从左、双数行从右滑入 16,8,4,2,0。
## 按键: ↑/← 减 1、↓/→ 加 1, 5 个档位循环; 取消返回 −1;
##   确认: 读档时空档位无反应; 存档到空档位直接存; 其余在 (270, 42+33·sel) 弹是/否框, 默认✗。
## 坐标、帧号取布局表 camp.save.* (档位序号 i; 档位条帧 which 0 有记录 / 1 空)。标题「前历再续」也用这个窗。

signal picked(slot: int)


var saving := false
var sel := 0
var _bars: Array[Node2D] = []
var _hl: Array = []
var _hl_mat: ShaderMaterial
var _ask: CampAsk.YesNo
var _info: Array = []
var _t := 0.0
var _slots := 5  # 档位数 (布局表 camp.save.slot repeat.count)

static var _shader: Shader


func _init(is_save: bool) -> void:
	saving = is_save
	GameSaves.sync_mirror()   # Android: 玩家往镜像目录换进来的存档在打开读档窗时导入
	_slots = int(UiLayout.val("camp.save.slot", "repeat", {}).get("count", _slots))
	add_child(UiLayout.panel("camp.save.bg"))
	add_child(UiLayout.panel("camp.save.title_box"))
	ScreenLayout.mirror_edges(self, 0)  # 整页底图铺满安全区: 宽屏两侧只镜像底图 (在存档条之前画), 不露出下面的场景
	add_child(UiText.make("camp.save.title", UiStrings.t("camp.menu.item.4" if saving else "camp.menu.item.5")))
	for i in _slots:
		var info := slot_info(i)
		_info.append(info)
		var bar := Node2D.new()
		var p := UiLayout.panel("camp.save.slot", i, {"which": 0 if not info.is_empty() else 1})
		bar.position = p.position
		p.position = Vector2.ZERO
		bar.add_child(p)
		_hl.append(p)
		if not info.is_empty():
			bar.add_child(UiText.make("camp.save.slot.title", info["title"]))
			bar.add_child(UiLayout.number("camp.save.slot.lv", int(info["lv"])))
			bar.add_child(UiLayout.number("camp.save.slot.time", String(info["time"])))
		elif not saving:
			CampUi.set_material_deep(p, _wash_material())
		add_child(bar)
		_bars.append(bar)
	_select(0)


func open() -> void:
	modulate = Color.BLACK
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, CampUi.TICK * 14)
	for i in _slots:
		UiSlide.run(_bars[i], UiLayout.at("camp.save.slot", i), Vector2.LEFT if i % 2 == 0 else Vector2.RIGHT, CampUi.SLIDE, true)


## 复刻版存档摘要: {"title": 关名, "lv": 殷剑平等级, "time": "MM/DD HH:MM"}, 空档位返回 {}
static func slot_info(i: int) -> Dictionary:
	var path: String = GameSaves.slot_path(i)
	var r: Dictionary = SaveFile.load_file(path, "game")  # 原子写入/.bak 回退/版本迁移
	if r.missing:
		return {}
	if not r.ok:  # 损坏或版本不符: 档位显示提示, 读取时 Game.load_game 会拒绝
		return {"title": r.error, "lv": 0, "time": ""}
	var d: Dictionary = r.data
	if GameSaves.check_content(d.get("content")).level == "error":  # 缺内容包/版本不兼容: 读取时会拒绝并说明
		return {"title": UiStrings.t("camp.save.incompat"), "lv": 0, "time": ""}
	var n := int(d.get("stage", 0))
	var title := Content.stage_name(n).replace("  ", " ")
	if title == "":
		title = UiStrings.t("camp.save.stage", [n])
	var lv := 0
	var party: Dictionary = d.get("party", {})
	if party.has("0"):
		lv = int(party["0"].get("lv", 0))
	else:
		for k in party:
			lv = maxi(lv, int(party[k].get("lv", 0)))
	var t := String(d.get("time", ""))   # YYYY-MM-DD HH:MM:SS
	if t == "" and FileAccess.file_exists(path):   # 旧存档没记时间: 用文件修改时间 (本地时区)
		var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		t = Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path) + bias, true)
	var time := ""
	if t.length() >= 16:
		time = "%s/%s %s" % [t.substr(5, 2), t.substr(8, 2), t.substr(11, 5)]
	return {"title": title, "lv": lv, "time": time}


func _wash_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _get_shader()
	m.set_shader_parameter("tint", Color(1, 1, 1))
	m.set_shader_parameter("amount", 2.0 / 14.0)
	m.set_shader_parameter("mix_mode", 1)
	return m


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type canvas_item;
uniform vec4 tint : source_color;
uniform float amount;
uniform int mix_mode;  // 0 叠加 (加色), 1 混合
void fragment() {
	vec4 c = COLOR;  // Godot 4: fragment 里 COLOR 已是贴图色 × 顶点色
	if (mix_mode == 0) c.rgb = min(c.rgb + tint.rgb * amount, vec3(1.0));
	else c.rgb = mix(c.rgb, tint.rgb, amount);
	COLOR = c;
}"""
	return _shader


func _select(i: int) -> void:
	if _hl_mat == null:
		_hl_mat = ShaderMaterial.new()
		_hl_mat.shader = _get_shader()
		_hl_mat.set_shader_parameter("tint", Color(0, 0, 1))
		_hl_mat.set_shader_parameter("mix_mode", 0)
		_hl_mat.set_shader_parameter("amount", 0.0)
	CampUi.set_material_deep(_hl[sel], _wash_material() if (not saving and _info[sel].is_empty()) else null)
	sel = i
	CampUi.set_material_deep(_hl[sel], _hl_mat)
	_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	# 2,4,…,16,…,4 共 14 档, 每 2 tick 一档
	var step := int(_t / (CampUi.TICK * 2)) % 14
	var lv := 2 + 2 * step if step < 8 else 16 - 2 * (step - 7)
	_hl_mat.set_shader_parameter("amount", lv / 16.0)


## 指针 (engine/ui/ui_hit.gd): 5 个档位条; 是/否框打开时交给它
func ui_pointer_target() -> Object:
	return _ask if _ask else self


func ui_hits() -> Array:
	var out: Array = []
	for i in _slots:
		var p: UiPanel = _hl[i]
		out.append(UiHit.area(UiPanel.frame_rect(p.anim_dir, p.frame), i, _bars[i]))
	return out


func ui_select(i) -> void:
	if i != sel:
		_select(i)


func key(k: String) -> void:
	if _ask:
		_ask.key(k)
		return
	match k:
		"up", "left":
			_select(posmod(sel - 1, _slots))
		"down", "right":
			_select(posmod(sel + 1, _slots))
		"cancel":
			picked.emit(-1)
		"accept":
			var empty: bool = _info[sel].is_empty()
			if not saving and empty:
				return
			if saving and empty:
				picked.emit(sel)
				return
			_ask = CampAsk.YesNo.make("camp.save.yesno", {"s": sel})
			add_child(_ask)
			_ask.done.connect(_on_ask)


func _on_ask(yes: bool) -> void:
	_ask.queue_free()
	_ask = null
	if yes:
		picked.emit(sel)

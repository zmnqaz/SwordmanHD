# SPDX-License-Identifier: GPL-3.0-only
class_name UiLayout
extends RefCounted
## 布局服务: 读内容包的界面布局表 ui_theme/layout.json (格式与规则、§3)。
## 界面脚本只按元素 id 取坐标/尺寸/对齐/字体/颜色/锚点, 不在脚本里写数字; 换游戏或 mod = 换布局表。
##
## 叠加: 按内容包加载顺序 (Content.packs, 基础包在前、mod 在后) 逐包读 ui_theme/layout.json,
##   对象逐字段深合并 (后面的覆盖前面的同名字段, 没写的保留); 值写 null = 删除该字段 (元素写 null = 删除元素);
##   数组与标量整个替换。fonts / font_faces / colors / text_styles / motions / sprite_rules / elements 都按名字合并。
## 坐标: 原版像素 (320x200 安全区), 元素 pos 相对 parent 元素的左上角 (没有 parent 即相对锚点坐标系); abs_pos() 累加父链。
## 缺文件、缺元素时各取值函数返回调用方给的缺省值, 所以布局表可以逐步补全。
##
## 用法:
##   UiLayout.pos("dialog.box")                 -> Vector2(2, 137)
##   UiLayout.anchor("infobar.left")            -> ScreenLayout.Anchor.TOP_LEFT ("A|B" 二选一时取 which 项)
##   UiLayout.text("dialog.text")               -> {font, flags, color: Color, align, line_height, ...} (已解析颜色名)
##   UiLayout.color("text.main")                -> Color (RGB555 按 round(x*255/31) 换算)
## 测试或换包后 UiLayout.reload(); 也可 UiLayout.use(dict) 直接给一份布局 (单元测试)。

const FILE := "ui_theme/layout.json"
const ANCHORS := {"TOP_LEFT": 0, "TOP": 1, "TOP_RIGHT": 2, "LEFT": 3, "CENTER": 4, "RIGHT": 5,
	"BOTTOM_LEFT": 6, "BOTTOM": 7, "BOTTOM_RIGHT": 8, "STRETCH": 9}

static var _data := {}
static var _loaded := false
static var _colors := {}


## 合并后的整份布局表
static func data() -> Dictionary:
	if not _loaded:
		_load()
	return _data


static func reload() -> void:
	_loaded = false
	_missing = {}
	_exprs = {}
	_data = {}
	_colors = {}


## 直接指定布局 (测试用); null = 回到从内容包读取
static func use(d) -> void:
	reload()
	if d is Dictionary:
		_data = d
		_loaded = true


static func _content() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Content") if tree else null


static func _load() -> void:
	_loaded = true
	_data = {}
	_colors = {}
	var c := _content()
	if c == null:
		return
	if not c.reloaded.is_connected(reload):
		c.reloaded.connect(reload)
	_data = merge_dirs(c.pack_dirs())
	for w in warnings:
		push_warning("UiLayout: " + w)


## 后加载的包覆盖了前面没有的元素 (且没写 type, 多半是 id 拼错); merge_dirs 时填写
static var warnings: Array = []


## 按包目录顺序 (基础包在前) 合并各包的 ui_theme/layout.json
static func merge_dirs(dirs: Array) -> Dictionary:
	var out := {}
	warnings = []
	for dir in dirs:
		var d = ContentDB._read_json_file(String(dir).path_join(FILE))
		if not (d is Dictionary):
			continue
		if not out.is_empty():
			var els: Dictionary = out.get("elements", {})
			var over = d.get("elements", {})
			for id in (over if over is Dictionary else {}):
				if over[id] is Dictionary and not els.has(id) and not over[id].has("type"):
					warnings.append("%s 覆盖了不存在的元素 %s" % [String(dir).get_file(), id])
		out = merge(out, d)
	return out


## 布局深合并: 对象递归, null 删除字段, 其余 (数组、标量) 整个替换
static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for k in over:
		var v = over[k]
		if v == null:
			out.erase(k)
		elif out.get(k) is Dictionary and v is Dictionary:
			out[k] = merge(out[k], v)
		else:
			out[k] = v
	return out


# ---------------------------------------------------------------- 元素

static func has(id: String) -> bool:
	return data().get("elements", {}).has(id)


## 元素记录 (没有返回 {}, 并警告一次: 代码引用了布局表里没有的元素, 多半是漏写或拼错)
static func el(id: String) -> Dictionary:
	var e = data().get("elements", {}).get(id)
	if e is Dictionary:
		return e
	if not _missing.has(id) and not data().is_empty():
		_missing[id] = true
		push_warning("UiLayout: 布局表没有元素 " + id)
	return {}


static var _missing := {}


## 元素字段 (没有返回 def)
static func val(id: String, key: String, def = null):
	var v = el(id).get(key)
	return def if v == null else v


static func _vec(v, def: Vector2) -> Vector2:
	if v is Array and v.size() >= 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
		return Vector2(int(v[0]), int(v[1]))
	return def


## 元素 pos (相对父元素, 原版整数像素)。which: "A|B" 写法 (如信息条上/下) 取第几项; 公式 (字符串) 项返回 def 的对应分量
static func pos(id: String, def := Vector2.ZERO, which := 0) -> Vector2:
	var p = el(id).get("pos")
	if not (p is Array) or p.size() < 2:
		return def
	var out := def
	for ax in 2:
		var v = p[ax]
		if v is String and "|" in v:
			var parts: PackedStringArray = v.split("|")
			v = parts[clampi(which, 0, parts.size() - 1)]
			if v.is_valid_int():
				v = int(v)
		if v is float or v is int:
			out[ax] = int(v)
	return out


## 父链累加后的位置 (相对最外层元素所在坐标系)
static func abs_pos(id: String, def := Vector2.ZERO, which := 0) -> Vector2:
	var p := pos(id, def, which)
	var parent := String(el(id).get("parent", ""))
	var guard := 0
	while parent != "" and parent != id and has(parent) and guard < 16:
		p += pos(parent, Vector2.ZERO, which)
		parent = String(el(parent).get("parent", ""))
		guard += 1
	return p


static func size(id: String, def := Vector2.ZERO) -> Vector2:
	return _vec(el(id).get("size"), def)


## 等距重复的步进 repeat.step (没有返回 def)
static func step(id: String, def := Vector2.ZERO) -> Vector2:
	var r = el(id).get("repeat")
	return _vec(r.get("step"), def) if r is Dictionary else def


## 锚点 (ScreenLayout.Anchor); "A|B" 时取 which 项; 没写返回 def
static func anchor(id: String, def := 4, which := 0) -> int:
	var a = el(id).get("anchor")
	if not (a is String) or a == "":
		return def
	var parts: PackedStringArray = a.split("|")
	return int(ANCHORS.get(parts[clampi(which, 0, parts.size() - 1)], def))


## 贴图字段 {anim, frame, ...} (没有返回 def); anim 写资源清单的逻辑名 (见 asset) 时换成资源名
static func sprite(id: String, def := {}) -> Dictionary:
	var s = el(id).get("sprite")
	if not (s is Dictionary):
		return def
	var out: Dictionary = def.duplicate()
	out.merge(s, true)
	if out.has("anim"):
		out["anim"] = asset(out["anim"])
	return out


## 数字字段 (digits) 合并缺省值; anim 同 sprite 按资源清单解析
static func digits(id: String, def := {}) -> Dictionary:
	var out: Dictionary = def.duplicate()
	var d = el(id).get("digits")
	if d is Dictionary:
		out.merge(d, true)
	if out.has("anim"):
		out["anim"] = asset(out["anim"])
	return out


## 布局表里的素材名: 不含 "/" 且在资源清单 (ui_theme/assets.json, ThemeAssets) 里的是逻辑名, 换成资源名;
## 其余 (直接写的资源名) 原样返回。这样换皮/mod 只改资源清单, 布局表与代码共用同一份素材命名。
static func asset(a) -> Variant:
	if a is String and not a.contains("/") and ThemeAssets.has(a):
		return ThemeAssets.p(a)
	return a


## 文字规格: 元素 text 字段 + 字体 (fonts[font]) 的 size/line_height/cell 缺省; color 解析成 Color
static func text(id: String, def := {}) -> Dictionary:
	var out := {"font": "body", "flags": 0, "color": "text.main", "align": "left"}
	out.merge(def, true)
	var t = el(id).get("text")
	if t is Dictionary:
		out.merge(t, true)
	var f := font(String(out["font"]))
	for k in ["size", "line_height", "cell", "half_width"]:
		if not out.has(k) and f.has(k):
			out[k] = f[k]
	out["color"] = color(out["color"], UiText.BROWN)
	return out


## 给节点标上布局元素 id (校对工具 UiDebugOverlay 据此画元素框); rect = 节点局部坐标里的外框 (文字自动算)
static func tag(n: Node, id: String, rect := Rect2()) -> Node:
	n.set_meta("ui_layout_id", id)
	if rect.size != Vector2.ZERO:
		n.set_meta("ui_layout_rect", rect)
	return n


## 给面板 (UiPanel) 标 id, 外框 = 帧外框
static func tag_panel(p: UiPanel, id: String) -> UiPanel:
	return tag(p, id, UiPanel.frame_rect(p.anim_dir, p.frame)) as UiPanel


# ---------------------------------------------------------------- 取位置 (序号 / 公式) 与按表建节点
# 界面脚本只写「哪个元素、第几个、数据是什么」, 坐标一律从这里取。

## 元素第 i 个 (repeat 的序号, 或多列/多行表的下标) 的位置, 相对父元素。pos 支持:
##   [x, y]                    固定; 有 repeat.step 时 + step*i
##   ["A|B", ...]              二选一, 取 vars.which 项 (如信息条上/下)
##   [[x0, x1, ...], y]        多列 (取第 i 列); [x, [y0, y1, ...]] 多行; 两者都是表时 vars.ix / vars.iy 分别选列、行
##   [[x, y], [x, y], ...]     点表 (取第 i 个; 每项都是二元数组即按点表解释)
##   "7+28*k" 等字符串公式     Expression 求值, 变量 i、k (= i) 与 vars (w h n cx ... 由调用方给); 整数运算 = C 整除
## 只有当 pos 本身不随序号变化时才加 repeat.step*i。
static func at(id: String, i := 0, vars := {}) -> Vector2:
	var e := el(id)
	var p = e.get("pos")
	var out := Vector2.ZERO
	var indexed := false
	if p is Array and not vars.has("w") and e.get("sprite") is Dictionary and p.any(func(v): return v is String):
		vars = sprite_vars(id, vars)
	if p is Array and not p.is_empty() and p.all(func(q): return q is Array and q.size() == 2):
		var q = p[clampi(i, 0, p.size() - 1)]
		return Vector2(_num(q[0], i, vars), _num(q[1], i, vars))
	if p is Array and p.size() >= 2:
		for ax in 2:
			var v = p[ax]
			if v is Array:
				var vi := int(vars.get("ix" if ax == 0 else "iy", i))  # 二维表: vars.ix 选列、vars.iy 选行 (缺省都 = i)
				v = v[clampi(vi, 0, v.size() - 1)] if not v.is_empty() else 0
				indexed = true
			elif v is String and not (v.contains("|") and v.split("|")[0].is_valid_float()):
				indexed = true
			out[ax] = _num(v, i, vars)
	if not indexed and i != 0:
		out += step(id) * i
	return out


## 公式变量 w/h = 元素贴图帧的外框大小 (原版 1 倍, UiPanel.frame_rect)
static func sprite_vars(id: String, vars := {}) -> Dictionary:
	var out := vars.duplicate()
	var sp := sprite(id)
	if sp.has("anim"):
		var r := UiPanel.frame_rect(String(sp["anim"]), frame(id, int(vars.get("which", 0))))
		out["w"] = int(r.size.x)
		out["h"] = int(r.size.y)
	return out


## at() 再累加父链 (父元素取各自第 0 个; vars.parent_i 指定父元素的序号)
static func abs_at(id: String, i := 0, vars := {}) -> Vector2:
	var p := at(id, i, vars)
	var parent := String(el(id).get("parent", "")) if el(id).get("parent") is String else ""
	var guard := 0
	while parent != "" and has(parent) and guard < 16:
		p += at(parent, int(vars.get("parent_i", 0)), vars)
		parent = String(el(parent).get("parent", "")) if el(parent).get("parent") is String else ""
		guard += 1
	return p


## 外框 Rect2(at(), size)
static func rect(id: String, i := 0, vars := {}) -> Rect2:
	return Rect2(at(id, i, vars), size_of(id, vars))


## size 字段 (支持公式, 如 [160, "44+20*n"])
static func size_of(id: String, vars := {}) -> Vector2:
	var s = el(id).get("size")
	if s is Array and s.size() >= 2:
		return Vector2(_num(s[0], 0, vars), _num(s[1], 0, vars))
	if s is float or s is int:
		return Vector2(s, s)
	return Vector2.ZERO


## 数值字段 (支持公式); 没有返回 def
static func num(id: String, key: String, def := 0.0, vars := {}) -> float:
	var v = el(id).get(key)
	return def if v == null else _num(v, int(vars.get("i", 0)), vars)


## 二维字段 [a, b] (项可为公式, 变量 vars) -> Vector2; 没有返回 def
static func vec_of(id: String, key: String, vars := {}, def := Vector2.ZERO) -> Vector2:
	var v = el(id).get(key)
	if v is Array and v.size() >= 2:
		return Vector2(_num(v[0], 0, vars), _num(v[1], 0, vars))
	return def


## 原版画面 (安全区) 大小: 布局表 base_size (缺省 320x200)。界面代码用它代替写死的 320/200
static func base_size() -> Vector2:
	return _vec(data().get("base_size"), Vector2(320, 200))


## 二维字段 [a, b] -> Vector2; 没有返回 def
static func vec(id: String, key: String, def := Vector2.ZERO) -> Vector2:
	return _vec(el(id).get(key), def)


## 贴图帧号: sprite.frame 为数字, 或 "2|3" 二选一 (取 which 项)
static func frame(id: String, which := 0) -> int:
	var f = sprite(id).get("frame", 0)
	if f is String:
		var parts: PackedStringArray = f.split("|")
		f = parts[clampi(which, 0, parts.size() - 1)].strip_edges()
		return int(f) if String(f).is_valid_int() else 0
	return int(f)


## 数字格式 "%4d" 的宽度 (digits.fmt; 没有返回 def)
static func fmt_width(id: String, def := 0) -> int:
	var f = digits(id).get("fmt")
	if f is String:
		var m: String = f.trim_prefix("%").trim_suffix("d")
		if m.is_valid_int():
			return int(m)
	return def


## 建面板: sprite 的素材与帧 (which 选 "A|B" 帧), 放在 at(id, i, vars), 标上 id
static func panel(id: String, i := 0, vars := {}) -> UiPanel:
	var p := UiPanel.new(String(sprite(id).get("anim", "")), frame(id, int(vars.get("which", 0))), at(id, i, vars))
	return tag_panel(p, id)


## 建文字 (UiText.make 的简写)
static func label(id: String, t := "", i := 0, vars := {}) -> UiText:
	return UiText.make(id, t, i, vars)


## 建字模数字: digits {anim, frame, step, space, vertical}; v 为整数时按 fmt (%Nd) 右对齐
static func number(id: String, v: Variant = "", i := 0, vars := {}) -> UiNumber:
	var d := digits(id)
	var fr = d.get("frame", 0)
	if fr is String:
		var parts: PackedStringArray = fr.split("|")
		fr = int(parts[clampi(int(vars.get("which", 0)), 0, parts.size() - 1)])
	var s := str(v)
	if v is int or v is float:  # %Nd 右对齐补空格, %0Nd 补零
		s = str(int(v)).pad_zeros(fmt_width(id, 1)) if String(d.get("fmt", "")).begins_with("%0") else CampUi.fmt(int(v), fmt_width(id, 1))
	var n := UiNumber.new(String(d.get("anim", "")), int(fr), s, at(id, i, vars), String(d.get("space", "blank")),
		bool(d.get("vertical", false)))
	if d.has("step"):
		n.step = int(d["step"])
	if d.has("qmark"):
		n.qmark = int(d["qmark"])
	var w := fmt_width(id, s.length())
	var st := n.step if n.step > 0 else (6 if n.vertical else 7)
	var cw := UiNumber.W
	var ch := UiNumber.H
	tag(n, id, Rect2(0, 0, cw, st * w + 1) if n.vertical else Rect2(0, 0, st * w + 1, ch))  # 字模格 8x7
	return n


static var _exprs := {}


## 数字或公式字符串求值 (C 整除: 整数相除向零取整)。"A|B" 取 vars.which 项
static func _num(v, i: int, vars: Dictionary) -> float:
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if not (v is String):
		return 0.0
	var s: String = v.strip_edges()
	if s.contains("|"):
		var parts := s.split("|")
		s = parts[clampi(int(vars.get("which", 0)), 0, parts.size() - 1)].strip_edges()
	if s.is_valid_int() or s.is_valid_float():
		return float(s)
	var names := PackedStringArray(["i", "k"])
	var values := [i, i]
	for k in vars:
		if k is String and (vars[k] is int or vars[k] is float):
			names.append(k)
			values.append(vars[k])
	var key := s + "#" + ",".join(names)
	var ex: Expression = _exprs.get(key)
	if ex == null:
		ex = Expression.new()
		if ex.parse(s, names) != OK:
			push_warning("UiLayout: 公式 %s 解析失败: %s" % [s, ex.get_error_text()])
			return 0.0
		_exprs[key] = ex
	var r = ex.execute(values, null, false)
	if ex.has_execute_failed() or not (r is int or r is float):
		push_warning("UiLayout: 公式 %s 缺变量 (给了 %s)" % [s, names])
		return 0.0
	return float(r)


# ---------------------------------------------------------------- 全局表

## 字体规格 fonts[name] (cell/size/line_height/half_width)
static func font(name: String) -> Dictionary:
	var f = data().get("fonts", {}).get(name)
	return f if f is Dictionary else {"cell": [12, 12], "size": 12, "line_height": 13, "half_width": 6}


## 字体外观 font_faces[name] (baseline_in_cell 等, 见 UiText)
static func face(name: String) -> Dictionary:
	var f = data().get("font_faces", {}).get(name)
	return f if f is Dictionary else {}


## 文字样式 text_styles[flags] 的绘制列表 [[dx, dy, 颜色名或 "color"], ...]
static func style(flags) -> Array:
	var s = data().get("text_styles", {}).get(style_key(flags))
	if s is Dictionary and s.get("draws") is Array:
		return s["draws"]
	return [[0, 0, "color"]]


## 样式键: JSON 数字是 float, 5.0 -> "5"
static func style_key(flags) -> String:
	if (flags is float or flags is int) and float(flags) == floorf(float(flags)):
		return str(int(flags))
	return str(flags)


## 动效表 motions[name] (没有返回 def)
static func motion(name: String, def := {}) -> Dictionary:
	var m = data().get("motions", {}).get(name)
	return m if m is Dictionary else def


## 颜色: 颜色名 (colors 表, 或 type=color 的元素) / [r,g,b(,a)] (0~255, a 为 0~1) / "#rrggbb" / 0xRGB555 字符串 / Color
static func color(v, def := Color.WHITE) -> Color:
	if v is Color:
		return v
	if v is Array and v.size() >= 3:
		var is_unit: bool = v.all(func(x): return (x is float or x is int) and x <= 1.0) and v.size() >= 3
		var c := Color(v[0], v[1], v[2]) if is_unit else Color8(int(v[0]), int(v[1]), int(v[2]))
		if v.size() >= 4:
			c.a = float(v[3])
		return c
	if v is String:
		if v.begins_with("#"):
			return Color.html(v)
		if v.begins_with("0x"):
			return c555(v.hex_to_int())
		if _colors.has(v):
			return _colors[v]
		var c := _named(v, def)
		_colors[v] = c
		return c
	return def


static func _named(name: String, def: Color) -> Color:
	var e = data().get("colors", {}).get(name)
	if e == null:
		var el_color = el(name).get("color") if has(name) else null
		return color(el_color, def) if el_color != null else def
	if e is Dictionary:
		var r5 = e.get("rgb555")
		if r5 is String and r5.begins_with("0x"):
			return c555(r5.hex_to_int())
		if e.get("rgb") is Array and e["rgb"].size() >= 3 and not (e["rgb"][0] is Array):
			return color(e["rgb"], def)
		return def
	return color(e, def)


## RGB555 -> Color (round(x*255/31), 白 = 255; 全工程统一这一种换算, 与原版截图实测 0x59a5 = (181,107,41) 一致)
static func c555(v: int) -> Color:
	return Color8((((v >> 10) & 31) * 255 + 15) / 31, (((v >> 5) & 31) * 255 + 15) / 31, ((v & 31) * 255 + 15) / 31)


# ---------------------------------------------------------------- 校验

## 报告布局表的引用错误: 父元素/颜色/字体/样式不存在 (mod 拼错 id 多半在这里暴露)。返回错误文字列表
static var _LOGICAL := RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")


static func validate(d: Dictionary = {}) -> Array:
	if d.is_empty():
		d = data()
	var errs: Array = []
	var els: Dictionary = d.get("elements", {})
	var colors: Dictionary = d.get("colors", {})
	var fonts: Dictionary = d.get("fonts", {})
	var styles: Dictionary = d.get("text_styles", {})
	for id in els:
		var e = els[id]
		if not (e is Dictionary):
			continue
		var p := str(e.get("parent", "")) if e.get("parent") is String else ""
		if p != "" and not p.contains("*") and not els.has(p):
			errs.append("%s: 父元素 %s 不存在" % [id, p])
		var a = e.get("anchor")
		if a is String:
			for part in a.split("|"):
				if not ANCHORS.has(part):
					errs.append("%s: 锚点 %s 不认识" % [id, part])
		var t = e.get("text")
		if t is Dictionary:
			var fn := str(t.get("font", "body"))
			if not fonts.has(fn):
				errs.append("%s: 字体 %s 不存在" % [id, fn])
			var cn = t.get("color")
			if cn is String and not cn.begins_with("#") and not cn.begins_with("0x") and not colors.has(cn) and not els.has(cn):
				errs.append("%s: 颜色 %s 不存在" % [id, cn])
			if t.has("flags") and not styles.has(style_key(t["flags"])):
				errs.append("%s: 文字样式 %s 不存在" % [id, style_key(t["flags"])])
		for f in ["sprite", "digits"]:  # 素材逻辑名 (a.b 形式) 必须在资源清单里
			var an = e.get(f).get("anim") if e.get(f) is Dictionary else null
			if an is String and _LOGICAL.search(an) != null and not ThemeAssets.has(an):
				errs.append("%s: 素材逻辑名 %s 不在资源清单 ui_theme/assets.json" % [id, an])
	for sn in styles:
		var s = styles[sn]
		for dr in (s.get("draws", []) if s is Dictionary else []):
			if dr is Array and dr.size() >= 3 and str(dr[2]) != "color" and not colors.has(str(dr[2])):
				errs.append("text_styles.%s: 颜色 %s 不存在" % [sn, dr[2]])
	return errs

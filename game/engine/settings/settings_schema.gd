# SPDX-License-Identifier: GPL-3.0-only
class_name SettingsSchema
extends RefCounted
## 设定项定义 (F10 设定面板 engine/ui/settings_panel.gd 与 Game.settings 共用): 键、显示名、取值、说明、缺省值与校验。
## 新增设定只在 ROWS 里加一项 (并在 Game.apply_settings 里让它生效), 面板、持久化、还原预设自动跟上。
## 持久化: user://settings.json 里的同名键 (Game.save_settings 合并写入, 不动内容包等别的键); 文件里没有或非法的键取缺省值,
## 所以旧版设定文件 (只有 music/sfx/gfx/font) 直接兼容, 无需升 SaveFile.VERSION。
## 两层 (GameContext): settings_saved 持久层 (写盘的只有它) + settings_override 本次运行覆盖层 (命令行 --lang= 等、monkey; 不落盘),
##   gc.settings 是两层合并后的生效值, 读设定只看它。写设定一律走 set_value (校验 → 生效 → 存盘) / set_override / reset_all,
##   不要直接 gc.settings[k] = v (那样既不校验也不进持久层, 不会存盘)。
##
## kind: volume 0~10 整数 (左右 ±1, 到头停住) / choice 在 options 间循环 / action 没有值, 确认键打开子界面 (不进设定文件) /
##   live 值不在设定里、直接读写运行中的东西 (回放速度, 见 live_value / set_live, 不进设定文件)。
## needs: desktop = 只在电脑上列 (手机没有窗口大小可选); guide = 内容包带攻略才列; replaying = 回放中才列; idle_replay = 没在回放时才列; face_hk = 装了港漫头像 mod 才列。
## 非行的设定键: pad_map (手柄覆盖项 {动作名: 键号}, 稀疏, 由 PadMap.sanitize 校验); key_map (键盘覆盖项 {动作名: 键值}, 稀疏, 由 KeyMap.sanitize 校验)。
## options: [{v: 存储值}], 显示文字 t 取自文案表 (UiStrings, 内容包 text/ui.json): 行名 settings.<key>.label、行说明 settings.<key>.desc (面板下方, 选中项)、
##   选项文字 settings.<key>.opt.<v>; options_of 返回的选项带 t。options_from "fonts" 的选项 (t/d) 与缺省值来自字体清单 (UiFonts)。

const ROWS := [
	# 语言: 简体 / 繁体 (内容包 locale/hant 叠加层, 切换后进入下个画面生效; 设计 docs/设计_繁简切换.md)
	{"key": "lang", "kind": "choice", "def": "hans",
		"options": [{"v": "hans"}, {"v": "hant"}]},
	{"key": "font", "kind": "choice", "def": "", "options_from": "fonts"},
	# 游戏速度 (复刻新增): 整个游戏的节奏 1.0~5.0 倍, 1.0~2.0 每 0.1 一档、2.0 以上每 0.5 一档; 值是十分之一倍的整数 (10 = 原速), 实现见 engine/core/game_speed.gd
	{"key": "game_speed", "kind": "choice", "def": 10,
		"options": [{"v": 10}, {"v": 11}, {"v": 12}, {"v": 13}, {"v": 14}, {"v": 15}, {"v": 16}, {"v": 17}, {"v": 18}, {"v": 19}, {"v": 20}, {"v": 25}, {"v": 30}, {"v": 35}, {"v": 40}, {"v": 45}, {"v": 50}]},
	# 头像风格: 经典 (hd4x 里的 GenV3 放大) / 港漫 (可选 mod mod/face_hk.pck, 没有这个包不列这一行; 缺省港漫, 没装包时 Assets 自动回退经典)
	{"key": "face_style", "kind": "choice", "def": "hk", "needs": "face_hk",
		"options": [{"v": "classic"}, {"v": "hk"}]},
	# 声音 (2026-10-29 设定菜单按用户给的顺序重排): 音乐 / 音效收进二级菜单, 主菜单只留这一行
	{"key": "sound", "kind": "action"},
	{"key": "music", "kind": "volume", "def": 10, "group": "sound"},
	{"key": "sfx", "kind": "volume", "def": 10, "group": "sound"},
	{"key": "speed_10", "kind": "action", "group": "speed"},
	{"key": "speed_15", "kind": "action", "group": "speed"},
	{"key": "speed_20", "kind": "action", "group": "speed"},
	{"key": "speed_30", "kind": "action", "group": "speed"},
	{"key": "speed_40", "kind": "action", "group": "speed"},
	{"key": "speed_50", "kind": "action", "group": "speed"},
	{"key": "gfx", "kind": "choice", "def": "hd", "hidden": true,
		"options": [{"v": "hd"}, {"v": "orig"}]},
	# hidden = 不在设定面板里显示 (2026-10-07 用户嫌菜单太多): 数据与命令行参数仍保留, 值一律取缺省 (旧设定文件里存的也作废)。
	#   画质固定高清 (命令行 --gfx=orig 仍可临时切原版用于对照); 贴图倍数自动; 画面比例自适应
	{"key": "tex", "kind": "choice", "def": "auto", "hidden": true,
		"options": [{"v": "auto"}, {"v": "4"}, {"v": "6"}]},
	# 显示 (2026-10-29 用户嫌设定菜单项太多): 窗口模式 / 分辨率 / 画质诊断收进二级菜单, 主菜单只留这一行
	{"key": "display", "kind": "action"},
	{"key": "fullscreen", "kind": "choice", "def": 0, "group": "display",
		"options": [{"v": 0}, {"v": 1}]},
	{"key": "aspect", "kind": "choice", "def": "auto", "hidden": true,
		"options": [{"v": "auto"}, {"v": "keep"}]},
	# 分辨率 (窗口模式的窗口大小, 16:10): 0 = 自动 (缺省, 按屏幕可用区域挑最大的合适档, auto_win), 或手选 1280/1600/1920
	#   手机没有可摆放的窗口 (窗口大小 / 位置交给系统), 这行只在桌面列 (needs desktop)
	{"key": "win", "kind": "choice", "def": 0, "group": "display", "needs": "desktop",
		"options": [{"v": 0}, {"v": 1280}, {"v": 1600}, {"v": 1920}]},
	# 贴图精度: 像素画类贴图 (人物 / 物件 / 特效, 约 6.9 万张) 运行时生成的倍数, 0 自动 (电脑 6, 手机按屏幕选 3/4/6) / 6 高 / 4 中 / 3 低; 与窗口分辨率无关。
	#   生成器启动时就定倍数 (Assets.saved_hq_scale 读这个键), 改了要重启生效; 命令行 --hq-scale 优先。AI 类大图 (地图 / 头像) 固定用包里的 4 倍图, 不受它影响
	{"key": "hq", "kind": "choice", "def": 0, "group": "display",
		"options": [{"v": 0}, {"v": 6}, {"v": 4}, {"v": 3}]},
	# 控制器 (2026-10-29 用户嫌设定菜单项太多): 键盘 / 手柄的设置收进二级菜单, 主菜单只留这一行 (动作行 controls 打开同一个 SettingsPanel, 只列 group = controls 的行)
	{"key": "controls", "kind": "action"},
	# 键盘: 逐动作改主键 (动作行 key_edit 打开子面板, 覆盖项存 key_map, 见 engine/input/key_map.gd)
	{"key": "key_edit", "kind": "action", "group": "controls"},   # 手机 / 平板上也列: 安卓掌机的实体按键、蓝牙键盘上报的都是键盘按键 (2026-10-31)
	# 手柄: 预设 + 逐动作改键 (动作行 pad_edit 打开子面板, 覆盖项存 pad_map, 见 engine/input/pad_map.gd)
	{"key": "pad_preset", "kind": "choice", "def": "std", "group": "controls",
		"options": [{"v": "std"}, {"v": "swap"}]},
	{"key": "pad_edit", "kind": "action", "group": "controls"},
	# 战场辅助 (默认全关 = 与原版一致): 宝箱显示 (隐藏宝箱图标 + 宝箱内容提示) / 光标格坐标
	{"key": "show_hidden", "kind": "choice", "def": 0,
		"options": [{"v": 0}, {"v": 1}]},
	{"key": "coord", "kind": "choice", "def": 0,
		"options": [{"v": 0}, {"v": 1}]},
	# 录像回放 (复刻新增): 没在回放时列「录像回放」(打开 engine/ui/replay_panel.gd); 回放中改列「结束回放」和「回放速度」
	#   (live: 值取自运行中的回放, 左右调、立即生效, 不进设定文件)
	# 整理行囊 (原来是攻略面板里的按钮, 2026-10-25 搬到这里): 公共行囊按物品编号排 (CampInventory.resort_bag); 回放中不列 (整理会改行囊, 回放时不能插手)
	{"key": "bag_sort", "kind": "action", "needs": "idle_replay"},
	{"key": "replay", "kind": "action", "needs": "idle_replay"},
	{"key": "replay_stop", "kind": "action", "needs": "replaying"},
	{"key": "replay_speed", "kind": "live", "needs": "replaying"},
	# 攻略 (随时也可按 F4): 打开攻略面板 engine/ui/guide_panel.gd; needs guide = 内容包没有攻略 (guide/guide.json) 时不列
	{"key": "guide", "kind": "action", "needs": "guide"},
	# 画质诊断 (复刻新增, 2026-10-29): 屏幕 / 贴图倍数 / 生成器状态 / 显存 / 帧率, 手机上画面发糊时用 (engine/ui/diag_panel.gd)
	{"key": "diag", "kind": "action", "group": "display"},
	# 关于 (复刻新增): 版本号 + GitHub 地址 (engine/ui/about_panel.gd), 主菜单最后一行
	{"key": "about", "kind": "action"},
]
## 窗口大小档 (宽度, 即 win 的取值; 0 = 自动) 对应的 16:10 窗口像素
static func win_size(w: int) -> Vector2i:
	return Vector2i(w, w * 5 / 8)


## 自动选窗口大小档: 屏幕可用区域 (去掉任务栏) 放得下的最大档 (留出标题栏与边框), 都放不下用最小档 1280
static func auto_win(usable: Vector2i) -> int:
	for w in [1920, 1600, 1280]:
		var sz := win_size(w)
		if sz.x <= usable.x * 0.96 and sz.y <= usable.y * 0.9:
			return w
	return 1280


## 二级菜单里非行的设定键 (随该组「还原预设」一起复位): 组 -> [键]
## 「加速」菜单 (手机右上角加速钮, 见 TouchPad.SPEED): 一个只有档位行的二级菜单, 选一档 = 把 game_speed 设成它并关闭。
## 档位行不是主菜单入口, 也不算设定项 (action 行不存盘), 所以不进 GROUPS / all_shown_rows; 档位值必须是 game_speed 的合法选项。
const SPEED_GROUP := "speed"
const SPEED_PRESETS := [10, 15, 20, 30, 40, 50]
const GROUPS := ["sound", "display", "controls"]   # 二级菜单 (组名 = 主菜单入口行的键)
const GROUP_EXTRA := {"controls": ["pad_map", "key_map"], "display": [], "sound": []}


## 主菜单 + 全部二级菜单里显示的行 (测试 / 猴子测试用)
static func all_shown_rows() -> Array:
	var out := shown_rows()
	for g in GROUPS:
		out += shown_rows(g)
	return out


## 设定面板里显示的行 (去掉 hidden 的, 以及 needs 条件不满足的)。group: "" = 主菜单 (没有 group 的行 + 各二级菜单的入口行), 否则只列该组的行
static func shown_rows(group := "") -> Array:
	var has_guide := GuideBook.available(GameContext.current().content)
	var replaying := PlayLog.replaying()
	var has_face_hk: bool = Assets.face_alt_available()
	return ROWS.filter(func(r): return String(r.get("group", "")) == group and not r.get("hidden", false) and _need_ok(String(r.get("needs", "")), has_guide, replaying, has_face_hk))


static func _need_ok(need: String, has_guide: bool, replaying: bool, has_face_hk := false) -> bool:
	match need:
		"face_hk": return has_face_hk
		"guide": return has_guide
		"replaying": return replaying
		"idle_replay": return not replaying
		"desktop": return not Platform.is_mobile()
	return true


## 没有存储值的行 (动作行 / live 行): 不进缺省值、不读写设定文件
static func _valueless(r: Dictionary) -> bool:
	return r["kind"] == "action" or r["kind"] == "live"


static func row(key: String) -> Dictionary:
	for r in ROWS:
		if r["key"] == key:
			return r
	return {}


## 一行的选项 (数据驱动的行从清单取)
static func options_of(r: Dictionary) -> Array:
	if r.get("options_from") == "fonts":
		return UiFonts.options()
	var out: Array = []
	for o in r.get("options", []):
		out.append(o.merged({"t": UiStrings.t("settings.%s.opt.%s" % [r["key"], str(o["v"])])}))
	return out


## 行名 / 行说明 (文案表)
static func label_of(r: Dictionary) -> String:
	return UiStrings.t("settings.%s.label" % r["key"])


static func row_desc(r: Dictionary) -> String:
	return UiStrings.t("settings.%s.desc" % r["key"])


static func def_of(r: Dictionary):
	return UiFonts.default_id() if r.get("options_from") == "fonts" else r["def"]


## 面板下方的说明: 行说明 + 当前选项自带的一句话
static func desc_of(key: String, v) -> String:
	var r := row(key)
	var s: String = row_desc(r)
	for o in options_of(r):
		if _same(o["v"], v) and o.get("d", "") != "":
			return s + " " + o["d"]
	return s


## 全部缺省值
static func defaults() -> Dictionary:
	var d := {}
	for r in ROWS:
		if not _valueless(r):
			d[r["key"]] = def_of(r)
	d["pad_map"] = {}
	d["key_map"] = {}
	return d


## 把任意来源的值 (设定文件) 校正成合法值: 缺的、类型不对的、取值不在选项里的取缺省值; 返回新字典 (不改传入的)
static func sanitize(src: Dictionary) -> Dictionary:
	var out := defaults()
	src = src.duplicate()
	for r in ROWS:
		var k: String = r["key"]
		if _valueless(r) or r.get("hidden", false) or not src.has(k):
			continue   # hidden 行不读设定文件里的值 (旧文件里的作废, 取缺省); 命令行要临时改它走覆盖层 (set_override / load_layers)
		var v = clean_value(k, src[k])
		if v != null:
			out[k] = v
	out["pad_map"] = PadMap.sanitize(out["pad_preset"], src.get("pad_map"))["map"]
	out["key_map"] = KeyMap.sanitize(src.get("key_map"))
	return out


## 单项校验: 合法返回规范值 (JSON 的 1.0 -> 1, 音量夹到 0~10), 非法 (未知键/类型不对/不在选项里) 返回 null。
## pad_map 按 preset (缺省 = 该键缺省预设) 校验成稀疏覆盖项。不看 hidden (命令行覆盖可以临时改隐藏项)
static func clean_value(key: String, v, preset = null):
	if key == "pad_map":
		return PadMap.sanitize(preset if preset != null else row("pad_preset")["def"], v)["map"]
	if key == "key_map":
		return KeyMap.sanitize(v)
	var r := row(key)
	if r.is_empty() or _valueless(r):
		return null
	if r["kind"] == "volume":
		return clampi(int(v), 0, 10) if (v is int or v is float) else null
	for o in (UiFonts.options(true) if r.get("options_from") == "fonts" else options_of(r)):   # 字体: 按清单全部校验 (限定语言的字体在别的语言下也保留已存的选择)
		if _same(o["v"], v):
			return o["v"]
	return null


# ---------------------------------------------------------------- 两层与写入入口 (gc: GameContext)

## 启动时装入: saved = 设定文件读出的字典 (sanitize), overrides = 命令行等临时值 (逐项校验, 非法的丢掉并告警); 不生效不存盘
static func load_layers(gc, saved: Dictionary, overrides: Dictionary) -> void:
	gc.settings_saved = sanitize(saved)
	gc.settings_override = {}
	for k in overrides:
		var v = clean_value(String(k), overrides[k], gc.settings_saved["pad_preset"])
		if v == null:
			push_warning("设定覆盖值非法, 已忽略: %s=%s" % [k, str(overrides[k])])
			continue
		gc.settings_override[k] = v
	gc.settings = effective(gc.settings_saved, gc.settings_override)


## 生效值 = 持久层上叠覆盖层 (新字典)
static func effective(saved: Dictionary, overrides: Dictionary) -> Dictionary:
	var out := saved.duplicate(true)
	out.merge(overrides.duplicate(true), true)
	return out


## 唯一的持久写入入口: 校验 → 写持久层 (并去掉该项的覆盖, 用户亲手改的以它为准) → 生效 → 存盘。非法值不改, 返回 false。
## 连带规则: 换手柄预设 = 清掉逐键自定义 pad_map。
static func set_value(gc, key: String, raw) -> bool:
	var v = clean_value(key, raw, gc.settings.get("pad_preset"))
	if v == null:
		push_warning("设定值非法, 未改: %s=%s" % [key, str(raw)])
		return false
	var preset_changed: bool = key == "pad_preset" and not _same(gc.settings.get(key), v)
	_put(gc, key, v)
	if preset_changed:
		_put(gc, "pad_map", {})
	gc.flow.apply_settings()
	gc.flow.save_settings()
	return true


## 本次运行的临时值 (monkey 等): 校验 → 写覆盖层 → 生效; 不存盘。非法值不改, 返回 false
static func set_override(gc, key: String, raw) -> bool:
	var v = clean_value(key, raw, gc.settings.get("pad_preset"))
	if v == null:
		return false
	gc.settings_override[key] = v
	gc.settings[key] = v
	gc.flow.apply_settings()
	return true


## 「还原预设」: 两层都回缺省 (覆盖层一并清掉), 生效并存盘
static func reset_all(gc) -> void:
	gc.settings_saved = defaults()
	gc.settings_override = {}
	gc.settings = defaults()
	gc.flow.apply_settings()
	gc.flow.save_settings()


## 二级菜单的「还原预设」: 只把该组的设定项 (和 GROUP_EXTRA 里的覆盖项) 恢复缺省, 不动别的
static func reset_group(gc, group: String) -> void:
	var d := defaults()
	if group == SPEED_GROUP:   # 加速菜单的「还原预设」= 回原速
		_put(gc, "game_speed", d["game_speed"])
	for r in ROWS:
		if String(r.get("group", "")) == group and not _valueless(r):
			_put(gc, String(r["key"]), d[r["key"]])
	for k in GROUP_EXTRA.get(group, []):
		_put(gc, String(k), d[k])
	gc.flow.apply_settings()
	gc.flow.save_settings()


## 音量开关 (战场系统菜单「声音」): 开着 -> 0 并记下原值; 关着 -> 恢复关之前的值, 没记过取缺省。经 set_value 存盘
static func toggle_volume(gc, key: String) -> void:
	var v := int(gc.settings[key])
	if v > 0:
		gc.volume_before_mute[key] = v
		set_value(gc, key, 0)
	else:
		set_value(gc, key, gc.volume_before_mute.get(key, def_of(row(key))))


static func _put(gc, key: String, v) -> void:
	gc.settings_saved[key] = v
	gc.settings_override.erase(key)
	gc.settings[key] = v


## JSON 读回来整数是 float: 数值按值比, 字符串与数值不混
static func _same(a, b) -> bool:
	if (a is String) != (b is String):
		return false
	return a == b


## 显示文字 (volume 返回数字)
static func text_of(key: String, v) -> String:
	var r := row(key)
	if r.get("kind") == "live":
		return PlayLog.speed_text(float(v))
	if r.get("kind") == "volume":
		return str(int(v))
	for o in options_of(r):
		if _same(o["v"], v):
			return o["t"]
	if r.get("options_from") == "fonts":   # 存的是当前语言下不可用的字体: 显示实际在用的缺省字体
		return String(UiFonts.get_or_default(str(v)).get("name", v))
	return str(v)


## choice 按 d (±1) 循环换一项; volume 加减并夹在 0~10。返回新值
static func step(key: String, v, d: int):
	var r := row(key)
	if r.get("kind") == "live":
		return PlayLog.step_speed(float(v), d)
	if r.get("kind") == "volume":
		return clampi(int(v) + d, 0, 10)
	var opts: Array = options_of(r)
	if opts.is_empty():
		return v
	var i := 0
	for j in opts.size():
		if _same(opts[j]["v"], v):
			i = j
	return opts[posmod(i + d, opts.size())]["v"]


## live 行的当前值 (回放速度取自运行中的回放; 没在回放返回 1.0)
static func live_value(key: String):
	if key == "replay_speed" and PlayLog.current != null:
		return PlayLog.current.speed
	return 1.0


## 写 live 行 (立即生效, 不存盘)
static func set_live(key: String, v) -> void:
	if key == "replay_speed":
		PlayLog.set_speed(float(v))

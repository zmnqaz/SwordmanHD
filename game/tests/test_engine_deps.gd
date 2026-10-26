# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 引擎对 autoload 的依赖闸门 (docs/架构设计.md「引擎与 autoload 的边界」):
##   1. engine/ 里不得出现 Game. / Autotest (组装层 scripts/ 才能用; 引擎经 GameContext 取状态与场景流转, 调试帧号读 RegressLog.log_frame);
##   2. engine/rules 与 engine/script 完全不碰任何 autoload, 可在无场景树下实例化;
##   3. 其余 autoload (Assets/Content/ScreenLayout/InputRouter/ResPacks) 的引用数只减不增 (CEILING), 清理后请把上限调低;
##   4. 按字符串取 autoload 节点 (get_node_or_null("Content") / get_node("/root/InputRouter") 等) 也是依赖, 存量登记在 NODE_ALLOW, 只减不增;
##   5. engine/ 不得引用组装层 scripts/ 里声明的 class_name (AnimPlayer、MovieScene...) 或 res://scripts/ 路径, 存量登记在 SCRIPTS_CLASS_ALLOW, 只减不增;
##   6. 命令行参数只在 engine/core/debug_args.gd 解析 (engine/ scripts/ 里别处不得调 OS.get_cmdline_user_args), 规则层不读 DebugArgs (开关由战场层注入)。
## 统计时去掉注释与字符串字面量 (第 4 条专看字符串)。

const FORBIDDEN := ["Game", "Autotest"]
## 白名单: 文件 -> 允许保留的 FORBIDDEN 名 (已清零, 新增须在此登记并写明理由)
const ALLOW := {}
const AUTOLOADS := ["Game", "Autotest", "Content", "Assets", "ScreenLayout", "InputRouter", "UserDirMigrate", "ResPacks"]
## 严格档: 这些目录不得引用任何 autoload (除下面 STRICT_ALLOW 登记的存量)
const STRICT_DIRS := ["res://engine/rules", "res://engine/script", "res://engine/core"]
## 严格档存量白名单 (文件 -> {autoload 名: 引用数}; 只减不增, 数量必须与当前值相等; 现已清零, core 经 GameContext.content 问内容包)
const STRICT_ALLOW := {}
## 当前 engine/ 内 (去注释/字符串后) 对各 autoload 的引用总数上限; 贴紧当前值, 只减不增, 清理后请调低
const CEILING := {"Assets": 72, "Content": 52, "ScreenLayout": 103, "InputRouter": 22, "ResPacks": 4}
## 按节点名/路径字符串取 autoload 的存量 (文件 -> {autoload 名: 处数}; 只减不增, 必须与当前值相等)。
## 这些多是为了避开严格档/全局名检查而按节点取 Content 的静态工具类; 新代码请经 GameContext 注入, 不要往这里加。
const NODE_ALLOW := {
	"res://engine/ui/ui_strings.gd": {"Content": 1},
	"res://engine/core/content_info.gd": {"Content": 1},
	"res://engine/ui/ui_fonts.gd": {"Content": 1},
	"res://engine/ui/theme_assets.gd": {"Content": 1},
	"res://engine/ui/ui_layout.gd": {"Content": 1},
	"res://engine/fx/fx_place.gd": {"Content": 1},
	"res://engine/render/assets.gd": {"Content": 1},
}
## engine/ 引用 scripts/ 里 class_name (或 res://scripts/ 路径) 的存量 (文件 -> 处数; 只减不增, 必须与当前值相等)。
## AnimPlayer / MovieScene 本该属于引擎层, 以后搬进 engine/ 后这里清零; 新增引用请先把被引用的类下沉到 engine/。
const SCRIPTS_CLASS_ALLOW := {
	"res://engine/battle/battle_scene.gd": 16,
	"res://engine/battle/battle_flow.gd": 1,
	"res://engine/battle/battle_unit.gd": 2,
	"res://engine/battle/battle_view.gd": 2,
	"res://engine/battle/battle_closeup.gd": 9,
	"res://engine/rpg/rpg_scene.gd": 5,
	"res://engine/fx/cutscene.gd": 2,
	"res://engine/ui/profile.gd": 1,
	"res://engine/ui/scene_show.gd": 4,
	"res://engine/ui/msg_box.gd": 7,
	"res://engine/ui/turn_banner.gd": 2,
	"res://engine/ui/panel.gd": 2,
	"res://engine/ui/choice_box.gd": 5,
}

## 层次规则 (只减不增): from 目录内不得出现 pattern 命名的符号; 存量登记在 allow (文件 -> 引用数, 必须相等)。
## 新增违例请改架构 (把被引用的组件下沉到 ui/ 或 rules/), 不要往 allow 里加。
const LAYER_RULES := [
	{
		"name": "battle 不依赖营地 UI 组件 (Camp*, ui/camp/)",
		"dir": "res://engine/battle",
		"pattern": "Camp[A-Z]\\w*",
		"path": "res://engine/ui/camp/",
		"allow": {},
	},
	{
		"name": "ui 不依赖 battle (Battle*, engine/battle/)",
		"dir": "res://engine/ui",
		"pattern": "Battle[A-Z]\\w*",
		"path": "res://engine/battle/",
		"allow": {},
	},
	{
		"name": "rules 不读命令行 (DebugArgs; 对照开关由战场层注入)",
		"dir": "res://engine/rules",
		"pattern": "DebugArgs|GameContext",
		"path": "res://engine/core/debug_args.gd",
		"allow": {},
	},
]

## 可以调 OS.get_cmdline_user_args() 的唯一文件
const CMDLINE_OWNER := "res://engine/core/debug_args.gd"


func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


## 去掉注释与字符串内容后的代码行
func _code(path: String, keep_strings := false) -> PackedStringArray:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var code := ""
		var q := ""
		var i := 0
		while i < line.length():
			var c := line[i]
			if q != "":
				if keep_strings:
					code += c
				if c == "\\":
					i += 1
					if keep_strings and i < line.length():
						code += line[i]
				elif c == q:
					q = ""
			elif c == "\"" or c == "'":
				q = c
				if keep_strings:
					code += c
			elif c == "#":
				break
			else:
				code += c
			i += 1
		out.append(code)
	return out


func _count(path: String, name: String) -> int:
	return _count_re(path, "(?<![\\w.])%s\\b" % name)


## 非注释代码里字符串字面量含 needle (preload("res://...") 这类按路径的引用) 的行数
func _count_path(path: String, needle: String) -> int:
	var n := 0
	for line in _code(path, true):
		if line.contains(needle):
			n += 1
	return n


func _count_re(path: String, pattern: String) -> int:
	var re := RegEx.create_from_string("(?<![\\w.])(?:%s)\\b" % pattern)
	var n := 0
	for line in _code(path):
		n += re.search_all(line).size()
	return n


func test_engine_has_no_game_or_autotest_reference():
	var files := []
	_scan("res://engine", files)
	check(files.size() > 100, "扫到引擎源文件 (%d)" % files.size())
	for f in files:
		for name in FORBIDDEN:
			var n := _count(f, name)
			var allowed: int = int(ALLOW.get(f, {}).get(name, 0))
			check(n <= allowed, "%s 引用了 %s %d 处 (引擎不得直接引用, 请经 GameContext; 白名单 %d)" % [f, name, n, allowed])


func test_strict_dirs_use_no_autoload():
	for d in STRICT_DIRS:
		var files := []
		_scan(d, files)
		check(files.size() >= 2, "%s 扫到文件" % d)
		for f in files:
			for name in AUTOLOADS:
				var n := _count(f, name)
				var allowed: int = int(STRICT_ALLOW.get(f, {}).get(name, 0))
				check(n <= allowed, "%s 引用了 autoload %s: 当前 %d 处, 白名单 %d (严格档, 请经 GameContext 注入)" % [f, name, n, allowed])
				check(n >= allowed, "%s 对 %s 的引用降到 %d 处, 白名单 %d 请同步收紧 (只减不增)" % [f, name, n, allowed])
	for f in STRICT_ALLOW:
		check(FileAccess.file_exists(f), "白名单文件存在: %s" % f)


func test_autoload_reference_ceiling():
	var files := []
	_scan("res://engine", files)
	for name in CEILING:
		var total := 0
		for f in files:
			total += _count(f, name)
		check(total <= int(CEILING[name]), "engine/ 对 %s 的引用: 当前 %d 处 / 上限 %d (只减不增, 超限请改架构)" % [name, total, CEILING[name]])


## 一个文件里按字符串取 autoload 节点的处数 (autoload 名 -> 处数): get_node / get_node_or_null / has_node 的参数是 "<名>" 或 "/root/<名>",
## 以及任何地方出现的 "/root/<名>" 字面量 ($"/root/X"、NodePath("/root/X") 等)
func _node_lookups(path: String) -> Dictionary:
	var names := "|".join(AUTOLOADS)
	var call := RegEx.create_from_string("\\b(?:get_node|get_node_or_null|has_node)\\s*\\(\\s*[\"'](?:/root/)?(%s)[\"']" % names)
	var root := RegEx.create_from_string("[\"']/root/(%s)[\"']" % names)
	var out := {}
	for line in _code(path, true):
		var hits := {}  # 结尾引号位置 -> 名 (get_node("/root/X") 两条规则都会命中, 按位置去重)
		for m in call.search_all(line) + root.search_all(line):
			hits[m.get_end()] = m.get_string(1)
		for k in hits:
			out[hits[k]] = int(out.get(hits[k], 0)) + 1
	return out


func test_autoload_node_lookup_by_string():
	var files := []
	_scan("res://engine", files)
	var total := 0
	for f in files:
		var got := _node_lookups(f)
		for name in AUTOLOADS:
			var n: int = int(got.get(name, 0))
			total += n
			var a: int = int(NODE_ALLOW.get(f, {}).get(name, 0))
			check(n <= a, "%s 按字符串取 autoload %s: 当前 %d 处 / 白名单 %d (这也是全局依赖, 请经 GameContext 注入)" % [f, name, n, a])
			check(n >= a, "%s 按字符串取 %s 降到 %d 处, 白名单 %d 请同步收紧 (只减不增)" % [f, name, n, a])
	check(total > 0, "能数到按字符串取 autoload (%d 处; 0 说明匹配失效)" % total)
	for f in NODE_ALLOW:
		check(FileAccess.file_exists(f), "白名单文件存在: %s" % f)


## scripts/ 里声明的 class_name (组装层的类)
func _scripts_classes() -> Array:
	var files := []
	_scan("res://scripts", files)
	var re := RegEx.create_from_string("^class_name\\s+(\\w+)")
	var out := []
	for f in files:
		for line in _code(f):
			var m := re.search(line)
			if m:
				out.append(m.get_string(1))
	return out


func test_engine_does_not_use_scripts_classes():
	var classes := _scripts_classes()
	check(classes.has("AnimPlayer") and classes.has("MovieScene"), "扫到 scripts/ 的 class_name: %s" % ", ".join(classes))
	var pattern := "|".join(classes)
	var files := []
	_scan("res://engine", files)
	for f in files:
		var n := _count_re(f, pattern) + _count_path(f, "res://scripts/")
		var a: int = int(SCRIPTS_CLASS_ALLOW.get(f, 0))
		check(n <= a, "engine/ 引用了组装层 scripts/ 的类: %s 当前 %d 处 / 白名单 %d (请把被引用的类下沉到 engine/)" % [f, n, a])
		check(n >= a, "%s 对 scripts/ 类的引用降到 %d 处, 白名单 %d 请同步收紧 (只减不增)" % [f, n, a])
	for f in SCRIPTS_CLASS_ALLOW:
		check(FileAccess.file_exists(f), "白名单文件存在: %s" % f)


func test_layer_rules():
	for rule in LAYER_RULES:
		var files := []
		_scan(rule["dir"], files)
		check(files.size() >= 2, "%s 扫到文件" % rule["dir"])
		var allow: Dictionary = rule["allow"]
		for f in files:
			var n := _count_re(f, rule["pattern"]) + _count_path(f, rule["path"])
			var a: int = int(allow.get(f, 0))
			check(n <= a, "层次违例「%s」: %s 当前 %d 处 / 白名单 %d" % [rule["name"], f, n, a])
			check(n >= a, "「%s」: %s 降到 %d 处, 白名单 %d 请同步收紧" % [rule["name"], f, n, a])
		for f in allow:
			check(FileAccess.file_exists(f), "白名单文件存在: %s" % f)


## rules 与 script 层无场景树、无 autoload 也能用: 解释器指令读写的是注入的 GameContext
func test_script_vm_runs_on_injected_context():
	var vm := RpgVM.new(null)
	var mine := GameContext.new()
	vm.gc = mine
	var d := PackedByteArray()
	d.resize(6)
	d.encode_s16(0, 5)
	d.encode_s32(2, 7)
	var before := GameContext.current().state.get_data(5)
	vm._ops[0x10].call(0x10, d)  # 设变量 5 = 7
	eq(mine.state.get_data(5), 7, "写进注入的上下文")
	eq(GameContext.current().state.get_data(5), before, "不碰全局上下文")
	vm.free()
	var ctx := Ctx.new()  # rules 层本来就不依赖任何全局
	check(ctx != null, "规则上下文可直接实例化")


func test_default_scene_flow_is_inert():
	var c := GameContext.new()
	check(not c.flow.load_game(0), "缺省流转: 读档无事发生")
	c.flow.goto_battle(3)
	c.flow.game_over()
	check(c.flow.is_current(null), "缺省流转 is_current 恒真")


## 6. 命令行只在 DebugArgs 解析一次
func test_cmdline_parsed_only_in_debug_args():
	var files := []
	for d in ["res://engine", "res://scripts"]:
		_scan(d, files)
	var bad := []
	for f in files:
		if f == CMDLINE_OWNER:
			check(_count_re(f, "OS\\.get_cmdline_user_args") == 1, "DebugArgs 里读一次命令行")
			continue
		var n := _count_re(f, "OS\\.get_cmdline_user_args|OS\\.get_cmdline_args")
		if n > 0:
			bad.append("%s (%d 处)" % [f, n])
	eq(bad, [], "读命令行请用 GameContext.debug / DebugArgs.current() 的字段")

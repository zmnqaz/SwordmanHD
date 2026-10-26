# SPDX-License-Identifier: GPL-3.0-only
class_name UiStrings
extends RefCounted
## 界面文案表 (内容包 text/ui.json, 扁平 {键: 文字}): 引擎里的界面文案 (设定面板、营地/标题菜单...) 从这里取, 不写死在脚本里,
## 内容包 (mod) 可以按键覆盖任意一条, 或随新游戏整套替换。
## 叠加: 按包加载顺序 (基础包在前) 逐键合并, 后者覆盖前者; 值写 null = 删除该键 (取不到按缺键处理)。
## 缺键返回键名本身并警告一次 (界面上直接看到键名, 比空白好查); 带参数的文案写 %s/%d, UiStrings.t(key, [args]) 按 % 格式化。
## 语言: 内容包的 locale/<lang>/text/ui.json 是该语言的叠加层 (Content.set_lang 切换, 见 docs/设计_繁简切换.md); 其余仍不是 tr() 式国际化。
## 键名约定: <界面>.<元素>[.<子项>], 例 settings.music.label、camp.menu.item.0、title.menu.item.2 (见 docs/内容格式.md「界面文案」)。
## 测试或换包后 UiStrings.reload(); 也可 UiStrings.use(dict) 直接给一份文案 (单元测试)。

const FILE := "text/ui.json"

static var _data := {}
static var _loaded := false
static var _missing := {}


static func reload() -> void:
	_loaded = false
	_missing = {}
	_data = {}


## 直接指定文案表 (测试用); null = 回到从内容包读取
static func use(d) -> void:
	reload()
	if d is Dictionary:
		_data = d
		_loaded = true


## 合并若干包目录里的 text/ui.json (测试直接传目录)
## lang 非空 (如 "hant") 时, 每个包的 text/ui.json 之后再合上该包的 locale/<lang>/text/ui.json (语言叠加层, 按键合并)
static func merge_dirs(dirs: Array, lang := "") -> Dictionary:
	var out := {}
	for dir in dirs:
		var files := [String(dir).path_join(FILE)]
		if lang != "":
			files.append(String(dir).path_join("locale").path_join(lang).path_join(FILE))
		for f in files:
			var d = ContentDB._read_json_file(f)
			if not (d is Dictionary):
				continue
			for k in d:
				if d[k] == null:
					out.erase(k)
				elif d[k] is String and not String(k).begins_with("_"):  # "_comment" 之类的说明键不进表
					out[k] = d[k]
	return out


static func _ensure() -> void:
	if _loaded:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var c: Node = tree.root.get_node_or_null("Content") if tree else null
	if c == null or c.packs.is_empty():
		return  # 内容包还没加载: 这次取键名, 不缓存
	if not c.reloaded.is_connected(reload):
		c.reloaded.connect(reload)
	_data = merge_dirs(c.pack_dirs(), String(c.lang))
	_loaded = true


static func has(key: String) -> bool:
	_ensure()
	return _data.has(key)


## 取文案; args 非空时按 % 格式化
static func t(key: String, args: Array = []) -> String:
	_ensure()
	var s = _data.get(key)
	if s == null:
		if _loaded and not _missing.has(key):
			_missing[key] = true
			push_warning("UiStrings: 文案表没有键 " + key)
		return key
	return String(s) % args if not args.is_empty() else String(s)

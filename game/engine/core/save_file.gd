# SPDX-License-Identifier: GPL-3.0-only
class_name SaveFile
extends RefCounted
## 存档文件读写 (存档位 saveN.json、战阵存录 battle.json、设置 settings.json), 纯静态, 不依赖场景。
##
## 原子写入: 先写 <文件>.tmp, 写成功后旧文件改名 <文件>.bak, 再把 .tmp 改名为正式文件。
## 读取: 正式文件缺失/损坏/解析失败时自动改读 .bak。
## 版本: 每个文件带 "version" (整数, 当前 VERSION); 读档时按版本依次跑 migrate_vN_to_vN+1,
##   没有 version 的旧档视为 v0。迁移失败返回 {"ok": false, "error": 提示文字}, 调用方提示玩家, 不崩溃。
## 存档 (kind "game"/"battle") 另带 "content": 内容包标识与版本 (Content.signature(): [{"id", "version"}])。

const VERSION := 2
const KINDS := ["game", "battle", "settings"]
const ItemRules = preload("res://engine/rules/items.gd")


# ---------------------------------------------------------------- 原子写入 / 带 .bak 回退的读取

## 原子写入 JSON, 成功返回 true。
## 临时文件名带进程号 (<文件>.tmp<pid>): 开两个游戏实例时不会互相写坏对方的临时文件 (以前共用 .tmp, 并发写同一存档约一半失败, 差异)。
## 改名那两步 (旧档 → .bak, 临时文件 → 正式) 被另一个实例抢先时重试几次; 读档侧 (read_json) 本来就会在正式文件暂时缺席时读 .bak。
static func write_json(path: String, data: Variant) -> bool:
	var tmp := "%s.tmp%d" % [path, OS.get_process_id()]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败: %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data))
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK or FileAccess.get_file_as_string(tmp).length() == 0:
		push_error("存档写入失败: %s (%s)" % [tmp, error_string(err)])
		DirAccess.remove_absolute(tmp)
		return false
	var bak := path + ".bak"
	for attempt in 8:
		if FileAccess.file_exists(path):
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			DirAccess.rename_absolute(path, bak)   # 失败 (被别的实例抢先改走) 不算错: 下面直接把临时文件放到正式位置
		if DirAccess.rename_absolute(tmp, path) == OK:
			return true
		OS.delay_msec(5 + attempt * 5)
	push_error("存档写入失败: 无法改名 " + tmp)
	DirAccess.remove_absolute(tmp)
	return false


## 正式文件或 .bak 存在
static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


## 读 JSON 字典: 正式文件不可用时读 .bak, 都不行返回 null
static func read_json(path: String) -> Variant:
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var j := JSON.new()  # 用实例解析: parse_string 对坏 JSON 会往日志打 ERROR, 而坏档是正常要处理的情形
		var d = j.data if j.parse(FileAccess.get_file_as_string(p)) == OK else null
		if d is Dictionary:
			if p != path:
				push_warning("存档 %s 损坏, 改用备份 %s" % [path, p])
			return d
	return null


# ---------------------------------------------------------------- 版本

## 给要写出的数据盖上版本与内容包标识 (原地修改并返回)
static func stamp(d: Dictionary, kind: String, content: Variant = null) -> Dictionary:
	d["version"] = VERSION
	if kind != "settings" and content != null:
		d["content"] = content
	return d


## 读 + 迁移: 返回 {"ok": bool, "data": Dictionary, "error": String, "missing": bool}
static func load_file(path: String, kind: String) -> Dictionary:
	if not exists(path):
		return {"ok": false, "data": {}, "error": "", "missing": true}
	var d = read_json(path)
	if d == null:
		return {"ok": false, "data": {}, "error": "存档损坏, 无法读取", "missing": false}
	var r := migrate(d, kind)
	r["missing"] = false
	return r


## 把任意版本的数据迁移到 VERSION: 返回 {"ok", "data", "error"}
static func migrate(d: Dictionary, kind: String) -> Dictionary:
	assert(kind in KINDS)
	var v := int(d["version"]) if (d.get("version") is int or d.get("version") is float) else 0
	if v > VERSION:
		return {"ok": false, "data": d, "error": "存档来自更新的版本 (v%d), 请升级游戏" % v}
	if v < VERSION:  # 旧档迁移前先查类型 (迁移代码会按字段类型读); 缺必需字段的由迁移自己给具体提示
		var g = d.get("game") if kind == "battle" else d
		if g is Dictionary and GameState.missing_field(g) == "":
			var pre := _validate(d, kind)
			if pre != "":
				return {"ok": false, "data": d, "error": pre}
	while v < VERSION:
		var fn := "migrate_v%d_to_v%d" % [v, v + 1]
		var m := SaveMigrations.new()
		if not m.has_method(fn):
			return {"ok": false, "data": d, "error": "缺少存档迁移 " + fn}
		var err: String = m.call(fn, d, kind)
		if err != "":
			return {"ok": false, "data": d, "error": err}
		v += 1
		d["version"] = v
	# 当前版本的存档也要查 (迁移里的校验只在旧档上跑): 先查必需字段齐全 (提示缺哪个), 再查各字段类型/取值合法, 不留给 apply_dict 半途出错
	var bad := _validate(d, kind)
	if bad != "":
		return {"ok": false, "data": d, "error": bad}
	return {"ok": true, "data": d, "error": ""}


## 结构校验 (类型错/缺字段的坏档当作损坏, 不让后面的读档与界面脚本报错): 先报缺哪个必需字段, 再按 GameState.SAVE_FIELDS 字段表查类型/取值。
## 字段表只在 GameState 一处; settings 不查 (缺省值由 Game.settings 补)
static func _validate(d: Dictionary, kind: String) -> String:
	var g: Variant = d
	match kind:
		"battle":
			if not (d.get("game") is Dictionary and d.get("battle") is Dictionary):
				return "存录损坏, 无法读取"
			g = d["game"]
		"game":
			pass
		_:
			return ""
	var k := GameState.missing_field(g)
	if k != "":
		return "存档缺少「%s」, 无法读取" % k
	return GameState.validate_dict(g)


## 各版本迁移: 原地修改 d, 成功返回 "", 失败返回提示文字。新版本在这里加 migrate_v1_to_v2 ...
class SaveMigrations:
	const DEFAULT_CONTENT := [{"id": ContentCompat.LEGACY_PACK_ID, "version": ""}]  # 没有 content 字段的旧档: 内容包机制之前只有原版包

	## v0: 规则接入 (b7d598be) 与内容包 (b4dd7352) 之前/之间写的存档, 没有 version
	static func migrate_v0_to_v1(d: Dictionary, kind: String) -> String:
		match kind:
			"settings":
				return ""  # 设置的缺省值由 Game.settings 补
			"game":
				return _game_v0(d)
			"battle":
				if not (d.get("game") is Dictionary and d.get("battle") is Dictionary):
					return "存录损坏, 无法读取"
				var e := _game_v0(d["game"])
				if e != "":
					return e
				# 规则接入前的单位快照是旧字段 (cx/cy/stats/gear/effects...), 没有 UnitState ("st"),
				# 状态效果、装备的表示都变了, 无法可靠转换
				var units = d["battle"].get("units", [])
				if not units is Array:
					return "存录损坏, 无法读取"
				for u in units:
					if not (u is Dictionary and u.has("st")):
						return "存录版本过旧"
				if not d.has("content"):
					d["content"] = d["game"]["content"]
				d["game"]["version"] = 1
				return ""
		return "未知存档类型"

	## v1 -> v2: 物品栏模型 (M5)。每个主角记录保证有 "items" (10 格, 装备占格): 旧档没有的按装备生成。
	## 公共行囊 bag 保留; 旧版主角初登场时把随身消耗品 (party_init 的初始物品除武器/护具) 倒进行囊, 迁移时按原版 (初始物品在本人 10 格,
	## KMAN_STA) 还回已登场主角的格子: 行囊里还有就拿出一件放回, 本人格子满了或行囊里已用掉的不补, 其余行囊物品不动
	static func migrate_v1_to_v2(d: Dictionary, kind: String) -> String:
		match kind:
			"settings":
				return ""
			"game":
				return _game_v2(d)
			"battle":
				if not d.get("game") is Dictionary:
					return "存录损坏, 无法读取"
				var e := _game_v2(d["game"])
				d["game"]["version"] = 2
				return e
		return "未知存档类型"

	static func _game_v2(d: Dictionary) -> String:
		var party = d.get("party")
		if not party is Dictionary:
			return "存档损坏, 无法读取"
		for k in party:
			var g = party[k]
			if g is Dictionary and not g.get("items") is Array:
				g["items"] = ItemRules.unit_slots([], g.get("gear", {}))
				if (d.get("seeded", []) as Array).has(int(k)) and d.get("bag") is Array:
					_return_initial_items(d["bag"], g, int(k))
		return ""

	## v1 行囊里属于该主角初始随身物品的消耗品还给本人 (initial_items 取内容包 party_init; 无内容包环境 (纯数据测试) 不动)
	static func _return_initial_items(bag: Array, g: Dictionary, uid: int) -> void:
		if not GameContext.current().content.is_hero(uid):
			return
		var gear: Dictionary = g.get("gear", {})
		for id in GameContext.current().content.party_init(uid).get("items", []):
			if id == null or int(id) < 0 or int(id) == _gid(gear, "weapon") or int(id) == _gid(gear, "armor"):
				continue
			var at: int = bag.find(int(id))
			if at >= 0 and g["items"].size() < 10:
				bag.remove_at(at)
				g["items"].append(int(id))

	static func _gid(gear: Dictionary, k: String) -> int:
		return int(gear[k]) if gear.get(k) != null else -1

	static func _game_v0(d: Dictionary) -> String:
		var miss := GameState.missing_field(d)
		if miss != "":
			return "存档缺少「%s」, 无法读取" % miss
		if not d.get("party") is Dictionary or not d.get("bag") is Array or not d.get("game_data") is Dictionary:
			return "存档损坏, 无法读取"
		if not d.has("seeded"):
			d["seeded"] = []
		if not d.has("where"):
			d["where"] = "camp"
		if not d.has("time"):
			d["time"] = ""
		if not d.has("content"):
			d["content"] = DEFAULT_CONTENT.duplicate(true)
		return ""

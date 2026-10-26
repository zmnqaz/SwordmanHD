# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 内容包加载层 (engine/content/content_db.gd)、.evs 编译 (engine/script/evs_compiler.gd)、改动包覆盖。
const REQUIRES_TEST := {
	"test_minimal_game_template": ["content"],
	"test_content_schema": ["content"],
	"test_evs_compile_matches_original": ["content"],
	"test_example_mod": ["content"],
	"test_example_mod_stage_loads": ["content"],
	"test_item_at_safe_lookup": ["content"],
	"test_load_base_pack": ["content"],
	"test_missing_stage_files_fall_back_to_title": ["content"],
	"test_mod_rules": ["content"],
	"test_unit_skill_at_safe_lookup": ["content"]
}  # 个别方法的依赖 (同上)

const ContentDBScript = preload("res://engine/content/content_db.gd")
const Evs = preload("res://engine/script/evs_compiler.gd")


func _db(ids: Array) -> Node:
	var db = ContentDBScript.new()
	db.load_packs(ids)
	return db


func _write(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(data if data is String else JSON.stringify(data))
	f.close()


func test_load_base_pack():
	var db = _db(["tdj"])
	eq(db.errors, [], "无加载错误")
	eq(db.packs.size(), 1)
	eq(db.stage_count(), 36)
	eq(db.town_count(), 27)
	eq(db.items().size(), 374)
	eq(db.units().size(), 116)
	eq(db.skills().size(), 106)
	eq(String(db.unit(0)["name"]), "殷剑平")
	eq(int(db.item(0)["price"]), 45)
	check(db.is_hero(9) and not db.is_hero(10), "我方角色 = party_init 表 (0~9)")
	eq(int(db.camp(3)["town"]), 2)
	eq(int(db.camp(32)["town"]), -1, "原版缺 CAMP32: 缺省直接下一关")
	eq(db.shop("town00.0")["items"].map(func(x): return int(x)), [0, 15, 45, 95])
	eq(db.stage_name(1), "第一幕  因缘")
	check(db.is_ending_movie(13) and not db.is_ending_movie(12), "结局过场来自 manifest")
	eq(db.params().to_dict(), Params.new().to_dict(), "原版包无 rules.json = 默认参数")
	eq(db.system_text("treasure").size() > 0, true)
	db.free()


## 63 个 .evs 编译结果与 events_raw.json (原版 COD 原样转存) 逐条逐字节相同
func test_evs_compile_matches_original():
	var db = _db(["tdj"])
	var n_ok := 0
	for kind in [["stages", "stage.json", db.stage_count()], ["towns", "town.json", db.town_count()]]:
		for n in kind[2]:
			var info: Dictionary = db.json("%s/%02d/%s" % [kind[0], n, kind[1]])
			var src := FileAccess.get_file_as_string(db.find(info["script"]["source"]))
			var r: Dictionary = Evs.compile(src, info["script"]["source"])
			if r.has("error"):
				check(false, String(r["error"]))
				continue
			var raw: Array = db.json(info["script"]["raw"])
			var same: bool = raw.size() == r["events"].size()
			for i in mini(raw.size(), r["events"].size()):
				same = same and raw[i].size() == r["events"][i].size()
				for j in mini(raw[i].size(), r["events"][i].size()):
					var c: Dictionary = r["events"][i][j]
					same = same and int(raw[i][j]["op"]) == c["type"] and String(raw[i][j]["data"]) == c["data"].hex_encode()
			check(same, "%s %02d 编译结果与原版不同" % [kind[0], n])
			n_ok += int(same)
	eq(n_ok, 63)
	db.free()


func test_evs_syntax():
	var r: Dictionary = Evs.compile("script battle\nevents 3\nevent 2\n  if_var var=9 cmp=gt value=0 goto=done\n  show ids=1,2\n"
		+ "  move_steps steps=3 speed=2 {\n    walk_dir unit=0 dir=2\n  }\n  say msg=1  # 注释\ndone:\n  return\n")
	check(not r.has("error"), str(r.get("error", "")))
	var ev: Array = r["events"][2]
	eq(ev.map(func(c): return c["type"]), [0x32, 0x0B, 0x01, 0x01, 0x10, 0x11, 0x16, 0x00])
	eq(ev[0]["data"].decode_s32(6), 7, "标签按展开后的指令序号")
	eq(ev[4]["data"].decode_s16(0), 1, "块的 count = 块内条数")
	eq(ev[6]["data"].decode_s16(0), -1, "省略的参数取默认值")
	check(Evs.compile("script battle\nevent 0\n  nosuch x=1\n").has("error"), "未知命令报错")
	check(Evs.compile("script town\nevent 0\n  say face=1\n").has("error"), "缺必填参数报错")


func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]):
				return false
		return true
	return a == b


func _same_events(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].size() != b[i].size():
			return false
		for j in a[i].size():
			if a[i][j]["type"] != b[i][j]["type"] or a[i][j]["data"] != b[i][j]["data"]:
				return false
	return true


## 示例改动包 game/content/example_mod: 单位属性、物品价格、规则参数覆盖生效, 其余不变
func test_example_mod():
	var base = _db(["tdj"])
	var db = _db(["tdj", "example_mod"])
	eq(db.errors, [])
	eq(db.packs.map(func(p): return p["id"]), ["tdj", "remake", "example_mod"], "加载顺序: 基础包在前 (example_mod 的 base remake 再以 tdj 为 base)")
	eq(int(db.unit(0)["move"]), 26, "殷剑平移动力 23 -> 26")
	eq(int(base.unit(0)["move"]), 23)
	eq(int(db.unit(0)["hp"]), int(base.unit(0)["hp"]), "没写的字段保持原版")
	eq(String(db.unit(0)["name"]), "殷剑平")
	eq(int(db.item(0)["price"]), 30, "长剑售价 45 -> 30")
	eq(db.items()[0]["price"], db.item(0)["price"], "下标数组与按键查询一致")
	eq(db.item(1), base.item(1), "其他物品不变")
	eq(db.items().size(), base.items().size())
	eq(db.params().turn_limit, 120, "rules.json 覆盖回合上限")
	eq(db.params().bag_capacity, base.params().bag_capacity)
	eq(db.stage_info(1), base.stage_info(1), "没改的关卡文件用基础包的")
	eq(db.signature(), [{"id": "tdj", "version": "1.3.0"}, {"id": "example_mod", "version": "0.1.0"}], "remake 是 save_neutral, 不进存档签名")
	base.free()
	db.free()

## 示例改动包带一整关 (stages/36: 地图 + 单位 + 剧情 .evs): 用 --mods=example_mod 的加载路径能载入并编译, 基础包没有这一关
## (真正打通该关见 tests/regress_cases.txt 的 mod_example; 这里只验证无头可测的部分)
func test_example_mod_stage_loads():
	var content: Node = Engine.get_main_loop().root.get_node("Content")
	content.load_packs([ContentDB.default_main()])
	check(not content.has_stage(36), "基础包没有第 36 关")
	eq(content.stage_count(), 36)
	content.load_packs(["tdj", "example_mod"])
	eq(content.errors, [], "加载与 .evs 编译无错")
	eq(content.stage_count(), 37, "关卡数取最大")
	check(content.has_stage(36), "改动包带来第 36 关")
	var st := BattleStage.load_stage(36)
	eq(st.n, 36)
	eq(st.name, "外传  夜魑巢穴")
	eq([st.width, st.height], [24, 16], "地图尺寸")
	eq(st.cells.size(), 24 * 16)
	eq(st.man.size(), 3, "单位: 主角 + 2 只夜魑")
	eq(st.xy.size(), 3)
	for u in st.man:
		check(not content.unit(int(u["unit_id"])).is_empty(), "单位模板 %d 存在于基础包 units 表" % int(u["unit_id"]))
	eq(st.tevt.size(), 1)
	eq(st.judge["win"][0]["event"], 2, "胜利条件触发事件 2")
	eq(st.events.size(), 3, "剧情脚本编译出 3 个事件")
	var ends_stage := false
	for c in st.events[2]:
		ends_stage = ends_stage or int(c["type"]) == 0x02
	check(ends_stage, "事件 2 以 end_stage (0x02) 收尾")
	check(st.emsg.size() >= 3 and st.emsg[1].size() == 2, "对白组按事件号")
	content.load_packs([ContentDB.default_main()])
	check(not content.has_stage(36), "还原后 36 关消失")


## 改动包规则: 深合并、追加新记录、_delete、同路径文件整体替换、新表、关卡数取最大、assets 覆盖、多包叠加顺序
func test_mod_rules():
	var a := "user://content/test_mod_a"
	var b := "user://content/test_mod_b"
	_write(a + "/manifest.json", {"format": "tdj-content/1", "id": "test_mod_a", "version": "1", "base": ["tdj"], "stage_count": 37,
		"tables": {"quests": {"file": "data/quests.json", "key": "id"}}})
	_write(a + "/data/items.json", [{"id": 0, "attack_range": {"max": 3}, "price": 1}, {"id": 374, "name": "新剑", "type": 1, "price": 9},
		{"id": 5, "_delete": true}])
	_write(a + "/data/quests.json", [{"id": "q1", "reward": 10}])
	_write(a + "/stages/01/stage.json", {"id": 1, "name": "新第一幕"})
	_write(a + "/text/system.json", {"treasure": [["宝箱!"]]})
	_write(a + "/assets/Stage/Stage01/Map01.png", "x")
	_write(b + "/manifest.json", {"format": "tdj-content/1", "id": "test_mod_b", "version": "1", "base": ["test_mod_a"]})
	_write(b + "/data/items.json", [{"id": 0, "price": 2}])
	_write(b + "/data/quests.json", [{"id": "q1", "reward": 20}, {"id": "q2"}])
	var base = _db(["tdj"])
	var db = _db(["test_mod_b"])
	eq(db.errors, [])
	eq(db.packs.map(func(p): return p["id"]), ["tdj", "test_mod_a", "test_mod_b"], "base 递归展开")
	var it: Dictionary = db.item(0)
	eq(int(it["price"]), 2, "后加载的包覆盖")
	eq(int(it["attack_range"]["max"]), 3, "子对象深合并")
	eq(int(it["attack_range"]["min"]), int(base.item(0)["attack_range"]["min"]), "子对象里没写的字段保留")
	eq(String(db.item(374)["name"]), "新剑", "追加新记录")
	eq(db.items().size(), 375)
	eq(db.item(5), {}, "_delete 删除记录")
	eq(db.items()[5], {}, "删除后下标数组留空位")
	eq(db.table("quests").map(func(q): return int(q.get("reward", 0))), [20, 0], "改动包新增的表")
	eq(db.stage_count(), 37, "关卡数取各包最大值")
	eq(db.stage_name(1), "新第一幕", "同路径文件整体替换")
	check(not db.stage_info(1).has("judge"), "整体替换不与原文件合并")
	eq(db.system_text("treasure"), [["宝箱!"]], "系统文本按表名替换")
	eq(db.system_text("give_item"), base.system_text("give_item"))
	check(db.asset_file("stage/stage01/MAP01.png").ends_with("assets/Stage/Stage01/Map01.png"), "assets 覆盖 (不区分大小写)")
	eq(base.asset_file("Stage/Stage01/Map01.png"), "")
	var bad = _db(["tdj", "no_such_pack"])
	eq(bad.errors.size(), 1, "找不到的包报错")
	base.free()
	db.free()
	bad.free()


## Python 可执行名: 环境变量 TDJ_PYTHON (tools/*.py 入口会设) > Windows 用 python, 其余 python3
func _python() -> String:
	var v := OS.get_environment("TDJ_PYTHON")
	return v if v != "" else ("python" if OS.get_name() == "Windows" else "python3")


## 内容包 schema 校验 (tools/checks/content_schema.py, 纯 Python): 内置的两个包必须通过, 故意写坏的改动包必须被报出
func test_content_schema():
	var script := ProjectSettings.globalize_path("res://").path_join("../tools/checks/content_schema.py").simplify_path()
	if not FileAccess.file_exists(script):
		check(true, "找不到 tools/checks/content_schema.py, 跳过")
		return
	var py := _python()
	# 输出走 --report 文件 (UTF-8): Windows 上 Godot 按 ANSI 代码页解码子进程 stdout, 直接抓中文会乱
	var report := ProjectSettings.globalize_path("user://schema_report.txt")
	var out := []
	var rc := OS.execute(py, [script, "--report", report], out, true)
	if rc == -1:
		check(true, "没有 Python (%s), 跳过" % py)
		return
	eq(rc, 0, "内置内容包 schema 校验: " + FileAccess.get_file_as_string(report))
	var bad := ProjectSettings.globalize_path("user://schema_bad/bad")
	_write(bad + "/manifest.json", {"format": "tdj-content/1", "id": "bad", "name": "x", "version": "1", "base": ["tdj"]})
	_write(bad + "/data/units.json", [{"id": 0, "move": "fast"}, {"name": "没有键"}])
	rc = OS.execute(py, [script, "--pack", bad, "--report", report], [], true)
	eq(rc, 1, "写坏的改动包应校验失败")
	out = [FileAccess.get_file_as_string(report)]
	check("move" in "\n".join(out) and "合并键" in "\n".join(out), "报出字段类型错与缺键: " + "\n".join(out))


func test_item_at_safe_lookup() -> void:
	var a := Content.items()
	check(not a.is_empty(), "有物品表")
	check(Content.item_at(0) == a[0], "合法编号与 items()[id] 同一记录")
	for bad in [-1, a.size(), 99999]:
		var r := Content.item_at(bad)
		check(r.get("name") == "" and int(r.get("type", -1)) == 0, "无效编号 %d 返回缺省记录" % bad)
	check(Content.item_at(-1) != a[a.size() - 1], "负数不再静默取到最后一项")



## 同 item_at: 单位/技能按编号取, 越界/负数报错并返回带常用键的缺省记录 (界面与战场直接取 name/sprite/mp_cost 不崩溃)
func test_unit_skill_at_safe_lookup() -> void:
	var us := Content.units()
	var ss := Content.skills()
	check(not us.is_empty() and not ss.is_empty(), "有单位表与技能表")
	check(Content.unit_at(0) == us[0], "合法单位编号与 units()[id] 同一记录")
	check(Content.skill_at(1) == ss[1], "合法技能编号与 skills()[id] 同一记录")
	for bad in [-1, us.size(), 99999]:
		var r := Content.unit_at(bad)
		check(r.get("name") == "" and int(r.get("sprite", -1)) == 0 and r.has("move"), "无效单位编号 %d 返回缺省记录" % bad)
	for bad in [-1, ss.size(), 99999]:
		var r := Content.skill_at(bad)
		check(r.get("name") == "" and int(r.get("mp_cost", -1)) == 0 and r.has("desc"), "无效技能编号 %d 返回缺省记录" % bad)
	check(Content.unit_at(-1) != us[us.size() - 1], "负数不再静默取到最后一项")
	var rows: Array = UiListMenu.spell_rows([1, 99999])
	eq(rows.size(), 2, "法术行: 坏编号不崩溃")
	eq(rows[1]["name"], "", "坏编号显示空名")

## 缺文件的内容包 (mod 声明了关卡/城镇却少文件): stage_error/town_error 指出缺什么, 完整的关卡 "" ;
## 场景流转 Game._battle_scene/_rpg_scene 据此回标题而不是崩溃
func test_missing_stage_files_fall_back_to_title():
	var m := "user://content/test_mod_missing"
	_write(m + "/manifest.json", {"format": "tdj-content/1", "id": "test_mod_missing", "version": "1", "base": ["tdj"], "stage_count": 50, "town_count": 50})
	_write(m + "/stages/49/stage.json", {"id": 49, "name": "缺文件关"})   # 只有 stage.json
	_write(m + "/towns/49/town.json", {"entries": []})                    # 缺 layers/map
	var db = _db(["test_mod_missing"])
	check(db.stage_error(1) == "", "完整的原版关卡无错: " + db.stage_error(1))
	check(db.town_error(1) == "", "完整的原版城镇无错: " + db.town_error(1))
	var e: String = db.stage_error(49)
	check(e.contains("49") and e.contains("units.json"), "指出缺哪个文件: " + e)
	check(db.town_error(49).contains("layers.json"), "城镇缺文件: " + db.town_error(49))
	check(db.stage_error(999) != "", "不存在的关卡")
	# 场景流转: 用真实 Content (只含原版), 取不存在的关卡/城镇
	var n0: int = Game.load_failures
	var s: Node = Game._battle_scene(999)
	check(s.get_script().resource_path.ends_with("title_scene.gd"), "战场加载失败回标题场景")
	s.free()
	s = Game._rpg_scene(999, 0)
	check(s.get_script().resource_path.ends_with("title_scene.gd"), "城镇加载失败回标题场景")
	s.free()
	eq(Game.load_failures, n0 + 2, "失败计数")
	db.free()


## 新游戏起点 (X1): manifest.start; 缺省 = tdj 起点 (第 0 关、initial_gold、无开场过场), 与改前 Game.new_game 的写死行为一致
func test_start_defaults_and_override():
	var db = _db(["tdj"])
	eq(db.start(), {"kind": "stage", "id": 0, "entry": 0, "gold": 5, "movie": -1}, "缺省起点 = 原版")
	eq(_db(["tdj", "example_mod"]).start()["id"], 0, "改动包不写 start 沿用缺省")
	var a := "user://content/test_start_a"
	_write(a + "/manifest.json", {"format": "tdj-content/1", "id": "test_start_a", "version": "1", "base": ["tdj"],
		"start": {"kind": "town", "id": 3, "entry": 2, "gold": 77, "movie": 5}})
	var s: Dictionary = _db(["test_start_a"]).start()
	eq(s, {"kind": "town", "id": 3, "entry": 2, "gold": 77, "movie": 5}, "manifest.start 生效")
	_write(a + "/manifest.json", {"format": "tdj-content/1", "id": "test_start_a", "version": "1", "base": ["tdj"],
		"start": {"kind": "stage", "id": 2}})
	eq(_db(["test_start_a"]).start(), {"kind": "stage", "id": 2, "entry": 0, "gold": 5, "movie": -1}, "没写的字段取缺省")
	DirAccess.remove_absolute(a + "/manifest.json")
	DirAccess.remove_absolute(a)


## 最小新游戏骨架 (content/templates/minimal_game, base 为空): 单独加载不依赖 tdj, 起点 = 城镇 0, 关卡/城镇/剧情可载入 (X1)
func test_minimal_game_template():
	var db = _db(["minimal_game"])
	eq(db.errors, [], "无加载错误")
	eq(db.packs.map(func(p): return p["id"]), ["minimal_game"], "base 为空: 只有自己")
	eq([db.stage_count(), db.town_count()], [1, 1])
	eq(db.start(), {"kind": "town", "id": 0, "entry": 0, "gold": 50, "movie": -1}, "起点来自 manifest.start")
	eq(db.units().size(), 2)
	check(db.is_hero(0) and not db.is_hero(1), "我方角色 = party_init")
	var content: Node = Engine.get_main_loop().root.get_node("Content")
	content.load_packs(["minimal_game"])
	var st := BattleStage.load_stage(0)
	eq([st.width, st.height, st.man.size(), st.events.size()], [12, 8, 2, 3], "关卡载入并编译出 3 个事件")
	var rs := RpgStage.load_stage(0)
	eq([rs.width, rs.height, rs.pos.size(), rs.shops.size()], [12, 10, 1, 1], "城镇载入")
	content.load_packs([ContentDB.default_main()])
	check(content.stage_count() == 36, "还原默认内容包")
	db.free()

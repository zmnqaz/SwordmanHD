# SPDX-License-Identifier: GPL-3.0-only
class_name GameSaves
extends RefCounted
## 游戏存档: 5 个存档位 (user://saveN.json, N = 1..5) 与战阵存录 (user://battle.json, 战场中途存档, 标题「戰陣重现」读取)。
## 只管 GameState <-> 文件, 不碰场景/界面/提示; 读写经 SaveFile (原子写入 + .bak 回退 + 版本迁移)。
## 失败返回 error 文字 (空串 = 成功), 由调用方 (Game) 决定怎么提示。

const SLOTS := 5
## 存档目录 (测试改成临时目录, 免得碰玩家的真存档)
static var base_dir := "user://"
## 存档镜像 (见 SaveMirror): 组装层在 Android 上调 enable_mirror 登记「本地存档目录 -> 镜像目录」;
## 只有 base_dir 正是登记的本地目录时才镜像 (回放沙盒、测试把 base_dir 换走后自动不镜像, 不会往真镜像目录写)
static var _mirror_local := ""
static var _mirror_remote := ""
## 内容包的关卡数 (组装层 Game.boot 设; 0 = 未知, 不检查关卡编号范围)
static var stage_limit := 0


## 登记镜像 (local_dir 空 = 关闭)
static func enable_mirror(local_dir: String, mirror_dir: String) -> void:
	_mirror_local = local_dir
	_mirror_remote = mirror_dir


static func mirror_dir() -> String:
	return _mirror_remote if _mirror_local != "" and base_dir == _mirror_local else ""


static func _mirror_push(path: String) -> void:
	var m := mirror_dir()
	if m != "":
		SaveMirror.push(base_dir, m, path.get_file())


## 导入镜像目录里被外部换过的存档, 并给还没镜像的存档补镜像 (非 Android 什么也不做); 返回 SaveMirror.pull 的结果
static func sync_mirror() -> Dictionary:
	var m := mirror_dir()
	if m == "":
		return {"imported": [], "rejected": {}}
	var r := SaveMirror.sync(base_dir, m, func(_name, d): return range_error(d["game"] if d.get("game") is Dictionary else d))
	if not r.imported.is_empty():
		print("已从镜像目录导入存档: ", r.imported)
	return r


static func battle_path() -> String:
	return base_dir.path_join("battle.json")


static func slot_path(slot: int) -> String:
	return base_dir.path_join("save%d.json" % (slot + 1))


## 存档里的关卡编号必须落在内容包范围内 (手改/损坏的档读进来会让战场/营地场景拿到不存在的关); 通过返回 ""
static func range_error(d: Dictionary) -> String:
	var n := stage_limit
	if n <= 0:
		return ""
	for k in ["stage", "next_stage"]:
		var v := int(d.get(k, 0))
		if v < 0 or v > n:  # next_stage 可以等于 n (通关后没有下一关)
			return "存档里的关卡编号 (%d) 超出内容包范围, 无法读取" % v
	return ""


## 存档字典: 全局进度 + 存档元信息 (位置、时间、内容包标识、版本)
static func _snapshot(st: GameState) -> Dictionary:
	var d := st.to_dict()
	d["where"] = "camp"
	d["time"] = Time.get_datetime_string_from_system(false, true)
	d["content"] = GameContext.current().content.signature()
	d["engine"] = ContentCompat.ENGINE_VERSION
	d["version"] = SaveFile.VERSION
	var rid := PlayLog.begin_save()   # 通关录像: 录像中存档带 id, 旁边存「到此为止的录像历史」, 以后读这个档能接上整场录像
	if rid != "":
		d["replay_id"] = rid
	return d


static func save_slot(st: GameState, slot: int) -> bool:
	var ok := SaveFile.write_json(slot_path(slot), _snapshot(st))
	if ok:
		PlayLog.note_save("slot", slot, slot_path(slot))   # 通关录像: 记下存档点 (读档时剪回这里), 并存录像历史
		_mirror_push(slot_path(slot))
	return ok


## 存档记录的内容包与当前加载的是否兼容 (策略见 ContentCompat): 返回 {level: ok|warn|error, text, messages}
static func check_content(saved: Variant) -> Dictionary:
	return ContentCompat.check_save(saved, GameContext.current().content.pack_infos())


## 读存档位到 st; 返回 {ok, missing, error, warning}: 内容包缺失/版本不兼容时 ok=false 并带提示 (不读入, 不崩溃), 兼容但有差异时 warning 非空
static func load_slot(st: GameState, slot: int) -> Dictionary:
	var r := SaveFile.load_file(slot_path(slot), "game")
	r["warning"] = ""
	if r.ok:
		var c := check_content(r.data.get("content"))
		if c.level == "error":
			r["ok"] = false
			r["error"] = c.text
			return r
		var e := range_error(r.data)
		if e != "":
			r["ok"] = false
			r["error"] = e
			return r
		r["warning"] = c.text
		st.apply_dict(r.data)
		PlayLog.note_load("slot", slot, r.data, slot_path(slot))   # 通关录像: 剪回这个存档点 (或以它为录像起点)
	return r


static func has_any_slot() -> bool:
	for i in SLOTS:
		if SaveFile.exists(slot_path(i)):
			return true
	return false


static func save_battle(st: GameState, snapshot: Dictionary) -> bool:
	var game := _snapshot(st)
	var ok := SaveFile.write_json(battle_path(), SaveFile.stamp({"game": game, "battle": snapshot}, "battle", game["content"]))
	if ok:
		PlayLog.note_save("battle", 0, battle_path())
		_mirror_push(battle_path())
	return ok


static func has_battle_save() -> bool:
	return SaveFile.exists(battle_path())


## 读战阵存录到 st; 返回 {ok, error, warning, battle: 战场快照} (内容包检查同 load_slot)
## snapshot_check: 校验战场快照的回调 (Variant -> 错误提示, "" 通过; 由组装层给, 本层不认识战场), 不通过则不读入任何状态
static func load_battle(st: GameState, snapshot_check := Callable()) -> Dictionary:
	if not has_battle_save():
		return {"ok": false, "error": "", "warning": "", "battle": {}}
	var r := SaveFile.load_file(battle_path(), "battle")
	if not r.ok:
		return {"ok": false, "error": r.error, "warning": "", "battle": {}}
	var c := check_content(r.data.get("content", r.data["game"].get("content")))
	if c.level == "error":
		return {"ok": false, "error": c.text, "warning": "", "battle": {}}
	var e := range_error(r.data["game"])
	if e != "":
		return {"ok": false, "error": e, "warning": "", "battle": {}}
	if snapshot_check.is_valid():
		e = String(snapshot_check.call(r.data["battle"]))
		if e != "":
			return {"ok": false, "error": e, "warning": "", "battle": {}}
	st.apply_dict(r.data["game"])
	PlayLog.note_load("battle", 0, {"game": r.data["game"], "battle": r.data["battle"]}, battle_path())
	return {"ok": true, "error": "", "warning": c.text, "battle": r.data["battle"]}

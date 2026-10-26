# SPDX-License-Identifier: GPL-3.0-only
class_name ContentCompat
extends RefCounted
## 内容包版本与存档兼容策略 (纯逻辑, 不依赖 autoload, 可无场景树测试)。
##
## 版本号: 点分数字 (如 "1.3.0" / "2"), 逐段按数字比较, 缺的段按 0。空串 = 未知。
## manifest 字段 (docs/内容格式.md「内容包版本」):
##   version          包自己的版本 (pack 版本), 存档会记录
##   engine_min/max   本包要求的引擎版本范围 (含); 引擎 ENGINE_VERSION 不在范围内时该包不加载并报错
##   save_compat_min  本包还能读的最旧存档版本: 存档里记的该包版本低于它则拒绝读档 (缺省 = 不限)
## 存档: 写档时记 "content": [{id, version}] (Content.signature()) 与 "engine": ENGINE_VERSION。
## 读档时 check_save() 按下面的策略出结论, 调用方 (GameSaves) 只取 level/text:
##   存档需要的包没加载            -> error  (缺什么、怎么启用)
##   存档的包版本比当前新          -> error  (请升级内容包)
##   存档的包版本低于 save_compat_min -> error
##   存档的包版本比当前旧但兼容     -> warn   (照常读档并提示)
##   当前多加载了存档没有的包       -> warn   (照常读档并提示)
##   其余 (含存档版本未知)         -> ok

## 引擎版本 (内容包用 engine_min/engine_max 约束它; 引擎对包格式做不兼容改动时升主版本)
const ENGINE_VERSION := "1.0.0"
## 没有 "content" 字段的存档 (内容包机制出现之前, 只有原版包) 视为用这个包: 历史事实, 不是默认配置
const LEGACY_PACK_ID := "tdj"


## 比较两个版本号: -1 / 0 / 1; 任一为空返回 0 (未知不算冲突)
static func compare(a: String, b: String) -> int:
	if a.strip_edges() == "" or b.strip_edges() == "":
		return 0
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


## 是合法版本号 (点分数字)
static func is_version(s: String) -> bool:
	return RegEx.create_from_string("^\\d+(\\.\\d+)*$").search(s) != null


## 包 manifest 对引擎的要求: 满足返回 "", 否则返回提示文字
static func engine_error(manifest: Dictionary, engine_version := ENGINE_VERSION) -> String:
	var id := String(manifest.get("id", "?"))
	var lo := String(manifest.get("engine_min", ""))
	var hi := String(manifest.get("engine_max", ""))
	if lo != "" and compare(engine_version, lo) < 0:
		return "内容包 %s 需要引擎 %s 以上, 当前引擎 %s" % [id, lo, engine_version]
	if hi != "" and compare(engine_version, hi) > 0:
		return "内容包 %s 只支持引擎 %s 以下, 当前引擎 %s" % [id, hi, engine_version]
	return ""


## 存档与当前已加载内容包的兼容检查。
## saved: 存档里的 "content" ([{id, version}]; 缺失/空按 LEGACY_PACK_ID 旧档处理); loaded: 当前加载的包 [{id, version, save_compat_min}]。
## 返回 {"level": "ok"|"warn"|"error", "text": 提示文字 (多条以换行连接), "messages": [提示...]}
static func check_save(saved: Variant, loaded: Array) -> Dictionary:
	var want: Array = saved if saved is Array and not (saved as Array).is_empty() else [{"id": LEGACY_PACK_ID, "version": ""}]
	var errors: Array = []
	var warns: Array = []
	var by_id := {}
	for l in loaded:
		by_id[String(l.get("id", ""))] = l
	var seen := {}
	for s in want:
		if not s is Dictionary:
			continue
		var id := str(s.get("id", ""))
		var sv := str(s.get("version", ""))
		seen[id] = true
		if not by_id.has(id):
			errors.append("存档需要内容包「%s」%s, 当前未加载 (用 --mods=%s 或在设定里启用)" % [id, ("v" + sv) if sv != "" else "", id])
			continue
		var l: Dictionary = by_id[id]
		var lv := String(l.get("version", ""))
		var lo := String(l.get("save_compat_min", ""))
		if compare(sv, lv) > 0:
			errors.append("存档来自更新的内容包「%s」v%s, 当前只有 v%s, 请升级" % [id, sv, lv])
		elif lo != "" and compare(sv, lo) < 0:
			errors.append("存档的内容包「%s」v%s 过旧, 当前版本 v%s 至少需要 v%s 的存档" % [id, sv, lv, lo])
		elif compare(sv, lv) < 0:
			warns.append("内容包「%s」已从 v%s 升到 v%s" % [id, sv, lv])
	for id in by_id:
		if not seen.has(id):
			warns.append("当前额外启用了内容包「%s」, 存档创建时没有" % id)
	if not errors.is_empty():
		return {"level": "error", "text": "\n".join(errors), "messages": errors}
	if not warns.is_empty():
		return {"level": "warn", "text": "\n".join(warns), "messages": warns}
	return {"level": "ok", "text": "", "messages": []}

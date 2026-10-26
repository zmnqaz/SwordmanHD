# SPDX-License-Identifier: GPL-3.0-only
class_name ContentInfo
extends RefCounted
## 核心层 (core/) 需要问内容包的几件事: 存档签名/版本兼容信息、主角判定与初始随身物品 (存档迁移用)。
## 经 GameContext.content 取用, core/ 不直接引用 autoload Content (闸门 tests/test_engine_deps.gd)。
## 缺省实现读 db 指向的 ContentDB; db 为 null 时取场景树上的 autoload "Content" (按节点名找, 不写代码引用);
## 找不到内容包 (纯逻辑测试) 返回空值, 测试要换内容包就 `GameContext.current().content.db = my_db`。

var db: Object = null


func _db() -> Object:
	if db != null:
		return db
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Content") if tree else null


## 存档签名 [{id, version}] (ContentDB.signature)
func signature() -> Array:
	var d := _db()
	return d.signature() if d != null else []


## 已加载内容包的版本信息 [{id, version, save_compat_min}] (ContentDB.pack_infos)
func pack_infos() -> Array:
	var d := _db()
	return d.pack_infos() if d != null else []


func is_hero(unit_id: int) -> bool:
	var d := _db()
	return d != null and d.is_hero(unit_id)


## 主角初始配置 (party_init 表记录); 无内容包返回 {}
func party_init(unit_id: int) -> Dictionary:
	var d := _db()
	return d.party_init(unit_id) if d != null else {}


## 内容包里的 JSON (同路径后加载的包优先, 当前语言的叠加层已合上; ContentDB.json); 无内容包或无此文件返回 null
func json(rel: String) -> Variant:
	var d := _db()
	return d.json(rel) if d != null else null


func has_file(rel: String) -> bool:
	var d := _db()
	return d != null and d.has_file(rel)

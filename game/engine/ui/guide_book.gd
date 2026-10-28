# SPDX-License-Identifier: GPL-3.0-only
class_name GuideBook
extends RefCounted
## 攻略内容 (内容包 guide/, docs/内容格式.md §16): 目录 guide/guide.json 列出各章 {id, file, stage?}, 每章一个 JSON {title, label, body}。
## 经 GameContext.content (ContentInfo) 读: 后加载的包整个替换同路径文件, 繁体叠加层 (locale/hant/guide/...) 由内容包层合上。
## 内容包可以没有攻略 (mod / 新游戏): available() 为假, 设定面板不列「攻略」, 热键打开的面板只显示「没有攻略」。

const INDEX := "guide/guide.json"

## [{id, title, label, stage (非关卡章 -1), body}]
var chapters: Array = []


static func available(content: Object) -> bool:
	return content != null and content.has_file(INDEX)


static func load_from(content: Object) -> GuideBook:
	var g := GuideBook.new()
	var idx = content.json(INDEX) if content != null else null
	if not idx is Dictionary or not idx.get("chapters") is Array:
		return g
	for c in idx["chapters"]:
		if not c is Dictionary or not c.get("file") is String:
			continue
		var d = content.json(String(c["file"]))
		if not d is Dictionary:
			push_warning("攻略: 目录里的章 %s 读不到" % c["file"])
			continue
		var title := String(d.get("title", c.get("id", "")))
		g.chapters.append({"id": String(c.get("id", "")), "title": title, "label": String(d.get("label", title)),
			"stage": int(c["stage"]) if (c.get("stage") is float or c.get("stage") is int) else -1, "body": String(d.get("body", ""))})
	return g


func is_empty() -> bool:
	return chapters.is_empty()


## 章 id 的下标, 没有 -1
func index_of(id: String) -> int:
	for i in chapters.size():
		if chapters[i]["id"] == id:
			return i
	return -1


## 第一次打开 (本次运行里还没翻过) 的章: 目录第一章是非关卡章 (本仓库是「完美结局」) 就是它, 否则按关号 (index_for_stage)
func first_open_index(stage: int) -> int:
	if not chapters.is_empty() and int(chapters[0]["stage"]) < 0:
		return 0
	return index_for_stage(stage)


## 默认打开的章: 关号 stage 的章; 没有就取关号不超过它的最近一章; 再没有取第一个关卡章; 都没有 0
func index_for_stage(stage: int) -> int:
	var best := -1
	var first := -1
	for i in chapters.size():
		var s: int = chapters[i]["stage"]
		if s < 0:
			continue
		if first < 0:
			first = i
		if s == stage:
			return i
		if s < stage and (best < 0 or s > int(chapters[best]["stage"])):
			best = i
	return best if best >= 0 else maxi(first, 0)


## 现在该看哪一关: 战场里 = 本关; 城镇/营地/标题 = 下一关 (state.next_stage, 关卡结束时与城镇剧情设定)
static func current_stage(gc: GameContext) -> int:
	return gc.state.stage if gc.in_battle else gc.state.next_stage

# SPDX-License-Identifier: GPL-3.0-only
class_name ImagePreloader
extends RefCounted
## 在工作线程里提前解码图片 (Image.load_from_file): 切场景的淡出期间把大图 (城镇大地图, 4 倍 AI 图几千像素宽) 先读好,
## 进场景 _ready 里 take 直接拿, 不再卡主线程。手机 CPU 弱, 天玑 720 上第 1 镇地图 (Rpg/Rpg00/map00.png) 解码要 2.2 秒, 整个应用冻住。
## 没 start 过的图 take 返回 null, 调用方自己同步读 (行为同没有预读)。

var _slots := {}   # 文件 -> {task, img, gen}
var _gen := 0


func start(file: String) -> void:
	if file == "" or _slots.has(file):
		return
	var slot := {"img": null, "gen": _gen}
	slot["task"] = WorkerThreadPool.add_task(func(): slot["img"] = Image.load_from_file(file), false, "preload image")
	_slots[file] = slot


## 取走解码好的图 (还没做完就等); 没有 start 过 / 读失败返回 null
func take(file: String) -> Image:
	if not _slots.has(file):
		return null
	var slot: Dictionary = _slots[file]
	_slots.erase(file)
	WorkerThreadPool.wait_for_task_completion(slot["task"])
	return slot["img"]


## 换场景时调: 上一轮 start 了却没人取的丢掉 (大图 RGBA 几十 MB); 这一轮 (切换前刚 start 的) 留着给新场景取
func next_scene() -> void:
	for f in _slots.keys():
		if int(_slots[f]["gen"]) < _gen:
			take(f)
	_gen += 1


## 退出前: 线程池里没人等待的任务退出时释放回调会崩, 先全部等完
func wait_all() -> void:
	for f in _slots.keys():
		take(f)


func pending() -> int:
	return _slots.size()

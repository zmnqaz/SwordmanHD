# SPDX-License-Identifier: GPL-3.0-only
class_name RegressLog
extends RefCounted
## 确定性回归记录 (引擎通用, 与具体游戏无关)。
## 游戏在关键时刻调用 RegressLog.checkpoint(kind, tag): 把所有「状态提供者」给出的状态摊平成 路径=值,
## 算出整体哈希, 与上一个检查点比较后只写变化的字段 (增量), 一行一个 JSON:
##   {"n": 序号, "k": 种类, "t": 标签 (关卡/回合/单位...), "h": 状态哈希, "d": {路径: 新值},
##    "x": [删掉的路径; "名字.*" = 该提供者整个注销], "f": 帧号 (仅参考, 不比较)}
## 对比工具 (仓库外的开发脚本) 逐行重建完整状态, 报告第一处偏差 (哪个检查点、哪些字段)。
## 状态提供者: RegressLog.provide(名字, Callable) 注册, 回调返回可 JSON 化的字典/数组/标量; provide(名字, Callable()) 注销。
## 命令行 (-- 之后):
##   --regress-out=<文件>          打开记录 (不给则全部调用为空操作)
##   --regress-stop=<种类>:<次数>  该种类检查点出现第 N 次后记录并退出 (可给多个, 任一满足即退出)
##   --regress-max-frames=<帧>     超过帧数仍未结束: 记一条 timeout 后退出
## 不论有没有 --regress-stop, 种类 "game_over" 都会结束记录。

static var _file: FileAccess
static var _providers := {}      # 名字 -> Callable
static var _prev := {}           # 上一个检查点的 路径 -> 值 (字符串)
static var _seq := 0
static var _counts := {}         # 种类 -> 次数
static var _stops := {}          # 种类 -> 次数
static var _max_frames := -1
static var _done := false
static var frame := 0            # 由驱动方 (Autotest) 每帧更新
static var log_frame := 0        # 日志里打印的帧号 (驱动方每帧更新; 生产代码只读它, 不引用测试驱动 autoload)


static func active() -> bool:
	return _file != null and not _done


## 由测试驱动在启动时调用 (Autotest._ready)
static func setup(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--regress-out="):
			var path := a.trim_prefix("--regress-out=")
			_file = FileAccess.open(path, FileAccess.WRITE)
			if _file == null:
				push_error("RegressLog: 打不开 %s" % path)
		elif a.begins_with("--regress-stop="):
			var kv := a.trim_prefix("--regress-stop=").split(":")
			_stops[kv[0]] = int(kv[1]) if kv.size() > 1 else 1
		elif a.begins_with("--regress-max-frames="):
			_max_frames = int(a.trim_prefix("--regress-max-frames="))


static func provide(name: String, fn: Callable) -> void:
	if fn.is_valid():
		_providers[name] = fn
	else:
		_providers.erase(name)


## 注销 owner 注册的提供者 (场景退出时; 新场景已用同名注册的不受影响)
static func drop(name: String, owner: Object) -> void:
	var fn: Callable = _providers.get(name, Callable())
	if fn.is_valid() and fn.get_object() == owner:
		_providers.erase(name)


## 每帧调用: 超时检查
static func tick(f: int) -> void:
	frame = f
	if active() and _max_frames > 0 and f >= _max_frames:
		checkpoint("timeout", {"frames": f})
		finish("timeout")


## 当前所有状态提供者的整体哈希 (不需要打开记录; 存读档一致性比对、猴子测试判断「状态是否在变」用)
static func state_hash() -> String:
	var flat := {}
	var names := _providers.keys()
	names.sort()
	for n in names:
		var fn: Callable = _providers[n]
		if fn.is_valid():
			flatten(fn.call(), n, flat)
	var keys := flat.keys()
	keys.sort()
	var lines := PackedStringArray()
	for k in keys:
		lines.append("%s=%s" % [k, flat[k]])
	return "\n".join(lines).md5_text().left(16)


static func checkpoint(kind: String, tag := {}) -> void:
	if not active():
		return
	var flat := {}
	var names := _providers.keys()
	names.sort()
	for n in names:
		var fn: Callable = _providers[n]
		if fn.is_valid():
			flatten(fn.call(), n, flat)
	var keys := flat.keys()
	keys.sort()
	var lines := PackedStringArray()
	var delta := {}
	for k in keys:
		lines.append("%s=%s" % [k, flat[k]])
		if not _prev.has(k) or _prev[k] != flat[k]:
			delta[k] = flat[k]
	var removed: Array = []
	var gone := {}   # 整个提供者都没了 (场景退出): 只记 "名字.*"
	for k in _prev:
		if not flat.has(k):
			var top: String = k.get_slice(".", 0)
			if not _providers.has(top):
				gone[top + ".*"] = true
			else:
				removed.append(k)
	removed.append_array(gone.keys())
	removed.sort()
	var rec := {"n": _seq, "k": kind, "t": tag, "h": "\n".join(lines).md5_text().left(16), "d": delta, "f": frame}
	if not removed.is_empty():
		rec["x"] = removed
	_file.store_line(JSON.stringify(rec, "", true))
	_file.flush()
	_prev = flat
	_seq += 1
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	if kind == "game_over" or (_stops.has(kind) and int(_counts[kind]) >= int(_stops[kind])):
		finish(kind)


## 结束记录并退出程序
static func finish(reason: String) -> void:
	if _file == null or _done:
		return
	_file.store_line(JSON.stringify({"n": _seq, "k": "end", "t": {"reason": reason}, "f": frame}))
	_file.close()
	_done = true
	print("RegressLog: 结束 (%s), 共 %d 个检查点" % [reason, _seq])
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for p in tree.root.find_children("*", "AudioStreamPlayer", true, false):  # 先让音频线程松手, 免得退出时报 ObjectDB 泄漏噪声
			p.stop()
			p.stream = null
		OS.delay_msec(150)
		tree.quit()


## 摊平为 路径 -> 规范字符串 (字典按键排序由调用方统一排序; 浮点保留 4 位小数, 避免显示误差)
static func flatten(v, path: String, out: Dictionary) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			if v.is_empty():
				out[path] = "{}"
			for k in v:
				flatten(v[k], "%s.%s" % [path, k], out)
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			# 标量数组整体记一项 (行囊、技能栏等), 便于阅读; 含字典/数组的逐项展开
			var nested := false
			for x in v:
				if typeof(x) in [TYPE_DICTIONARY, TYPE_ARRAY]:
					nested = true
					break
			if nested:
				out[path + "#"] = str(v.size())
				for i in v.size():
					flatten(v[i], "%s.%d" % [path, i], out)
			else:
				out[path] = "[" + ",".join(Array(v).map(func(x): return _scalar(x))) + "]"
		_:
			out[path] = _scalar(v)


static func _scalar(v) -> String:
	match typeof(v):
		TYPE_FLOAT:
			if v == floor(v) and absf(v) < 1e15:
				return str(int(v))
			return "%.4f" % v
		TYPE_BOOL:
			return "1" if v else "0"
		TYPE_VECTOR2I:
			return "%d,%d" % [v.x, v.y]
		TYPE_VECTOR2:
			return "%.4f,%.4f" % [v.x, v.y]
		TYPE_NIL:
			return "null"
	return str(v)

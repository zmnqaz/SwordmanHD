# SPDX-License-Identifier: GPL-3.0-only
class_name EvsCompiler
extends RefCounted
## 剧情脚本 .evs (docs/剧情脚本格式.md) -> 指令序列, 供 EventVM (战场) / RpgVM (城镇) 执行。
## 编译结果与原版字节码逐条相同: 每个事件是 [{"type": 指令号, "data": 参数字节 PackedByteArray}, ...],
## 批量命令 (show/hide/fade_out ids=、move/move_steps 块) 展开成 头指令 + N 条记录, 标签换算成展开后的指令序号。
## 所以解释器按原版语义执行 (头指令之后的 N 条一律当记录读、越界跳转即结束等), 与执行原版 EVENT_NN.COD 完全一致。
## 指令表来自 evs_ops.json (由 tools/assets/compile_events.py --export-ops 生成, 指令表的唯一定义在该 Python 文件)。
## 本文件是 tools/assets/compile_events.py 的 parse_script / compile_event 的逐行移植; 两者由 tests/test_content.gd 对照。

const OPS_PATH := "res://engine/script/evs_ops.json"

static var _ops := {}   # 缓存的指令表


## 编译 .evs 文本。返回 {"kind": "battle"|"town", "events": [[{type, data}, ...], ...]};
## 出错返回 {"error": "文件:行: 原因"}
static func compile(text: String, path := "<script>") -> Dictionary:
	var c := EvsCompiler.new()
	return c._compile(text, path)


static func ops() -> Dictionary:
	if _ops.is_empty():
		_ops = JSON.parse_string(FileAccess.get_file_as_string(OPS_PATH))
	return _ops


var _err := ""
var _kind := ""
var _table := {}       # 指令号 -> {name, params}
var _by_name := {}     # 命令名 -> [指令号]


func _fail(msg: String) -> void:
	if _err == "":
		_err = msg


func _set_kind(kind: String) -> void:
	_kind = kind
	_table.clear()
	_by_name.clear()
	for o in ops()["kinds"][kind]["ops"]:
		var op := int(o["op"])
		_table[op] = o
		_by_name.get_or_add(String(o["name"]), []).append(op)


static func _strip_comment(line: String) -> String:
	if not line.contains("\""):
		var h := line.find("#")
		return (line if h < 0 else line.substr(0, h)).strip_edges()
	var q := false
	var out := ""
	for ch in line:
		if ch == "\"":
			q = not q
		if ch == "#" and not q:
			break
		out += ch
	return out.strip_edges()


## Python int(s, 0) 的子集: 十进制 (可带负号)、0x 十六进制
func _int(s: String, where: String) -> int:
	var t := s.strip_edges()
	var neg := t.begins_with("-")
	var body := t.substr(1) if neg or t.begins_with("+") else t
	var v := 0
	if body.to_lower().begins_with("0x") and body.length() > 2 and body.substr(2).is_valid_hex_number():
		v = body.substr(2).hex_to_int()
	elif body.is_valid_int() and not body.begins_with("-") and not body.begins_with("+"):
		v = body.to_int()
	else:
		_fail("%s: 不是整数: %s" % [where, s])
		return 0
	return -v if neg else v


static var _re_label: RegEx
static var _re_token: RegEx
static var _re_num: RegEx


static func _regex() -> void:
	if _re_label == null:
		_re_label = RegEx.create_from_string("^[A-Za-z_]\\w*:$")
		_re_token = RegEx.create_from_string("\\s*(?:([A-Za-z_][\\w]*)=(\"(?:[^\"\\\\]|\\\\.)*\"|[^\\s#]+)|([^\\s#=]+))")
		_re_num = RegEx.create_from_string("^(-?\\d+|0x[0-9a-fA-F]+)$")


## -> {kind, slots, events: {id: [stmt]}}; stmt = {"label": 名} 或 {"name", "args", "children" (Array 或 null), "line"}
func _parse(text: String, path: String) -> Dictionary:
	_regex()
	var slots = null
	var events := {}
	var cur = null
	var block = null
	var no := 0
	for raw in text.split("\n"):
		no += 1
		var where := "%s:%d" % [path, no]
		var line := _strip_comment(raw)
		if line == "":
			continue
		if line == "}":
			if block == null:
				_fail("%s: 多余的 }" % where)
			block = null
			continue
		if _re_label.search(line):
			if cur == null or block != null:
				_fail("%s: 标签只能写在事件内、块外" % where)
				continue
			cur.append({"label": line.trim_suffix(":")})
			continue
		var opens := line.ends_with("{")
		if opens:
			line = line.substr(0, line.length() - 1).strip_edges()
		var sp := line.find(" ")
		var tab := line.find("\t")
		if sp < 0 or (tab >= 0 and tab < sp):
			sp = tab
		var word := line if sp < 0 else line.substr(0, sp)
		var rest := "" if sp < 0 else line.substr(sp + 1).strip_edges()
		if word == "script":
			if not ops()["kinds"].has(rest):
				_fail("%s: script 只能是 battle 或 town" % where)
				continue
			_set_kind(rest)
			continue
		if word == "events":
			slots = _int(rest, where)
			continue
		if word == "event":
			if block != null:
				_fail("%s: 块未关闭" % where)
			var eid := _int(rest.trim_suffix(":"), where)
			if events.has(eid):
				_fail("%s: 事件 %d 重复" % [where, eid])
			cur = []
			events[eid] = cur
			continue
		if cur == null:
			_fail("%s: 命令必须写在 event 之后" % where)
			continue
		var args := {}
		var pos := 0
		while pos < rest.length():
			var m := _re_token.search(rest, pos)
			if m == null or m.get_start() != pos or m.get_end() == pos:
				break
			pos = m.get_end()
			if m.get_string(1) != "":
				args[m.get_string(1)] = m.get_string(2)
			elif m.get_string(3) != "":
				_fail("%s: 参数必须写成 名=值: %s" % [where, m.get_string(3)])
		var stmt := {"name": word, "args": args, "children": [] if opens else null, "line": no}
		if block != null:
			if opens:
				_fail("%s: 块不能嵌套" % where)
			block.append(stmt)
		else:
			cur.append(stmt)
			if opens:
				block = stmt["children"]
	if block != null:
		_fail("%s: 文件结束时块未关闭" % path)
	if _kind == "":
		_fail("%s: 缺少 script battle|town" % path)
	return {"slots": slots, "events": events}


func _encode(name: String, args: Dictionary, labels: Dictionary, where: String) -> Dictionary:
	if name == "raw":
		var hex := String(args.get("data", ""))
		return {"type": _int(String(args.get("op", "")), where), "data": hex.hex_decode() if hex != "" else PackedByteArray()}
	if not _by_name.has(name):
		_fail("%s: 未知命令 %s" % [where, name])
		return {"type": 0, "data": PackedByteArray()}
	var op: int = _by_name[name][0]
	if name == "if_var":
		var c := String(args.get("cmp", ""))
		var names: Array = ops()["cmp_names"]
		if not c in names:
			_fail("%s: if_var 的 cmp 必须是 %s" % [where, "/".join(names)])
			return {"type": 0, "data": PackedByteArray()}
		op = int(ops()["kinds"][_kind]["cmp_base"]) + names.find(c)
	var params: Array = _table[op]["params"]
	var known := {"cmp": true}
	for p in params:
		known[p[0]] = true
	for k in args:
		if not known.has(k):
			_fail("%s: %s 没有参数 %s" % [where, name, k])
	var data := PackedByteArray()
	for p in params:
		var pname: String = p[0]
		var t: String = p[1]
		var v := 0
		if args.has(pname):
			var s: String = args[pname]
			if t == "L":
				if _re_num.search(s):
					v = _int(s, where)
				elif labels.has(s):
					v = labels[s]
				else:
					_fail("%s: 未定义的标签 %s" % [where, s])
			else:
				v = _int(s, where)
		elif p[2] != null:
			v = int(p[2])
		else:
			_fail("%s: %s 缺少参数 %s" % [where, name, pname])
		var o := data.size()
		if t == "h":
			data.resize(o + 2)
			data.encode_s16(o, v)
		else:
			data.resize(o + 4)
			data.encode_s32(o, v)
	return {"type": op, "data": data}


func _is_unit_list(name: String) -> bool:
	return _kind == "battle" and name in ["show", "hide", "fade_out"]


static func _ids(s: String) -> Array:
	return Array(s.split(",")).map(func(x): return String(x).strip_edges()).filter(func(x): return x != "")


## 一条语句展开成的原版指令数 (算标签位置用)
func _expand(stmt: Dictionary) -> int:
	if stmt["children"] != null:
		return 1 + stmt["children"].size()
	if _is_unit_list(stmt["name"]) and stmt["args"].has("ids"):
		return 1 + _ids(stmt["args"]["ids"]).size()
	return 1


func _compile_event(stmts: Array, path: String) -> Array:
	var labels := {}
	var idx := 0
	for st in stmts:
		if st.has("label"):
			if labels.has(st["label"]):
				_fail("%s: 标签 %s 重复" % [path, st["label"]])
			labels[st["label"]] = idx
		else:
			idx += _expand(st)
	var cmds: Array = []
	for st in stmts:
		if st.has("label"):
			continue
		var name: String = st["name"]
		var args: Dictionary = st["args"].duplicate()
		var where := "%s:%d" % [path, st["line"]]
		if _is_unit_list(name):
			if args.has("ids"):
				var ids := _ids(args["ids"])
				args.erase("ids")
				args["count"] = str(ids.size())
				cmds.append(_encode(name, args, labels, where))
				for u in ids:
					var d := PackedByteArray()
					d.resize(2)
					d.encode_s16(0, _int(u, where))
					cmds.append({"type": 0x01, "data": d})
				continue
			if args.has("group"):
				var g: String = args["group"]
				args.erase("group")
				args["count"] = "-1"
				args["arg"] = str(int(ops()["groups"][g])) if ops()["groups"].has(g) else g
			cmds.append(_encode(name, args, labels, where))
			continue
		if st["children"] != null:
			var batch: Dictionary = ops()["kinds"][_kind]["batch"]
			if not _by_name.has(name) or not batch.has(str(_by_name[name][0])):
				_fail("%s: %s 不能带块" % [where, name])
				continue
			var rec_name: String = _table[int(batch[str(_by_name[name][0])])]["name"]
			if args.has("count"):
				_fail("%s: 带块时不写 count (由块内命令数决定)" % where)
			args["count"] = str(st["children"].size())
			cmds.append(_encode(name, args, labels, where))
			for ch in st["children"]:
				if ch["name"] != rec_name:
					_fail("%s:%d: %s 块内只能写 %s" % [path, ch["line"], name, rec_name])
				cmds.append(_encode(ch["name"], ch["args"], labels, "%s:%d" % [path, ch["line"]]))
			continue
		cmds.append(_encode(name, args, labels, where))
	return cmds


func _compile(text: String, path: String) -> Dictionary:
	var sc := _parse(text, path)
	if _err != "":
		return {"error": _err}
	var slots: int = int(sc["slots"]) if sc["slots"] != null else int(ops()["kinds"][_kind]["slots"])
	var events: Array = []
	for k in sc["events"]:
		if int(k) >= slots:
			_fail("%s: 事件号超出 events %d" % [path, slots])
	for i in slots:
		events.append(_compile_event(sc["events"].get(i, []), path))
	if _err != "":
		return {"error": _err}
	return {"kind": _kind, "events": events}

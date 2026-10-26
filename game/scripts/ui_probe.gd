# SPDX-License-Identifier: GPL-3.0-only
class_name UiProbe
extends RefCounted
## 界面状态探针 (验收用, Autotest --dump=<帧>:<标签>): 在指定帧把「当前场景 + 界面栈各接收方」的脚本变量
## (布尔/数字/字符串/小数组/向量; 嵌套对象最多 6 层) 打印成一行 JSON, 供 仓库外的开发脚本 对输入脚本逐步断言。
##   UIDUMP {"label":..,"f":帧,"scene":场景脚本名,"stack":[栈上各接收方脚本名],"top":栈顶脚本名,
##           "vars":{"scene.xxx":..,"top.xxx":..,"scene._top.selected":..}, "audio":{..}, "win":{..}}
## 变量路径以 scene (Game.current) 与 top (InputRouter.top()) 开头, 点号逐层深入; 私有变量 (下划线开头) 也在内。

const MAX_DEPTH := 6
const MAX_ARRAY := 16


static func dump(label: String, frame: int) -> void:
	var cur = Game.current
	var out := {"label": label, "f": frame, "scene": _name(cur), "stack": [], "vars": {}}
	for r in InputRouter._stack:
		out["stack"].append(_name(r))
	var top = InputRouter.top()
	out["top"] = _name(top)
	var vars: Dictionary = out["vars"]
	_collect("scene", cur, vars, 0, {})
	_collect("top", top, vars, 0, {})   # 栈顶接收方单独成树 (路径 top.xxx 稳定, 不因 scene 树里先遇到而改名)
	var hd := InputRouter.held_dir()
	out["held"] = [hd.x, hd.y]
	out["router"] = {"stack_n": InputRouter._stack.size(), "overlays": InputRouter._overlays.size(), "touch": InputRouter.touch_mode}
	out["audio"] = audio_state()
	out["win"] = win_state()
	print("UIDUMP " + JSON.stringify(out, "", false, true))


static func _name(o) -> String:
	if o == null or not is_instance_valid(o):
		return "null"
	var s = o.get_script()
	return String(s.resource_path.get_file()) if s else o.get_class()


## 广度优先: 每个对象只在最浅的路径下出现一次 (scene.ctl.input 不会因更深处的别名路径先遇到而丢失)
static func _collect(path: String, root, vars: Dictionary, _depth: int, _seen: Dictionary) -> void:
	var queue: Array = [[path, root, 0]]
	var seen := {}
	var qi := 0
	while qi < queue.size():
		var it: Array = queue[qi]
		qi += 1
		var o = it[1]
		var depth: int = it[2]
		if o == null or not is_instance_valid(o) or o.get_script() == null or depth > MAX_DEPTH:
			continue
		var id: int = o.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		for p in o.get_script().get_script_property_list():
			if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var v = o.get(p.name)
			if typeof(v) == TYPE_OBJECT and not is_instance_valid(v):   # 已 queue_free 的节点 (如刚关闭的菜单)
				continue
			var key: String = "%s.%s" % [it[0], p.name]
			if v == null:
				continue
			if v is bool or v is int or v is float or v is String or v is StringName:
				vars[key] = v if not (v is StringName) else String(v)
			elif v is Vector2 or v is Vector2i:
				vars[key] = [v.x, v.y]
			elif (v is Array and not v.is_empty() and typeof(v[0]) == TYPE_OBJECT and not is_instance_valid(v[0])):
				continue   # 元素已被 queue_free (如刚关闭的菜单文字节点)
			elif v is Array or v is PackedInt32Array or v is PackedStringArray:
				vars[key + "#n"] = v.size()
				if v.size() <= MAX_ARRAY and (v.is_empty() or v[0] is int or v[0] is float or v[0] is String or v[0] is bool):
					vars[key] = Array(v)
				elif v.size() <= MAX_ARRAY and v[0] is Object:  # 对象数组 (如战场状态栈): 记各元素脚本名与变量 key[i].xxx
					vars[key + "#names"] = Array(v).map(func(x): return _name(x))
					for k in mini(v.size(), 6):
						if v[k] is Object and not (v[k] is Resource):
							queue.append(["%s[%d]" % [key, k], v[k], depth + 1])
			elif v is Dictionary:  # 小字典 (≤16 项, 值为标量/小标量数组): 记 key.k (如三选项菜单状态 _menu_state.items)
				if v.size() <= MAX_ARRAY:
					for dk in v:
						var dv = v[dk]
						if dv is bool or dv is int or dv is float or dv is String:
							vars["%s.%s" % [key, str(dk)]] = dv
						elif dv is Array and dv.size() <= MAX_ARRAY and (dv.is_empty() or dv[0] is bool or dv[0] is int or dv[0] is float or dv[0] is String):
							vars["%s.%s" % [key, str(dk)]] = dv
			elif v is Object and not (v is Resource) and not (v is Callable):
				if p.name in ["gc", "ctx", "state"]:
					continue
				vars[key + "#obj"] = _name(v)
				queue.append([key, v, depth + 1])


static func audio_state() -> Dictionary:
	var out := {}
	for b in ["Master", "Music", "SFX"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			out[b] = {"mute": AudioServer.is_bus_mute(i), "db": snappedf(AudioServer.get_bus_volume_db(i), 0.01)}
	var players := []
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	for p in root.find_children("*", "AudioStreamPlayer", true, false):
		var st = p.stream
		players.append({"bus": String(p.bus), "playing": p.playing, "track": p.get_meta("track", -1), "paused": p.stream_paused, "path": st.resource_path if st else "", "pos": snappedf(p.get_playback_position(), 0.01) if p.playing else 0.0, "vol_db": snappedf(p.volume_db, 0.01)})
	out["players"] = players
	return out


static func win_state() -> Dictionary:
	var w: Window = (Engine.get_main_loop() as SceneTree).root
	return {"size": [w.size.x, w.size.y], "mode": int(w.mode), "content_scale": [w.content_scale_size.x, w.content_scale_size.y],
		"aspect": int(w.content_scale_aspect), "gfx": String(Assets.gfx), "tex_mult": Assets.tex_mult, "disp_mult": snappedf(ScreenLayout.display_mult(), 0.01),
		"settings": Game.settings.duplicate()}

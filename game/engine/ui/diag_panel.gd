# SPDX-License-Identifier: GPL-3.0-only
class_name DiagPanel
extends CanvasLayer
## 画质 / 性能诊断页 (设定面板「画质诊断」行打开的模态子面板): 整屏文字, 每 0.5 秒刷新, 点任意处 / 确认 / 取消返回。
## 用途: 手机 / 平板上画面发糊时不连电脑也能看到原因 —— 屏幕与窗口像素、自动选的贴图倍数、生成器是否已失败回退到 1 倍原图、
## 已载入贴图的清晰度分布、显存、帧率。内容同时写进 user://diag.txt (手机在「文件」App 里能取出来)。
## 标签用英文 / 字段名 (截图发给开发者、复制进日志都方便), 只有标题和提示走文案表。

const OUT := "user://diag.txt"
var out_path := OUT   # 测试里改成临时文件, 别覆盖玩家真实的诊断结果
const REFRESH := 0.5
const GUARD := 0.3   # 刚打开时的点按不算 (打开它的那一下点按不能顺手把它关了)

var gc: GameContext
var router   # 统一输入层, 由设定面板传入 (引擎层不直接引用 InputRouter); 测试可换成独立实例

signal closed(save: bool)

var _label: Label
var _age := 0.0
var _t := 0.0
var _frame_ms: Array = []
var _closing := false


## 诊断文字 (一行一项)。info: GameContext.diag_info 给的贴图信息 (Assets.diag_report, 缺项显示 -); frame_ms: 最近若干帧的帧时间 (毫秒), 空则不显示帧时间统计。
## 无窗口 / 无头时各项取到什么显示什么
static func lines(info: Dictionary = {}, frame_ms: Array = []) -> Array:
	var out: Array = []
	out.append("Game      %s" % GameVersion.label())
	var win := DisplayServer.window_get_size()
	var scr := DisplayServer.screen_get_size()
	var mobile := Platform.is_mobile()
	out.append("Godot     %s   %s %s   %s" % [Engine.get_version_info().get("string", "?"), OS.get_name(), OS.get_version(), OS.get_model_name()])
	out.append("GPU       %s" % RenderingServer.get_video_adapter_name())
	out.append("API       %s   %s / %s" % [RenderingServer.get_video_adapter_api_version(), RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])
	out.append("Window    %dx%d px   Screen %dx%d px   scale %.2f   dpi %d" % [win.x, win.y, scr.x, scr.y, DisplayServer.screen_get_scale(), DisplayServer.screen_get_dpi()])
	var vp: Dictionary = info.get("viewport", {})
	if not vp.is_empty():
		out.append("Viewport  logical %s   content scale %s   aspect %s   window mode %s   stretch origin %s scale %s" % [vp["logical"], vp["content"], vp["aspect"], vp["mode"], vp["origin"], vp["scale"]])
		out.append("Mouse     screen %s   window pos %s   -> window px %s   viewport (engine) %s   viewport (expected) %s   delta %s" % [vp["screen_mouse"], vp["win_pos"], vp["win_mouse"], vp["vp_mouse"], vp["vp_expected"], vp["delta"]])
	var m := minf(float(win.x) / 320.0, float(win.y) / 200.0)
	out.append("Mobile    %s   m = min(w/320, h/200) = %.2f   (mobile pick: m<=3.3 -> 3x, <=4.6 -> 4x, else 6x)" % ["yes" if mobile else "no", m])
	out.append("HQ        %s   scale %s   auto %s x   codec '%s'   compressed %s" % [info.get("hq", "-"), info.get("hq_scale", "-"), info.get("auto_scale", "-"), info.get("hq_codec", ""), info.get("hq_compressed", "-")])
	out.append("HQ gen    generated %s   bad readbacks %s   disk cache %s (hits %s, writes %s)" % [info.get("hq_generated", "-"), info.get("hq_bad_readbacks", "-"), info.get("hq_cache", "-"), info.get("hq_cache_hits", "-"), info.get("hq_cache_writes", "-")])
	if bool(info.get("hq_failed", false)):
		out.append("!! FAILED %s  -> pixel art falls back to 1x originals (blurry)" % info.get("hq_fail_reason", ""))
	var sh: Dictionary = info.get("sharp", {})
	var by: Dictionary = sh.get("by_mult", {})
	var ks := by.keys()
	ks.sort()
	var parts: Array = []
	for k in ks:
		parts.append("%dx: %d" % [k, by[k]])
	out.append("Textures  %s loaded   %s   placeholders %s" % [sh.get("total", "-"), "   ".join(parts), sh.get("low", "-")])
	var cr: Dictionary = info.get("cache", {})
	out.append("TexCache  %s MB est   budget %s MB (grown %s)   loads %s   evicted %s   baker queue %s" % [cr.get("mb", "-"), cr.get("budget_mb", "-"), cr.get("budget_grown", "-"), cr.get("loads", "-"), cr.get("evicted", "-"), cr.get("baker_pending", "-")])
	out.append("Limits    max texture side %s   gfx '%s'" % [info.get("max_tex", "-"), info.get("gfx", "-")])
	out.append("VRAM      textures %.0f MB   total %.0f MB   RAM %.0f MB" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		OS.get_static_memory_usage() / 1048576.0])
	var sl: Array = info.get("slow_loads", [])
	if not sl.is_empty():
		var parts2: Array = []
		for e in sl:
			parts2.append("%s %.0f ms" % [String(e["rel"]).get_file() if String(e["rel"]).count("/") < 2 else String(e["rel"]).trim_prefix("Sprite/"), float(e["ms"])])
		out.append("SlowLoad  slowest texture loads: " + "   |   ".join(parts2))
	var fps := "FPS       %d" % Engine.get_frames_per_second()
	if not frame_ms.is_empty():
		var sorted := frame_ms.duplicate()
		sorted.sort()
		var sum := 0.0
		for v in frame_ms:
			sum += float(v)
		fps += "   frame avg %.1f ms   p95 %.1f ms   worst %.1f ms   (last %d frames)" % [sum / frame_ms.size(), float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]), float(sorted[-1]), frame_ms.size()]
	out.append(fps)
	var fr := FrameStats.report()
	if int(fr["frames"]) > 0:
		out.append("Gameplay  %s %d frames: avg %.1f ms   p95 %.1f ms   worst %.1f ms   >25 ms: %d (%d on texture-load frames)   >50 ms: %d" % ["(before this menu)" if fr["frozen"] else "(live)", fr["frames"], fr["avg"], fr["p95"], fr["worst"], fr["slow"], fr["slow_loading"], fr["very_slow"]])
	return out


## 鼠标 / 窗口换算自检: 屏幕鼠标位置 - 窗口客户区位置 = 窗口像素, 再按根窗口的 stretch 变换换回画面坐标, 与引擎实际给事件的画面坐标 (get_mouse_position) 比 ——
## delta 不是 (0, 0) = 引擎的鼠标换算和窗口的真实位置 / 尺寸对不上 (切分辨率 / 桌面缩放后鼠标偏移就看这一行)。鼠标不在窗口里时没有意义
func _viewport_info() -> Dictionary:
	var w := get_window()
	var ft := w.get_final_transform()
	var screen_mouse := DisplayServer.mouse_get_position()
	var win_pos := DisplayServer.window_get_position()
	var win_mouse := Vector2(screen_mouse - win_pos)
	var vp_mouse := get_viewport().get_mouse_position()
	var expected := ft.affine_inverse() * win_mouse
	return {"logical": get_viewport().get_visible_rect().size, "content": w.content_scale_size, "aspect": w.content_scale_aspect, "mode": w.mode,
		"origin": ft.origin.round(), "scale": ft.get_scale().snapped(Vector2(0.001, 0.001)), "screen_mouse": screen_mouse, "win_pos": win_pos, "win_mouse": win_mouse,
		"vp_mouse": vp_mouse.round(), "vp_expected": expected.round(), "delta": (vp_mouse - expected).round()}


## 当前诊断文字: 贴图信息取自 GameContext.diag_info, 再补上设定里的画质档
func current_lines() -> Array:
	var info: Dictionary = gc.diag_info.call() if gc != null and gc.diag_info.is_valid() else {}
	info["gfx"] = gc.settings.get("gfx", "-") if gc != null else "-"
	info["viewport"] = _viewport_info()
	return lines(info, _frame_ms)


## 打开并等到关闭
func open() -> bool:
	layer = 56
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_override("font", UiText.game_font(false))
	_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	add_child(_label)
	_refresh()
	router.push(self, true)
	set_process(true)
	await closed
	router.pop(self)
	_save()
	queue_free()
	return false


func _process(delta: float) -> void:
	_age += delta
	_t += delta
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > 120:
		_frame_ms.pop_front()
	if _t >= REFRESH:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	var h := float(get_viewport().get_visible_rect().size.y)
	var ls := current_lines()
	var size := clampi(int(minf(h * 0.026, h * 0.86 / (ls.size() + 3) / 1.3)), 10, 40)
	_label.add_theme_font_size_override("font_size", size)
	_label.position = Vector2(h * 0.04, h * 0.03)
	_label.text = "%s\n\n%s\n\n%s" % [UiStrings.t("diag.title"), "\n".join(ls), UiStrings.t("diag.hint")]


## 内容写进 user://diag.txt, 手机上从「文件」App 取出来
func _save() -> void:
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(current_lines()) + "\n")


func ui_action(a: UiAction) -> bool:
	if a.echo or _closing or _age < GUARD:
		return true
	if a.is_confirm() or a.is_cancel():   # 鼠标 / 触屏点按也是带坐标的确认
		_closing = true
		closed.emit(false)
	return true

# SPDX-License-Identifier: GPL-3.0-only
class_name HqBaker
extends Node
## 运行时生成 6 倍像素画贴图 (游戏里像素画类贴图的唯一高清来源, 不存文件): 1 倍原图 → 填色 ×FILL_PASSES → hq3x → hq2x → 合 xBRZ 透明通道。
## 算法与当初的离线 6 倍流水线 (已移除) 相同, 只是在 GPU 上跑 (SubViewport 串联, 子视口先于父视口绘制, 一帧出结果)。
## 用法: request() 立即返回一张 ImageTexture (先放占位图), 生成完成后原地 set_image —— 引用它的
## Sprite2D 等自动换成高清图, 调用方无需等待。每帧最多生成 PER_FRAME 张, 余下排队。
## 请求在本帧处理阶段发出、本帧绘制后才生成完, 所以贴图首次出现的那一帧显示占位图 (原图最近邻放大, 即原版像素画样子)。
## 需要真实渲染 (无头模式下没有 GPU 绘制, available() 为 false, 调用方应回退文件档位)。

const SCALE := 6
const FILL_PASSES := 3  # 离线迭代 16 次; 生成结果只用到轮廓外 1~2 个原图像素的填色 (hqx 邻域 + xBRZ 外扩), 3 次足够
const PER_FRAME := 32
const BATCH_PIXELS := 6_000_000  # 单批输出 6 倍像素上限 (一条生成链约 2 个 6 倍 + 1 个 3 倍 RGBA 缓冲, 防大图成批时显存冲高); 至少放 1 张
const READBACK_BUDGET_US := 6000  # 一帧内读回生成结果的时间预算 (微秒), 超了留到下一帧; 帧时间已经偏高时按 SLOW_FRAME_US 减半, 见 _slice_us()
const SLOW_FRAME_US := 18000      # 平滑帧时间超过它 (低于约 55 帧) 就把读回时间片减半, 让位给渲染
const LOW_GAP_FRAMES := 2         # 低优先 (预取) 每烘焙一张后让出几帧: 预取最多约 20 张/秒, 不影响走路
const MAX_COMP_PENDING := 48      # 同时在后台压缩的张数上限 (超了暂停读回, 免得 RGBA8 原图在内存里越堆越多)
const MAX_COMP_BYTES := 256 * 1024 * 1024
const COMP_SWAPS_PER_FRAME := 8   # 每帧最多把几张压缩好的图换进纹理 (上传显存)
const KEEP_IDLE := 4              # 队列清空后保留的空闲生成链数 (其余释放, 余下的缩到最小): 视口缓冲不随池子一直占着显存

## 自动回退: 第一次生成前先拿一张 4x4 自检图跑完整条链, 结果不对 (着色器编译失败 → 视口输出透明/空白、读回异常) 或超过
## timeout_s 秒 (软件渲染/老驱动极慢), 以及之后任何一批读回超过 timeout_s 秒, 就置 failed = true: 不再生成, 已发出的贴图保留最近邻 6 倍占位图
## (原版像素画样子), Assets 对之后的请求直接用 1 倍原图 (不占 36 倍显存), 日志一行 push_warning, 不黑屏不崩溃。
const SELFTEST_SIZE := Vector2i(4, 4)
## 读回校验: 单张读回为空/尺寸不对/有内容的原图读回全透明 (驱动异常) 就保留占位图不写入, 累计 BAD_READBACK_LIMIT 次也置 failed (自检过了但之后个别输出坏的驱动)
const BAD_READBACK_LIMIT := 3

const FILL := preload("res://engine/render/hq/hq_fill.gdshader")
const HQX := preload("res://engine/render/hq/hqx.gdshader")
const XBRZ := preload("res://engine/render/hq/xbrz6_alpha.gdshader")
const DOWN := preload("res://engine/render/hq/hq_down.gdshader")
const LUT2 := preload("res://engine/render/hq/hq2x.png")
const LUT3 := preload("res://engine/render/hq/hq3x.png")

signal idle  # 队列清空 (所有已请求的贴图都已生成)
signal failed_over(reason: String)  # 自检失败/超时: 已停止生成 (只发一次)

var timeout_s := 20.0       # 自检与单批生成的时限 (秒); 命令行 --hq-timeout=秒 (Assets 转交)
var failed := false         # 已回退: 不再生成
var fail_reason := ""
var bad_readbacks := 0      # 读回校验不通过的累计张数 (见 BAD_READBACK_LIMIT)
var generated := 0          # 已成功写回的张数 (perf-log 用)
var shaders := {"fill": FILL, "hqx": HQX, "xbrz": XBRZ, "down": DOWN}  # 测试可替换成坏着色器验证回退
var _tested := false
var _deadline_ms := 0       # 看门狗: 正在进行的自检/批次必须在此之前完成

var out_scale := SCALE   # 输出倍数: 6 (默认, 电脑) / 4 / 3 (低分辨率屏; 流水线仍按 6 倍烘焙, 最后一道 GPU 缩小再读回), Assets 按屏幕注入
var max_comp_pending := MAX_COMP_PENDING   # 手机 CPU 弱: 少排几张, 压缩跟不上就自动暂停读回
var low_gap_frames := LOW_GAP_FRAMES
var codec := ""           # 压缩格式 (TexCodec: bptc/astc/etc2), "" = 不压缩 (Assets 按显卡能力注入)
var cache_on := false    # 磁盘缓存开关 (只在 codec 非空时有意义)
var compressed := 0      # 已压缩换入的张数 (perf-log 用)
var comp_failed := 0     # 压缩失败的张数
var cache_hits := 0      # 磁盘缓存命中张数 (没烘焙)
var cache_writes := 0
var last_bytes := 0      # cache_lookup 最近一次命中的显存字节数 (调用方记账用)
var _sig := ""
var _stop := false      # 退出中: 后台压缩任务直接跳过 (关窗口不能等压缩队列)
var _comp: Array = []    # 后台压缩中的任务 [{id, img, tex, cb, path, ok}]
var _comp_bytes := 0
var _smooth_frame_us := 16000.0   # 平滑后的帧间隔 (微秒)
var _queue: Array = []   # 紧急: 屏幕上要用的 [{img: Image, tex: ImageTexture, md5, cb}]
var _low: Array = []     # 低优先: 预取 (场景载入后慢慢把要用的烘焙好), 紧急队列空了才做; 被屏幕用到会 promote 到紧急
var _free: Array = []    # 空闲的生成链 (Chain), 复用视口
var _busy := false
var _inflight := 0


static func available() -> bool:
	return DisplayServer.get_name() != "headless"


## 看门狗: 自检/批次的协程停在 await 里 (渲染没推进) 时, 靠每帧检查截止时间发现超时
func _process(delta: float) -> void:
	_smooth_frame_us = lerpf(_smooth_frame_us, delta * 1e6, 0.1)
	if _deadline_ms > 0 and not failed and Time.get_ticks_msec() > _deadline_ms:
		_fail("生成超过 %.0f 秒" % timeout_s)
	_drain_comp()


## 本帧读回的时间预算 (微秒): 帧时间已经偏高就减半
func _slice_us() -> int:
	return READBACK_BUDGET_US / 2 if _smooth_frame_us > SLOW_FRAME_US else READBACK_BUDGET_US


func _exit_tree() -> void:
	_stop = true   # 还没开始的压缩任务直接跳过; 已经在跑的 (最多每核一个) 等它们收尾 —— 线程池里没等待的任务在退出时释放回调会崩 (2026-10-20 实测)
	for slot in _comp:
		WorkerThreadPool.wait_for_task_completion(slot["id"])
	_comp.clear()


func _fail(reason: String) -> void:
	if failed:
		return
	failed = true
	fail_reason = reason
	_deadline_ms = 0
	push_warning("HqBaker: %s, 像素画类回退 (已出现的用最近邻 6 倍占位, 之后用 1 倍原图)" % reason)
	failed_over.emit(reason)


## 单张读回结果是否可信: 非空、尺寸 = 原图 x SCALE; 原图有可见像素而输出全透明 (着色器/驱动出错的典型表现) 判坏
static func readback_ok(src: Image, out: Image, scale := SCALE) -> bool:
	if out == null or out.is_empty() or out.get_size() != src.get_size() * scale:
		return false
	if out.is_invisible() and not src.is_invisible():
		return false
	return true


func _note_bad_readback() -> void:
	bad_readbacks += 1
	if bad_readbacks >= BAD_READBACK_LIMIT:
		_fail("读回结果异常 %d 次 (空图/尺寸不符/全透明)" % bad_readbacks)


## 自检图: 左半不透明红、右半透明; 正确的输出 36x... (6 倍) 里红区内部像素仍是红且不透明、右区全透明
static func selftest_image() -> Image:
	var img := Image.create(SELFTEST_SIZE.x, SELFTEST_SIZE.y, false, Image.FORMAT_RGBA8)
	for y in SELFTEST_SIZE.y:
		for x in SELFTEST_SIZE.x:
			img.set_pixel(x, y, Color8(200, 40, 40, 255) if x < 2 else Color8(0, 0, 0, 0))
	return img


static func selftest_ok(out: Image) -> bool:
	if out == null or out.get_size() != SELFTEST_SIZE * SCALE:
		return false
	var a := out.get_pixel(SCALE, SCALE)  # 红区内部 (原图 (1,1) 的左上角附近, 离边界 >= 1 个原图像素)
	if a.a8 != 255 or absi(a.r8 - 200) > 2 or absi(a.g8 - 40) > 2 or absi(a.b8 - 40) > 2:
		return false
	return out.get_pixel(SCALE * 3, SCALE).a8 == 0 and out.get_pixel(SCALE * 3 + 3, SCALE * 3).a8 == 0


## 请求一张 6 倍贴图。img = 1 倍原图 (RGBA8)。返回的纹理先是最近邻占位, 生成后原地替换 (再压缩一次、换成压缩格式)。
## md5 = 原图文件内容的 MD5 (空 = 不进磁盘缓存); on_final = 压缩换入后回调 (tex, 显存字节数), 调用方据此更新记账; low = 低优先 (预取)
func request(img: Image, md5 := "", on_final := Callable(), low := false) -> ImageTexture:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if failed:  # 回退后: 调用方 (Assets) 本不该再请求; 兜底给原图
		return ImageTexture.create_from_image(img)
	var ph := img.duplicate() as Image
	ph.resize(img.get_width() * out_scale, img.get_height() * out_scale, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(ph)
	(_low if low else _queue).append({"img": img, "tex": tex, "md5": md5, "cb": on_final})
	if not _busy:
		_run.call_deferred()
	return tex


## 预取的贴图被屏幕用到了: 提到紧急队列最前面
func promote(tex: Texture2D) -> void:
	for i in _low.size():
		if _low[i]["tex"] == tex:
			_queue.push_front(_low[i])
			_low.remove_at(i)
			return


## 烘焙算法签名 (缓存键的一部分): 倍数、填色次数、三个着色器的源码; 改了任何一个旧缓存自动作废
func signature() -> String:
	if _sig == "":
		var h := hash([out_scale, FILL_PASSES, TexCodec.CACHE_VERSION, (shaders["fill"] as Shader).code, (shaders["hqx"] as Shader).code, (shaders["xbrz"] as Shader).code,
			(shaders["down"] as Shader).code if out_scale != SCALE else ""])
		_sig = "%08x" % (h & 0xffffffff)
	return _sig


func _cache_file(md5: String) -> String:
	return TexCodec.cache_path(md5, signature(), codec)


## 磁盘缓存命中: 返回压缩好的纹理 (不烘焙), 没有返回 null。命中时 last_bytes = 它占的显存字节
func cache_lookup(md5: String) -> ImageTexture:
	if not cache_on or codec == "" or md5 == "":
		return null
	var img := TexCodec.cache_read(_cache_file(md5))
	if img == null:
		return null
	last_bytes = img.get_data_size()
	cache_hits += 1
	return ImageTexture.create_from_image(img)


func pending() -> int:
	return _queue.size() + _low.size() + _inflight + _comp.size()


## 紧急队列 + 在途的张数 (预取据此限流: 它们的占位图在烘焙完成前占着 36 倍显存)
func urgent_pending() -> int:
	return _queue.size() + _inflight


func low_pending() -> int:
	return _low.size()


func _run() -> void:
	if _busy:
		return
	_busy = true
	if not _tested:
		_tested = true
		await _selftest()
	while (not _queue.is_empty() or not _low.is_empty()) and not failed:
		var low := _queue.is_empty()   # 紧急的先做; 只剩预取时一次只烘焙 1 张, 做完让几帧
		var src: Array = _low if low else _queue
		var n := 0
		var px := 0
		var cap := 1 if low else mini(PER_FRAME, src.size())
		while n < cap:
			px += (src[n]["img"] as Image).get_width() * (src[n]["img"] as Image).get_height() * SCALE * SCALE
			if n > 0 and px > BATCH_PIXELS:
				break
			n += 1
		var jobs: Array = src.slice(0, n)
		var rest: Array = src.slice(n)
		if low:
			_low = rest
		else:
			_queue = rest
		var chains: Array = []
		for j in jobs:
			var c: Chain = _free.pop_back() if not _free.is_empty() else _new_chain()
			c.setup(ImageTexture.create_from_image(j["img"]), j["img"].get_size())
			chains.append(c)
		_inflight = jobs.size()
		_deadline_ms = Time.get_ticks_msec() + int(timeout_s * 1000.0)
		await RenderingServer.frame_post_draw
		# 读回 (GPU->CPU->GPU, 每张约 7ms) 按时间片摊到几帧里: 渲染已完成, 视口缓冲留到读回后才释放; 一帧只读回到预算用完, 余下的下一帧接着做 (避免一次读回整批造成顿帧)
		var t0 := Time.get_ticks_usec()
		for i in jobs.size():
			if i > 0 and Time.get_ticks_usec() - t0 > _slice_us():
				await get_tree().process_frame
				t0 = Time.get_ticks_usec()
			while (_comp.size() >= max_comp_pending or _comp_bytes > MAX_COMP_BYTES) and not failed:   # 压缩跟不上: 等它, 别让原图堆在内存里
				_deadline_ms = Time.get_ticks_msec() + int(timeout_s * 1000.0)
				await get_tree().process_frame
				t0 = Time.get_ticks_usec()
			if failed:  # 看门狗已判超时: 余下的不再读回, 保留占位, 链丢弃
				for k in range(i, chains.size()):
					(chains[k] as Chain).queue_free()
				break
			var out: Image = chains[i].result()
			if readback_ok(jobs[i]["img"], out, out_scale):
				(jobs[i]["tex"] as ImageTexture).set_image(out)
				generated += 1
				_start_compress(jobs[i], out)
			else:  # 保留最近邻占位图, 不把空图/错尺寸写进纹理
				push_warning("HqBaker: 读回结果异常, 该张保留占位图")
				_note_bad_readback()
			chains[i].release()
			_free.append(chains[i])
			_inflight -= 1
		_inflight = 0
		_deadline_ms = 0
		if failed:
			break
		if low:
			for _g in low_gap_frames:
				await get_tree().process_frame
	if failed:
		_queue.clear()
		_low.clear()
	_trim_pool()
	_busy = false
	idle.emit()


## 读回的 RGBA8 图交给后台线程压缩 (并写磁盘缓存); 压缩好了 _drain_comp 把它换进纹理
func _start_compress(job: Dictionary, out: Image) -> void:
	if codec == "":
		return
	var slot := {"img": out, "tex": job["tex"], "cb": job["cb"], "ok": false,
		"path": _cache_file(String(job["md5"])) if cache_on and String(job["md5"]) != "" else "", "wrote": false}
	slot["id"] = WorkerThreadPool.add_task(_compress_job.bind(slot), false, "hq compress")
	_comp.append(slot)
	_comp_bytes += out.get_data_size()


func _compress_job(slot: Dictionary) -> void:   # 工作线程
	if _stop:
		return
	var img: Image = slot["img"]
	if TexCodec.compress(img, codec):
		slot["ok"] = true
		if slot["path"] != "":
			slot["wrote"] = TexCodec.cache_write(slot["path"], img)


func _drain_comp() -> void:
	var swaps := 0
	var i := 0
	while i < _comp.size() and swaps < COMP_SWAPS_PER_FRAME:
		var slot: Dictionary = _comp[i]
		if not WorkerThreadPool.is_task_completed(slot["id"]):
			i += 1
			continue
		WorkerThreadPool.wait_for_task_completion(slot["id"])
		_comp.remove_at(i)
		var img: Image = slot["img"]
		var raw_bytes := (slot["tex"] as ImageTexture).get_width() * (slot["tex"] as ImageTexture).get_height() * 4
		_comp_bytes = maxi(0, _comp_bytes - raw_bytes)
		if not slot["ok"]:
			# 压缩失败: 保留已换入的 RGBA8。一张都没成功过就连续失败 (引擎没带压缩器等) -> 关掉压缩, 不再白烧 CPU 刷报错
			comp_failed += 1
			if compressed == 0 and comp_failed >= 3:
				codec = ""
				push_warning("HqBaker: 贴图压缩连续失败, 已关闭压缩与磁盘缓存")
			continue
		(slot["tex"] as ImageTexture).set_image(img)
		compressed += 1
		if slot["wrote"]:
			cache_writes += 1
		swaps += 1
		var cb: Callable = slot["cb"]
		if cb.is_valid():
			cb.call(slot["tex"], img.get_data_size())


## 自检: 4x4 图跑完整条链并核对输出。失败/超时即回退
func _selftest() -> void:
	var t0 := Time.get_ticks_msec()
	var c: Chain = _new_chain(SCALE)   # 自检永远按 6 倍整条链验证 (缩小那道只是线性采样)
	c.setup(ImageTexture.create_from_image(selftest_image()), SELFTEST_SIZE)
	_inflight = 1
	_deadline_ms = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	await RenderingServer.frame_post_draw
	_inflight = 0
	_deadline_ms = 0
	if not failed:
		var out := c.result()
		if not selftest_ok(out):
			_fail("着色器自检失败 (输出不符: 着色器编译失败或驱动不支持)")
		else:
			print("HqBaker: 着色器自检通过, %d ms (含首次编译)" % (Time.get_ticks_msec() - t0))
	c.release()
	if out_scale == SCALE:
		_free.append(c)
	else:
		c.queue_free()   # 自检链没有缩小那一级, 不能进池给 3/4 倍的活用


## 队列清空后收缩生成链池: 多出的释放, 保留的把视口缩到最小 (2x2) (否则池里的链一直按历史最大一张图的尺寸占显存)
func _trim_pool() -> void:
	while _free.size() > KEEP_IDLE:
		(_free.pop_back() as Chain).queue_free()
	for c in _free:
		(c as Chain).shrink()


func pool_size() -> int:
	return _free.size()


func _new_chain(scale := out_scale) -> Chain:
	var c := Chain.new()
	add_child(c)
	c.build(shaders, scale)
	return c


## 一条生成链: 视口嵌套 final ⊃ hq2 ⊃ hq3 ⊃ fill_N ⊃ … ⊃ fill_1, 内层先画, 外层读内层的 ViewportTexture。
class Chain extends Node:
	var _fills: Array[SubViewport] = []
	var _hq3: SubViewport
	var _hq2: SubViewport
	var _final: SubViewport
	var _out: SubViewport      # 输出倍数不是 6 时多一道 GPU 缩小 (最外层); 6 倍时为 null, 读回 _final
	var _scale := SCALE

	func build(sh: Dictionary, out_scale := SCALE) -> void:
		var parent: Node = self
		_scale = out_scale
		if out_scale != SCALE:
			_out = _vp(parent, sh["down"])
			parent = _out
		_final = _vp(parent, sh["xbrz"])
		_hq2 = _vp(_final, sh["hqx"])
		_hq3 = _vp(_hq2, sh["hqx"])
		var p: Node = _hq3
		for i in FILL_PASSES:
			var f := _vp(p, sh["fill"])
			_fills.append(f)
			p = f
		# 嵌套顺序是由外到内建的; _fills[0] 在最外层 (最后一道填色), _fills[-1] 最内层 (读原图)
		var m_hq3 := _mat(_hq3)
		m_hq3.set_shader_parameter("lut", LUT3)
		m_hq3.set_shader_parameter("scale", 3)
		m_hq3.set_shader_parameter("src", _fills[0].get_texture())
		var m_hq2 := _mat(_hq2)
		m_hq2.set_shader_parameter("lut", LUT2)
		m_hq2.set_shader_parameter("scale", 2)
		m_hq2.set_shader_parameter("src", _hq3.get_texture())
		_mat(_final).set_shader_parameter("color6", _hq2.get_texture())
		if _out != null:
			_mat(_out).set_shader_parameter("src", _final.get_texture())
		for i in FILL_PASSES - 1:
			_mat(_fills[i]).set_shader_parameter("src", _fills[i + 1].get_texture())

	func setup(orig: Texture2D, size: Vector2i) -> void:
		_mat(_fills[-1]).set_shader_parameter("src", orig)
		_mat(_final).set_shader_parameter("orig", orig)
		for f in _fills:
			_resize(f, size)
		_resize(_hq3, size * 3)
		_resize(_hq2, size * SCALE)
		_resize(_final, size * SCALE)
		if _out != null:
			_resize(_out, size * _scale)

	func result() -> Image:
		return (_out if _out != null else _final).get_texture().get_image()

	func shrink() -> void:
		for vp in _fills + [_hq3, _hq2, _final] + ([_out] if _out != null else []):
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			vp.size = Vector2i(2, 2)  # SubViewport 最小 2x2

	func release() -> void:
		_mat(_fills[-1]).set_shader_parameter("src", null)
		_mat(_final).set_shader_parameter("orig", null)

	static func _mat(vp: SubViewport) -> ShaderMaterial:
		return (vp.get_child(0) as ColorRect).material as ShaderMaterial

	func _vp(parent: Node, shader: Shader) -> SubViewport:
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var r := ColorRect.new()
		var m := ShaderMaterial.new()
		m.shader = shader
		r.material = m
		vp.add_child(r)
		parent.add_child(vp)
		return vp

	static func _resize(vp: SubViewport, size: Vector2i) -> void:
		vp.size = size
		(vp.get_child(0) as ColorRect).size = Vector2(size)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE

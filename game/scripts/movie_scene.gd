# SPDX-License-Identifier: GPL-3.0-only
class_name MovieScene
extends Control
## 依次播放过场视频, 全部播完后调用 on_done。跳过键由 skip 决定 ("confirm" / "cancel" 的子集, 缺省两者都跳过):
## 原版: Esc (及 Delete) 恒可跳过, 回车只在启动参数 字段 = 1 时跳过 (诸物炼化只认取消键)。

signal done

## 过场视频的音量增益 (dB)。原版 实测 (Bink 经 Miles 播放, 抓 PulseAudio 输出与离线解码的 Bink 音轨最小二乘对齐):
## 视频声音比同一音轨的离线解码 (ffmpeg binkaudio, 复刻 Vorbis 即由它转出) 响 +5.74 dB (增益 1.94, 左右声道相同, 约 2% 采样削波); 复刻 Vorbis 本身比 Bink 解码低 0.2 dB, 削波后整段 rms 对齐再补 +0.26 => 6.2,
## 而音乐 mp3 实测增益 0.997 (±0 dB)、音效 wav 无音量调用 (无 AIL_set_sample_volume 导入) 为原样。
const VIDEO_GAIN_DB := 6.2

var _queue: Array = []
var _on_done: Callable
var _skip: Array = ["confirm", "cancel"]
var _player: VideoStreamPlayer
var _layer: CanvasLayer   # 最高层画布: 铺满全屏的黑底 + 视频, 盖住下面的场景与界面层 (宽屏全屏时两侧不再露出下面的贴图)

## 视频层的画布层号: 高于战场/营地的界面层 (30/31/40) 与设定面板 (54/55)
const VIDEO_LAYER := 100


static func create(movies: Array, on_done: Callable, skip: Array = ["confirm", "cancel"]) -> Control:
	var s: Control = (load("res://scripts/movie_scene.gd") as GDScript).new()
	s._skip = skip.duplicate()
	s._queue = movies.duplicate()
	s._on_done = on_done
	return s


func _ready() -> void:
	size = UiLayout.base_size() * Assets.SCALE  # 原版画面 x 倍数 (1280x800)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 本控件只是播放队列的壳, 画面都在下面的视频层里
	# 视频是 16:10, 全屏宽屏时屏幕比视频宽: 多出来的部分不能露出下面的场景 (营地/战场的边缘镜像贴图很难看)。
	# 所以视频放进自己的最高层画布, 先铺一块盖满整个窗口的黑底, 视频再按安全区居中画在黑底上
	_layer = CanvasLayer.new()
	_layer.layer = VIDEO_LAYER
	add_child(_layer)
	ScreenLayout.bind_layer(_layer, ScreenLayout.SAFE)  # 视频按安全区居中
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP   # 播放期间点击不穿透到下面的界面 (点击由统一输入层跳过视频)
	_layer.add_child(backdrop)
	ScreenLayout.cover(backdrop)
	_player = VideoStreamPlayer.new()
	_player.bus = "Master"   # 不走 Music 总线: 原版 实测音乐开关关掉/音效开关关掉时过场视频声音都照常播 (同一电平 -7.6 dBFS)
	_player.volume_db = VIDEO_GAIN_DB
	_player.expand = true
	_player.size = size
	_player.finished.connect(func():
		print("视频播完")
		_next())
	_layer.add_child(_player)
	InputRouter.push(self)
	_next()


func _next() -> void:
	if _queue.is_empty():
		InputRouter.pop(self)
		done.emit()
		_on_done.call()
		return
	var name: String = _queue.pop_front()
	if Game.skip_movies:
		print("跳过视频 ", name)
		_next.call_deferred()
		return
	if not Assets.movie_exists(name):  # 视频包缺失/文件不存在 (classic_movies / hd_movies 都没装): 跳过这一段, 不然播放器永远等不到 finished, 画面黑着卡死
		push_warning("找不到视频 %s, 跳过" % name)
		_next.call_deferred()
		return
	_player.stream = Assets.movie(name)
	print("播放视频 %s (%s)" % [name, _player.stream.file])
	_player.play()
	if not _player.is_playing():  # 文件打不开/解码失败: finished 永远不会来, 不跳过这段整个演出 (及等它的协程) 会卡死
		push_warning("视频无法播放: " + name)
		_next.call_deferred()


func _exit_tree() -> void:
	InputRouter.pop(self)  # 中途被释放 (换场景/退出) 也要出栈, 不等 _prune 兜底


## 这个动作是否跳过当前段
func skips(a: UiAction) -> bool:
	return not a.echo and ((a.is_confirm() and "confirm" in _skip) or (a.is_cancel() and "cancel" in _skip))


## 统一输入层: 确认或取消跳过当前这段; 播放期间在界面栈顶
func ui_action(a: UiAction) -> bool:
	if skips(a):
		print("视频被跳过 (%s)" % a.kind)
		_player.stop()
		_next()
	return true

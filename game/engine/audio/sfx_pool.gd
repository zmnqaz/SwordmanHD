# SPDX-License-Identifier: GPL-3.0-only
class_name SfxPool
extends Node
## 音效声部池 (全局, 与场景/动画节点的寿命无关)。对照原版: 最多 12 个同时播放的声部; 每次播放先回收已播完的, 再取第一个空位开新声部,
##   已在播的**不被打断**, 叠加混音; 12 个都在播时新音效被丢弃。声部与触发它的动画对象无关: 动画对象销毁 / 换场景后音效照放完。
## 复刻原先每个 AnimPlayer 一个播放器, 新音效 play() 会把上一个从头截断 (密集触发处听感被截断), 且节点释放时音效被腰斩。
## 用法: SfxPool.play(stream) -> 是否开始播放 (声部满则 false)。

const VOICES := 12

static var _inst: SfxPool


static func play(stream: AudioStream) -> bool:
	if stream == null:
		return false
	return _instance().play_stream(stream)


static func _instance() -> SfxPool:
	if _inst == null or not is_instance_valid(_inst):
		_inst = SfxPool.new()
		_inst.name = "SfxPool"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


## 当前正在播放的声部数 (测试/探针用)
static func busy() -> int:
	if _inst == null or not is_instance_valid(_inst):
		return 0
	var n := 0
	for p in _inst._players:
		if p.playing:
			n += 1
	return n


var _players: Array[AudioStreamPlayer] = []


func _init() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		_players.append(p)
		add_child(p)


var _pending: Array = []   # 池节点还没进场景树时 (第一次播放在同一帧里 add_child 之前) 先排队, _ready 后播


func _ready() -> void:
	for st in _pending:
		_play_now(st)
	_pending.clear()


func play_stream(stream: AudioStream) -> bool:
	if not is_inside_tree():
		_pending.append(stream)
		return true
	return _play_now(stream)


func _play_now(stream: AudioStream) -> bool:
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.play()
			return true
	return false

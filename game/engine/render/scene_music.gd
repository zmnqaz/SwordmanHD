# SPDX-License-Identifier: GPL-3.0-only
class_name SceneMusic
extends RefCounted
## 场景里的音乐通道 (战场/城镇剧情共用): 通道号 -> AudioStreamPlayer。
## 原版语义: 载入只把曲子装进通道不播放, 播放另有指令 (fade=1 淡入), 暂停/继续/关闭按通道。

const FADE_IN_SECS := 1.0  # 淡入时长原版未测

var _host: Node
var _players := {}


func _init(host: Node) -> void:
	_host = host


func load_track(ch: int, num: int) -> void:
	var rel := ThemeAssets.f("music", [num])
	if not Assets.exists(rel):
		push_warning("没有音乐 " + rel)
		return
	var s := Assets.music(rel)
	if s == null:
		return
	var p: AudioStreamPlayer = _players.get(ch)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = "Music"
		_host.add_child(p)
		_players[ch] = p
	p.stop()
	p.remove_meta("resume_pos")
	p.stream = s
	p.set_meta("track", num)   # 验收探针 (scripts/ui_probe.gd) 读: 通道里当前是哪首 Music_NN.mp3
	p.stream_paused = false
	p.volume_db = 0


func start(ch: int, fade := 0) -> void:
	var p: AudioStreamPlayer = _players.get(ch)
	if p == null or p.stream == null:
		return
	p.stream_paused = false
	if fade == 1:
		p.volume_db = -40.0
		p.play()
		_host.create_tween().tween_property(p, "volume_db", 0.0, FADE_IN_SECS)
	else:
		p.volume_db = 0
		p.play()


## 载入并立即播放 (场景开场的背景音乐)
func play(ch: int, num: int) -> void:
	load_track(ch, num)
	start(ch)


func close(ch: int) -> void:
	var p: AudioStreamPlayer = _players.get(ch)
	if p != null:
		p.stop()
		p.remove_meta("resume_pos")
		p.stream = null


## 暂停 / 继续。继续时如果这个通道是被 stop_all 停掉的 (放过场视频时), 从停下的位置接着放, 不然只取消暂停标志、什么也不响
func pause(ch: int, paused: bool) -> void:
	var p: AudioStreamPlayer = _players.get(ch)
	if p == null:
		return
	p.stream_paused = paused
	if not paused and p.stream != null and not p.playing and p.has_meta("resume_pos"):
		p.play(float(p.get_meta("resume_pos")))
		p.remove_meta("resume_pos")


## 停掉所有通道 (放过场视频等, 视频自带声音)。正在播的记下位置, 之后该通道收到「继续」会接着放 (原版开场: 先放视频, 再暂停/载入别的曲子, 最后继续战斗曲)
func stop_all() -> void:
	for p in _players.values():
		if p.playing:
			p.set_meta("resume_pos", p.get_playback_position())
		p.stop()


## 场景离开 / 退出时停掉并摘掉流, 否则退出时 MP3 播放对象被音频线程占着, 报 ObjectDB 泄漏
func release() -> void:
	for p in _players.values():
		if is_instance_valid(p):
			p.stop()
			p.stream = null

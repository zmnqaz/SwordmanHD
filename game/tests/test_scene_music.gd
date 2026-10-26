# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 场景音乐通道 (SceneMusic): 放过场视频会 stop_all, 之后剧本「暂停 → 继续」要让被停掉的战斗曲接着放
## (第 0 关开场: 战斗曲先放, 视频停掉所有音乐, 暂停通道 0, 载入别的曲子, 最后继续通道 0; 以前继续只取消暂停标志, 战斗曲永远没声音)。


func _wav() -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 22050
	var b := PackedByteArray()
	b.resize(22050 * 2 * 5)   # 5 秒静音
	s.data = b
	return s


func _channel(m: SceneMusic, host: Node, ch: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	host.add_child(p)
	p.stream = _wav()
	m._players[ch] = p
	return p


func test_resume_after_stop_all_continues_playing():
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var m := SceneMusic.new(host)
	var p := _channel(m, host, 0)
	m.start(0)
	check(p.playing, "通道 0 开始播放")
	m.stop_all()
	check(not p.playing, "放视频: 全部停掉")
	m.pause(0, true)
	m.pause(0, false)
	check(p.playing, "暂停 → 继续后接着放 (以前只取消暂停标志, 没声音)")
	m.release()
	host.free()


func test_resume_does_not_start_never_played_or_closed_channels():
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var m := SceneMusic.new(host)
	var p := _channel(m, host, 0)
	m.pause(0, true)
	m.pause(0, false)
	check(not p.playing, "载入了没开始播的通道, 继续不会自己响 (原版: 载入不播放)")
	var q := _channel(m, host, 1)
	m.start(1)
	m.stop_all()
	m.close(1)
	m.pause(1, false)
	check(not q.playing, "已关闭的通道继续不响")
	m.release()
	host.free()

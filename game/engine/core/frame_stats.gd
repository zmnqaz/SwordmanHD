# SPDX-License-Identifier: GPL-3.0-only
class_name FrameStats
extends RefCounted
## 游戏自己记的逐帧耗时 (真实时钟, 不受 Engine.time_scale 影响): 最近 RING 帧的环形缓冲, 画质诊断页 (engine/ui/diag_panel.gd) 显示平均 / p95 / 最差和超过 25 / 50 ms 的帧数。
## 用途: 「感觉不流畅」要有数字 —— 在这台机器和另一台机器上各玩一会儿再打开诊断页对比, 不依赖看画面的方式 (远程桌面 / 采集会改变观感)。
## 设定面板打开时先 freeze() 拷一份, 诊断页读冻结的那份: 看到的是打开菜单之前玩的那段, 不混进菜单本身的帧。组装层 (Game._process) 每帧 record()。

const RING := 900          # 约 15 秒 (60 帧/秒)
const SLOW_MS := 25.0
const VERY_SLOW_MS := 50.0

static var _ring := PackedFloat32Array()
static var _load_ring := PackedByteArray()   # 与 _ring 同位置: 这一帧里有没有载入新贴图 (1 = 有), 判断慢帧是不是贴图加载造成的
static var _last_loads := -1
static var _n := 0         # 已记录总数 (环形写指针 = _n % RING)
static var _last_us := 0
static var _frozen: Array = []   # 冻结的拷贝 (毫秒, 按时间顺序); 空 = 没冻结
static var _frozen_loads: Array = []


## 每帧调用一次: 取与上一帧的真实时间差。loads = 累计载入贴图数 (Assets.loads), 比上一帧多了就算「这一帧载入了新贴图」
static func record(loads := -1) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		record_ms((now - _last_us) / 1000.0, loads >= 0 and _last_loads >= 0 and loads > _last_loads)
	_last_us = now
	_last_loads = loads


## 记一帧 (毫秒); 测试直接用它
static func record_ms(ms: float, loaded := false) -> void:
	if _ring.size() != RING:
		_ring.resize(RING)
		_load_ring.resize(RING)
	_ring[_n % RING] = ms
	_load_ring[_n % RING] = 1 if loaded else 0
	_n += 1


## 当前缓冲里的帧时间, 按时间顺序
static func frames() -> Array:
	var out: Array = []
	var cnt := mini(_n, RING)
	var start := _n - cnt
	for i in cnt:
		out.append(_ring[(start + i) % RING])
	return out


## 同 frames(), 每帧 1 / 0: 这一帧里有没有载入新贴图
static func load_flags() -> Array:
	var out: Array = []
	var cnt := mini(_n, RING)
	var start := _n - cnt
	for i in cnt:
		out.append(int(_load_ring[(start + i) % RING]))
	return out


## 拷一份冻结 (设定面板打开时); unfreeze 放开
static func freeze() -> void:
	_frozen = frames()
	_frozen_loads = load_flags()


static func unfreeze() -> void:
	_frozen = []
	_frozen_loads = []


## 统计: 冻结了就用冻结的那份, 否则用实时缓冲。frames = 帧数, avg / p95 / worst 毫秒, slow = > 25 ms 的帧数, very_slow = > 50 ms 的帧数
static func report() -> Dictionary:
	var f: Array = _frozen if not _frozen.is_empty() else frames()
	var lf: Array = _frozen_loads if not _frozen.is_empty() else load_flags()
	if f.is_empty():
		return {"frames": 0, "avg": 0.0, "p95": 0.0, "worst": 0.0, "slow": 0, "very_slow": 0, "slow_loading": 0, "frozen": not _frozen.is_empty()}
	var sorted := f.duplicate()
	sorted.sort()
	var sum := 0.0
	var slow := 0
	var very := 0
	var slow_loading := 0
	for i in f.size():
		var v = f[i]
		sum += float(v)
		if float(v) > SLOW_MS:
			slow += 1
			if i < lf.size() and int(lf[i]) == 1:
				slow_loading += 1
		if float(v) > VERY_SLOW_MS:
			very += 1
	return {"frames": f.size(), "avg": sum / f.size(), "p95": float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]), "worst": float(sorted[-1]),
		"slow": slow, "very_slow": very, "slow_loading": slow_loading, "frozen": not _frozen.is_empty()}


## 测试清场
static func reset() -> void:
	_ring = PackedFloat32Array()
	_load_ring = PackedByteArray()
	_last_loads = -1
	_n = 0
	_last_us = 0
	_frozen = []
	_frozen_loads = []

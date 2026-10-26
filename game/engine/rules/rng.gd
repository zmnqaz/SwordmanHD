# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 规则用随机数。所有规则只通过 rand() 取数 (0..32767, 同 MSVC CRT rand),
## 几率判定一律 rand() % 100 < p。
## 默认实现 = MSVC rand 的线性同余 (seed*214013+2531011, 取 bit16..30), 同种子可复现。
## 测试用 Scripted 子类按队列给出指定值。

var _state: int = 1


func _init(seed_value: int = 1) -> void:
	_state = seed_value & 0xFFFFFFFF


func set_seed(seed_value: int) -> void:
	_state = seed_value & 0xFFFFFFFF


## 内部状态 (确定性回归把它算进状态哈希: 随机数取用次数不同会立即显出)
func get_state() -> int:
	return _state


## 0..32767
func rand() -> int:
	_state = (_state * 214013 + 2531011) & 0xFFFFFFFF
	return (_state >> 16) & 0x7FFF


## rand() % n  (n > 0)
func mod(n: int) -> int:
	return rand() % n


## rand()%100 < pct
func chance(pct: int) -> bool:
	return rand() % 100 < pct

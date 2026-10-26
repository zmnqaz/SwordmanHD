# SPDX-License-Identifier: GPL-3.0-only
extends RefCounted
## 16 位字段读写: HP/HPmax 按 u16 读, MP/MPmax/五项属性按 s16 读, 写回都是 16 位加法 (回绕)


static func u16(v: int) -> int:
	return v & 0xFFFF


static func s16(v: int) -> int:
	return ((v & 0xFFFF) ^ 0x8000) - 0x8000


## HP 回复量封顶: hp + h > hpmax 则取 hpmax - hp (u16 读; hp > hpmax 时为负, 把 HP 拉回上限)
static func clamp_hp_gain(h: int, hp: int, hp_max: int) -> int:
	var a := u16(hp)
	var m := u16(hp_max)
	return m - a if a + h > m else h


## MP 回复量封顶: 同上, 但 MP/MPmax 是 s16 (MPmax > 32767 读成负数)
static func clamp_mp_gain(h: int, mp: int, mp_max: int) -> int:
	var a := s16(mp)
	var m := s16(mp_max)
	return m - a if a + h > m else h

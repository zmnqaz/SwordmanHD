# SPDX-License-Identifier: GPL-3.0-only
class_name UiDigits
extends RefCounted
## 原版数字串格式。字模数字的绘制统一由 UiNumber (UiLayout.number 按布局表 digits 字段建: 素材帧、步进、空格、「?」格号) 完成,
## 这里只剩原版 sprintf 的格式规则。


## 原版 sprintf("%Nd") 的结果; 超过 9999 时原版写 "????"
static func fmt(v: int, width: int) -> String:
	if width >= 4 and v > 9999:
		return "????"
	var s := str(v)
	return " ".repeat(maxi(0, width - s.length())) + s

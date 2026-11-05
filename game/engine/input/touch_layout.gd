# SPDX-License-Identifier: GPL-3.0-only
class_name TouchLayout
extends RefCounted
## 手机虚拟键的布局 (设定键 touch_layout, 非行; 「控制器设置 → 触屏键位置」进 TouchPad 的编辑模式拖动修改, 2026-11-04 用户要求):
##   alpha = 不透明度 (百分比 ALPHA_MIN~100), size = 整套键的大小 (百分比 SIZE_MIN~SIZE_MAX, 100 = 原来的尺寸),
##   pos = {键名: [x, y]} 各键中心在可用区域 (窗口去掉系统安全区) 里的比例位置 (0~1), 没有的键按缺省排法。
## 存比例而不是像素: 换分辨率 / 横竖屏 / 平板黑边都还在原来的相对位置。

const ALPHA_DEF := 90
const ALPHA_MIN := 20
const SIZE_DEF := 100
const SIZE_MIN := 60
const SIZE_MAX := 160
## 可拖动的键 (TouchPad 里的键与名字一一对应, 见 TouchPad.NAME_OF)
const NAMES := ["stick", "confirm", "cancel", "toggle", "settings", "speed"]


static func defaults() -> Dictionary:
	return {"alpha": ALPHA_DEF, "size": SIZE_DEF, "pos": {}}


## 任意来源 (设定文件的 JSON) 校正成合法布局: 缺的、类型不对的取缺省, 数值夹到范围里; 返回新字典
static func sanitize(v) -> Dictionary:
	var out := defaults()
	if not (v is Dictionary):
		return out
	var a = v.get("alpha")
	if a is int or a is float:
		out["alpha"] = clampi(roundi(a), ALPHA_MIN, 100)
	var s = v.get("size")
	if s is int or s is float:
		out["size"] = clampi(roundi(s), SIZE_MIN, SIZE_MAX)
	var pos = v.get("pos")
	if pos is Dictionary:
		for n in NAMES:
			var p = pos.get(n)
			if p is Array and p.size() == 2 and (p[0] is int or p[0] is float) and (p[1] is int or p[1] is float):
				out["pos"][n] = [clampf(float(p[0]), 0.0, 1.0), clampf(float(p[1]), 0.0, 1.0)]
	return out

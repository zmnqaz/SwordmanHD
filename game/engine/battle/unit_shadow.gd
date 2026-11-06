# SPDX-License-Identifier: GPL-3.0-only
class_name UnitShadow
extends RefCounted
## 战场单位脚下的影子。原版 (Win10 原生逐帧截图实测, S1): 每个单位脚下一个黑色半透明椭圆,
## 精灵 SAF 的行走 / 站立帧里没有 (只有 man055 带 type 1 部件, 它是在标准影子之上再叠一层), 是画单位时另外画的。
## 形状固定: 宽 32、高 14 原版像素, 相对格子 (30x24) 左上: x ∈ [-1, 31)、y ∈ [12, 26), 中心 (15, 19);
## 位置**跟格子不跟精灵** (96 个精灵实测与身体包围盒无关, 同一精灵各站立帧影子不动), 走路时跟逻辑位置。黑色, alpha ≈ 0.55; 边缘软渐变约 2.4 原版像素 (smoothstep)。
## 站立位置那一帧没有可见部件的精灵 (163 头 / 165 黑龙) 没有影子。

## 形状参数都在布局表 map.unit.shadow (mod 可改), 缺表时用上面的原版实测值。
## 实测逐行宽度 (12..25 行: 14 22 26 28 29 ... ) 比正圆更方: 超椭圆 |x|^N + |y|^N = 1, N=2.3 与实测各行宽度吻合 (误差 < 1 像素)
static func size() -> Vector2i:
	var v = UiLayout.val("map.unit.shadow", "size", [32, 14])
	return Vector2i(int(v[0]), int(v[1]))   # 原版像素


static func center() -> Vector2:   # 影子中心, 相对格子左上 (单位节点原点)
	var v = UiLayout.val("map.unit.shadow", "center", [15, 19])
	return Vector2(float(v[0]), float(v[1]))


static func alpha() -> float:
	return float(UiLayout.val("map.unit.shadow", "alpha", 0.55))


static func exponent() -> float:
	return float(UiLayout.val("map.unit.shadow", "exponent", 2.3))


static func edge() -> float:   # 边缘软渐变宽度 (原版像素)
	return float(UiLayout.val("map.unit.shadow", "edge", 2.4))

## 贴图按布局放大倍数 (Assets.SCALE, 原版 320x200 -> 1280x800 恒为 4) 做高分辨率, 节点再缩回 1/SUPERSAMPLE: 边缘在放大后仍平滑, 不是 32x14 的色块放大
## (engine/ 对 Assets 的引用数有上限, 这里不直接取; 测试核对两者相等)
const SUPERSAMPLE := 4
static var _tex: ImageTexture


## 椭圆贴图 (黑色, 边缘抗锯齿约 1 原版像素; 半透明由节点的 modulate 给): 一张全局共用, 尺寸 size()*SUPERSAMPLE
static func texture() -> ImageTexture:
	if _tex == null:
		var sz := size()
		var n := exponent()
		var w := sz.x * SUPERSAMPLE
		var h := sz.y * SUPERSAMPLE
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var band := edge() / (sz.y / 2.0)   # 过渡带 ~2.4 原版像素 (归一化到半高): 原版阴影贴图边缘分 0.62 / 0.88 / 1.0 几档渐变, 软边
		for y in h:
			for x in w:
				var dx := absf(x + 0.5 - w / 2.0) / (w / 2.0)
				var dy := absf(y + 0.5 - h / 2.0) / (h / 2.0)
				var d := pow(pow(dx, n) + pow(dy, n), 1.0 / n)   # 1 = 椭圆边
				var t := clampf((1.0 - d) / band + 0.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(0, 0, 0, t * t * (3.0 - 2.0 * t)))   # smoothstep: 边缘平滑渐变到 0, 中心保持满
		_tex = ImageTexture.create_from_image(img)
	return _tex


## 这个精灵有没有影子: 站立位置那一帧 (引擎站立时取的那一帧, BattleUnit._play_act: base = 2 + 胜利帧数 (没有取 1)) 有可见部件。
## 没有站立帧的单位 (167 / 168 / 170) 这一帧里有一块 30x24 部件, 照样有影子; 头 / 黑龙 (163 / 165) 这一帧是空的, 原版没有影子
static func has_picture(data: Dictionary) -> bool:
	var c: Array = data.get("action_counts", [])
	if c.size() < 5:
		return false
	var base := 2 + (int(c[4]) if int(c[4]) > 0 else 1)
	var frames: Array = data.get("frames", [])
	if base >= frames.size():
		return false
	for p in frames[base]["parts"]:
		if p["tex"] != null:
			return true
	return false

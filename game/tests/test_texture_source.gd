# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## TextureSource (engine/render/texture_source.gd): 档位注册、逐张选档与回退收敛后的单元测试
## 。不依赖 Assets/窗口/命令行: 临时目录里造假贴图与清单, 目标倍数与高清开关注入固定值。

var _want := 4.0      # want_mult 注入的固定值
var _hd_on := true    # hd_enabled 注入的固定值
var _base := ""       # 本测试的临时目录 (user:// 下, CI 每次隔离)


func _mk_dirs(paths: Array) -> void:
	for p in paths:
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p))
		check(err == OK, "建临时目录 %s (%d)" % [p, err])


func _img(path: String, px: int) -> void:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	check(img.save_png(path) == OK, "写测试贴图 " + path)


## orig + hd4 (+hd6) 三档, hd4 有 a/t.png 与 b.png, hd6 只有 a/t.png (模拟 hd6x 是子集: 人物有、大图没有)
func _source(with_hd6: bool) -> TextureSource:
	_base = "user://texsrc_test/%d" % Time.get_ticks_usec()
	_mk_dirs([_base + "/orig/a", _base + "/hd4/a", _base + "/hd6/a"])
	_img(_base + "/orig/a/t.png", 2)
	_img(_base + "/hd4/a/t.png", 8)
	_img(_base + "/hd4/b.png", 8)
	if with_hd6:
		_img(_base + "/hd6/a/t.png", 12)
	_hd_on = true
	_want = 4.0
	var s := TextureSource.new()
	s.orig_dir = _base + "/orig"
	s.hd_enabled = func() -> bool: return _hd_on
	s.want_mult = func() -> float: return _want
	s.add_tier(4, _base + "/hd4", {"a/t.png": true, "b.png": true})
	if with_hd6:
		s.add_tier(6, _base + "/hd6", {"a/t.png": true})
	return s


func test_pick_smallest_tier_not_below_want():
	var s := _source(true)
	var rel := "a/t.png"
	_want = 4.0
	var t := s.pick(rel)
	eq(int(t["mult"]), 4, "显示 4 倍选 hd4x")
	check(bool(t["hd"]), "hd4x 是高清")
	near(float(t["scale"]), 0.25, 0.0001, "scale = 1/倍数")
	eq(String(t["file"]), _base + "/hd4/a/t.png", "文件在 hd4 档目录")
	_want = 6.0
	eq(int(s.pick(rel)["mult"]), 6, "显示 6 倍选 hd6x")
	_want = 5.4
	eq(int(s.pick(rel)["mult"]), 6, "1080p (5.4 倍) 也选 hd6x")
	_want = 4.003
	eq(int(s.pick(rel)["mult"]), 4, "窗口 1281 宽 (4.003 倍) 仍算 4 档 (余量 EPS)")
	_want = 4.02
	eq(int(s.pick(rel)["mult"]), 6, "刚过余量就升 6 档 (与旧阈值 4.01 两侧一致)")


func test_fallback_to_lower_tier_then_original():
	var s := _source(true)
	_want = 6.0
	var t := s.pick("b.png")
	eq(int(t["mult"]), 4, "b 没有 6 倍档, 回退 hd4x (AI 类大图同理)")
	eq(String(t["file"]), _base + "/hd4/b.png", "回退档文件在 hd4 目录")
	t = s.pick("c.png")
	eq(int(t["mult"]), 0, "三档都没有 -> 原图")
	check(not bool(t["hd"]), "原图按 1 倍最近邻")
	near(float(t["scale"]), 1.0, 0.0001, "原图 scale=1")
	eq(String(t["file"]), _base + "/orig/c.png", "文件在原图目录")
	_hd_on = false
	eq(int(s.pick("a/t.png")["mult"]), 0, "原版画质 (--gfx=orig) 一律原图")


func test_webp_preference_only_for_hd_tiers():
	var s := _source(true)
	check(Image.create(8, 8, false, Image.FORMAT_RGBA8).save_webp(_base + "/hd4/a/t.webp", true) == OK, "写 webp")
	_want = 4.0
	eq(String(s.pick("a/t.png")["file"]), _base + "/hd4/a/t.webp", "高清档同路径有 webp 优先用")
	eq(String(s.file_at("a/t.png", 0)), _base + "/orig/a/t.png", "原图档不做 webp 偏好 (used_rect 的 1 倍帧框)")


func test_tier_registry_and_order():
	var s := _source(true)
	eq(s.tier_mults(), [4, 6] as Array[int], "已注册档位")
	eq(s.tier_size(4), 2, "hd4 清单条数")
	eq(s.tier_size(6), 1, "hd6 清单条数")
	eq(s.tier_size(8), 0, "未注册档为 0")
	var s2 := TextureSource.new()  # 乱序注册也保持升序 (未来加 hd2x/hd8x 不用关心注册顺序)
	s2.add_tier(6, "", {})
	s2.add_tier(4, "", {})
	eq(s2.tier_mults(), [4, 6] as Array[int], "add_tier 按 mult 升序插入")


func test_without_want_mult_stays_at_lowest_tier():
	_base = "user://texsrc_test/bare"
	_mk_dirs([_base + "/orig/a", _base + "/hd4/a", _base + "/hd6/a"])
	_img(_base + "/hd4/a/t.png", 8)
	_img(_base + "/hd6/a/t.png", 12)
	var s := TextureSource.new()
	s.orig_dir = _base + "/orig"
	s.add_tier(4, _base + "/hd4", {"a/t.png": true})
	s.add_tier(6, _base + "/hd6", {"a/t.png": true})
	eq(int(s.pick("a/t.png")["mult"]), 4, "没注入目标倍数就停在最低档 (安全缺省, 不误升高档)")


## 手机把运行时烘焙档降成 4 倍时与 AI 类 hd4x 的 4 倍档同倍数: 各取清单里有这张图的那一档, 不能把 AI 图当成运行时生成
func test_same_multiplier_tiers_resolve_by_index() -> void:
	var ts := TextureSource.new()
	ts.orig_dir = "/orig"
	ts.add_tier(4, "/hd4", {"Face/a.png": true})
	ts.add_tier(4, "", {"Sprite/b.png": true}, true)
	var a := ts.pick("Face/a.png")
	check(not bool(a["gen"]) and String(a["file"]).begins_with("/hd4"), "AI 图走 hd4x 档: %s" % [a])
	var b := ts.pick("Sprite/b.png")
	check(bool(b["gen"]) and int(b["mult"]) == 4 and absf(float(b["scale"]) - 0.25) < 1e-9, "像素画走运行时生成档: %s" % [b])
	check(int(ts.pick("Other/c.png")["mult"]) == 0, "两档都没有 -> 原图")

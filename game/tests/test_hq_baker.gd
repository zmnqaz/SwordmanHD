# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## HqBaker (engine/render/hq/hq_baker.gd) 的池管理: 队列清空后多余的生成链释放、保留的缩到最小 (显存不随历史最大尺寸一直占着)。
## 生成本身需要 GPU 绘制, 无头下不跑; 这里只测不依赖渲染的池逻辑 (视口节点无头也能建)。


func test_trim_pool_frees_extra_chains_and_shrinks_kept() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var b := HqBaker.new()
	root.add_child(b)
	for i in HqBaker.KEEP_IDLE + 3:
		var c := b._new_chain()
		c.setup(ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8)), Vector2i(8, 8))
		b._free.append(c)
	check(b.pool_size() == HqBaker.KEEP_IDLE + 3, "建了 %d 条链" % (HqBaker.KEEP_IDLE + 3))
	b._trim_pool()
	check(b.pool_size() == HqBaker.KEEP_IDLE, "清空后只留 KEEP_IDLE 条: %d" % b.pool_size())
	for c in b._free:
		var vp: SubViewport = c._final
		check(vp.size == Vector2i(2, 2), "保留的链缩到最小: %s" % vp.size)
		check(vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "缩小后不再渲染")
	b.free()


## 自检图: 理想输出 (最近邻 6 倍) 通过; 空白/尺寸不对/编译失败常见的全透明输出不通过
func test_selftest_judges_output() -> void:
	var img := HqBaker.selftest_image()
	var ideal := img.duplicate() as Image
	ideal.resize(img.get_width() * HqBaker.SCALE, img.get_height() * HqBaker.SCALE, Image.INTERPOLATE_NEAREST)
	check(HqBaker.selftest_ok(ideal), "理想输出通过自检")
	var blank := Image.create(ideal.get_width(), ideal.get_height(), false, Image.FORMAT_RGBA8)
	check(not HqBaker.selftest_ok(blank), "全透明 (着色器编译失败时的输出) 不通过")
	var black := blank.duplicate() as Image
	black.fill(Color(0, 0, 0, 1))
	check(not HqBaker.selftest_ok(black), "全黑不通过")
	check(not HqBaker.selftest_ok(img), "1 倍尺寸不通过")
	check(not HqBaker.selftest_ok(null), "null 不通过")
	var wrong := ideal.duplicate() as Image
	wrong.fill_rect(Rect2i(Vector2i(HqBaker.SCALE * 3, 0), Vector2i(HqBaker.SCALE, ideal.get_height())), Color(1, 1, 1, 1))
	check(not HqBaker.selftest_ok(wrong), "透明区被填色不通过")


## 回退状态机: _fail 只生效一次并发信号, 之后 request 给原图大小的纹理 (不占 6 倍显存); 看门狗超时触发 _fail
func test_fail_state_and_watchdog() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var b := HqBaker.new()
	root.add_child(b)
	var hits := []
	b.failed_over.connect(func(r: String) -> void: hits.append(r))
	check(not b.failed, "初始未回退")
	b._deadline_ms = Time.get_ticks_msec() - 10  # 已过期
	b._process(0.0)
	check(b.failed and hits.size() == 1, "看门狗超时置 failed 并发一次信号: %d" % hits.size())
	b._fail("again")
	check(hits.size() == 1, "重复 _fail 不重复发信号")
	var tex := b.request(Image.create(5, 3, false, Image.FORMAT_RGBA8))
	check(Vector2i(tex.get_size()) == Vector2i(5, 3), "回退后 request 返回 1 倍纹理: %s" % tex.get_size())
	check(b.pending() == 0, "回退后不入队")
	b.free()


## Assets 接入: 生成器已回退时, 生成档的贴图改用 1 倍原图 (scale 1, hd false)
func test_assets_uses_original_after_fallback() -> void:
	var png := ""
	for f in Assets.list_files("Rpg"):
		if String(f).ends_with(".png"):
			png = f
			break
	if png == "":
		check(true, "无原图资源, 跳过")
		return
	var rel := Assets.resolve(png)
	var old_baker = Assets._baker
	var old_mult := Assets.tex_mult
	var ntiers := Assets._texsrc.tiers.size()
	var b := HqBaker.new()
	b.failed = true
	Assets._baker = b
	Assets.tex_mult = 6
	Assets._texsrc.add_tier(6, "", {rel: true}, true)
	Assets.clear_cache()
	var t := Assets.tex(png)
	var sc := float(t["scale"])
	var hd: bool = t["hd"]
	var sz := Vector2i(t["texture"].get_size())
	Assets._texsrc.tiers.resize(ntiers)
	Assets._baker = old_baker
	Assets.tex_mult = old_mult
	Assets.clear_cache()
	b.free()
	check(sc == 1.0 and not hd, "回退后用 1 倍原图: scale %f hd %s" % [sc, str(hd)])
	check(sz.x > 0 and sz.x < 6000, "纹理是原图大小: %s" % sz)


## 读回校验: 空图/尺寸不符/有内容的原图读回全透明判坏; 累计 BAD_READBACK_LIMIT 次回退
func test_readback_validation_and_fail_count() -> void:
	var src := HqBaker.selftest_image()
	var good := src.duplicate() as Image
	good.resize(src.get_width() * HqBaker.SCALE, src.get_height() * HqBaker.SCALE, Image.INTERPOLATE_NEAREST)
	check(HqBaker.readback_ok(src, good), "正常读回通过")
	check(not HqBaker.readback_ok(src, null), "null 读回判坏")
	check(not HqBaker.readback_ok(src, Image.new()), "空图读回判坏")
	check(not HqBaker.readback_ok(src, src), "尺寸不符判坏")
	var blank := Image.create(good.get_width(), good.get_height(), false, Image.FORMAT_RGBA8)
	check(not HqBaker.readback_ok(src, blank), "原图有内容而输出全透明判坏")
	var empty_src := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	check(HqBaker.readback_ok(empty_src, blank), "原图本身全透明时全透明输出是对的")
	var root := (Engine.get_main_loop() as SceneTree).root
	var b := HqBaker.new()
	root.add_child(b)
	for i in HqBaker.BAD_READBACK_LIMIT - 1:
		b._note_bad_readback()
	check(not b.failed, "未到阈值不回退")
	b._note_bad_readback()
	check(b.failed and b.bad_readbacks == HqBaker.BAD_READBACK_LIMIT, "累计到阈值回退: %s" % b.fail_reason)
	b.free()

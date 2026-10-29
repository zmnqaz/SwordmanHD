# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## TexCodec (engine/render/hq/tex_codec.gd): 烘焙结果的 GPU 压缩与磁盘缓存。压缩与缓存读写是纯 CPU, 无头也能测;
## 「显卡支持哪种格式」依赖真实渲染, 无头一律不支持, 只测选择逻辑的分支。


func _sprite(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var inside := (x - w / 2) * (x - w / 2) + (y - h / 2) * (y - h / 2) < (mini(w, h) / 3) * (mini(w, h) / 3)
			img.set_pixel(x, y, Color8(40 + x, 90 + y / 2, 200, 255) if inside else Color8(0, 0, 0, 0))
	return img


func test_pick_choices() -> void:
	check(TexCodec.pick("off") == "", "off 不压缩")
	check(TexCodec.pick("") == "", "空 = 不压缩")
	check(TexCodec.pick("nonsense") == "", "不认识的格式不压缩")
	if DisplayServer.get_name() == "headless":
		check(TexCodec.pick("auto") == "", "无头没有渲染, 自动选择也不压缩")
		check(TexCodec.pick("bptc") == "", "无头不支持 bptc")


func test_compress_formats_shrink_and_keep_shape() -> void:
	for fmt in ["bptc", "etc2", "astc"]:
		var img := _sprite(150, 90)   # 不是 4 的倍数: 压缩块要补边
		var raw := img.get_data_size()
		check(TexCodec.compress(img, fmt), "%s 压缩成功" % fmt)
		check(img.is_compressed(), "%s 结果是压缩格式" % fmt)
		# 压缩块 4x4: Godot 把宽高补成 4 的倍数 (150x90 -> 152x92), 多出来的是右/下边的透明补边; 精灵左上角对齐, 画面不变
		check(img.get_width() >= 150 and img.get_width() < 154 and img.get_height() >= 90 and img.get_height() < 94, "%s 压缩后尺寸只多出补边: %s" % [fmt, img.get_size()])
		check(img.get_data_size() * 3 < raw, "%s 体积明显变小: %d -> %d" % [fmt, raw, img.get_data_size()])
	check(not TexCodec.compress(_sprite(8, 8), "nonsense"), "未知格式返回 false")
	check(not TexCodec.compress(_sprite(8, 8), "s3tc"), "S3TC 不支持 (换入会崩, 见 tex_codec.gd 头注释)")
	var again := _sprite(16, 16)
	TexCodec.compress(again, "bptc")
	check(not TexCodec.compress(again, "bptc"), "已经压缩过的图不再压缩")


func test_bptc_quality_is_close() -> void:
	var ref := _sprite(128, 128)
	var c := ref.duplicate() as Image
	TexCodec.compress(c, "bptc")
	c.decompress()
	c.convert(Image.FORMAT_RGBA8)
	var worst := 0
	var bad_alpha := 0
	for y in 128:
		for x in 128:
			var a := ref.get_pixel(x, y)
			var b := c.get_pixel(x, y)
			if absi(a.a8 - b.a8) > 32:
				bad_alpha += 1
			if a.a8 > 0 and b.a8 > 0:
				worst = maxi(worst, maxi(absi(a.r8 - b.r8), maxi(absi(a.g8 - b.g8), absi(a.b8 - b.b8))))
	check(worst < 24, "BC7 可见像素最大通道差 %d" % worst)
	check(bad_alpha < 128 * 128 / 100, "alpha 差 > 32 的像素不到 1%%: %d" % bad_alpha)


func test_cache_roundtrip_trim_and_corruption() -> void:
	var old := TexCodec.cache_dir
	TexCodec.cache_dir = "user://hq_cache_test_%d" % Time.get_ticks_usec()
	var img := _sprite(96, 64)
	check(not TexCodec.cache_write(TexCodec.cache_path("a" + "0".repeat(31), "sig", "bptc"), img), "没压缩的图不写缓存")
	TexCodec.compress(img, "bptc")
	var data0 := img.get_data()
	var p1 := TexCodec.cache_path("ab" + "0".repeat(30), "sig1", "bptc")
	check(p1.contains("/bptc/ab/"), "路径按格式/md5 前两位分目录: " + p1)
	check(TexCodec.cache_write(p1, img), "写缓存成功")
	var back := TexCodec.cache_read(p1)
	check(back != null and back.get_width() == 96 and back.get_height() == 64 and back.get_format() == img.get_format(), "读回尺寸与格式一致")
	check(back != null and back.get_data() == data0, "读回的字节与写入完全一致")
	check(TexCodec.cache_read(TexCodec.cache_path("ff" + "0".repeat(30), "sig1", "bptc")) == null, "没有的缓存返回 null")
	check(TexCodec.cache_path("ab" + "0".repeat(30), "sig2", "bptc") != p1, "签名不同, 路径不同 (改了烘焙算法旧缓存作废)")
	# 损坏的文件读成 null, 不崩
	var bad := FileAccess.open(p1 + ".junk.tcb", FileAccess.WRITE)
	bad.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]))
	bad.close()
	check(TexCodec.cache_read(p1 + ".junk.tcb") == null, "损坏文件读成 null")
	# 清理: 超上限删最旧
	var p2 := TexCodec.cache_path("cd" + "0".repeat(30), "sig1", "bptc")
	TexCodec.cache_write(p2, img)
	var scan := TexCodec.cache_scan()
	check(int(scan["total"]) > 0 and (scan["files"] as Array).size() >= 2, "扫描到缓存文件: %d 个" % (scan["files"] as Array).size())
	var removed := TexCodec.cache_trim(1)
	check(removed >= 1 and int(TexCodec.cache_scan()["total"]) < int(scan["total"]), "超上限删了 %d 个文件" % removed)
	check(TexCodec.cache_trim(0) == 0 and TexCodec.cache_trim(1 << 40) == 0, "上限 0 = 不清理; 没超上限不删")
	# 收尾: 删测试目录 (文件 + 空目录; 以前只删文件, user:// 下留了一堆空的 hq_cache_test_*)
	for e in TexCodec.cache_scan()["files"]:
		DirAccess.remove_absolute(e["path"])
	_remove_tree(TexCodec.cache_dir)
	TexCodec.cache_dir = old


func _remove_tree(dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for fn in da.get_files():
		DirAccess.remove_absolute(dir + "/" + fn)   # 损坏文件测试留下的 .junk.tcb 等
	for sub in da.get_directories():
		_remove_tree(dir + "/" + sub)
	DirAccess.remove_absolute(dir)


## 退出时 TexCodec.cancel 置位: 后台缓存扫描 / 清理立即停手 (扫几万个文件在 Windows 上要好几秒, 不能拖住关窗口); 没置位时照常
func test_cancel_stops_scan_and_trim() -> void:
	var old := TexCodec.cache_dir
	TexCodec.cache_dir = "user://hq_cache_test_%d" % Time.get_ticks_usec()
	var img := _sprite(32, 32)
	TexCodec.compress(img, "bptc")
	for i in 5:
		TexCodec.cache_write(TexCodec.cache_path("%02x" % (i * 3) + "0".repeat(30), "sig", "bptc"), img)
	var n := (TexCodec.cache_scan()["files"] as Array).size()
	check(n >= 5, "没取消: 扫到 %d 个文件" % n)
	TexCodec.cancel = true
	eq(TexCodec.cache_scan(), {"total": 0, "files": []}, "取消后扫描立即返回空")
	eq(TexCodec.cache_trim(1), 0, "取消后清理不删任何文件")
	TexCodec.cancel = false
	eq((TexCodec.cache_scan()["files"] as Array).size(), n, "取消只是停手, 没删文件")
	for e in TexCodec.cache_scan()["files"]:
		DirAccess.remove_absolute(e["path"])
	_remove_tree(TexCodec.cache_dir)
	TexCodec.cache_dir = old

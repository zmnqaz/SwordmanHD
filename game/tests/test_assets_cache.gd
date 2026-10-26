# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## Assets (engine/render/assets.gd) 的缓存代数与大图降采样: 换场景只清旧代、新场景已用到的不丢; 超显卡单边上限的图等比缩小且显示尺寸不变。


func test_fit_dim() -> void:
	check(Assets.fit_dim(Vector2i(2640, 8928), 16384) == 1.0, "上限内不缩")
	var f := Assets.fit_dim(Vector2i(2640, 8928), 8192)
	check(absf(f - 8192.0 / 8928.0) < 1e-9, "按长边缩: %f" % f)
	check(Assets.fit_dim(Vector2i(100, 100), 0) == 1.0, "上限 0 视为不限")


func test_sweep_keeps_current_generation() -> void:
	var files := Assets.list_files("Face")
	var png := ""
	for f in files:
		if String(f).ends_with(".png"):
			png = f
			break
	if png == "":  # 没有原图资源的环境 (CI 缺原版) 跳过, 与其它依赖资源的测试一致
		check(true, "无原图资源, 跳过")
		return
	Assets.clear_cache()
	Assets.tex(png)                # 旧场景载入
	var other := ""
	for f in files:
		if String(f).ends_with(".png") and f != png:
			other = f
			break
	Assets.begin_scene()           # 换场景
	Assets.tex(other)              # 新场景载入另一张
	var before := Assets.cache_size()
	Assets.sweep()
	check(before == 2 and Assets.cache_size() == 1, "旧代被清、新代保留: %d -> %d" % [before, Assets.cache_size()])
	Assets.begin_scene()
	Assets.tex(other)              # 新场景命中旧项: 记入新一代, 不被清
	Assets.sweep()
	check(Assets.cache_size() == 1, "命中旧项续代: %d" % Assets.cache_size())
	Assets.clear_cache()


func test_big_texture_downscaled_keeps_display_size() -> void:
	var png := ""
	for f in Assets.list_files("Rpg"):
		if String(f).ends_with(".png"):
			png = f
			break
	if png == "":
		check(true, "无原图资源, 跳过")
		return
	Assets.clear_cache()
	var base := Assets.tex(png)
	var disp0: Vector2 = Vector2(base["texture"].get_size()) * float(base["scale"])
	var old := Assets.max_tex
	Assets.max_tex = int(maxf(disp0.x, disp0.y) / 2.0 / maxf(float(base["scale"]), 0.0001) / 2.0) + 1  # 强制降采样
	Assets.clear_cache()
	var t := Assets.tex(png)
	var disp1: Vector2 = Vector2(t["texture"].get_size()) * float(t["scale"])
	Assets.max_tex = old
	Assets.clear_cache()
	check(t["texture"].get_width() < base["texture"].get_width() or t["texture"].get_height() < base["texture"].get_height(), "纹理变小了")
	check(absf(disp1.x - disp0.x) <= 1.0 and absf(disp1.y - disp0.y) <= 2.0, "显示尺寸不变: %s vs %s" % [disp0, disp1])


func test_budget_evicts_unreferenced_lru_but_never_held() -> void:
	var pngs: Array = []
	for f in Assets.list_files("Sprite"):
		if String(f).ends_with(".png"):
			pngs.append(f)
			if pngs.size() >= 1500:
				break
	if pngs.size() < 1500:
		check(true, "无足够原图资源, 跳过")
		return
	Assets.clear_cache()
	var old := Assets.tex_budget_mb
	var old_max := Assets.tex_budget_max_mb
	Assets.tex_budget_mb = 1
	Assets.tex_budget_max_mb = 0   # 这条只测淘汰, 不要自适应放大
	var held: Dictionary = Assets.tex(pngs[0])   # 模拟场景节点持有: 字典里的 texture 多一个引用
	var held_tex: Texture2D = held["texture"]
	var ev0 := Assets.evicted
	for i in range(1, pngs.size()):
		Assets.tex(pngs[i])
		if i % 50 == 0:
			await Engine.get_main_loop().process_frame   # 同帧用过的不淘汰, 跨帧才进候选
	Assets.tex(pngs[1])
	var kept := Assets.cache_size()
	var rel := Assets.resolve(pngs[0])
	var still: bool = Assets._texs.has(rel) and Assets._texs[rel]["texture"] == held_tex
	Assets.tex_budget_mb = old
	Assets.tex_budget_max_mb = old_max
	Assets.clear_cache()
	check(Assets.evicted > ev0, "超预算淘汰了贴图: %d" % (Assets.evicted - ev0))
	check(kept < pngs.size(), "缓存没有无限增长: %d / %d" % [kept, pngs.size()])
	check(still, "被节点持有的贴图没有被淘汰")


## 工作集比预算大、循环用到的贴图刚淘汰又要用 (城镇客栈的循环动画): 预算自动放大到上限为止; 上限为 0 时不放大
func test_budget_grows_when_evicted_textures_are_reloaded() -> void:
	var pngs: Array = []
	for f in Assets.list_files("Sprite"):
		if String(f).ends_with(".png"):
			pngs.append(f)
			if pngs.size() >= 600:
				break
	if pngs.size() < 600:
		check(true, "无足够原图资源, 跳过")
		return
	var old := Assets.tex_budget_mb
	var old_max := Assets.tex_budget_max_mb
	for cap in [0, 6]:
		Assets.clear_cache()
		Assets.tex_budget_mb = 2
		Assets.tex_budget_max_mb = cap
		var grown0 := Assets.budget_grown
		var l0 := Assets.loads
		for lap in 3:   # 循环播放: 同一批贴图一圈一圈地用, 预算装不下时每圈全部重载
			for i in pngs.size():
				Assets.tex(pngs[i])
				if i % 25 == 0:
					await Engine.get_main_loop().process_frame
		var grown := Assets.budget_grown - grown0
		var budget := Assets.tex_budget_mb
		var loads := Assets.loads - l0
		Assets.tex_budget_mb = old
		Assets.tex_budget_max_mb = old_max
		Assets.clear_cache()
		if cap == 0:
			check(grown == 0 and budget == 2, "上限 0 不放大: 放大 %d 次, 预算 %d" % [grown, budget])
		else:
			check(grown > 0 and budget <= cap, "重复载入触发放大并停在上限内: 放大 %d 次, 预算 %d (上限 %d), 载入 %d" % [grown, budget, cap, loads])


## 像素画类烘焙倍数: 手机按屏幕分辨率选 3 / 4 / 6, 电脑固定 6, 显式指定优先
func test_pick_hq_scale() -> void:
	check(Assets.pick_hq_scale(Vector2(1280, 720), true) == 4, "手机 720p (m=3.6) 用 4 倍")
	check(Assets.pick_hq_scale(Vector2(1920, 1080), true) == 6, "手机 1080p (m=5.4) 用 6 倍")
	check(Assets.pick_hq_scale(Vector2(2400, 1080), true) == 6, "手机 2400x1080 用 6 倍")
	check(Assets.pick_hq_scale(Vector2(1136, 640), true) == 3, "老手机 1136x640 (m=3.2) 用 3 倍")
	check(Assets.pick_hq_scale(Vector2(2048, 1536), true) == 6, "平板 2048x1536 用 6 倍")
	check(Assets.pick_hq_scale(Vector2(1280, 720), false) == 6, "电脑不降: 固定 6 倍")
	check(Assets.pick_hq_scale(Vector2(1280, 720), false, 3) == 3 and Assets.pick_hq_scale(Vector2(1920, 1080), true, 4) == 4, "显式指定优先")
	check(Assets.pick_hq_scale(Vector2(1280, 720), true, 5) == 4, "不认识的显式值按自动处理")
	check(Assets.pick_hq_scale(Vector2.ZERO, true) == 6, "没有窗口尺寸时不降")

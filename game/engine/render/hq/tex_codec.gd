# SPDX-License-Identifier: GPL-3.0-only
class_name TexCodec
extends RefCounted
## 烘焙结果的 GPU 压缩与磁盘缓存 (HqBaker 用)。
##
## 为什么: 运行时烘焙出的 6 倍 RGBA8 贴图一张约 4 字节/像素, 客栈/大城镇的动画全部载入要 1.2~1.4GB, 超过缓存预算后循环动画
## 每帧都在重复烘焙 (读回约 7ms/张), GPU 一直忙。压成 GPU 原生压缩格式 (1 字节/像素) 显存降到 1/4, 画质损失很小
## (2026-10-20 实测 PSNR: BC7 46.8 dB / ASTC4x4 50.4 dB / ETC2 35.1 dB / DXT5 32.9 dB; 压缩耗时 BC7 约 35~130 ms/百万像素,
## 全部放后台线程); 压缩结果再写进磁盘缓存 (zstd), 以后任何场景/任何次启动直接读, 不再烘焙。
##
## 格式按显卡能力选 (RenderingServer.has_os_feature): 电脑 BC7, 手机 ASTC 4x4, 都不支持就不压缩 (维持原行为)。
## 不用 S3TC/DXT5: 2026-10-20 实测「烘焙后换入 DXT5 纹理」在 NVIDIA 与 Mesa llvmpipe 两种驱动上都会崩 (Godot 自身的问题, 退出时 SIGSEGV/SIGABRT),
## BC7 (NVIDIA 真机) 与 ASTC (llvmpipe 软件 GL) 的这条路径都跑通; ETC2 在软件 GL 上不被支持没能验证, 只允许 --hq-codec=etc2 显式指定。
## 缓存键 = 原图文件内容的 MD5 + 烘焙算法签名 + 格式: 内容相同的图 (如五个客栈共用的物件) 只烘焙一次, 改着色器/倍数自动失效。

const CACHE_VERSION := 1
const MAGIC := 0x434A4454   # "TDJC"
const FORMATS := ["bptc", "astc"]          # 自动选择的优先顺序 (画质 / 通用性)
const EXPLICIT_ONLY := ["etc2"]            # 只在命令行显式指定时才用 (没验证过)

## 缓存目录 (user:// 下); 测试里可改
static var cache_dir := "user://hq_cache"


## 格式名 -> [Image.CompressMode, ASTC 档位]
static func mode_of(fmt: String) -> Array:
	match fmt:
		"bptc": return [Image.COMPRESS_BPTC, 0]
		"astc": return [Image.COMPRESS_ASTC, Image.ASTC_FORMAT_4x4]
		"etc2": return [Image.COMPRESS_ETC2, 0]
	return []


## 显卡支持这个压缩格式吗 (无头模式没有渲染, 一律不支持)
static func supported(fmt: String) -> bool:
	if DisplayServer.get_name() == "headless" or not (FORMATS.has(fmt) or EXPLICIT_ONLY.has(fmt)):
		return false
	return RenderingServer.has_os_feature(fmt)


## 这个引擎构建能在运行时压缩图片吗: 官方导出模板 (release/debug) 不带 Image 压缩器 (BPTC/ASTC/ETC 压缩只在编辑器构建里注册),
## 在导出版调 Image.compress 会报 `_image_compress_bptc_func is null` 并失败 (2026-10-20 Windows 实机发现; 之前的实测都用编辑器二进制, 没测到)。
## 自制模板 (tools/platform/build_template_windows.sh, scons 开关 cvtt_export_templates=yes) 带压缩器, 打包时给预设加功能标签 tex_compress, 这里据此放行;
## 也可以用 --hq-codec=bptc 显式指定
static func runtime_compress_available() -> bool:
	return not OS.has_feature("template") or OS.has_feature("tex_compress")


## 选格式: pref = "auto" 按优先顺序挑显卡支持的第一个 (导出模板里没有压缩器, 自动选择不压缩); "off" / "" 不压缩; 其余指定格式 (显卡不支持则不压缩)。返回 "" = 不压缩
static func pick(pref: String) -> String:
	if pref == "off" or pref == "":
		return ""
	if pref != "auto":
		return pref if supported(pref) else ""
	if not runtime_compress_available():
		return ""
	for f in FORMATS:
		if supported(f):
			return f
	return ""


## 压缩一张 RGBA8 图 (原地)。成功返回 true; 这是纯 CPU 的重活, 调用方放工作线程
static func compress(img: Image, fmt: String) -> bool:
	var m := mode_of(fmt)
	if m.is_empty() or img.is_compressed():
		return false
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img.compress(m[0], Image.COMPRESS_SOURCE_GENERIC, m[1]) == OK


## 缓存文件路径: user://hq_cache/<格式>/<md5 前两位>/<md5>_<签名>.tcb
static func cache_path(md5: String, sig: String, fmt: String) -> String:
	return "%s/%s/%s/%s_%s.tcb" % [cache_dir, fmt, md5.substr(0, 2), md5, sig]


## 写缓存 (压缩后的图): 头 = MAGIC, 版本, 宽, 高, Image.Format, 原始字节数; 体 = zstd。先写临时文件再改名, 半截文件不会被读到。可在线程里调
static func cache_write(path: String, img: Image) -> bool:
	if not img.is_compressed():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var data := img.get_data()
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(MAGIC)
	f.store_32(CACHE_VERSION)
	f.store_32(img.get_width())
	f.store_32(img.get_height())
	f.store_32(int(img.get_format()))
	f.store_32(data.size())
	f.store_buffer(data.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


## 读缓存: 成功返回压缩格式的 Image, 没有/损坏返回 null
static func cache_read(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 24:
		return null
	if f.get_32() != MAGIC or f.get_32() != CACHE_VERSION:
		return null
	var w := f.get_32()
	var h := f.get_32()
	var fmt := f.get_32()
	var raw := f.get_32()
	var z := f.get_buffer(f.get_length() - 24)
	if w <= 0 or h <= 0 or raw <= 0 or raw > 512 * 1024 * 1024:
		return null
	var data := z.decompress(raw, FileAccess.COMPRESSION_ZSTD)
	if data.size() != raw:
		return null
	var img := Image.create_from_data(w, h, false, fmt, data)
	return img if img != null and not img.is_empty() else null


## 缓存目录总字节数与文件清单 [{path, size, time}], 按修改时间旧 -> 新 (清理用, 可在线程里调; 只遍历 user:// 缓存目录, 不碰别处)
static func cache_scan() -> Dictionary:
	var files: Array = []
	var total := 0
	var stack: Array = [cache_dir]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			stack.append(d + "/" + sub)
		for fn in da.get_files():
			if fn.ends_with(".tmp") and Time.get_unix_time_from_system() - FileAccess.get_modified_time(d + "/" + fn) > 3600:
				DirAccess.remove_absolute(d + "/" + fn)   # 写到一半被杀掉留下的临时文件
				continue
			if not fn.ends_with(".tcb"):
				continue
			var p := d + "/" + fn
			var fa := FileAccess.open(p, FileAccess.READ)
			var sz := fa.get_length() if fa != null else 0
			fa = null
			files.append({"path": p, "size": sz, "time": FileAccess.get_modified_time(p)})
			total += sz
	files.sort_custom(func(a, b): return int(a["time"]) < int(b["time"]))
	return {"total": total, "files": files}


## 缓存超过 cap_bytes 就删最旧的, 降到 90%。返回删掉的文件数
static func cache_trim(cap_bytes: int) -> int:
	if cap_bytes <= 0:
		return 0
	var s := cache_scan()
	var total: int = s["total"]
	if total <= cap_bytes:
		return 0
	var n := 0
	var target := int(cap_bytes * 0.9)
	for e in s["files"]:
		if total <= target:
			break
		if DirAccess.remove_absolute(e["path"]) == OK:
			total -= int(e["size"])
			n += 1
	return n

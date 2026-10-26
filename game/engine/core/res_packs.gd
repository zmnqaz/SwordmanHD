# SPDX-License-Identifier: GPL-3.0-only
extends Node
## 资源包挂载 (autoload "ResPacks", 排在所有 autoload 之前, 因为 Content / Assets 启动时就要读包里的文件)。
## 资源包由 资源生成工具 从玩家自己的原版游戏生成 (仓库不含版权资源), 包内路径即 res:// 路径。发布目录分两部分:
##
##   resource/  必备资源 (游戏离不开的; 画质 hd / classic 二选一, common 永远要放):
##     common_assets.pck  → res://common/          公用素材: 动画数据、像素画类贴图、音乐音效 (任何画质都用); used_rects.json 是 classic_images 的标记
##     common_story.pck   → res://content/tdj/     公用剧情: 脚本/对白/数值/关卡/贴图分类表 (项目手写的界面/演出配置是 content/remake, 在主 pck)
##     hd_images.pck      → res://hd/              高清图: 头像/地图/大特效/界面大图 4 倍 (AI 放大)
##     hd_movies.pck      → res://hd/Movie|Magic/  高清过场/法术视频 1280x800 (与 hd_images 同一个 res://hd/ 前缀, 文件互不重叠)
##     classic_images.pck → res://common/          原版画质图: 上面 hd_images 替代的那部分 1 倍原图 (放了 hd_images 就不用放它; 没有 hd_images 就必须放)
##     classic_movies.pck → res://classic/movies/ 原版分辨率过场 (320x200; 放了 hd_movies 就不用放)
##
##   mod/  可选 mod (叠加覆盖): 目录里所有 *.pck 按文件名顺序挂在 resource/ 之后, 同路径文件后挂的覆盖先挂的。
##     face_hk.pck        → res://mod/face_hk/     港漫风格头像 (设定里「头像风格」选「港漫」才读; 没装则没有这一行, 见 Assets.face_style)
##     其他 mod 包 (改内容、换素材) 同样放这里; mod 自带的新素材放在 res://mod/<包名>/ 下, 要覆盖必备资源里的文件就用同一个 res:// 路径。
##
## 两个目录都可以直接放在 exe 旁, 也兼容旧的平铺摆法 (资源包直接放 exe 旁、不分目录)。
## 导出版自动挂载 exe 旁的包; 开发版默认直接读目录, 加 --packs=<目录> 可改为挂载该目录下的包 (验证生成结果)。
## 挂载后读取方式与目录完全相同 (FileAccess / Image.load_from_file / VideoStreamTheora.file)。

const RESOURCE := ["common_assets", "common_story", "classic_images", "classic_movies", "hd_images", "hd_movies"]  # 必备资源 (resource/ 下), 文件互不重叠
const RESOURCE_DIR := "resource"
const MOD_DIR := "mod"   # 可选 mod: 目录里所有 *.pck 按文件名顺序挂在必备资源之后
## Android: 资源包放在应用自己的外部存储目录 (adb push 能写, 应用读自己的目录不需要权限); 包名与 export_presets.cfg 的 package/unique_name、tools/platform/build_android.py 的 PACKAGE 一致 (tools/tests/test_package_ids.py 校验)
const ANDROID_PACKAGE := "com.tdj.swordmanhd"
## 整包 (自用, 不公开发布; docs/打包/Android.md「整包」): 资源包随安装包一起装, 装完就能玩, 不用再拷资源。
## 打包时放进 <安装包>/bundled/: resource/*.pck、mod/*.pck 和 manifest.json (列出包名, 因为 Android 的 APK 里不方便列目录)。
## Android: APK 的 assets/bundled/, 运行时按 res://bundled/ 读 (原地挂载, 不占两份空间; 万一挂不上就拷到 user:// 再挂);
## iOS: .app 里的 bundled/ 目录。整包里的包先挂, 之后外部目录 (adb push / 文件 App 放的) 里同名的包照旧覆盖它们。
const BUNDLE_DIR := "bundled"
const BUNDLE_MANIFEST := "manifest.json"

var _mounted := {}  # 包名 -> 文件路径
var _failed := []   # 存在但挂载失败的包路径 (诊断用)
var _base := ""     # base_dir() 的缓存 (启动时算一次; 移动端要探测候选目录, 不必每次调用都碰文件系统)
var _base_done := false


func _enter_tree() -> void:
	_mount_bundle()
	var dir := base_dir()
	if Platform.is_android() and dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)  # 应用外部存储目录不存在就建出来, 之后 adb push 才有地方放 (只在启动时做一次)
	if DebugArgs.current().packs != "":   # --packs=<目录>
		dir = DebugArgs.current().packs
	if dir == "":
		return
	for name in RESOURCE:
		var p := pack_file_in(dir, name)
		if p != "":
			_mount(name, p)
	var md := DirAccess.open(dir.path_join(MOD_DIR))
	if md != null:
		var mods := Array(md.get_files()).filter(func(f): return String(f).ends_with(".pck"))
		mods.sort()
		for f in mods:
			_mount("mod/" + String(f).get_basename(), dir.path_join(MOD_DIR).path_join(f))
	if not _mounted.is_empty():
		print("ResPacks: 已挂载 ", ", ".join(_mounted.keys()), " (", dir, ")")


## 整包所在目录: Android = res://bundled (APK 的 assets); iOS = .app 里的 bundled/; 其他平台没有整包返回 ""
static func bundled_dir() -> String:
	if DebugArgs.current().bundled != "":   # --bundled=<目录>: 桌面上模拟整包 (测试)
		return DebugArgs.current().bundled
	if Platform.is_android():
		return "res://" + BUNDLE_DIR
	if Platform.is_ios():
		return OS.get_executable_path().get_base_dir().path_join(BUNDLE_DIR)
	return ""


## 整包清单 manifest.json -> {"resource": [包名...], "mod": [包名...]} (包名不带 .pck); 不是合法清单返回 {}
static func parse_bundle(j) -> Dictionary:
	if not j is Dictionary:
		return {}
	var out := {"resource": [], "mod": []}
	for k in out:
		var v = j.get(k, [])
		if not v is Array:
			return {}
		for n in v:
			if not n is String or String(n) == "" or "/" in String(n) or ".." in String(n):
				return {}
			out[k].append(String(n))
	return out if not out["resource"].is_empty() else {}


## 读整包清单: 没有整包 / 清单坏了返回 {}
static func read_bundle(dir: String) -> Dictionary:
	if dir == "":
		return {}
	var p := dir.path_join(BUNDLE_MANIFEST)
	if not FileAccess.file_exists(p):
		return {}
	return parse_bundle(JSON.parse_string(FileAccess.get_file_as_string(p)))


## 挂整包里的资源包 (有就挂, 没有什么也不做); 后面外部目录里的同名包会再挂一次覆盖它
func _mount_bundle() -> void:
	var dir := bundled_dir()
	var m := read_bundle(dir)
	if m.is_empty():
		return
	for n in m["resource"]:
		_mount(String(n), dir.path_join(RESOURCE_DIR).path_join(n + ".pck"))
	for n in m["mod"]:
		_mount("mod/" + String(n), dir.path_join(MOD_DIR).path_join(n + ".pck"))
	print("ResPacks: 整包 ", ", ".join(_mounted.keys()), " (", dir, ")")


func _mount(name: String, p: String) -> void:
	if ProjectSettings.load_resource_pack(p):
		_mounted[name] = p
		return
	if p.begins_with("res://"):   # APK assets 里的包原地挂不上: 拷到应用目录 (user://bundled/) 再挂, 只第一次拷
		var q := _extract_asset(name, p)
		if q != "" and ProjectSettings.load_resource_pack(q):
			_mounted[name] = q
			return
	_failed.append(p)
	push_error("资源包挂载失败: " + p)


## 把 res:// (APK assets) 里的包拷到 user://bundled/<名>.pck, 返回拷好的路径 (已经拷过且大小一样就不再拷); 失败返回 ""
func _extract_asset(name: String, src: String) -> String:
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		return ""
	var dst := "user://%s/%s.pck" % [BUNDLE_DIR, name.replace("/", "_")]
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	if FileAccess.file_exists(dst):
		var g := FileAccess.open(dst, FileAccess.READ)
		if g != null and g.get_length() == f.get_length():
			return dst
	var o := FileAccess.open(dst, FileAccess.WRITE)
	if o == null:
		return ""
	while f.get_position() < f.get_length():
		o.store_buffer(f.get_buffer(8 * 1024 * 1024))
	o.close()
	return dst


## 必备资源包 name 在 dir 里的文件路径: 先找 dir/resource/<name>.pck, 再找平铺的 dir/<name>.pck; 都没有返回 ""
static func pack_file_in(dir: String, name: String) -> String:
	for p in [dir.path_join(RESOURCE_DIR).path_join(name + ".pck"), dir.path_join(name + ".pck")]:
		if FileAccess.file_exists(p):
			return p
	return ""


## 导出版: 程序所在目录 (资源包与旧版散文件目录 original/ hd4x/ 都放在它旁边; Assets 也用它定位); 开发版没有这个概念, 返回 ""
func base_dir() -> String:
	if not _base_done:
		_base = _find_base_dir()
		_base_done = true
	return _base


static func _find_base_dir() -> String:
	if Platform.is_android():
		return android_pack_dir()
	if Platform.is_ios():
		return ios_pack_dir()
	if not Platform.is_exported():
		return ""
	var exe_dir := OS.get_executable_path().get_base_dir()
	if Platform.is_macos() and exe_dir.ends_with(".app/Contents/MacOS"):
		return mac_pack_dir(exe_dir)
	return exe_dir


## macOS: 程序在 SwordmanHD.app/Contents/MacOS/ 里, 资源包放在 .app 旁边 (和 Windows 的 exe 旁一样, 不用改 .app 包内容, 也不破坏签名);
## .app 旁没有就找用户数据目录 (~/Library/Application Support/...), 都没有返回 .app 旁的目录 (诊断里会显示)
static func mac_pack_dir(exe_dir: String) -> String:
	var beside := exe_dir.get_base_dir().get_base_dir().get_base_dir()   # .../SwordmanHD.app/Contents/MacOS → .app 所在目录
	for d in [beside, OS.get_user_data_dir()]:
		if String(d) != "" and pack_file_in(String(d), "common_assets") != "":
			return d
	return beside


## iOS: 资源包放在应用的 Documents 目录 (导出时开了文件共享: 「文件」App 里「我的 iPhone/iPad → 天地劫」, 或 Finder/iTunes 文件共享里拷进去)
## 真机上 OS.get_system_dir(DOCUMENTS) 实测返回过空串 (这时路径为 "" 会被当成"当前目录"=安装包内部, 找不到包), 所以多个候选依次试: 哪个目录里已有 common_assets.pck 用哪个, 都没有用第一个非空的
static func ios_dirs() -> Array:
	var out := []
	for d in [OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), OS.get_user_data_dir()]:
		if String(d) != "" and not out.has(d):
			out.append(d)
	return out


static func ios_pack_dir() -> String:
	var dirs := ios_dirs()
	for d in dirs:
		if pack_file_in(String(d), "common_assets") != "":
			return d
	return dirs[0] if not dirs.is_empty() else ""


## Android 上资源包所在目录的候选 (不同系统版本/厂商 /sdcard 的挂载写法不同)
static func android_dirs() -> Array:
	return ["/storage/emulated/0/Android/data/%s/files" % ANDROID_PACKAGE, "/sdcard/Android/data/%s/files" % ANDROID_PACKAGE]


## 有资源包的那个候选目录; 都没有就取已存在的候选目录, 再没有就是第一个候选 (只查不建; 目录由启动时 _enter_tree 建一次)
static func android_pack_dir() -> String:
	var dirs := android_dirs()
	for d in dirs:
		if pack_file_in(String(d), "common_assets") != "":
			return d
	for d in dirs:
		if DirAccess.dir_exists_absolute(d):
			return d
	return dirs[0]


## 手机上找不到资源包时给用户看的诊断: 实际在找哪个目录、里面有什么文件 (多大)、各包挂载结果 (用户看不到日志, 靠这个定位是没拷对还是拷坏了)
func diagnose() -> String:
	var dir := base_dir()
	var lines := PackedStringArray(["目录: " + (dir if dir != "" else "(空)")])
	if Platform.is_ios():
		lines.append("候选: " + (" | ".join(ios_dirs()) if not ios_dirs().is_empty() else "(都是空)"))
	var d := DirAccess.open(dir) if dir != "" else null
	if d == null:
		lines.append("打不开该目录 (错误 %d)" % DirAccess.get_open_error())
	else:
		var n := 0
		for sub in ["", RESOURCE_DIR, MOD_DIR]:
			var dd := DirAccess.open(dir.path_join(sub)) if sub != "" else d
			if dd == null:
				continue
			for f in dd.get_files():
				var fa := FileAccess.open(dir.path_join(sub).path_join(f), FileAccess.READ)
				lines.append("  %s  %s" % [(sub + "/" if sub != "" else "") + f, ("%.1f MB" % (fa.get_length() / 1048576.0)) if fa else "读不开"])
				n += 1
		if n == 0:
			lines.append("  (目录里没有任何文件)")
	lines.append("已挂载: " + (", ".join(_mounted.keys()) if not _mounted.is_empty() else "无"))
	if not _failed.is_empty():
		lines.append("挂载失败: " + ", ".join(_failed))
	return "\n".join(lines)


## 找不到原版资源时给玩家的提示: 按平台说明资源包该放哪 (手机上附带 diagnose() 的诊断)。Game.resource_error 只负责显示。
## 文案走 UiStrings (键 boot.missing.*); 缺包时内容包多半也没加载 (取不到文案表), 这时用下面的后备文字。
func missing_hint() -> String:
	if Platform.is_ios():
		return _text("boot.missing.ios", "找不到资源包。请把 resource 文件夹 (里面是 common_assets.pck 等) 拷进本应用的文件夹 (「文件」App → 我的 iPhone/iPad → 天地劫; 或电脑上 Finder/iTunes 的文件共享), 它们由 资源生成工具 从你自己的原版游戏生成。\n\n%s", [diagnose()])
	if Platform.is_android():
		return _text("boot.missing.android", "找不到资源包。请把 resource 文件夹 (里面是 common_assets.pck 等) 放进 %s (电脑上用 adb push), 它们由 资源生成工具 从你自己的原版游戏生成。\n\n%s", [base_dir(), diagnose()])
	if Platform.is_exported():
		return _text("boot.missing.desktop", "找不到资源包 common_assets.pck。请把 resource 文件夹放在游戏目录 (与可执行文件同一目录), 它由 资源生成工具 从你自己的原版游戏生成。", [])
	return _text("boot.missing.dev", "找不到原版资源 (original 目录, 见 README「获取游戏资源」)。", [])


## 只有 common_assets 公用素材、既没有 hd_images 也没有 classic_images 时的提示
func missing_img_hint() -> String:
	return _text("boot.missing.img", "缺少画面资源包。请在 resource 文件夹里再放入 hd_images.pck (AI 高清, 推荐) 或 classic_images.pck (原版画质) 之一, 它们由 资源生成工具 从你自己的原版游戏生成。", [])


static func _text(key: String, fallback: String, args: Array) -> String:
	if UiStrings.has(key):
		return UiStrings.t(key, args)
	return fallback % args if not args.is_empty() else fallback


## 某个资源包是否已挂载 (Assets 据此决定读 res:// 还是目录)
func has(name: String) -> bool:
	return _mounted.has(name)

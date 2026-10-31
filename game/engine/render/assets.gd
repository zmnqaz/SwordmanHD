# SPDX-License-Identifier: GPL-3.0-only
extends Node
## 资源读取 (autoload "Assets")。
## original/ 是原版 1 倍资源, hd4x/ 是 4 倍高清贴图, 目录结构一一对应 (见仓库 README)。
## 运行时直接读文件, 不走 Godot 导入, 资源仓库与引擎保持解耦。游戏数据不在这里读, 一律经内容包 (autoload Content)。
## 内容包 assets/ 目录里的同路径文件优先 (改动包换图/换音), 见 path()/tex()。
## 开发版的原图目录: 游戏仓库里的 original/ 目录 (或符号链接)。
## 资源包 (resource/ 下的 common_assets / hd_images / hd_movies 等, 导出版或 --packs=) 由 ResPacks 挂载, 挂了就读 res://common/、res://hd/;
##   导出版没有包时兼容旧的散文件布局 (exe 旁 original/ hd4x/ 目录)。
## 命令行 (-- 之后): --assets=<目录> 指定游戏仓库根 (含 hd4x/ data/); --original=<目录> 指定原图目录; --gfx=orig 使用原版画质;
##   --tex-mult=4|6|auto 贴图倍数 (默认 auto: 按窗口大小逐张选档, 见 tex())。
##   --tex-budget=MB 贴图缓存显存预算 (默认 768, 0 = 不限; 超了淘汰最久没用且没被节点引用的贴图; 桌面上刚淘汰又要用时自动放大到 2048, --tex-budget-max=MB 改上限, 手动给预算则不放大)。
##   --no-hq 关掉运行时 6 倍生成 (像素画类用 1 倍原图; 显卡不支持时的退路); --max-tex=N 单边纹理上限 (默认桌面 16384/手机 4096, 超过的大图载入时等比缩小)。
## 像素画类贴图 (人物、小贴图, 内容包 textures.json 里方式 px) 不存文件, 由 HqBaker 从原图生成 6 倍 (任何窗口大小都用它, 线性过滤缩放);
## AI 类 (头像/地图/发光大图) 读 hd4x/ 文件, 窗口大于 4 倍时按比例放大绘制。
## 档位注册与逐张选档/回退收敛在 TextureSource (engine/render/texture_source.gd), 这里只做装配与缓存。

const MAX_TEX_DESKTOP := 16384  # GPU 单边纹理上限的保守取值 (Compatibility/GL 3.3 桌面显卡普遍 >= 16384)
const MAX_TEX_MOBILE := 4096    # 手机/平板 GL ES 3.0 常见下限; 超过的图载入时等比缩小, 见 tex()/fit_dim()
const SCALE := 4  # 布局倍数: 原版 320x200 -> 视口 1280x800 (与贴图倍数无关, 窗口缩放由 canvas_items 负责)

var root := ""          # 游戏仓库根: 含 hd4x/ data/
var orig := ""          # 原图目录 (原图仓库)
var face_style := ""     # 头像风格: "" / "classic" = hd4x 里的经典头像, "hk" = 可选 mod 的港漫头像 (face_alt_dir 下同名 webp, 缺哪张退回经典); 由 Game.apply_settings 设
var face_alt_dir := ""  # 港漫头像目录 (含 Face/<目录>/tN.webp; mod/face_hk.pck 挂载后是 res://mod/face_hk, 开发版可用 TDJ_FACE_HK / tools/dev_env.json 的 face_hk 指到目录)
var hd4_dir := ""       # hd4x 目录 (默认 <root>/hd4x, 可由 TDJ_HD4X / tools/dev_env.json 指到别处)
var gfx := "hd"         # "hd" 或 "orig"
var _index := {}        # 小写相对路径 -> 真实相对路径 (原版文件名大小写不统一)
var _texsrc := TextureSource.new()  # 贴图档位源: 档位清单 + 选档/回退 (见 texture_source.gd)
var tex_mult := 0       # 命令行 --tex-mult 强制的贴图倍数, 0 = 自动
var no_hq := false      # 命令行 --no-hq: 不做运行时 6 倍生成 (显卡/驱动跑不了着色器时的退路), 像素画类用 1 倍原图
var hd6x_gen := false   # 像素画类 6 倍运行时生成中 (默认; 无头模式时 false)
var hq_codec := "auto"   # 命令行 --hq-codec=: 烘焙结果的压缩格式 (auto 按显卡选, off 不压缩), 见 TexCodec
var hq_scale := 0        # 命令行 --hq-scale=: 像素画类烘焙倍数 (0 自动: 手机按屏幕分辨率选, 电脑 6), 见 pick_hq_scale
var hq_cache_mb := -1    # 命令行 --hq-cache-mb=: 压缩结果的磁盘缓存上限 (-1 按平台: 桌面 3072 / 手机 1024, 0 不用缓存)
var hq_timeout_s := 20.0  # 命令行 --hq-timeout=秒: 6 倍生成自检/单批超时即自动回退 1 倍原图 (HqBaker.failed)
var hq_break := false
var _baker: HqBaker     # 6 倍运行时生成器, 仅 hd6x_gen 且有真实渲染时创建
var _anims := {}
var _texs := {}
var _sounds := {}
var max_tex := 0        # 单边纹理上限 (0 = 按平台取 MAX_TEX_*; 命令行 --max-tex=N 可改, 测试大图降采样用)
var tex_budget_mb := 768  # 贴图缓存显存预算 (MB, 按 w*h*4 估算; 命令行 --tex-budget=MB): 超了按最近使用淘汰只剩缓存持有的贴图, 见 _evict()
## 预算自适应: 工作集比预算大时 LRU 对循环播放的动画是最坏情形 (每帧都刚被淘汰又要用, 反复读盘 + GPU 重新生成, 实测客栈 15 帧)。
## 刚淘汰的贴图又被请求 = 预算不够; 一段时间内累计 GROW_RELOADS 次就把预算放大 GROW_FACTOR 倍, 直到 tex_budget_max_mb (0 = 不自适应, 手机缺省)。
const PREFETCH_US := 1500    # 预取每帧最多占用的微秒
const PREFETCH_QUEUE := 12   # 预取低优先队列的长度上限 (占位图在烘焙前占 36 倍显存, 不能一次排太多)
const GROW_RELOADS := 24
const GROW_WINDOW := 250     # 帧: 窗口内凑够次数才算 (偶尔回头路不放大)
const GROW_FACTOR := 1.5
const BUDGET_MAX_DESKTOP := 2048
var tex_budget_max_mb := -1   # 预算上限 (MB); -1 = 按平台 (桌面 BUDGET_MAX_DESKTOP, 手机 0); 命令行 --tex-budget-max=MB
var budget_grown := 0         # 累计放大次数 (诊断)
var _trim_task := -1          # 磁盘缓存清理的线程池任务
var _trim_cap_mb := 0         # > 0: 启动 TRIM_DELAY_S 秒后再清缓存 (见 _process); 马上退出的玩家不用为它付出代价
var _trim_wait := 0.0
const TRIM_DELAY_S := 30.0
var _pf_queue: Array = []     # 预取队列 (prefetch_list)
var _pf_i := 0
var _recent_evicted := {}     # 本场景淘汰过的贴图键 (再次请求 = 重复载入)
var _reload_n := 0
var _reload_frame0 := 0
var evicted := 0        # 累计淘汰张数 (诊断)
var loads := 0          # 累计载入张数 (缓存未命中: 读盘 + 像素画类还要排队生成; 诊断, 走路时每张都是一次顿帧风险)
var _tex_bytes := 0     # 缓存里贴图的估算字节数
var _gen := 0           # 场景代数: goto 换场景时 +1, 缓存项带上最近一次被用到的代数, sweep() 只清旧代 (见 begin_scene)
var _sound_gen := {}    # 音效缓存项 -> 代数
var _used := {}         # 原版贴图的不透明区域 (used_rect 缓存, 不随画质变)
var _used_side = null   # 预先算好的不透明区域 {相对路径: [x, y, w, h]} (原版目录 used_rects.json, 打包时生成; null = 还没读, {} = 没有)


func _ready() -> void:
	_init_root_and_args()
	_init_dirs()
	_load_index()
	_init_tiers()
	print("Assets: %s, 原图 %s, 原版文件 %d, 高清贴图 %d (6 倍 %d%s), 画质 %s" % [root, orig, _index.size(), _texsrc.tier_size(4), _texsrc.tier_size(6), " 运行时生成" if hd6x_gen else "", gfx])


## 根目录 (导出版在 exe 旁) 与命令行参数 (--assets= / --original= / --gfx= / --tex-* / --no-hq / --max-tex=)
func _init_root_and_args() -> void:
	root = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	if ResPacks.base_dir() != "":  # 导出版: 资源包 (或旧版散文件目录) 在 exe 旁
		root = ResPacks.base_dir()
	var d := DebugArgs.current()
	if d.assets_root != "":
		root = d.assets_root
	if d.original != "":
		orig = d.original
	if d.gfx_orig:
		gfx = "orig"
	if d.tex_mult >= 0:
		tex_mult = d.tex_mult  # "auto" -> 0
	if d.tex_budget_mb >= 0:
		tex_budget_mb = d.tex_budget_mb
	tex_budget_max_mb = d.tex_budget_max_mb
	if tex_budget_max_mb < 0 and d.tex_budget_mb >= 0:
		tex_budget_max_mb = 0   # 手动指定了预算 = 就要这个预算, 不自动放大 (除非同时给 --tex-budget-max)
	no_hq = no_hq or d.no_hq
	if d.hq_timeout_s >= 0.0:
		hq_timeout_s = d.hq_timeout_s
	hq_codec = d.hq_codec
	hq_cache_mb = d.hq_cache_mb
	hq_scale = d.hq_scale
	hq_break = hq_break or d.hq_break  # 测试用: 故意用坏着色器, 验证自动回退
	if d.max_tex >= 0:
		max_tex = d.max_tex


## 各资源目录与贴图上限
func _init_dirs() -> void:
	# 目录位置: 命令行 > 已挂载的资源包 > 环境变量 TDJ_ORIGINAL/TDJ_HD4X/TDJ_HD6X > tools/dev_env.json > 默认
	# (后三者与 tools/paths.py 同一规则; 不依赖符号链接)
	if orig == "" and ResPacks.has("common_assets"):
		orig = "res://common"
	if orig == "":
		orig = _configured("original", "TDJ_ORIGINAL")
	if orig == "":
		orig = root.path_join("original")
		if not DirAccess.dir_exists_absolute(orig):
			orig = root.path_join("../original").simplify_path()
	hd4_dir = "res://hd" if DirAccess.dir_exists_absolute("res://hd") else _configured("hd4x", "TDJ_HD4X")   # hd_images / hd_movies 任何一个挂载后这个目录就在
	if hd4_dir == "":
		hd4_dir = root.path_join("hd4x")
	face_alt_dir = "res://mod/face_hk" if DirAccess.dir_exists_absolute("res://mod/face_hk") else _configured("face_hk", "TDJ_FACE_HK")   # mod/face_hk.pck 挂载后这个目录就在
	if max_tex <= 0:
		max_tex = MAX_TEX_MOBILE if Platform.is_mobile() else MAX_TEX_DESKTOP
	if tex_budget_max_mb < 0:
		tex_budget_max_mb = 0 if Platform.is_mobile() else BUDGET_MAX_DESKTOP


## 原版文件索引 (小写路径 -> 原路径)
func _load_index() -> void:
	if not FileAccess.file_exists(orig.path_join("index.json")):
		push_error("找不到原版资源 %s/index.json: 设环境变量 TDJ_ORIGINAL 或在 tools/dev_env.json 写 \"original\" (见 docs/Windows开发.md)" % orig)
	var files = _read_json(orig.path_join("index.json"))  # 缺失时 null: 索引为空, 之后取贴图走缺图占位, 不崩 (assert 在导出版里不生效)
	if files is Array:
		for p in files:
			_index[String(p).to_lower()] = p


## 贴图档位注册: 4 倍 (hd4x) 与 6 倍 (运行时烘焙)
func _init_tiers() -> void:
	# 贴图分类表在内容包 (textures.json, 生成工具的脚本): px (像素画) 类运行时从原图生成 6 倍 (HqBaker);
	# AI 类的高清文件在 hd4x/ (hd_images.pck, 可选), 以它自带的目录 hd4x.json 为准, 没有就显示原图
	var px_idx := {}
	var classes = _content().json("textures.json") if _content() else null
	if classes is Dictionary:
		for k in classes["textures"]:
			if classes["textures"][k] == "px":
				px_idx[k] = true
	var ai_idx := {}
	var hd_path := hd4_dir.path_join("hd4x.json")
	if FileAccess.file_exists(hd_path):
		var hd_files := _textures_of(hd_path)
		for k in hd_files:
			if hd_files[k] != "px":  # 旧版 hd4x.json 里还记着 px 项, 忽略
				ai_idx[k] = true
	_texsrc.orig_dir = orig
	_texsrc.hd_enabled = func() -> bool: return gfx == "hd"
	_texsrc.want_mult = _want_mult
	_texsrc.add_tier(4, hd4_dir, ai_idx)
	if not no_hq and HqBaker.available():  # 无头模式没有 GPU 绘制, 不注册: px 类用 1 倍原图 (测试/CI 不看画面)
		hd6x_gen = true
		_baker = HqBaker.new()
		_baker.timeout_s = hq_timeout_s
		if hq_break:
			_baker.shaders = {"fill": Shader.new(), "hqx": Shader.new(), "xbrz": Shader.new()}
			(_baker.shaders["fill"] as Shader).code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0) THIS IS BROKEN; }"
		var out_scale := pick_hq_scale(Vector2(DisplayServer.window_get_size()), Platform.is_mobile(), hq_scale if hq_scale > 0 else saved_hq_scale())
		_baker.out_scale = out_scale
		if Platform.is_mobile():   # 手机 CPU 弱 (压缩 / 读回都比电脑慢好几倍): 少排几张压缩任务, 预取让出更多帧, 免得持续占满 CPU 发热掉帧
			_baker.max_comp_pending = 6
			_baker.low_gap_frames = 4
		_baker.codec = TexCodec.pick(hq_codec)   # 烘焙结果压成显卡原生压缩格式 (显存约 1/4); 显卡不支持/off 则 ""
		var cache_mb := hq_cache_mb if hq_cache_mb >= 0 else (1024 if Platform.is_mobile() else 3072)
		_baker.cache_on = _baker.codec != "" and cache_mb > 0
		add_child(_baker)
		_texsrc.add_tier(out_scale, "", px_idx, true)
		if _baker.cache_on:   # 缓存超上限就删最旧的: 延后 TRIM_DELAY_S 秒再开始 (后台线程, 只动 user://hq_cache); 任务 id 留着, 退出时要等它 (见 _exit_tree / prepare_exit)
			_trim_cap_mb = cache_mb


## 设定「贴图精度」(settings.json 的 hq 键: 0 自动 / 6 / 4 / 3): 生成器启动时就要定倍数, 比 Game 读设定还早, 所以这里直接读文件 (改了设定要重启才生效)。
## 缺文件 / 非法值当自动 (0); 命令行 --hq-scale 优先 (调用处先看它)。path 参数给测试用, 别在测试里写真正的设定文件
static func saved_hq_scale(path := "user://settings.json") -> int:
	var d = SaveFile.read_json(path)
	if not (d is Dictionary) or not (d.get("hq") is int or d.get("hq") is float):
		return 0
	var v := int(d["hq"])
	return v if v in [3, 4, 6] else 0


## 像素画类烘焙倍数: 显式指定 (3/4/6) 优先; 否则手机按屏幕分辨率选 —— 窗口里 1 个原版像素占 m 个物理像素 (m = min(宽/320, 高/200)),
## m <= 3.3 用 3 倍, <= 4.6 用 4 倍, 否则 6 倍 (1920x1080 / 2400x1080 横屏 m = 5.4 用 6 倍; 1280x720 m = 3.6 用 4 倍)。电脑固定 6 倍 (窗口可随时改大小, 6 倍已验证)。
## 倍数低了贴图面积降到 (n/6)^2: 读回、压缩、显存、磁盘缓存都按比例降; 流水线仍按 6 倍烘焙, 最后一道 GPU 线性缩小。
static func pick_hq_scale(win: Vector2, mobile: bool, forced := 0) -> int:
	if forced in [3, 4, 6]:
		return forced
	if not mobile or win.x <= 0.0 or win.y <= 0.0:
		return HqBaker.SCALE
	var m := minf(win.x / 320.0, win.y / 200.0)
	if m <= 3.3:
		return 3
	if m <= 4.6:
		return 4
	return HqBaker.SCALE


## 6 倍生成器状态 (perf-log 与排查用): 是否启用/是否已自动回退/原因/读回异常数
func hq_report() -> Dictionary:
	if _baker == null:
		return {"hq": "off" if no_hq else ("headless" if not HqBaker.available() else "tier"), "hq_failed": false, "hq_fail_reason": "", "hq_generated": 0, "hq_bad_readbacks": 0}
	return {"hq": "gen", "hq_failed": _baker.failed, "hq_fail_reason": _baker.fail_reason, "hq_generated": _baker.generated, "hq_bad_readbacks": _baker.bad_readbacks,
		"hq_scale": _baker.out_scale, "hq_codec": _baker.codec, "hq_cache": _baker.cache_on, "hq_cache_hits": _baker.cache_hits, "hq_cache_writes": _baker.cache_writes, "hq_compressed": _baker.compressed}


## 目标贴图倍数: 命令行/设定强制的倍数优先, 否则跟随窗口显示倍数 (TextureSource 升档判断用)
func _want_mult() -> float:
	return float(tex_mult) if tex_mult > 0 else display_mult()


## 环境变量 > tools/dev_env.json 里的路径 (相对路径相对 root); 没配返回 ""。导出版不读 dev_env.json
func _configured(key: String, env_name: String) -> String:
	var v := OS.get_environment(env_name)
	if v == "" and not Platform.is_exported():
		var cfg := root.path_join("tools/dev_env.json")
		if FileAccess.file_exists(cfg):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(cfg))
			if d is Dictionary:
				v = String(d.get(key, ""))
	if v == "":
		return ""
	return (v if v.is_absolute_path() else root.path_join(v)).simplify_path()


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("打不开 " + path)
		return null
	return JSON.parse_string(f.get_as_text())


## 档位清单 (hd4x.json) 的 "textures" 字典; 文件损坏当作空清单 (该档整体回退原图), 并报错
func _textures_of(path: String) -> Dictionary:
	var d = _read_json(path)
	if d is Dictionary and d.get("textures") is Dictionary:
		return d["textures"]
	push_error("贴图档位清单不可用: " + path)
	return {}


## 原版文件索引是否已载入 (空 = 找不到原版资源, 启动自检据此提示)
func has_index() -> bool:
	return not _index.is_empty()


## 把任意大小写的相对路径解析成 original/ 里真实存在的路径, 找不到返回 ""
func resolve(rel: String) -> String:
	return _index.get(rel.to_lower(), "")


## original/ 里某目录下 (含子目录) 的所有文件 (真实相对路径)
func list_files(dir_rel: String) -> Array:
	var pre := dir_rel.to_lower().trim_suffix("/") + "/"
	var out: Array = []
	for k in _index:
		if k.begins_with(pre):
			out.append(_index[k])
	return out


func exists(rel: String) -> bool:
	return _index.has(rel.to_lower()) or _pack_file(rel) != ""


## 内容包 assets/ 里的覆盖文件 (改动包、原创包用; 见 engine/content/content_db.gd asset_file), 没有返回 ""
func _pack_file(rel: String) -> String:
	var c := _content()
	return c.asset_file(rel) if c else ""


## 头像风格 hk 时某张头像在 mod 包里的 webp 路径; 不是头像 / 风格不是 hk / 没有该包 / 该帧不在包里 / 原版画质时返回 "" (用经典头像)
func _face_alt_file(rel: String) -> String:
	if face_style != "hk" or face_alt_dir == "" or gfx != "hd" or not rel.to_lower().begins_with("face/"):
		return ""
	var f := face_alt_dir.path_join(rel.get_basename() + ".webp")
	return f if FileAccess.file_exists(f) else ""


## 可选的港漫 E2 头像是否可用 (设定里「头像风格」一行据此显示)
func face_alt_available() -> bool:
	return face_alt_dir != "" and DirAccess.dir_exists_absolute(face_alt_dir.path_join("Face"))


## 内容包服务 (autoload 节点 "Content"; 按节点取, 不直接引用全局名, 见 tests/test_engine_deps.gd)
func _content() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Content")


## 资源文件的实际路径: 内容包 assets/ 覆盖优先, 否则原图仓库
func path(rel: String) -> String:
	var pf := _pack_file(rel)
	if pf != "":
		return pf
	var r := resolve(rel)
	assert(r != "", "资源不存在: " + rel)
	return orig.path_join(r)


## 动画数据 (anim.json), dir 为动画目录, 如 "Sprite/man001/001MAN"
func anim(dir: String) -> Dictionary:
	var key := dir.to_lower()
	if not _anims.has(key):
		var data = _read_json(path(dir + "/anim.json"))
		if not data is Dictionary:
			push_error("动画数据不可用: " + dir)
			data = {"frames": [{"time": 0, "parts": [], "sound": -1}], "textures": [], "sounds": []}  # 一张空帧, 播放方不会越界
		data["dir"] = dir if _pack_file(dir + "/anim.json") != "" else resolve(dir + "/anim.json").get_base_dir()
		_anims[key] = data
	return _anims[key]


## 显示倍数: 窗口里 1 个原版像素占多少物理像素 (canvas_items + keep, 16:10 留边)
func display_mult() -> float:
	return ScreenLayout.display_mult()


## 贴图: 高清模式逐张选档 (scale=1/倍数), 都没有则用原版 (scale=1, 需最近邻采样)。
## 像素画类只有 6 倍 (运行时生成), 任何窗口都用它; AI 类只有 hd4x。窗口大小变化在下次 clear_cache() (换场景) 后生效。
## 档位选择与文件路径解析在 TextureSource.pick (唯一实现), 这里只做内容包覆盖与纹理缓存。
## 返回 {"texture": Texture2D, "scale": float, "hd": bool}
func tex(rel_in: String) -> Dictionary:
	return _tex(rel_in, false)


## 预取一批贴图 (按给定顺序; 调用方把离玩家近的排前面): 场景载入后慢慢把运行时烘焙的贴图载入 (磁盘缓存命中) 或烘焙好, 走到哪都不用现烘焙。
## Assets 自己逐帧推进并限流: 每帧最多占 PREFETCH_US 微秒, 低优先烘焙队列满了就等 (占位图在烘焙完成前占 36 倍显存, 不能一次排很多);
## 屏幕上用到的会自动提到紧急队列。换场景 (begin_scene) 清掉没做完的; 没有运行时烘焙器 (无头/--no-hq/已回退) 时什么也不做。
func prefetch_list(rels: Array) -> void:
	_pf_queue = rels if _baker != null and not _baker.failed else []
	_pf_i = 0


## 退出前调: 让后台的缓存扫描 / 清理马上停手 (TexCodec.cancel), 之后 _exit_tree 里的等待几乎是瞬间。没起过的清理任务也取消
func prepare_exit() -> void:
	_trim_cap_mb = 0
	TexCodec.cancel = true


func _exit_tree() -> void:
	TexCodec.cancel = true
	if _trim_task >= 0:   # 线程池任务必须等待完成, 否则退出时释放回调崩溃
		WorkerThreadPool.wait_for_task_completion(_trim_task)
		_trim_task = -1


func _process(delta: float) -> void:
	if _trim_cap_mb > 0:
		_trim_wait += delta
		if _trim_wait >= TRIM_DELAY_S:
			_trim_task = WorkerThreadPool.add_task(TexCodec.cache_trim.bind(_trim_cap_mb * 1048576), false, "hq cache trim")
			_trim_cap_mb = 0
	if _pf_i < _pf_queue.size():
		_prefetch_step()


func _prefetch_step() -> void:
	if _baker == null or _baker.failed:
		_pf_queue = []
		return
	var t0 := Time.get_ticks_usec()
	while _pf_i < _pf_queue.size() and _baker.low_pending() < PREFETCH_QUEUE and _baker.urgent_pending() == 0:
		var rel := String(_pf_queue[_pf_i])
		_pf_i += 1
		var r := resolve(rel)
		if r != "" and not _texs.has(r) and _pack_file(rel) == "" and bool(_texsrc.pick(r)["gen"]):
			_tex(rel, true)
		if Time.get_ticks_usec() - t0 > PREFETCH_US:
			return
	if _pf_i >= _pf_queue.size():
		_pf_queue = []


func _tex(rel_in: String, low: bool) -> Dictionary:
	var l0 := loads
	var t0 := Time.get_ticks_usec()
	var r := _tex_load(rel_in, low)
	if loads != l0:   # 缓存未命中, 这次真的载入了: 记下耗时 (诊断页列最慢的几张, 看「鼠标扫到新区域卡一下」卡在哪张图)
		_note_load(rel_in, (Time.get_ticks_usec() - t0) / 1000.0)
	return r


const SLOW_LOADS_KEEP := 6
var _slow_loads: Array = []   # [{rel, ms}], 按耗时从大到小, 只留最慢的 SLOW_LOADS_KEEP 张 (本次运行)


func _note_load(rel: String, ms: float) -> void:
	if _slow_loads.size() >= SLOW_LOADS_KEEP and ms <= float(_slow_loads[-1]["ms"]):
		return
	_slow_loads.append({"rel": rel, "ms": ms})
	_slow_loads.sort_custom(func(a, b): return float(a["ms"]) > float(b["ms"]))
	if _slow_loads.size() > SLOW_LOADS_KEEP:
		_slow_loads.pop_back()


func _tex_load(rel_in: String, low: bool) -> Dictionary:
	var pf := _pack_file(rel_in)
	if pf != "":  # 内容包自带的贴图: 原版 1 倍大小, 最近邻采样
		if not _texs.has(pf):
			var pimg := Image.load_from_file(pf)
			_store(pf, {"texture": _missing_tex() if pimg == null else ImageTexture.create_from_image(pimg), "scale": 1.0, "hd": false})
		return _touch(_texs[pf])
	var rel := resolve(rel_in)
	if rel == "":  # 清单里没有 (assert 在导出版不生效): 报错并给占位图, 不让整个场景崩
		push_error("贴图不存在: " + rel_in)
		return {"texture": _missing_tex(), "scale": 1.0, "hd": false}
	var alt := _face_alt_file(rel)
	if alt != "":   # 头像风格 = 港漫: 读可选包里的同名头像 (4 倍, 与 hd4x 的头像同尺寸同对位), 缺这一张就往下走经典头像
		if not _texs.has(alt):
			var aimg := Image.load_from_file(alt)
			if aimg != null:
				_store(alt, {"texture": ImageTexture.create_from_image(aimg), "scale": 0.25, "hd": true})
		if _texs.has(alt):
			return _touch(_texs[alt])
	if not _texs.has(rel):
		loads += 1
		if _recent_evicted.has(rel):
			_note_reload()
		var t := _texsrc.pick(rel)
		var md5 := ""
		if t["gen"] and _baker != null and not _baker.failed and _baker.cache_on and _baker.codec != "":
			md5 = FileAccess.get_md5(t["file"])   # 缓存键 = 原图内容: 内容相同的图 (五个客栈共用的物件) 只烘焙一次
			var ctx := _baker.cache_lookup(md5)
			if ctx != null and fit_dim(Vector2i(ctx.get_width(), ctx.get_height()), max_tex) >= 1.0:
				_store(rel, {"texture": ctx, "scale": float(t["scale"]), "hd": t["hd"], "bytes": _baker.last_bytes})
				return _touch(_texs[rel])
		var img := Image.load_from_file(t["file"])
		if img == null:
			push_error("贴图读取失败: " + String(t["file"]))
			_store(rel, {"texture": _missing_tex(), "scale": 1.0, "hd": false})
		else:
			var scale := float(t["scale"])
			var gen: bool = t["gen"] and _baker != null and not _baker.failed
			if t["gen"] and not gen:  # 生成器未启用或已自动回退 (着色器/驱动不行): 1 倍原图, 最近邻
				scale = 1.0
				t["hd"] = false
			if gen and fit_dim(img.get_size() * _baker.out_scale, max_tex) < 1.0:  # 烘焙倍数超过显卡单边上限: 不生成, 用原图
				gen = false
				scale = 1.0
				t["hd"] = false
			var f := fit_dim(img.get_size(), max_tex)
			if f < 1.0 and not gen:  # 超过显卡单边上限的大图 (如第 17 关 4 倍图 2640x8928): 等比缩小, 显示尺寸 (纹理尺寸 x scale) 不变
				var w0 := img.get_width()
				img.resize(maxi(1, roundi(img.get_width() * f)), maxi(1, roundi(img.get_height() * f)), Image.INTERPOLATE_LANCZOS)
				scale *= float(w0) / float(img.get_width())
			var tx: Texture2D = _baker.request(img, md5, _on_final.bind(rel), low) if gen else ImageTexture.create_from_image(img)
			var e := {"texture": tx, "scale": scale, "hd": t["hd"]}
			if gen and low:
				e["low"] = true
			_store(rel, e)
	var hit: Dictionary = _texs[rel]
	if hit.has("low") and not low:   # 预取的贴图被屏幕用到了: 提到紧急队列
		hit.erase("low")
		_baker.promote(hit["texture"])
	return _touch(hit)


## 烘焙结果压缩换入后回调: 把这张的显存记账从 RGBA8 估算改成真实字节 (被淘汰/换掉的不管)
func _on_final(tex: Texture2D, bytes: int, rel: String) -> void:
	var e = _texs.get(rel)
	if e == null or e["texture"] != tex:
		return
	_tex_bytes += bytes - int(e["bytes"])
	e["bytes"] = bytes


## 缓存项记账: 估算字节 (w*h*4), 超预算先淘汰再放 (新项本帧用过, 不会被淘汰)
func _store(key: String, e: Dictionary) -> void:
	var tx: Texture2D = e["texture"]
	if not e.has("bytes"):   # 缓存命中的压缩纹理已带真实字节
		e["bytes"] = tx.get_width() * tx.get_height() * 4
	_texs[key] = e
	_tex_bytes += int(e["bytes"])
	_touch(e)
	if tex_budget_mb > 0 and _tex_bytes > tex_budget_mb * 1048576:
		_evict()


## 记录使用: 场景代数 (sweep 用) 与最近使用帧号 (LRU 用)
func _touch(e: Dictionary) -> Dictionary:
	e["gen"] = _gen
	e["used"] = Engine.get_process_frames()
	return e


func _erase_tex(key: String) -> void:
	if _texs.has(key):
		_tex_bytes -= int(_texs[key].get("bytes", 0))
		_texs.erase(key)


## 缓存项里纹理的引用计数 (经同一个函数取, 计数口径与 _idle_rc 一致)
static func _rc(e: Dictionary) -> int:
	return (e["texture"] as RefCounted).get_reference_count()


## 「只剩缓存持有」时的引用计数基线 (现场量一个只放进字典的纹理, 不假设引擎内部口径)
static var _idle_rc_cache := -1

static func _idle_rc() -> int:
	if _idle_rc_cache < 0:
		var probe := {"texture": ImageTexture.new()}  # 必须是变量里的字典 (字面量临时对象多一个引用, 实测 4 vs 3)
		_idle_rc_cache = _rc(probe)
	return _idle_rc_cache


## 超预算: 淘汰最久没用的、且没有任何节点/生成任务还拿着引用的贴图, 降到预算 90% (留余量, 避免每次插入都扫一遍)。
## 场景节点 (Sprite2D 等) 或烘焙队列持有的纹理引用计数高于基线, 绝不会被淘汰; 被淘汰的下次请求重新载入/生成 (像素画类占位 1 帧)。
func _evict() -> void:
	var now := Engine.get_process_frames()
	var idle := _idle_rc()
	var cand: Array = []
	for k in _texs:
		var e: Dictionary = _texs[k]
		if int(e["used"]) < now and _rc(e) <= idle:
			cand.append(k)
	cand.sort_custom(func(a, b): return int(_texs[a]["used"]) < int(_texs[b]["used"]))
	var target := int(tex_budget_mb * 1048576 * 0.9)
	var n := 0
	for k in cand:
		if _tex_bytes <= target:
			break
		_recent_evicted[k] = true
		_erase_tex(k)
		n += 1
	evicted += n


## 刚淘汰的贴图又被请求了一次: 窗口内累计够多就放大预算 (见 GROW_RELOADS)
func _note_reload() -> void:
	var now := Engine.get_process_frames()
	if _reload_n == 0 or now - _reload_frame0 > GROW_WINDOW:
		_reload_n = 0
		_reload_frame0 = now
	_reload_n += 1
	if _reload_n < GROW_RELOADS or tex_budget_mb <= 0 or tex_budget_mb >= tex_budget_max_mb:
		return
	tex_budget_mb = mini(int(tex_budget_mb * GROW_FACTOR), tex_budget_max_mb)
	budget_grown += 1
	_reload_n = 0
	_recent_evicted.clear()


## 图片按单边上限 max_dim 需要的缩小比例 (<= 1; 不超限为 1)。纯函数, 测试用
static func fit_dim(size: Vector2i, max_dim: int) -> float:
	var m := maxi(size.x, size.y)
	return 1.0 if m <= max_dim or max_dim <= 0 else float(max_dim) / float(m)


## 缺图占位 (洋红 2x2, 最近邻): 明显可见又不崩
func _missing_tex() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1, 1))
	return ImageTexture.create_from_image(img)


## 原版 1 倍贴图的不透明区域 (排版用帧外框一律按它算, 与画质 hd4x/hd6x 无关)
func used_rect(rel_in: String) -> Rect2i:
	var key := rel_in.to_lower()
	if not _used.has(key):
		var pf := _pack_file(rel_in)
		var rel := resolve(rel_in)
		var file := pf if pf != "" else _texsrc.file_at(rel, 0)
		if pf == "" and not FileAccess.file_exists(file):   # 原版 1 倍图不在 (没装 classic_images.pck, 只用高清包): 读打包时预先算好的
			var r: Variant = _used_sidecar().get(rel)
			if r is Array and r.size() == 4:
				_used[key] = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
				return _used[key]
		var img := Image.load_from_file(file)
		_used[key] = img.get_used_rect() if img else Rect2i()
	return _used[key]


func _used_sidecar() -> Dictionary:
	if _used_side == null:
		var f := orig.path_join("used_rects.json")
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(f)) if FileAccess.file_exists(f) else null
		_used_side = d if d is Dictionary else {}
	return _used_side


## 画面资源是否齐: 打包时把「高清包里有高清版的原版 PNG」拆进了 classic_images.pck (公用包 common_assets 里留 used_rects.json 作标记),
## 这时必须装 hd_images.pck 或 classic_images.pck 之一, 否则头像/地图等没有图可显示。没拆过 (标记不存在) 或开发版目录都算齐。
func image_packs_ok() -> bool:
	var side := _used_sidecar()
	if side.is_empty():
		return true
	for rel in side.keys().slice(0, 5):
		if FileAccess.file_exists(orig.path_join(String(rel))) or bool(_texsrc.pick(String(rel))["hd"]):
			return true
	return false


## 切换场景时释放贴图与音效缓存 (高清贴图很占显存, 否则跨关卡会越积越多)
func clear_cache() -> void:
	_texs.clear()
	_recent_evicted.clear()
	_tex_bytes = 0
	_sounds.clear()
	_sound_gen.clear()


## 换场景: 开新一代。之后新场景用到的缓存项 (命中旧项也算) 记新代数, 旧场景释放后调 sweep() 只清没被新场景用到的。
## 不能在 goto 里直接 clear_cache (它推迟到旧场景释放后执行, 那时新场景 _ready 已载入的贴图会被一并清掉, 之后同一张图被重复载入/重复生成)。
func begin_scene() -> void:
	_gen += 1
	_pf_queue = []


## 清掉旧代 (begin_scene 之前最后一次使用) 的贴图与音效缓存; 仍被节点引用的纹理由引用计数保活
func sweep() -> void:
	_recent_evicted.clear()
	for k in _texs.keys():
		if int(_texs[k].get("gen", -1)) < _gen:
			_erase_tex(k)
	for k in _sounds.keys():
		if int(_sound_gen.get(k, -1)) < _gen:
			_sounds.erase(k)
			_sound_gen.erase(k)


func cache_size() -> int:
	return _texs.size()


## 贴图缓存诊断 (性能采样 --perf-log 用): 张数、估算显存 (RGBA8 w*h*4, 不含 mipmap)、按目录汇总的前 N 名
func cache_report(top := 5) -> Dictionary:
	var by_dir := {}
	var total := 0
	for k in _texs:
		var b := int(_texs[k].get("bytes", 0))
		total += b
		var d := String(k).get_base_dir().get_base_dir() if String(k).count("/") > 2 else String(k).get_base_dir()
		by_dir[d] = int(by_dir.get(d, 0)) + b
	var keys := by_dir.keys()
	keys.sort_custom(func(a, b): return by_dir[a] > by_dir[b])
	var out := []
	for k in keys.slice(0, top):
		out.append("%s %.1fMB" % [k, by_dir[k] / 1048576.0])
	return {"count": _texs.size(), "mb": snappedf(total / 1048576.0, 0.1), "top": out,
		"loads": loads, "evicted": evicted, "budget_mb": tex_budget_mb, "budget_grown": budget_grown, "baker_pending": _baker.pending() if _baker else 0, "baker_pool": _baker.pool_size() if _baker else 0}


## 已载入贴图的清晰度分布 (诊断页用): 按有效倍数 (1 / 显示缩放系数) 分档, 1 倍 = 原图最近邻 (没有高清版 / 生成器没启用或已回退 / 单边超过显卡上限退回原图),
## 单边超限被缩小的大图倍数会低于档位 (如 4 倍图缩一半 = 2 倍); low = 预取排队中、还是占位图 (最近邻放大, 烘焙完成才清晰)
func sharpness_report() -> Dictionary:
	var by := {}
	var low := 0
	for k in _texs:
		var e: Dictionary = _texs[k]
		var m := maxi(1, roundi(1.0 / maxf(0.001, float(e.get("scale", 1.0)))))
		by[m] = int(by.get(m, 0)) + 1
		if e.has("low"):
			low += 1
	return {"by_mult": by, "low": low, "total": _texs.size()}


## 画质诊断页 (engine/ui/diag_panel.gd) 要的全部贴图信息: 生成器状态 + 自动选的倍数 + 清晰度分布 + 缓存 + 上限。组装层经 GameContext.diag_info 交给诊断页
func diag_report() -> Dictionary:
	var d := hq_report()
	d["auto_scale"] = pick_hq_scale(Vector2(DisplayServer.window_get_size()), Platform.is_mobile(), 0)
	d["sharp"] = sharpness_report()
	d["cache"] = cache_report(0)
	d["max_tex"] = max_tex
	d["slow_loads"] = _slow_loads.duplicate(true)
	return d


## 音效文件的实际路径: 原版目录里是无损 wav (开发版直接读); 导出版的 common_assets.pck 里为省体积转成了同名 .ogg (生成工具的脚本), 先找 wav 再找 ogg。都没有返回 ""
func sound_file(rel: String) -> String:
	var wav := path(rel)
	if FileAccess.file_exists(wav):
		return wav
	var ogg := wav.get_basename() + ".ogg"
	return ogg if FileAccess.file_exists(ogg) else ""


func sound(rel: String) -> AudioStream:
	if not _sounds.has(rel):
		var f := sound_file(rel)
		var s: AudioStream = null
		if f.ends_with(".ogg"):
			s = AudioStreamOggVorbis.load_from_file(f)
		elif f != "":
			s = AudioStreamWAV.load_from_file(f)
		if s == null:
			push_error("音效读取失败: " + rel)
		_sounds[rel] = s
	_sound_gen[rel] = _gen
	return _sounds[rel]


func music(rel: String) -> AudioStream:
	var s := AudioStreamMP3.load_from_file(path(rel))
	if s == null:
		push_error("音乐读取失败: " + rel)
		return null
	s.loop = true   # 场景音乐循环到场景结束 (eae7c5cc 去重复时误删了, 曲子放完一遍就静音: 战场/城镇都靠这里)
	return s


## 过场视频: 原版分辨率 game/classic/movies/*.ogv (生成工具的脚本; 导出版在 classic_movies.pck, 同一 res:// 路径);
## 有 AI 高清版 (生成工具的脚本 生成在高清目录 (开发机 hd4x/, 包内 res://hd/) 的同名路径, 导出版在 hd_movies.pck) 就优先用高清版, 没有就用 classic_movies.pck 的原版。name 如 "Movie/Movie_00"。
func movie_exists(name: String) -> bool:
	return FileAccess.file_exists(_movie_file(name))


func movie(name: String) -> VideoStream:
	var s := VideoStreamTheora.new()
	s.file = _movie_file(name)
	return s


func _movie_file(name: String) -> String:
	var hd := hd4_dir.path_join(name + ".ogv")
	if gfx == "hd" and FileAccess.file_exists(hd):
		return hd
	return "res://classic/movies/%s.ogv" % name


## 游戏字体: 只用矢量字库字体, 清单与回退见 UiFonts (content ui_theme/fonts.json)。
## 返回的是「当前字体」的代理 (FontVariation): 换字体时只换代理的 base_font, 已创建的 Label 等立即跟着变,
## 自绘文字 (UiText) 监听 font_changed 重画。缺字由 Godot 的系统字体回退补 (FontFile.allow_system_fallback, 默认开)。
## 命令行 --sysfont 改用系统 Noto Serif CJK 明体 (对比用)。
signal font_changed

var font_id := ""          # 当前字体 id (UiFonts 清单里的 id)
var _faces := {}           # id -> FontFile
var _proxy := {}           # bold(bool) -> FontVariation


func font(bold := false) -> Font:
	if font_id == "":
		font_id = UiFonts.default_id()
	if not _proxy.has(bold):
		var v := FontVariation.new()
		v.base_font = _face(font_id)
		_proxy[bold] = v
		_style(bold)
	return _proxy[bold]


## 设定里的字体 id 换成当前字体: 未知/缺失的回退清单缺省; 没变化不动
func set_font(id: String) -> void:
	var e := UiFonts.get_or_default(id)
	var nid := String(e["id"])
	if nid == font_id and not _proxy.is_empty():
		return
	font_id = nid
	for bold in _proxy:
		_proxy[bold].base_font = _face(font_id)
		_style(bold)
	font_changed.emit()


func _style(bold: bool) -> void:
	var e := UiFonts.get_or_default(font_id)
	var v: FontVariation = _proxy[bold]
	v.variation_embolden = float(e.get("embolden", 0.5)) if bold else 0.0  # 没有单独的粗体文件, 用加粗变体


func _face(id: String) -> Font:
	if DebugArgs.current().sysfont:
		if not _faces.has("sys"):
			var sf := FontFile.new()
			sf.load_dynamic_font("/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc")
			sf.set_face_index(0, 2)  # 简体中文 (SC)
			_faces["sys"] = sf
		return _faces["sys"]
	if not _faces.has(id):
		var f := FontFile.new()
		var path := String(UiFonts.get_or_default(id)["file"])
		f.load_dynamic_font(path)  # 字体文件不导入 (.import 为 keep), 原样进主 pck, 开发版/导出版都按 res:// 读
		if String(UiFonts.get_or_default(id).get("hinting", "")) == "none":   # 点阵风字体 (原版点阵): 自动微调会把对齐像素格的方块笔画拉歪
			f.hinting = TextServer.HINTING_NONE
		var full := UiFonts.complete_id()
		if id != full:   # 文楷/宋体是裁过的子集 (缺省的文楷也是), 缺的字 (繁体字等) 先回退到自带的完整字库 (清单里 full 标记的, 缺省思源黑体), 再到系统字体
			f.fallbacks = [_face(full)]
		_faces[id] = f
	return _faces[id]

# SPDX-License-Identifier: GPL-3.0-only
class_name TextureSource
extends RefCounted
## 贴图档位源: 「逻辑资源相对路径 → 实际档位与文件路径」的唯一解析处 。
## 档位 (tier) = 同一张原图的放大版 (hd4x/hd6x/…), 按 mult 升序注册; original (1 倍原图) 永远兜底, 不注册。
## 选档规则见 pick(): 在有该图的档里从低到高走, 起步选最低档, 每上一层要求目标倍数高出当前档 EPS 以上
## (窗口 1281 宽 = 4.003 倍仍算 4 档), 没有任何档有该图则回退原图 —— 与旧 Assets.tex 的逐张选档逐位一致。
## 依赖注入: 高清开关 hd_enabled 与目标倍数 want_mult 由宿主 (Assets autoload) 提供, 本类不读窗口/命令行/环境,
## 无场景树也能实例化 (tests/test_texture_source.gd)。
## 「只存最高档 + 构建生成低档」(方案 A/C: hd6x 不入库, 像素画类运行时生成) 的接入点:
##   构建期生成低档 → 打包脚本按 tier_mults() 产出各档 pck, 运行时按档注册即可 (dir 指到 pck 挂载后的路径,
##   FileAccess/Image.load_from_file 原样可读); 缺哪档就少注册哪档, 回退语义不变。本类不实现构建管线。

const EPS := 0.01  # 升档余量: 旧实现的 "want > 4.01 才上 6 倍" 泛化成 "want > 当前档 + EPS"

var orig_dir := ""                  # 原图目录 (1 倍, 永远兜底)
var hd_enabled := Callable()        # () -> bool: 高清开关 (--gfx=orig / 设定「原版画质」时 false), 未注入视为开
var want_mult := Callable()         # () -> float: 目标显示倍数 (窗口倍数或 --tex-mult 强制值), 升档判断时才调
var tiers: Array[Dictionary] = []   # {mult: int, dir: String, index: Dictionary, gen: bool}, mult 升序; index = 真实相对路径 -> true


## 注册一个档位 (按 mult 升序插入)。index 的键是按原图索引解析后的真实相对路径 (hd4x.json / hd6x.json
## 的 "textures" 字典取键); 清单缺失就不注册该档, 运行时自然整体回退, 与旧实现一致。
## gen = 运行时生成档 (没有文件, dir 为空): pick 返回原图路径并带 gen=true, 由宿主从原图生成 (Assets → HqBaker)。
func add_tier(mult: int, dir: String, index: Dictionary, gen := false) -> void:
	var t := {"mult": mult, "dir": dir, "index": index, "gen": gen}
	var i := 0
	while i < tiers.size() and int(tiers[i]["mult"]) < mult:
		i += 1
	tiers.insert(i, t)


## 已注册的档位倍数 (升序)。打包脚本决定要产哪些档的 pck 时以此为清单。
func tier_mults() -> Array[int]:
	var out: Array[int] = []
	for t in tiers:
		out.append(int(t["mult"]))
	return out


## 某档清单里的贴图数 (Assets 启动日志用; 未注册返回 0)
func tier_size(mult: int) -> int:
	for t in tiers:
		if int(t["mult"]) == mult:
			return (t["index"] as Dictionary).size()
	return 0


## 选档: 返回 {"mult": int, "file": String, "scale": float, "hd": bool, "gen": bool} (mult=0 即原图 1 倍, scale=1 最近邻;
## gen=true 时 file 是原图, 需按 mult 倍生成)。
## rel 必须是已按原图索引解析成真实大小写的相对路径 (Assets.resolve 之后; 高清清单按真实路径存)。
func pick(rel: String) -> Dictionary:
	var mult := 0
	if not hd_enabled.is_valid() or bool(hd_enabled.call()):
		var want := -1.0
		for t in tiers:
			if not (t["index"] as Dictionary).has(rel):
				continue
			if mult == 0:
				mult = int(t["mult"])  # 有该图的最低档起步 (旧实现: 高清入口在 hd4x)
				continue
			if want < 0.0:  # 有更高档时才需要目标倍数, 到这里才算 (惰性, 与旧实现一致)
				want = float(want_mult.call()) if want_mult.is_valid() else 0.0
			if want > mult + EPS:
				mult = int(t["mult"])  # 目标倍数够高才升档
	return _entry(rel, mult)


## 指定档位的文件路径 (mult=0 原图, 无 webp 偏好 —— used_rect 等只要 1 倍原图的地方用; mult 须已注册)。
func file_at(rel: String, mult: int) -> String:
	return String(_entry(rel, mult)["file"])


func _entry(rel: String, mult: int) -> Dictionary:
	if mult > 0:
		var dir := ""
		for t in tiers:
			# 同倍数可以有两档 (手机把运行时烘焙档降成 4 倍, 与 AI 类 hd4x 的 4 倍档撞车): 优先取清单里有这张图的那一档
			if int(t["mult"]) == mult and (t["index"] as Dictionary).has(rel):
				if t["gen"]:
					return {"mult": mult, "file": orig_dir.path_join(rel), "scale": 1.0 / mult, "hd": true, "gen": true}
				dir = String(t["dir"])
				break
		if dir == "":   # 没有哪一档的清单里有它: 退回第一个同倍数的档 (旧行为, file_at 等只给倍数不保证清单里有)
			for t in tiers:
				if int(t["mult"]) == mult:
					if t["gen"]:
						return {"mult": mult, "file": orig_dir.path_join(rel), "scale": 1.0 / mult, "hd": true, "gen": true}
					dir = String(t["dir"])
					break
		if dir != "":
			var file := dir.path_join(rel)
			var webp := file.get_basename() + ".webp"  # 高清贴图存 WebP (AI 放大 q92 / 像素画无损), 旧版输出是 PNG
			if FileAccess.file_exists(webp):
				file = webp
			return {"mult": mult, "file": file, "scale": 1.0 / mult, "hd": true, "gen": false}
	return {"mult": 0, "file": orig_dir.path_join(rel), "scale": 1.0, "hd": false, "gen": false}


## 高清贴图线性过滤、原版 1 倍最近邻 (逐像素对齐)。调用方统一经这里取过滤模式, 不再各写一遍三元式。
static func filter_for(hd_tex: bool) -> int:
	return CanvasItem.TEXTURE_FILTER_LINEAR if hd_tex else CanvasItem.TEXTURE_FILTER_NEAREST

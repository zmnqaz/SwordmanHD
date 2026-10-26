# SPDX-License-Identifier: GPL-3.0-only
class_name Cutscene
extends RefCounted
## 全屏过场演出 (通用): 任何界面 (营地炼化、以后的合成/召唤/剧情节点) 按 id 播一段「垫图 + 视频」, 演出全部来自内容数据:
##   内容包 fx/cutscenes.json  cutscenes.<id> = {backdrop, movie, skip, notice}
##     backdrop  布局表元素 id (type=panel, 位置与帧在 ui_theme/layout.json), 视频载入前/播放时垫在下面; 缺省 = 只有黑底
##     movie     资源清单逻辑名 (ui_theme/assets.json, 如 movie.forge)
##     skip      可跳过的键 ["confirm", "cancel"] 子集; 缺省两者都可; 空数组 = 不可跳过
##     notice    {text, ticks}: 演出后的浮动提示 (见 notice())
## 用法: await Cutscene.play(host, "forge")。播放期间视频在界面栈顶 (MovieScene), 下面的界面收不到输入 (原版同: 视频自己轮询按键)。
## 自动测试 / --skip-movies / 没有视频文件时整段跳过 (等同玩家取消)。
## 垫图按原版 320x200 画面裁切 (超出部分不显示, 如 FI_PRO 第 18 帧 330x216), 宽屏两侧是黑底。

const LAYER := 90
const TICK := 0.04  # 1 tick = 40 ms (同 SceneShow)


static func spec(id: String) -> Dictionary:
	var d = FxPlace.content_json("fx/cutscenes.json")
	if d is Dictionary and d.get("cutscenes") is Dictionary and d["cutscenes"].get(id) is Dictionary:
		return d["cutscenes"][id]
	return {}


## 是否真的会放视频 (False 时 play 立刻返回)
static func playable(id: String) -> bool:
	var s := spec(id)
	if s.is_empty() or GameContext.current().skip_movies:
		return false
	return _file_ok(ThemeAssets.p(String(s.get("movie", ""))))


static func _file_ok(movie: String) -> bool:
	return movie != "" and not GameContext.current().skip_movies and Assets.movie_exists(movie)


## 播放 id 这一段, 放完 (或被跳过) 才返回
static func play(host: Node, id: String) -> void:
	if not playable(id):
		return
	var s := spec(id)
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	host.add_child(layer)
	var black := ColorRect.new()
	black.color = Color.BLACK
	layer.add_child(black)
	ScreenLayout.cover(black, 2048.0)
	var stage := Control.new()
	stage.size = UiLayout.base_size() * Assets.SCALE  # 原版画面 x 倍数 (1280x800)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(stage)
	ScreenLayout.bind_node(stage, ScreenLayout.SAFE)
	var root := Node2D.new()
	root.scale = Vector2.ONE * Assets.SCALE
	stage.add_child(root)
	var bd := String(s.get("backdrop", ""))
	if bd != "" and UiLayout.has(bd):
		root.add_child(UiLayout.panel(bd))
	var skip: Array = s["skip"] if s.get("skip") is Array else ["confirm", "cancel"]
	var m: Control = MovieScene.create([ThemeAssets.p(String(s["movie"]))], func(): pass, skip)
	layer.add_child(m)
	await m.done
	layer.queue_free()


## 直接播一个视频文件 (资源逻辑名 = classic/movies 下去掉 .ogv 的路径), 不经演出表: 战斗法术演出用 (技能记录 has_movie)。
## 同 play: 视频在界面栈顶、黑底全屏; skip 为可跳过的键; 自动测试 / --skip-movies / 没有文件时立刻返回。
static func play_file(host: Node, movie: String, skip: Array = ["confirm", "cancel"]) -> void:
	if not _file_ok(movie):
		return
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	host.add_child(layer)
	var black := ColorRect.new()
	black.color = Color.BLACK
	layer.add_child(black)
	ScreenLayout.cover(black, 2048.0)
	var m: Control = MovieScene.create([movie], func(): pass, skip)
	layer.add_child(m)
	await m.done
	layer.queue_free()


## 演出结束后的浮动提示文字 (spec.notice.text 套参数), 没有配置返回 ""
static func notice_text(id: String, args := []) -> String:
	var n = spec(id).get("notice")
	if not (n is Dictionary):
		return ""
	var t := String(n.get("text", ""))
	return t % args if args.size() > 0 else t


## 提示停留秒数 (tick 数 * 40 ms); 自动测试快进时为 0
static func notice_secs(id: String) -> float:
	var n = spec(id).get("notice")
	if not (n is Dictionary) or GameContext.current().fast:
		return 0.0
	return float(n.get("ticks", 0)) * TICK

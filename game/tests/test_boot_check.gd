# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 启动自检 (scripts/game.gd resource_error) 与 --scene 编号范围: 资源齐全时放行, 缺必需资源给清楚提示
const REQUIRES_TEST := {
	"test_resources_present_pass": ["original", "content"]
}  # 个别方法的依赖 (同上)

func test_resources_present_pass():
	eq(Game.resource_error(), "", "资源齐全时自检通过")
	eq(Game.boot_error, "", "没有启动失败")


func test_missing_original_reports():
	var saved: Dictionary = Assets._index
	Assets._index = {}
	var msg: String = Game.resource_error()
	Assets._index = saved
	check(msg.contains("原版") and msg != "", "缺原版资源给出提示: " + msg)


## 手机上缺资源包: 提示画在屏幕上而不是立刻退出 (闪退看不到提示); 屏幕上有标题、完整提示文字和换行
func test_boot_error_screen_shows_message():
	var msg := "找不到资源包。请把 resource 文件夹放进 /sdcard/Android/data/com.tdj.swordmanhd/files"
	var s := BootErrorScreen.make(msg)
	Engine.get_main_loop().root.add_child(s)
	await Engine.get_main_loop().process_frame
	var texts := []
	for n in s.find_children("*", "Label", true, false):
		texts.append((n as Label).text)
	check(texts.has(msg), "整段提示文字显示在屏幕上")
	check(texts.has(BootErrorScreen.title()) and BootErrorScreen.title() != "", "有标题")
	for n in s.find_children("*", "Label", true, false):
		eq((n as Label).autowrap_mode, TextServer.AUTOWRAP_ARBITRARY, "长提示自动换行")
	s.queue_free()


## 视频文件缺失 (没装 classic_movies / hd_movies) 时, 过场整段跳过并正常结束, 不能黑屏等 finished 等到死
func test_missing_movie_is_skipped():
	var fired := [0]
	var m: Control = MovieScene.create(["Movie/__no_such_movie__"], func(): fired[0] += 1)
	Engine.get_main_loop().root.add_child(m)
	var n := 0
	while fired[0] == 0 and n < 10:
		await Engine.get_main_loop().process_frame
		n += 1
	eq(fired[0], 1, "缺视频时过场在几帧内结束")
	m.queue_free()

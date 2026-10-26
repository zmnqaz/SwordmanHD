# SPDX-License-Identifier: GPL-3.0-only
extends "res://tests/test_base.gd"
## 整包 (资源包随安装包一起装, ResPacks.parse_bundle / read_bundle): 清单解析与校验; 桌面没有整包。


func test_parse_bundle_manifest():
	var m := ResPacks.parse_bundle({"resource": ["common_assets", "common_story", "hd_images"], "mod": ["face_hk"]})
	eq(m["resource"], ["common_assets", "common_story", "hd_images"], "必备包按清单顺序")
	eq(m["mod"], ["face_hk"], "mod 包")
	eq(ResPacks.parse_bundle({"resource": ["common_assets"]})["mod"], [], "mod 可以不写")


func test_parse_bundle_rejects_bad_manifests():
	eq(ResPacks.parse_bundle(null), {}, "不是字典")
	eq(ResPacks.parse_bundle({"resource": []}), {}, "一个必备包都没有")
	eq(ResPacks.parse_bundle({"resource": "common_assets"}), {}, "类型不对")
	eq(ResPacks.parse_bundle({"resource": ["../evil"]}), {}, "包名不能带 ..")
	eq(ResPacks.parse_bundle({"resource": ["a/b"]}), {}, "包名不能带路径")
	eq(ResPacks.parse_bundle({"resource": [""]}), {}, "包名不能为空")


func test_desktop_has_no_bundle():
	if Platform.is_android() or Platform.is_ios():
		return
	eq(ResPacks.bundled_dir(), "", "桌面平台没有整包")
	eq(ResPacks.read_bundle(""), {}, "没有整包目录: 空")
	eq(ResPacks.read_bundle("user://__no_such_bundle__"), {}, "目录里没有清单: 空")

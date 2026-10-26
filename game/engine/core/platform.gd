# SPDX-License-Identifier: GPL-3.0-only
class_name Platform
extends RefCounted
## 运行平台查询: 引擎与组装层判断「手机 / iOS / Android / 导出版」统一走这里, 不再各处散写 OS.has_feature("mobile"/"ios"/"android"/"template")。
## 以后要加平台差异 (如平板、掌机、网页版) 或测试里模拟某平台, 改这一处即可。


## 手机/平板 (iOS 或 Android): 触屏模式、安全区内缩、贴图上限按移动端
static func is_mobile() -> bool:
	return OS.has_feature("mobile")


static func is_ios() -> bool:
	return OS.has_feature("ios")


static func is_android() -> bool:
	return OS.has_feature("android")


static func is_macos() -> bool:
	return OS.has_feature("macos")


## 导出版 (发布包, 用导出模板运行); 开发版 (编辑器/源码目录直接跑) 为 false
static func is_exported() -> bool:
	return OS.has_feature("template")

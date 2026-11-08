# SPDX-License-Identifier: GPL-3.0-only
class_name GameVersion
extends RefCounted
## 游戏版本号: 唯一来源是 project.godot 的 application/config/version (发版时只改这一处和 export_presets.cfg, 两处一致由
## tools/checks/check_version.py 守着)。标题画面右下角与关于页显示 display_label (带版本名「揽月」), 画质诊断页第一行、启动日志用 label, 玩家报 bug 时对得上是哪一版。


## 纯数字版本, 如 "0.1.1"; 没写时 "?"
static func number() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "?"))


## 项目主页 (GitHub 地址), project.godot 的 application/config/homepage
static func homepage() -> String:
	return String(ProjectSettings.get_setting("application/config/homepage", ""))


## 给人看的短写法, 如 "v0.1.1" (启动日志、诊断页: 报 bug 对版本用)
static func label() -> String:
	return "v" + number()


## 标题画面右下角与关于页的写法: 版本名 + 短写法, 如「揽月 v1.0.0」(繁体「攬月」)。版本名在文案表 app.edition (内容包 / mod 可改), 没写或为空时只显示 "v1.0.0"
static func display_label() -> String:
	var ed := UiStrings.t("app.edition") if UiStrings.has("app.edition") else ""
	return label() if ed.strip_edges() == "" else "%s %s" % [ed, label()]

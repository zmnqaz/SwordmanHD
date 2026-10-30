# SPDX-License-Identifier: GPL-3.0-only
class_name GameVersion
extends RefCounted
## 游戏版本号: 唯一来源是 project.godot 的 application/config/version (发版时只改这一处和 export_presets.cfg, 两处一致由
## tools/checks/check_version.py 守着)。显示在标题画面右下角、画质诊断页第一行、启动日志里, 玩家报 bug 时对得上是哪一版。


## 纯数字版本, 如 "0.1.1"; 没写时 "?"
static func number() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "?"))


## 项目主页 (GitHub 地址), project.godot 的 application/config/homepage
static func homepage() -> String:
	return String(ProjectSettings.get_setting("application/config/homepage", ""))


## 给人看的短写法, 如 "v0.1.1"
static func label() -> String:
	return "v" + number()

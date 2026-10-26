# SPDX-License-Identifier: GPL-3.0-only
class_name SceneFlow
extends RefCounted
## 场景流转接口 (引擎 -> 组装层): 引擎里的剧情指令、战场、营地想「去下一关 / 存档 / 回标题」时调用它,
## 不必知道场景怎么切。真实实现 scripts/game_flow.gd 转给 autoload Game; 这里的缺省实现什么都不做 (无头单元测试用)。
## 带 await 的方法 (淡入淡出、读档) 在缺省实现里立即返回。


func goto_rpg(_n: int, _entry: int) -> void:
	pass


func goto_battle(_n: int) -> void:
	pass


func goto_camp(_n: int) -> void:
	pass


func leave_camp(_town: int, _town_pos: int) -> void:
	pass


## 事件 0x02: 关卡结束 (town>=0 进城镇, 否则 camp>=0 进营地, 否则开 next 关)
func stage_over(_town: int, _camp: int, _next: int) -> void:
	pass


func game_over() -> void:
	pass


func ending() -> void:
	pass


## 淡出 -> 回标题 -> 淡入 (战场系统菜单/营地「返回标题」)
func return_to_title() -> void:
	pass


func save_game(_slot := 0) -> void:
	pass


func load_game(_slot := 0) -> bool:
	return false


func save_battle(_snapshot: Dictionary) -> void:
	pass


func load_battle() -> bool:
	return false


## 设定改动后让它生效 (音量/画质/字体/窗口) 与落盘
func apply_settings() -> void:
	pass


func save_settings() -> void:
	pass


## 菜单回放: 进程内切到录像回放 (设定面板「录像回放」选定后调); 缺省实现什么都不做
func start_replay(_path: String, _speed: float) -> void:
	pass


## 结束回放回标题 (设定面板回放中的「结束回放」行)
func stop_replay() -> void:
	pass


## node 是否是当前场景 (场景被切走后, 挂在它上面的异步流程据此停手)
func is_current(_node: Node) -> bool:
	return true

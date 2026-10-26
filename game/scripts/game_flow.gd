# SPDX-License-Identifier: GPL-3.0-only
class_name GameFlow
extends SceneFlow
## SceneFlow 的真实实现 (组装层): 转给 autoload Game 的场景流转。engine/ 只认 SceneFlow, 不认 Game。

var _game: Node


func _init(game: Node) -> void:
	_game = game


func goto_rpg(n: int, entry: int) -> void:
	await _game.goto_rpg(n, entry)


func goto_battle(n: int) -> void:
	await _game.goto_battle(n)


func goto_camp(n: int) -> void:
	await _game.goto_camp(n)


func leave_camp(town: int, town_pos: int) -> void:
	await _game.leave_camp(town, town_pos)


func stage_over(town: int, camp: int, next: int) -> void:
	await _game.stage_over(town, camp, next)


func game_over() -> void:
	await _game.game_over()


func ending() -> void:
	await _game.ending()


func return_to_title() -> void:
	await _game.fade_out(0.8)
	_game.goto(_game.TitleScene.new())
	await _game.fade_in(0.5)


func save_game(slot := 0) -> void:
	_game.save_game(slot)


func load_game(slot := 0) -> bool:
	return await _game.load_game(slot)


func save_battle(snapshot: Dictionary) -> void:
	_game.save_battle(snapshot)


func load_battle() -> bool:
	return await _game.load_battle()


func start_replay(path: String, speed: float) -> void:
	await _game.start_replay(path, speed)


func stop_replay() -> void:
	await _game.stop_replay()


func apply_settings() -> void:
	_game.apply_settings()


func save_settings() -> void:
	_game.save_settings()


func is_current(node: Node) -> bool:
	return _game.current == node

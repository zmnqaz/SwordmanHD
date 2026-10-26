# SPDX-License-Identifier: GPL-3.0-only
extends Node
## 根节点: 所有场景挂在这里, 流程由 Game 控制。

func _ready() -> void:
	Game.boot.call_deferred()

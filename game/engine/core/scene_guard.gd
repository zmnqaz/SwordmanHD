# SPDX-License-Identifier: GPL-3.0-only
class_name SceneGuard
extends RefCounted
## 场景协程的「场景仍有效」保护 。
## 场景里的协程常用 `await get_tree().create_timer(s).timeout` 等时间; SceneTreeTimer 属于场景树, 场景被切走后照样到点:
##   - 节点已释放: Godot 会丢弃该实例上挂起的协程, 不再恢复 (无害);
##   - 节点已 queue_free 但本帧还没释放 / 已移出场景树: 协程照样恢复, 在过期场景上继续跑逻辑 (改全局状态、跑剧情),
##     移出树时 get_tree() 为 null 还会报错。
## 用 `await SceneGuard.wait(self, s)` 代替上面的写法: 到点时节点仍有效才返回 (true); 否则协程就停在这里不再继续
## (排队释放的随节点释放一起丢弃, 移出树的等重新入树再继续), 调用方不用逐处判断、也不会把控制权交回调用链去跑过期逻辑。
## 只有调用方自身不随场景释放 (RefCounted, 如回放驾驶员) 且节点已释放时才返回 false, 这种调用方要自行停手。


## 节点是否仍在有效场景里: 未释放、在场景树内、自己和祖先都没有排队释放 (切场景是 queue_free 场景根)
static func alive(n) -> bool:
	if not is_instance_valid(n) or not (n is Node) or not (n as Node).is_inside_tree():
		return false
	var p: Node = n
	while p != null:
		if p.is_queued_for_deletion():
			return false
		p = p.get_parent()
	return true


## 等 sec 秒 (与 get_tree().create_timer(sec) 同一种计时器); 返回时节点仍有效。节点已离场时见文件头
static func wait(n, sec: float) -> bool:
	if alive(n):
		await (n as Node).get_tree().create_timer(sec).timeout
	return await hold(n)


## 节点离场时停住 (不返回), 仍有效立即返回 true; 已释放返回 false
static func hold(n) -> bool:
	while not alive(n):
		if not is_instance_valid(n):
			return false
		await (n as Node).tree_entered   # 排队释放的: 永不触发, 节点释放时连同本协程丢弃; 移出树的: 重新入树后再判
	return true

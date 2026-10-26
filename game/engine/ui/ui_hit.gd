# SPDX-License-Identifier: GPL-3.0-only
class_name UiHit
extends RefCounted
## 指针 (鼠标 / 触摸点按) 命中框架。组件只声明「各选项命中矩形」(原版坐标), 输入层 (InputRouter) 统一处理悬停、点按、
## 右键、滚轮, 界面不写任何鼠标代码。 3.2。
##
## 坐标换算: 命中矩形是某个节点的局部坐标 (原版像素), 按该节点的全局变换把屏幕坐标换算回去
##   (UiLayer 的 ×SCALE、锚点节点的平移、CanvasLayer 偏移、--aspect 宽屏、hd6x 等窗口大小都在变换里, 不用另算)。
##
## 组件 (鸭子类型, 都可选):
##   ui_hits() -> Array             命中区, 每项 UiHit.area(rect, index, node, action, grid); 先列的优先。
##                                  rect: node 局部坐标 (node 省略 = 组件本身, 节点隐藏时该区不命中);
##                                  index: 悬停/点按时交给 ui_select 的选项 (null = 不改选中项);
##                                  action: 点按时交给界面的动作 (默认 CONFIRM; NONE = 只选中);
##                                  grid: 非零时 rect 按格切分, index = 起始 index (Vector2i) + 格坐标 (地图格子)。
##   ui_select(index)               把选中项移到 index (同方向键移到该项)。
##   ui_outside_action() -> int     点在所有命中区外时交给界面的动作 (缺省 NONE = 忽略)。
##   ui_pointer_target() -> Object  当前接收指针的子组件 (弹出的是/否框等); 返回自身 = 自己处理, null = 暂不接收指针。
## 界面 (InputRouter 界面栈上的接收方): 自己就是组件 (有 ui_hits) 时什么都不用加; 否则实现 ui_pointer_target() 返回当前组件
## (忙时 null, 指针动作照常交给 ui_action)。输入层的处理:
##   移动 (POINT)   命中且有 index → ui_select(index) (悬停 = 选中项跟随)
##   左键 / 点按    命中 → ui_select(index), 再把 action (默认确认) 作为普通动作交给界面的 ui_action (与键盘「移到该项 + 确认」一致);
##                  点空处 → ui_outside_action()
##   中键 (查看)    命中 → 先 ui_select(index), 查看动作照常交给界面
##   右键 / 滚轮    不经命中, 照常是取消 / 上下 (界面按键盘语义处理)
## 防误触: 组件刚出现 GUARD 秒内、指针还没在它上面悬停命中过时, 点按不算 (双击单位时第二下落在刚弹出的菜单上)。

const GUARD := 0.4


## 一个命中区
static func area(rect: Rect2, index: Variant = null, node: CanvasItem = null, action: int = UiAction.CONFIRM, grid := Vector2.ZERO) -> Dictionary:
	return {"rect": rect, "index": index, "node": node, "action": action, "grid": grid}


## 沿 ui_pointer_target() 找到实际接收指针的组件 (没有 ui_hits 或暂不接收的返回 null)
static func resolve(t: Object) -> Object:
	for _i in 8:
		if t == null or not is_instance_valid(t):
			return null
		if not t.has_method("ui_pointer_target"):
			break
		var n: Object = t.call("ui_pointer_target")
		if n == null:
			return null
		if n == t:
			break
		t = n
	return t if t.has_method("ui_hits") else null


## 屏幕坐标 p (视口像素) 命中的区 (area 的字典, index 已按格算好), 没有为 {}
static func find(t: Object, p: Vector2) -> Dictionary:
	if t == null or not is_instance_valid(t) or not t.has_method("ui_hits"):
		return {}
	if t is CanvasItem and not shown(t):
		return {}
	for h in t.call("ui_hits"):
		var n: CanvasItem = h["node"] if h["node"] != null else t as CanvasItem
		if n == null or not is_instance_valid(n) or not shown(n):
			continue
		var local := n.get_global_transform_with_canvas().affine_inverse() * p
		var r: Rect2 = h["rect"]
		if not r.has_point(local):
			continue
		var g: Vector2 = h["grid"]
		if g != Vector2.ZERO:
			var cell := Vector2i(((local - r.position) / g).floor())
			h = h.duplicate()
			h["index"] = (h["index"] if h["index"] is Vector2i else Vector2i.ZERO) + cell
		return h
	return {}


## 节点在树里且自己与各级父节点 (CanvasItem / CanvasLayer) 都可见 (不看窗口本身, 无头测试里根窗口不算可见)
static func shown(n: Node) -> bool:
	if not n.is_inside_tree():
		return false
	while n != null and not n is Window:
		if (n is CanvasItem and not (n as CanvasItem).visible) or (n is CanvasLayer and not (n as CanvasLayer).visible):
			return false
		n = n.get_parent()
	return true

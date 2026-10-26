# SPDX-License-Identifier: GPL-3.0-only
class_name ShopUI
extends CanvasLayer
## 商店 (原版 外壳 + CItemProcessor 双栏物品窗, 与营地「囊內乾坤」同一个界面, 见 game/engine/ui/camp/camp_item_window.gd):
##   背景为店主动画 Shop/ShopNN, 进出店的演出走通用的 SceneShow (内容包 shops.json 的 show 字段):
##   城镇渐黑 → 黑场 → 店面渐入 → 播完店主开场 → 打开物品窗, 店主循环待机 → 物品窗渐隐 → 店面渐黑 → 黑场 → 城镇渐入
##   (原版 + 40 ms 间隔录像实测, 见 SceneShow 与机制);
##   左栏 = 商店货品 (显示原价), 右栏 = 行囊 / 各在队主角 (显示卖价 = 价格/2), 买来的东西放进右栏当前显示的那一栏。
##   商店栏按确认问「是否要買入此物品？」; 自己的物品按确认打开 賣出/裝備/丟棄 菜单。
## 锚点: 店内背景与双栏窗按安全区居中 (加宽时两边留给装饰边), 底下的黑幕铺满全屏。
## 按键同囊內乾坤: ↑/↓ 选行, ←/→ 切换焦点栏内容, Tab 切换焦点, 确认, 取消关闭, 空格按住预览装备。

var gc: GameContext = GameContext.current()  # 运行上下文 (引擎不直接引用 autoload Game)

signal closed

const SceneShow := preload("res://engine/ui/scene_show.gd")

var _root: Node2D
var _show: SceneShow
var _ui: UiLayer
var _win: CampItemWindow


func _ready() -> void:
	layer = 48
	ScreenLayout.bind_layer(self, ScreenLayout.SAFE)
	visible = false


func open(shop: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_root = Node2D.new()
	_root.scale = Vector2.ONE * Assets.SCALE
	add_child(_root)
	InputRouter.push(self)  # 演出期间吞掉操作 (_win 为空)
	visible = true
	var spec = shop.get("show")
	if not SceneShow.valid(spec):
		spec = default_show(String(shop["keeper_anim"]) if shop.get("keeper_anim") != null else ThemeAssets.f("shop_keeper", [int(shop["shop"])]))
	if SceneShow.valid(spec):
		_show = SceneShow.new(spec)
		var bg := ColorRect.new()  # 整屏黑幕垫在店面下 (第一个子节点, 布局表 shop.bg): 安全区外的黑边, 经黑场时它就是「黑场」, 随店面一起渐入渐出
		bg.color = UiLayout.color(UiLayout.val("shop.bg", "color"), Color.BLACK)
		var r := UiLayout.rect("shop.bg")
		bg.position = r.position
		bg.size = r.size
		_show.add_child(bg)
		ScreenLayout.cover(bg)
		_root.add_child(_show)
		ScreenLayout.mirror_edges(_root)  # 宽屏两侧镜像铺满 (取代原来的黑边)
		await _show.enter(gc.fast)
	_ui = UiLayer.new(layer + 1)
	add_child(_ui)
	_win = CampItemWindow.new(CampInventory.new(shop["items"], int(shop.get("type", -1))))
	_ui.add(_win)
	_win.open()
	_win.closed.connect(func(): closed.emit())
	if gc.fast:
		await get_tree().create_timer(0.8).timeout
	else:
		await closed
	await _close()


## 旧内容包没有 show 字段时按原版 的规则由店主动画的动作帧数生成 (同 生成工具的脚本 shop_show)
static func default_show(dir: String) -> Dictionary:
	if not Assets.exists(dir + "/anim.json"):
		return {}
	var c: Array = Assets.anim(dir)["action_counts"]
	var fade := [2, 4, 6, 8, 10, 12, 14]
	var out := fade.duplicate()
	out.reverse()
	return {"anim": dir, "base": 0, "intro": [1, int(c[0])], "loop": [int(c[0]) + 2, int(c[1])],
		"fade_in": fade, "fade_out": out, "fade_tick": 2, "via_black": true, "black_hold": [4, 6],
		"ui_fade_out": out, "ui_fade_tick": 1}


func _close() -> void:
	if _win and not gc.fast:  # 物品窗渐隐 (原版 7 档 x 1 tick, 之后店面才开始渐出)
		var spec = _show.spec if _show else {}
		var tick := maxi(1, int(spec.get("ui_fade_tick", 1)))
		for v in spec.get("ui_fade_out", []):
			_win.modulate.a = float(v) / 16.0
			await get_tree().create_timer(SceneShow.TICK * tick).timeout
	if _ui:
		_ui.queue_free()
		_ui = null
	_win = null
	if _show:
		await _show.leave(gc.fast)
		_show = null
	visible = false
	InputRouter.pop(self)


## 界面连发间隔: 转给双栏物品窗 (←/→ 换栏 0.84 秒)
func repeat_interval(kind: int) -> float:
	if visible and _win != null:
		return _win.repeat_interval(kind)
	return KeyRepeat.REPEAT


## 指针: 交给双栏物品窗的命中矩形 (InputRouter -> UiHit)
func ui_pointer_target() -> Object:
	return _win if visible else null


## 统一输入层 (打开期间在界面栈顶): 动作 -> 按键名, 同营地 (UiAction.camp_key)
func ui_action(a: UiAction) -> bool:
	if not visible or _win == null:
		return true
	var k := a.camp_key()
	if k == "" or (a.echo and not a.is_dir()):
		return true
	_win.key(k)
	return true

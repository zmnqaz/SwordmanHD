# SPDX-License-Identifier: GPL-3.0-only
class_name UiInfoBar
extends Node2D
## 单位信息条 (素材 Misc/Man_bri)。坐标原式在带边框 (30,24) 的地图缓冲区里, 这里已换成屏幕坐标:
##   左块 第 0 帧 (144x31): x=31-30=1; 右块 第 1 帧 (173x31): x=176-30=146。
##   y: 单位所在行 (相对画面) > 4 时放顶端 25-24=1, 否则放底部 192-24=168。
##   左块内容: 名字 (11,4); 体 %4d (72,7) / %4d (105,7); 術 %4d (72,19) / %4d (105,19); 移 %2d (22,19) / %2d (45,19)。
##   右块内容: 攻 %4d (28,6); 防 %4d (28,18); 位 (等级) %3d (71,6); 歷 (经验) %3d (71,18);
##       增益图标 第 2~5 帧 在 (94,8) (112,8) (130,8) (148,8)。
##   数字: Man_bri 第 6 帧字模, 步进 7 (UiLayout.number)。超过 9999 写 "????"。
##   打开: 左块从左、右块从右滑入, 偏移 16→8→4→2→0 并淡入 (UiSlide.BRI_OFFSETS)。
##   以上坐标都在布局表 infobar.* (缺省为这些原版值), 换游戏改表即可。
##
## 单位数据 (Dictionary): name hp hp_max mp mp_max move move_max attack defence lv exp, buffs: [攻 防 智 速] 四个 bool

## 数字字段 -> 所在块 (布局元素 infobar.<字段>: 位置、字模、格式宽度)
const NUMS := {"hp": "left", "hp_max": "left", "mp": "left", "mp_max": "left", "move": "left", "move_max": "left",
	"attack": "right", "defence": "right", "lv": "right", "exp": "right"}

var top := false
var detail := false
var _left: Node2D
var _right: Node2D
var _name: UiText
var _nums := {}
var _buffs: Array[UiPanel] = []
var _anchors: Array = []   # use_screen_anchors() 后: [左块锚点, 右块锚点]


func _init() -> void:
	_left = CanvasGroup.new()  # 整体淡入
	add_child(_left)
	var pl := UiLayout.panel("infobar.left")
	pl.position = Vector2.ZERO  # 块位置由 show_unit 按上/下放在外层
	_left.add_child(pl)
	_name = UiText.make("infobar.name")
	_left.add_child(_name)
	_right = CanvasGroup.new()
	add_child(_right)
	var pr := UiLayout.panel("infobar.right")
	pr.position = Vector2.ZERO
	_right.add_child(pr)
	for k in NUMS:
		var d := UiLayout.number("infobar." + k)
		(_left if NUMS[k] == "left" else _right).add_child(d)
		_nums[k] = d
	var frames: Array = UiLayout.sprite("infobar.buffs").get("frames", [])
	for i in frames.size():
		var b := UiPanel.new(String(UiLayout.sprite("infobar.buffs")["anim"]), int(frames[i]), UiLayout.at("infobar.buffs", i))
		_right.add_child(b)
		_buffs.append(b)
	_left.visible = false
	_right.visible = false


## 左右块的位置 (which: 0 顶端 / 1 底部, 布局 pos 写 "1|168")
static func block_pos(side: String, at_top: bool) -> Vector2:
	return UiLayout.at("infobar." + side, 0, {"which": 0 if at_top else 1})


## 左右两块分别贴屏幕边 (docs/架构设计.md 6.4): 左块 TOP_LEFT / BOTTOM_LEFT, 右块 TOP_RIGHT / BOTTOM_RIGHT。
## 须在加进场景树之后调用 (锚点节点要在父节点里就地替换)。16:10 下偏移为 0。
func use_screen_anchors() -> void:
	if not _anchors.is_empty():
		return
	_anchors = [ScreenLayout.wrap(_left, ScreenLayout.Anchor.BOTTOM_LEFT), ScreenLayout.wrap(_right, ScreenLayout.Anchor.BOTTOM_RIGHT)]


func _place_anchors() -> void:
	if _anchors.is_empty():
		return
	_anchors[0].anchor = ScreenLayout.Anchor.TOP_LEFT if top else ScreenLayout.Anchor.BOTTOM_LEFT
	_anchors[1].anchor = ScreenLayout.Anchor.TOP_RIGHT if top else ScreenLayout.Anchor.BOTTOM_RIGHT


## 原版规则: 单位所在行 (相对画面左上角, 格高 24) 大于 4 时信息条放顶端
static func top_for_row(screen_row: int) -> bool:
	return screen_row > 4


## 显示某单位。detail=true 时同时显示右块。animate=true 时从隐藏状态滑入 (已显示的块直接刷新)
func show_unit(u: Dictionary, at_top: bool, show_detail := false, animate := true) -> void:
	var moved := at_top != top
	top = at_top
	detail = show_detail
	_name.text = String(u.get("name", ""))
	for k in _nums:
		_nums[k].text = UiDigits.fmt(int(u.get(k, 0)), UiLayout.fmt_width("infobar." + k))
	var buffs: Array = u.get("buffs", [false, false, false, false])
	for i in _buffs.size():
		_buffs[i].visible = i < buffs.size() and bool(buffs[i])
	_place_anchors()
	_show_block(_left, block_pos("left", top), Vector2.LEFT, true, animate and (moved or not _left.visible))
	_show_block(_right, block_pos("right", top), Vector2.RIGHT, detail, animate and (moved or not _right.visible))


func _show_block(n: Node2D, base: Vector2, dir: Vector2, on: bool, animate: bool) -> void:
	if not on:
		UiSlide.cancel(n)  # 关块也要取消旧动画, 否则滑入中的 tween 会把块拉回可见
		n.visible = false
		return
	if animate:
		UiSlide.run(n, base, dir, UiSlide.BRI_OFFSETS, true)
	else:
		n.position = base
		n.modulate.a = 1.0
		n.visible = true


func hide_bar(animate := false) -> void:
	for pair in [[_left, Vector2(block_pos("left", top).x, _left.position.y), Vector2.LEFT],
			[_right, Vector2(block_pos("right", top).x, _right.position.y), Vector2.RIGHT]]:
		var n: Node2D = pair[0]
		if not n.visible:
			continue
		if animate:
			UiSlide.run(n, pair[1], pair[2], UiSlide.BRI_OFFSETS, false)
		else:
			UiSlide.cancel(n)  # 滑入进行中立刻隐藏 (选目标后马上确认攻击): 不取消会被旧 tween 拉回可见
			n.visible = false

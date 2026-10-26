# SPDX-License-Identifier: GPL-3.0-only
class_name BattleCoord
extends Node2D
## 战场格子坐标 (设定「格子坐标」开/关, 默认关; 原版没有, 只画不改规则): 光标所在格「列,行」(从 0 起, 与内部格坐标一致) 的小标签,
## 贴在光标格上方 (靠近画面顶时放到下方, 横向夹在画面内), 随光标移动。
## 只在战场的玩家操作阶段显示 (我方回合、光标可操作、没有剧情/对白在跑); 开场/过关剧情、敌方回合、读档过场里不显示。
## 挂在战场界面层 (与信息栏同层, 晚于它加入, 画在信息栏上面), 标签带半透明底, 压在浅色界面上也读得清。

const LABEL_SIZE := 8.0                       # 标签字号 (原版像素)
const LABEL_COLOR := Color(1.0, 0.95, 0.72, 0.9)
const EDGE_COLOR := Color(0, 0, 0, 0.9)
const PLATE := Color(0, 0, 0, 0.6)

var gc: GameContext = GameContext.current()
var bs                        # 战场场景 (BattleScene): cam / view() / cursor_cell() / in_player_phase()

var _tag: UiText
var _key := ""                # 上次布局的状态 (没变就不重排)
var _tag_pos := Vector2.ZERO
var _tag_text := ""


## 光标格的坐标文字; 光标不可见 (-1,-1) 时为空
static func cursor_text(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y] if c.x >= 0 and c.y >= 0 else ""


## 是否显示: 设定开着, 且在玩家操作阶段
static func shown(setting, in_player_phase: bool) -> bool:
	return (setting is int or setting is float) and int(setting) == 1 and in_player_phase


## 标签的左上角: 贴在光标格上方 (格左上角 + (1, -标签高-3)); 上方放不下 (压到画面顶) 就放格下方; 横向夹在画面内
static func tag_pos(c: Vector2i, cam: Vector2, view: Vector2, text_w: float, cell := Vector2(30, 24)) -> Vector2:
	var p := Vector2(c.x * cell.x - cam.x + 1.0, c.y * cell.y - cam.y - LABEL_SIZE - 3.0)
	if p.y < LABEL_SIZE + 3.0:
		p.y = (c.y + 1) * cell.y - cam.y + 1.0
	p.x = clampf(p.x, 1.0, maxf(1.0, view.x - text_w - 2.0))
	p.y = clampf(p.y, 1.0, maxf(1.0, view.y - LABEL_SIZE - 3.0))
	return p


func _ready() -> void:
	z_index = 30
	_tag = UiText.new("", LABEL_SIZE, LABEL_COLOR)
	_tag.flags = "edge5"
	_tag.edge_color = EDGE_COLOR
	add_child(_tag)
	visible = false


func _process(_delta: float) -> void:
	var setting = gc.settings.get("coord", 0)
	var on: bool = bs != null and (setting is int or setting is float) and int(setting) == 1 and bs.in_player_phase()   # 设定关时不去问场景
	visible = on
	if not on:
		_key = ""
		return
	var view: Vector2 = bs.view()
	var cur: Vector2i = bs.cursor_cell()
	var key := "%s|%s|%s" % [bs.cam.round(), view, cur]
	if key == _key:
		return
	_key = key
	_tag_text = cursor_text(cur)
	_tag.visible = _tag_text != ""
	_tag.text = _tag_text
	if _tag_text != "":
		_tag_pos = tag_pos(cur, bs.cam.round(), view, _tag_text.length() * LABEL_SIZE / 2.0)
		_tag.position = _tag_pos
	queue_redraw()


func _draw() -> void:
	if _tag_text != "":
		var w := _tag_text.length() * LABEL_SIZE / 2.0 + 2.0
		draw_rect(Rect2(_tag_pos - Vector2(1, 1), Vector2(w, LABEL_SIZE + 2.0)), PLATE)

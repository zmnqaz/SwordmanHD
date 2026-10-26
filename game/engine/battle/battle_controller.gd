# SPDX-License-Identifier: GPL-3.0-only
class_name BattleController
extends Node
## 战场的组合根: 建立各部分并连起来, 对外 (BattleScene / EventVM) 提供少量接口。各部分职责:
##   BattleRules   (battle_rules.gd)    规则适配层: 一切规则判断经它调用 engine/rules
##   BattleFlow    (battle_flow.gd)     回合流程: 阶段结算、回合事件、AI 行动、地图事件/宝物、死亡与胜负
##   BattleActions (battle_actions.gd)  行动结算与演出调度: 普攻、法术、道具、召唤、经验与升级提示
##   BattleView    (battle_view.gd)     地图上的表现: 范围格、飘字、结果动画、变灰、回合横幅、光标与信息条
##   BattleUi      (battle_ui.gd)       界面组件 (engine/ui) 的摆放: 图标菜单、列表、确认框、居中窗口 (ui/*.gd)
##   BattleInput   (control/battle_input.gd + control/*_state.gd)  玩家操作状态机, 只收统一输入层的动作
##   BattleCloseup (battle_closeup.gd)  近景战斗画面
## 内容只经 Content 读取; 第二版扩展时换掉/继承其中一部分即可 (如新的界面组件、新的操作方式), 其余不动。

var bs
var rules: BattleRules
var closeup: BattleCloseup
var ui: BattleUi
var view: BattleView
var actions: BattleActions
var flow: BattleFlow
var input: BattleInput

## 地图事件表 (剧情事件/宝物; 代打策略读它)
var map_events: Dictionary:
	get: return flow.map_events
var over: bool:
	get: return flow.over


func _init(scene) -> void:
	bs = scene
	rules = BattleRules.new(scene)
	closeup = BattleCloseup.new(scene)
	ui = BattleUi.new(scene)
	view = BattleView.new(scene, ui)
	actions = BattleActions.new(scene, rules, view, ui, closeup)
	flow = BattleFlow.new(scene, rules, view, actions)
	actions.flow = flow
	input = BattleInput.new(self)
	flow.input = input


func _ready() -> void:
	for n in [closeup, ui, view, actions, flow, input]:
		add_child(n)
	InputRouter.push(input)


## 回合流程; resume: 戰陣重現时的快照 (见 snapshot)
func run(resume := {}) -> void:
	await flow.run(resume)


## 战阵存录: 还没触发的地图事件
func snapshot() -> Dictionary:
	return {"map_events": flow.map_events.keys()}


## 剧情扣血 (事件 0x46 / 0x4A)
func event_damage(uid: int) -> void:
	await flow.event_damage(uid)

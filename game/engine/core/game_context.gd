# SPDX-License-Identifier: GPL-3.0-only
class_name GameContext
extends RefCounted
## 一局游戏的运行上下文: 引擎代码 (战场/城镇/营地/界面/剧情解释器) 通过它拿全局进度、运行开关与场景流转,
## 不再直接引用 autoload "Game" / "Autotest" (见 docs/架构设计.md「引擎与 autoload 的边界」)。
##   state    GameState (可序列化的全局进度: 剧情变量/金钱/行囊/队伍)
##   settings 设定生效值 (持久层 settings_saved + 本次运行覆盖层 settings_override 合并; 写入走 SettingsSchema.set_value 等)
##   fast/autoplay/god/skip_dialog/skip_movies  测试与调试开关 (命令行, 组装层写入)
##   debug    DebugArgs: 命令行调试/测试参数 (只读)
##   content  ContentInfo: core/ 层问内容包的窄接口 (存档签名/版本兼容/主角判定), 代替 core 直接引用 autoload Content
##   flow     SceneFlow: 场景流转/存读档/设置应用的接口, 组装层 (scripts/game.gd) 装入真实实现, 缺省是空实现 (无场景树也能 new)
##
## 注入: 组装层 (autoload Game) 持有唯一的 current() 并在 goto() 时交给场景; 解释器/场景/界面组件的成员
## `var gc: GameContext = GameContext.current()` 缺省取它, 测试可直接 `x.gc = GameContext.new()` 换成独立上下文。
## 没人装过时 current() 惰性建一个空的 (纯逻辑测试不需要任何 autoload)。

## 设定改动并已应用 (Game.apply_settings 发; 战场据此即时刷新「隐藏宝箱」图标等)
signal settings_applied

static var _current: GameContext

var state := GameState.new()
var settings := SettingsSchema.defaults()           # 生效值 (只读; 写入见 SettingsSchema.set_value / set_override / reset_all)
var settings_saved := SettingsSchema.defaults()     # 持久层: 写进 user://settings.json 的只有它
var settings_override := {}                         # 本次运行覆盖层 (命令行 --lang= 等、monkey), 不落盘
var volume_before_mute := {}                        # 战场「声音」开关关掉前的音量 {键: 值}, 再打开时恢复 (本次运行)
var flow := SceneFlow.new()
var debug: DebugArgs = DebugArgs.current()   # 命令行调试/测试参数 (启动时解析一次; 引擎只读字段, 不再自己读命令行)
var content := ContentInfo.new()   # core 层向内容包问话的窄接口 (存档签名/主角判定), 见 content_info.gd
var fast := false          # 测试: 跳过视频, 对白快速翻页
var autoplay := false      # 测试: 我方回合也由 AI 操作
var god := false           # 测试: 我方不受伤害
var skip_dialog := false   # 调试: 跳过对白
var skip_movies := false
var battle_resume := {}    # 非空时战场按此恢复 (戰陣重現), 跳过开场事件
var town_talks: Array = []   # 测试: --auto-exit 先去谈的城镇事件 [{event, times}] (--town-talk=; 如第 3 幕后襄阳客栈绿衣人 = 事件 12, 谈 3 次买紫霜云芝)
var cur_rpg := -1
var prev_rpg := -1
var in_battle := false     # 当前场景是战场 (组装层切场景时设; 攻略面板据此选默认章: 战场 = 本关, 城镇/营地 = 下一关)


static func current() -> GameContext:
	if _current == null:
		_current = GameContext.new()
	return _current


## 组装层启动时装入 (之后 current() 都返回它)
static func install(c: GameContext) -> void:
	_current = c

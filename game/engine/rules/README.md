# engine/rules —— 规则引擎

纯数据、无 Node、可无头测试的战斗规则模块: 规则按原版的实际行为实现, 数值常数与行为开关集中在 `params.gd`。
仍未定案的地方在代码注释里写 `TODO`。

战斗通过适配层 `game/engine/battle/battle_rules.gd` 调用本模块（B1 接入）：适配层只建上下文与棋盘（`Board.units` = 在场单位）、做 `BattleUnit`（节点）↔ `UnitState`（`BattleUnit.st`）对照、`--god`/`--autoplay` 测试开关；`battle_controller.gd` 只驱动流程与演出。规则公式不要写回战斗脚本。

## 文件

| 文件 | 内容 |
|---|---|
| params.gd | **全部可调参数**（默认 = 原版），内容包覆盖入口 |
| context.gd | 参数 + 随机数 + 数据表（items/skills/units/levelup/MAG_OPP） |
| rng.gd / scripted_rng.gd | MSVC rand；测试用脚本化随机数 |
| unit_state.gd | 单位运行时状态（可序列化），字段对应原版单位记录的偏移 |
| board.gd | 地形网格 + 单位 |
| stats.gd | ATK/DEF/MOV、敌人与召唤物属性 |
| growth.gd | 升级、成长、习得、五魂化蘊 |
| movement.gd | 移动点、可达、ZOC、爆發、行动结束 |
| attack.gd | 命中、会心、连击、格挡、射程、反击、武器附加、普攻交换 |
| damage.gd | 物理/咒术/绝技伤害、治疗、道具回复、自爆、剧情扣血 |
| status.gd | 状态位、R/K 模型、阶段结算、中毒、冰結 |
| skills.gd | 技能分类、使用条件、消耗、结算 |
| items.gd | 战斗中道具使用（回复、解状态、上限、发动技能） |
| exp.gd | 经验（二次曲线、截断、多目标、治疗） |
| ai.gd | 统一打分决策（普攻/道具/技能）、AI 类型 0~4、接近、走向敌群 |
| flow.gd | 回合步骤、TEVT 匹配、胜负判定（先胜后负、判定时机）、存档条件、地图事件检查、脚本结束去向、事件来源 |

测试在 `game/tests/test_*.gd`，`test_field.gd` 是逐条实测用例。运行：

```
tools/godot/godot --headless --path game --import        # 新增 class/脚本后
tools/godot/godot --headless --path game --script res://tests/run_tests.gd [-- 过滤串]
```

## 规则参数与内容包覆盖（第二版魔改用）

所有数值常数、原版 bug 的开关、自定选项都集中在 `params.gd` 的成员变量里，规则函数只通过 `ctx.params.xxx` 读取，不写死。默认值就是原版（V1.3 无补丁）行为（唯一例外是修补 `fix_ending_return_title`，见下表），所以**原版内容包不需要任何参数文件**。

覆盖方式：

1. 代码：`Params.new({"bag_capacity": 999})` 或 `params.apply({...})`。
2. 内容包：在包根目录放 `rules.json`，按包加载顺序叠加，后加载的覆盖前面的：

```json
{
  "format": "tdj-rules/1",
  "params": {
    "weapon_status_mode": "custom",
    "recall_resets_move": true,
    "burrow_sets_phantom": true,
    "turn_limit": 150
  }
}
```

```gdscript
# 运行时 (engine/battle/battle_rules.gd): 参数与数据表都来自内容包加载层 Content (engine/content/content_db.gd)
var ctx = Context.new(Content.params(), Rng.new(seed))   # = 内容包层读各包 rules.json 后 Params.from_documents([...])
ctx.load_records(Content.items(), Content.skills(), Content.table("attribute_defense"), Content.table("levelup"), Content.units())
```

- 未知参数名报错并忽略；JSON 数字自动转回 int；表格参数（`terrain_cost`、`ai_heal_tiers` 等）整体替换。
- `params.to_dict()` 导出当前全部参数，可用于存档记录「用哪套规则存的」。

### 原版 bug / 未定义行为开关（默认 = 原版）

| 参数 | 原版 | 魔改值 |
|---|---|---|
| `weapon_status_mode` | `"original"`：武器附加毒/麻/封主攻不生效，反击 R=K=0 | `"custom"`：R=time, K=cost |
| `weapon_add4_undefined_mag` | 19（紫金劍触发时伤害 ×0.19） | 100 = 不变 |
| `recall_resets_move` | false：返召之咒实际不能再行动 | true：重置移动点 |
| `burrow_sets_phantom` | false：遁地神行无效果 | true：置幻影 |
| `fix_mo_tian` | false：魔天降臨无效果 | true：走吸术分支 |
| `burst_accumulate` | false：连续爆發保留点覆盖 | true：累积 |
| `ally_npc_double_tick` | true：友军 NPC 一轮结算两次 | false |
| `status_death_judge_needs_event` | true：毒死且 kill_event=−1 不判胜负 | false：总判定 |
| `hp_mp_u16_wrap` | true：HPmax/MPmax 超 65535 回绕 | false：封顶 |
| `growth_mode` | `"random"` | `"max"`（最大成长补丁）/`"min"` |
| `battle_save_after_action` | false：我方有人行动后「存讀→存档」变灰 | true：随时可存 |
| `give_costs_action` | true：战斗中「交給」结束行动（对方满了改交换） | false：不耗行动 |
| `unit_item_slots` / `bag_capacity` | 10 / 512：每人随身格数、公共行囊容量（`engine/rules/inventory.gd`） | 可改 |
| `equip_costs_action` | false：战斗中装备/丢弃不耗行动与移动点 | true：结束行动 |
| `fix_ending_return_title` | **true（复刻修补，默认开）**：结局过场播完、脚本 END 无出口 → 回标题 | false：原版停黑屏、战斗后台空转 |

演出参数（不影响规则）：`guard_flash_sec`（0.3；格挡时全屏红色闪光，伤害数字不变红，0 = 关）、`guard_flash_color`（[255,0,0]）。

> `fix_ending_return_title` 是唯一默认偏离原版的开关：原版行为是脚本缺陷，玩家无法操作。
> 不移动的 AI 不检查地图事件（`Flow.map_event_hit`）是原版通用规则，不设开关；第 20 关「封寒月已站在石座」时开门剧情卡住由它自然重现。

数值类参数（伤害除数、经验曲线、AI 分数、行囊 512、初始金钱 5、100 回合等）同样可覆盖，含义见 `params.gd` 的注释。

### 换公式

尚未实现。目前只能改参数；需要改公式本身时，在 B1/B2 接入阶段再定替换机制（以模块为单位替换）。

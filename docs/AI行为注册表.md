# AI 行为注册表

`game/engine/rules/ai.gd` 的 AI 类型分发 (`plan()`) 不再是写死的 `match`, 而是查一张注册表:
类型号 (单位模板 `ai` / 剧情 0x2F 写入的值) -> `Callable(ctx, board, u, stay) -> {move_to: Vector2i, action: Dictionary}`。

## 默认 (= 原版, 行为不变)

| 类型 | 常量 | 行为 |
|---|---|---|
| 0 | `U.AI_IDLE` | 原地待机 |
| 1 | `U.AI_ACTIVE` | 主动出击 (同时是**未注册类型号的回退**, 对应原版 default 分支) |
| 2 | `U.AI_PASSIVE` | 消极: 只在原版统一决策能出手时才动 |
| 3 | `U.AI_FOLLOW` | 向指定单位移动 |
| 4 | `U.AI_GOTO` | 向指定坐标移动, 到达格再决策 |

麻痺/冰結按类型 0 处理、玩家单位 (原版分发不调用) 按主动等前置判断仍在 `plan()` 里, 不进注册表。

## mod 新增第 6 种

1. 只改数据: `rules.json` 的 `ai_type_alias`, 如 `{"params": {"ai_type_alias": {"5": 1}}}`, 类型 5 的单位按「主动」行动。键是字符串 (JSON), 值是已有类型号。
2. 带 GDScript 的 mod: 启动时调用

   ```gdscript
   AI.register_behavior(5, func(ctx, board, u, stay):
       return {"move_to": u.pos(), "action": {}})
   ```

   `AI.register_behavior` 也能覆盖 0~4。`AI.has_behavior(t)` / `AI.behavior_for(t)` 查询, `AI.reset_behaviors()` 还原为原版 5 种 (测试用)。

内容包 (纯数据) 本身仍不能凭空新增行为代码, 只能选已有类型或别名; 单位模板的 `ai` 字段与 `data/enums.json` 的 `ai` 标注要自己补上新号。

测试: `game/tests/test_ai_registry.gd` (默认 5 种、回退、注册第 6 种、别名)。

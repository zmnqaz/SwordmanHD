#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""剧情变量保留表: 哪些变量号被引擎 / 原版 (tdj) 脚本占用, 新内容的 .evs 不该写 (X2 校验、D9 文档共用同一份定义)。

剧情变量空间: game_data 里 0~127 (原版 128 个 int32); 1000+角色号 是离队标志 (GameState.ROSTER_OUT), 也在同一个字典里,
所以脚本不得读写 >= 128 的变量号。依据 engine/core/game_state.gd、
engine/battle/battle_flow.gd / battle_actions.gd / event_vm.gd。

级别: engine = 引擎自己会写, 脚本只应读 (写了会被引擎覆盖或破坏机制) -> --strict 报错
      tdj    = 原版 tdj 剧情脚本占用的变量 (基于 tdj 的改动包若写它们会影响原版剧情分支) -> 仅在表里提示, 不报错
      range  = 越出变量空间 -> 报错

用法: python3 tools/docgen/reserved_vars.py                 打印表
      python3 tools/docgen/reserved_vars.py --write-doc     生成 docs/保留变量表.md
      python3 tools/docgen/reserved_vars.py --check-doc     文档与生成结果一致 (CI 用), 不一致退出 1
"""
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/
REPO = os.path.dirname(HERE)
DOC = os.path.join(REPO, "docs", "保留变量表.md")

VAR_COUNT = 128          # 剧情变量空间 0..127
ROSTER_OUT = 1000        # game_state.gd ROSTER_OUT: 离队标志键基址
# 回合数记录基址 = params.gd turn_record_base 的默认值 (单一来源; event_vm.gd _stage_over 经 rules/clear_rank.gd 写 base + next)
sys.path.insert(0, HERE)
from params_table import load_params  # noqa: E402
TURN_RECORD_BASE = int(load_params()["turn_record_base"]["default"])

# (起, 止含, 级别, 含义, 依据)
FIXED = [
    (100, 100, "engine", "最近一次行动者的单位下标 (普攻/法术/道具都写)", "battle_actions.gd"),
    (101, 101, "engine", "普攻的被攻击者下标; 法术/道具写 -1", "battle_actions.gd"),
    (102, 102, "engine", "当前行动单位下标 (玩家选中 / AI 开始行动时写; 地图事件里 = 踩格者, kill_event 里 = 击杀者)", "battle_flow.gd / battle_input.gd 读 params.var_actor (rules.json 可改, 默认 102)"),
    (103, 106, "engine", "召唤标志 (每关开始清 0; 召唤成功置 1, 召唤物死亡清 0)", "params.summon_flag_vars (rules.json 可改, 默认 [103,104,105,106])"),
    (1, 17, "tdj", "原版剧情: 关内开关 var1~7、关内计数 var8~10、跨关分支 var11~17 (夏侯仪入队 14、修剑路线 16 ...)", "原版剧情数据"),
    (80, 90, "tdj", "原版城镇剧情: 醉汉/酒 80~82、杂货店 81、绿衣人 85、京城挖宝 88 ...", "原版城镇剧情数据"),
]


def summon_vars(skills):
    """技能表里「召唤」技能 (result_type 5 且 result_effect 14) 的标志变量号 (rate10)"""
    out = set()
    for s in skills or []:
        if isinstance(s, dict) and s.get("result_type") == 5 and s.get("result_effect") == 14 and isinstance(s.get("rate10"), int):
            out.add(s["rate10"])
    return out


def classify(var, stage_count=36, skills=None):
    """-> (级别, 含义) 或 None (空闲变量)"""
    if var < 0 or var >= VAR_COUNT:
        return ("range", "超出剧情变量空间 0~%d (>= %d 的键被离队标志等占用)" % (VAR_COUNT - 1, VAR_COUNT))
    for lo, hi, lvl, desc, _ in FIXED:
        if lo <= var <= hi:
            return (lvl, desc)
    if TURN_RECORD_BASE <= var < TURN_RECORD_BASE + max(stage_count, 1) + 1:
        return ("engine", "第 var-30 关的过关回合数 (关卡结束时由引擎写入, 通关序号读取)")
    if var in summon_vars(skills):
        return ("engine", "召唤技能标志 (技能记录的 rate10)")
    return None


def markdown():
    L = ["# 保留变量表", "",
         "<!-- 由 tools/docgen/reserved_vars.py --write-doc 生成, 请勿手改 (改 tools/docgen/reserved_vars.py 的 FIXED 后重新生成) -->", "",
         "剧情变量 (`.evs` 的 `set_var/add_var/sub_var/if_var ...` 的 `var`) 是一个字典, 键 0~127 供脚本使用 (原版 128 个 int32, 新游戏全部清 0, 关卡切换与读档都不清)。",
         "`>= 128` 的键被引擎占用 (如 `1000 + 角色号` = 离队标志), 脚本不得使用。`python3 tools/checks/content_schema.py --strict` 会对越界和下面标 **engine** 的变量的写操作报错。", "",
         "| 变量 | 级别 | 含义 | 依据 |", "|---|---|---|---|"]
    rows = [(lo, hi, lvl, d, src) for lo, hi, lvl, d, src in FIXED]
    rows.append((TURN_RECORD_BASE, TURN_RECORD_BASE + 35, "engine", "第 `var-30` 关的过关回合数 (stage_over 写 `30 + next`; 通关序号 `show_clear_rank` 读 30~64); 新游戏关数更多时占 `30 .. 30+关数`; 基址/区间/异或常量是 rules.json 参数 `turn_record_base` / `clear_rank_segments` / `clear_rank_xor` (默认 = 原版, -1 = 不记)", "rules/clear_rank.gd; event_vm.gd _stage_over"))
    rows.append((0, 0, "summon", "召唤技能的标志变量 = 该技能记录的 `rate10` (技能表里 result_type 5 / result_effect 14); 校验时按内容包的技能表扫描", "skills.gd summon_flag_var"))
    rows.sort(key=lambda r: (r[0] if r[2] != "summon" else 999, r[1]))
    for lo, hi, lvl, d, src in rows:
        if lvl == "summon":
            span = "(技能表给定)"
        else:
            span = str(lo) if lo == hi else "%d ~ %d" % (lo, hi)
        L.append("| %s | %s | %s | %s |" % (span, lvl, d, src))
    L += ["", "级别: **engine** = 引擎自己会写, 脚本只应读; **tdj** = 原版剧情脚本占用, 基于 tdj 的改动包写它们会改变原版分支 (校验只提示, 不报错); 新游戏 (`base: []`) 可以自由使用 tdj 级变量。", "",
          "表里没有的变量号 (0、18~29、关数更多时 30+关数 之后的 67~79、91~99、107~127 等) 都是空闲的, 变量 0 没有特殊含义。关卡之间不清变量: 关内局部变量请在事件 1 开头用 `set_var` 重新赋值。", ""]
    return "\n".join(L)


def main(argv):
    if "--write-doc" in argv:
        open(DOC, "w", encoding="utf-8", newline="\n").write(markdown())
        print("写入", DOC)
        return 0
    if "--check-doc" in argv:
        cur = open(DOC, encoding="utf-8").read() if os.path.isfile(DOC) else ""
        if cur != markdown():
            print("docs/保留变量表.md 已过期: 运行 python3 tools/docgen/reserved_vars.py --write-doc")
            return 1
        print("docs/保留变量表.md 是最新的")
        return 0
    print(markdown())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

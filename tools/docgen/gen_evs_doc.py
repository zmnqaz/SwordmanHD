#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""由 tools/assets/compile_events.py 的指令表 OPS 生成 docs/剧情脚本格式_指令表.md (X4)。手写正文在 docs/剧情脚本格式.md, 不被覆盖。

用法: python3 tools/docgen/gen_evs_doc.py            写 docs/剧情脚本格式_指令表.md
      python3 tools/docgen/gen_evs_doc.py --check    文档与生成结果一致 (闸门), 不一致退出 1
"""
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/
sys.path.insert(0, HERE)
import _boot  # noqa: E402,F401  (assets/ checks/ qa/ 进 sys.path)
import compile_events as ce  # noqa: E402

DOC = os.path.join(os.path.dirname(HERE), "docs", "剧情脚本格式_指令表.md")
KIND_TITLE = {"battle": "战场 (`script battle`)", "town": "城镇 (`script town`)"}
TYPE_NAME = {ce.H: "int16", ce.I: "int32", ce.L: "标签"}


def param_text(params):
    out = []
    for n, t, d in params:
        s = n + ("" if d is None else "=%d" % d)
        if t != ce.H:
            s += ":" + ("i32" if t == ce.I else "标签")
        out.append(s)
    return " ".join(out)


def flags_text(kind, op):
    f = ce.OP_FLAGS[kind]
    out = []
    if op in f["yield"]:
        out.append("让出帧")
    if op in f["scene"]:
        out.append("切场景")
    if op in f["wait"]:
        out.append("等待界面")
    if op in ce.UNIMPLEMENTED[kind]:
        out.append("引擎未实现(%s)" % ce.UNIMPLEMENTED[kind][op])
    return "、".join(out)


def markdown():
    L = ["# 剧情脚本指令表 (生成)", "",
         "<!-- 由 tools/docgen/gen_evs_doc.py 生成, 请勿手改: 指令的唯一定义在 tools/assets/compile_events.py 的 OPS (含 OP_FLAGS / UNIMPLEMENTED)。 "
         "改完后运行 python3 tools/docgen/gen_evs_doc.py 重新生成; tools/tests/test_evs_ops_gate.py 检查它没过期 -->", "",
         "手写的语法与执行模型见 [剧情脚本格式.md](剧情脚本格式.md) (其 §4 带「原版出现次数」列, 是历史统计); 本文件是**当前代码里指令表的原样导出**。",
         "参数写法: `名=默认值` 表示可省略 (省略取默认值), 无默认值的必填; `:i32` 为 int32, `:标签` 为跳转目标 (脚本里写标签名), 其余 int16。",
         "标志列: **让出帧** = 战场/城镇 VM 在该指令后多等 2 帧 (原版解释器开销); **切场景** = 执行后事件结束并切换场景; "
         "**等待界面** = 打开商店/选择框等待玩家; **引擎未实现** = VM 没有 handler (原版数据里不用, 遇到只告警跳过)。", ""]
    for kind in ("battle", "town"):
        table = ce.OPS[kind]
        names = {v[0] for v in table.values()}
        L += ["## %s: %d 条指令, %d 个命令名" % (KIND_TITLE[kind], len(table), len(names)), "",
              "| 指令 | 命令 | 参数 | 含义 | 标志 |", "|---|---|---|---|---|"]
        for op, (name, params, desc) in sorted(table.items()):
            L.append("| 0x%02X | `%s` | %s | %s | %s |" % (op, name, param_text(params), desc.replace("|", "\\|"), flags_text(kind, op)))
        L.append("")
    L += ["批量命令 (战场 `fade_out` / `hide` / `show` / `move` / `move_steps`) 的块内记录: " +
          "、".join("0x%02X→0x%02X" % (h, r) for h, r in sorted(ce.BATCH["battle"].items())) + " (头指令→记录指令)。", ""]
    L += ["## 新增一条指令的步骤", "",
          "指令定义只有一处: `tools/assets/compile_events.py` 的 `OPS`。其余都是生成物或被闸门检查 (`python3 -m unittest tools/tests/test_evs_ops_gate.py`)。", "",
          "1. 在 `tools/assets/compile_events.py` 的 `BATTLE` / `TOWN` 表里加一行 `0x指令号: (\"命令名\", [(参数名, H|I|L, 默认值或 None)], \"说明\")`; 同名命令在两张表语义应相同。",
          "2. 若该指令让出帧 / 切场景 / 等待界面, 加进同文件的 `OP_FLAGS` (并同步 GDScript 里的 `YIELD_OPS` / `SCENE_OPS` / `WAIT_OPS` 常量, 闸门会比较两边)。",
          "3. 引擎实现: 在 `game/engine/battle/event_vm.gd` (战场) 或 `game/engine/rpg/rpg_vm.gd` (城镇) 的 `_register_ops` 里 `register_op(0x指令号, handler)`; "
          "不实现的 (原版数据不用) 列进 `compile_events.py` 的 `UNIMPLEMENTED` 并写原因。mod 也可在运行时用 `ScriptVM.register_op` 追加或覆盖, 不必改解释器。",
          "4. 如果指令读写剧情变量, 参数名用 `var` / `var_x` / `var_y` / `src` / `dst` 之一, 写变量的指令登记进 `VAR_WRITES` (保留变量检查据此判断读/写)。",
          "5. 重新生成: `python3 tools/assets/compile_events.py --export-ops` (evs_ops.json, 引擎运行时编译 .evs 用), `python3 tools/docgen/gen_evs_doc.py` (本文件)。",
          "6. 验证: `python3 -m unittest tools/tests/test_evs_ops_gate.py`, Godot 无头测试。", ""]
    return "\n".join(L)


def main(argv):
    text = markdown()
    if "--check" in argv:
        cur = open(DOC, encoding="utf-8").read() if os.path.isfile(DOC) else ""
        if cur != text:
            print("docs/剧情脚本格式_指令表.md 已过期: 运行 python3 tools/docgen/gen_evs_doc.py")
            return 1
        print("docs/剧情脚本格式_指令表.md 是最新的")
        return 0
    open(DOC, "w", encoding="utf-8", newline="\n").write(text)
    print("写入", DOC)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

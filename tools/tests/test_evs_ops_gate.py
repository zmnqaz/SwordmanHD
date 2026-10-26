# SPDX-License-Identifier: GPL-3.0-only
"""X4 闸门: .evs 指令表只在 tools/assets/compile_events.py 的 OPS 定义, 其余全由它生成或被检查。
1. OPS <-> evs_ops.json (生成物未过期)
2. OPS <-> VM 注册表 (event_vm.gd / rpg_vm.gd 的 register_op) : 每条指令要么登记要么列在 UNIMPLEMENTED
3. OP_FLAGS <-> 引擎里的 YIELD_OPS / SCENE_OPS / WAIT_OPS 常量
4. docs/剧情脚本格式_指令表.md 未过期
5. 每条指令的合成脚本都能编译"""
import glob
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import _boot  # noqa: E402,F401  (assets/ checks/ qa/ 进 sys.path)
import compile_events as ce  # noqa: E402
import gen_evs_doc  # noqa: E402
import paths  # noqa: E402

VM_FILES = {"battle": "game/engine/battle/event_vm.gd", "town": "game/engine/rpg/rpg_vm.gd"}


def read(rel):
    return open(os.path.join(REPO, rel), encoding="utf-8").read()


def registered(kind):
    s = read(VM_FILES[kind])
    body = s[s.index("func _register_ops"):]
    body = body[:body.index("\nfunc ", 10)]
    regs = set()
    for m in re.finditer(r"register_op\((0x[0-9A-Fa-f]+)", body):
        regs.add(int(m.group(1), 16))
    for m in re.finditer(r"register_ops\(\[([^\]]*)\]", body):
        regs |= {int(x.strip(), 16) for x in m.group(1).split(",") if x.strip()}
    return regs


def gd_const(rel, name):
    m = re.search(r"const %s\s*:?=\s*\[([^\]]*)\]" % name, read(rel))
    assert m, "%s 里没有 %s" % (rel, name)
    return sorted(int(x.strip(), 16) for x in m.group(1).split(",") if x.strip())


class OpsJson(unittest.TestCase):
    def test_json_up_to_date(self):
        cur = open(ce.OPS_JSON, encoding="utf-8").read()
        self.assertEqual(cur, ce.ops_json_text(), "evs_ops.json 过期: python3 tools/assets/compile_events.py --export-ops")


class VmRegistry(unittest.TestCase):
    def test_registry_matches_ops(self):
        for kind in ("battle", "town"):
            ops, regs, unimpl = set(ce.OPS[kind]), registered(kind), set(ce.UNIMPLEMENTED[kind])
            self.assertEqual(regs - ops, set(), "%s: VM 登记了 OPS 里没有的指令" % kind)
            self.assertEqual(regs & unimpl, set(), "%s: 已登记的指令不该在 UNIMPLEMENTED 里" % kind)
            self.assertEqual(ops - regs - unimpl, set(),
                             "%s: 指令既没登记 handler 也没列入 UNIMPLEMENTED (新增指令步骤见 docs/剧情脚本格式_指令表.md 文末)" % kind)

    def test_flag_sets_match_engine_consts(self):
        self.assertEqual(gd_const(VM_FILES["battle"], "YIELD_OPS"), sorted(ce.OP_FLAGS["battle"]["yield"]))
        self.assertEqual(gd_const(VM_FILES["town"], "YIELD_OPS"), sorted(ce.OP_FLAGS["town"]["yield"]))
        self.assertEqual(gd_const("game/engine/rpg/rpg_scene.gd", "SCENE_OPS"), sorted(ce.OP_FLAGS["town"]["scene"]))
        self.assertEqual(gd_const("game/engine/rpg/rpg_scene.gd", "WAIT_OPS"), sorted(ce.OP_FLAGS["town"]["wait"]))

    def test_flags_reference_known_ops(self):
        for kind, fl in ce.OP_FLAGS.items():
            for k, v in fl.items():
                self.assertTrue(set(v) <= set(ce.OPS[kind]), "%s.%s 含未知指令" % (kind, k))


class DocGate(unittest.TestCase):
    def test_doc_up_to_date(self):
        self.assertEqual(gen_evs_doc.main(["--check"]), 0)


def synth_script(kind):
    """每个命令名至少出现一次的合成脚本 (必填参数填 1, 标签指向事件末尾)"""
    lines = ["script " + kind, "events %d" % ce.EVENT_SLOTS[kind], "", "event 1"]
    seen = set()
    for op, (name, params, _) in sorted(ce.OPS[kind].items()):
        if name in seen or name in ("unit_ref", "return"):
            continue
        seen.add(name)
        args = []
        for p, t, d in params:
            if t == ce.L:
                args.append("%s=end" % p)
            elif d is None:
                args.append("%s=1" % p)
        if name == "if_var":
            args = ["cmp=eq"] + args
        elif name in ("fade_out", "hide", "show"):
            args = ["ids=0,1"]
        elif name in ("move", "move_steps"):
            continue   # 批量命令带块, 由 tdj 脚本往返覆盖
        lines.append("    %s %s" % (name, " ".join(args)))
    lines += ["end:", "    return", ""]
    return "\n".join(lines)


class SyntheticCompile(unittest.TestCase):
    def test_synthetic_every_command(self):
        for kind in ("battle", "town"):
            self.assertTrue(ce.compile_script(synth_script(kind), "synthetic-" + kind))


if __name__ == "__main__":
    unittest.main()

# SPDX-License-Identifier: GPL-3.0-only
"""X1: game/content/templates/minimal_game (base 为空的全新游戏骨架) 通过 strict 校验, 并能被引擎无头加载、新游戏进入起点城镇、
走完城镇事件、打通第 0 关。无头部分需要 Godot 与原版资源 (UI 皮肤/角色贴图仍取自原图仓库), 缺则跳过。"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import _boot  # noqa: E402,F401  (assets/ checks/ qa/ 进 sys.path)
import content_schema as cs  # noqa: E402
import paths  # noqa: E402

PACK = os.path.join(paths.REPO, "game", "content", "templates", "minimal_game")


def can_run():
    try:
        return os.path.isfile(paths.godot_exe()) and os.path.isfile(os.path.join(paths.original_dir(), "index.json"))
    except Exception:
        return False


def run_game(args, timeout=240):
    cmd = [paths.godot_exe(), "--headless", "--path", os.path.join(paths.REPO, "game"), "--fixed-fps", "25", "--", "--content=minimal_game",
           "--skip-movies"] + args
    p = subprocess.run(cmd, capture_output=True, timeout=timeout)
    return (p.stdout + p.stderr).decode("utf-8", "replace")


class MinimalGameStatic(unittest.TestCase):
    def test_schema_strict(self):
        self.assertEqual(cs.check(["minimal_game"], strict=True), [])

    def test_base_empty_and_start(self):
        import json
        m = json.load(open(os.path.join(PACK, "manifest.json"), encoding="utf-8"))
        self.assertEqual(m["base"], [])
        self.assertEqual(m["start"]["kind"], "town")


@unittest.skipUnless(can_run(), "没有 Godot 或原版资源")
class MinimalGameHeadless(unittest.TestCase):
    def test_new_game_enters_start_town(self):
        out = run_game(["--fast", "--press=20:ui_accept", "--quit=200"])
        self.assertIn("RPG 场景 Rpg/min", out)
        self.assertNotIn("SCRIPT ERROR", out)

    def test_town_walk_all(self):
        out = run_game(["--scene=rpg0", "--skip-dialog", "--walk-all"])
        self.assertIn("走查 城镇 0", out)
        self.assertIn("问题 0", out)
        self.assertNotIn("SCRIPT ERROR", out)

    def test_stage0_playthrough(self):
        out = run_game(["--scene=stage0", "--fast", "--autoplay", "--god", "--seed=1", "--quit=6000"])
        self.assertIn("判定: win", out)
        self.assertIn("结局: 回到标题", out)
        self.assertNotIn("SCRIPT ERROR", out)


if __name__ == "__main__":
    unittest.main()

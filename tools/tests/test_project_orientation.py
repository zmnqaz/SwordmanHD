# SPDX-License-Identifier: GPL-3.0-only
"""手机上必须锁定横屏: 项目设置 display/window/handheld/orientation 取 0 (横屏) / 2 (反向横屏) / 4 (传感器横屏),
不能是 6 (传感器, 含竖屏) 或竖屏值。画面是 16:10 横向游戏, 竖屏下启动、再横竖切换时视口与触摸映射跟不上 (魅族 20 Pro 实测: 竖屏进游戏,
切横屏再切回竖屏显示被拉伸、触摸不准)。"""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _boot  # noqa: E402,F401
from paths import REPO  # noqa: E402

LANDSCAPE = {0: "横屏", 2: "反向横屏", 4: "传感器横屏"}


class OrientationTest(unittest.TestCase):
    def test_handheld_orientation_is_landscape(self):
        cfg = open(os.path.join(REPO, "game", "project.godot"), encoding="utf-8").read()
        m = re.search(r"^window/handheld/orientation=(\d+)", cfg, re.M)
        self.assertIsNotNone(m, "project.godot 里没有 window/handheld/orientation")
        self.assertIn(int(m.group(1)), LANDSCAPE, "手机方向必须是横屏 (0/2/4), 不能放开竖屏")


if __name__ == "__main__":
    unittest.main()

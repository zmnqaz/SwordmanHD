# SPDX-License-Identifier: GPL-3.0-only
"""布局表 stats 与元素一致 (tools/checks/layout_stats.py --check), 防止改了布局表忘记重算统计。"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import _boot  # noqa: E402,F401  (assets/ checks/ qa/ 进 sys.path)
import layout_stats  # noqa: E402


class LayoutStatsTest(unittest.TestCase):
    def test_stats_up_to_date(self):
        self.assertEqual(layout_stats.main(["--check"]), 0, "layout.json 的 stats 过期: python tools/checks/layout_stats.py")


if __name__ == "__main__":
    unittest.main()

# SPDX-License-Identifier: GPL-3.0-only
"""Android 包名只能有一个值: 导出预设 package/unique_name、运行时 ResPacks.ANDROID_PACKAGE (资源包目录
/storage/emulated/0/Android/data/<包名>/files 由它拼出)、tools/platform/build_android.py 的 PACKAGE (adb push 目标) 三处必须一致,
否则装上的应用去别的目录找资源包, 屏幕上只会提示「找不到资源包」。改包名三处一起改。"""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _boot  # noqa: E402,F401
from paths import REPO  # noqa: E402


def _read(*p):
    return open(os.path.join(REPO, *p), encoding="utf-8").read()


def preset_value(cfg, platform, key):
    """export_presets.cfg 里 platform=<platform> 那个预设 (含其 .options 段) 的 key 值"""
    i = cfg.index('platform="%s"' % platform)
    j = cfg.find("\n[preset.", cfg.index("[preset.", cfg.index("\n", i)) + 1)  # 跳过本预设的 .options 段, 到下一个预设
    sec = cfg[i:j if j > 0 else len(cfg)]
    m = re.search(r'^%s="([^"]*)"' % re.escape(key), sec, re.M)
    return m.group(1) if m else None


class AndroidPackageTest(unittest.TestCase):
    def test_three_copies_agree(self):
        preset = preset_value(_read("game", "export_presets.cfg"), "Android", "package/unique_name")
        m = re.search(r'^const ANDROID_PACKAGE := "([^"]+)"', _read("game", "engine", "core", "res_packs.gd"), re.M)
        b = re.search(r'^PACKAGE = "([^"]+)"', _read("tools", "platform", "build_android.py"), re.M)
        self.assertTrue(preset, "export_presets.cfg 的 Android 预设里找到 package/unique_name")
        self.assertTrue(m, "res_packs.gd 里找到 ANDROID_PACKAGE")
        self.assertTrue(b, "build_android.py 里找到 PACKAGE")
        self.assertEqual(m.group(1), preset, "ResPacks.ANDROID_PACKAGE 与导出预设 package/unique_name 一致")
        self.assertEqual(b.group(1), preset, "build_android.PACKAGE 与导出预设 package/unique_name 一致")

    def test_preset_parser_reads_the_right_section(self):
        cfg = ('[preset.0]\nname="A"\nplatform="Android"\n\n[preset.0.options]\npackage/unique_name="a.b"\n\n'
               '[preset.1]\nname="B"\nplatform="iOS"\n\n[preset.1.options]\npackage/unique_name="x.y"\n')
        self.assertEqual(preset_value(cfg, "Android", "package/unique_name"), "a.b")
        self.assertEqual(preset_value(cfg, "iOS", "package/unique_name"), "x.y")


if __name__ == "__main__":
    unittest.main()

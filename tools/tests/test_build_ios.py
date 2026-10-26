# SPDX-License-Identifier: GPL-3.0-only
import os
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import build_ios as B  # noqa: E402


class XcodebuildTest(unittest.TestCase):
    def test_command_builds_unsigned_device_archive(self):
        c = B.xcodebuild_cmd("/p/A.xcodeproj", "/a/A.xcarchive")
        self.assertEqual(c[0], "xcodebuild")
        self.assertEqual(c[c.index("-project") + 1], "/p/A.xcodeproj")
        self.assertEqual(c[c.index("-sdk") + 1], "iphoneos", "真机 SDK (不是模拟器)")
        self.assertEqual(c[c.index("-archivePath") + 1], "/a/A.xcarchive")
        for flag in ("CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="):
            self.assertIn(flag, c, "不签名: 签名交给自签工具")
        self.assertEqual(c[-1], "archive")


class LayoutTest(unittest.TestCase):
    def test_project_is_in_a_subfolder_and_deliverables_stay_on_top(self):
        """dist/ios/ 顶层只放成品 (xcode.zip、IPA); Godot 导出的一堆工程文件收在 xcode/ 子目录里, 不平铺"""
        self.assertEqual(os.path.dirname(B.PROJECT), B.XCODE_DIR)
        self.assertEqual(os.path.dirname(B.XCODE_DIR), B.OUT)
        self.assertEqual(os.path.dirname(B.IPA), B.OUT)
        self.assertEqual(os.path.dirname(B.XCODE_ZIP), B.OUT)


class IpaTest(unittest.TestCase):
    def test_ipa_is_payload_zip_with_the_app(self):
        with tempfile.TemporaryDirectory() as d:
            app = os.path.join(d, "x.xcarchive", "Products", "Applications", "SwordmanHD.app")
            os.makedirs(os.path.join(app, "sub"))
            open(os.path.join(app, "SwordmanHD"), "w").write("bin")
            open(os.path.join(app, "sub", "a.txt"), "w").write("a")
            ipa = os.path.join(d, "out.ipa")
            B.make_ipa(os.path.join(d, "x.xcarchive"), ipa)
            names = sorted(zipfile.ZipFile(ipa).namelist())
            self.assertEqual(names, ["Payload/SwordmanHD.app/SwordmanHD", "Payload/SwordmanHD.app/sub/a.txt"])

    def test_missing_app_is_an_error(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(SystemExit):
                B.make_ipa(d, os.path.join(d, "o.ipa"))


class PresetTest(unittest.TestCase):
    def test_ios_preset_matches_the_runtime_paths(self):
        """导出预设里的包名与代码里一致; 文件共享打开 (资源包靠它拷进应用)"""
        s = open(os.path.join(B.REPO, "game", "export_presets.cfg"), encoding="utf-8").read()
        i = s.index('platform="iOS"')
        sec = s[i:]
        self.assertIn('application/bundle_identifier="com.tdj.swordmanhd"', sec)
        self.assertIn("user_data/accessible_from_files_app=true", sec)
        self.assertIn("user_data/accessible_from_itunes_sharing=true", sec)
        self.assertIn("application/export_project_only=true", sec, "Linux 上只能导工程")

    def test_templates_dir_macos(self):
        import build_windows as W
        old = (W.sys.platform, W.os.name)
        try:
            W.sys.platform, W.os.name = "darwin", "posix"
            self.assertTrue(W.templates_dir("4.7.2.stable").endswith(
                "Library/Application Support/Godot/export_templates/4.7.2.stable"))
        finally:
            W.sys.platform, W.os.name = old


if __name__ == "__main__":
    unittest.main()


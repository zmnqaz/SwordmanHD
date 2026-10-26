# SPDX-License-Identifier: GPL-3.0-only
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import setup_android as S  # noqa: E402


class UrlTest(unittest.TestCase):
    def test_urls_name_the_right_artifacts(self):
        self.assertIn("/17/ga/", S.jdk_url())
        self.assertIn("api.adoptium.net", S.jdk_url())
        u = S.cmdline_tools_url()
        self.assertTrue(u.startswith("https://dl.google.com/android/repository/commandlinetools-"))
        self.assertTrue(u.endswith("-%s_latest.zip" % S.CMDLINE_TOOLS_REV))

    def test_sdk_versions_match_godot_template(self):
        """与 Godot 4.7.2 导出模板 (config.gradle: buildTools 36.1.0, compileSdk 36) 一致; 升级 Godot 时这里要对"""
        self.assertEqual(S.SDK_VERSIONS, {"build_tools": "36.1.0", "platform": "36"})
        self.assertEqual(S.JDK_MAJOR, 17)


class LayoutTest(unittest.TestCase):
    def test_paths_under_home(self):
        p = S.paths_of("/x/and")
        self.assertTrue(p["java"].replace("\\", "/").startswith("/x/and/jdk/bin/java"))
        self.assertTrue(p["build_tools"].replace("\\", "/").endswith("Sdk/build-tools/36.1.0"))
        self.assertTrue(p["platform"].replace("\\", "/").endswith("Sdk/platforms/android-36"))

    def test_missing_lists_everything_for_an_empty_dir(self):
        with tempfile.TemporaryDirectory() as d:
            m = S.missing(d)
            self.assertEqual(len(m), 6, m)
            self.assertTrue(any("JDK 17" in x for x in m))
            self.assertTrue(any("debug.keystore" in x for x in m))

    def test_missing_is_empty_when_everything_exists(self):
        with tempfile.TemporaryDirectory() as d:
            p = S.paths_of(d)
            for k in ("java", "sdkmanager", "adb", "keystore"):
                os.makedirs(os.path.dirname(p[k]), exist_ok=True)
                open(p[k], "w").close()
            for k in ("build_tools", "platform"):
                os.makedirs(p[k], exist_ok=True)
            self.assertEqual(S.missing(d), [])


class EditorSettingsTest(unittest.TestCase):
    VALUES = {"export/android/java_sdk_path": "/j", "export/android/debug_keystore_pass": "android"}

    def test_creates_a_minimal_file(self):
        t = S.apply_settings_text("", self.VALUES)
        self.assertIn("[resource]", t)
        self.assertIn('export/android/java_sdk_path = "/j"', t)

    def test_replaces_existing_lines_and_keeps_the_rest(self):
        old = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\ninterface/theme = "x"\nexport/android/java_sdk_path = ""\n'
        t = S.apply_settings_text(old, self.VALUES)
        self.assertIn('interface/theme = "x"', t)
        self.assertEqual(t.count("export/android/java_sdk_path"), 1)
        self.assertIn('export/android/java_sdk_path = "/j"', t)
        self.assertIn('export/android/debug_keystore_pass = "android"', t)

    def test_idempotent(self):
        once = S.apply_settings_text("", self.VALUES)
        self.assertEqual(S.apply_settings_text(once, self.VALUES), once)

    def test_windows_backslashes_become_slashes(self):
        t = S.apply_settings_text("", {"export/android/java_sdk_path": "C:\\a\\b"})
        self.assertIn('"C:/a/b"', t)


if __name__ == "__main__":
    unittest.main()

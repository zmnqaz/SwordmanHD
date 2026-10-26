# SPDX-License-Identifier: GPL-3.0-only
"""APK 重新签名与整包命令行 (tools/platform/apk_sign.py + bundle_apk.py): 命令拼装、工具查找提示、个人密钥库缺省位置、参数校验。
不依赖真的 JDK / Android SDK (真实签名在 build_android.py --bundle 和 bundle_apk.py 的实测里用 apksigner verify 验过)。"""
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "platform"))
import apk_sign as S  # noqa: E402
import bundle_apk  # noqa: E402


class CommandTest(unittest.TestCase):
    def test_zipalign_command_aligns_to_4_bytes_and_page_aligns_libs(self):
        c = S.align_cmd("zipalign", "in.apk", "out.apk")
        self.assertEqual(c, ["zipalign", "-f", "-p", "4", "in.apk", "out.apk"])

    def test_sign_command_uses_given_key_and_writes_to_out(self):
        c = S.sign_cmd("apksigner", "k.keystore", "alias1", "pw", "in.apk", "out.apk")
        self.assertEqual(c[:2], ["apksigner", "sign"])
        self.assertEqual(c[c.index("--ks") + 1], "k.keystore")
        self.assertEqual(c[c.index("--ks-key-alias") + 1], "alias1")
        self.assertEqual(c[c.index("--ks-pass") + 1], "pass:pw")
        self.assertEqual(c[c.index("--key-pass") + 1], "pass:pw")
        self.assertEqual(c[c.index("--out") + 1], "out.apk")
        self.assertEqual(c[-1], "in.apk")


class ToolsTest(unittest.TestCase):
    def test_missing_tools_error_says_how_to_install(self):
        with tempfile.TemporaryDirectory() as d, mock.patch("shutil.which", return_value=None):
            with self.assertRaises(S.SignError) as cm:
                S.find_tools(d)
            self.assertIn("setup_android.py", str(cm.exception))

    def test_password_is_long_and_alnum(self):
        p = S.new_password()
        self.assertGreaterEqual(len(p), 24)
        self.assertTrue(p.isalnum(), "纯字母数字: 放进命令行 / 环境变量不用转义")
        self.assertNotEqual(p, S.new_password())

    def test_default_keystore_lives_in_home_and_is_fresh_the_first_time(self):
        with tempfile.TemporaryDirectory() as home:
            with mock.patch.object(S, "DEFAULT_DIR", os.path.join(home, ".swordmanhd")):
                ks, pw, fresh = S.default_keystore()
                self.assertTrue(ks.startswith(home))
                self.assertEqual((pw, fresh), ("", True))
                os.makedirs(os.path.dirname(ks))
                with open(ks, "wb") as f:
                    f.write(b"x")
                with open(ks + ".pass", "w") as f:
                    f.write("secret\n")
                self.assertEqual(S.default_keystore(), (ks, "secret", False), "已有密钥库和密码文件: 复用 (以后更新才能覆盖安装)")

    def test_existing_keystore_is_never_regenerated(self):
        with tempfile.TemporaryDirectory() as d:
            ks = os.path.join(d, "a.keystore")
            with open(ks, "wb") as f:
                f.write(b"old")
            self.assertFalse(S.ensure_keystore("keytool-not-run", ks, "a", "pw"))
            with open(ks, "rb") as f:
                self.assertEqual(f.read(), b"old")


class CliTest(unittest.TestCase):
    def test_missing_apk_is_an_error(self):
        self.assertEqual(bundle_apk.main(["/no/such.apk"]), 1)

    def test_output_cannot_overwrite_the_input(self):
        with tempfile.TemporaryDirectory() as d:
            apk = os.path.join(d, "a.apk")
            with open(apk, "wb") as f:
                f.write(b"x")
            self.assertEqual(bundle_apk.main([apk, "--out", apk]), 1)

    def test_own_keystore_needs_alias_and_password(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(bundle_apk.S, "find_tools", return_value={}):
            apk = os.path.join(d, "a.apk")
            ks = os.path.join(d, "my.keystore")
            for f_ in (apk, ks):
                with open(f_, "wb") as f:
                    f.write(b"x")
            self.assertEqual(bundle_apk.main([apk, "--keystore", ks]), 1, "没给别名和密码")
            self.assertEqual(bundle_apk.main([apk, "--keystore", os.path.join(d, "nope.keystore"), "--alias", "a", "--ks-pass", "p"]), 1, "密钥库不存在")


if __name__ == "__main__":
    unittest.main()

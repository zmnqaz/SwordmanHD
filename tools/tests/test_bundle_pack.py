# SPDX-License-Identifier: GPL-3.0-only
"""整包 (tools/platform/bundle_pack.py + bundle_ipa.py): 选包、清单、往 APK / IPA 这种 zip 里加资源包。不依赖 Godot / Android SDK。"""
import json
import os
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "platform"))
import bundle_pack as B  # noqa: E402
import bundle_ipa  # noqa: E402


def make_pkgs(root, names=None, mods=("face_hk",)):
    names = names if names is not None else ["common_assets", "common_story", "hd_images", "hd_movies", "classic_images", "classic_movies"]
    os.makedirs(os.path.join(root, "resource"))
    os.makedirs(os.path.join(root, "mod"))
    for n in names:
        open(os.path.join(root, "resource", n + ".pck"), "wb").write(b"PCK-" + n.encode())
    for m in mods:
        open(os.path.join(root, "mod", m + ".pck"), "wb").write(b"MOD-" + m.encode())


def make_zip(path, files):
    with zipfile.ZipFile(path, "w") as z:
        for n, data in files.items():
            z.writestr(n, data, compress_type=zipfile.ZIP_DEFLATED)


class SelectTest(unittest.TestCase):
    def test_editions_pick_the_right_packs(self):
        with tempfile.TemporaryDirectory() as d:
            make_pkgs(d)
            hd = B.select(d, "hd")
            self.assertEqual(hd["resource"], ["common_assets", "common_story", "hd_images", "hd_movies"])
            self.assertEqual(hd["mod"], ["face_hk"])
            cl = B.select(d, "classic", with_mod=False)
            self.assertEqual(cl["resource"], ["common_assets", "common_story", "classic_images", "classic_movies"])
            self.assertEqual(cl["mod"], [])

    def test_missing_pack_and_bad_edition_are_errors(self):
        with tempfile.TemporaryDirectory() as d:
            make_pkgs(d, names=["common_assets", "common_story"])
            with self.assertRaises(B.BundleError) as cm:
                B.select(d, "hd")
            self.assertIn("hd_images.pck", str(cm.exception))
            with self.assertRaises(B.BundleError):
                B.select(d, "ultra")

    def test_manifest_round_trips_with_the_runtime_format(self):
        m = json.loads(B.manifest_bytes({"resource": ["common_assets"], "mod": ["face_hk"]}))
        self.assertEqual(m, {"resource": ["common_assets"], "mod": ["face_hk"]})


class InjectTest(unittest.TestCase):
    def test_apk_gets_stored_bundle_and_loses_old_signature(self):
        with tempfile.TemporaryDirectory() as d:
            make_pkgs(d)
            apk = os.path.join(d, "a.apk")
            make_zip(apk, {"AndroidManifest.xml": b"<m/>", "META-INF/CERT.RSA": b"sig", "assets/content/x.json": b"{}" * 100})
            sel = B.select(d, "hd")
            out = os.path.join(d, "b.apk")
            B.inject(apk, out, B.entries(d, sel, "assets"), drop_prefixes=("META-INF/",))
            with zipfile.ZipFile(out) as z:
                names = z.namelist()
                self.assertNotIn("META-INF/CERT.RSA", names, "旧签名要去掉 (之后重新签)")
                self.assertIn("AndroidManifest.xml", names)
                self.assertEqual(z.read("assets/content/x.json"), b"{}" * 100, "原有条目原样搬")
                self.assertEqual(z.getinfo("assets/content/x.json").compress_type, zipfile.ZIP_DEFLATED, "原有条目保持压缩方式")
                for n in ("common_assets", "common_story", "hd_images", "hd_movies"):
                    i = z.getinfo("assets/bundled/resource/%s.pck" % n)
                    self.assertEqual(i.compress_type, zipfile.ZIP_STORED, "资源包不压缩, 运行时才能原地挂载")
                    self.assertEqual(z.read(i), b"PCK-" + n.encode())
                self.assertEqual(z.read("assets/bundled/mod/face_hk.pck"), b"MOD-face_hk")
                m = json.loads(z.read("assets/bundled/manifest.json"))
                self.assertEqual(m["resource"], sel["resource"])
                self.assertEqual(m["mod"], ["face_hk"])

    def test_duplicate_entry_is_an_error(self):
        with tempfile.TemporaryDirectory() as d:
            make_pkgs(d)
            apk = os.path.join(d, "a.apk")
            make_zip(apk, {"assets/bundled/manifest.json": b"old"})
            with self.assertRaises(B.BundleError):
                B.inject(apk, os.path.join(d, "b.apk"), B.entries(d, B.select(d, "hd"), "assets"))


class IpaTest(unittest.TestCase):
    def test_ipa_bundle_goes_inside_the_app_folder(self):
        with tempfile.TemporaryDirectory() as d:
            make_pkgs(d)
            ipa = os.path.join(d, "SwordmanHD-unsigned.ipa")
            make_zip(ipa, {"Payload/SwordmanHD.app/SwordmanHD": b"bin", "Payload/SwordmanHD.app/Info.plist": b"<plist/>"})
            self.assertEqual(B.app_prefix(ipa), "Payload/SwordmanHD.app")
            out = bundle_ipa.make_bundled_ipa(ipa, d, "classic", True)
            self.assertTrue(out.endswith("SwordmanHD-bundled-classic-unsigned.ipa"))
            with zipfile.ZipFile(out) as z:
                names = z.namelist()
                self.assertIn("Payload/SwordmanHD.app/SwordmanHD", names)
                self.assertIn("Payload/SwordmanHD.app/bundled/manifest.json", names)
                self.assertIn("Payload/SwordmanHD.app/bundled/resource/classic_images.pck", names)
                self.assertNotIn("Payload/SwordmanHD.app/bundled/resource/hd_images.pck", names, "原版画质不带高清包")

    def test_not_an_ipa_is_an_error(self):
        with tempfile.TemporaryDirectory() as d:
            z = os.path.join(d, "x.zip")
            make_zip(z, {"a.txt": b"x"})
            with self.assertRaises(B.BundleError):
                B.app_prefix(z)


if __name__ == "__main__":
    unittest.main()

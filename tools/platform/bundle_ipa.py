#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""iOS / iPadOS 整包 (自用): 给已经编好的未签名 IPA 加上预制资源包, 装完 (用自己的 Apple ID 自签后) 就能玩, 不用再往「文件」App 里拷资源。
**整包只给自己用, 不要公开发布** (含原作衍生资源, 见 README 声明)。

  python3 tools/platform/bundle_ipa.py dist/ios/SwordmanHD-unsigned.ipa                  高清画质 (pkgs/ 里的 hd_*), 出 dist/ios/SwordmanHD-bundled-hd-unsigned.ipa
  python3 tools/platform/bundle_ipa.py <ipa> --edition classic --pkgs D:\\pkgs --out x.ipa

IPA 本身只有 macOS (Xcode) 或 GitHub Actions 的 ios.yml 能编; 拿到 IPA 后这一步在任何系统上都能做 (IPA 就是个 zip): 把
bundled/{manifest.json, resource/*.pck, mod/*.pck} 放进 Payload/<名>.app/ 里。之后 Sideloader / Sideloadly / AltStore 签名时会把它们一起封进签名。
运行时挂载见 game/engine/core/res_packs.gd (ResPacks.bundled_dir: .app 里的 bundled/)。
体积: 高清 ~1.4 GB、原版画质 ~0.8 GB (自签工具上传要等一会)。
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bundle_pack as B  # noqa: E402


def make_bundled_ipa(ipa: str, pkgs: str, edition: str, with_mod: bool, out: str = "") -> str:
    sel = B.select(pkgs, edition, with_mod)
    out = out or os.path.join(os.path.dirname(os.path.abspath(ipa)), "SwordmanHD-bundled-%s-unsigned.ipa" % edition)
    B.inject(ipa, out, B.entries(pkgs, sel, B.app_prefix(ipa)))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ipa", help="未签名的 IPA (build_ios.py --ipa 或 GitHub Actions 出的)")
    ap.add_argument("--pkgs", default=B.PKGS, help="预制资源包目录 (缺省 <仓库>/pkgs, 里面是 resource/ 与 mod/)")
    ap.add_argument("--edition", default="hd", choices=sorted(B.EDITIONS), help="hd 高清画质 (缺省) / classic 原版画质")
    ap.add_argument("--no-mod", action="store_true", help="不带 mod/ 里的包 (如港漫头像)")
    ap.add_argument("--out", default="", help="输出 IPA 路径 (缺省在原 IPA 旁边)")
    a = ap.parse_args(argv)
    if not os.path.isfile(a.ipa):
        print("错误: 找不到 IPA: " + a.ipa, file=sys.stderr)
        return 1
    try:
        out = make_bundled_ipa(a.ipa, a.pkgs, a.edition, not a.no_mod, a.out)
    except B.BundleError as e:
        print("错误: " + str(e), file=sys.stderr)
        return 1
    print("整包 IPA: %s  %s (只自用, 不要公开发布)" % (out, B.human(os.path.getsize(out))))
    return 0


if __name__ == "__main__":
    sys.exit(main())

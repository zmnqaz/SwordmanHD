#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Android 整包 (自用): 给**已经编好 (如 GitHub Releases 下载) 的 APK** 加上你自己的资源包, 并用**你自己的密钥**重新签名。
**整包只给自己用, 不要公开发布** (含原作衍生资源, 见 README 声明)。

  python3 tools/platform/bundle_apk.py SwordmanHD.apk --pkgs D:\\pkgs                       高清画质, 出 SwordmanHD-bundled-hd.apk
  python3 tools/platform/bundle_apk.py SwordmanHD.apk --pkgs ./pkgs --edition classic     原版画质 (体积小一半)

--pkgs 是资源包目录 (里面是 resource/ 与 mod/ 两个文件夹, 就是 ResTool / 资源生成工具 出的那两个), 缺省 <仓库>/pkgs。

怎么签名 (为什么要自己的密钥):
  APK 里加了文件, 原来的签名就失效了, 不重新签装不上 (没签名的 APK 手机会直接拒绝)。Android 只检查「有没有签、签得对不对」,
  不检查「是谁签的」, 所以**用你自己的密钥签就行, 用不着我们的**。
  - 缺省: 第一次运行自动生成一把个人密钥 ~/.swordmanhd/bundle.keystore (密码存同目录 bundle.keystore.pass), 以后一直用它,
    所以你以后更新整包可以直接覆盖安装。**这个目录请自己备份**, 丢了以后更新整包就得先卸载再装 (存档会丢)。
  - 想用自己已有的密钥: --keystore <路径> --alias <别名> --ks-pass <密码> (或环境变量 BUNDLE_KS_PASS)。
  - 签完的 APK 和 Releases 里原版 APK 的**签名不同, 不能互相覆盖安装**: 手机上已经装了 Releases 的 APK 的话, 要先卸载 (存档会丢, 先备份)。

需要的工具: JDK 17 + Android build-tools (zipalign / apksigner / keytool)。没有的话 python3 tools/platform/setup_android.py 一次性装好 (放 TDJ_ANDROID_HOME 或 <仓库>/tools/android)。
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apk_sign as S  # noqa: E402
import bundle_pack as B  # noqa: E402


def make_bundled_apk(apk: str, pkgs: str, edition: str, with_mod: bool, out: str, tools: dict, ks: str, alias: str, password: str) -> str:
    sel = B.select(pkgs, edition, with_mod)
    tmp = out + ".inject.tmp"
    try:
        B.inject(apk, tmp, B.entries(pkgs, sel, "assets"), drop_prefixes=("META-INF/",))
        S.align_and_sign(tools, tmp, out, ks, alias, password)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("apk", help="已经编好的 APK (如 Releases 下载的 SwordmanHD.apk)")
    ap.add_argument("--pkgs", default=B.PKGS, help="资源包目录 (里面是 resource/ 与 mod/), 缺省 <仓库>/pkgs")
    ap.add_argument("--edition", default="hd", choices=sorted(B.EDITIONS), help="hd 高清画质 (缺省) / classic 原版画质")
    ap.add_argument("--no-mod", action="store_true", help="不带 mod/ 里的包 (如港漫头像)")
    ap.add_argument("--out", default="", help="输出 APK 路径 (缺省在原 APK 旁边: SwordmanHD-bundled-<画质>.apk)")
    ap.add_argument("--keystore", default="", help="自己的签名密钥库 (缺省 ~/.swordmanhd/bundle.keystore, 第一次自动生成)")
    ap.add_argument("--alias", default="", help="密钥别名 (用自己的密钥库时必填; 缺省密钥库用 %s)" % S.DEFAULT_ALIAS)
    ap.add_argument("--ks-pass", default=os.environ.get("BUNDLE_KS_PASS", ""), help="密钥库密码 (也可用环境变量 BUNDLE_KS_PASS)")
    ap.add_argument("--android-home", default="", help="JDK + Android SDK 目录 (缺省 TDJ_ANDROID_HOME 或 <仓库>/tools/android, 再找 PATH)")
    a = ap.parse_args(argv)
    if not os.path.isfile(a.apk):
        print("错误: 找不到 APK: " + a.apk, file=sys.stderr)
        return 1
    out = a.out or os.path.join(os.path.dirname(os.path.abspath(a.apk)), "SwordmanHD-bundled-%s.apk" % a.edition)
    if os.path.abspath(out) == os.path.abspath(a.apk):
        print("错误: 输出不能覆盖原 APK", file=sys.stderr)
        return 1
    try:
        tools = S.find_tools(a.android_home)
        if a.keystore:
            ks, alias, password = a.keystore, a.alias, a.ks_pass
            if not os.path.isfile(ks):
                raise S.SignError("找不到密钥库: " + ks)
            if not alias or not password:
                raise S.SignError("用自己的密钥库要同时给 --alias 和 --ks-pass (或环境变量 BUNDLE_KS_PASS)")
        else:
            ks, password, fresh = S.default_keystore()
            alias = S.DEFAULT_ALIAS
            if fresh:
                password = S.new_password()
                S.ensure_keystore(tools["keytool"], ks, alias, password)
                open(ks + ".pass", "w", encoding="utf-8").write(password + "\n")
                try:
                    os.chmod(ks + ".pass", 0o600)
                except OSError:
                    pass
                print("已生成你的个人签名密钥: %s (密码在同目录 .pass 文件里) —— 请备份这个目录, 以后更新整包要用同一把密钥才能覆盖安装" % ks)
        make_bundled_apk(a.apk, a.pkgs, a.edition, not a.no_mod, out, tools, ks, alias, password)
    except (B.BundleError, S.SignError) as e:
        print("错误: " + str(e), file=sys.stderr)
        return 1
    print("整包 APK: %s  %s (用你自己的密钥签名; 只自用, 不要公开发布)" % (out, B.human(os.path.getsize(out))))
    print("提示: 手机上如果装着 Releases 里的 APK, 要先卸载 (签名不同, 存档会丢, 先备份) 再装这个整包。")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""出 iOS 包 (iPhone / iPad): 导出 Xcode 工程 (Linux/Windows/macOS 都行), 在 macOS 上可继续编出未签名的 IPA。说明见 docs/打包/iOS.md。
编译 iOS 需要 Apple 的 Xcode (只有 macOS 有), 所以分两段:
  python3 tools/platform/build_ios.py            任何系统: 导出 Xcode 工程到 dist/ios/xcode/ (SwordmanHD.xcodeproj + 引擎库 + pck) 并打成 dist/ios/SwordmanHD-xcode.zip
                                                 dist/ios/ 顶层只放成品 (xcode.zip、IPA), 工程的一堆文件都收在 xcode/ 里
  python3 tools/platform/build_ios.py --ipa      macOS (有 Xcode): 导出后 xcodebuild 编译 (不签名), 出 dist/ios/SwordmanHD-unsigned.ipa
  python3 tools/platform/build_ios.py --ipa --bundle   同上, 再把 pkgs/ 里的预制资源包打进去, 出 dist/ios/SwordmanHD-bundled-<画质>-unsigned.ipa (整包, 只自用);
                                                 已经有 IPA 的话直接 python3 tools/platform/bundle_ipa.py <ipa> (任何系统都行)
未签名的 IPA 用 Sideloader / Sideloadly / AltStore 这类自签工具以你自己的 Apple ID 签名后装到 iPhone/iPad (免费账号证书 7 天); 云上的 macOS 构建机
见 .github/workflows/ios.yml。资源包 (resource/ 与 mod/ 文件夹里的 .pck, 由玩家自己的原版生成) 不在包里, 装好后拷进应用的文件夹 (文档里有写)。
前提: Godot 4.7.2 + 同版本导出模板 (含 ios.zip); 工程里的 Team ID 是占位值 (0000000000), 自签工具会换成你自己的。
"""
import argparse
import os
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _boot  # noqa: E402,F401
import paths  # noqa: E402
from build_windows import templates_dir  # noqa: E402
from build_android import godot_version  # noqa: E402

REPO = paths.REPO
OUT = os.path.join(REPO, "dist", "ios")                   # 顶层只放成品: xcode.zip、IPA
XCODE_DIR = os.path.join(OUT, "xcode")                    # Godot 导出的 Xcode 工程 (一堆 xcframework / pck 等) 都收在这里, 不平铺在顶层
PROJECT = os.path.join(XCODE_DIR, "SwordmanHD.xcodeproj")
ARCHIVE = os.path.join(REPO, "dist", "ios_build", "SwordmanHD.xcarchive")
IPA = os.path.join(OUT, "SwordmanHD-unsigned.ipa")
XCODE_ZIP = os.path.join(OUT, "SwordmanHD-xcode.zip")
SCHEME = "SwordmanHD"


def die(msg):
    print("错误: " + msg, file=sys.stderr)
    sys.exit(1)


def xcodebuild_cmd(project: str = PROJECT, archive: str = ARCHIVE) -> list:
    """不签名地编译并归档 (真机 arm64); 签名留给自签工具"""
    return ["xcodebuild", "-project", project, "-scheme", SCHEME, "-configuration", "Release", "-sdk", "iphoneos",
            "-destination", "generic/platform=iOS", "-archivePath", archive,
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "archive"]


def make_ipa(archive: str, ipa: str) -> None:
    """xcarchive 里的 .app 放进 Payload/ 压成 .ipa (zip)"""
    app = os.path.join(archive, "Products", "Applications", SCHEME + ".app")
    if not os.path.isdir(app):
        die("归档里没有 %s.app: %s" % (SCHEME, app))
    if os.path.isfile(ipa):
        os.remove(ipa)
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(app):
            for f in files:
                p = os.path.join(root, f)
                z.write(p, os.path.join("Payload", SCHEME + ".app", os.path.relpath(p, app)))


def export_project(godot: str) -> None:
    shutil.rmtree(XCODE_DIR, ignore_errors=True)   # 只清工程目录, 不动 dist/ios/ 里已有的 IPA
    os.makedirs(XCODE_DIR)
    game = os.path.join(REPO, "game").replace("\\", "/")
    env = paths.env_for_godot()
    print("== 导入资源 (godot --import)")
    subprocess.run([godot, "--headless", "--path", game, "--import"], capture_output=True, env=env)
    print("== 导出 Xcode 工程")
    r = subprocess.run([godot, "--headless", "--path", game, "--export-release", "iOS", os.path.join(XCODE_DIR, "SwordmanHD.ipa")],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
    if not os.path.isdir(PROJECT):
        print((r.stdout + r.stderr)[-3000:])
        die("导出 Xcode 工程失败 (Godot 退出码 %d, 上面是它的输出); 常见原因: 缺 iOS 导出模板 (ios.zip)" % r.returncode)
    print("  " + os.path.relpath(PROJECT, REPO))


def zip_project() -> None:
    with zipfile.ZipFile(XCODE_ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(XCODE_DIR):   # 压缩包里 SwordmanHD.xcodeproj 在最外层 (不带 xcode/ 这一层)
            for f in files:
                p = os.path.join(root, f)
                if not p.endswith(".ipa"):
                    z.write(p, os.path.relpath(p, XCODE_DIR))
    print("  %s  %.0f MB" % (os.path.relpath(XCODE_ZIP, REPO), os.path.getsize(XCODE_ZIP) / 1048576))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ipa", action="store_true", help="macOS: 用 xcodebuild 编译并出未签名 IPA")
    ap.add_argument("--bundle", action="store_true", help="和 --ipa 一起用: 出 IPA 后把预制资源包打进去 (整包, 只自用)")
    ap.add_argument("--edition", default="hd", choices=["hd", "classic"], help="整包的画质 (缺省 hd)")
    a = ap.parse_args()
    godot = paths.godot_exe()
    if not os.path.isfile(godot):
        die(paths.missing_godot_hint())
    td = templates_dir(godot_version(godot))
    if not os.path.isfile(os.path.join(td, "ios.zip")):
        die("缺少 iOS 导出模板 ios.zip (在 %s): 装 Godot %s 的 export templates (官方 .tpz)" % (td, godot_version(godot)))
    export_project(godot)
    if a.ipa:
        if sys.platform != "darwin" or not shutil.which("xcodebuild"):
            zip_project()
            die("--ipa 需要 macOS 和 Xcode (xcodebuild); 没有的话把 %s 拷到一台 Mac, 或用 .github/workflows/ios.yml 在云上编译" % os.path.relpath(XCODE_ZIP, REPO))
        shutil.rmtree(os.path.dirname(ARCHIVE), ignore_errors=True)
        print("== xcodebuild (不签名)")
        r = subprocess.run(xcodebuild_cmd())
        if r.returncode != 0:
            die("xcodebuild 失败 (退出码 %d)" % r.returncode)
        make_ipa(ARCHIVE, IPA)
        print("  %s  %.0f MB" % (os.path.relpath(IPA, REPO), os.path.getsize(IPA) / 1048576))
        if a.bundle:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import bundle_ipa
            if bundle_ipa.main([IPA, "--edition", a.edition]) != 0:
                return 1
    else:
        zip_project()
        print("下一步: 把它拷到 Mac 用 Xcode 打开 SwordmanHD.xcodeproj 运行; 或 python3 tools/platform/build_ios.py --ipa (macOS); 或推到 GitHub 用 Actions 编译。详见 docs/打包/iOS.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())

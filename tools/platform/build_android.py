#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""出 Android 包: 导出 debug APK, 可选把资源包 (resource/ 与 mod/ 里的 .pck) 一并装到连着的手机。说明见 docs/打包/Android.md。
APK 只含引擎和手写内容 (约 40MB); 资源包 (约 1.5GB, 由玩家自己的原版生成, 仓库不含) 另放在手机的应用外部存储目录
/sdcard/Android/data/com.tdj.swordmanhd/files/ (游戏启动时从那里挂载, 缺包会在屏幕上提示路径)。

  python3 tools/platform/build_android.py                  导出 dist/android/SwordmanHD.apk (dist/packs/ 里有资源包就一并推到手机)
  python3 tools/platform/build_android.py --no-packs       只出 APK
  python3 tools/platform/build_android.py --install        出包后 adb 装到手机并把资源包推进去 (手机要开 USB 调试并连着)
  python3 tools/platform/build_android.py --push-packs     只把已有的资源包推到手机 (APK 已装过时用)
  python3 tools/platform/build_android.py --release        用自己的密钥签 release 版 (环境变量 GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD; 公开 CI 用)
整包 (资源直接打在 APK 里, 装完就能玩, 不用拷资源; 含原作衍生资源, **只自用, 不要公开发布**):
  python3 tools/platform/build_android.py --bundle                  高清画质 (取仓库 pkgs/ 里的预制资源包), 出 dist/android/SwordmanHD-bundled-hd.apk (~1.5GB)
  python3 tools/platform/build_android.py --bundle --edition classic   原版画质 (~0.9GB); --pkgs <目录> 指定预制包目录; --no-mod 不带 mod 包
  整包的原理 (assets/bundled/ + 运行时从 res://bundled/ 原地挂载) 见 tools/platform/bundle_pack.py 与 docs/打包/Android.md「整包」。
出的 APK 旁边会带 Windows 一键安装脚本 install_android.bat + android_install.ps1 (来自 tools/android_win/): 手机 USB 连 Windows 电脑,
双击它自动装 APK 并把资源包 (本目录/pck 或 C:/pck 下的 resource、mod 两个文件夹) 推进手机。
前提: 先 python3 tools/platform/setup_android.py 搭好 JDK/SDK (--check 可查); Godot 4.7.2 与同版本导出模板 (含 android_debug.apk);
资源包由 资源生成工具 从玩家自己的原版生成。签名是调试签名, 只用于自己装机测试; 上架要另做发布签名。
"""
import argparse
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _boot  # noqa: E402,F401
import paths  # noqa: E402
import setup_android as SA  # noqa: E402
import bundle_pack as BP  # noqa: E402
import apk_sign as AS  # noqa: E402
from build_windows import templates_dir  # noqa: E402

REPO = paths.REPO
OUT = os.path.join(REPO, "dist", "android")
APK = os.path.join(OUT, "SwordmanHD.apk")
PACKS = os.path.join(REPO, "dist", "packs")   # 全平台共用的唯一一份资源包 (tools/build_windows.py 也用)
PACK_DIRS = ["resource", "mod"]   # 手机上也保持 resource/ + mod/ 两个文件夹 (ResPacks 同样的找法); 里面的 .pck 有才推
PACKAGE = "com.tdj.swordmanhd"    # 与 game/export_presets.cfg 的 package/unique_name、ResPacks.ANDROID_PACKAGE 一致 (tools/tests/test_package_ids.py 校验)
DEVICE_DIR = "/sdcard/Android/data/%s/files" % PACKAGE


def die(msg):
    print("错误: " + msg, file=sys.stderr)
    sys.exit(1)


def godot_version(godot):
    import re
    out = subprocess.run([godot, "--version"], capture_output=True, text=True).stdout.strip()
    m = re.match(r"^([0-9.]+)\.([a-z]+[0-9]*)\..*", out)
    return "%s.%s" % m.groups() if m else out


def check_env(home):
    godot = paths.godot_exe()
    if not os.path.isfile(godot):
        die(paths.missing_godot_hint())
    miss = SA.missing(home)
    if miss:
        die("Android 构建环境不齐:\n  " + "\n  ".join(miss) + "\n先运行 python3 tools/platform/setup_android.py" + ("" if home == SA.default_home() else " --home " + home))
    td = templates_dir(godot_version(godot))
    for n in ("android_debug.apk", "android_release.apk"):
        if not os.path.isfile(os.path.join(td, n)):
            die("缺少 Android 导出模板 %s (在 %s): 装 Godot %s 的 export templates (官方 .tpz)" % (n, td, godot_version(godot)))
    return godot


RELEASE_ENV = ("GODOT_ANDROID_KEYSTORE_RELEASE_PATH", "GODOT_ANDROID_KEYSTORE_RELEASE_USER", "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD")


def export_apk(godot, release=False):
    """release: 用环境变量 RELEASE_ENV 给的自己的密钥签 release 版 (Godot 导出时读这三个变量; 同一密钥签的新版能覆盖安装旧版);
    否则用调试签名 (setup_android.py 生成的 debug.keystore, 只适合自己装机)。"""
    if release:
        miss = [k for k in RELEASE_ENV if not os.environ.get(k)]
        if miss:
            die("--release 需要环境变量 %s (签名密钥, 见 docs/打包/Android.md「签名」)" % ", ".join(miss))
        if not os.path.isfile(os.environ[RELEASE_ENV[0]]):
            die("签名密钥文件不存在: " + os.environ[RELEASE_ENV[0]])
    os.makedirs(OUT, exist_ok=True)
    print("== 导入资源 (godot --import)")
    subprocess.run([godot, "--headless", "--path", os.path.join(REPO, "game"), "--import"], capture_output=True, env=paths.env_for_godot())
    print("== 导出 APK (%s)" % ("release, 自己的密钥" if release else "debug, 调试签名"))
    r = subprocess.run([godot, "--headless", "--path", os.path.join(REPO, "game").replace("\\", "/"), "--export-release" if release else "--export-debug", "Android", APK],
                       capture_output=True, text=True, encoding="utf-8", errors="replace", env=paths.env_for_godot())
    log = r.stdout + r.stderr
    if r.returncode != 0 or not os.path.isfile(APK) or "Signed" not in log:
        print(log[-3000:])
        die("导出 APK 失败 (Godot 退出码 %d, 上面是它的输出)" % r.returncode)
    print("  %s  %.1f MB" % (os.path.relpath(APK, REPO), os.path.getsize(APK) / 1048576))
    copy_windows_installer()


def copy_windows_installer():
    """把 Windows 一键安装脚本 (tools/android_win/) 放到 APK 旁边, 整个 dist/android 拷到 Windows 电脑上就能双击装机。"""
    src = os.path.join(REPO, "tools", "android_win")
    for name in ("install_android.bat", "android_install.ps1"):
        shutil.copy2(os.path.join(src, name), os.path.join(OUT, name))
    print("  + install_android.bat / android_install.ps1 (Windows 一键装机, 资源包放本目录\\pck 或 C:\\pck)")


def make_bundle(home, pkgs, edition, with_mod, release=False):
    """整包: 在刚导出的 APK 上加 assets/bundled/ (资源包不压缩), 去掉旧签名, zipalign 后重新签名 (调试签名, --release 用自己的密钥)。"""
    p = SA.paths_of(home)
    try:
        sel = BP.select(pkgs, edition, with_mod)
        add = BP.entries(pkgs, sel, "assets")
    except BP.BundleError as e:
        die(str(e))
    final = os.path.join(OUT, "SwordmanHD-bundled-%s.apk" % edition)
    tmp = os.path.join(OUT, ".bundle_unaligned.apk")
    print("== 整包: %s 画质, 资源包 %s%s" % (edition, ", ".join(sel["resource"]), (" + mod " + ", ".join(sel["mod"])) if sel["mod"] else ""))
    BP.inject(APK, tmp, add, drop_prefixes=("META-INF/",))
    if release:
        ks, alias, pw = (os.environ[k] for k in RELEASE_ENV)
    else:
        ks, alias, pw = p["keystore"], SA.DEBUG_ALIAS, SA.DEBUG_PASS
    tools = {"zipalign": os.path.join(p["build_tools"], SA.exe("zipalign")), "apksigner": os.path.join(p["build_tools"], SA.bat("apksigner")),
             "keytool": p["keytool"], "java_home": p["jdk"]}
    try:
        AS.align_and_sign(tools, tmp, final, ks, alias, pw)
    except AS.SignError as e:
        die(str(e))
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    print("  %s  %s (只自用, 不要公开发布)" % (os.path.relpath(final, REPO), BP.human(os.path.getsize(final))))
    return final


def have_packs():
    return all(os.path.isfile(os.path.join(PACKS, "resource", n + ".pck")) for n in ("common_assets", "common_story"))


def adb(home, *args, check=True):
    cmd = [SA.paths_of(home)["adb"], *args]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if check and r.returncode != 0:
        die("adb %s 失败: %s" % (" ".join(args), (r.stdout + r.stderr).strip()[-600:]))
    return r


def device_ready(home):
    out = adb(home, "devices").stdout.splitlines()[1:]
    devs = [l.split()[0] for l in out if l.strip().endswith("device")]
    if not devs:
        die("没有连着的手机: 打开手机的 USB 调试并用线连上, 弹出授权点允许 (adb devices 应显示 device)")
    return devs[0]


def push_packs(home):
    if not have_packs():
        die("没有资源包 (%s), 先用 资源生成工具 生成资源包放进该目录" % os.path.relpath(PACKS, REPO))
    for d in PACK_DIRS:
        folder = os.path.join(PACKS, d)
        packs = sorted(f for f in os.listdir(folder) if f.endswith(".pck")) if os.path.isdir(folder) else []
        if not packs:
            continue
        adb(home, "shell", "mkdir", "-p", DEVICE_DIR + "/" + d)
        for f in packs:
            p = os.path.join(folder, f)
            print("  推送 %s/%s (%.0f MB)" % (d, f, os.path.getsize(p) / 1048576), flush=True)
            adb(home, "push", p, DEVICE_DIR + "/" + d + "/")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--home", default=SA.default_home(), help="Android 环境目录 (缺省 <仓库>/tools/android 或 TDJ_ANDROID_HOME)")
    ap.add_argument("--no-packs", action="store_true", help="只出 APK, 不打资源包")
    ap.add_argument("--install", action="store_true", help="adb 装 APK 并推资源包")
    ap.add_argument("--push-packs", action="store_true", help="只推已有的资源包到手机")
    ap.add_argument("--bundle", action="store_true", help="整包: 资源包直接打进 APK (取 pkgs/ 里的预制包), 出 SwordmanHD-bundled-<画质>.apk, 只自用")
    ap.add_argument("--edition", default="hd", choices=sorted(BP.EDITIONS), help="整包的画质: hd 高清 (缺省) / classic 原版画质")
    ap.add_argument("--pkgs", default=BP.PKGS, help="整包用的预制资源包目录 (缺省 <仓库>/pkgs, 里面是 resource/ 与 mod/)")
    ap.add_argument("--no-mod", action="store_true", help="整包不带 mod/ 里的包 (如港漫头像)")
    ap.add_argument("--release", action="store_true", help="用自己的密钥签 release 版 (环境变量 GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD)")
    a = ap.parse_args()
    home = os.path.abspath(os.path.expanduser(a.home))
    if a.push_packs:
        device_ready(home)
        push_packs(home)
        return 0
    godot = check_env(home)
    if not a.no_packs and not have_packs():
        print("提示: %s 里没有资源包, 只出 APK (资源包用 资源生成工具 生成, 放进该目录)" % os.path.relpath(PACKS, REPO))
        a.no_packs = True
    export_apk(godot, a.release)
    apk_out = APK
    if a.bundle:
        apk_out = make_bundle(home, os.path.abspath(a.pkgs), a.edition, not a.no_mod, a.release)
    if a.install:
        dev = device_ready(home)
        print("== 安装到 %s" % dev)
        adb(home, "install", "-r", apk_out)
        if not a.no_packs and not a.bundle:   # 整包里已经带了资源包, 不用再推
            push_packs(home)
        print("完成: 手机上打开「天地劫 復刻」")
    else:
        print("下一步: 手机开 USB 调试连上后 python3 tools/platform/build_android.py --install; 或自己传: APK 装好后把 %s 里的 resource、mod 两个文件夹放进手机 %s" %
              (os.path.relpath(PACKS, REPO), DEVICE_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())

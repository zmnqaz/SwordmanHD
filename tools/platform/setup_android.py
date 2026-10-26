#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""一键搭 Android 构建环境 (JDK 17 + Android SDK 最小集 + 调试签名), 供 tools/platform/build_android.py 出 APK 用。
大二进制不进仓库 (和 tools/godot 一样): 默认装到 <仓库>/tools/android/ (已 gitignore), 可用 --home 或环境变量 TDJ_ANDROID_HOME 指到别处
(已经装过的目录直接复用, 已装好的部分跳过)。

  python3 tools/platform/setup_android.py                 装 JDK 17 + SDK (platform-tools、build-tools、platform) + 调试签名, 并配置 Godot 编辑器设置
  python3 tools/platform/setup_android.py --home ~/Android  装到指定目录
  python3 tools/platform/setup_android.py --check          只检查环境是否齐全 (不下载、不写任何东西), 缺什么说什么; 齐全退出码 0
  python3 tools/platform/setup_android.py --no-godot-config 不改 Godot 编辑器设置 (默认会改, 见下)

装好后目录:
  <home>/jdk/                 Temurin JDK 17 (Godot 4.x 导出 Android 要求 17; 系统的 Java 版本不对也不影响)
  <home>/Sdk/                 platform-tools、build-tools;<版本>、platforms;android-<版本>、cmdline-tools
  <home>/debug.keystore       调试签名 (用户名 androiddebugkey, 密码 android; 只用于自己装机测试, 上架要另做发布签名)

Godot 编辑器设置 (导出 Android 只认编辑器设置, 环境变量不起作用): 幂等地写入 export/android/{java_sdk_path, android_sdk_path,
debug_keystore, debug_keystore_user, debug_keystore_pass} 这五项, 其余设置不动; 改之前把原文件备份成 .bak-<时间戳>。
版本号 (SDK_VERSIONS) 与 Godot 4.7.2 导出模板 (android_source.zip 里的 config.gradle) 一致; 升级 Godot 时要对一下。
下载走直连 (忽略 http(s)_proxy 环境变量: 本项目的机器上曾因失效的旧代理下载失败), 支持断点续传。
"""
import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _boot  # noqa: E402,F401
from paths import REPO  # noqa: E402

# 与 Godot 4.7.2 的 android_source.zip/config.gradle 一致 (compileSdk 36, buildTools 36.1.0, JDK 17)
SDK_VERSIONS = {"build_tools": "36.1.0", "platform": "36"}
JDK_MAJOR = 17
CMDLINE_TOOLS_REV = "11076708"
DEBUG_ALIAS = "androiddebugkey"
DEBUG_PASS = "android"


def default_home() -> str:
    return os.environ.get("TDJ_ANDROID_HOME") or os.path.join(REPO, "tools", "android")


def host() -> tuple:
    """(Adoptium 的 os 名, arch 名, Android 命令行工具的 os 名)"""
    s = platform.system()
    m = platform.machine().lower()
    arch = "aarch64" if m in ("arm64", "aarch64") else "x64"
    if s == "Windows":
        return "windows", "x64", "win"
    if s == "Darwin":
        return "mac", arch, "mac"
    return "linux", arch, "linux"


def jdk_url() -> str:
    os_name, arch, _ = host()
    return "https://api.adoptium.net/v3/binary/latest/%d/ga/%s/%s/jdk/hotspot/normal/eclipse" % (JDK_MAJOR, os_name, arch)


def cmdline_tools_url() -> str:
    return "https://dl.google.com/android/repository/commandlinetools-%s-%s_latest.zip" % (host()[2], CMDLINE_TOOLS_REV)


def exe(name: str) -> str:
    return name + (".exe" if platform.system() == "Windows" else "")


def bat(name: str) -> str:
    return name + (".bat" if platform.system() == "Windows" else "")


def paths_of(home: str) -> dict:
    sdk = os.path.join(home, "Sdk")
    return {
        "jdk": os.path.join(home, "jdk"),
        "java": os.path.join(home, "jdk", "bin", exe("java")),
        "keytool": os.path.join(home, "jdk", "bin", exe("keytool")),
        "sdk": sdk,
        "sdkmanager": os.path.join(sdk, "cmdline-tools", "latest", "bin", bat("sdkmanager")),
        "adb": os.path.join(sdk, "platform-tools", exe("adb")),
        "build_tools": os.path.join(sdk, "build-tools", SDK_VERSIONS["build_tools"]),
        "platform": os.path.join(sdk, "platforms", "android-" + SDK_VERSIONS["platform"]),
        "keystore": os.path.join(home, "debug.keystore"),
    }


def missing(home: str) -> list:
    """缺哪些 (空 = 环境齐全)"""
    p = paths_of(home)
    out = []
    for key, what in (("java", "JDK 17"), ("sdkmanager", "Android 命令行工具"), ("adb", "platform-tools"),
                      ("build_tools", "build-tools " + SDK_VERSIONS["build_tools"]), ("platform", "platforms;android-" + SDK_VERSIONS["platform"]),
                      ("keystore", "调试签名 debug.keystore")):
        if not os.path.exists(p[key]):
            out.append("%s (%s)" % (what, p[key]))
    return out


# ---------------------------------------------------------------- Godot 编辑器设置

def godot_settings_path(version="4.7") -> str:
    s = platform.system()
    if s == "Windows":
        base = os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~"), "Godot")
    elif s == "Darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot")
    else:
        base = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "godot")
    return os.path.join(base, "editor_settings-%s.tres" % version)


def godot_android_settings(home: str) -> dict:
    p = paths_of(home)
    return {
        "export/android/java_sdk_path": p["jdk"],
        "export/android/android_sdk_path": p["sdk"],
        "export/android/debug_keystore": p["keystore"],
        "export/android/debug_keystore_user": DEBUG_ALIAS,
        "export/android/debug_keystore_pass": DEBUG_PASS,
    }


def apply_settings_text(text: str, values: dict) -> str:
    """在编辑器设置文本里设定这几项 (已有的行替换, 没有的追加到 [resource] 段末尾); 其余原样保留"""
    if "[resource]" not in text:
        text = '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' + text
    for k, v in values.items():
        line = '%s = "%s"' % (k, v.replace("\\", "/"))
        pat = re.compile(r"^%s = .*$" % re.escape(k), re.M)
        if pat.search(text):
            text = pat.sub(lambda _m, line=line: line, text, count=1)
        else:
            text = text.rstrip("\n") + "\n" + line + "\n"
    return text


def configure_godot(home: str) -> str:
    path = godot_settings_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    old = open(path, encoding="utf-8").read() if os.path.isfile(path) else ""
    new = apply_settings_text(old, godot_android_settings(home))
    if new == old:
        return path + " (已是最新)"
    if old:
        shutil.copy2(path, "%s.bak-%s" % (path, time.strftime("%Y%m%d%H%M")))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(new)
    return path


# ---------------------------------------------------------------- 下载与安装

def download(url: str, dst: str) -> None:
    """直连下载, 支持断点续传 (先写 .part, 完成再改名); 进度每 10 秒打一行"""
    if os.path.isfile(dst) and os.path.getsize(dst) > 0:
        return
    part = dst + ".part"
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # 忽略代理环境变量
    for attempt in range(1, 6):
        have = os.path.getsize(part) if os.path.isfile(part) else 0
        # 带浏览器 UA: api.adoptium.net (Cloudflare) 对 Python-urllib 缺省 UA 直接回 403
        headers = {"User-Agent": "Mozilla/5.0 (tdj setup_android)"}
        if have:
            headers["Range"] = "bytes=%d-" % have
        req = urllib.request.Request(url, headers=headers)
        try:
            with opener.open(req, timeout=60) as r:
                if have and r.status != 206:   # 服务器不支持续传: 从头来
                    have = 0
                total = have + int(r.headers.get("Content-Length") or 0)
                last = time.time()
                with open(part, "ab" if have else "wb") as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
                        have += len(chunk)
                        if time.time() - last > 10:
                            print("  %s: %.0f / %.0f MB" % (os.path.basename(dst), have / 1048576, total / 1048576), flush=True)
                            last = time.time()
            os.replace(part, dst)
            return
        except Exception as e:  # noqa: BLE001
            print("  下载中断 (%s), 第 %d 次重试" % (e, attempt), flush=True)
            time.sleep(3)
    raise SystemExit("错误: 下载失败 " + url)


def extract(archive: str, dest: str, strip_top=False) -> None:
    os.makedirs(dest, exist_ok=True)
    if archive.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            z.extractall(dest)
            names = z.namelist()
        top = names[0].split("/")[0]
    else:
        with tarfile.open(archive) as t:
            t.extractall(dest)
            top = t.getnames()[0].split("/")[0]
    if strip_top:   # 压缩包里多一层顶层目录 (如 jdk-17.0.x+y/): 拿出来
        src = os.path.join(dest, top)
        for n in os.listdir(src):
            shutil.move(os.path.join(src, n), os.path.join(dest, n))
        os.rmdir(src)


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def install(home: str) -> None:
    p = paths_of(home)
    dl = os.path.join(home, "dl")
    if not os.path.exists(p["java"]):
        print("== JDK %d" % JDK_MAJOR)
        ext = ".zip" if platform.system() == "Windows" else ".tar.gz"
        arc = os.path.join(dl, "jdk%d%s" % (JDK_MAJOR, ext))
        download(jdk_url(), arc)
        shutil.rmtree(p["jdk"], ignore_errors=True)
        extract(arc, p["jdk"], strip_top=True)
    env = dict(os.environ, JAVA_HOME=p["jdk"])
    if not os.path.exists(p["sdkmanager"]):
        print("== Android 命令行工具")
        arc = os.path.join(dl, "cmdline-tools.zip")
        download(cmdline_tools_url(), arc)
        tmp = os.path.join(p["sdk"], "cmdline-tools")
        extract(arc, tmp)
        shutil.rmtree(os.path.join(tmp, "latest"), ignore_errors=True)
        os.replace(os.path.join(tmp, "cmdline-tools"), os.path.join(tmp, "latest"))
        if platform.system() != "Windows":
            for n in os.listdir(os.path.join(tmp, "latest", "bin")):
                os.chmod(os.path.join(tmp, "latest", "bin", n), 0o755)
    need = [n for key, n in (("adb", "platform-tools"), ("build_tools", "build-tools;" + SDK_VERSIONS["build_tools"]),
                             ("platform", "platforms;android-" + SDK_VERSIONS["platform"])) if not os.path.exists(p[key])]
    if need:
        print("== SDK 组件: " + ", ".join(need))
        run([p["sdkmanager"], "--sdk_root=" + p["sdk"], "--licenses"], input=("y\n" * 40).encode(), env=env, stdout=subprocess.DEVNULL)
        run([p["sdkmanager"], "--sdk_root=" + p["sdk"]] + need, env=env)
    if not os.path.exists(p["keystore"]):
        print("== 调试签名")
        run([p["keytool"], "-genkey", "-keystore", p["keystore"], "-storepass", DEBUG_PASS, "-alias", DEBUG_ALIAS, "-keypass", DEBUG_PASS,
             "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000", "-dname", "CN=Android Debug,O=Android,C=US"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--home", default=default_home(), help="安装目录 (缺省 <仓库>/tools/android 或 TDJ_ANDROID_HOME)")
    ap.add_argument("--check", action="store_true", help="只检查, 不下载不写文件")
    ap.add_argument("--no-godot-config", action="store_true", help="不改 Godot 编辑器设置")
    a = ap.parse_args()
    home = os.path.abspath(os.path.expanduser(a.home))
    if a.check:
        m = missing(home)
        if m:
            print("Android 构建环境不齐 (%s):" % home)
            for x in m:
                print("  缺: " + x)
            print("运行 python3 tools/platform/setup_android.py%s 安装" % ("" if home == default_home() else " --home " + home))
            return 1
        print("Android 构建环境齐全: " + home)
        return 0
    print("安装目录: " + home)
    install(home)
    if not a.no_godot_config:
        print("Godot 编辑器设置: " + configure_godot(home))
    m = missing(home)
    if m:
        print("仍缺: " + "; ".join(m))
        return 1
    print("完成。出包: python3 tools/platform/build_android.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""APK 对齐 + 签名 (zipalign + apksigner) 和自己的签名密钥库 (keytool)。给「整包」用: 往 APK 里加了资源包, 原来的签名就失效了,
必须用**自己的**密钥重新签名才能安装 (Android 只检查有没有签、签得对不对, 不检查是谁签的)。

工具从哪里找 (按顺序): --android-home / TDJ_ANDROID_HOME (tools/platform/setup_android.py 装的 JDK + SDK 最小集) → PATH 里的
apksigner / zipalign / keytool。没有就提示怎么装, 不会静默失败。
"""
import os
import secrets
import shutil
import string
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import setup_android as SA  # noqa: E402

DEFAULT_DIR = os.path.join(os.path.expanduser("~"), ".swordmanhd")
DEFAULT_ALIAS = "swordmanhd-bundle"


class SignError(Exception):
    pass


def find_tools(android_home: str = "") -> dict:
    """{"zipalign", "apksigner", "keytool", "java_home"}; 缺工具抛 SignError (带安装提示)"""
    home = os.path.abspath(os.path.expanduser(android_home or SA.default_home()))
    p = SA.paths_of(home)
    if os.path.isdir(p["build_tools"]) and os.path.isfile(p["keytool"]):
        return {"zipalign": os.path.join(p["build_tools"], SA.exe("zipalign")), "apksigner": os.path.join(p["build_tools"], SA.bat("apksigner")),
                "keytool": p["keytool"], "java_home": p["jdk"]}
    za, ap, kt = shutil.which("zipalign"), shutil.which("apksigner"), shutil.which("keytool")
    if za and ap and kt:
        return {"zipalign": za, "apksigner": ap, "keytool": kt, "java_home": os.environ.get("JAVA_HOME", "")}
    raise SignError("找不到签名工具 (zipalign / apksigner / keytool)。装一下: python3 tools/platform/setup_android.py  (一次性下载 JDK 17 + Android build-tools, 装到 %s), "
                    "或者自己装 JDK 17 和 Android build-tools 并加进 PATH" % home)


def ensure_keystore(keytool: str, path: str, alias: str, password: str, dname: str = "CN=SwordmanHD bundle, O=personal, C=CN") -> bool:
    """密钥库不存在就生成一把 (RSA 2048, 有效 100 年); 已存在不动。返回是不是刚生成的"""
    if os.path.isfile(path):
        return False
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    r = subprocess.run([keytool, "-genkeypair", "-keystore", path, "-storetype", "PKCS12", "-alias", alias, "-keyalg", "RSA", "-keysize", "2048",
                        "-validity", "36500", "-storepass", password, "-keypass", password, "-dname", dname], capture_output=True, text=True)
    if r.returncode != 0:
        raise SignError("生成密钥库失败: " + (r.stdout + r.stderr)[-500:])
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return True


def new_password() -> str:
    return "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(28))


def default_keystore() -> tuple:
    """缺省的个人整包密钥库 (~/.swordmanhd/bundle.keystore) 与它的密码 (同目录 bundle.keystore.pass, 第一次自动生成)。返回 (路径, 密码, 刚生成?)"""
    ks = os.path.join(DEFAULT_DIR, "bundle.keystore")
    pw_file = ks + ".pass"
    if os.path.isfile(ks) and os.path.isfile(pw_file):
        return ks, open(pw_file, encoding="utf-8").read().strip(), False
    return ks, "", True


def align_cmd(zipalign: str, src: str, dst: str) -> list:
    return [zipalign, "-f", "-p", "4", src, dst]


def sign_cmd(apksigner: str, ks: str, alias: str, password: str, src: str, dst: str) -> list:
    return [apksigner, "sign", "--ks", ks, "--ks-key-alias", alias, "--ks-pass", "pass:" + password, "--key-pass", "pass:" + password, "--out", dst, src]


def align_and_sign(tools: dict, src: str, dst: str, ks: str, alias: str, password: str) -> None:
    """src (已加好资源、去掉旧签名的 APK) → zipalign → 用 ks 签名 → dst。中间文件自动清理"""
    aligned = dst + ".aligned.tmp"
    try:
        r = subprocess.run(align_cmd(tools["zipalign"], src, aligned), capture_output=True, text=True)
        if r.returncode != 0:
            raise SignError("zipalign 失败: " + (r.stdout + r.stderr)[-500:])
        env = dict(os.environ)
        if tools.get("java_home"):
            env["JAVA_HOME"] = tools["java_home"]
            env["PATH"] = os.path.join(tools["java_home"], "bin") + os.pathsep + env.get("PATH", "")
        r = subprocess.run(sign_cmd(tools["apksigner"], ks, alias, password, aligned, dst), capture_output=True, text=True, env=env)
        if r.returncode != 0 or not os.path.isfile(dst):
            raise SignError("apksigner 签名失败: " + (r.stdout + r.stderr)[-500:])
    finally:
        for f in (aligned, dst + ".idsig"):
            if os.path.exists(f):
                os.remove(f)

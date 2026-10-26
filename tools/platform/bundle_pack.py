#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""整包 (自用): 把预制资源包 (pkgs/ 里的 resource/*.pck、mod/*.pck) 塞进 Android APK / iOS IPA 里, 装完就能玩, 不用再拷资源。
资源包是对原版的演绎, **整包只给自己用, 不要放到 Releases / 网盘 / 任何公开的地方** (公开发布的包仍然只含程序, 见 README 声明)。

  tools/platform/build_android.py --bundle [--edition hd|classic]     出 dist/android/SwordmanHD-bundled-<画质>.apk
  tools/platform/bundle_ipa.py <SwordmanHD-unsigned.ipa>              出 SwordmanHD-bundled-<画质>-unsigned.ipa (macOS 编出 IPA 后在任何系统上都能做)

预制资源包放在仓库根的 pkgs/ (整个目录被 .gitignore 忽略, 资源不入库): pkgs/resource/*.pck 与 pkgs/mod/*.pck, 就是
资源生成工具 打出来的那两个文件夹。--pkgs 可以指到别处。运行时怎么挂这些包见 game/engine/core/res_packs.gd (BUNDLE_DIR)。
本文件只做「选包 + 清单 + 往 zip 里加文件」, 不依赖 Godot / Android SDK, 有单元测试 (tools/tests/test_bundle_pack.py)。
"""
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _boot  # noqa: E402,F401
import paths  # noqa: E402

REPO = paths.REPO
PKGS = os.path.join(REPO, "pkgs")      # 预制资源包 (不入库)
BUNDLE_DIR = "bundled"                 # 与 game/engine/core/res_packs.gd 的 BUNDLE_DIR 一致
MANIFEST = "manifest.json"
COMMON = ["common_assets", "common_story"]
EDITIONS = {
    "hd": COMMON + ["hd_images", "hd_movies"],                 # 高清画质
    "classic": COMMON + ["classic_images", "classic_movies"],  # 原版画质 (体积小一半)
}


class BundleError(Exception):
    pass


def select(pkgs: str, edition: str, with_mod: bool = True) -> dict:
    """按画质挑出要塞进整包的资源包 -> {"resource": [包名...], "mod": [包名...]}; 缺必备包抛 BundleError"""
    if edition not in EDITIONS:
        raise BundleError("画质只能是 %s, 不是 %r" % ("/".join(EDITIONS), edition))
    res = EDITIONS[edition]
    miss = [n for n in res if not os.path.isfile(os.path.join(pkgs, "resource", n + ".pck"))]
    if miss:
        raise BundleError("预制资源包目录 %s 里缺: %s (放进 pkgs/resource/, 或用 --pkgs 指定目录)" % (pkgs, ", ".join(n + ".pck" for n in miss)))
    mods = []
    md = os.path.join(pkgs, "mod")
    if with_mod and os.path.isdir(md):
        mods = sorted(f[:-4] for f in os.listdir(md) if f.endswith(".pck"))
    return {"resource": list(res), "mod": mods}


def manifest_bytes(sel: dict) -> bytes:
    return (json.dumps({"resource": sel["resource"], "mod": sel["mod"]}, ensure_ascii=False, indent=1) + "\n").encode("utf-8")


def entries(pkgs: str, sel: dict, prefix: str) -> list:
    """要加进 zip 的条目 [(zip 内路径, 本地文件路径 | bytes)]: <prefix>/bundled/{manifest.json, resource/*.pck, mod/*.pck}"""
    base = prefix.rstrip("/") + "/" + BUNDLE_DIR
    out = [(base + "/" + MANIFEST, manifest_bytes(sel))]
    for n in sel["resource"]:
        out.append(("%s/resource/%s.pck" % (base, n), os.path.join(pkgs, "resource", n + ".pck")))
    for n in sel["mod"]:
        out.append(("%s/mod/%s.pck" % (base, n), os.path.join(pkgs, "mod", n + ".pck")))
    return out


def inject(src: str, dst: str, add: list, drop_prefixes=()) -> None:
    """把 add 的条目加进 src 这个 zip (APK / IPA), 存成 dst。原有条目原样搬 (保持压缩方式), drop_prefixes 开头的丢掉 (如 META-INF/ 旧签名);
    资源包不压缩 (STORED: 本来就是压过的, 不压缩运行时才能随机读、原地挂载)。已经有同名条目 = 报错 (不能静默覆盖)。"""
    names = set()
    with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst, "w", allowZip64=True) as zo:
        for info in zi.infolist():
            if any(info.filename.startswith(p) for p in drop_prefixes):
                continue
            names.add(info.filename)
            zo.writestr(info, zi.read(info), compress_type=info.compress_type)
        for arc, data in add:
            if arc in names:
                raise BundleError("%s 里已经有 %s" % (os.path.basename(src), arc))
            names.add(arc)
            if isinstance(data, bytes):
                zo.writestr(zipfile.ZipInfo(arc, (2026, 1, 1, 0, 0, 0)), data, compress_type=zipfile.ZIP_STORED)
            else:
                zo.write(data, arc, compress_type=zipfile.ZIP_STORED)


def app_prefix(ipa: str) -> str:
    """IPA 里 Payload/<名>.app 的路径 (没有返回 BundleError)"""
    with zipfile.ZipFile(ipa) as z:
        for n in z.namelist():
            parts = n.split("/")
            if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app"):
                return "Payload/" + parts[1]
    raise BundleError("%s 里没有 Payload/*.app, 不是 IPA?" % ipa)


def human(n: float) -> str:
    return "%.2f GB" % (n / 1073741824) if n >= 1073741824 else "%.0f MB" % (n / 1048576)

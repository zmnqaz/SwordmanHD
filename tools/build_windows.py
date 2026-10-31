#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""导出 Windows 版并组装 dist/windows/SwordmanHD/ (跨平台实现, 说明见 docs/打包/Windows.md; build_windows.sh 是本文件的薄封装)。
  python tools/build_windows.py              导出 exe+pck, 带 dist/packs/ 里的资源包; 像素画类运行时在 GPU 上生成 (engine/render/hq)
  python tools/build_windows.py --zip        另打 dist/windows/SwordmanHD-win64.7z (需要 7z/7za/7zz; 没有则退回 .zip)
  python tools/build_windows.py --mac        导出 macOS universal 版到 dist/macos/SwordmanHD/ (未签名的 .app, 可在 Linux/Windows 上出; --zip 打 .zip)
  python tools/build_windows.py --linux      导出 Linux x86_64 版到 dist/linux/SwordmanHD/ (同一套资源组装与必带清单; --zip 打 tar.xz)
  python tools/build_windows.py --zip --split=2g   打分卷 (SwordmanHD-win64.7z.001 ..., 仅 7z)
  python tools/build_windows.py --packs-from=DIR   不重新生成资源包, 直接用 DIR 里现成的 resource/*.pck 与 mod/*.pck (不需要原版)
  python tools/build_windows.py --engine-only      只出引擎 (exe + 手写内容 + 许可), 不打资源包、不需要原版: 公开 CI 出安装包用;
                                                   玩家把自己生成的 resource/ 文件夹 (必要时加 mod/) 放到 exe 旁 (docs/打包/资源包.md)
需要: Godot 4.7.2 (tools/paths.py 解析, Windows 用 *_console.exe) 与同版本 export templates:
  Linux  ~/.local/share/godot/export_templates/<版本>/    macOS  ~/Library/Application Support/Godot/export_templates/<版本>/    Windows  %APPDATA%\\Godot\\export_templates\\<版本>\\
资源打成 exe 旁 resource/ (必备) 与 mod/ (可选) 两个文件夹里的 .pck (资源生成工具), 主 pck 嵌在 exe 里。
  --edition=hd|classic|all  发布哪种画质 (缺省 all): hd 不带 classic_images/classic_movies (体积小), classic 不带 hd_images/hd_movies
资源包由 资源生成工具 从玩家自己的原版游戏生成, 放进 dist/packs/ (resource/ 与 mod/), 本脚本把它们放到发布目录里。
"""
import json
import contextlib
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths  # noqa: E402

REPO = paths.REPO
PACKS = os.path.join(REPO, "dist", "packs")  # 唯一一份资源包 (resource/*.pck + mod/*.pck + BUILD.json)
OUT = os.path.join(REPO, "dist", "windows", "SwordmanHD")  # --linux 时改为 dist/linux/SwordmanHD (main 里按平台设)

def pack_lists_from_dir(d):
    """现成的资源包目录 -> {相对路径: []} (只收集 resource/ 与 mod/ 下的 .pck, 不看里面的内容)"""
    found = {}
    for sub_dir in ("resource", "mod"):
        folder = os.path.join(d, sub_dir)
        for fn in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
            if fn.endswith(".pck"):
                found[sub_dir + "/" + fn] = []
    if "resource/common_assets.pck" not in found:
        die("%s 里没有资源包 (resource/common_assets.pck 等): 放进去, 或用 --packs-from 指到现成的资源包目录, 或加 --engine-only 只出引擎" % d)
    return found


FREE_NOTICE = """SwordmanHD is free (GPL-3.0) and is an unofficial fan-made reimplementation.
If you paid for it (purchase, paid download, paid installation ...), please report the seller and ask for a refund.
本游戏免费，采用 GPL-3.0 协议，属于同人复刻；如有收费获得，请举报退款。

"""

NOTE = """SwordmanHD (Windows)

Run SwordmanHD.exe (SwordmanHD.console.exe shows the log). Keep the whole folder together: the resource packs next to the
executable (the resource folder, and the optional mod folder) are read at run time and must not be deleted.
Saves and settings: %APPDATA%\\SwordmanHD\\
If the picture is broken or the game does not start, run from a command line: SwordmanHD.exe --rendering-driver opengl3_angle
Licenses: see the licenses folder (LICENSE.txt, NOTICE.md and third-party license texts).
"""

NOTE_ENGINE = """

This package contains only the engine and hand-written content, not the original game's assets.
Generate the resource packs (the resource folder: common_assets.pck, common_story.pck, plus hd_images.pck + hd_movies.pck or classic_images.pck + classic_movies.pck)
from your own legally obtained copy of the original game (see docs/打包/资源包.md in the source repository) and put them next to the executable.
Optional mods (e.g. face_hk.pck) go into a mod folder next to it. The game shows a message
on screen if packs are missing.
"""

PLACEHOLDER_RESOURCE = """把资源包 (.pck) 放在这个文件夹里: common_assets.pck, common_story.pck,
再加 hd_images.pck + hd_movies.pck (高清画质) 或 classic_images.pck + classic_movies.pck (原版画质)。
资源包要用你自己的原版游戏生成, 本软件不含任何原版资源。

Put the resource packs (.pck) in this folder. Generate them from your own copy of the original game.
"""

PLACEHOLDER_MOD = """可选: mod 资源包 (如 face_hk.pck 港漫头像) 放在这个文件夹里; 不放也能正常游玩。

Optional: put mod packs (e.g. face_hk.pck) here.
"""

NOTE_MAC = """SwordmanHD (macOS, universal: Apple silicon + Intel)

Put SwordmanHD.app, the resource folder and the optional mod folder in the same folder (do not put the packs inside the .app).
This app is not signed or notarized. On first launch macOS will refuse to open it; run this once in Terminal, then open it normally:
    xattr -dr com.apple.quarantine SwordmanHD.app && codesign --force --deep -s - SwordmanHD.app
(the second command gives it an ad-hoc signature, required on Apple silicon). Or right-click the app -> Open.
Saves and settings: ~/Library/Application Support/Godot/app_userdata/SwordmanHD/
Licenses: see the licenses folder (LICENSE.txt, NOTICE.md and third-party license texts).
"""

NOTE_LINUX = """SwordmanHD (Linux)

Run ./SwordmanHD.x86_64 (run it from a terminal to see the log). Keep the whole folder together: the resource packs next to the
executable (the resource folder, and the optional mod folder) are read at run time and must not be deleted. An OpenGL 3.3 driver is required.
Saves and settings: ~/.local/share/SwordmanHD/
Native Wayland (sharper on hiDPI): ./SwordmanHD.x86_64 --display-driver wayland
Licenses: see the licenses folder (LICENSE.txt, NOTICE.md and third-party license texts).
"""

# 平台: 导出预设名 (game/export_presets.cfg)、可执行文件、必带的平台文件、压缩包名
PLATFORMS = {
    "windows": {"preset": "Windows Desktop", "exe": "SwordmanHD.exe", "extra": ["SwordmanHD.console.exe"], "note": NOTE,
                "arc": "SwordmanHD-win64"},
    "linux": {"preset": "Linux", "exe": "SwordmanHD.x86_64", "extra": [], "note": NOTE_LINUX, "arc": "SwordmanHD-linux-x86_64"},
    # macOS: 导出出来是 SwordmanHD.zip (里面一个 .app), 解开放在 OUT 里; 资源包放 .app 旁边 (见 game/engine/core/res_packs.gd mac_pack_dir)
    "macos": {"preset": "macOS", "exe": "SwordmanHD.app", "extra": [], "note": NOTE_MAC, "arc": "SwordmanHD-macos"},
}


# 发布版本: 画质 hd / classic 二选一的包按版本取舍 (all = 都带)
EDITIONS = {"all": (), "hd": ("classic_images", "classic_movies"), "classic": ("hd_images", "hd_movies")}


def die(msg):
    print("错误: " + msg, file=sys.stderr)
    sys.exit(1)


def find_7z():
    env = os.environ.get("TDJ_7Z")  # 便携: 显式指定 7z 可执行文件
    if env and os.path.isfile(env):
        return env
    for n in ("7z", "7za", "7zz", "7zr"):
        p = shutil.which(n)
        if p:
            return p
    # 便携: 随仓库带的 7zr (tools/7z/, 见 docs/Windows开发.md); 再退到标准安装位置
    for p in (os.path.join(HERE, "7z", "7zr.exe"), os.path.join(HERE, "7z", "7z.exe"),
              os.path.join(HERE, "7z", "7zz"), os.path.join(HERE, "7z", "7z"), os.path.join(HERE, "7z", "7za"),
              r"C:\Program Files\7-Zip\7z.exe", r"C:\Program Files (x86)\7-Zip\7z.exe"):
        if os.path.isfile(p):
            return p
    return None


def templates_dir(ver):
    if os.name == "nt":
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        return os.path.join(base, "Godot", "export_templates", ver)
    if sys.platform == "darwin":
        return os.path.join(os.path.expanduser("~/Library/Application Support"), "Godot", "export_templates", ver)
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "godot", "export_templates", ver)


@contextlib.contextmanager
def custom_template(plat, preset):
    """有自制模板 (.work/templates/, tools/platform/build_template_windows.sh 编出来) 就临时写进导出预设的 custom_template/release,
    导出完恢复预设文件。官方 release 模板不带图片压缩器, 导出版里 BC7 压缩用不了; 自制模板开了 cvtt_export_templates。"""
    tname = {"windows": "windows_release_x86_64.exe", "linux": "linux_release.x86_64"}.get(plat)
    tpl = os.path.join(REPO, ".work", "templates", tname or "-")
    cfg = os.path.join(REPO, "game", "export_presets.cfg")
    if not os.path.isfile(tpl):
        yield
        return
    with open(cfg, encoding="utf-8", newline="") as f:
        orig = f.read()
    head, sep, rest = orig.partition('name="%s"' % preset)
    new_rest = rest.replace('custom_template/release=""', 'custom_template/release="%s"' % tpl.replace("\\", "/"), 1)
    new_rest = new_rest.replace('custom_features=""', 'custom_features="tex_compress"', 1)   # 游戏据此知道这个包的引擎能压缩 (TexCodec.runtime_compress_available)
    if not sep or new_rest == rest:
        yield
        return
    print("== 用自制模板 (带图片压缩器): " + tpl)
    with open(cfg, "w", encoding="utf-8", newline="") as f:
        f.write(head + sep + new_rest)
    try:
        yield
    finally:
        with open(cfg, "w", encoding="utf-8", newline="") as f:
            f.write(orig)


def main(argv):
    global OUT
    zip_, split, plat, engine_only, edition, packs_from = False, "", "windows", False, "all", ""
    for a in argv:
        if a == "--no-hd6x":  # 旧参数: 现在包里本来就不带 hd6x
            pass
        elif a == "--engine-only":
            engine_only = True
        elif a.startswith("--packs-from="):
            packs_from = os.path.abspath(os.path.expanduser(a[len("--packs-from="):]))
            if not os.path.isdir(packs_from):
                die("--packs-from 目录不存在: " + packs_from)
        elif a.startswith("--edition="):
            edition = a[len("--edition="):]
            if edition not in EDITIONS:
                die("--edition 只能是 " + "|".join(EDITIONS))
        elif a == "--linux":
            plat = "linux"
        elif a == "--mac":
            plat = "macos"
        elif a == "--zip":
            zip_ = True
        elif a.startswith("--split="):
            zip_, split = True, a[len("--split="):]
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            die("未知参数: " + a)
    pf = PLATFORMS[plat]
    OUT = os.path.join(REPO, "dist", plat, "SwordmanHD")
    godot = paths.godot_exe()
    if not os.path.isfile(godot):
        die(paths.missing_godot_hint())
    import re
    out = subprocess.run([godot, "--version"], capture_output=True, text=True).stdout.strip()
    m = re.match(r"^([0-9.]+)\.([a-z]+[0-9]*)\..*", out)
    ver = "%s.%s" % m.groups() if m else out
    td = templates_dir(ver)
    if not os.path.isdir(td):
        die("缺少 export templates: %s" % td)

    # 图标: 用自制的桌面图标 game/assets/icon_pc.png (tools/platform/make_app_icon.py --plain 生成); icon.ico 不入库, 导出预设引用 res://assets/icon.ico,
    # 缺了 Godot 导出直接报「图标路径无效」。
    ico = os.path.join(REPO, "game", "assets", "icon.ico")
    if not os.path.isfile(ico):
        subprocess.run([sys.executable, os.path.join(HERE, "platform", "make_ico.py"), os.path.join(REPO, "game", "assets", "icon_pc.png"), ico], check=True)

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    print("== 导出 %s + pck (%s)" % (pf["exe"], ver))
    target = os.path.join(OUT, "SwordmanHD.zip" if plat == "macos" else pf["exe"])   # macOS 只能导出成 zip/dmg, 里面是 .app
    with custom_template(plat, pf["preset"]):
        r = subprocess.run([godot, "--headless", "--path", os.path.join(REPO, "game").replace("\\", "/"), "--export-release", pf["preset"],
                            target], capture_output=True, text=True, encoding="utf-8", errors="replace", env=paths.env_for_godot())
    for line in (r.stdout + r.stderr).splitlines():
        if line.strip() and "savepack" not in line and not re.match(r"^\[ *\d+% \]", line):
            print(line)
    if plat == "macos" and r.returncode == 0 and os.path.isfile(target):
        subprocess.run(["unzip", "-q", target, "-d", OUT], check=True)   # unzip 保留可执行权限 (python zipfile 不保留)
        os.remove(target)
    if r.returncode != 0 or not os.path.exists(os.path.join(OUT, pf["exe"])):  # 以前只看文件在不在, Godot 报错退出但留下半个文件时会悄悄通过
        die("导出失败 (Godot 退出码 %d, 上面是它的输出)" % r.returncode)

    if engine_only:
        lists = {}
        print("== 只出引擎 (--engine-only): 不打资源包")
    else:
        print("== 打资源包")
        # 资源包 (resource/ + mod/ 下的 .pck) 由 资源生成工具 从玩家自己的原版生成, 放进 dist/packs/; 本脚本只把它们放到 exe 旁, 启动时 ResPacks 挂载。
        # 主 pck (脚本/字体/着色器/手写内容包 content/remake) 嵌在 exe 里 (导出预设 embed_pck, 不含生成的 content/tdj)。仓库根 data/ 运行时不读, 不带。
        # 资源包全平台只打一份放 dist/packs/ (Android 推手机、iOS 拷进应用也从这里取), 平台目录里用硬链接 (不能硬链接时才复制), 不占第二份磁盘
        if packs_from:
            print("== 用现成资源包: %s" % packs_from)
            lists, src_root = pack_lists_from_dir(packs_from), packs_from
        else:
            lists, src_root = pack_lists_from_dir(PACKS), PACKS
        skip = {"resource/%s.pck" % n for n in EDITIONS[edition]}
        lists = {k: v for k, v in lists.items() if k not in skip}
        for dp, dns, fns in os.walk(src_root):
            if dp == src_root:
                dns[:] = [d for d in dns if d in ("resource", "mod")]   # 现成包目录里可能还有说明、校验和、脚本, 只取资源包
            for fn in fns:
                src = os.path.join(dp, fn)
                rel = os.path.relpath(src, src_root).replace(os.sep, "/")
                if rel in skip or not (fn.endswith(".pck") or rel == "BUILD.json"):
                    continue
                dst = os.path.join(OUT, *rel.split("/"))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                try:
                    os.link(src, dst)
                except OSError:
                    shutil.copy2(src, dst)
        if edition == "hd" and "resource/hd_images.pck" not in lists:
            die("--edition=hd 需要 hd_images.pck (没有 AI 高清产物)")
    # resource/ 与 mod/ 一定要在包里 (没有资源包时是空的, zip/7z 会丢空目录, 所以各放一个说明文件), 玩家把资源包放进去即可
    for d, txt in (("resource", PLACEHOLDER_RESOURCE), ("mod", PLACEHOLDER_MOD)):
        dd = os.path.join(OUT, d)
        os.makedirs(dd, exist_ok=True)
        if not any(fn.endswith(".pck") for fn in os.listdir(dd)):
            with open(os.path.join(dd, "放资源包到这里.txt"), "w", encoding="utf-8", newline="\n") as f:
                f.write(txt)
    # 第三方许可放包外, 方便查看: 字体 (OFL 等, 字体本身在主 pck) 与运行时放大着色器 (hqx LGPL-2.1+、xBRZ GPL-3.0)
    hq = os.path.join(REPO, "game", "engine", "render", "hq")
    os.makedirs(os.path.join(OUT, "licenses"), exist_ok=True)
    for lic in ("LICENSE-GPL-3.0.txt", "LICENSE-LGPL-2.1.txt"):
        shutil.copy2(os.path.join(hq, lic), os.path.join(OUT, "licenses", lic))
    # 本项目许可 (GPL-3.0-only) 与第三方汇总; 引擎许可从打包用的同一个 Godot 导出 (Engine.get_license_text 等)
    shutil.copy2(os.path.join(REPO, "LICENSE"), os.path.join(OUT, "licenses", "LICENSE.txt"))
    shutil.copy2(os.path.join(REPO, "NOTICE.md"), os.path.join(OUT, "licenses", "NOTICE.md"))
    r = subprocess.run([godot, "--headless", "-s", os.path.join(HERE, "release", "godot_licenses.gd"), "--",
                        os.path.join(OUT, "licenses")], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        sys.exit("错误: 导出 Godot 许可文本失败:\n" + r.stdout[-2000:] + r.stderr[-2000:])
    with open(os.path.join(REPO, "game", "content", "remake", "ui_theme", "fonts.json"), encoding="utf-8") as f:
        fonts = json.load(f)
    for ft in fonts.get("fonts", []):
        if ft.get("license_file"):
            lf = os.path.join(REPO, "game", ft["license_file"].replace("res://", ""))
            shutil.copy2(lf, os.path.join(OUT, "licenses", os.path.basename(lf)))
    with open(os.path.join(OUT, "README.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(FREE_NOTICE + pf["note"] + (NOTE_ENGINE if engine_only else ""))

    # 必带清单校验: 包外文件 + 各资源包里运行时直接读的关键文件, 漏带时在这里报错, 而不是玩到才发现
    need = [pf["exe"]] + pf["extra"] + list(lists) + ["README.txt", "licenses/LICENSE-GPL-3.0.txt", "licenses/LICENSE-LGPL-2.1.txt",
            "licenses/LICENSE.txt", "licenses/NOTICE.md", "licenses/Godot-LICENSE.txt", "licenses/Godot-COPYRIGHT.txt"]
    miss = [x for x in need if not os.path.exists(os.path.join(OUT, x))]
    if miss:
        die("包内缺少: " + ", ".join(miss))
    print("必带清单校验通过 (%d 项)" % (len(need) + 1))

    print("== 体积")
    total = 0
    for name in sorted(os.listdir(OUT)):
        p = os.path.join(OUT, name)
        size = os.path.getsize(p) if os.path.isfile(p) else sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(p) for fn in fns)
        total += size
        print("  %8.1f MB  %s" % (size / 1048576, name))
    print("  %8.1f MB  合计" % (total / 1048576))

    if zip_ and plat == "linux":  # tar 保留可执行权限 (zip 不保证)
        base = os.path.join(REPO, "dist", plat)
        arc = os.path.join(base, pf["arc"] + ".tar.xz")
        subprocess.run(["tar", "-cJf", arc, "-C", base, "SwordmanHD"], check=True, env=dict(os.environ, XZ_OPT="-1 -T0"))
        print("%s  %.0f MB" % (arc, os.path.getsize(arc) / 1048576))
    elif zip_ and plat == "macos":  # zip -y 保留符号链接与可执行权限
        base = os.path.join(REPO, "dist", plat)
        arc = os.path.join(base, pf["arc"] + ".zip")
        if os.path.exists(arc):
            os.remove(arc)
        subprocess.run(["zip", "-qry", arc, "SwordmanHD"], cwd=base, check=True)
        print("%s  %.0f MB" % (arc, os.path.getsize(arc) / 1048576))
    elif zip_:
        base = os.path.join(REPO, "dist", "windows")
        sz = find_7z()
        if sz:
            arc = os.path.join(base, "SwordmanHD-win64.7z")
            for fn in os.listdir(base):
                if fn.startswith("SwordmanHD-win64.7z"):
                    os.remove(os.path.join(base, fn))
            # 贴图已是 WebP/PNG, 再压缩收益很小, 用最快档
            subprocess.run([sz, "a", "-mx=1"] + (["-v" + split] if split else []) + [arc, "SwordmanHD"], cwd=base, stdout=subprocess.DEVNULL, check=True)
            for fn in sorted(os.listdir(base)):
                if fn.startswith("SwordmanHD-win64.7z"):
                    print("%s  %.0f MB" % (os.path.join(base, fn), os.path.getsize(os.path.join(base, fn)) / 1048576))
        else:
            if split:
                die("没有 7z, 无法分卷")
            print("没有找到 7z, 改打 zip")
            arc = shutil.make_archive(os.path.join(base, "SwordmanHD-win64"), "zip", base, "SwordmanHD")
            print("%s  %.0f MB" % (arc, os.path.getsize(arc) / 1048576))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except subprocess.CalledProcessError as e:  # tar / 7z / make_icon 失败: 给一行说明与非 0 退出码, 不甩 Python 回溯
        print("命令失败 (退出码 %d): %s" % (e.returncode, " ".join(str(c) for c in e.cmd[:3])), file=sys.stderr)
        sys.exit(e.returncode or 1)

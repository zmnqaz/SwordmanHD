#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""运行复刻版 (Godot 4) 的跨平台入口, 与 tools/run_game.sh 等价 (run_game.sh 现为调用本文件的薄封装)。
  python tools/run_game.py                          正常游玩
  python tools/run_game.py --fixed-fps 25 -- --skip-movies --shot=30:out.png --quit=31   自动测试 (见 game/scripts/autotest.gd)
  python tools/run_game.py --wayland [...]          仅 Linux: 原生 Wayland (须为第一个参数), hiDPI 下自动用 6 倍贴图
所有参数原样交给 Godot (Godot 自己的参数在 -- 前, 游戏参数在 -- 后)。Godot 路径、原版位置见 tools/paths.py
(环境变量 TDJ_GODOT / TDJ_ORIGINAL / TDJ_HD6X 或 tools/dev_env.json)。Linux 上自动用本机桌面的 Xwayland (:0)。
Windows 想看日志用 Godot 的 *_console.exe。未在 Windows 实机验证。
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths  # noqa: E402
import xauth  # noqa: E402


def main(argv):
    godot = paths.godot_exe()
    if not os.path.isfile(godot):
        print(paths.missing_godot_hint(), file=sys.stderr)
        return 2
    if not paths.has_original():
        print("警告: " + paths.missing_original_hint(), file=sys.stderr)
    paths.ensure_godot_imported(godot)
    env = paths.env_for_godot()
    game = os.path.join(paths.REPO, "game").replace("\\", "/")
    args = list(argv)
    if os.name != "nt":
        if args[:1] == ["--wayland"]:
            args = args[1:]
            uid = os.getuid()
            env.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % uid)
            env.setdefault("WAYLAND_DISPLAY", "wayland-0")
            cmd = [godot, "--display-driver", "wayland", "--path", game] + args
            return subprocess.call(cmd, env=env)
        xa = xauth.xauthority()
        if xa and os.path.exists("/tmp/.X11-unix/X0"):
            env["DISPLAY"] = ":0"
            env["XAUTHORITY"] = xa
    elif args[:1] == ["--wayland"]:
        print("--wayland 只在 Linux 上有意义", file=sys.stderr)
        return 2
    return subprocess.call([godot, "--path", game] + args, env=env)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 运行复刻版 (Godot 4): 薄封装, 实际逻辑在 tools/run_game.py (跨平台)。默认用本机桌面的 Xwayland (:0, 硬件加速, 不依赖 SSH 转发)。
#   tools/run_game.sh                          正常游玩
#   tools/run_game.sh --wayland [...]          原生 Wayland (可选, 须为第一个参数): 避开 Xwayland 的 2 倍再缩小,
#                                              hiDPI 下窗口约 1908x1193 物理像素, 自动用 6 倍贴图 (见 docs/分辨率增强.md)
#   tools/run_game.sh --fixed-fps 25 -- --skip-movies --shot=30:/tmp/a.png --quit=31   自动测试 (见 game/scripts/autotest.gd)
PY=$(command -v python3 || command -v python) || { echo "找不到 python3" >&2; exit 2; }
exec "$PY" "$(dirname "$0")/run_game.py" "$@"

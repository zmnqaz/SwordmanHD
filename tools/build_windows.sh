#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 导出 Windows 版并组装 dist/windows/SwordmanHD/: 薄封装, 实际逻辑在 tools/build_windows.py (跨平台, 说明见该文件与 docs/打包/Windows.md)。
#   tools/build_windows.sh              导出 exe+pck, 带原图 + hd4x (AI 类); 像素画类运行时生成
#   tools/build_windows.sh --zip [--split=2g]   另打 7z (分卷)
PY=$(command -v python3 || command -v python) || { echo "找不到 python3" >&2; exit 2; }
exec "$PY" "$(dirname "$0")/build_windows.py" "$@"

#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 本地与 CI 共用的唯一检查入口: 薄封装, 实际逻辑在 tools/ci.py (跨平台, 说明见该文件头)。
#   tools/ci.sh fast      Godot --import + 无头测试 + content_schema + check_ui_text + layout_stats + 文档检查 + tools/tests/ Python 测试
#   tools/ci.sh full      fast + 慢测试组
# 环境变量: CI_LOG_DIR (日志目录, 默认 <仓库>/.work/ci)、CI_GODOT / TDJ_GODOT (Godot 4.7.2 可执行文件)。
# 退出码: 0 全部通过 (允许有 SKIP), 1 有失败, 2 用法或环境错误 (缺 Godot 等)。
PY=$(command -v python3 || command -v python) || { echo "找不到 python3" >&2; exit 2; }
exec "$PY" "$(dirname "$0")/ci.py" "$@"

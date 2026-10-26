#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 安装固定版本 Godot 4.7.2 (标准版, Linux x86_64) 到 tools/godot/godot, 供 CI runner 使用; 已装且版本对就什么也不做。
#   GODOT_URL       覆盖下载地址 (内网镜像); 默认官方 GitHub release
#   GODOT_CACHE_DIR 下载缓存目录 (默认 ~/.cache/tdj-godot); CI 里把这个目录配成缓存, 就不用每次重下 (约 70MB zip)
#   GODOT_TEMPLATES 设为 1 时另装同版本导出模板 (官方 .tpz 约 1GB) 到 ~/.local/share/godot/export_templates/<版本>.stable/,
#                   出安装包 (build_windows / build_android) 要用; 只跑测试不需要
# 注意: 本脚本与下载地址未在真实 runner 验证 (见 docs/「已知未验证项」)。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="4.7.2"
URL="${GODOT_URL:-https://github.com/godotengine/godot/releases/download/${VER}-stable/Godot_v${VER}-stable_linux.x86_64.zip}"
CACHE="${GODOT_CACHE_DIR:-$HOME/.cache/tdj-godot}"
DEST="$ROOT/tools/godot/godot"
mkdir -p "$CACHE" "$ROOT/tools/godot"
if [ -x "$DEST" ] && "$DEST" --version 2>/dev/null | grep -q "^$VER\."; then
  echo "Godot $VER 已就绪: $DEST"
else
  ZIP="$CACHE/Godot_v${VER}-stable_linux.x86_64.zip"
  [ -s "$ZIP" ] || { curl -fL --retry 3 -o "$ZIP.part" "$URL" && mv "$ZIP.part" "$ZIP"; }  # 下完再改名: 中断不留残缺 zip 被下次复用
  python3 - "$ZIP" "$DEST" <<'PY'
import shutil, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
name = next(n for n in z.namelist() if n.endswith("linux.x86_64") and not n.endswith("/"))
with z.open(name) as src, open(sys.argv[2], "wb") as dst:
    shutil.copyfileobj(src, dst)
PY
  chmod +x "$DEST"
  "$DEST" --version
fi
if [ "${GODOT_TEMPLATES:-0}" = "1" ]; then
  TD="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${VER}.stable"
  if [ -f "$TD/version.txt" ]; then echo "导出模板已就绪: $TD"; exit 0; fi
  TPZ="$CACHE/Godot_v${VER}-stable_export_templates.tpz"
  TURL="${GODOT_TEMPLATES_URL:-https://github.com/godotengine/godot/releases/download/${VER}-stable/Godot_v${VER}-stable_export_templates.tpz}"
  [ -s "$TPZ" ] || { curl -fL --retry 3 -o "$TPZ.part" "$TURL" && mv "$TPZ.part" "$TPZ"; }
  mkdir -p "$TD"
  python3 - "$TPZ" "$TD" <<'PY'
import os, shutil, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
for n in z.namelist():   # .tpz 里是 templates/<文件>
    if n.endswith("/") or not n.startswith("templates/"):
        continue
    with z.open(n) as src, open(os.path.join(sys.argv[2], n[len("templates/"):]), "wb") as dst:
        shutil.copyfileobj(src, dst)
PY
  echo "导出模板: $TD"
fi

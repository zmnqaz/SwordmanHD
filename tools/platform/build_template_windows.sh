#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# 自制 Windows 导出模板: 官方 release 模板不带图片压缩器 (Image.compress 报 _image_compress_bptc_func is null),
# 贴图 BC7 压缩 (游戏 engine/render/hq/tex_codec.gd) 在导出版里用不了。Godot 有官方开关 cvtt_export_templates=yes, 重编一份就行 (不改引擎源码)。
# 用法: tools/platform/build_template_windows.sh      产出 .work/templates/windows_release_x86_64.exe (+ .console.exe), tools/build_windows.py 自动使用
# 前提: python3 / scons / curl / xz; 联网下载 Godot 源码 (约 70MB) 与 llvm-mingw (约 150MB, 官方 Windows 构建同款工具链)。首次编译约 15~25 分钟 (14 核)。
set -e
VER=4.7.2-stable
LLVM=20261006
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$ROOT/.work/godot-src"
OUT="$ROOT/.work/templates"
mkdir -p "$W" "$OUT"
cd "$W"
[ -d "godot-$VER" ] || { curl -fL -o godot.tgz "https://codeload.github.com/godotengine/godot/tar.gz/refs/tags/$VER" && tar xzf godot.tgz; }
TC=$(ls -d "$W"/llvm-mingw-* 2>/dev/null | head -1)
if [ -z "$TC" ]; then
  curl -fL -o llvm-mingw.tar.xz "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM/llvm-mingw-$LLVM-ucrt-ubuntu-22.04-x86_64.tar.xz"
  tar xJf llvm-mingw.tar.xz
  TC=$(ls -d "$W"/llvm-mingw-* | head -1)
fi
cd "godot-$VER"
# d3d12 / accesskit / ANGLE 不带 (游戏用 gl_compatibility, 这几项要另下依赖); 不开 LTO 省内存与时间
scons platform=windows target=template_release arch=x86_64 use_mingw=yes use_llvm=yes mingw_prefix="$TC" \
  cvtt_export_templates=yes d3d12=no accesskit=no optimize=speed lto=none debug_symbols=no -j"$(nproc)"
cp bin/godot.windows.template_release.x86_64.llvm.exe "$OUT/windows_release_x86_64.exe"
cp bin/godot.windows.template_release.x86_64.llvm.console.exe "$OUT/windows_release_x86_64.console.exe" 2>/dev/null || true
ls -la "$OUT"

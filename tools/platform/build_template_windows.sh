#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# 自制 Windows 导出模板: 官方 release 模板不带图片压缩器 (Image.compress 报 _image_compress_bptc_func is null),
# 贴图 BC7 压缩 (游戏 engine/render/hq/tex_codec.gd) 在导出版里用不了。Godot 有官方开关 cvtt_export_templates=yes, 重编一份就行 (不改引擎源码)。
# 用法: tools/platform/build_template_windows.sh      产出 .work/templates/windows_release_x86_64.exe (+ .console.exe), tools/build_windows.py 自动使用
# 前提: python3 / scons / curl / xz; 联网下载 Godot 源码 (约 70MB) 与 llvm-mingw (约 150MB, 官方 Windows 构建同款工具链)。首次编译约 15~25 分钟 (14 核)。
set -e
VER=4.7.2-stable
LLVM=20261006
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
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
# ANGLE (OpenGL 跑在 D3D11 上): 官方模板带, 驱动不支持 OpenGL 3.3 / 在 Godot 的 ANGLE 名单里的老显卡靠它启动, 自制模板也要带。
# 只下 x86_64-llvm 一份 (misc/scripts/install_angle.py 会下 5 份), 版本取该脚本里写的
ANGLE_DIR=bin/build_deps/angle-x86_64-llvm
if [ ! -d "$ANGLE_DIR" ]; then
  AV=$(sed -n 's/^angle_version = "\(.*\)"/\1/p' misc/scripts/install_angle.py)
  mkdir -p bin/build_deps
  curl -fL -o bin/build_deps/angle.zip "https://github.com/godotengine/godot-angle-static/releases/download/$AV/godot-angle-static-x86_64-llvm-release.zip"
  python3 -c "import shutil,sys; shutil.unpack_archive(sys.argv[1], sys.argv[2])" bin/build_deps/angle.zip "$ANGLE_DIR"
  rm bin/build_deps/angle.zip
fi
# d3d12 / accesskit 不带 (游戏用 gl_compatibility, 这两项要另下依赖); 不开 LTO 省内存与时间
scons platform=windows target=template_release arch=x86_64 use_mingw=yes use_llvm=yes mingw_prefix="$TC" \
  cvtt_export_templates=yes angle=yes angle_libs="$PWD/bin/build_deps/angle" d3d12=no accesskit=no optimize=speed lto=none debug_symbols=no -j"$(nproc)"
cp bin/godot.windows.template_release.x86_64.llvm.exe "$OUT/windows_release_x86_64.exe"
cp bin/godot.windows.template_release.x86_64.llvm.console.exe "$OUT/windows_release_x86_64.console.exe" 2>/dev/null || true
ls -la "$OUT"

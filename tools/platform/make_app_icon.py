#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""生成应用图标 (1024x1024, 无透明通道: iOS 要求)。两个文件:
  game/assets/app_icon.png  手游图标 (iOS / Android 取它: project.godot 的 config/icon), 用 --art 生成
  game/assets/icon_pc.png   桌面图标 (窗口 / 任务栏 / macOS .app / Windows 回退 .ico, ScreenLayout 启动时设), 用 --plain 生成
  --art <图片>   用一张美术图做图标 (2026-10-31 起用的《天地劫》封面图): 方图直接缩, 不是方的取中间最大方块, 带透明的铺在深色底上
  --plain        不用任何原版素材的自制图标: 深红渐变底 + 金色圆环 + 米色「劫」字 (项目自带的开源文楷子集字体 game/assets/font/WuxiaKai-Subset.ttf, OFL)
  --adaptive     用现成的 app_icon.png 生成 Android 自适应图标两层 (game/assets/android/adaptive_fg.png / adaptive_bg.png, 432x432):
                 系统会把前景层裁成圆 / 圆角方 (只留中间约 2/3), 整张图铺满会被切掉边缘 (2026-10-31 网友: 「天地劫」三个字被裁), 所以前景把图缩到约 66% 放中间,
                 背景层用同一张图放大模糊铺满, 被裁出来的外圈颜色连得上
  --out <路径>   输出到别处 (缺省: --art 写 app_icon.png, --plain 写 icon_pc.png, 会覆盖现用图标)
用法: python3 tools/platform/make_app_icon.py (--art <图片> | --plain | --adaptive) [--out <路径>]     产物入库。"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _boot  # noqa: E402,F401
from paths import REPO  # noqa: E402

SIZE = 1024
OUT_ART = os.path.join(REPO, "game", "assets", "app_icon.png")
OUT_PLAIN = os.path.join(REPO, "game", "assets", "icon_pc.png")
FONT = os.path.join(REPO, "game", "assets", "font", "WuxiaKai-Subset.ttf")
GLYPH = "劫"


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make() -> Image.Image:
    top, bot = (122, 30, 24), (48, 10, 8)
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    c = SIZE / 2
    for y in range(SIZE):
        for x in range(SIZE):
            d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 / (SIZE * 0.72)   # 中心亮、四周暗的径向渐变
            px[x, y] = lerp(top, bot, min(1.0, d))
    d = ImageDraw.Draw(img)
    gold = (232, 190, 96)
    for r, w, col in ((0.40, 14, gold), (0.435, 4, (156, 118, 52))):   # 双层金环
        rr = SIZE * r
        d.ellipse([c - rr, c - rr, c + rr, c + rr], outline=col, width=w)
    f = ImageFont.truetype(FONT, int(SIZE * 0.5))
    bb = d.textbbox((0, 0), GLYPH, font=f)
    x = c - (bb[0] + bb[2]) / 2
    y = c - (bb[1] + bb[3]) / 2
    d.text((x + 6, y + 8), GLYPH, font=f, fill=(20, 4, 2))             # 投影
    d.text((x, y), GLYPH, font=f, fill=(255, 240, 205))
    return img


def from_art(path: str) -> Image.Image:
    im = Image.open(path)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGBA", im.size, (20, 24, 40, 255))
        im = Image.alpha_composite(bg, im)
    im = im.convert("RGB")
    w, h = im.size
    m = min(w, h)
    left, top = (w - m) // 2, (h - m) // 2
    return im.crop((left, top, left + m, top + m)).resize((SIZE, SIZE), Image.LANCZOS)


ADAPTIVE = 432          # Android 自适应图标每层 432x432 (108dp x 4); 系统只保证中间 66dp (约 61%) 不被裁
ADAPTIVE_ART = 0.66     # 前景里图占的比例
ADAPTIVE_DIR = os.path.join(REPO, "game", "assets", "android")


def adaptive_layers(art: Image.Image):
    """(前景 RGBA, 背景 RGB), 各 432x432"""
    n = ADAPTIVE
    bg = art.resize((n, n), Image.LANCZOS)
    zoom = int(n * 1.6)   # 放大取中间再糊, 外圈只剩颜色
    bg = bg.resize((zoom, zoom), Image.LANCZOS).crop(((zoom - n) // 2, (zoom - n) // 2, (zoom + n) // 2, (zoom + n) // 2))
    bg = bg.filter(ImageFilter.GaussianBlur(14))
    k = int(n * ADAPTIVE_ART)
    small = art.resize((k, k), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (k, k), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, k - 1, k - 1], radius=int(k * 0.14), fill=255)
    small.putalpha(mask)
    fg = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    fg.paste(small, ((n - k) // 2, (n - k) // 2), small)
    return fg, bg


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--art", default="", help="用这张美术图做图标")
    g.add_argument("--plain", action="store_true", help="生成自制的中性图标")
    g.add_argument("--adaptive", action="store_true", help="用 app_icon.png 生成 Android 自适应图标两层")
    ap.add_argument("--out", default="", help="输出路径 (缺省 --art: game/assets/app_icon.png, --plain: game/assets/icon_pc.png)")
    a = ap.parse_args()
    if a.adaptive:
        fg, bg = adaptive_layers(Image.open(OUT_ART).convert("RGB"))
        os.makedirs(ADAPTIVE_DIR, exist_ok=True)
        fg.save(os.path.join(ADAPTIVE_DIR, "adaptive_fg.png"), optimize=True)
        bg.save(os.path.join(ADAPTIVE_DIR, "adaptive_bg.png"), optimize=True)
        print("写入", os.path.relpath(ADAPTIVE_DIR, REPO) + "/adaptive_fg.png, adaptive_bg.png")
        sys.exit(0)
    out = a.out or (OUT_ART if a.art else OUT_PLAIN)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    (from_art(a.art) if a.art else make()).save(out, optimize=True)
    print("写入", os.path.relpath(out, REPO), os.path.getsize(out) // 1024, "KB")

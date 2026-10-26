#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""生成应用图标 game/assets/app_icon.png (1024x1024, 无透明通道: iOS 要求)。不用任何原版素材: 深红渐变底 + 金色圆环 + 米色「劫」字
(用项目自带的开源文楷子集字体 game/assets/font/WuxiaKai-Subset.ttf, OFL)。iOS / Android 的启动图标都取它 (project.godot 的 config/icon)。
用法: python3 tools/platform/make_app_icon.py     产物入库 (小文件), 改样式后重跑。"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _boot  # noqa: E402,F401
from paths import REPO  # noqa: E402

SIZE = 1024
OUT = os.path.join(REPO, "game", "assets", "app_icon.png")
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


if __name__ == "__main__":
    make().save(OUT, optimize=True)
    print("写入", os.path.relpath(OUT, REPO), os.path.getsize(OUT) // 1024, "KB")

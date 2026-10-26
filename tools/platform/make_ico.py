# SPDX-License-Identifier: GPL-3.0-only
"""图片 -> 多尺寸 Windows 导出图标 .ico (居中裁方):
make_ico.py <图片> <out.ico>"""
import sys
from PIL import Image

src = Image.open(sys.argv[1]).convert("RGBA")
if src.width != src.height:  # 居中裁方 (.ico 各档都是正方形, 直接 resize 会把非方形图拉变形)
    s = min(src.size)
    src = src.crop(((src.width - s) // 2, (src.height - s) // 2, (src.width + s) // 2, (src.height + s) // 2))
sizes = [16, 24, 32, 48, 64, 128, 256]
frames = [src.resize((s, s), Image.NEAREST if s >= src.width else Image.LANCZOS) for s in sizes]
frames[-1].save(sys.argv[2], format="ICO", sizes=[(s, s) for s in sizes], append_images=frames[:-1])
print("图标", sys.argv[2], sizes)

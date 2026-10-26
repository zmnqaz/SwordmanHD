# NOTICE

SwordmanHD is an unofficial, non-profit fan project: an RPG engine written in Godot for "Tian Di Jie: Shen Mo Zhi Zun Zhuan" (1999),
which runs on resource packs that players make from their own copy of the original game.
It contains none of the original game's assets (see the disclaimer in `README.md`).

The original code and documentation in this project are licensed under the **GNU General Public License, version 3 only**
(full text in `LICENSE`). Copyright (C) 2026 SwordmanHD contributors.

The third-party components below are included in, or used with, this project, under their own licenses.

## Distributed with the repository and release packages

| Component | Location | License | Copyright holders | Notes |
|---|---|---|---|---|
| xBRZ shader (ported from libretro `6xbrz.slang`) | `game/engine/render/hq/xbrz6_alpha.gdshader` | GPL-3.0-only; the xBR framework parts are MIT | Zenju (xBRZ); Hyllian (xBR) | This component is why the project as a whole is GPL-3.0-only. Full text: `game/engine/render/hq/LICENSE-GPL-3.0.txt` |
| hqx shader and lookup tables | `game/engine/render/hq/hqx.gdshader`, `hq2x.png`, `hq3x.png`, `hq4x.png` | LGPL-2.1-or-later | (C) 2003 Maxim Stepin; (C) 2010 Cameron Zemek; (C) 2014 Jules Blok (via libretro slang-shaders) | Full text: `game/engine/render/hq/LICENSE-LGPL-2.1.txt` |
| Source Han Sans (Noto Sans CJK SC) subset, `NotoSansSC-Medium.otf` | `game/assets/font/` | SIL Open Font License 1.1 | (C) Adobe / Google | `NotoSansCJK-LICENSE.txt` |
| Source Han Serif (Noto Serif CJK SC) subset, `NotoSerifSC-Subset.otf` | `game/assets/font/` | SIL Open Font License 1.1 (Reserved Font Name "Source") | (C) 2017-2024 Adobe | `NotoSerifCJK-OFL.txt` |
| LXGW WenKai subset, `WuxiaKai-Subset.ttf` (internal name changed; includes Klee One) | `game/assets/font/` | SIL Open Font License 1.1 | (C) 2021-2026 LXGW; (C) 2020 The Klee Project Authors | `LXGWWenKai-OFL.txt`. The font may not be sold by itself |
| Godot Engine 4.7.2 (runtime in release packages only) | not in the repository | MIT, plus bundled third-party libraries (FreeType, libwebp, libtheora, libvorbis, zlib, mbedTLS, and others) | Godot Engine contributors | Release packages include `licenses/Godot-LICENSE.txt` and `licenses/Godot-COPYRIGHT.txt`, exported from the same Godot build |

Release packages ship all of these license texts in the `licenses/` folder.

## Not distributed; optional local tools

| Component | License | Notes |
|---|---|---|
| ffmpeg / ffprobe | LGPL-2.1+ or GPL-2+ (depends on the build) | Invoked as external commands |
| Python packages: fonttools, opencc-python-reimplemented, Pillow, numpy, opencv-python-headless | MIT / Apache-2.0 / HPND / BSD-3-Clause | `tools/requirements-*.txt` |

## References (file-format facts only; no code was copied)

| Project | License | Used for |
|---|---|---|
| [sfczzzj/TDJSwordmanResourceEditor](https://github.com/sfczzzj/TDJSwordmanResourceEditor) | GPL-3.0 | SAF and related resource formats |
| [alantsai1024/tdjeditor](https://github.com/alantsai1024/tdjeditor) | not declared | SAF / FB2 formats |
| [foxgame/Sword](https://github.com/foxgame/Sword) (Unity remake) | no LICENSE file | Data-file field layout; corroboration of game mechanics |

## The original game

"Tian Di Jie" and its name, characters, artwork, music and text are the property of their respective rights holders.
This project is not affiliated with or endorsed by them.

# Linux 打包

与 Windows 同一脚本、同一套资源组装与必带清单（`tools/build_windows.py --linux`，导出预设 `Linux`，模板 `linux_release.x86_64`）。

```bash
python3 tools/build_windows.py --linux          # dist/linux/SwordmanHD/
python3 tools/build_windows.py --linux --zip    # 另打 dist/linux/SwordmanHD-linux-x86_64.tar.xz (保留可执行权限)
```

包内容：可执行文件（主 pck 内嵌）+ `resource/` 里的资源包 (`common_*`、`hd_*` / `classic_*`, 见 [资源包.md](资源包.md); `--edition=hd|classic` 只带一种画质) + 许可文本（见 [Windows.md](Windows.md)）。

运行：解压后 `./SwordmanHD.x86_64`（需要 OpenGL 3.3）；原生 Wayland 加 `--display-driver wayland`。存档 `~/.local/share/SwordmanHD/`。

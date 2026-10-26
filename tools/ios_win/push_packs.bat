@echo off
rem Double-click to push the resource packs (.pck) into the app on a USB-connected iPad/iPhone.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push_packs.ps1" %*
echo.
pause

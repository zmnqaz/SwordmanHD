@echo off
rem Double-click to install the Android APK and push the resource packs to a USB-connected phone.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0android_install.ps1" %*
echo.
pause

@echo off
rem Double-click to sign and install the iOS IPA to an iPad/iPhone connected by USB. See docs/ios.md (ios_install.ps1 header)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ios_install.ps1" %*
echo.
pause

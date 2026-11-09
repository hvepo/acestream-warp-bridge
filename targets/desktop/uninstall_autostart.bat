@echo off
setlocal
title Restore Original AceStream Startup
cd /d "%~dp0"

echo [*] Restoring default AceStream autostart...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_autostart.ps1" -Uninstall
pause
exit /b 0

@echo off
setlocal
title Connect Network Drive Z: (Raspberry Pi Playlists)
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect_rpi_z.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [!] Could not mount Drive Z:.
    pause
    exit /b %ERRORLEVEL%
)

exit /b 0

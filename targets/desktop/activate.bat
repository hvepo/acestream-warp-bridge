@echo off
setlocal
title Activate Desktop Target - WarpAcePi
cd /d "%~dp0"

echo ========================================================
echo     WARPACEPI ACTIVATION - TARGET: DESKTOP PC
echo ========================================================
echo  P2P Port: 48621  ^|  HTTP API: 127.0.0.1:6878
echo  RPi Proxy: 1080  ^|  Zero Desktop Clutter
echo ========================================================
echo.

:: 1. Update repository if git is present
where git >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [*] Pulling latest repository updates...
    git pull origin main
    echo.
)

:: 2. Install silent autostart & clean desktop
echo [*] Installing silent autostart and cleaning Desktop...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_autostart.ps1"
if %ERRORLEVEL% neq 0 (
    echo [!] Failed to register autostart.
    pause
    exit /b %ERRORLEVEL%
)
echo.

:: 3. Connect Drive Z:
echo [*] Verifying Network Drive Z: (RPi Playlists)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect_rpi_z.ps1"
echo.

:: 4. Restart AceStream with WARP shield
echo [*] Starting AceStream with Cloudflare WARP proxy on port 48621...
call "%~dp0restart_acestream_warp.bat"

echo.
echo ========================================================
echo  DESKTOP ACTIVATION COMPLETE
echo  - All tools stay strictly inside targets\desktop\
echo  - Zero files on Desktop
echo  - Playlists ready at Z:\playlist_vlc.m3u
echo ========================================================
pause
exit /b 0

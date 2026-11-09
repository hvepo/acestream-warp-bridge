@echo off
setlocal
title Activate Laptop Target - WarpAcePi
cd /d "%~dp0"

echo ========================================================
echo     WARPACEPI ACTIVATION - TARGET: LAPTOP
echo ========================================================
echo  P2P Port: 48622  ^|  HTTP API: 127.0.0.1:6878
echo  RPi Proxy: 1080  ^|  Dock NIC Optimization
echo  Zero Desktop Clutter
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
echo [*] Installing silent autostart (Port 48622) and cleaning Desktop...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_autostart.ps1"
if %ERRORLEVEL% neq 0 (
    echo [!] Failed to register autostart.
    pause
    exit /b %ERRORLEVEL%
)
echo.

:: 3. Optimize Laptop Dock Network Adapter
echo [*] Optimizing network adapter (disabling Green Ethernet / packet drops)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Loopback|Tailscale' }; foreach ($a in $adapters) { $props = @('Energy Efficient Ethernet', 'Green Ethernet', 'Gigabit Lite'); foreach ($prop in $props) { try { Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $prop -DisplayValue 'Disabled' -ErrorAction SilentlyContinue } catch {} } } }" >nul 2>&1
echo [OK] Network adapter tuned for P2P streaming.
echo.

:: 4. Connect Drive Z:
echo [*] Verifying Network Drive Z: (RPi Playlists)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect_rpi_z.ps1"
echo.

:: 5. Restart AceStream with WARP shield
echo [*] Starting AceStream with Cloudflare WARP proxy on port 48622...
call "%~dp0restart_acestream_warp.bat"

echo.
echo ========================================================
echo  LAPTOP ACTIVATION COMPLETE
echo  - All tools stay strictly inside targets\laptop\
echo  - Zero files on Desktop
echo  - Playlists ready at Z:\playlist_vlc.m3u
echo ========================================================
pause
exit /b 0

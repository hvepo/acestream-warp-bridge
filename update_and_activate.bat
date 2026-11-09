@echo off
setlocal
title Update and Activate - WarpAcePi
cd /d "%~dp0"

echo ========================================================
echo       AUTOMATIC UPDATER AND INSTALLER - WarpAcePi
echo ========================================================
echo.

:: 1. Update repository if git is available
where git >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [*] Pulling latest updates from GitHub...
    git pull origin main
    echo.
) else (
    echo [*] Git not found in PATH, continuing with local files...
)

:: 2. Execute PowerShell installer
echo [*] Registering auto-start launcher and configuration...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\install-windows-autostart.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [!] An error occurred during installation.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================================
echo   INSTALLATION AND UPDATE COMPLETED SUCCESSFULLY
echo ========================================================
echo  Applied configuration:
echo   - Silent auto-start with WARP shield at Windows login
echo   - Tools available in windows\ folder
echo   - Desktop kept 100%% clean (zero shortcuts)
echo ========================================================
echo.

set /p RESP="Do you want to restart AceStream with the WARP shield now? (Y/N): "
if /i "%RESP%"=="Y" (
    start "" "%~dp0windows\restart_acestream_warp.bat"
)

exit /b 0

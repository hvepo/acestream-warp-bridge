@echo off
setlocal
title WarpAcePi Target Selector & Activator
cd /d "%~dp0"

echo ========================================================
echo       WARPACEPI - TARGET ACTIVATOR ^& UPDATER
echo ========================================================
echo  All resources remain strictly inside the repository.
echo  Zero files or shortcuts will be created on your Desktop.
echo ========================================================
echo.
echo Please select your target device:
echo.
echo   [1] Desktop PC (Inbound P2P Port 48621, HTTP API 6878)
echo   [2] Laptop     (Inbound P2P Port 48622, Dock Optimization)
echo   [Q] Quit
echo.
set /p TARGET_CHOICE="Enter selection [1, 2, or Q]: "

if "%TARGET_CHOICE%"=="1" goto :TARGET_DESKTOP
if "%TARGET_CHOICE%"=="2" goto :TARGET_LAPTOP
if /i "%TARGET_CHOICE%"=="Q" goto :QUIT
echo Invalid selection.
pause
exit /b 1

:TARGET_DESKTOP
echo.
echo [*] Launching Desktop PC activation...
call "%~dp0targets\desktop\activate.bat"
exit /b %ERRORLEVEL%

:TARGET_LAPTOP
echo.
echo [*] Launching Laptop activation...
call "%~dp0targets\laptop\activate.bat"
exit /b %ERRORLEVEL%

:QUIT
exit /b 0

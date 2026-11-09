@echo off
title AceStream Channels Updater - WarpAcePi
chcp 65001 >nul

cd /d "%~dp0"

echo ======================================================================
echo   📡 AUTOMATIC ACESTREAM CHANNELS UPDATER - WarpAcePi
echo ======================================================================
echo.
echo Starting channel update process and refreshing M3U playlists...
echo.

REM 1. Python detection on Windows
set PY_CMD=
where python >nul 2>&1 && set PY_CMD=python
if not defined PY_CMD (
    where py >nul 2>&1 && set PY_CMD=py
)
if not defined PY_CMD (
    if exist "C:\Python315\python.exe" set PY_CMD="C:\Python315\python.exe"
    if exist "C:\Python314\python.exe" set PY_CMD="C:\Python314\python.exe"
    if exist "C:\Python313\python.exe" set PY_CMD="C:\Python313\python.exe"
    if exist "C:\Python312\python.exe" set PY_CMD="C:\Python312\python.exe"
    if exist "C:\Python311\python.exe" set PY_CMD="C:\Python311\python.exe"
    if exist "C:\Python310\python.exe" set PY_CMD="C:\Python310\python.exe"
)

if not defined PY_CMD (
    echo ======================================================================
    echo [ERROR] Python was not found on this system.
    echo.
    echo Please install Python 3: https://www.python.org/downloads/
    echo * IMPORTANT: Check "Add python.exe to PATH" during installation.
    echo ======================================================================
    echo.
    pause
    exit /b 1
)

REM 2. Run channel evaluation and update
echo [1/3] Downloading sources (Elcano, AceStreamID, local feeds)...
echo [2/3] Querying search engines for channel keywords...
echo [3/3] Deduplicating hashes and compiling master M3U playlists...
echo.

if "%~1"=="" (
    %PY_CMD% scripts\evaluate_and_update.py --skip-probe
) else (
    %PY_CMD% scripts\evaluate_and_update.py %*
)
set SCRIPT_EXIT=%errorlevel%

echo.
echo ======================================================================
if %SCRIPT_EXIT% equ 0 goto :success
goto :failure

:success
echo [SUCCESS] Playlists updated and verified.
echo.
echo Master playlists available in: %~dp0playlists\
echo ======================================================================
echo.
start "" explorer.exe "%~dp0playlists"
goto :end

:failure
echo [WARNING] Finished with warnings or errors (Code: %SCRIPT_EXIT%).
echo Check the logs above for details.
echo ======================================================================
echo.

:end
timeout /t 5 >nul
exit /b %SCRIPT_EXIT%

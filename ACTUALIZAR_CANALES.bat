@echo off
title Actualizador de Canales AceStream
chcp 65001 >nul

REM Situarse en la carpeta donde esta este archivo .bat
cd /d "%~dp0"

echo ======================================================================
echo   📡 ACTUALIZADOR AUTOMATICO DE CANALES ACESTREAM
echo ======================================================================
echo.
echo Iniciando proceso de actualizacion y refresco de listas M3U...
echo.

REM 1. Deteccion de Python en Windows
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
    echo [ERROR] No se ha encontrado Python instalado en este equipo.
    echo.
    echo Para ejecutar este actualizador necesitas instalar Python:
    echo https://www.python.org/downloads/
    echo.
    echo * IMPORTANTE: Marca la casilla "Add python.exe to PATH" al instalarlo.
    echo ======================================================================
    echo.
    echo Presiona cualquier tecla para salir...
    pause >nul
    exit /b 1
)

REM 2. Ejecutar la actualizacion completa de canales
echo [1/3] Descargando fuentes (Elcano, AceStreamID.com, descargas locales)...
echo [2/3] Consultando buscadores complementarios (search-ace.stream y acestreamid.com) por keywords...
echo [3/3] Deduplicando hashes y actualizando listas M3U maestras...
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
goto :error

:success
echo  ✅ LISTAS M3U ACTUALIZADAS Y REFLEJADAS CON EXITO
echo.
echo  Tus archivos listos para usar en VLC, Kodi o IPTV estan en:
echo    • playlists\playlist.m3u              [Lista maestra compatible con VLC]
echo    • playlists\playlist_vlc.m3u          [Optimizada para VLC con buffer 3s y reconexion]
echo    • playlists\working_streams.m3u       [Canales activos verificados (compatible con VLC)]
echo    • playlists\playlist_http.m3u         [Proxy HTTP estándar http://]
echo    • playlists\playlist_direct.m3u       [Enlaces directos acestream:// (Ace Player/Kodi)]
echo    • playlists\working_streams_direct.m3u [Canales activos directos acestream://]
echo    • data\channels.json                  [Catalogo completo]
echo ======================================================================
echo.
echo Abriendo la carpeta playlists en el Explorador...
start "" "%~dp0playlists"
goto :end

:error
echo  ⚠️ Se detecto un problema durante la actualizacion (Codigo %SCRIPT_EXIT%).
echo ======================================================================
goto :end

:end
echo.
echo Presiona cualquier tecla para cerrar esta ventana...
pause >nul
exit /b %SCRIPT_EXIT%


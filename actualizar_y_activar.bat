@echo off
setlocal
title Actualizar e Instalar AceStream WARP Bridge
cd /d "%~dp0"

echo ========================================================
echo   ACTUALIZADOR E INSTALADOR AUTOMATICO - ACESTREAM WARP
echo ========================================================
echo.

:: 1. Actualizar repositorio si git esta disponible
where git >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [*] Descargando ultimas mejoras de GitHub...
    git pull origin main
    echo.
) else (
    echo [*] Git no detectado en PATH, continuando con los archivos locales...
)

:: 2. Ejecutar instalador de PowerShell
echo [*] Registrando lanzadores y creando accesos directos...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\install-windows-autostart.ps1"

if %ERRORLEVEL% neq 0 (
    echo.
    echo [!] Hubo un error durante la instalacion.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================================
echo  INSTALACION Y ACTUALIZACION COMPLETADA CON EXITO
echo ========================================================
echo  Configuracion aplicada:
echo   - Autoarranque silencioso con escudo WARP al iniciar sesion
echo   - Herramientas listas dentro de la carpeta windows\ de este repositorio
echo   - Tu Escritorio queda 100%% limpio (sin accesos directos)
echo ========================================================
echo.

set /p RESP="Deseas reiniciar AceStream con el escudo ahora mismo? (S/N): "
if /i "%RESP%"=="S" (
    start "" "%~dp0windows\Reiniciar AceStream (WARP).bat"
)

exit /b 0

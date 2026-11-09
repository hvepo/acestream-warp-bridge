@echo off
setlocal enabledelayedexpansion
title Reiniciar AceStream con Escudo WARP (Raspberry Pi)

echo ========================================================
echo        REINICIANDO ACESTREAM CON ESCUDO ANTI-BLOQUEO
echo ========================================================
echo.

echo [*] Cerrando instancias activas de AceStream...
taskkill /F /IM ace_engine.exe >nul 2>&1
timeout /t 1 >nul

echo [*] Comprobando conexion con Raspberry Pi...

set PROXY_HOST=
set PROXY_PORT=1080

:: 1. Comprobar Tailscale (100.89.165.79) con 2500ms de margen
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('100.89.165.79', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(2500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    set PROXY_HOST=100.89.165.79
    echo [OK] Raspberry Pi conectada via Tailscale (!PROXY_HOST!:!PROXY_PORT!).
    echo [OK] Escudo Cloudflare WARP anti-bloqueo: ACTIVADO.
    goto :LAUNCH
)

:: 2. Comprobar red local LAN (192.168.1.139) con 1500ms de margen
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('192.168.1.139', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    set PROXY_HOST=192.168.1.139
    echo [OK] Raspberry Pi conectada via LAN (!PROXY_HOST!:!PROXY_PORT!).
    echo [OK] Escudo Cloudflare WARP anti-bloqueo: ACTIVADO.
    goto :LAUNCH
)

echo [!] AVISO: Raspberry Pi no responde en el puerto 1080 (Tailscale ni LAN).
echo [!] Comprueba que la RPi este encendida y el servicio warp-proxy activo.
echo [!] Iniciando AceStream en modo directo (sin proxy)...

:LAUNCH
echo.
if not "!PROXY_HOST!"=="" (
    set HTTP_PROXY=http://!PROXY_HOST!:!PROXY_PORT!
    set HTTPS_PROXY=http://!PROXY_HOST!:!PROXY_PORT!
    set http_proxy=http://!PROXY_HOST!:!PROXY_PORT!
    set https_proxy=http://!PROXY_HOST!:!PROXY_PORT!
    set NO_PROXY=localhost,127.0.0.1,::1
    set no_proxy=localhost,127.0.0.1,::1
)

echo [*] Iniciando AceStream Engine...
cd /d "%APPDATA%\ACEStream\engine"
start "" "%APPDATA%\ACEStream\engine\ace_engine.exe"

echo [*] Esperando confirmacion de inicio...
timeout /t 3 >nul

tasklist /FI "IMAGENAME eq ace_engine.exe" 2>nul | findstr /i "ace_engine.exe" >nul
if !ERRORLEVEL! equ 0 (
    echo.
    echo ========================================================
    echo  [OK] ACESTREAM INICIADO Y CORRIENDO CON ESCUDO WARP
    echo ========================================================
    echo  Proxy activo : !PROXY_HOST!:!PROXY_PORT!
    echo ========================================================
    timeout /t 4
    exit /b 0
) else (
    echo.
    echo ========================================================
    echo  [!] ALERTA: AceStream intento arrancar pero se cerro.
    echo ========================================================
    echo [*] Ultimas lineas de %APPDATA%\ACEStream\engine\acestream.log:
    echo --------------------------------------------------------
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "if (Test-Path \"$env:APPDATA\ACEStream\engine\acestream.log\") { Get-Content \"$env:APPDATA\ACEStream\engine\acestream.log\" -Tail 20 | Out-String | Write-Host } else { Write-Host 'No se encontro acestream.log' }"
    echo --------------------------------------------------------
    echo.
    pause
    exit /b 1
)

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

:: 1. Comprobar Tailscale (100.89.165.79)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('100.89.165.79', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(700, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    set PROXY_HOST=100.89.165.79
    echo [OK] Raspberry Pi conectada via Tailscale (!PROXY_HOST!:!PROXY_PORT!).
    echo [OK] Escudo Cloudflare WARP anti-bloqueo: ACTIVADO.
    goto :LAUNCH
)

:: 2. Comprobar red local LAN (192.168.1.139)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('192.168.1.139', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    set PROXY_HOST=192.168.1.139
    echo [OK] Raspberry Pi conectada via LAN (!PROXY_HOST!:!PROXY_PORT!).
    echo [OK] Escudo Cloudflare WARP anti-bloqueo: ACTIVADO.
    goto :LAUNCH
)

echo [!] AVISO: Raspberry Pi no disponible o apagada.
echo [!] Iniciando AceStream en modo directo (sin proxy)...

:LAUNCH
echo.
if not "!PROXY_HOST!"=="" (
    set HTTP_PROXY=http://!PROXY_HOST!:!PROXY_PORT!
    set HTTPS_PROXY=http://!PROXY_HOST!:!PROXY_PORT!
    set ALL_PROXY=socks5://!PROXY_HOST!:!PROXY_PORT!
)

echo [*] Iniciando AceStream Engine...
start "" "%APPDATA%\ACEStream\engine\ace_engine.exe"
echo [OK] AceStream iniciado correctamente.
timeout /t 3
exit

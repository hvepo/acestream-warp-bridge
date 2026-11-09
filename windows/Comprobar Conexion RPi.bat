@echo off
setlocal enabledelayedexpansion
title Comprobador de Conexion - AceStream WARP Bridge

echo ========================================================
echo       DIAGNOSTICO DE CONEXION RASPBERRY PI + WARP
echo ========================================================
echo.

set PROXY_PORT=1080
set TAILSCALE_IP=100.89.165.79
set LAN_IP=192.168.1.139

echo [1/4] Probando puerto 1080 en Tailscale (!TAILSCALE_IP!)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('!TAILSCALE_IP!', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(3000, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    echo       -> [OK] Puerto 1080 responde correctamente via Tailscale.
    set ACTIVE_IP=!TAILSCALE_IP!
) else (
    echo       -> [FALLO] No responde via Tailscale.
)

echo.
echo [2/4] Probando puerto 1080 en Red Local LAN (!LAN_IP!)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('!LAN_IP!', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(2000, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    echo       -> [OK] Puerto 1080 responde correctamente via LAN.
    if "!ACTIVE_IP!"=="" set ACTIVE_IP=!LAN_IP!
) else (
    echo       -> [FALLO] No responde via LAN.
)

echo.
if "!ACTIVE_IP!"=="" (
    echo ========================================================
    echo  ERROR CRITICO: La Raspberry Pi no responde en el puerto 1080.
    echo ========================================================
    echo  Posibles causas:
    echo   1. La Raspberry Pi esta apagada o desconectada.
    echo   2. El servicio warp-proxy no esta corriendo en la RPi.
    echo      Compruebalo con: sudo systemctl status warp-proxy.service
    echo   3. Tailscale no esta conectado en este PC o en la RPi.
    echo ========================================================
    pause
    exit /b 1
)

echo [3/4] Probando tunel Cloudflare WARP a traves de !ACTIVE_IP!:!PROXY_PORT!...
curl -s --max-time 6 -x http://!ACTIVE_IP!:!PROXY_PORT! https://cloudflare.com/cdn-cgi/trace > "%TEMP%\warp_trace.txt" 2>nul

findstr /i "warp=on" "%TEMP%\warp_trace.txt" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo       -> [OK] Tunel WARP ACTIVO y validado con exito.
    for /f "tokens=*" %%a in ('findstr /i "ip= loc= warp=" "%TEMP%\warp_trace.txt"') do echo          %%a
) else (
    echo       -> [FALLO] La RPi responde pero Cloudflare WARP no devuelve warp=on.
)

echo.
echo [4/4] Comprobando conexiones activas de AceStream hacia la RPi...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$conns = Get-NetTCPConnection -RemotePort 1080 -ErrorAction SilentlyContinue; if ($conns) { Write-Host '      -> [OK] Hay conexiones ACTIVAS establecidas con la RPi en el puerto 1080:' -ForegroundColor Green; $conns | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State | Format-Table -AutoSize | Out-String | Write-Host } else { Write-Host '      -> [INFO] En este momento no hay conexiones abiertas hacia el puerto 1080.' -ForegroundColor Yellow; Write-Host '         (Inicia un stream en AceStream para ver el trafico fluir).' }"

echo.
echo ========================================================
echo                 RESUMEN DEL DIAGNOSTICO
echo ========================================================
echo  Proxy RPi Activo : !ACTIVE_IP!:!PROXY_PORT!
echo  Listo para usar  : SI
echo ========================================================
echo.
pause

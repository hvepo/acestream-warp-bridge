@echo off
setlocal enabledelayedexpansion
title Reiniciar AceStream con Escudo WARP (Raspberry Pi)

echo ========================================================
echo        REINICIANDO ACESTREAM CON ESCUDO ANTI-BLOQUEO
echo ========================================================
echo.

echo [*] Cerrando instancias activas de AceStream y liberando puerto 6878...
taskkill /F /IM ace_engine.exe >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = (Get-NetTCPConnection -LocalPort 6878 -ErrorAction SilentlyContinue).OwningProcess; if ($p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }" >nul 2>&1
timeout /t 1 >nul

echo [*] Comprobando conexion con Raspberry Pi...

set PROXY_HOST=
set PROXY_PORT=1080

REM 1. Comprobar Tailscale (100.89.165.79) con 2500ms de margen
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('100.89.165.79', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(2500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1
if %ERRORLEVEL% equ 0 goto :USE_TAILSCALE

REM 2. Comprobar red local LAN (192.168.1.139) con 1500ms de margen
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('192.168.1.139', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1
if %ERRORLEVEL% equ 0 goto :USE_LAN

echo [!] AVISO: Raspberry Pi no responde en el puerto 1080 (Tailscale ni LAN).
echo [!] Comprueba que la RPi este encendida y el servicio warp-proxy activo.
echo [!] Iniciando AceStream en modo directo (sin proxy)...
goto :START_PROCESS

:USE_TAILSCALE
set PROXY_HOST=100.89.165.79
echo [OK] Raspberry Pi conectada via Tailscale - %PROXY_HOST%:%PROXY_PORT%
echo [OK] Escudo Cloudflare WARP anti-bloqueo: ACTIVADO
goto :START_PROCESS

:USE_LAN
set PROXY_HOST=192.168.1.139
echo [OK] Raspberry Pi conectada via LAN - %PROXY_HOST%:%PROXY_PORT%
echo [OK] Escudo Cloudflare WARP anti-bloqueo: ACTIVADO
goto :START_PROCESS

:START_PROCESS
echo.
if not "%PROXY_HOST%"=="" (
    set HTTP_PROXY=http://%PROXY_HOST%:%PROXY_PORT%
    set HTTPS_PROXY=http://%PROXY_HOST%:%PROXY_PORT%
    set http_proxy=http://%PROXY_HOST%:%PROXY_PORT%
    set https_proxy=http://%PROXY_HOST%:%PROXY_PORT%
    set NO_PROXY=localhost,127.0.0.1,::1
    set no_proxy=localhost,127.0.0.1,::1
)

echo [*] Iniciando AceStream Engine en puerto 6878...
cd /d "%APPDATA%\ACEStream\engine"
start "" "%APPDATA%\ACEStream\engine\ace_engine.exe" --http-port 6878

echo [*] Esperando confirmacion de inicio...
timeout /t 3 >nul

tasklist /FI "IMAGENAME eq ace_engine.exe" 2>nul | findstr /i "ace_engine.exe" >nul
if %ERRORLEVEL% equ 0 goto :RUNNING_OK
goto :RUNNING_FAILED

:RUNNING_OK
echo.
echo ========================================================
echo  [OK] ACESTREAM INICIADO Y CORRIENDO CON ESCUDO WARP
echo ========================================================
echo  Proxy activo : %PROXY_HOST%:%PROXY_PORT%
echo.
echo [*] Verificando servidor local VLC (127.0.0.1:6878)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ready = $false; for ($i=0; $i -lt 10; $i++) { try { $r = Invoke-RestMethod -Uri 'http://127.0.0.1:6878/webui/api/service?method=get_version' -TimeoutSec 1 -ErrorAction Stop; $ready = $true; break } catch { Start-Sleep -Milliseconds 500 } }; if ($ready) { Write-Host ' [OK] Puerto 6878 ACTIVO y respondiendo. Ya puedes reproducir el canal en VLC.' -ForegroundColor Green } else { Write-Host ' [AVISO] El motor arranco pero el puerto 6878 sigue inicializandose.' -ForegroundColor Yellow }"
echo ========================================================
echo.
timeout /t 5
exit /b 0

:RUNNING_FAILED
echo.
echo ========================================================
echo  [!] ALERTA: AceStream intento arrancar pero se cerro.
echo ========================================================
echo [*] Ultimas lineas de acestream.log:
echo --------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path \"$env:APPDATA\ACEStream\engine\acestream.log\") { Get-Content \"$env:APPDATA\ACEStream\engine\acestream.log\" -Tail 20 | Out-String | Write-Host } else { Write-Host 'No se encontro acestream.log' }"
echo --------------------------------------------------------
echo.
pause
exit /b 1

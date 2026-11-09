@echo off
setlocal

set PROXY_HOST=
set PROXY_PORT=1080

:: 1. Probar primero la IP de Tailscale (100.89.165.79) con 2500ms de timeout
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('100.89.165.79', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(2500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    set PROXY_HOST=100.89.165.79
    goto :START_ENGINE
)

:: 2. Fallback a la IP local (192.168.1.139) con 1500ms de timeout
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('192.168.1.139', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    set PROXY_HOST=192.168.1.139
    goto :START_ENGINE
)

:START_ENGINE
if not "%PROXY_HOST%"=="" (
    set HTTP_PROXY=http://%PROXY_HOST%:%PROXY_PORT%
    set HTTPS_PROXY=http://%PROXY_HOST%:%PROXY_PORT%
    set http_proxy=http://%PROXY_HOST%:%PROXY_PORT%
    set https_proxy=http://%PROXY_HOST%:%PROXY_PORT%
    set NO_PROXY=localhost,127.0.0.1,::1
    set no_proxy=localhost,127.0.0.1,::1
)

cd /d "%APPDATA%\ACEStream\engine"
start "" "%APPDATA%\ACEStream\engine\ace_engine.exe"
exit

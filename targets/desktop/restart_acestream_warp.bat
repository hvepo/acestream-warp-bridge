@echo off
setlocal enabledelayedexpansion
title Restart AceStream with WARP Shield - Desktop PC (Port 48621)

echo ========================================================
echo   RESTARTING ACESTREAM (WARP SHIELD) - TARGET: DESKTOP
echo ========================================================
echo  P2P Port: 48621  ^|  HTTP API: 127.0.0.1:6878
echo ========================================================
echo.

echo [*] Closing active AceStream instances and freeing port 6878...
taskkill /F /IM ace_engine.exe >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = (Get-NetTCPConnection -LocalPort 6878 -ErrorAction SilentlyContinue).OwningProcess; if ($p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }" >nul 2>&1
timeout /t 1 >nul

echo [*] Checking connection to Raspberry Pi...

set PROXY_HOST=
set PROXY_PORT=1080

REM 1. Check Tailscale IP (100.89.165.79)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('100.89.165.79', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(2500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1
if %ERRORLEVEL% equ 0 goto :USE_TAILSCALE

REM 2. Check local LAN IP (192.168.1.139)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('192.168.1.139', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1
if %ERRORLEVEL% equ 0 goto :USE_LAN

echo [!] WARNING: Raspberry Pi did not answer on port 1080 (Tailscale or LAN).
echo [!] Check that the Raspberry Pi is turned on and warp-proxy service is running.
echo [!] Starting AceStream in direct mode (without proxy)...
goto :START_PROCESS

:USE_TAILSCALE
set PROXY_HOST=100.89.165.79
echo [OK] Raspberry Pi connected via Tailscale - %PROXY_HOST%:%PROXY_PORT%
echo [OK] Cloudflare WARP anti-censorship shield: ACTIVE
goto :START_PROCESS

:USE_LAN
set PROXY_HOST=192.168.1.139
echo [OK] Raspberry Pi connected via LAN - %PROXY_HOST%:%PROXY_PORT%
echo [OK] Cloudflare WARP anti-censorship shield: ACTIVE
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

echo [*] Starting AceStream Engine (Desktop: --http-port 6878 --port 48621)...
cd /d "%APPDATA%\ACEStream\engine"
start "" "%APPDATA%\ACEStream\engine\ace_engine.exe" --http-port 6878 --port 48621

echo [*] Waiting for startup confirmation...
timeout /t 3 >nul

tasklist /FI "IMAGENAME eq ace_engine.exe" 2>nul | findstr /i "ace_engine.exe" >nul
if %ERRORLEVEL% equ 0 goto :RUNNING_OK
goto :RUNNING_FAILED

:RUNNING_OK
echo.
echo ========================================================
echo  [OK] ACESTREAM STARTED AND RUNNING WITH WARP SHIELD
echo ========================================================
echo  Target Machine : Desktop PC (Port 48621)
echo  Active Proxy   : %PROXY_HOST%:%PROXY_PORT%
echo.
echo [*] Verifying local VLC server (127.0.0.1:6878)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ready = $false; for ($i=0; $i -lt 10; $i++) { try { $r = Invoke-RestMethod -Uri 'http://127.0.0.1:6878/webui/api/service?method=get_version' -TimeoutSec 1 -ErrorAction Stop; $ready = $true; break } catch { Start-Sleep -Milliseconds 500 } }; if ($ready) { Write-Host ' [OK] Port 6878 is ACTIVE and answering. Ready to play streams in VLC.' -ForegroundColor Green } else { Write-Host ' [WARNING] Engine started but port 6878 is still initializing.' -ForegroundColor Yellow }"
echo ========================================================
echo.
timeout /t 4
exit /b 0

:RUNNING_FAILED
echo.
echo ========================================================
echo  [!] ERROR: AceStream attempted to start but exited.
echo ========================================================
echo [*] Last lines of acestream.log:
echo --------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path \"$env:APPDATA\ACEStream\engine\acestream.log\") { Get-Content \"$env:APPDATA\ACEStream\engine\acestream.log\" -Tail 20 | Out-String | Write-Host } else { Write-Host 'acestream.log not found' }"
echo --------------------------------------------------------
echo.
pause
exit /b 1

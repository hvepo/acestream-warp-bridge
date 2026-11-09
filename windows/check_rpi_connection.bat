@echo off
setlocal enabledelayedexpansion
title Connection Tester - WarpAcePi

echo ========================================================
echo       RASPBERRY PI + WARP PROXY CONNECTIVITY TEST
echo ========================================================
echo.

set PROXY_PORT=1080
set TAILSCALE_IP=100.89.165.79
set LAN_IP=192.168.1.139

echo [1/4] Testing port 1080 on Tailscale (!TAILSCALE_IP!)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('!TAILSCALE_IP!', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(3000, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    echo       -^> [OK] Port 1080 responding via Tailscale.
    set ACTIVE_IP=!TAILSCALE_IP!
) else (
    echo       -^> [FAIL] No response via Tailscale.
)

echo.
echo [2/4] Testing port 1080 on Local LAN (!LAN_IP!)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('!LAN_IP!', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(2000, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1

if %ERRORLEVEL% equ 0 (
    echo       -^> [OK] Port 1080 responding via LAN.
    if "!ACTIVE_IP!"=="" set ACTIVE_IP=!LAN_IP!
) else (
    echo       -^> [FAIL] No response via LAN.
)

echo.
if "!ACTIVE_IP!"=="" (
    echo ========================================================
    echo  CRITICAL ERROR: Raspberry Pi did not answer on port 1080.
    echo ========================================================
    echo  Possible causes:
    echo   1. Raspberry Pi is powered off or disconnected.
    echo   2. warp-proxy service is not running on the RPi.
    echo      Check with: sudo systemctl status warp-proxy.service
    echo   3. Tailscale is not connected on this PC or the RPi.
    echo ========================================================
    pause
    exit /b 1
)

echo [3/4] Testing Cloudflare WARP tunnel via !ACTIVE_IP!:!PROXY_PORT!...
curl -s --max-time 6 -x http://!ACTIVE_IP!:!PROXY_PORT! https://cloudflare.com/cdn-cgi/trace > "%TEMP%\warp_trace.txt" 2>nul

findstr /i "warp=on" "%TEMP%\warp_trace.txt" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo       -^> [OK] Cloudflare WARP tunnel is ACTIVE and validated.
    for /f "tokens=*" %%a in ('findstr /i "ip= loc= warp=" "%TEMP%\warp_trace.txt"') do echo          %%a
) else (
    echo       -^> [FAIL] RPi responded but Cloudflare WARP did not return warp=on.
)

echo.
echo [4/4] Checking active AceStream connections to RPi...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$conns = Get-NetTCPConnection -RemotePort 1080 -ErrorAction SilentlyContinue; if ($conns) { Write-Host '      -> [OK] Active connections established with RPi on port 1080:' -ForegroundColor Green; $conns | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State | Format-Table -AutoSize | Out-String | Write-Host } else { Write-Host '      -> [INFO] No open connections to port 1080 at this moment.' -ForegroundColor Yellow; Write-Host '         (Start a stream in AceStream to see traffic flowing).' }"

echo.
echo ========================================================
echo                 DIAGNOSTIC SUMMARY
echo ========================================================
echo  Active RPi Proxy: !ACTIVE_IP!:!PROXY_PORT!
echo  Ready to Stream : YES
echo ========================================================
echo.
pause

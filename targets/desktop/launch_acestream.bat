@echo off
setlocal
cd /d "%APPDATA%\ACEStream\engine"

:: Check connection to Raspberry Pi WARP Gateway (Tailscale or LAN)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('100.89.165.79', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(2000, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1
if %ERRORLEVEL% equ 0 goto :USE_TAILSCALE

powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = New-Object Net.Sockets.TcpClient; try { $ar = $t.BeginConnect('192.168.1.139', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) { $t.EndConnect($ar); exit 0 } else { exit 1 } } catch { exit 1 } finally { $t.Close() }" >nul 2>&1
if %ERRORLEVEL% equ 0 goto :USE_LAN

goto :DIRECT_LAUNCH

:USE_TAILSCALE
set HTTP_PROXY=http://100.89.165.79:1080
set HTTPS_PROXY=http://100.89.165.79:1080
set http_proxy=http://100.89.165.79:1080
set https_proxy=http://100.89.165.79:1080
set NO_PROXY=localhost,127.0.0.1,::1
set no_proxy=localhost,127.0.0.1,::1
goto :LAUNCH

:USE_LAN
set HTTP_PROXY=http://192.168.1.139:1080
set HTTPS_PROXY=http://192.168.1.139:1080
set http_proxy=http://192.168.1.139:1080
set https_proxy=http://192.168.1.139:1080
set NO_PROXY=localhost,127.0.0.1,::1
set no_proxy=localhost,127.0.0.1,::1
goto :LAUNCH

:DIRECT_LAUNCH
:: No proxy if RPi is unreachable

:LAUNCH
:: Desktop target uses P2P port 48621 and fixed HTTP API port 6878
start "" "%APPDATA%\ACEStream\engine\ace_engine.exe" --http-port 6878 --port 48621
exit /b 0

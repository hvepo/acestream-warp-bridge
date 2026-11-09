@echo off
setlocal
title Test Connection to Raspberry Pi - WarpAcePi
cd /d "%~dp0"

echo ========================================================
echo       CONNECTIVITY TEST TO RASPBERRY PI (WarpAcePi)
echo ========================================================
echo.

echo [1/3] Testing Cloudflare WARP proxy on port 1080...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ts = New-Object Net.Sockets.TcpClient; try { $ar = $ts.BeginConnect('100.89.165.79', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(2000, $false)) { $ts.EndConnect($ar); Write-Host ' [OK] Tailscale Proxy (100.89.165.79:1080): CONNECTED' -ForegroundColor Green } else { Write-Host ' [FAIL] Tailscale Proxy (100.89.165.79:1080): TIMEOUT' -ForegroundColor Yellow } } catch { Write-Host ' [FAIL] Tailscale Proxy: NOT ANSWERING' -ForegroundColor Red } finally { $ts.Close() }"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$lan = New-Object Net.Sockets.TcpClient; try { $ar = $lan.BeginConnect('192.168.1.139', 1080, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) { $lan.EndConnect($ar); Write-Host ' [OK] LAN Proxy (192.168.1.139:1080): CONNECTED' -ForegroundColor Green } else { Write-Host ' [FAIL] LAN Proxy (192.168.1.139:1080): TIMEOUT' -ForegroundColor Yellow } } catch { Write-Host ' [FAIL] LAN Proxy: NOT ANSWERING' -ForegroundColor Red } finally { $lan.Close() }"

echo.
echo [2/3] Testing Samba File Share on port 445...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$smb = New-Object Net.Sockets.TcpClient; try { $ar = $smb.BeginConnect('192.168.1.139', 445, $null, $null); if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) { $smb.EndConnect($ar); Write-Host ' [OK] LAN Samba (192.168.1.139:445): CONNECTED' -ForegroundColor Green } else { Write-Host ' [FAIL] LAN Samba: TIMEOUT' -ForegroundColor Yellow } } catch { Write-Host ' [FAIL] LAN Samba: NOT ANSWERING' -ForegroundColor Red } finally { $smb.Close() }"

echo.
echo [3/3] Testing Local AceStream Engine on port 6878...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $v = Invoke-RestMethod -Uri 'http://127.0.0.1:6878/webui/api/service?method=get_version' -TimeoutSec 2 -ErrorAction Stop; Write-Host ' [OK] Local AceStream Engine API (127.0.0.1:6878): READY' -ForegroundColor Green } catch { Write-Host ' [WARNING] Local AceStream API (127.0.0.1:6878) not answering. Launch via restart_acestream_warp.bat.' -ForegroundColor Yellow }"

echo.
echo ========================================================
pause
exit /b 0

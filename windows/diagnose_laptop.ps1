# Comprehensive Diagnostic and Repair Tool (Drive Z: + AceStream + WARP) - WarpAcePi
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "       DIAGNOSTIC AND REPAIR - WarpAcePi" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$TailscaleIP = "100.89.165.79"
$LanIP = "192.168.1.139"
$ProxyPort = 1080

# ------------------------------------------------------------------------------
# 1. CHECK NETWORK DRIVE Z:
# ------------------------------------------------------------------------------
Write-Host "[1/4] Checking Network Drive Z:..." -ForegroundColor Yellow

$zDrive = Get-PSDrive -Name "Z" -ErrorAction SilentlyContinue
$netZ = Get-CimInstance -ClassName Win32_NetworkConnection -ErrorAction SilentlyContinue | Where-Object { $_.LocalName -eq "Z:" }

if ($zDrive) {
    Write-Host "      -> [OK] Drive Z: is connected and mounted." -ForegroundColor Green
    Write-Host "         Root: $($zDrive.Root)" -ForegroundColor Gray
    if ($zDrive.DisplayRoot) {
        Write-Host "         Remote Path: $($zDrive.DisplayRoot)" -ForegroundColor Gray
    }
} elseif ($netZ) {
    Write-Host "      -> [WARNING] Drive Z: is registered but DISCONNECTED." -ForegroundColor Red
    Write-Host "         Remote Path: $($netZ.RemoteName)" -ForegroundColor Yellow
    Write-Host "         State: $($netZ.ConnectionState)" -ForegroundColor Yellow
    
    # Try reconnecting
    Write-Host "         Attempting to reconnect Drive Z:..." -ForegroundColor Cyan
    try {
        $reconn = Start-Process -FilePath "net.exe" -ArgumentList "use Z: $($netZ.RemoteName) /persistent:yes" -NoNewWindow -Wait -PassThru
        if ($reconn.ExitCode -eq 0) {
            Write-Host "         -> [REPAIRED] Drive Z: reconnected successfully." -ForegroundColor Green
        } else {
            Write-Host "         -> [FAILED] Could not automatically reconnect to $($netZ.RemoteName)." -ForegroundColor Red
        }
    } catch {
        Write-Host "         -> [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "      -> [NOT DETECTED] Drive Z: is not mapped on this computer." -ForegroundColor Red
    Write-Host "         Mapped network drives on this system:" -ForegroundColor Gray
    $allNets = Get-CimInstance -ClassName Win32_NetworkConnection -ErrorAction SilentlyContinue
    if ($allNets) {
        foreach ($net in $allNets) {
            Write-Host "           * $($net.LocalName) -> $($net.RemoteName) ($($net.ConnectionState))" -ForegroundColor Cyan
        }
    } else {
        Write-Host "           (No network drives mapped on this machine)" -ForegroundColor Gray
    }
}

Write-Host ""

# ------------------------------------------------------------------------------
# 2. CHECK LOCAL ACESTREAM ENGINE
# ------------------------------------------------------------------------------
Write-Host "[2/4] Checking local AceStream Engine..." -ForegroundColor Yellow

$aceProc = Get-Process -Name "ace_engine" -ErrorAction SilentlyContinue

if ($aceProc) {
    Write-Host "      -> [OK] ace_engine.exe is running (PID: $($aceProc.Id))." -ForegroundColor Green
    
    # Test local API
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:6878/webui/api/service?method=get_version" -TimeoutSec 3 -ErrorAction Stop
        Write-Host "      -> [OK] AceStream API answering on 127.0.0.1:6878 (Version: $($resp.result.version))." -ForegroundColor Green
    } catch {
        Write-Host "      -> [WARNING] ace_engine.exe is running but API at 127.0.0.1:6878 is not answering." -ForegroundColor Yellow
    }

    # Test sample stream
    Write-Host "      -> Testing stream response on 127.0.0.1:6878..." -ForegroundColor Cyan
    try {
        $req = [System.Net.WebRequest]::Create("http://127.0.0.1:6878/ace/getstream?id=cc108ae39f92c48f6c946763047bd1c9b7b7d889")
        $req.Timeout = 4000
        $sResp = $req.GetResponse()
        Write-Host "      -> [OK] Engine responded with HTTP: $([int]$sResp.StatusCode)" -ForegroundColor Green
        $sResp.Close()
    } catch [System.Net.WebException] {
        if ($_.Response) {
            $errStream = $_.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errStream)
            $errBody = $reader.ReadToEnd()
            Write-Host "      -> [ENGINE RESPONSE] HTTP $([int]$_.Response.StatusCode): $errBody" -ForegroundColor Red
        } else {
            Write-Host "      -> [NETWORK ERROR] No response from stream: $($_.Message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "      -> [ERROR] $($_.Message)" -ForegroundColor Red
    }

    # Show last lines of acestream.log
    $logPath = "$env:APPDATA\ACEStream\engine\acestream.log"
    if (Test-Path $logPath) {
        Write-Host "      -> Last lines from acestream.log:" -ForegroundColor Gray
        Get-Content $logPath -Tail 8 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    }
} else {
    Write-Host "      -> [FAIL] ace_engine.exe is NOT running." -ForegroundColor Red
    Write-Host "         Starting AceStream with WARP shield..." -ForegroundColor Cyan
    
    $restartBat = Join-Path $PSScriptRoot "restart_acestream_warp.bat"
    if (Test-Path $restartBat) {
        Start-Process -FilePath $restartBat
        Write-Host "         -> Launcher executed." -ForegroundColor Green
    } else {
        Write-Host "         -> restart_acestream_warp.bat not found in $PSScriptRoot" -ForegroundColor Red
    }
}

Write-Host ""

# ------------------------------------------------------------------------------
# 3. CHECK RASPBERRY PI WARP GATEWAY
# ------------------------------------------------------------------------------
Write-Host "[3/4] Checking Raspberry Pi (WARP Gateway)..." -ForegroundColor Yellow

$ActiveProxy = $null

# Test Tailscale
$tcp = New-Object Net.Sockets.TcpClient
try {
    $ar = $tcp.BeginConnect($TailscaleIP, $ProxyPort, $null, $null)
    if ($ar.AsyncWaitHandle.WaitOne(2500, $false)) {
        $tcp.EndConnect($ar)
        Write-Host "      -> [OK] Port 1080 answering via Tailscale ($TailscaleIP)." -ForegroundColor Green
        $ActiveProxy = "$TailscaleIP`:$ProxyPort"
    } else {
        Write-Host "      -> [TIMEOUT] Timeout connecting to Tailscale ($TailscaleIP`:$ProxyPort)." -ForegroundColor Yellow
    }
} catch {
    Write-Host "      -> [FAIL] Connection error to Tailscale: $($_.Exception.Message)" -ForegroundColor Yellow
} finally {
    $tcp.Close()
}

# Test LAN if Tailscale failed
if (-not $ActiveProxy) {
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $ar = $tcp.BeginConnect($LanIP, $ProxyPort, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) {
            $tcp.EndConnect($ar)
            Write-Host "      -> [OK] Port 1080 answering via LAN ($LanIP)." -ForegroundColor Green
            $ActiveProxy = "$LanIP`:$ProxyPort"
        } else {
            Write-Host "      -> [TIMEOUT] Timeout connecting to LAN ($LanIP`:$ProxyPort)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      -> [FAIL] Connection error to LAN: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        $tcp.Close()
    }
}

# If proxy alive, validate WARP trace
if ($ActiveProxy) {
    Write-Host "      -> Testing Cloudflare WARP via proxy $ActiveProxy..." -ForegroundColor Cyan
    try {
        $trace = (Invoke-WebRequest -Uri "https://cloudflare.com/cdn-cgi/trace" -Proxy "http://$ActiveProxy" -TimeoutSec 5 -ErrorAction Stop).Content
        if ($trace -match "warp=on") {
            Write-Host "      -> [OK] Cloudflare WARP is ACTIVE (warp=on)." -ForegroundColor Green
            ($trace -split "`n" | Where-Object { $_ -match "^(ip|loc|warp)=" }) | ForEach-Object {
                Write-Host "         $_" -ForegroundColor Gray
            }
        } else {
            Write-Host "      -> [WARNING] Proxy active but Cloudflare does not report warp=on." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      -> [WARNING] WARP trace error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "      -> [ALERT] Raspberry Pi did not answer on port 1080." -ForegroundColor Red
    Write-Host "         Check that RPi is powered on and Tailscale is connected." -ForegroundColor Yellow
}

Write-Host ""

# ------------------------------------------------------------------------------
# 4. CHECK LOCAL TAILSCALE
# ------------------------------------------------------------------------------
Write-Host "[4/4] Checking local Tailscale client..." -ForegroundColor Yellow

$tsService = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
if ($tsService) {
    if ($tsService.Status -eq "Running") {
        Write-Host "      -> [OK] Tailscale service is RUNNING." -ForegroundColor Green
    } else {
        Write-Host "      -> [WARNING] Tailscale installed, status: $($tsService.Status)" -ForegroundColor Yellow
    }
} else {
    Write-Host "      -> [INFO] Tailscale Windows service not detected (or user-mode)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "                     SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

if (-not $zDrive -and -not $netZ) {
    Write-Host " [!] Drive Z: is not mapped." -ForegroundColor Yellow
    Write-Host "     Run: windows\connect_z_drive_rpi.bat to map the Raspberry Pi share." -ForegroundColor White
    Write-Host ""
}

if (-not $aceProc) {
    Write-Host " [!] AceStream was not running." -ForegroundColor Yellow
    Write-Host "     Launch command sent with WARP shield." -ForegroundColor Green
    Write-Host ""
}

Write-Host "Diagnostics completed." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

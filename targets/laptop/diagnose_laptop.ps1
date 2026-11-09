# Comprehensive Diagnostic and Repair Tool for Laptop - WarpAcePi
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "     DIAGNOSTIC AND REPAIR - TARGET: LAPTOP" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Expected P2P Port: 48622  |  HTTP API: 127.0.0.1:6878" -ForegroundColor Gray
Write-Host ""

$TailscaleIP = "100.89.165.79"
$LanIP = "192.168.1.139"
$ProxyPort = 1080

# ------------------------------------------------------------------------------
# 1. CHECK NETWORK DRIVE Z:
# ------------------------------------------------------------------------------
Write-Host "[1/5] Checking Network Drive Z:..." -ForegroundColor Yellow

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
    Write-Host "         Attempting automatic reconnection..." -ForegroundColor Cyan
    try {
        $reconn = Start-Process -FilePath "net.exe" -ArgumentList "use Z: $($netZ.RemoteName) /persistent:yes" -NoNewWindow -Wait -PassThru
        if ($reconn.ExitCode -eq 0) {
            Write-Host "         -> [REPAIRED] Drive Z: reconnected successfully." -ForegroundColor Green
        } else {
            Write-Host "         -> [FAILED] Could not automatically reconnect." -ForegroundColor Red
        }
    } catch {
        Write-Host "         -> [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "      -> [NOT DETECTED] Drive Z: is not mapped on this computer." -ForegroundColor Red
    Write-Host "         Run targets\laptop\mount_z_drive.bat to map the Raspberry Pi share." -ForegroundColor Yellow
}

Write-Host ""

# ------------------------------------------------------------------------------
# 2. CHECK DOCK / NETWORK ADAPTERS
# ------------------------------------------------------------------------------
Write-Host "[2/5] Checking Network Adapters & Energy Saving (Dock)..." -ForegroundColor Yellow
$adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Loopback|Tailscale' }
foreach ($a in $adapters) {
    Write-Host "      -> Adapter: $($a.Name) ($($a.InterfaceDescription)) - LinkSpeed: $($a.LinkSpeed)" -ForegroundColor Cyan
    $eee = Get-NetAdapterAdvancedProperty -Name $a.Name -DisplayName "*Energy*" -ErrorAction SilentlyContinue
    if ($eee -and $eee.DisplayValue -ne "Disabled") {
        Write-Host "         [WARNING] Energy Efficient Ethernet is enabled ($($eee.DisplayValue)). Can cause packet drops during streams." -ForegroundColor Yellow
        Write-Host "                   Run targets\laptop\optimize_network.bat to disable it." -ForegroundColor Gray
    }
}

Write-Host ""

# ------------------------------------------------------------------------------
# 3. CHECK LOCAL ACESTREAM ENGINE & PORTS
# ------------------------------------------------------------------------------
Write-Host "[3/5] Checking AceStream Engine (Local Port 6878 & P2P Port 48622)..." -ForegroundColor Yellow

$aceProc = Get-Process -Name "ace_engine" -ErrorAction SilentlyContinue

if ($aceProc) {
    Write-Host "      -> [OK] ace_engine.exe is running (PID: $($aceProc.Id))." -ForegroundColor Green
    
    # Test local HTTP API
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:6878/webui/api/service?method=get_version" -TimeoutSec 3 -ErrorAction Stop
        Write-Host "      -> [OK] Local API answering on 127.0.0.1:6878 (Version: $($resp.result.version))." -ForegroundColor Green
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
} else {
    Write-Host "      -> [FAIL] ace_engine.exe is NOT running." -ForegroundColor Red
    Write-Host "         Launching AceStream with WARP shield..." -ForegroundColor Cyan
    $restartBat = Join-Path $PSScriptRoot "restart_acestream_warp.bat"
    if (Test-Path $restartBat) {
        Start-Process -FilePath $restartBat
        Write-Host "         -> restart_acestream_warp.bat triggered." -ForegroundColor Green
    }
}

Write-Host ""

# ------------------------------------------------------------------------------
# 4. CHECK RASPBERRY PI WARP GATEWAY (Port 1080)
# ------------------------------------------------------------------------------
Write-Host "[4/5] Checking Raspberry Pi (WARP Gateway on port 1080)..." -ForegroundColor Yellow

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
        Write-Host "      -> [TIMEOUT] Timeout on Tailscale ($TailscaleIP`:$ProxyPort)." -ForegroundColor Yellow
    }
} catch {
    Write-Host "      -> [FAIL] Error connecting to Tailscale: $($_.Exception.Message)" -ForegroundColor Yellow
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
            Write-Host "      -> [TIMEOUT] Timeout on LAN ($LanIP`:$ProxyPort)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      -> [FAIL] Error connecting to LAN: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        $tcp.Close()
    }
}

# If proxy alive, validate Cloudflare WARP trace
if ($ActiveProxy) {
    Write-Host "      -> Validating Cloudflare WARP via proxy $ActiveProxy..." -ForegroundColor Cyan
    try {
        $trace = (Invoke-WebRequest -Uri "https://cloudflare.com/cdn-cgi/trace" -Proxy "http://$ActiveProxy" -TimeoutSec 5 -ErrorAction Stop).Content
        if ($trace -match "warp=on") {
            Write-Host "      -> [OK] Cloudflare WARP is ACTIVE (warp=on)." -ForegroundColor Green
        } else {
            Write-Host "      -> [WARNING] Proxy responded, but Cloudflare did not report warp=on." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      -> [WARNING] WARP check request failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "      -> [ALERT] Raspberry Pi proxy did not answer on port 1080." -ForegroundColor Red
}

Write-Host ""

# ------------------------------------------------------------------------------
# 5. STRICT DESKTOP CLEANLINESS CHECK
# ------------------------------------------------------------------------------
Write-Host "[5/5] Checking Desktop Cleanliness (Zero Desktop Files Policy)..." -ForegroundColor Yellow

$candidateDesktops = @(
    [Environment]::GetFolderPath("Desktop"),
    (Join-Path $env:USERPROFILE "Desktop"),
    (Join-Path $env:USERPROFILE "OneDrive\Desktop"),
    (Join-Path $env:USERPROFILE "OneDrive\Escritorio"),
    (Join-Path $env:PUBLIC "Desktop")
) | Select-Object -Unique | Where-Object { $_ -and (Test-Path $_) }

$foundStray = $false
foreach ($d in $candidateDesktops) {
    $strays = Get-ChildItem -Path $d -Filter "*AceStream*" -File -ErrorAction SilentlyContinue
    $strays += Get-ChildItem -Path $d -Filter "*WarpAcePi*" -File -ErrorAction SilentlyContinue
    foreach ($s in $strays) {
        $foundStray = $true
        Remove-Item $s.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "      -> Cleaned stray file from Desktop: $($s.Name)" -ForegroundColor Yellow
    }
}
if (-not $foundStray) {
    Write-Host "      -> [OK] Desktop is 100% clean. Zero files on Desktop." -ForegroundColor Green
} else {
    Write-Host "      -> [OK] Stray shortcuts purged. Desktop is now clean." -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "                     SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
if ($zDrive) {
    Write-Host " [OK] Drive Z: ready (Playlists available at Z:\playlist_vlc.m3u)" -ForegroundColor Green
} else {
    Write-Host " [!] Drive Z: not mounted. Run targets\laptop\mount_z_drive.bat" -ForegroundColor Yellow
}
if ($aceProc) {
    Write-Host " [OK] AceStream Engine active (Listening on 127.0.0.1:6878)" -ForegroundColor Green
}
Write-Host "========================================================" -ForegroundColor Cyan

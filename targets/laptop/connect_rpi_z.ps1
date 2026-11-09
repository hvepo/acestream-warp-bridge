# Map Network Drive Z: to Raspberry Pi (WarpAcePi)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "      MAP NETWORK DRIVE Z: TO RASPBERRY PI" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$LanIP = "192.168.1.139"
$TailscaleIP = "100.89.165.79"
$RpiHost = "rpi"

# 1. Test SMB port 445 connectivity
Write-Host "[1/3] Locating Raspberry Pi on the network..." -ForegroundColor Yellow

$targets = @(
    @{ Name = "LAN ($LanIP)"; IP = $LanIP },
    @{ Name = "Tailscale ($TailscaleIP)"; IP = $TailscaleIP },
    @{ Name = "Hostname ($RpiHost)"; IP = $RpiHost }
)

$activeTarget = $null

foreach ($t in $targets) {
    Write-Host "      Testing $($t.Name)..." -NoNewline
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $ar = $tcp.BeginConnect($t.IP, 445, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(2000, $false)) {
            $tcp.EndConnect($ar)
            Write-Host " [CONNECTED]" -ForegroundColor Green
            $activeTarget = $t.IP
            break
        } else {
            Write-Host " [TIMEOUT]" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " [NO RESPONSE]" -ForegroundColor Red
    } finally {
        $tcp.Close()
    }
}

if (-not $activeTarget) {
    Write-Host ""
    Write-Host " [ERROR] Could not connect to Raspberry Pi on SMB port 445." -ForegroundColor Red
    Write-Host " Possible causes:" -ForegroundColor Yellow
    Write-Host " 1. Samba service is not installed or running on Raspberry Pi." -ForegroundColor Gray
    Write-Host " 2. Windows network profile is set to 'Public' (blocks SMB discovery)." -ForegroundColor Gray
    Write-Host " 3. Tailscale is not running on this PC." -ForegroundColor Gray
    Write-Host ""
    
    $netProfiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    foreach ($p in $netProfiles) {
        if ($p.NetworkCategory -eq "Public") {
            Write-Host " [WARNING] Network adapter '$($p.Name)' is set to Public." -ForegroundColor Yellow
            $change = Read-Host " Switch to Private network to unblock SMB? (Y/N)"
            if ($change -eq "Y" -or $change -eq "y") {
                try {
                    Set-NetConnectionProfile -Name $p.Name -NetworkCategory Private -ErrorAction Stop
                    Write-Host " -> [OK] Changed to Private network." -ForegroundColor Green
                } catch {
                    Write-Host " -> [WARNING] Administrator rights required." -ForegroundColor Yellow
                }
            }
        }
    }
    exit 1
}

Write-Host ""
Write-Host "[2/3] Raspberry Pi detected at: $activeTarget" -ForegroundColor Green

# 2. Check existing Z: mapping
Write-Host "[3/3] Configuring Network Drive Z:..." -ForegroundColor Yellow

$existingZ = Get-PSDrive -Name "Z" -ErrorAction SilentlyContinue
$netZ = Get-CimInstance -ClassName Win32_NetworkConnection -ErrorAction SilentlyContinue | Where-Object { $_.LocalName -eq "Z:" }

if ($existingZ -or $netZ) {
    Write-Host "      Disconnecting previous mapping for Z:..." -ForegroundColor Cyan
    net use Z: /delete /yes 2>$null | Out-Null
}

$shareName = "playlists"
if (-not (Test-Path "\\$activeTarget\$shareName")) {
    if (Test-Path "\\$activeTarget\share") {
        $shareName = "share"
    }
}

$fullPath = "\\$activeTarget\$shareName"
Write-Host " Mapping Z: to $fullPath..." -ForegroundColor Cyan

$mapResult = net use Z: "$fullPath" /persistent:yes 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host " Authentication requested by Raspberry Pi." -ForegroundColor Yellow
    $user = Read-Host " Raspberry Pi username (default: hvepo)"
    if ([string]::IsNullOrWhiteSpace($user)) { $user = "hvepo" }
    
    $pass = Read-Host " Password for $user" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    
    $mapResult = net use Z: "$fullPath" "$plainPass" "/user:$user" /persistent:yes 2>&1
}

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host " [SUCCESS] Drive Z: mapped to Raspberry Pi ($fullPath)" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host " [FAILED] Could not map drive Z:." -ForegroundColor Red
    Write-Host " Details: $mapResult" -ForegroundColor Yellow
    exit 1
}

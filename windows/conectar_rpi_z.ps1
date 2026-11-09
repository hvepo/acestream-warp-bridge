# Conectar Unidad Z: a la Raspberry Pi
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "    CONECTAR UNIDAD Z: A LA RASPBERRY PI" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$LanIP = "192.168.1.139"
$TailscaleIP = "100.89.165.79"
$RpiHost = "rpi"

# 1. Probar conectividad al puerto SMB 445
Write-Host "[1/3] Buscando la Raspberry Pi en la red..." -ForegroundColor Yellow

$targets = @(
    @{ Name = "LAN ($LanIP)"; IP = $LanIP },
    @{ Name = "Tailscale ($TailscaleIP)"; IP = $TailscaleIP },
    @{ Name = "Hostname ($RpiHost)"; IP = $RpiHost }
)

$activeTarget = $null

foreach ($t in $targets) {
    Write-Host "      Probando $($t.Name)..." -NoNewline
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $ar = $tcp.BeginConnect($t.IP, 445, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(2000, $false)) {
            $tcp.EndConnect($ar)
            Write-Host " [CONECTADO]" -ForegroundColor Green
            $activeTarget = $t.IP
            break
        } else {
            Write-Host " [TIMEOUT]" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " [NO RESPONDE]" -ForegroundColor Red
    } finally {
        $tcp.Close()
    }
}

if (-not $activeTarget) {
    Write-Host ""
    Write-Host " [ERROR] No se pudo contactar con la Raspberry Pi en el puerto SMB (445)." -ForegroundColor Red
    Write-Host " Posibles causas:" -ForegroundColor Yellow
    Write-Host " 1. La Raspberry Pi no tiene Samba (servidor de archivos) instalado o esta parado." -ForegroundColor Gray
    Write-Host " 2. El portatil esta conectado a una red WiFi clasificada como 'Publica'." -ForegroundColor Gray
    Write-Host " 3. Tailscale no esta conectado en el portatil." -ForegroundColor Gray
    Write-Host ""
    
    # Comprobar perfil de red
    $netProfiles = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    foreach ($p in $netProfiles) {
        if ($p.NetworkCategory -eq "Public") {
            Write-Host " [AVISO] Tu conexion WiFi '$($p.Name)' esta configurada como Red Publica." -ForegroundColor Yellow
            Write-Host "        Windows bloquea el acceso a archivos de red local en redes publicas." -ForegroundColor Yellow
            $cambiar = Read-Host " Deseas cambiarla a Red Privada para desbloquear la conexion con la RPi? (S/N)"
            if ($cambiar -eq "S" -or $cambiar -eq "s") {
                try {
                    Set-NetConnectionProfile -Name $p.Name -NetworkCategory Private -ErrorAction Stop
                    Write-Host " -> [OK] Cambiado a Red Privada exitosamente." -ForegroundColor Green
                } catch {
                    Write-Host " -> [AVISO] Ejecuta este script como Administrador para cambiar el tipo de red." -ForegroundColor Yellow
                }
            }
        }
    }
    Write-Host ""
    Write-Host "Pulsa una tecla para continuar..." -ForegroundColor Gray
    [Console]::ReadKey($true) | Out-Null
    exit 1
}

Write-Host ""
Write-Host "[2/3] Raspberry Pi detectada en: $activeTarget" -ForegroundColor Green
Write-Host "      Consultando carpetas compartidas..." -ForegroundColor Cyan

# Ver recursos disponibles
$sharesOutput = net view "\\$activeTarget" 2>&1
$sharesOutput | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }

Write-Host ""
Write-Host "[3/3] Configurando Unidad Z:..." -ForegroundColor Yellow

# Comprobar si Z: ya esta en uso
$existingZ = Get-PSDrive -Name "Z" -ErrorAction SilentlyContinue
$netZ = Get-CimInstance -ClassName Win32_NetworkConnection -ErrorAction SilentlyContinue | Where-Object { $_.LocalName -eq "Z:" }

if ($existingZ -or $netZ) {
    Write-Host "      Desconectando mapeo anterior de Z:..." -ForegroundColor Cyan
    net use Z: /delete /yes 2>$null | Out-Null
}

# Preguntar nombre de la carpeta compartida o intentar conectar
Write-Host ""
Write-Host " (Pulsa Enter para autodeteccion de 'playlists' o 'share'):" -ForegroundColor Gray
$shareName = Read-Host " Nombre de la carpeta"
if ([string]::IsNullOrWhiteSpace($shareName)) {
    if (Test-Path "\\$activeTarget\playlists") {
        $shareName = "playlists"
    } else {
        $shareName = "share"
    }
}

$fullPath = "\\$activeTarget\$shareName"
Write-Host " Conectando Z: a $fullPath..." -ForegroundColor Cyan

# Intentar mapear primero sin credenciales
$mapResult = net use Z: "$fullPath" /persistent:yes 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host " Se requieren credenciales de la Raspberry Pi." -ForegroundColor Yellow
    $user = Read-Host " Usuario de la RPi (por defecto: hvepo)"
    if ([string]::IsNullOrWhiteSpace($user)) { $user = "hvepo" }
    
    $pass = Read-Host " Contraseña de la RPi ($user)" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    
    $mapResult = net use Z: "$fullPath" "$plainPass" "/user:$user" /persistent:yes 2>&1
}

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host " [EXITO] Unidad Z: conectada a la Raspberry Pi ($fullPath)" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Start-Process "explorer.exe" -ArgumentList "Z:\"
} else {
    Write-Host ""
    Write-Host " [FALLO] No se pudo conectar la unidad Z:." -ForegroundColor Red
    Write-Host " Detalle: $mapResult" -ForegroundColor Yellow
}

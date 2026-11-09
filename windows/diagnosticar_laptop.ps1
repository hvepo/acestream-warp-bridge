# Diagnostico y Reparacion Integral para Portatil (Unidad Z: + AceStream + WARP)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "      DIAGNOSTICO Y REPARACION - PORTATIL" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$TailscaleIP = "100.89.165.79"
$LanIP = "192.168.1.139"
$ProxyPort = 1080

# ------------------------------------------------------------------------------
# 1. COMPROBAR UNIDAD Z:
# ------------------------------------------------------------------------------
Write-Host "[1/4] Comprobando Unidad Z:..." -ForegroundColor Yellow

$zDrive = Get-PSDrive -Name "Z" -ErrorAction SilentlyContinue
$netZ = Get-CimInstance -ClassName Win32_NetworkConnection -ErrorAction SilentlyContinue | Where-Object { $_.LocalName -eq "Z:" }

if ($zDrive) {
    Write-Host "      -> [OK] La unidad Z: existe y esta montada." -ForegroundColor Green
    Write-Host "         Ruta / Raiz: $($zDrive.Root)" -ForegroundColor Gray
    if ($zDrive.DisplayRoot) {
        Write-Host "         Destino Red: $($zDrive.DisplayRoot)" -ForegroundColor Gray
    }
} elseif ($netZ) {
    Write-Host "      -> [AVISO] La unidad Z: esta registrada pero DESCONECTADA." -ForegroundColor Red
    Write-Host "         Destino Red: $($netZ.RemoteName)" -ForegroundColor Yellow
    Write-Host "         Estado: $($netZ.ConnectionState)" -ForegroundColor Yellow
    
    # Intentar reconectar
    Write-Host "         Intentando reconectar unidad Z:..." -ForegroundColor Cyan
    try {
        $reconn = Start-Process -FilePath "net.exe" -ArgumentList "use Z: $($netZ.RemoteName) /persistent:yes" -NoNewWindow -Wait -PassThru
        if ($reconn.ExitCode -eq 0) {
            Write-Host "         -> [REPARADO] Unidad Z: reconectada con exito." -ForegroundColor Green
        } else {
            Write-Host "         -> [FALLO] No se pudo reconectar automaticamente a $($netZ.RemoteName)." -ForegroundColor Red
        }
    } catch {
        Write-Host "         -> [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "      -> [NO DETECTADA] La unidad Z: no existe en este portatil." -ForegroundColor Red
    Write-Host "         Mostrando todas las unidades de red disponibles:" -ForegroundColor Gray
    $allNets = Get-CimInstance -ClassName Win32_NetworkConnection -ErrorAction SilentlyContinue
    if ($allNets) {
        foreach ($net in $allNets) {
            Write-Host "           * $($net.LocalName) -> $($net.RemoteName) ($($net.ConnectionState))" -ForegroundColor Cyan
        }
    } else {
        Write-Host "           (No hay ninguna unidad de red mapeada en este equipo)" -ForegroundColor Gray
    }
}

Write-Host ""

# ------------------------------------------------------------------------------
# 2. COMPROBAR MOTOR ACESTREAM EN EL PORTATIL
# ------------------------------------------------------------------------------
Write-Host "[2/4] Comprobando Motor AceStream local..." -ForegroundColor Yellow

$aceProc = Get-Process -Name "ace_engine" -ErrorAction SilentlyContinue

if ($aceProc) {
    Write-Host "      -> [OK] ace_engine.exe esta en ejecucion (PID: $($aceProc.Id))." -ForegroundColor Green
    
    # Probar API local
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:6878/webui/api/service?method=get_version" -TimeoutSec 3 -ErrorAction Stop
        Write-Host "      -> [OK] API AceStream responde (Version: $($resp.result.version))." -ForegroundColor Green
    } catch {
        Write-Host "      -> [AVISO] ace_engine.exe corre pero la API 127.0.0.1:6878 no responde." -ForegroundColor Yellow
    }

    # Probar peticion de stream de prueba para diagnosticar error de VLC
    Write-Host "      -> Probando respuesta de stream en 127.0.0.1:6878..." -ForegroundColor Cyan
    try {
        $req = [System.Net.WebRequest]::Create("http://127.0.0.1:6878/ace/getstream?id=cc108ae39f92c48f6c946763047bd1c9b7b7d889")
        $req.Timeout = 4000
        $sResp = $req.GetResponse()
        Write-Host "      -> [OK] El motor responde al stream con estado HTTP: $([int]$sResp.StatusCode)" -ForegroundColor Green
        $sResp.Close()
    } catch [System.Net.WebException] {
        if ($_.Response) {
            $errStream = $_.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errStream)
            $errBody = $reader.ReadToEnd()
            Write-Host "      -> [ERROR MOTOR] HTTP $([int]$_.Response.StatusCode): $errBody" -ForegroundColor Red
        } else {
            Write-Host "      -> [ERROR RED] No se pudo obtener respuesta del stream: $($_.Message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "      -> [ERROR] $($_.Message)" -ForegroundColor Red
    }

    # Mostrar ultimas lineas de acestream.log
    $logPath = "$env:APPDATA\ACEStream\engine\acestream.log"
    if (Test-Path $logPath) {
        Write-Host "      -> Ultimas lineas del registro de AceStream (acestream.log):" -ForegroundColor Gray
        Get-Content $logPath -Tail 8 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    }
} else {
    Write-Host "      -> [FALLO] ace_engine.exe NO esta corriendo en este portatil." -ForegroundColor Red
    Write-Host "         Iniciando AceStream con escudo WARP..." -ForegroundColor Cyan
    
    $restartBat = Join-Path $PSScriptRoot "Reiniciar AceStream (WARP).bat"
    if (Test-Path $restartBat) {
        Start-Process -FilePath $restartBat
        Write-Host "         -> Lanzador ejecutado." -ForegroundColor Green
    } else {
        Write-Host "         -> No se encontro Reiniciar AceStream (WARP).bat en $PSScriptRoot" -ForegroundColor Red
    }
}

Write-Host ""

# ------------------------------------------------------------------------------
# 3. COMPROBAR ESCUDO WARP (RASPBERRY PI)
# ------------------------------------------------------------------------------
Write-Host "[3/4] Comprobando pasarela Raspberry Pi (WARP)..." -ForegroundColor Yellow

$ActiveProxy = $null

# Probar Tailscale
$tcp = New-Object Net.Sockets.TcpClient
try {
    $ar = $tcp.BeginConnect($TailscaleIP, $ProxyPort, $null, $null)
    if ($ar.AsyncWaitHandle.WaitOne(2500, $false)) {
        $tcp.EndConnect($ar)
        Write-Host "      -> [OK] Puerto 1080 responde via Tailscale ($TailscaleIP)." -ForegroundColor Green
        $ActiveProxy = "$TailscaleIP`:$ProxyPort"
    } else {
        Write-Host "      -> [FALLO] Timeout conectando a Tailscale ($TailscaleIP`:$ProxyPort)." -ForegroundColor Yellow
    }
} catch {
    Write-Host "      -> [FALLO] Error conectando a Tailscale: $($_.Exception.Message)" -ForegroundColor Yellow
} finally {
    $tcp.Close()
}

# Probar LAN si Tailscale fallo
if (-not $ActiveProxy) {
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $ar = $tcp.BeginConnect($LanIP, $ProxyPort, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne(1500, $false)) {
            $tcp.EndConnect($ar)
            Write-Host "      -> [OK] Puerto 1080 responde via LAN ($LanIP)." -ForegroundColor Green
            $ActiveProxy = "$LanIP`:$ProxyPort"
        } else {
            Write-Host "      -> [FALLO] Timeout conectando a LAN ($LanIP`:$ProxyPort)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      -> [FALLO] Error conectando a LAN: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        $tcp.Close()
    }
}

# Si hay proxy, validar WARP trace
if ($ActiveProxy) {
    Write-Host "      -> Probando Cloudflare WARP a traves del proxy $ActiveProxy..." -ForegroundColor Cyan
    try {
        $trace = (Invoke-WebRequest -Uri "https://cloudflare.com/cdn-cgi/trace" -Proxy "http://$ActiveProxy" -TimeoutSec 5 -ErrorAction Stop).Content
        if ($trace -match "warp=on") {
            Write-Host "      -> [OK] Cloudflare WARP esta ACTIVO (warp=on)." -ForegroundColor Green
            ($trace -split "`n" | Where-Object { $_ -match "^(ip|loc|warp)=" }) | ForEach-Object {
                Write-Host "         $_" -ForegroundColor Gray
            }
        } else {
            Write-Host "      -> [AVISO] Proxy activo pero Cloudflare no reporta warp=on." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      -> [AVISO] Error al verificar traza WARP: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "      -> [ALERTA] La Raspberry Pi no responde en el puerto 1080." -ForegroundColor Red
    Write-Host "         Comprueba que la RPi este encendida y Tailscale conectado." -ForegroundColor Yellow
}

Write-Host ""

# ------------------------------------------------------------------------------
# 4. COMPROBAR TAILSCALE LOCAL
# ------------------------------------------------------------------------------
Write-Host "[4/4] Comprobando Tailscale en el portatil..." -ForegroundColor Yellow

$tsService = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
if ($tsService) {
    if ($tsService.Status -eq "Running") {
        Write-Host "      -> [OK] Servicio Tailscale esta EN EJECUCION." -ForegroundColor Green
    } else {
        Write-Host "      -> [AVISO] Servicio Tailscale instalado pero estado: $($tsService.Status)" -ForegroundColor Yellow
    }
} else {
    Write-Host "      -> [INFO] No se detecto el servicio Tailscale de Windows (o usa modo usuario)." -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "                      RESUMEN" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

if (-not $zDrive -and -not $netZ) {
    Write-Host " [!] CAUSA MAS PROBABLE DE QUE EL CANAL NO SALGA EN Z:" -ForegroundColor Yellow
    Write-Host "     El portatil NO tiene mapeada la unidad de red Z: que si tiene tu PC." -ForegroundColor White
    Write-Host "     Si Z: apunta a una carpeta compartida de tu PC fijo:" -ForegroundColor White
    Write-Host "     Ejecuta en PowerShell del portatil:" -ForegroundColor Cyan
    Write-Host "     net use Z: \\IP_O_NOMBRE_DE_TU_PC\CarpetaCompartida /persistent:yes" -ForegroundColor Cyan
    Write-Host ""
}

if (-not $aceProc) {
    Write-Host " [!] AceStream no estaba arrancado en el portatil." -ForegroundColor Yellow
    Write-Host "     Se ha enviado la orden de inicio con el escudo WARP." -ForegroundColor Green
    Write-Host ""
}

Write-Host "Diagnostico finalizado." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

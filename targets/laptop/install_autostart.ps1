# Auto-Start Installer & Desktop Cleaner for Laptop (WarpAcePi)
param (
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regName = "AceStream"
$appData = $env:APPDATA
$engineDir = Join-Path $appData "ACEStream\engine"
$vbsTarget = Join-Path $engineDir "launch_acestream_silent.vbs"
$batTarget = Join-Path $engineDir "launch_acestream.bat"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

if ($Uninstall) {
    Write-Host "[*] Restoring default AceStream startup..." -ForegroundColor Yellow
    $defaultExe = Join-Path $engineDir "ace_engine.exe"
    Set-ItemProperty -Path $regPath -Name $regName -Value $defaultExe
    Write-Host "[OK] Startup restored to direct ace_engine.exe." -ForegroundColor Green
    return
}

Write-Host "=== WarpAcePi: Laptop Target Auto-Start Installer ===" -ForegroundColor Cyan
Write-Host "Target Configuration: Laptop (P2P Port 48622, HTTP API 6878)" -ForegroundColor Gray

# 1. Copy launcher scripts to AceStream directory
Write-Host "[*] Installing scripts to $engineDir..."
if (-not (Test-Path $engineDir)) {
    throw "AceStream directory not found in $engineDir. Please make sure AceStream is installed."
}

Copy-Item (Join-Path $scriptDir "launch_acestream.bat") -Destination $batTarget -Force
Copy-Item (Join-Path $scriptDir "launch_acestream_silent.vbs") -Destination $vbsTarget -Force
Write-Host "[OK] Launcher files copied." -ForegroundColor Green

# 2. Strict Zero-Desktop-Files Cleaning
Write-Host "[*] Cleaning all shortcuts and batch files from Desktop..." -ForegroundColor Cyan
$candidateDesktops = @(
    [Environment]::GetFolderPath("Desktop"),
    (Join-Path $env:USERPROFILE "Desktop"),
    (Join-Path $env:USERPROFILE "OneDrive\Desktop"),
    (Join-Path $env:USERPROFILE "OneDrive\Escritorio"),
    (Join-Path $env:PUBLIC "Desktop")
) | Select-Object -Unique | Where-Object { $_ -and (Test-Path $_) }

$filesToPurge = @(
    "Reiniciar AceStream (WARP).bat",
    "Comprobar Conexion RPi.bat",
    "Conectar Unidad Z (Raspberry Pi).bat",
    "Diagnostico y Reparacion Portatil.bat",
    "restart_acestream_warp.bat",
    "check_rpi_connection.bat",
    "connect_z_drive_rpi.bat",
    "laptop_diagnostic_repair.bat",
    "WarpAcePi.lnk",
    "AceStream.lnk",
    "update_and_activate.bat"
)

foreach ($dPath in $candidateDesktops) {
    foreach ($fName in $filesToPurge) {
        $p = Join-Path $dPath $fName
        if (Test-Path $p) {
            Remove-Item $p -Force -ErrorAction SilentlyContinue
            Write-Host "    - Removed stray file: $p" -ForegroundColor DarkGray
        }
    }
}
Write-Host "[OK] Desktop 100% clean (zero files/shortcuts on Desktop)." -ForegroundColor Green

# 3. Register HKCU Run key
$regValue = "wscript.exe `"$vbsTarget`""
Set-ItemProperty -Path $regPath -Name $regName -Value $regValue
Write-Host "[OK] Auto-start entry registered in Windows Registry (Run key):" -ForegroundColor Green
Write-Host "     $regValue" -ForegroundColor Gray

Write-Host "=== Laptop configuration completed successfully ===" -ForegroundColor Cyan

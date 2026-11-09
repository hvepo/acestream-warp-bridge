# Windows Auto-Start Installer for WarpAcePi
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

Write-Host "=== WarpAcePi: Windows Auto-Start Installer ===" -ForegroundColor Cyan

# 1. Copy launcher scripts to AceStream directory
Write-Host "[*] Copying scripts to $engineDir..."
if (-not (Test-Path $engineDir)) {
    throw "AceStream directory not found in $engineDir. Please make sure AceStream is installed."
}

Copy-Item (Join-Path $scriptDir "launch_acestream.bat") -Destination $batTarget -Force
Copy-Item (Join-Path $scriptDir "launch_acestream_silent.vbs") -Destination $vbsTarget -Force

# 2. Clean desktop variants (strictly zero files on desktop)
$candidateDesktops = @(
    [Environment]::GetFolderPath("Desktop"),
    (Join-Path $env:USERPROFILE "Desktop"),
    (Join-Path $env:USERPROFILE "OneDrive\Desktop"),
    (Join-Path $env:USERPROFILE "OneDrive\Escritorio")
) | Select-Object -Unique | Where-Object { Test-Path $_ }

foreach ($dPath in $candidateDesktops) {
    Remove-Item (Join-Path $dPath "Reiniciar AceStream (WARP).bat") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $dPath "Comprobar Conexion RPi.bat") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $dPath "restart_acestream_warp.bat") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $dPath "check_rpi_connection.bat") -Force -ErrorAction SilentlyContinue
}
Write-Host "[OK] Desktop cleaned (all tools remain strictly inside repository)." -ForegroundColor Green

# 3. Register HKCU Run key
$regValue = "wscript.exe `"$vbsTarget`""
Set-ItemProperty -Path $regPath -Name $regName -Value $regValue
Write-Host "[OK] Auto-start entry registered in Windows Registry: $regValue" -ForegroundColor Green

Write-Host "=== Installation completed successfully ===" -ForegroundColor Cyan

# Script de instalación para Windows: Registra el launcher inteligente en el inicio de Windows
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
    Write-Host "[*] Restaurando inicio predeterminado de AceStream..." -ForegroundColor Yellow
    $defaultExe = Join-Path $engineDir "ace_engine.exe"
    Set-ItemProperty -Path $regPath -Name $regName -Value $defaultExe
    Write-Host "[OK] Inicio restaurado a ace_engine.exe directo." -ForegroundColor Green
    return
}

Write-Host "=== Instalador AceStream WARP Launcher para Windows ===" -ForegroundColor Cyan

# 1. Copiar scripts al directorio de AceStream
Write-Host "[*] Copiando scripts a $engineDir..."
if (-not (Test-Path $engineDir)) {
    throw "No se encontro el directorio de AceStream en $engineDir. Asegurate de haber instalado AceStream."
}

Copy-Item (Join-Path $scriptDir "launch_acestream.bat") -Destination $batTarget -Force
Copy-Item (Join-Path $scriptDir "launch_acestream_silent.vbs") -Destination $vbsTarget -Force

# 2. Copiar accesos directos al escritorio
$desktopPath = [Environment]::GetFolderPath("Desktop")
Copy-Item (Join-Path $scriptDir "Reiniciar AceStream (WARP).bat") -Destination (Join-Path $desktopPath "Reiniciar AceStream (WARP).bat") -Force
Copy-Item (Join-Path $scriptDir "Comprobar Conexion RPi.bat") -Destination (Join-Path $desktopPath "Comprobar Conexion RPi.bat") -Force
Write-Host "[OK] Creados accesos directos en el Escritorio ('Reiniciar AceStream (WARP)' y 'Comprobar Conexion RPi')." -ForegroundColor Green

# 3. Registrar en HKCU Run
$regValue = "wscript.exe `"$vbsTarget`""
Set-ItemProperty -Path $regPath -Name $regName -Value $regValue
Write-Host "[OK] Clave de inicio registrada en el Registro de Windows: $regValue" -ForegroundColor Green

Write-Host "=== Instalacion completada con exito ===" -ForegroundColor Cyan

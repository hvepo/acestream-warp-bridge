# Script de instalación remota en 1 línea para cualquier PC o Portátil
$ErrorActionPreference = "Stop"
$targetDir = Join-Path $env:USERPROFILE "acestream-warp-bridge"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "    INSTALADOR RAPIDO ACESTREAM WARP BRIDGE" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

if (Get-Command git -ErrorAction SilentlyContinue) {
    if (Test-Path (Join-Path $targetDir ".git")) {
        Write-Host "[*] Repositorio detectado en $targetDir. Actualizando con git pull..." -ForegroundColor Yellow
        Push-Location $targetDir
        git pull origin main
        Pop-Location
    } else {
        Write-Host "[*] Clonando repositorio de GitHub en $targetDir..." -ForegroundColor Yellow
        git clone https://github.com/hvepo/acestream-warp-bridge.git $targetDir
    }
} else {
    Write-Host "[*] Git no instalado. Descargando codigo fuente de GitHub en ZIP..." -ForegroundColor Yellow
    $zipPath = Join-Path $env:TEMP "acestream-warp-bridge.zip"
    $extractedFolder = Join-Path $env:TEMP "acestream-warp-bridge-main"
    
    Invoke-WebRequest -Uri "https://github.com/hvepo/acestream-warp-bridge/archive/refs/heads/main.zip" -OutFile $zipPath
    if (Test-Path $extractedFolder) { Remove-Item $extractedFolder -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
    
    if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
    Move-Item $extractedFolder $targetDir -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
}

Write-Host "[*] Registrando servicios y accesos directos de escritorio..." -ForegroundColor Yellow
Push-Location $targetDir
& ".\windows\install-windows-autostart.ps1"
Pop-Location

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " [OK] INSTALACION COMPLETADA EN ESTE EQUIPO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host " Accede a tu Escritorio para encontrar:" -ForegroundColor Cyan
Write-Host "  1. 'Reiniciar AceStream (WARP).bat' (Inicia con escudo)" -ForegroundColor White
Write-Host "  2. 'Comprobar Conexion RPi.bat' (Verifica el tunel)" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

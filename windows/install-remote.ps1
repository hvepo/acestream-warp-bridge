# One-line remote installer for Windows clients (Desktop & Laptop) - WarpAcePi
$ErrorActionPreference = "Stop"
$targetDir = Join-Path $env:USERPROFILE "WarpAcePi"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "       QUICK INSTALLER - WarpAcePi" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

if (Get-Command git -ErrorAction SilentlyContinue) {
    if (Test-Path (Join-Path $targetDir ".git")) {
        Write-Host "[*] Repository detected at $targetDir. Pulling latest updates..." -ForegroundColor Yellow
        Push-Location $targetDir
        git pull origin main
        Pop-Location
    } else {
        Write-Host "[*] Cloning GitHub repository to $targetDir..." -ForegroundColor Yellow
        git clone https://github.com/hvepo/acestream-warp-bridge.git $targetDir
    }
} else {
    Write-Host "[*] Git not found. Downloading repository ZIP..." -ForegroundColor Yellow
    $zipPath = Join-Path $env:TEMP "WarpAcePi.zip"
    $extractedFolder = Join-Path $env:TEMP "acestream-warp-bridge-main"
    
    Invoke-WebRequest -Uri "https://github.com/hvepo/acestream-warp-bridge/archive/refs/heads/main.zip" -OutFile $zipPath
    if (Test-Path $extractedFolder) { Remove-Item $extractedFolder -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $env:TEMP -Force
    
    if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
    Move-Item $extractedFolder $targetDir -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
}

Write-Host "[*] Registering auto-start launcher..." -ForegroundColor Yellow
Push-Location $targetDir
& ".\windows\install-windows-autostart.ps1"
Pop-Location

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " [OK] INSTALLATION COMPLETED ON THIS DEVICE" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host " Everything stays inside repository directory: $targetDir" -ForegroundColor Cyan
Write-Host "  1. 'windows\restart_acestream_warp.bat' (Launch with shield)" -ForegroundColor White
Write-Host "  2. 'windows\check_rpi_connection.bat' (Verify tunnel)" -ForegroundColor White
Write-Host "  3. 'windows\connect_z_drive_rpi.bat' (Map Drive Z: to RPi)" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

@echo off
setlocal
title Laptop Network & Dock Optimization - WarpAcePi
cd /d "%~dp0"

echo ========================================================
echo    LAPTOP NETWORK & DOCK OPTIMIZATION - WarpAcePi
echo ========================================================
echo  Disables power-saving packet drops on USB Docks / NICs
echo  (Green Ethernet / Energy Efficient Ethernet)
echo ========================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& {
    Write-Host '[*] Scanning network adapters...' -ForegroundColor Cyan
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Loopback|Tailscale' }
    
    foreach ($a in $adapters) {
        Write-Host (' Adapter: ' + $a.Name + ' (' + $a.InterfaceDescription + ')') -ForegroundColor Yellow
        
        # Disable Green Ethernet and EEE on Realtek / USB Docks
        $props = @('Energy Efficient Ethernet', 'Energy-Efficient Ethernet', 'Green Ethernet', 'Gigabit Lite', 'Advanced EEE', 'Auto Disable Gigabit')
        foreach ($prop in $props) {
            $val = Get-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $prop -ErrorAction SilentlyContinue
            if ($val) {
                Write-Host ('   - Setting ' + $prop + ' -> Disabled') -ForegroundColor Gray
                try {
                    Set-NetAdapterAdvancedProperty -Name $a.Name -DisplayName $prop -DisplayValue 'Disabled' -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }
    
    Write-Host ''
    Write-Host '[OK] Network adapter optimization completed.' -ForegroundColor Green
}"

echo.
echo ========================================================
pause
exit /b 0

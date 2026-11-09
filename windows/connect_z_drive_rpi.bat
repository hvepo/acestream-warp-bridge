@echo off
setlocal
title Connect Drive Z to Raspberry Pi - WarpAcePi
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect_rpi_z.ps1"
echo.
pause
